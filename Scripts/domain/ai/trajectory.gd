class_name AITrajectory

# Forward-simulate a skater / puck position N steps ahead. Returns the position
# at each step (index 0 = t=dt, index N-1 = t=N*dt).
#
# Two physics models, picked via the `decel_m_s2` and `board_cor_scale`
# parameters:
#
# - Skater / generic body (decel = 0, board_cor_scale = 0): constant velocity
#   with rink CLAMPING. An unclamped lead would put a defender's anchor inside
#   the boards; a skater on the wall scrapes rather than passing through.
#
# - Puck (decel = PUCK_ICE_DECEL, board_cor_scale = PUCK_BOARD_COR_SCALE):
#   Coulomb ice friction, and board contact REFLECTS the normal velocity
#   component scaled by board_cor_scale × the puck's rigid-wall COR at that
#   normal speed (PuckRestitution.rigid_wall). The `predict_puck*` / `step_puck`
#   wrappers wire these from GameRules.

static func predict(pos: Vector3, vel: Vector3,
		steps: int, dt: float,
		decel_m_s2: float = 0.0,
		board_cor_scale: float = 0.0,
		accel: Vector3 = Vector3.ZERO,
		max_speed_m_s: float = 0.0,
		board_friction: float = 0.0,
		board_margin: float = 0.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var p: Vector3 = pos
	var v: Vector3 = vel
	if _stays_off_boards(pos, vel, steps, dt, accel, board_margin):
		for i: int in range(steps):
			if max_speed_m_s > 0.0:
				v = _capped(v, max_speed_m_s)
			p += v * dt
			if decel_m_s2 > 0.0:
				v = _iced(v, decel_m_s2, dt)
			out.append(p)
		return out
	for i: int in range(steps):
		var stepped: Transform3D = _step(
				p, v, dt, decel_m_s2, board_cor_scale, accel, max_speed_m_s, board_friction,
				board_margin)
		p = stepped.origin
		v = stepped.basis.x
		out.append(p)
	return out


# Final position after `steps` of the same integration, WITHOUT building the
# per-step array — predict_at / predict_puck_at / intercept_time only need the
# endpoint, and run on per-bot dispatch paths (pass lead, chase and body-check
# intercepts).
static func predict_final(pos: Vector3, vel: Vector3,
		steps: int, dt: float,
		decel_m_s2: float = 0.0,
		board_cor_scale: float = 0.0,
		accel: Vector3 = Vector3.ZERO,
		max_speed_m_s: float = 0.0,
		board_friction: float = 0.0,
		board_margin: float = 0.0) -> Vector3:
	var p: Vector3 = pos
	var v: Vector3 = vel
	if _stays_off_boards(pos, vel, steps, dt, accel, board_margin):
		for i: int in range(steps):
			if max_speed_m_s > 0.0:
				v = _capped(v, max_speed_m_s)
			p += v * dt
			if decel_m_s2 > 0.0:
				v = _iced(v, decel_m_s2, dt)
		return p
	for i: int in range(steps):
		var stepped: Transform3D = _step(
				p, v, dt, decel_m_s2, board_cor_scale, accel, max_speed_m_s, board_friction,
				board_margin)
		p = stepped.origin
		v = stepped.basis.x
	return p


# One integration step. Returns the stepped state packed into a Transform3D — a
# VALUE type, so no heap allocation (origin = new position, basis.x = new
# velocity).
static func _step(p: Vector3, v: Vector3, dt: float,
		decel_m_s2: float, board_cor_scale: float,
		accel: Vector3, max_speed_m_s: float,
		board_friction: float = 0.0,
		board_margin: float = 0.0) -> Transform3D:
	# Control acceleration before the position step (semi-implicit Euler): off by
	# 0.5·a·dt² per step, negligible over the pass / chase windows this serves.
	if accel != Vector3.ZERO:
		v += accel * dt
	if max_speed_m_s > 0.0:
		v = _capped(v, max_speed_m_s)
	p += v * dt

	# Board interaction. With a bounce factor, REFLECT velocity off the boards
	# (puck caroms); without, CLAMP position to the rink (skater approximation).
	# clamp_to_rink_inner honours the rounded corners, so the reflection about the
	# inward normal is radial there — never an axis-aligned rectangle, which
	# grants phantom corner ice. `board_margin` is the body's own half-extent: a
	# puck passes its radius, so it caroms when its EDGE meets the board, not its
	# centre. Skater approximations pass 0.
	var clamped_xz: Vector2 = GameRules.clamp_to_rink_inner(Vector2(p.x, p.z), board_margin)
	if board_cor_scale > 0.0:
		var outward := Vector2(p.x - clamped_xz.x, p.z - clamped_xz.y)
		if outward.length_squared() > 1e-9:
			var n := outward.normalized()
			var v_xz := Vector2(v.x, v.z)
			var vn: float = v_xz.dot(n)
			if vn > 0.0:  # moving outward into the boards
				var e: float = board_cor_scale * PuckRestitution.rigid_wall(vn)
				v_xz -= (1.0 + e) * vn * n
				# Board friction (Coulomb): bleed the along-board speed in proportion to
				# the normal impulse, so a glancing carom barely slows and a square hit
				# sheds more. Bounded by PUCK_BOARD_TANGENTIAL_MAX_LOSS: a board bends a
				# carom toward square, it never annihilates the along-board channel.
				if board_friction > 0.0:
					var v_tan := v_xz - v_xz.dot(n) * n
					var t_speed: float = v_tan.length()
					if t_speed > 1e-6:
						var drop: float = minf(
								board_friction * (1.0 + e) * vn,
								t_speed * GameRules.PUCK_BOARD_TANGENTIAL_MAX_LOSS)
						var new_t: float = maxf(t_speed - drop, 0.0)
						v_xz += v_tan * (new_t / t_speed - 1.0)
				v.x = v_xz.x
				v.z = v_xz.y
	p = Vector3(clamped_xz.x, p.y, clamped_xz.y)

	if decel_m_s2 > 0.0:
		v = _iced(v, decel_m_s2, dt)

	return Transform3D(Basis(v, Vector3.ZERO, Vector3.ZERO), p)


# Top-speed cap; 0 = uncapped. Only ever reduces an over-cap speed, so a cap
# ≥ the body's current speed never slows it (see AIPassLead).
static func _capped(v: Vector3, max_speed_m_s: float) -> Vector3:
	var v_cap_mag: float = sqrt(v.x * v.x + v.z * v.z)
	if v_cap_mag > max_speed_m_s:
		var cap_scale: float = max_speed_m_s / v_cap_mag
		v.x *= cap_scale
		v.z *= cap_scale
	return v


# Coulomb friction, clamped at zero so a slow puck stops rather than reversing.
static func _iced(v: Vector3, decel_m_s2: float, dt: float) -> Vector3:
	var v_xz_mag: float = sqrt(v.x * v.x + v.z * v.z)
	if v_xz_mag > 0.001:
		var decel_amount: float = decel_m_s2 * dt
		if v_xz_mag <= decel_amount:
			v.x = 0.0
			v.z = 0.0
		else:
			var scale: float = (v_xz_mag - decel_amount) / v_xz_mag
			v.x *= scale
			v.z *= scale
	return v


# Clearance the open-ice walk keeps from the inset boards: far above the drift
# float32 steps accumulate off the exact segment, so a walk cleared by it never
# reaches the clamp.
const _OFF_BOARDS_SLACK_M: float = 0.01


# Whether a walk can be stepped without the board branch, which is then _step
# exactly: the clamp returns an interior point unchanged. With no control
# acceleration the cap and the friction only ever scale the velocity, never turn
# it, so every step lies on the segment from `pos` to `pos + vel·T`. The inset
# rink is convex, so both ends inside it puts the whole walk inside.
static func _stays_off_boards(pos: Vector3, vel: Vector3, steps: int, dt: float,
		accel: Vector3, board_margin: float) -> bool:
	if accel != Vector3.ZERO:
		return false
	var inset: float = board_margin + _OFF_BOARDS_SLACK_M
	var start := Vector2(pos.x, pos.z)
	if GameRules.clamp_to_rink_inner(start, inset) != start:
		return false
	var span: float = dt * float(steps)
	var end := Vector2(pos.x + vel.x * span, pos.z + vel.z * span)
	return GameRules.clamp_to_rink_inner(end, inset) == end


# Position at a single lead time. Steps default to 6 — granular enough that the
# rink clamp catches mid-flight wall contact. Constant velocity + optional
# constant acceleration, no friction, no bounce; `predict_puck_at` is the puck.
static func predict_at(pos: Vector3, vel: Vector3, lead_time_s: float,
		steps: int = 6, accel: Vector3 = Vector3.ZERO,
		max_speed_m_s: float = 0.0) -> Vector3:
	if lead_time_s <= 0.0 or steps <= 0:
		return pos
	var dt: float = lead_time_s / float(steps)
	return predict_final(pos, vel, steps, dt, 0.0, 0.0, accel, max_speed_m_s)


# Solve the lead time so a constant-speed projectile fired from
# `shooter_pos` and a target moving at `target_vel` (+ optional `accel`)
# arrive at the same point. The naive `dist_to_current / speed` is wrong
# whenever the target moves radially. Two fixed-point iterations refine the
# straight-line guess against the predicted intercept point. Clamped to
# `max_lead_s` so a target fleeing faster than the projectile doesn't diverge.
# Returns 0 for a non-positive projectile speed.
static func intercept_time(shooter_pos: Vector3, target_pos: Vector3,
		target_vel: Vector3, accel: Vector3,
		proj_speed: float, max_lead_s: float, steps: int = 6,
		max_speed_m_s: float = 0.0) -> float:
	if proj_speed <= 0.0:
		return 0.0
	var t: float = clampf(
			shooter_pos.distance_to(target_pos) / proj_speed, 0.0, max_lead_s)
	for _i: int in range(2):
		var pred: Vector3 = predict_at(target_pos, target_vel, t, steps, accel, max_speed_m_s)
		t = clampf(shooter_pos.distance_to(pred) / proj_speed, 0.0, max_lead_s)
	return t


# Puck-physics forward simulation (ice friction + board reflection) — for
# wherever the AI reasons about where the puck WILL BE rather than a body.
static func predict_puck(pos: Vector3, vel: Vector3,
		steps: int, dt: float) -> Array[Vector3]:
	return predict(pos, vel, steps, dt,
			GameRules.PUCK_ICE_DECEL_M_S2,
			GameRules.PUCK_BOARD_COR_SCALE,
			Vector3.ZERO, 0.0, GameRules.PUCK_BOARD_FRICTION,
			GameRules.PUCK_COLLISION_RADIUS)


static func predict_puck_at(pos: Vector3, vel: Vector3, lead_time_s: float,
		steps: int = 6) -> Vector3:
	if lead_time_s <= 0.0 or steps <= 0:
		return pos
	var dt: float = lead_time_s / float(steps)
	return predict_final(pos, vel, steps, dt,
			GameRules.PUCK_ICE_DECEL_M_S2, GameRules.PUCK_BOARD_COR_SCALE,
			Vector3.ZERO, 0.0, GameRules.PUCK_BOARD_FRICTION,
			GameRules.PUCK_COLLISION_RADIUS)


# One deterministic puck step (ice friction + rounded-corner board reflection),
# returning position AND velocity packed into a Transform3D (origin, basis.x),
# for free-run callers that carry velocity forward tick by tick.
#
# The shared atom of the deterministic puck (docs/netcode-determinism-
# migration.md): the sim the AI reasons with IS the sim that drives the loose puck
# on the host and predicts it on the client. Grounded (XZ) puck only — gravity/loft
# and goalie/net/pipe collision live in step_puck_3d and the collision rules.
static func step_puck(pos: Vector3, vel: Vector3, dt: float) -> Transform3D:
	return _step(pos, vel, dt,
			GameRules.PUCK_ICE_DECEL_M_S2, GameRules.PUCK_BOARD_COR_SCALE,
			Vector3.ZERO, 0.0, GameRules.PUCK_BOARD_FRICTION,
			GameRules.PUCK_COLLISION_RADIUS)


# ── Board-aware reception gate ──────────────────────────────────────────────
# Where a loose puck comes into a receiver's reach, solved on the puck's REAL
# path instead of the straight ray off its current velocity.
#
# On a RIM the straight ray off the current velocity lies twice: the ARRIVAL
# TIME is measured along the chord instead of around the carom, and the
# INCOMING DIRECTION is the pre-carom one. So this walks the real friction +
# rounded-corner-carom path and reports the first point on it the blade can
# touch — the gate the blade waits at — or, with no such point, the closest
# approach, so a receiver still has somewhere honest to aim while he closes.
#
# It is a RENDEZVOUS: the reach circle rides `from_vel` down the walk, so the
# answer is where the puck's path meets the body's, not where it meets the spot
# the body occupies now. A circle drawn where a body off the line is STANDING is
# never entered, which parks the blade at the closest-approach foot, out of
# reach until the last few ticks.
#
# The body is projected at CONSTANT velocity, and only for `ride_s` — after that
# it is treated as parked, since a steering receiver's present velocity is a
# claim with a shelf life. Callers pass the passer's own lead bound
# (AICarrierPassSearch.PASS_LEAD_MAX_S), so the two halves of a pass agree on how much
# of the receiver's motion is real.
#
# Results land in statics (single-threaded AI tick): one solve serves the
# stance, the timing gate and the blade aim, with no per-call allocation on a
# per-tick path.
static var gate_point: Vector3 = Vector3.INF   # where the puck meets the reach
static var gate_velocity: Vector3 = Vector3.ZERO   # its travel there (post-carom)
static var gate_time_s: float = 0.0            # when it gets there
# The meet in the BODY's frame — the puck's offset from the body AT the meet.
# The stance and the timing gate want the world point; the BLADE AIM wants this,
# because a cursor held as an offset rides the still-skating body and lands on
# the meet as the body gets there, where one aimed at the world meet parks on
# ice the arm cannot reach yet. With `from_vel` ZERO,
# `from_pos + gate_offset == gate_point`.
static var gate_offset: Vector3 = Vector3.ZERO
# Does the path bring the puck CLOSER than it is right now? The board-aware
# "is this coming to me": never a dot product against the current velocity,
# which reads a rim heading away down the far wall as leaving when it has only a
# corner to turn first.
static var gate_closes: bool = false


# Returns true when the puck really enters the reach, false when the gate is
# only its closest approach. `reach` is the receiver's comfortable blade extension.
# `from_vel` rides the reach circle down the walk for `ride_s` (see above); ZERO
# reproduces the frozen-body solve exactly.
#
# Each walk step is tested as a SEGMENT, not a sample point: a fast feed crosses
# metres per step, and segment entry is exact at any step size (the ray/circle
# root gives the sub-step crossing), which keeps the walk coarse enough to run
# per tick per receiver. With the body riding, the segment is taken in the
# BODY's frame — both endpoints move linearly within the step — so the same
# quadratic stays exact and `u` maps straight back onto the puck's world span.
static func solve_reception_gate(puck_pos: Vector3, puck_vel: Vector3,
		from_pos: Vector3, reach: float,
		horizon_s: float, steps: int,
		from_vel: Vector3 = Vector3.ZERO, ride_s: float = INF) -> bool:
	gate_point = puck_pos
	gate_velocity = puck_vel
	gate_time_s = 0.0
	gate_closes = false
	gate_offset = Vector3(puck_pos.x - from_pos.x, 0.0, puck_pos.z - from_pos.z)
	if steps <= 0 or horizon_s <= 0.0:
		return false
	var reach_sq: float = reach * reach
	var dt: float = horizon_s / float(steps)
	var p: Vector3 = puck_pos
	var v: Vector3 = puck_vel
	# Body offset per step, and the running body position down the walk; the ride
	# stops after `ride_s`.
	var bx: float = from_pos.x
	var bz: float = from_pos.z
	var bstep_x: float = from_vel.x * dt
	var bstep_z: float = from_vel.z * dt
	var ride_steps: int = steps if is_inf(ride_s) else int(ride_s / dt)
	# Already on the blade — the gate is the puck itself.
	var ax: float = p.x - bx
	var az: float = p.z - bz
	var start_sq: float = ax * ax + az * az
	if start_sq <= reach_sq:
		gate_closes = true
		return true
	var best_sq: float = INF
	for i: int in steps:
		var stepped: Transform3D = step_puck(p, v, dt)
		var q: Vector3 = stepped.origin
		var qv: Vector3 = stepped.basis.x
		var step_bx: float = bstep_x if i < ride_steps else 0.0
		var step_bz: float = bstep_z if i < ride_steps else 0.0
		# Relative span across this step: puck offset from the body at the step's
		# start and at its end, with the body having moved one step in between.
		var fx: float = p.x - bx
		var fz: float = p.z - bz
		var dx: float = (q.x - step_bx) - p.x
		var dz: float = (q.z - step_bz) - p.z
		# The puck's own world span, which is what `u` is reported against.
		var wx: float = q.x - p.x
		var wz: float = q.z - p.z
		var aa: float = dx * dx + dz * dz
		var u_near: float = 0.0
		if aa > 1e-9:
			var b: float = fx * dx + fz * dz
			var c: float = fx * fx + fz * fz - reach_sq
			var disc: float = b * b - aa * c
			if disc >= 0.0:
				var u: float = (-b - sqrt(disc)) / aa
				if u >= 0.0 and u <= 1.0:
					gate_point = Vector3(p.x + wx * u, 0.0, p.z + wz * u)
					gate_offset = Vector3(fx + dx * u, 0.0, fz + dz * u)
					gate_velocity = v.lerp(qv, u)
					gate_time_s = (float(i) + u) * dt
					gate_closes = true
					return true
			# Closest approach on this segment, for the no-entry fallback.
			u_near = clampf(-b / aa, 0.0, 1.0)
		var nx: float = fx + dx * u_near
		var nz: float = fz + dz * u_near
		var n_sq: float = nx * nx + nz * nz
		if n_sq < best_sq:
			best_sq = n_sq
			gate_point = Vector3(p.x + wx * u_near, 0.0, p.z + wz * u_near)
			gate_offset = Vector3(nx, 0.0, nz)
			gate_velocity = v.lerp(qv, u_near)
			gate_time_s = (float(i) + u_near) * dt
		p = q
		v = qv
		bx += step_bx
		bz += step_bz
	gate_closes = best_sq < start_sq
	return false


# Puck rest height on the ice — disc bottom on y=0, cylinder half-height above (matches
# Puck.ice_height / GameRules.PUCK_START_POS.y). A puck at this height with no vertical
# speed is grounded; anything higher or moving vertically is airborne (ballistic).
const PUCK_REST_HEIGHT_M: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
# A puck this far above rest, OR with |vy| above this, integrates ballistically. Small
# enough that any real loft (launch vy ≥ ~2 m/s) is airborne and a pinned-to-ice puck
# (vy == 0) is grounded; large enough to ignore float noise on a resting puck.
const _AIRBORNE_POS_EPS_M: float = 0.001
const _AIRBORNE_VY_EPS_M_S: float = 0.05


# step_puck with a vertical (gravity) channel — the airborne extension of the puck
# atom, for loft shots, saucer passes and rebounds. Matches Puck.gd's drive:
#  - AIRBORNE (off the ice or moving vertically): ballistic — gravity on Y, board
#    reflection on XZ, and NO ice friction (no ice contact means no normal force, so a
#    puck in flight keeps its horizontal pace).
#  - LANDING: the puck lands and slides — Puck.gd zeroes linear_velocity.y and pins the
#    height the instant it's back on the ice, so there is NO vertical restitution/bounce.
#  - GROUNDED (at rest height, no vertical speed): identical to step_puck (ice friction +
#    board reflection); the height passes through unchanged.
# Returns (pos, vel) packed into a Transform3D (origin = pos, basis.x = vel) — the same
# value-type, no-alloc convention as _step / step_puck.
static func step_puck_3d(pos: Vector3, vel: Vector3, dt: float,
		rest_height: float = PUCK_REST_HEIGHT_M) -> Transform3D:
	if not is_puck_airborne(pos, vel, rest_height):
		return step_puck(pos, vel, dt)
	# Ballistic step: reuse _step (which reflects XZ off the rounded-corner boards and
	# preserves Y) with a downward gravity accel and zero ice friction.
	var stepped: Transform3D = _step(pos, vel, dt,
			0.0, GameRules.PUCK_BOARD_COR_SCALE,
			Vector3(0.0, -GameRules.GRAVITY_M_S2, 0.0), 0.0, GameRules.PUCK_BOARD_FRICTION,
			GameRules.PUCK_COLLISION_RADIUS)
	var p: Vector3 = stepped.origin
	var v: Vector3 = stepped.basis.x
	if p.y <= rest_height:
		p.y = rest_height
		v.y = 0.0
	return Transform3D(Basis(v, Vector3.ZERO, Vector3.ZERO), p)


# Whether a puck at (pos, vel) integrates ballistically (off the ice or moving
# vertically) vs slides on the ice. The branch step_puck_3d uses — exposed so callers
# that bucket airborne vs grounded (the shadow comparator) share the exact same test.
static func is_puck_airborne(pos: Vector3, vel: Vector3,
		rest_height: float = PUCK_REST_HEIGHT_M) -> bool:
	return pos.y > rest_height + _AIRBORNE_POS_EPS_M or absf(vel.y) > _AIRBORNE_VY_EPS_M_S


# Seconds until a puck is back under the blade plane for good (GameRules.
# PUCK_AIRBORNE_HEIGHT_M above rest — the gate PuckReceptionRules.
# blade_can_interact holds a grounded blade to), i.e. the descending root of
# y(t) = y0 + vy·t − ½gt² at that height. 0 for a puck that never rises above it.
static func time_until_on_blade_plane(pos: Vector3, vel: Vector3,
		rest_height: float = PUCK_REST_HEIGHT_M) -> float:
	var h: float = pos.y - rest_height - GameRules.PUCK_AIRBORNE_HEIGHT_M
	var disc: float = vel.y * vel.y + 2.0 * GameRules.GRAVITY_M_S2 * h
	if disc <= 0.0 or (h <= 0.0 and vel.y <= 0.0):
		return 0.0
	return maxf((vel.y + sqrt(disc)) / GameRules.GRAVITY_M_S2, 0.0)

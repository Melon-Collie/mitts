class_name PuckCollisionRules

# Pure math for puck interactions. The Puck node computes contact points and
# velocities from physics state, then calls these to produce the resulting
# velocity. No engine or signal dependencies here — fully unit-testable.

# Domain rule: an opponent can always attempt a poke check; teammates cannot.
static func can_poke_check(carrier_team_id: int, checker_team_id: int) -> bool:
	return carrier_team_id != checker_team_id

# Passive-blade deflection via a NORMAL/TANGENTIAL decomposition of the incoming
# velocity against the blade face. contact_normal is the blade face normal
# (unit, points against the incoming puck). Returns new horizontal velocity (no
# Y). Drives BOTH the natural too-fast-to-catch deflect and the deliberate
# redirect (hold LMB without the puck) — one model, so they always feel identical.
#
# The incoming velocity is split into the component INTO the face (normal) and the
# component ALONG the face (tangential). The normal part rebounds with restitution
# `e`; the tangential part is kept by `tangential_retain`. Two real outcomes fall
# out of this ONE model, no hand-drawn curve:
#   - a SQUARE hit (nearly all normal) off a hard puck → low e → the puck dies in
#     front (the "bobble": knocked down, not held);
#   - a GLANCING hit (mostly tangential) → the glance survives → the puck keeps its
#     pace and only its LINE changes (a true tip / redirect).
# This is why it needs no angle cap: the only way to reverse the puck is a square
# hit, and a square hard hit is killed by the low restitution — there is no fast
# carom to clamp.
#
# `e` eases from normal_restitution (soft/slow puck) toward normal_restitution_min
# (hard puck) as speed climbs to speed_ref — a hard puck deadens more head-on, so
# a squared blade smothers a slapper into a bobble instead of caroming it.
# normal_restitution_min < 0 disables the falloff (flat e). tangential_retain is
# flat: a glance keeps its pace regardless of speed (that IS the redirect).
#
# Deliberately WORLD-frame / blade-static — do NOT fold blade velocity into the
# bounce (blade-frame decomposition, sweep-adds-pace). The blade IK-chases the
# cursor every frame, so its instantaneous velocity at contact is aim noise, not
# intent: identical-looking tips would come off at different paces depending on
# where the cursor was mid-flick. Same reason reception has no cushion term.
# (Reception's relative frame uses the SKATER's velocity, which is smooth and
# deliberate — that's the distinction.)
static func deflect_velocity(
		incoming_velocity: Vector3,
		contact_normal: Vector3,
		normal_restitution: float,
		normal_restitution_min: float = -1.0,
		tangential_retain: float = 1.0,
		speed_ref: float = 0.0) -> Vector3:
	var horiz := Vector3(incoming_velocity.x, 0.0, incoming_velocity.z)
	var speed: float = horiz.length()
	if speed < 0.0001:
		return Vector3.ZERO
	var n := Vector3(contact_normal.x, 0.0, contact_normal.z)
	if n.length() < 0.0001:
		return horiz  # degenerate normal: nothing to reflect against, pass through
	n = n.normalized()
	# Into-face component. horiz·n is negative for an approaching puck (n points
	# against travel), so v_normal points into the face; flipping it by -e below
	# sends the rebounded part back out along +n.
	var v_normal: Vector3 = horiz.dot(n) * n
	var v_tangent: Vector3 = horiz - v_normal
	var hard: float = clampf(speed / speed_ref, 0.0, 1.0) if speed_ref > 0.0001 else 0.0
	var e: float = normal_restitution
	if normal_restitution_min >= 0.0:
		e = lerpf(normal_restitution, normal_restitution_min, hard)
	return v_tangent * tangential_retain - v_normal * e

# A catch the hands nearly held, in the receiver's frame (`relative_velocity`,
# puck − receiver): the face takes it as a deflect does, but a blade reaching to
# receive is cupped over the puck, so it grips the glance — `tangential_retain`
# well under a tip's — and the hands soak `pace_retain` of what is left. The
# puck leaves along the face's normal more than along the blade, slow but not
# dead. Horizontal; the caller adds the receiver's velocity and any hop.
static func bobble_velocity(
		relative_velocity: Vector3,
		face_normal: Vector3,
		normal_restitution: float,
		normal_restitution_min: float,
		speed_ref: float,
		tangential_retain: float,
		pace_retain: float) -> Vector3:
	return deflect_velocity(relative_velocity, face_normal, normal_restitution,
			normal_restitution_min, tangential_retain, speed_ref) * pace_retain

# The same decomposition in 3D, for a surface whose normal can point anywhere —
# a goalie's pad, blocker, chest or paddle (GoalieSaveRules.rebound_velocity).
# `deflect_velocity` is horizontal-only because a blade's lift is a separate,
# deliberate channel (deflect_loft_speed); a body has no such channel and its
# faces are tilted, so the vertical has to come out of the contact itself.
#
# The normal rebound is `cor_scale` × the frozen puck's rigid-wall COR at the
# NORMAL impact speed (PuckRestitution.rigid_wall), so a hard shot retains a
# smaller FRACTION while still rebounding faster in absolute terms — which is why
# hard shots make dangerous rebounds and soft ones die. The along-face channel
# answers to `friction` through reflect_with_friction, so a glance keeps its pace
# and a hard hit into a face tilted back cannot climb it at shot speed.
#
# `normal` points out of the surface, toward the puck. A separating puck is
# returned unchanged, so re-testing a puck already ejected off a face never
# re-reflects it. With `friction` 0 this is PuckGeometryCollision.reflect_off_pipe
# scaled by `cor_scale`.
static func deflect_velocity_3d(
		incoming: Vector3,
		normal: Vector3,
		cor_scale: float,
		friction: float) -> Vector3:
	if normal.length_squared() < 0.000001:
		return incoming
	var vn: float = incoming.dot(normal.normalized())
	if vn >= 0.0:
		return incoming
	return reflect_with_friction(
			incoming, normal, cor_scale * PuckRestitution.rigid_wall(-vn), friction)


# A puck off a face with Coulomb friction: the into-face channel rebounds at
# `restitution`, and the along-face channel (vertical included) sheds `friction`
# × the normal impulse (1 + e)·|vn|, never past zero. So a graze keeps nearly all
# its slide and a square-ish hit loses all of it. `normal` points out of the
# surface toward the puck; a separating puck is returned unchanged.
static func reflect_with_friction(
		incoming: Vector3,
		normal: Vector3,
		restitution: float,
		friction: float) -> Vector3:
	var n: Vector3 = normal.normalized()
	var vn: float = incoming.dot(n)
	if vn >= 0.0:
		return incoming
	var v_tan: Vector3 = incoming - vn * n
	var t_speed: float = v_tan.length()
	var keep: float = 0.0
	if t_speed > 1e-6:
		var drop: float = -friction * (1.0 + restitution) * vn
		keep = maxf(t_speed - drop, 0.0) / t_speed
	return v_tan * keep - restitution * vn * n


# Signed vertical launch speed for a deflect's redirect (fed to
# ShotMechanics.loft_y by Puck.apply_blade_deflect). Positive lifts, negative
# drives the puck down, zero keeps it flat.
#
# The loft level names the direction, as it does for a shot: FLAT and LOW tip
# DOWN, MID and HIGH tip UP. A puck already on the ice has no down to go, so a
# down tip there stays flat. The sign is the player's stated intent, never
# puck-vs-blade geometry at the contact, so two identical contacts cannot flip
# outcome on a centimetre of height.
static func deflect_loft_speed(
		elevation_level: int,
		up_speed: float,
		down_speed: float,
		puck_airborne: bool) -> float:
	if elevation_level >= ShotMechanics.ELEVATION_MID:
		return up_speed
	return -down_speed if puck_airborne else 0.0

# Analytic board-containment rescue: the velocity for a puck the engine let
# slip past the inner board boundary (trimesh facet-seam escape — the wall
# triangles are zero-thickness, so a center that crosses a facet plane can be
# depenetrated OUTWARD; see HockeyRink._add_perimeter_collision). The caller
# clamps the position back inside; this reflects the outward velocity
# component with the boards' restitution — the exact reflection the boards
# would have applied, and the exact model Trajectory.predict uses for
# predicted board bounces, so a rescued rim is indistinguishable from a
# normal carom. `outward_normal_xz` points from the boundary toward the
# escaped position. Tangential and vertical components are untouched (the
# engine owns friction on real contacts; a rescue shouldn't double-charge
# it). Inward-moving velocity is returned unchanged — the engine already
# resolved the bounce this step, only the position needed fixing.
static func board_rescue_velocity(
		velocity: Vector3,
		outward_normal_xz: Vector2,
		restitution: float) -> Vector3:
	if outward_normal_xz.length_squared() < 0.000001:
		return velocity
	var n: Vector2 = outward_normal_xz.normalized()
	var vn: float = velocity.x * n.x + velocity.z * n.y
	if vn <= 0.0:
		return velocity
	return Vector3(
			velocity.x - (1.0 + restitution) * vn * n.x,
			velocity.y,
			velocity.z - (1.0 + restitution) * vn * n.y)


# Loose puck off a skater's body (the body block), horizontal only: the body is a
# vertical cylinder and `contact_normal` is horizontal, out of it toward the puck.
# The same contact as the goalie's gear — `cor_scale` × the frozen puck's
# rigid-wall COR on the normal channel, `friction` on the slide — so a puck that
# brushes a hip keeps going and one that meets a chest dies off it.
static func body_block_velocity(
		incoming_velocity: Vector3,
		contact_normal: Vector3,
		cor_scale: float,
		friction: float) -> Vector3:
	var horiz := Vector3(incoming_velocity.x, 0.0, incoming_velocity.z)
	return deflect_velocity_3d(horiz, contact_normal, cor_scale, friction)

# Body-check strip: the puck comes loose along the hit line, but a HARD hit jars it
# nearly dead at the point of contact rather than launching it downice with the
# victim. `trickle_speed` is the soft-strip pace; as `intensity` (0..1 hit hardness)
# rises the forward carry falls toward `loose_speed`, so a squared-up check drops
# the puck at the hitter's feet — they drive through the check (reduced attacker
# restitution) and skate onto it, instead of the puck flying off with the body.
static func body_check_strip_velocity(
		hit_direction: Vector3,
		trickle_speed: float,
		loose_speed: float,
		intensity: float) -> Vector3:
	var speed: float = lerpf(trickle_speed, loose_speed, clampf(intensity, 0.0, 1.0))
	return hit_direction * speed

# Poke-check strip velocity — a stick-on-stick momentum contest. The checker's
# blade sweep plus a fraction of the carrier's (carrier_vel_blend) form the blended
# contest momentum: its heading AIMS the loose puck and its MAGNITUDE PACES it — a
# hard poke squirts the puck away fast, a soft one barely nudges it, clamped to
# [min_speed, max_speed]. When the checker's blade is near-still it's a positional
# strip with no sweep momentum, so the puck is pushed off the carrier
# (carrier_pos - checker_pos) at min_speed. If both collapse to zero the
# caller-supplied fallback_direction keeps the rule deterministic under test.
static func poke_strip_velocity(
		checker_blade_vel: Vector3,
		carrier_blade_vel: Vector3,
		carrier_pos: Vector3,
		checker_pos: Vector3,
		carrier_vel_blend: float,
		min_speed: float,
		max_speed: float,
		fallback_direction: Vector3) -> Vector3:
	var checker_horiz := Vector3(checker_blade_vel.x, 0.0, checker_blade_vel.z)
	var carrier_horiz := Vector3(carrier_blade_vel.x, 0.0, carrier_blade_vel.z)
	var strip_dir: Vector3
	var speed: float
	if checker_horiz.length() > 0.5:
		# Active poke: heading and pace both come from the blended contest momentum.
		var blended: Vector3 = checker_horiz + carrier_horiz * carrier_vel_blend
		strip_dir = blended
		speed = clampf(blended.length(), min_speed, max_speed)
	else:
		# Positional stick-on-puck: no sweep to pace it, so floor speed, pushed away.
		strip_dir = Vector3(carrier_pos.x - checker_pos.x, 0.0, carrier_pos.z - checker_pos.z)
		speed = min_speed
	strip_dir.y = 0.0
	if strip_dir.length() > 0.001:
		strip_dir = strip_dir.normalized()
	else:
		strip_dir = fallback_direction.normalized()
	return strip_dir * speed


# Contested pickup: two blades reach the same loose puck at once. Neither player
# ever gets possession off this path — the puck squirts free — but its HEADING is
# biased toward the stronger blade: the exit is the vector sum of the two blade
# momenta, so a harder/faster sweep dominates the sum and the puck goes that
# player's way (blade speed already carries the build's stick/arm lever, so no
# attribute term is needed here). Speed is that combined momentum, clamped to [min_speed, max_speed]. When
# the two blades roughly cancel (net below deadlock_threshold — a true 50/50), the
# puck instead pops out PERPENDICULAR to the line between the blade contact points
# (the "pinched seed" behavior) at deadlock_speed; the caller supplies the ± side
# and a degenerate fallback direction so the rule stays deterministic under test.
static func contested_pickup_velocity(
		blade_a_vel: Vector3, blade_b_vel: Vector3,
		blade_a_pos: Vector3, blade_b_pos: Vector3,
		min_speed: float, max_speed: float,
		deadlock_speed: float, deadlock_threshold: float,
		perp_sign: float, fallback_dir: Vector3) -> Vector3:
	var net := Vector3(blade_a_vel.x + blade_b_vel.x, 0.0, blade_a_vel.z + blade_b_vel.z)
	if net.length() > deadlock_threshold:
		return net.normalized() * clampf(net.length(), min_speed, max_speed)
	# Deadlock — blades cancel. Pop perpendicular to the blade-to-blade line.
	var along := Vector3(blade_a_pos.x - blade_b_pos.x, 0.0, blade_a_pos.z - blade_b_pos.z)
	if along.length() < 0.001:
		along = Vector3(fallback_dir.x, 0.0, fallback_dir.z)
		if along.length() < 0.001:
			along = Vector3(1.0, 0.0, 0.0)
	var perp := Vector3(-along.z, 0.0, along.x).normalized()
	return perp * perp_sign * deadlock_speed


# Upward launch speed (m/s) for a puck squeezed between two blades — the pinched
# seed escaping up off the ice. The squeeze is the blades' horizontal closing
# speed along the line between their contact points; only what exceeds
# `threshold` lifts, scaled by `gain` and capped at `max_speed`. Blades parting,
# sliding past each other, or sharing a contact point squeeze nothing and return
# 0. Adds only the vertical: the horizontal exit stays the contest's or poke's.
static func pinch_lift_speed(
		blade_a_vel: Vector3, blade_b_vel: Vector3,
		blade_a_pos: Vector3, blade_b_pos: Vector3,
		threshold: float, gain: float, max_speed: float) -> float:
	var along := Vector3(blade_a_pos.x - blade_b_pos.x, 0.0, blade_a_pos.z - blade_b_pos.z)
	if along.length_squared() < 0.000001:
		return 0.0
	return squeeze_lift_speed((blade_b_vel - blade_a_vel).dot(along.normalized()),
			threshold, gain, max_speed)


# Upward launch speed (m/s) for a puck squeezed against a blade at `closing` m/s
# — by a second blade (pinch_lift_speed) or by the ice under a hard pass driven
# into the face (a reception bobble). Only what exceeds `threshold` lifts.
static func squeeze_lift_speed(closing: float, threshold: float, gain: float,
		max_speed: float) -> float:
	return clampf((closing - threshold) * gain, 0.0, max_speed)

class_name AIPuckLane

# Whether a fired puck gets through: the lane (can a defender's stick reach the
# path before the puck passes), the saucer that flies over the sticks, the
# release contest at the blade, the pass's launch speed and its own miss. A leaf
# (GameRules, the puck rules, AIBotMechanics and AISkaterCaps only).

# ── Lane interception: closest-approach reachability model ───────────────────
# A fired puck (shot or pass) travels the straight segment from→to at
# `puck_speed`. A defender intercepts iff they can get a stick onto the
# puck's PATH at the moment the puck is there. We solve this per defender
# as a closest-approach problem between two moving points:
#
#   puck(τ)     = from + dir·speed·τ                 (τ ∈ [0, T], T = len/speed)
#   defender(τ) = D + V·τ                            (dead-reckoned momentum)
#   τ*          = argmin |puck(τ) − defender(τ)|     (closest approach, clamped)
#   miss        = |puck(τ*) − defender(τ*)|
#   reach(τ*)   = REACH + CLOSE_SPEED · max(0, τ* − REACTION)
#   block       = clamp((reach − miss) / REACH, 0, 1)
#
# Never a separable "how close to the line" × "how much flight time" product:
# that form reads a defender draped on the carrier (on the line, short flight)
# as block ≈ 0. Posed as reachability, a defender within a stick of the path
# blocks fully regardless of timing, one off it must close the gap before the
# puck passes, and faster pucks thread better for free.
#   REACH       — blade reach of a lane defender (stick length).
#   REACTION    — read delay (s) before he starts closing.
#   CLOSE_SPEED — lateral adjustment pace (LANE_LATERAL_FRACTION below).
const LANE_DEFENDER_REACH_M: float = GameRules.DEFAULT_STICK_LENGTH_M
const LANE_REACTION_DELAY_S: float = 0.08
# Fraction of top skating speed a defender covers LATERALLY sliding into a lane
# (you close a passing lane sideways, not at full straight-line speed). Per-
# defender close speed is this × the defender's real max_speed.
const LANE_LATERAL_FRACTION: float = 0.5
const LANE_DEFENDER_CLOSE_SPEED_M_S: float = LANE_LATERAL_FRACTION * GameRules.DEFAULT_SKATER_MAX_SPEED_M_S

# A defender's STICK, where he holds it: the puck is his if it passes within a
# blade's catch of where his blade can be — carried at his skating velocity, and
# moving at his hands' traverse speed (AISkaterCaps.blade_speed) from his read of
# the windup on — and only where his body can hold the stick there (the arm,
# stick and blade it holds out, AISkaterCaps.max_blade_reach). The catch is the
# pickup radius (PuckController.PICKUP_RADIUS). A forechecker reaching for the puck has his blade a metre
# nearer the passing lane than his body: read from the body alone, the first
# metres of every pass out of his reach look clean.
const LANE_BLADE_CATCH_M: float = 0.5
# His hands start on the windup, not the release: the charged pass shows itself
# for its whole wind-up (AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S) before it flies.
const LANE_BLADE_READ_DELAY_S: float = LANE_REACTION_DELAY_S \
		- AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S

# A defender's reach in the airborne stretch of a saucer: his BODY radius, no
# stick, no closing — a flip clears a grounded stick but not a torso. The
# canonical body half-width (GameRules.OFFSIDE_LINE_SLACK tracks the skater's
# collision-cylinder radius).
const LANE_DEFENDER_BODY_RADIUS_M: float = GameRules.OFFSIDE_LINE_SLACK

# The quick pass's release speed (m/s — Puck.release consumes `direction ×
# power` as linear velocity, so "power" IS m/s); longer passes are
# wrister-charged (pass_launch_speed).
const PASS_SPEED_M_S: float = GameRules.DEFAULT_QUICK_PASS_POWER_M_S

# Full-pace target CLOSING speed at reception — the puck's speed in the
# RECEIVER'S frame, which is what PuckReceptionRules judges. Under its ceilings
# (any-angle catch ≤ deflect_min 22, squared ≤ 30), 20 catches at ANY blade
# angle with margin, though it settles (AIFeedReception.receiver_settle_s); the carrier prices
# softer steps of it (PASS_PACE_FRACS). pass_launch_speed holds it across
# distance and receiver motion.
const PASS_TARGET_CLOSING_M_S: float = 20.0

# The paces a carrier prices a pass at, as fractions of the target closing
# speed — 12 / 16 / 20 m/s at full pace, from the NHL short-pass received mean
# to the stretch pass's (docs/stick-settling-plan.md). The pass EV picks: a
# softer feed spends flight time, a harder one leaves the receiver settling or
# bobbling (AIFeedReception).
const PASS_PACE_FRACS: Array[float] = [0.6, 0.8, 1.0]

# Hardest receiver-frame arrival we'll allow a pass to land at — the cap on how
# much the receiver-motion solve may SOFTEN the world launch for a receiver
# curling back, which would otherwise floor at a min-wrister floater. A bot
# receiver sets up SQUARE (_pass_receive_aim_and_steer), so its ceiling sits
# above the any-angle bar (22); 26 credits that squaring with margin below the
# squared ceiling (30) for an imperfect setup.
const PASS_RECEIVE_CEILING_M_S: float = 26.0

# Reference charged-pass speed (~mid-ramp) for callers that want one typical
# number. Not a release target — a real pass is pass_launch_speed.
const PASS_CHARGE_SPEED_M_S: float = (
		GameRules.DEFAULT_WRISTER_POWER_MIN_M_S
		+ (GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
				- GameRules.DEFAULT_WRISTER_POWER_MIN_M_S) * 0.5)

# Pass LAUNCH speed backed out of the target CLOSING speed: fire hard enough that
# the puck arrives on the tape at PASS_TARGET_CLOSING_M_S in the receiver's frame
# after shedding ice friction over the pass distance.
#
# Two corrections stack:
#   1. Friction (always): v_launch = sqrt(v_arrival² + 2·a·d), a =
#      PUCK_ICE_DECEL_M_S2.
#   2. Receiver motion (when receiver_vel/pass_dir supplied): the WORLD arrival
#      is the stationary-receiver target clamped between the two arrivals that
#      close in the receiver's frame at the target (soft) and at
#      PASS_RECEIVE_CEILING_M_S (crisp), each
#        w = (pass_dir·receiver_vel) + sqrt(max(0, closing² − |receiver_vel_⊥|²)).
#      Streaking onto a lead feed fires harder; curling back softens only to
#      what he can still catch. With no receiver_vel, w = the target.
#
# Clamped to max_launch — the passer's own max wrister, or the league default
# for opponent threat modeling.
#
# speed_scale is the difficulty pace knob (BotSkillProfile.pass_speed_scale) and
# scales the TARGET ARRIVAL pace, so everything downstream runs on the softened
# target and a lower tier's puck arrives soft and still gets there. Never apply
# it to the finished LAUNCH — that discards the receiver-motion solve, and a
# feed to a streaking receiver dies behind him. 1.0 is bit-identical to the
# unscaled solve, which the threat model (expected_pass_speed) relies on.
static func pass_launch_speed(distance: float, max_launch: float,
		speed_scale: float = 1.0,
		receiver_vel: Vector3 = Vector3.ZERO,
		pass_dir: Vector3 = Vector3.ZERO) -> float:
	var target_closing: float = PASS_TARGET_CLOSING_M_S * maxf(speed_scale, 0.01)
	var world_arrival: float = target_closing
	if pass_dir.length_squared() > 0.0001:
		var along: float = pass_dir.dot(receiver_vel)
		var perp_sq: float = maxf(0.0, receiver_vel.length_squared() - along * along)
		# The crisp bound is NOT scaled by the pace dial: it is what a receiver
		# can handle, not a choice about how hard to pass.
		var soft_arrival: float = along + sqrt(maxf(0.0,
				target_closing * target_closing - perp_sq))
		var crisp_arrival: float = along + sqrt(maxf(0.0,
				PASS_RECEIVE_CEILING_M_S * PASS_RECEIVE_CEILING_M_S - perp_sq))
		world_arrival = clampf(target_closing, soft_arrival, crisp_arrival)
		# A receiver charging the passer harder than the target could drive this
		# negative/tiny; floor at the soft-pass minimum so we still fire a real pass.
		world_arrival = maxf(world_arrival, GameRules.DEFAULT_WRISTER_POWER_MIN_M_S)
	var launch: float = sqrt(
			world_arrival * world_arrival
			+ 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * maxf(distance, 0.0))
	return clampf(launch, GameRules.DEFAULT_WRISTER_POWER_MIN_M_S, max_launch)

# ── Saucer pass ──────────────────────────────────────────────────────────────
# A bot's every pass is a charged wrister, whose LOW loft is the shot ladder's
# set angle (GameRules.DEFAULT_LOFT_TAN_LOW, ShotMechanics.shot_loft_y), so the
# lift grows with the pace. Pure kinematics under gravity:
#
#   vertical launch vy = v·sin θ                          (~1.2 m/s at 12 m/s)
#   hang time      T_hang = 2·vy / g
#   over window    [t_over, t_down] where y(t) exceeds the blade plane
#                  (GameRules.PUCK_AIRBORNE_HEIGHT_M — the same gate
#                  PuckReceptionRules.blade_can_interact uses)
#   airborne carry = v·cos θ × T_hang (no ice friction in the air)
#
# The quick pass's fixed-vy saucer (GameRules.DEFAULT_LOFT_VY_LOW_M_S) is a
# human's button; no bot fires it.
#
# Inside the over window a defender's reach is LANE_DEFENDER_BODY_RADIUS_M;
# outside it a stick intercepts normally. An airborne arrival flies over the
# receiver's grounded blade too, so the launch is capped by
# saucer_max_launch_speed. See Scripts/domain/ai/CLAUDE.md → "Pass lanes".

# Grounded slide runway the saucer must land with before the receiver's
# tape: the puck has to be back on the blade plane — landed and settled
# out of its touch-down skip — for a grounded blade to play it.
const SAUCER_LANDING_RUN_M: float = 2.0

# If the grounded lane is already this clear, never bother scoring a
# saucer variant — there's no defender worth lofting over (and the flip
# carries extra execution risk for nothing).
const SAUCER_SKIP_WHEN_LANE_CLEAR: float = 0.85

# Extra execution-miss probability a saucer adds on top of pass_miss_prob: the
# touch-down can skip or wobble off line, so the loft only wins the EV compete
# when the lane it clears is worth more than the landing risk.
const SAUCER_EXTRA_MISS_PROB: float = 0.05


# The vertical launch speed of a charged LOW release at `launch_speed`.
static func saucer_launch_vy(launch_speed: float) -> float:
	var tan_low: float = GameRules.DEFAULT_LOFT_TAN_LOW
	return launch_speed * tan_low / sqrt(1.0 + tan_low * tan_low)


# Time a saucer launched at `launch_speed` spends off the ice (launch to
# touch-down).
static func saucer_hang_time_s(launch_speed: float) -> float:
	return 2.0 * saucer_launch_vy(launch_speed) / GameRules.GRAVITY_M_S2


# Horizontal distance a saucer launched at `launch_speed` covers before
# touching back down. No ice friction while airborne.
static func saucer_airborne_distance_m(launch_speed: float) -> float:
	var tan_low: float = GameRules.DEFAULT_LOFT_TAN_LOW
	return launch_speed / sqrt(1.0 + tan_low * tan_low) * saucer_hang_time_s(launch_speed)


# The fastest launch that still LANDS with SAUCER_LANDING_RUN_M of grounded
# slide before a receiver `distance` away — the receivability bound (an
# airborne arrival flies over the tape). The carry goes as the launch squared.
# 0 for a feed no longer than the runway; below min wrister pace there is no
# legal saucer, the physical floor on saucer distance (~4 m at the 10 m/s
# soft-touch minimum).
static func saucer_max_launch_speed(distance: float) -> float:
	var flight: float = distance - SAUCER_LANDING_RUN_M
	if flight <= 0.0:
		return 0.0
	# carry = v² · 2·sin θ·cos θ / g, and sin θ·cos θ = tan θ / (1 + tan² θ).
	var tan_low: float = GameRules.DEFAULT_LOFT_TAN_LOW
	var sin_cos: float = tan_low / (1.0 + tan_low * tan_low)
	return sqrt(flight * GameRules.GRAVITY_M_S2 / (2.0 * sin_cos))


# The LAUNCH speed a pass from `shooter` to `receiver` fires at to arrive at
# the magnet pace (pass_launch_speed), capped at the league default max
# wrister — the passer's own execution uses its own max. Shared by offensive
# lane math and the threat model (opponents assumed to pass the same way).
static func expected_pass_speed(shooter: Vector3, receiver: Vector3) -> float:
	return pass_launch_speed(shooter.distance_to(receiver), GameRules.DEFAULT_WRISTER_POWER_MAX_M_S)


# ── Release contest: the pressure read, as a physical race ────────────────────
# P(the release completes clean) in [0, 1] against every nearby opponent — the
# factor the shot scorers multiply by. A physical
# contest, never a density curve: an opponent's BLADE must reach the RELEASE
# POINT (release_point_toward) while the puck is still on the blade.
#
# Per opponent, in lane_block_at's vocabulary (same reach convention, read
# delay and lateral close pace):
#
#   reach_i  = stick_i + close_speed_i × max(0, T_window − read delay)
#              — his stick, plus what he closes after a competitive read,
#              over the real windup window
#   block_i  = clamp((reach_i − d_i) / stick_i, 0, 1)
#              — one full stick inside reach ⇒ certain blade-on-puck
#   p_i      = block_i × (T_window − read delay)⁺ / T_window
#              — a blade can only disrupt the fraction of the release
#              that remains after its read: arriving as the puck leaves
#              does nothing, arriving at the start of the windup kills it
#
#   clean    = Π (1 − p_i)      — independent contests compose as a
#              product; no count normalizer, no saturation constant
#
# T_window is the bot's real decision→puck-away time
# (AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S). Directionality is
# emergent: the release point sits a carry-handle toward the target, so a man
# behind the shooter is farther from the puck. A blade planted on the release
# point still leaves read_delay / T_window clean per opponent.
static func release_contest_clean(release_pt: Vector3,
		opponents: Array[Vector3], opponent_caps: Array = []) -> float:
	var t_window: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	var contest_frac: float = maxf(0.0, t_window - LANE_REACTION_DELAY_S) \
			/ t_window
	var has_caps: bool = opponent_caps.size() == opponents.size()
	var clean: float = 1.0
	for i: int in opponents.size():
		var p: Vector3 = opponents[i]
		var stick_reach: float = LANE_DEFENDER_REACH_M
		var close_speed: float = LANE_DEFENDER_CLOSE_SPEED_M_S
		if has_caps:
			var caps: AISkaterCaps = opponent_caps[i]
			if caps != null:
				stick_reach = caps.stick_reach
				close_speed = LANE_LATERAL_FRACTION * caps.max_speed
		var reach: float = stick_reach \
				+ close_speed * maxf(0.0, t_window - LANE_REACTION_DELAY_S)
		var dx: float = p.x - release_pt.x
		var dz: float = p.z - release_pt.z
		var d_sq: float = dx * dx + dz * dz
		if d_sq >= reach * reach:
			continue
		var block: float = clampf(
				(reach - sqrt(d_sq)) / maxf(stick_reach, 0.001), 0.0, 1.0)
		clean *= 1.0 - block * contest_frac
	return clean


# The release point the contest is raced to: the puck on the blade, one
# carry-handle ahead of the body toward the target (the same handle
# distance the evasion model uses for a carried puck). Falls back to the
# body itself when the target direction is degenerate.
static func release_point_toward(shooter: Vector3, target: Vector3) -> Vector3:
	var dx: float = target.x - shooter.x
	var dz: float = target.z - shooter.z
	var len_sq: float = dx * dx + dz * dz
	if len_sq < 0.0001:
		return shooter
	var inv: float = AIBotMechanics.EVADE_CARRY_HANDLE_M / sqrt(len_sq)
	return Vector3(shooter.x + dx * inv, 0.0, shooter.z + dz * inv)


# Unclamped closest-approach time τ* that minimises the distance between
# the fired puck and a dead-reckoned defender. `pvx/pvz` are the puck's
# velocity components (dir × speed); `vx/vz` the defender's. May be < 0
# (closest approach already behind us — defender drifting off) or
# > seg_time (closest approach only AFTER the puck reaches the receiver —
# the defender is trailing the play and never intercepts it in flight).
# Callers clamp the low end to 0 and skip the high end. Pure float math
# (no allocation) — safe per defender on the lane hot path.
static func _lane_closest_approach_t(
		fx: float, fz: float, pvx: float, pvz: float,
		px: float, pz: float, vx: float, vz: float) -> float:
	# W(τ) = (from − D) + (puck_vel − defender_vel)·τ ; minimise |W(τ)|.
	var w0x: float = fx - px
	var w0z: float = fz - pz
	var wdx: float = pvx - vx
	var wdz: float = pvz - vz
	var wd_sq: float = wdx * wdx + wdz * wdz
	if wd_sq < 0.0001:
		return 0.0  # no relative motion — closest approach is now
	return -(w0x * wdx + w0z * wdz) / wd_sq


# Miss distance: how far the puck passes from the dead-reckoned defender
# at approach time `t`. Pure float math — shared by the flat-pass and
# saucer (body-only) block calculations so the two agree on the geometry.
static func _lane_miss_at(
		fx: float, fz: float, pvx: float, pvz: float, t: float,
		px: float, pz: float, vx: float, vz: float) -> float:
	var wx: float = (fx - px) + (pvx - vx) * t
	var wz: float = (fz - pz) + (pvz - vz) * t
	return sqrt(wx * wx + wz * wz)


# Flat per-defender block strength [0, 1] at a given approach time `t`:
# reach = stick + closing they can do after the reaction delay; block is
# how far the lane penetrates that reach, normalised by a stick length
# (one full stick inside reach ⇒ certain block). Pure float math.
#
# `read_delay` is when his closing starts, from the release: the default read
# delay, or less for a blade that has been moving through the windup.
static func lane_block_at(
		fx: float, fz: float, pvx: float, pvz: float, t: float,
		px: float, pz: float, vx: float, vz: float,
		stick_reach: float = LANE_DEFENDER_REACH_M,
		close_speed: float = LANE_DEFENDER_CLOSE_SPEED_M_S,
		read_delay: float = LANE_REACTION_DELAY_S) -> float:
	var miss: float = _lane_miss_at(fx, fz, pvx, pvz, t, px, pz, vx, vz)
	# Normalised by his own stick, so "one full stick inside reach" scales with
	# the defender.
	var reach: float = stick_reach + close_speed * maxf(0.0, t - read_delay)
	return clampf((reach - miss) / stick_reach, 0.0, 1.0)


# Brake-and-clog reachability block [0, 1] for one defender: the best lane point
# he can skate to and STOP on before the puck crosses it. The ballistic term
# (lane_block_at) lets a fast defender COAST through the lane and out the far
# side; this asks the guided-interceptor question instead. lane_clear takes the
# max of the two, so it only ever ADDS block.
#
# Closed form: maximise block(u) = (stick + close·(u/speed − reaction) − |X(u)−D|)
# over the lane arc-coord u, where X(u) is the point u metres along the lane and
# the puck reaches it at u/speed. With a = the defender's along-lane coord and
# b = his perpendicular distance, |X(u)−D| = √((u−a)²+b²); setting d/du = 0 gives
# the interior optimum (u−a) = k·b/√(1−k²), k = close/speed. Evaluated there and
# at the perpendicular foot (u = a, robust to the reaction-delay kink), best wins.
# Returns (block, u): the block and the lane arc-coord he plants on for it. Pure
# float math, allocation-free.
static func _lane_brake_block(
		fx: float, fz: float, dirx: float, dirz: float, seg_len: float,
		speed: float, px: float, pz: float,
		stick_reach: float, close_speed: float,
		read_delay: float = LANE_REACTION_DELAY_S) -> Vector2:
	var rx: float = px - fx
	var rz: float = pz - fz
	var a: float = rx * dirx + rz * dirz             # along-lane coord of the defender
	var perp_x: float = rx - a * dirx
	var perp_z: float = rz - a * dirz
	var b: float = sqrt(perp_x * perp_x + perp_z * perp_z)   # perpendicular distance
	var k: float = close_speed / speed
	var u_opt: float = clampf(
			seg_len if k >= 1.0 else a + k * b / sqrt(1.0 - k * k), 0.0, seg_len)
	var u_foot: float = clampf(a, 0.0, seg_len)
	var blk_opt: float = _brake_block_at(u_opt, a, b, speed, stick_reach, close_speed,
			read_delay)
	var blk_foot: float = _brake_block_at(u_foot, a, b, speed, stick_reach, close_speed,
			read_delay)
	if blk_opt >= blk_foot:
		return Vector2(blk_opt, u_opt)
	return Vector2(blk_foot, u_foot)


# One defender's block on an `accurate` lane (see lane_clear) and where he makes
# it: the ballistic read at his closest approach, or the guided interceptor's
# planted point when that blocks harder. Returns (block, lane arc-coord of the
# pick), so lane_clear's probability and lane_loss_point's place come from one
# read of the same defender, closing from `read_delay` (< 0: already reading).
static func _accurate_block(fx: float, fz: float, dirx: float, dirz: float,
		line_len: float, eff_speed: float, px: float, pz: float,
		vx: float, vz: float, stick_reach: float, close_speed: float,
		read_delay: float = LANE_REACTION_DELAY_S) -> Vector2:
	var pvx: float = dirx * eff_speed
	var pvz: float = dirz * eff_speed
	var block: float = 0.0
	var u: float = 0.0
	# Ballistic (coasting) block — 0 for a defender whose closest approach is
	# only AFTER the puck reaches the receiver (trailing the play).
	var t_raw: float = _lane_closest_approach_t(fx, fz, pvx, pvz, px, pz, vx, vz)
	if t_raw <= line_len / eff_speed:
		var t: float = maxf(t_raw, 0.0)
		block = lane_block_at(fx, fz, pvx, pvz, t, px, pz, vx, vz,
				stick_reach, close_speed, read_delay)
		u = eff_speed * t
	# Guided-interceptor floor: he can brake and clog a reachable crossing
	# instead of coasting through it (only ADDS block).
	var brake: Vector2 = _lane_brake_block(fx, fz, dirx, dirz, line_len, eff_speed,
			px, pz, stick_reach, close_speed, read_delay)
	if brake.x > block:
		return brake
	return Vector2(block, u)


# Block strength if the defender aims to occupy lane arc-coord `u` — reach at the
# puck's arrival time there, minus the distance he must cover to it. Shared by the
# two candidate points _lane_brake_block evaluates.
static func _brake_block_at(u: float, a: float, b: float, speed: float,
		stick_reach: float, close_speed: float,
		read_delay: float = LANE_REACTION_DELAY_S) -> float:
	var t_x: float = u / speed
	var reach: float = stick_reach + close_speed * maxf(0.0, t_x - read_delay)
	var du: float = u - a
	var gap: float = sqrt(du * du + b * b)
	return clampf((reach - gap) / stick_reach, 0.0, 1.0)


# Time for a puck launched at `v0` to slide `dist` against ice friction (Coulomb
# decel PUCK_ICE_DECEL_M_S2): the first root of dist = v0·T − ½·a·T². Falls
# back to frictionless if the puck would stop before arriving.
static func _friction_traverse_time(dist: float, v0: float) -> float:
	var a: float = GameRules.PUCK_ICE_DECEL_M_S2
	if a <= 0.0:
		return dist / v0
	var disc: float = v0 * v0 - 2.0 * a * dist
	if disc <= 0.0:
		return dist / v0
	return (v0 - sqrt(disc)) / a


# One defender's blade on an `accurate` lane, as _accurate_block reads his body:
# (block, lane arc-coord of the pick) for the blade (bx, bz), where his body could
# hold the stick there — within `hold_reach` (AISkaterCaps.max_blade_reach) of it
# as it closes (see LANE_BLADE_CATCH_M).
static func _blade_block(fx: float, fz: float, dirx: float, dirz: float,
		line_len: float, eff_speed: float, bx: float, bz: float, px: float, pz: float,
		vx: float, vz: float, hold_reach: float, close_speed: float,
		blade_speed: float) -> Vector2:
	var pvx: float = dirx * eff_speed
	var pvz: float = dirz * eff_speed
	var best := Vector2.ZERO
	var t_raw: float = _lane_closest_approach_t(fx, fz, pvx, pvz, bx, bz, vx, vz)
	if t_raw <= line_len / eff_speed:
		var t: float = maxf(t_raw, 0.0)
		var block: float = lane_block_at(fx, fz, pvx, pvz, t, bx, bz, vx, vz,
				LANE_BLADE_CATCH_M, blade_speed, LANE_BLADE_READ_DELAY_S)
		if block > 0.0 and lane_block_at(fx, fz, pvx, pvz, t, px, pz, vx, vz,
				hold_reach, close_speed) > 0.0:
			best = Vector2(block, eff_speed * t)
	var guided: Vector2 = _lane_brake_block(fx, fz, dirx, dirz, line_len, eff_speed,
			bx, bz, LANE_BLADE_CATCH_M, blade_speed, LANE_BLADE_READ_DELAY_S)
	if guided.x > best.x and lane_block_at(fx, fz, pvx, pvz, guided.y / eff_speed,
			px, pz, vx, vz, hold_reach, close_speed) > 0.0:
		best = guided
	return best


# Lane-clear factor in [0, 1] for a FIRED puck (shot or pass) — the
# closest-approach reachability model (see the doc-block above the lane
# constants), not the carry-path AICarrySpace.carry_lane_clearance.
# `puck_speed_m_s` is the speed the puck travels the segment. `opponent_vels`
# is an OPTIONAL array index-matched to `opponents`; missing entries read as
# stationary.
#
# `accurate` (the carrier's own pass EV opts in) composes three refinements
# over the default `1 − max(block)` constant-speed ballistic model:
#   1. Guided interceptor (_lane_brake_block, max'd per defender).
#   2. Independent-defender SURVIVAL (product, not max) — the puck must beat
#      EVERY defender, so two on different segments compound; two stacked on
#      one spot are mildly over-counted, which errs conservative.
#   3. Friction timing — the far end of a long lane gives defenders the extra
#      time they really get.
#   4. With `opponent_blades` (index-matched), each defender's stick where he
#      holds it (_blade_block, max'd per defender).
static func lane_clear(from: Vector3, to: Vector3, opponents: Array[Vector3],
		puck_speed_m_s: float, opponent_vels: Array[Vector3] = [],
		opponent_caps: Array = [], accurate: bool = false,
		opponent_blades: Array[Vector3] = []) -> float:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	var line_len_sq: float = dx * dx + dz * dz
	if line_len_sq < 0.01:
		return 1.0  # degenerate (overlapping endpoints)
	var line_len: float = sqrt(line_len_sq)
	var speed: float = maxf(puck_speed_m_s, 1.0)
	# Friction-aware average speed over the real traversal (accurate only).
	var eff_speed: float = speed
	if accurate:
		eff_speed = line_len / _friction_traverse_time(line_len, speed)
	var seg_time: float = line_len / eff_speed
	var inv_len: float = 1.0 / line_len
	var pvx: float = dx * inv_len * eff_speed
	var pvz: float = dz * inv_len * eff_speed
	var dirx: float = dx * inv_len
	var dirz: float = dz * inv_len
	var vel_count: int = opponent_vels.size()
	var has_caps: bool = opponent_caps.size() == opponents.size()
	var has_blades: bool = opponent_blades.size() == opponents.size()
	var max_block: float = 0.0
	var survival: float = 1.0   # accurate: independent-defender survival product
	for i: int in opponents.size():
		var p: Vector3 = opponents[i]
		var vx: float = 0.0
		var vz: float = 0.0
		if i < vel_count:
			vx = opponent_vels[i].x
			vz = opponent_vels[i].z
		# This defender's real stick reach, lateral close speed and hands.
		var stick_reach: float = LANE_DEFENDER_REACH_M
		var close_speed: float = LANE_DEFENDER_CLOSE_SPEED_M_S
		var blade_speed: float = AISkaterCaps.LEAGUE_BLADE_SPEED_M_S
		var hold_reach: float = AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
		if has_caps:
			var caps: AISkaterCaps = opponent_caps[i]
			if caps != null:
				stick_reach = caps.stick_reach
				close_speed = LANE_LATERAL_FRACTION * caps.max_speed
				blade_speed = caps.blade_speed
				hold_reach = caps.max_blade_reach
		if accurate:
			# Survival: the puck must beat this defender too.
			var lane_block: float = _accurate_block(from.x, from.z, dirx, dirz, line_len,
					eff_speed, p.x, p.z, vx, vz, stick_reach, close_speed).x
			if has_blades:
				var b: Vector3 = opponent_blades[i]
				lane_block = maxf(lane_block, _blade_block(from.x, from.z, dirx, dirz, line_len,
						eff_speed, b.x, b.z, p.x, p.z, vx, vz, hold_reach, close_speed,
						blade_speed).x)
			survival *= 1.0 - lane_block
			if survival <= 0.0:
				break
			continue
		# Ballistic (coasting) block — 0 for a defender whose closest approach is
		# only AFTER the puck reaches the receiver (trailing the play).
		var block: float = 0.0
		var t_raw: float = _lane_closest_approach_t(
				from.x, from.z, pvx, pvz, p.x, p.z, vx, vz)
		if t_raw <= seg_time:
			block = lane_block_at(from.x, from.z, pvx, pvz, maxf(t_raw, 0.0),
					p.x, p.z, vx, vz, stick_reach, close_speed)
		if block > max_block:
			max_block = block
			if max_block >= 1.0:
				break
	if accurate:
		return clampf(survival, 0.0, 1.0)
	return clampf(1.0 - max_block, 0.0, 1.0)


# Lane-clear for a SAUCER (LOW-loft) pass fired at `puck_speed_m_s`: in the air
# (the over window, see the saucer doc-block) a defender blocks with his BODY
# radius, on the release with his stick, and from the touch-down on the rest of
# the lane is the accurate flat lane_clear's. Every defender must be beaten.
static func lane_clear_saucer(from: Vector3, to: Vector3, opponents: Array[Vector3],
		puck_speed_m_s: float, opponent_vels: Array[Vector3] = [],
		opponent_caps: Array = []) -> float:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	var line_len_sq: float = dx * dx + dz * dz
	if line_len_sq < 0.01:
		return 1.0  # degenerate (overlapping endpoints)
	var line_len: float = sqrt(line_len_sq)
	var speed: float = maxf(puck_speed_m_s, 1.0)
	var inv_len: float = 1.0 / line_len
	var dirx: float = dx * inv_len
	var dirz: float = dz * inv_len
	var pvx: float = dirx * speed
	var pvz: float = dirz * speed
	var vel_count: int = opponent_vels.size()
	var has_caps: bool = opponent_caps.size() == opponents.size()
	# Over window: y(t) = vy·t − ½·g·t² above the blade plane between its roots.
	var vy: float = saucer_launch_vy(speed)
	var root: float = sqrt(maxf(0.0,
			vy * vy - 2.0 * GameRules.GRAVITY_M_S2 * GameRules.PUCK_AIRBORNE_HEIGHT_M))
	var t_over: float = (vy - root) / GameRules.GRAVITY_M_S2
	var t_down: float = (vy + root) / GameRules.GRAVITY_M_S2
	# From the touch-down on it is a flat pass on the ice for the rest of the lane.
	var flown: float = speed * t_down
	var landed_len: float = line_len - flown
	var land_x: float = from.x + dirx * flown
	var land_z: float = from.z + dirz * flown
	var landed_speed: float = landed_len / _friction_traverse_time(landed_len, speed) \
			if landed_len > 0.01 else speed
	var survival: float = 1.0
	for i: int in opponents.size():
		var p: Vector3 = opponents[i]
		var v: Vector3 = opponent_vels[i] if i < vel_count else Vector3.ZERO
		var stick_reach: float = LANE_DEFENDER_REACH_M
		var close_speed: float = LANE_DEFENDER_CLOSE_SPEED_M_S
		if has_caps:
			var caps: AISkaterCaps = opponent_caps[i]
			if caps != null:
				stick_reach = caps.stick_reach
				close_speed = LANE_LATERAL_FRACTION * caps.max_speed
		var t_raw: float = _lane_closest_approach_t(
				from.x, from.z, pvx, pvz, p.x, p.z, v.x, v.z)
		var block: float = 0.0
		if t_raw >= t_over and t_raw <= t_down:
			# It flies over him: only his body blocks it in the air.
			var miss: float = _lane_miss_at(
					from.x, from.z, pvx, pvz, t_raw, p.x, p.z, v.x, v.z)
			block = clampf(
					(LANE_DEFENDER_BODY_RADIUS_M - miss) / LANE_DEFENDER_BODY_RADIUS_M,
					0.0, 1.0)
		elif t_raw < t_over:   # still on the blade: a stick stuffs the flip
			block = lane_block_at(from.x, from.z, pvx, pvz, maxf(t_raw, 0.0),
					p.x, p.z, v.x, v.z, stick_reach, close_speed)
		# Landed, it is the accurate flat lane from where he is then, read that far
		# on: the man it flew over still plays it sliding off behind him.
		if landed_len > 0.01:
			block = maxf(block, _accurate_block(land_x, land_z, dirx, dirz,
					landed_len, landed_speed, p.x + v.x * t_down, p.z + v.z * t_down,
					v.x, v.z, stick_reach, close_speed, LANE_REACTION_DELAY_S - t_down).x)
		survival *= 1.0 - block
		if survival <= 0.0:
			return 0.0
	return clampf(survival, 0.0, 1.0)


# Interceptor point for a fired-puck lane under lane_clear's ACCURATE model:
# where on the puck's path its strongest-blocking defender picks it — the
# coasting man's closest approach, or the spot a guided interceptor plants on.
# Vector3.INF exactly when no defender blocks (lane_clear(accurate) == 1.0), so
# a lane with any interception risk always has a place to price it at.
#
# The loss location for the pass turnover cost (AICarrierField.turnover_cost).
static func lane_loss_point(from: Vector3, to: Vector3,
		opponents: Array[Vector3], puck_speed_m_s: float,
		opponent_vels: Array[Vector3] = [],
		opponent_caps: Array = [], opponent_blades: Array[Vector3] = []) -> Vector3:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	var line_len_sq: float = dx * dx + dz * dz
	if line_len_sq < 0.01:
		return Vector3.INF
	var line_len: float = sqrt(line_len_sq)
	var speed: float = maxf(puck_speed_m_s, 1.0)
	var eff_speed: float = line_len / _friction_traverse_time(line_len, speed)
	var dirx: float = dx / line_len
	var dirz: float = dz / line_len
	var vel_count: int = opponent_vels.size()
	var has_caps: bool = opponent_caps.size() == opponents.size()
	var has_blades: bool = opponent_blades.size() == opponents.size()
	var max_block: float = 0.0
	var best_u: float = 0.0
	for i: int in opponents.size():
		var p: Vector3 = opponents[i]
		var vx: float = 0.0
		var vz: float = 0.0
		if i < vel_count:
			vx = opponent_vels[i].x
			vz = opponent_vels[i].z
		var stick_reach: float = LANE_DEFENDER_REACH_M
		var close_speed: float = LANE_DEFENDER_CLOSE_SPEED_M_S
		var blade_speed: float = AISkaterCaps.LEAGUE_BLADE_SPEED_M_S
		var hold_reach: float = AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
		if has_caps:
			var caps: AISkaterCaps = opponent_caps[i]
			if caps != null:
				stick_reach = caps.stick_reach
				close_speed = LANE_LATERAL_FRACTION * caps.max_speed
				blade_speed = caps.blade_speed
				hold_reach = caps.max_blade_reach
		var read: Vector2 = _accurate_block(from.x, from.z, dirx, dirz, line_len,
				eff_speed, p.x, p.z, vx, vz, stick_reach, close_speed)
		if has_blades:
			var b: Vector3 = opponent_blades[i]
			var blade_read: Vector2 = _blade_block(from.x, from.z, dirx, dirz, line_len,
					eff_speed, b.x, b.z, p.x, p.z, vx, vz, hold_reach, close_speed,
					blade_speed)
			if blade_read.x > read.x:
				read = blade_read
		if read.x > max_block:
			max_block = read.x
			best_u = read.y
	if max_block <= 0.0:
		return Vector3.INF
	return Vector3(from.x + dirx * best_u, 0.0, from.z + dirz * best_u)


# ── Pass execution risk ──────────────────────────────────────────────────────
# The lane model prices INTERCEPTION only; without an execution term a
# clear-lane backpass deep in our own zone scores as risk-free. pass_miss_prob
# is the residual chance a lane-clear pass still fails, and the puck then ends
# up loose PASS_MISS_OVERSHOOT_M past the receiver along the pass line. Fed to
# AICarrierField.turnover_cost, that risk self-localizes like interception
# risk: least in the OZ, the opponent's chance in front of our net for a DZ
# backpass.
#
# The bot solves its launch to ARRIVE catchable (pass_launch_speed), so
# reception difficulty is designed out of its own passes; the residual is an
# irreducible floor (PASS_MISS_BASE_PROB — a bounce, a skate) plus HAND error
# (BotSkillProfile.pass_aim_error_rad) over the pass distance.
const PASS_MISS_BASE_PROB: float = 0.04
const PASS_MISS_OVERSHOOT_M: float = 3.0


# Per-pass execution-miss probability (see the block above). `aim_error_rad` is
# the passer's release-direction error — 0 for the perfect baseline and the
# cross-player threat model (we don't know another player's hand), collapsing to
# the base floor. `catch_radius` is how far off the tape the receiver can still
# corral the feed (its handle reach). Uniform-error model: the base floor
# compounded with the fraction of the ±(aim_error × distance) lateral spread that
# lands outside the catch envelope.
static func pass_miss_prob(distance: float, aim_error_rad: float,
		catch_radius: float = AIBotMechanics.EVADE_CARRY_HANDLE_M,
		receiver_uncertainty_m: float = 0.0) -> float:
	# Two lateral catch-point offsets (m) against the receiver's catch
	# envelope, added (the worst case is they align): the passer's aim spread
	# and the receiver's heading uncertainty (receiver_heading_uncertainty_m).
	var spread: float = maxf(aim_error_rad, 0.0) * maxf(distance, 0.0) \
			+ maxf(receiver_uncertainty_m, 0.0)
	var execution: float = 0.0
	if spread > 0.0001:
		execution = clampf(
				(spread - catch_radius) / spread, 0.0, 1.0)
	return clampf(
			1.0 - (1.0 - PASS_MISS_BASE_PROB) * (1.0 - execution), 0.0, 1.0)


# Catch-point uncertainty (m) a TURNING receiver adds to a pass. The lead aims
# down his current heading (AIPassLead), but a receiver turning at `omega`
# rad/s curves off that tangent: a constant-radius arc deviates from it by
# R·(1 − cos θ), R = v/ω, θ = ω·t over flight time `t`. ~0 for a receiver
# holding a line. θ is capped at π, past which the deviation stops growing
# monotonically.
static func receiver_heading_uncertainty_m(
		receiver_speed: float, omega: float, flight_t: float) -> float:
	var w: float = absf(omega)
	if w < 0.0001 or receiver_speed <= 0.0 or flight_t <= 0.0:
		return 0.0
	var theta: float = minf(w * flight_t, PI)
	var radius: float = receiver_speed / w
	return radius * (1.0 - cos(theta))


# Loss point for the execution-miss mode of a pass: the puck sails past
# the receiver and dies PASS_MISS_OVERSHOOT_M beyond them on the pass
# line. Degenerate (overlapping endpoints) falls back to the receiver.
static func pass_miss_loss_point(from: Vector3, receiver: Vector3) -> Vector3:
	var dx: float = receiver.x - from.x
	var dz: float = receiver.z - from.z
	var len_sq: float = dx * dx + dz * dz
	if len_sq < 0.0001:
		return receiver
	var inv: float = PASS_MISS_OVERSHOOT_M / sqrt(len_sq)
	return Vector3(receiver.x + dx * inv, 0.0, receiver.z + dz * inv)

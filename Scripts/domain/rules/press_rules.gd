class_name PressRules
extends RefCounted

# Two bodies pressed together: who gives ground (docs/net-front-battles-plan.md).
# A pressed pair moves as one body along the contact normal, driven by both
# bodies' strides and held by both bodies' edges, so each body's movement step
# lays the pair's acceleration along the normal in place of its own. Every input
# is replicated state (mass, posture, brake, intent, facing, stagger) and the
# rules are antisymmetric in the pair, so both bodies, on every machine and
# through reconcile, lay the same acceleration. All vectors are XZ; `n` points
# from the body asking toward the other.

# The stop's edges in the stance over upright: the wider, lower base takes more
# edge before it slides. Sized for the ladder across builds (mass × thrust
# against mass × stop × this, where both rates fall with weight): an equal man's
# drive held, 235 lb creeping 170 lb, 170 lb never moving 235 lb
# (test_press.gd).
const STANCE_ANCHOR: float = 1.3
# The stride an uncommitted body drives into a man with, as a share: skating
# into him without putting the body into it slides off him, as an uncommitted
# bump transfers this share (Skater.hit_passive_transfer_mult).
const PASSIVE_DRIVE_SHARE: float = 0.3
# Discs this close count as touching: the resolver separates every overlap, so a
# pair pushing into each other sits just apart at the tick's start.
const CONTACT_SLACK_M: float = 0.02
# Below this pair speed (m/s) along the normal the pair is at rest, and the
# edges hold whatever they can.
const REST_SPEED: float = 0.01


# Whether two bodies `gap` apart (edge to edge, m) touch, for a reader that
# places the other body only to within `timing_s` of the instant it reads him
# at, while he moves at `speed_along` (m/s) along the line between them: the
# slack, plus that much of his travel either way. A reader with the bodies
# themselves passes 0.
static func touching(gap: float, speed_along: float, timing_s: float) -> bool:
	return gap < CONTACT_SLACK_M + absf(speed_along) * timing_s


# The acceleration (m/s²) body X's legs push along `n` with: its stride in its
# posture (the commit's stride penalty is the cost of skating loaded at speed,
# lifted in contact, where the commit is the drive), the uncommitted share
# otherwise, the stride's direction scale against his facing, the stagger's
# thrust penalty, and the stride's power limit past its knee at the pair's
# speed `u` along n. Signed: negative pushes away. Braking and planted bodies
# drive nothing. `thrust` is the build's base thrust (the config's is transient).
static func drive(cfg: SkaterMovementRules.MovementConfig, thrust: float, posture: int,
		braking: bool, planted: bool, stagger_thrust: float, facing: Vector2,
		intent: Vector2, n: Vector2, u: float) -> float:
	if braking or planted or intent.length_squared() <= cfg.move_deadzone * cfg.move_deadzone:
		return 0.0
	var stride: float = 1.0
	if posture == SkaterMovementRules.Posture.STANCE:
		stride = cfg.stance_stride_mult * PASSIVE_DRIVE_SHARE
	elif posture == SkaterMovementRules.Posture.UPRIGHT:
		stride = PASSIVE_DRIVE_SHARE
	var along: float = minf(intent.length(), 1.0) * intent.normalized().dot(n)
	var power: float = 1.0
	if along * u > 0.0 and absf(u) > cfg.power_knee_speed:
		power = cfg.power_knee_speed / absf(u)
	return thrust * stride * stagger_thrust * power \
			* SkaterMovementRules.direction_thrust_scale(cfg, facing, intent) * along


# The most (m/s²) body X's edges resist the pair's motion along `n` with: the
# stop's edges braking (the blades turned across, so from any side), anchored by
# the stance; else his edges across his blades (|sin θ| of `n` off his facing)
# at his turning grip in his posture, and the glide's friction at the pair's
# speed `u`. The stagger's grip penalty takes from the edges.
static func hold(cfg: SkaterMovementRules.MovementConfig, posture: int, braking: bool,
		planted: bool, stagger_grip: float, facing: Vector2, n: Vector2, u: float) -> float:
	if braking or planted:
		var anchor: float = STANCE_ANCHOR if posture == SkaterMovementRules.Posture.STANCE else 1.0
		return cfg.stop_decel * anchor * stagger_grip
	var posture_grip: float = 1.0
	if posture == SkaterMovementRules.Posture.STANCE:
		posture_grip = cfg.stance_grip_mult
	elif posture == SkaterMovementRules.Posture.COMMIT:
		posture_grip = cfg.commit_grip_mult
	return cfg.turn_accel * cfg.lateral_grip * posture_grip * stagger_grip * absf(facing.cross(n)) \
			+ cfg.friction + cfg.friction_drag * absf(u)


# Whether the pair is pressed: their drives into each other (A's along n, B's
# along −n) add up to a push. Contact only pushes, so a pair neither body drives
# into is not held together.
static func pressing(drive_a: float, drive_b: float) -> bool:
	return drive_a + drive_b > 0.0


# The pair's acceleration (m/s²) along n, from A toward B, for a pair moving at
# `u` (m/s) along it. The drives' net force against both bodies' edges, which
# oppose the motion (or, at rest, hold up to their sum and never push back):
# edges stop the pair rather than reverse it inside a tick. Antisymmetric:
# swapping A and B with u negated negates it.
static func pair_accel(mass_a: float, drive_a: float, hold_a: float,
		mass_b: float, drive_b: float, hold_b: float, u: float, delta: float) -> float:
	var f: float = mass_a * drive_a - mass_b * drive_b
	var h: float = mass_a * hold_a + mass_b * hold_b
	var m: float = maxf(mass_a + mass_b, 0.001)
	if absf(u) <= REST_SPEED:
		if absf(f) <= h:
			return -u / delta
		return (f - signf(f) * h) / m
	var a: float = (f - signf(u) * h) / m
	if signf(u + a * delta) != signf(u) and absf(f) <= h:
		return -u / delta
	return a

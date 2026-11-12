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

# A press is a battle a body is in or out of: holding the check button (the
# COMMIT posture) engages it, and only an engaged body pushes with his whole
# stride or holds his ground. The loaded stance (Shift) is nothing here.

# An engaged body braking has set his edges against the push: the stop's own
# edges over a plain stop's. Sized for the ladder across builds (mass × thrust
# against mass × stop × this, where both rates fall with weight): an equal man's
# drive held, 235 lb creeping 170 lb, 170 lb never moving 235 lb (test_press.gd).
const SET_ANCHOR: float = 1.3
# What edges that have broken loose hold of what set ones do, the way sliding
# friction is under static: a set man holds an equal drive, a sliding one is
# moved by it until he pushes back.
const LOOSE_SHARE: float = 0.6
# The pair speed (m/s) up to which edges are still set, and by which they are
# loose.
const SET_SPEED: float = 0.15
const LOOSE_SPEED: float = 0.45
# The stride an unengaged body drives into a man with, as a share: skating into
# him without putting the body into it slides off him, as an uncommitted bump
# transfers this share (Skater.hit_passive_transfer_mult).
const PASSIVE_DRIVE_SHARE: float = 0.3
# What an unengaged body's brake holds of a plain stop: a stop is not a stand.
const PASSIVE_BRAKE_SHARE: float = 0.3
# How hard a body pushes side-on to the man, over chest-on: the legs drive the
# way he faces.
const SIDE_ON_SHARE: float = 0.4
# A press moves a man no faster than this (m/s), a walking pace: the drive
# fades to nothing as the pair reaches it.
const MAX_SPEED_M_S: float = 1.5
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


# The acceleration (m/s²) body X's legs push along `n` with: his whole stride
# engaged, the unengaged share otherwise, by how squarely he faces the man, the
# stagger's thrust penalty, and fading out as the pair nears a walking pace `u`
# along n. Signed: negative pushes away. Braking and planted bodies drive
# nothing. `thrust` is the build's base thrust (the config's is transient).
static func drive(cfg: SkaterMovementRules.MovementConfig, thrust: float, posture: int,
		braking: bool, planted: bool, stagger_thrust: float, facing: Vector2,
		intent: Vector2, n: Vector2, u: float) -> float:
	if braking or planted or intent.length_squared() <= cfg.move_deadzone * cfg.move_deadzone:
		return 0.0
	var share: float = 1.0 if posture == SkaterMovementRules.Posture.COMMIT \
			else PASSIVE_DRIVE_SHARE
	var along: float = minf(intent.length(), 1.0) * intent.normalized().dot(n)
	var square: float = lerpf(SIDE_ON_SHARE, 1.0, maxf(facing.dot(n) * signf(along), 0.0))
	var pace: float = 1.0
	if along * u > 0.0:
		pace = clampf(1.0 - absf(u) / MAX_SPEED_M_S, 0.0, 1.0)
	return thrust * share * stagger_thrust * square * pace * along


# The most (m/s²) body X's edges resist the pair's motion at `u` (m/s) with:
# engaged and braking, the stop's edges set against the push (SET_ANCHOR), from
# any side, loose once the pair is sliding or while he is staggered
# (`stagger_grip` under 1); braking unengaged, or planted, a stop's share; else
# the glide's friction. `_facing` and `_n` are unread: a set man holds from any
# side.
static func hold(cfg: SkaterMovementRules.MovementConfig, posture: int, braking: bool,
		planted: bool, stagger_grip: float, _facing: Vector2, _n: Vector2, u: float) -> float:
	if braking and posture == SkaterMovementRules.Posture.COMMIT:
		var loose: float = smoothstep(SET_SPEED, LOOSE_SPEED, absf(u))
		if stagger_grip < 1.0:
			loose = 1.0
		return cfg.stop_decel * SET_ANCHOR * stagger_grip * lerpf(1.0, LOOSE_SHARE, loose)
	if planted:
		return cfg.stop_decel * stagger_grip
	if braking:
		return cfg.stop_decel * PASSIVE_BRAKE_SHARE * stagger_grip
	return cfg.friction + cfg.friction_drag * absf(u)


# How far (m) a press that starts the pair off at `accel` (m/s², pair_accel from
# rest) moves a man in `seconds`: the drive fades toward the walking pace, so
# the pair's speed runs up to it and the ground it covers falls short of
# ½·a·t² the longer it runs.
static func displacement(accel: float, seconds: float) -> float:
	if accel <= 0.0 or seconds <= 0.0:
		return 0.0
	var tau: float = MAX_SPEED_M_S / accel
	return MAX_SPEED_M_S * (seconds - tau * (1.0 - exp(-seconds / tau)))


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

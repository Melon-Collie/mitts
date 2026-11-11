class_name FightFistRules
extends RefCounted

# The punching fist, placed by the cursor the way the blade is (docs/fighting-
# plan.md §3). The cursor's point on the ice names where the fist goes across the
# ice, held to the arm's reach and kept in front of the body; how high it goes is
# solved, not aimed: up at the guard (FightGuardRules) while the arm is bent, and
# at the other man's chin as it straightens out at him. The fist chases that
# target with a speed and an acceleration it cannot exceed, so a punch is the
# cursor driven out at him and its power (phase 4) is how fast the fist arrives.
# Every position is in the puncher's UpperBody frame (−Z forward, +Y up).

# A fist's top speed, m/s: a hockey fight's punches, thrown off skates and held
# by the sweater, land around 8-9 m/s; a boxer's straight is ~10.
const MAX_SPEED_M_S: float = 9.0
# How hard a fist can speed up or slow down, m/s²: to top speed in ~6 cm.
const MAX_ACCEL_M_S2: float = 650.0
# How fast the fist closes on its target at the arrive law's knee, 1/s.
const ARRIVE_GAIN: float = 28.0
# The least a fist is held in front of its shoulder, metres: no fist goes back
# into its own chest.
const MIN_FORWARD_M: float = 0.15
# The arm's extension (target off the shoulder over its reach) over which the
# fist rises from the guard's height to the other man's chin.
const RISE_FROM: float = 0.45
const RISE_TO: float = 0.85
# A punching arm the other man holds (FightHoldRules.Grip.ARM_*) reaches this
# share of its reach and moves at this share of its speed and acceleration.
const TIED_REACH_SHARE: float = 0.55
const TIED_SPEED_SHARE: float = 0.3


# Where the fist goes. `shoulder` is its arm's, `cursor` the cursor (only its x
# and z are read), `reach` the arm's straight reach from the shoulder,
# `guard_y` the guard's height and `chin_y` the other man's chin (the guard's
# with no one to hit).
static func target(shoulder: Vector3, cursor: Vector3, reach: float, guard_y: float,
		chin_y: float) -> Vector3:
	var off := Vector2(cursor.x - shoulder.x, minf(cursor.z - shoulder.z, -MIN_FORWARD_M))
	var rise: float = smoothstep(RISE_FROM, RISE_TO, off.length() / maxf(reach, 0.001))
	var y: float = lerpf(guard_y, chin_y, rise)
	var dy: float = y - shoulder.y
	var across: float = sqrt(maxf(reach * reach - dy * dy, 0.0))
	if off.length() > across:
		off = off.normalized() * across
	return Vector3(shoulder.x + off.x, y, shoulder.z + off.y)


# The fist's velocity after `delta` chasing `target` from `pos` at `vel`: an
# arrive law (closing at ARRIVE_GAIN, no faster than `max_speed`) reached no
# faster than `max_accel` allows. The caller moves the fist by it.
static func step_velocity(pos: Vector3, vel: Vector3, target_pos: Vector3, delta: float,
		max_speed: float, max_accel: float) -> Vector3:
	var desired: Vector3 = (target_pos - pos) * ARRIVE_GAIN
	if desired.length() > max_speed:
		desired = desired.normalized() * max_speed
	var dv: Vector3 = desired - vel
	var most: float = max_accel * delta
	if dv.length() > most:
		dv = dv.normalized() * most
	return vel + dv


# A fist held within `reach` of its shoulder: an arm that is straight goes no
# further, whatever the fist's momentum.
static func held_to_reach(shoulder: Vector3, fist: Vector3, reach: float) -> Vector3:
	var off: Vector3 = fist - shoulder
	return shoulder + off.normalized() * reach if off.length() > reach else fist

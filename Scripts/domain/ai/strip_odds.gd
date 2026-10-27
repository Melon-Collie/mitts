class_name AIStripOdds

# Whether a defender strips the carrier of the puck on a path he skates
# (docs/defender-race-plan.md): where the defender will be is his momentum's
# line give or take his push, and while the puck is within his stick it is
# stripped at a rate. Every number is measured against our defending bots
# (tests/instruments/ai/test_defender_race_truth.gd). A leaf — GameRules and
# AISkaterCaps only.

# How far off his body his stick takes the puck (m): stick, blade and poke.
const STRIP_RADIUS_M: float = 2.0
# The strip rates (/s) while the puck is within it, moving and standing.
const MOVING_STRIP_RATE: float = 4.5
const STANDING_STRIP_RATE: float = 3.0
# A puck slower than this (m/s) is standing.
const STANDING_PUCK_M_S: float = 1.0
# How far off his momentum's line he goes: the odds of a spot fall by e per this
# share of his body's push it takes to be there.
const FAN_SCALE: float = 0.25
# A held puck's samples (s).
const DWELL_STEP_S: float = 0.1

# _within's table: the odds a fan of length L holds him within R of a point d
# off its centre, by d / R (linear) and L / R (logarithmic).
const _D_STEPS: int = 41
const _D_MAX: float = 8.0
const _L_STEPS: int = 25
const _L_MIN: float = 0.02
const _L_MAX: float = 8.0
const _BUILD_STEPS: int = 400
const _BUILD_SPAN: float = 30.0

static var _table: PackedFloat32Array = _build_table()


# The odds a defender at `pos` moving `vel`, built as `caps` (null: the league
# build), is within his stick of `point` `t` after that; `elapsed_s` is how long
# before then his state was read (a defence carried forward to start from), which
# his spread has been growing over too.
static func odds_within(pos: Vector3, vel: Vector3, caps: AISkaterCaps, point: Vector3,
		t: float, elapsed_s: float = 0.0) -> float:
	var dx: float = point.x - pos.x - vel.x * t
	var dz: float = point.z - pos.z - vel.z * t
	var thrust: float = caps.max_accel if caps != null else GameRules.DEFAULT_SKATER_THRUST_M_S2
	var spread: float = t + elapsed_s
	return _within(sqrt(dx * dx + dz * dz) / STRIP_RADIUS_M,
			FAN_SCALE * 0.5 * thrust * spread * spread / STRIP_RADIUS_M)


# The expected strips over one stretch of a path: the puck from `prev` to
# `point`, there `t` from now after `dt`, at the rate for its pace, by the odds
# each defender (index-matched `vels`, `caps` or empty for the league build) is
# within his stick of it then. The defenders add.
static func stretch_strips(prev: Vector3, point: Vector3, dt: float, t: float,
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array = [],
		elapsed_s: float = 0.0) -> float:
	if dt <= 0.0:
		return 0.0
	var has_caps: bool = caps.size() == defenders.size()
	var near: float = 0.0
	for i: int in defenders.size():
		near += odds_within(defenders[i], vels[i], caps[i] if has_caps else null, point, t,
				elapsed_s)
	var pace: float = Vector2(point.x - prev.x, point.z - prev.z).length() / dt
	return dt * near * (STANDING_STRIP_RATE if pace < STANDING_PUCK_M_S else MOVING_STRIP_RATE)


# The expected strips along a path: the puck from `start` now through `points`,
# reached at `times` from now.
static func path_strips(start: Vector3, points: Array[Vector3], times: Array[float],
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array = [],
		elapsed_s: float = 0.0) -> float:
	var total: float = 0.0
	var prev: Vector3 = start
	var prev_t: float = 0.0
	for k: int in points.size():
		total += stretch_strips(prev, points[k], times[k] - prev_t, times[k], defenders, vels,
				caps, elapsed_s)
		prev = points[k]
		prev_t = times[k]
	return total


# The expected strips of a puck held at `point` from `t0` to `t1` from now.
static func dwell_strips(point: Vector3, t0: float, t1: float, defenders: Array[Vector3],
		vels: Array[Vector3], caps: Array = [], elapsed_s: float = 0.0) -> float:
	var total: float = 0.0
	var t: float = t0
	while t < t1 - 1e-6:
		var dt: float = minf(DWELL_STEP_S, t1 - t)
		t += dt
		total += stretch_strips(point, point, dt, t, defenders, vels, caps, elapsed_s)
	return total


# The expected strips of a straight carry from `from` to `to` in `arrival_time`,
# the puck at a steady pace (held, when they meet), sampled every DWELL_STEP_S;
# setting off `start_s` from now against the defence as it is now.
static func carry_strips(from: Vector3, to: Vector3, arrival_time: float,
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array = [],
		elapsed_s: float = 0.0, start_s: float = 0.0) -> float:
	if arrival_time <= 0.0 or defenders.is_empty():
		return 0.0
	var steps: int = maxi(1, ceili(arrival_time / DWELL_STEP_S - 1e-6))
	var dt: float = arrival_time / steps
	var total: float = 0.0
	var prev: Vector3 = from
	for k: int in steps:
		var p: Vector3 = from.lerp(to, float(k + 1) / steps)
		total += stretch_strips(prev, p, dt, start_s + dt * (k + 1), defenders, vels, caps,
				elapsed_s)
		prev = p
	return total


# The odds the puck survives `strips` expected strips.
static func keep(strips: float) -> float:
	return exp(-strips)


# The odds a fan of length `l` (in radii) around a centre `d` (in radii) off the
# point holds him within one radius of it.
static func _within(d: float, l: float) -> float:
	if l < _L_MIN:
		return 1.0 if d < 1.0 else 0.0
	if l > _L_MAX or d >= _D_MAX:
		# The fan is wide against the disc: its density there × the disc's area.
		return minf(exp(-d / l) / (2.0 * l * l), 1.0)
	var fd: float = d / _D_MAX * (_D_STEPS - 1)
	var fl: float = log(l / _L_MIN) / log(_L_MAX / _L_MIN) * (_L_STEPS - 1)
	var i: int = mini(int(fd), _D_STEPS - 2)
	var j: int = mini(int(fl), _L_STEPS - 2)
	var u: float = fd - i
	var v: float = fl - j
	var a: float = lerpf(_table[i * _L_STEPS + j], _table[(i + 1) * _L_STEPS + j], u)
	var b: float = lerpf(_table[i * _L_STEPS + j + 1], _table[(i + 1) * _L_STEPS + j + 1], u)
	return lerpf(a, b, v)


# Every cell of _within's table: the fan's radial density, e^(−r/l) / (2π l²),
# over each circle round its centre times the share of that circle inside the
# disc.
static func _build_table() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_D_STEPS * _L_STEPS)
	for i: int in _D_STEPS:
		var d: float = _D_MAX * i / (_D_STEPS - 1)
		for j: int in _L_STEPS:
			var l: float = _L_MIN * pow(_L_MAX / _L_MIN, float(j) / (_L_STEPS - 1))
			var total: float = 0.0
			var ds: float = _BUILD_SPAN / _BUILD_STEPS
			for k: int in _BUILD_STEPS:
				var s: float = (k + 0.5) * ds
				total += s / PI * exp(-s) * _inside_angle(s * l, d) * ds
			out[i * _L_STEPS + j] = minf(total, 1.0)
	return out


# The half-angle of a circle of radius `r` round a centre `d` off a unit disc's
# centre that lies inside the disc.
static func _inside_angle(r: float, d: float) -> float:
	if r <= 1.0 - d:
		return PI
	if r >= 1.0 + d or r <= d - 1.0:
		return 0.0
	return acos(clampf((r * r + d * d - 1.0) / (2.0 * r * d), -1.0, 1.0))

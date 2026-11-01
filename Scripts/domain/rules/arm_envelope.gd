class_name ArmEnvelope
extends RefCounted

# Where a carried blade can be held, and how, as the arm anatomy model derived
# it (docs/arm-anatomy-plan.md §6): per build height and trunk state, on a grid
# of blade positions round the carrier, whether a body holds the blade as
# players hold it, and where that pose has the top hand and the bottom hand's
# grip down the shaft. Written by tests/instruments/actors/
# test_derive_arm_envelope.gd; read through SkaterArmEnvelope.
#
# The skater's root frame (his facing, -Z ahead, m off his origin), +X toward
# his forehand: the caller mirrors for a left or right shot. Angles are off the
# facing, + round the forehand.

const VERSION: int = 1
const PATH: String = "res://data/arm_envelope.json"
const HEIGHTS: Array[int] = [67, 73, 80]
const STATES: Array[String] = ["stand", "skate"]
const ANGLES_DEG: Array[float] = [-150.0, -135.0, -120.0, -105.0, -90.0, -75.0, -60.0,
		-45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0, 105.0, 120.0, 135.0,
		150.0]
const RADII_M: Array[float] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5,
		1.6, 1.7]
# How far round from the cursor a blocked bearing looks for one that holds,
# toward straight ahead (degrees a step).
const _ANGLE_SEARCH_STEP_DEG: float = 5.0

# A blade held: the top hand (root frame, +X forehand) and the bottom hand's
# place down the shaft from it (m).
class Hold:
	var hand := Vector3.ZERO
	var spacing: float = 0.0

# [height index][state index] -> PackedFloat32Array of 5 per cell: held, hand
# x, y, z, spacing; angle-major.
var _cells: Array = []
# _corners' answer, refilled each call (the carry reads it on the tick): four
# floats a corner, up to eight corners.
var _corner_buf := PackedFloat32Array()


static func from_dict(d: Dictionary) -> ArmEnvelope:
	if int(d.get("version", 0)) != VERSION:
		return null
	var env := ArmEnvelope.new()
	var builds: Array = d.get("builds", [])
	if builds.size() != HEIGHTS.size():
		return null
	for b: Dictionary in builds:
		var per_state: Array = []
		for state: String in STATES:
			var rows: Array = (b["states"] as Dictionary)[state]
			var flat := PackedFloat32Array()
			for row: Array in rows:
				for v: Variant in row:
					flat.append(float(v))
			if flat.size() != ANGLES_DEG.size() * RADII_M.size() * 5:
				return null
			per_state.append(flat)
		env._cells.append(per_state)
	return env


# Where the blade at `angle` (rad, + forehand) and `radius` (m) comes to rest
# for a carrier `height` inches tall, `skating` (0 standing, 1 his full
# skating fold) of the way between the two trunks: the radius held into the
# band a body holds there, and, where nothing holds at that bearing, the bearing
# turned toward straight ahead to the nearest that does. Vector2(angle, radius).
func held_blade(height: float, skating: float, angle: float, radius: float) -> Vector2:
	var deg: float = rad_to_deg(angle)
	var band: Vector2 = band_at(height, skating, deg)
	var step: float = -signf(deg) * _ANGLE_SEARCH_STEP_DEG
	while band.x > band.y and absf(deg) > 0.0:
		deg += step
		if signf(deg) == signf(step) and deg != 0.0:
			deg = 0.0
		band = band_at(height, skating, deg)
	if band.x > band.y:
		return Vector2(angle, radius)
	return Vector2(deg_to_rad(deg), clampf(radius, band.x, band.y))


# The radii a body holds the blade between at `deg` off the facing; x > y when
# none holds there.
func band_at(height: float, skating: float, deg: float) -> Vector2:
	var lo: float = 0.0
	var hi: float = 0.0
	var weight: float = 0.0
	for c: int in _corners(height, skating, deg):
		var corner := Vector4(_corner_buf[c * 4], _corner_buf[c * 4 + 1], _corner_buf[c * 4 + 2],
				_corner_buf[c * 4 + 3])
		var cells: PackedFloat32Array = _cells[int(corner.x)][int(corner.y)]
		var ai: int = int(corner.z)
		var first: int = -1
		var last: int = -1
		for ri: int in RADII_M.size():
			if cells[(ai * RADII_M.size() + ri) * 5] > 0.5:
				if first < 0:
					first = ri
				last = ri
		if first < 0:
			continue
		lo += RADII_M[first] * corner.w
		hi += RADII_M[last] * corner.w
		weight += corner.w
	if weight < 0.5:
		return Vector2(1.0, 0.0)
	return Vector2(lo / weight, hi / weight)


# How a body holds the blade at `deg` off the facing and `radius` out, into
# `out`: the held cells round it, each weighted by its share. False when none
# round it holds.
func hold_at(height: float, skating: float, deg: float, radius: float, out: Hold) -> bool:
	var r: float = clampf((radius - RADII_M[0]) / (RADII_M[1] - RADII_M[0]), 0.0,
			float(RADII_M.size() - 1))
	var r0: int = mini(int(r), RADII_M.size() - 2)
	var rt: float = r - float(r0)
	var hand := Vector3.ZERO
	var spacing: float = 0.0
	var weight: float = 0.0
	for c: int in _corners(height, skating, deg):
		var corner := Vector4(_corner_buf[c * 4], _corner_buf[c * 4 + 1], _corner_buf[c * 4 + 2],
				_corner_buf[c * 4 + 3])
		var cells: PackedFloat32Array = _cells[int(corner.x)][int(corner.y)]
		var ai: int = int(corner.z)
		for k: int in 2:
			var w: float = corner.w * (rt if k == 1 else 1.0 - rt)
			var i: int = (ai * RADII_M.size() + r0 + k) * 5
			if w <= 0.0 or cells[i] < 0.5:
				continue
			hand += Vector3(cells[i + 1], cells[i + 2], cells[i + 3]) * w
			spacing += cells[i + 4] * w
			weight += w
	if weight <= 0.0:
		return false
	out.hand = hand / weight
	out.spacing = spacing / weight
	return true


# The grid's corners round a query and their shares, into _corner_buf as
# (height index, state index, angle index, weight); returns how many. The angle
# is held to the grid's span.
func _corners(height: float, skating: float, deg: float) -> int:
	var h: Vector2 = _bracket_heights(height)
	var a: float = clampf((deg - ANGLES_DEG[0]) / (ANGLES_DEG[1] - ANGLES_DEG[0]), 0.0,
			float(ANGLES_DEG.size() - 1))
	var a0: int = mini(int(a), ANGLES_DEG.size() - 2)
	var at: float = a - float(a0)
	var s: float = clampf(skating, 0.0, 1.0)
	if _corner_buf.size() != 32:
		_corner_buf.resize(32)
	var n: int = 0
	for hi: int in 2:
		var hw: float = h.y if hi == 1 else 1.0 - h.y
		for si: int in 2:
			var sw: float = s if si == 1 else 1.0 - s
			for ak: int in 2:
				var w: float = hw * sw * (at if ak == 1 else 1.0 - at)
				if w > 0.0:
					_corner_buf[n * 4] = h.x + hi
					_corner_buf[n * 4 + 1] = si
					_corner_buf[n * 4 + 2] = a0 + ak
					_corner_buf[n * 4 + 3] = w
					n += 1
	return n


# The lower bracketing height's index and the share toward the next.
static func _bracket_heights(height: float) -> Vector2:
	for i: int in HEIGHTS.size() - 1:
		if height <= float(HEIGHTS[i + 1]):
			return Vector2(i, clampf((height - HEIGHTS[i]) / float(HEIGHTS[i + 1] - HEIGHTS[i]),
					0.0, 1.0))
	return Vector2(HEIGHTS.size() - 2, 1.0)

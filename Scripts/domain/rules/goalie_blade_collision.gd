class_name GoalieBladeCollision

# The stick's collision with the goalie: his gear is solid to the blade, a wall
# it cannot reach through, and touching it confiscates nothing. The boxes are
# his save boxes, the ones a loose puck meets (GoalieContactDetector's packed
# layout: three basis columns, the origin, the half extents, 15 floats a box),
# so the stick stops on exactly what the puck stops on. A carried puck pressed
# into him meets the same wall on its pin (SkaterController
# ._pinned_puck_off_goalies), held off his gear as the twine holds it.
#
# The blade is a SEGMENT (heel → toe), sampled along its length, each sample
# swept from where it was at the start of the tick: a sample that came in
# through a face stays on that face's side, so a blade swept across a pad
# never comes out on his far side, and one his gear moved onto goes out the
# nearest side. The push is always across the ice, the way the boards and the
# net push it, and only what took it into the face is taken off: along the
# face it slides.
#
# Pure and allocation-free.

const FLOATS_PER_BOX: int = 15
# Samples along the blade, heel to toe.
const SAMPLES: int = 5
# A face whose normal is no more than this across the ice is his gear's top or
# underside: the blade on the ice is pushed off a side, never up or down.
const SIDE_MIN: float = 0.3
# Rounds of resolution: a push off one box can put the blade into another.
const ROUNDS: int = 2


# The translation that holds the blade (`heel` → `toe`, world) out of every box
# in `boxes`, given the blade's middle was at `prev_mid` at the start of the
# tick; `half_thickness` is the blade's own reach off its segment. ZERO when it
# is clear of him.
static func resolve(prev_mid: Vector3, heel: Vector3, toe: Vector3, half_thickness: float,
		boxes: PackedFloat32Array) -> Vector3:
	var count: int = boxes.size() / FLOATS_PER_BOX
	var moved: Vector3 = (heel + toe) * 0.5 - prev_mid
	var reach: float = heel.distance_to(toe) * 0.5 + moved.length() + half_thickness
	var offset := Vector3.ZERO
	for _round: int in ROUNDS:
		var best := Vector3.ZERO
		for b: int in count:
			var mid: Vector3 = (heel + toe) * 0.5 + offset
			if mid.distance_to(_origin(boxes, b)) > _half(boxes, b).length() + reach:
				continue
			var push: Vector3 = _blade_out(heel + offset, toe + offset, moved, half_thickness, boxes, b)
			if push.length_squared() > best.length_squared():
				best = push
		if best == Vector3.ZERO:
			break
		offset += best
	return offset


# The push across the ice that takes the whole blade out of box `b`, one way
# for all of it: the way the sample in the box nearest the blade's middle goes
# out (`point_out`), as far as the deepest sample needs.
static func _blade_out(heel: Vector3, toe: Vector3, moved: Vector3, half_thickness: float,
		boxes: PackedFloat32Array, b: int) -> Vector3:
	var lead := Vector3.ZERO
	var nearest: float = INF
	for k: int in SAMPLES:
		var f: float = float(k) / float(SAMPLES - 1)
		var now: Vector3 = heel.lerp(toe, f)
		var push: Vector3 = point_out(now - moved, now, half_thickness, boxes, b)
		if push != Vector3.ZERO and absf(f - 0.5) < nearest:
			nearest = absf(f - 0.5)
			lead = push
	if lead == Vector3.ZERO:
		return Vector3.ZERO
	var way: Vector3 = lead.normalized()
	var far: float = 0.0
	for k: int in SAMPLES:
		far = maxf(far, _out_along(heel.lerp(toe, float(k) / float(SAMPLES - 1)), way, half_thickness, boxes, b))
	return way * far


# How far a point at `at` has to go along `way` (across the ice) to be out of
# box `b` grown by `radius`; 0 when it is out already, or never gets out that
# way through a side it can reach.
static func _out_along(at: Vector3, way: Vector3, radius: float, boxes: PackedFloat32Array, b: int) -> float:
	var o := _origin(boxes, b)
	var e: Vector3 = _half(boxes, b) + Vector3.ONE * radius
	var ln: Vector3 = _local(at - o, boxes, b)
	if absf(ln.x) >= e.x or absf(ln.y) >= e.y or absf(ln.z) >= e.z:
		return 0.0
	var wl: Vector3 = _local(way, boxes, b)
	var out: float = INF
	for i: int in 3:
		if absf(wl[i]) < 1e-6:
			continue
		out = minf(out, (signf(wl[i]) * e[i] - ln[i]) / wl[i])
	return out if out != INF else 0.0


# The push across the ice that takes a point now at `now` (at `was` a tick ago),
# with `radius` of its own, out of box `b`: off the side it came in through, or
# the nearest side when it was inside already. ZERO when it is clear.
static func point_out(was: Vector3, now: Vector3, radius: float, boxes: PackedFloat32Array, b: int) -> Vector3:
	var o := _origin(boxes, b)
	var e: Vector3 = _half(boxes, b) + Vector3.ONE * radius
	var ln: Vector3 = _local(now - o, boxes, b)
	if absf(ln.x) >= e.x or absf(ln.y) >= e.y or absf(ln.z) >= e.z:
		return Vector3.ZERO
	var lw: Vector3 = _local(was - o, boxes, b)
	var face: int = _entered(lw, ln, e)
	var side: float = 0.0
	if face >= 0 and _across(_axis(boxes, b, face)) >= SIDE_MIN:
		side = signf(lw[face])
	else:
		face = _nearest_side(ln, e, boxes, b)
		if face < 0:
			return Vector3.ZERO
		side = signf(ln[face]) if ln[face] != 0.0 else 1.0
	var axis: Vector3 = _axis(boxes, b, face)
	var flat := Vector3(axis.x, 0.0, axis.z)
	var across: float = flat.length()
	return flat / across * side * (e[face] - side * ln[face]) / across


# The face a point moving from `lw` to `ln` (box-local) came in through: the
# axis whose slab it entered last, or -1 when it started inside.
static func _entered(lw: Vector3, ln: Vector3, e: Vector3) -> int:
	if absf(lw.x) < e.x and absf(lw.y) < e.y and absf(lw.z) < e.z:
		return -1
	var face: int = -1
	var last: float = -INF
	for i: int in 3:
		var d: float = ln[i] - lw[i]
		if absf(lw[i]) < e[i] or absf(d) < 1e-9:
			continue
		var t: float = (signf(lw[i]) * e[i] - lw[i]) / d
		if t > last:
			last = t
			face = i
	return face


# The side (a face across the ice) nearest a point at `ln` inside box `b`, by
# how far it has to go along the ice to get out; -1 when the box has none.
static func _nearest_side(ln: Vector3, e: Vector3, boxes: PackedFloat32Array, b: int) -> int:
	var face: int = -1
	var least: float = INF
	for i: int in 3:
		var across: float = _across(_axis(boxes, b, i))
		if across < SIDE_MIN:
			continue
		var go: float = (e[i] - absf(ln[i])) / across
		if go < least:
			least = go
			face = i
	return face


static func _axis(boxes: PackedFloat32Array, b: int, i: int) -> Vector3:
	var base: int = b * FLOATS_PER_BOX + i * 3
	return Vector3(boxes[base], boxes[base + 1], boxes[base + 2])


static func _local(v: Vector3, boxes: PackedFloat32Array, b: int) -> Vector3:
	return Vector3(v.dot(_axis(boxes, b, 0)), v.dot(_axis(boxes, b, 1)), v.dot(_axis(boxes, b, 2)))


static func _across(axis: Vector3) -> float:
	return Vector2(axis.x, axis.z).length()


static func _origin(boxes: PackedFloat32Array, b: int) -> Vector3:
	var base: int = b * FLOATS_PER_BOX
	return Vector3(boxes[base + 9], boxes[base + 10], boxes[base + 11])


static func _half(boxes: PackedFloat32Array, b: int) -> Vector3:
	var base: int = b * FLOATS_PER_BOX
	return Vector3(boxes[base + 12], boxes[base + 13], boxes[base + 14])

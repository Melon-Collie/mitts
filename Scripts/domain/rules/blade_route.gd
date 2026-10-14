class_name BladeRoute
extends RefCounted

# The path a carried puck takes between two spots off a skater's body, so the
# bot's cursor walks it and the shot-hold pricing measures the same route. All
# vectors are body-relative XZ offsets. The puck goes straight across unless that
# line runs through the skater; then it takes the shortest way that stays CLEAR_M
# off his centre without passing behind him: a tangent onto that circle, around
# the front, and a tangent off it. A puck already inside the circle goes straight,
# unless that line takes it deeper into the body: then it comes out to the circle
# first.

const BODY_RADIUS_M: float = 0.35
const CLEAR_M: float = BODY_RADIUS_M + GameRules.PUCK_COLLISION_RADIUS


static func crosses_body(from: Vector2, to: Vector2) -> bool:
	if to.length() <= CLEAR_M:
		return false
	var ab: Vector2 = to - from
	var len_sq: float = ab.length_squared()
	if len_sq < 0.000001:
		return false
	var t: float = clampf(-from.dot(ab) / len_sq, 0.0, 1.0)
	var closest: float = (from + ab * t).length()
	return closest < minf(from.length(), CLEAR_M) - 0.001


static func length(from: Vector2, to: Vector2, facing: Vector2) -> float:
	if not crosses_body(from, to):
		return from.distance_to(to)
	var start: Vector2 = _entry(from)
	var turn_sign: float = _front_sign(start, to, facing)
	return from.distance_to(start) + _tangent(start) \
			+ CLEAR_M * _arc(start, to, turn_sign) + _tangent(to)


# The point `s` metres along the route from `from` to `to`.
static func point_along(from: Vector2, to: Vector2, facing: Vector2, s: float) -> Vector2:
	if not crosses_body(from, to):
		return from.move_toward(to, s)
	var start: Vector2 = _entry(from)
	var out: float = from.distance_to(start)
	if s <= out:
		return from.move_toward(start, s)
	s -= out
	var turn_sign: float = _front_sign(start, to, facing)
	var on: float = start.angle() + turn_sign * _tangent_turn(start)
	var lead: float = _tangent(start)
	if s <= lead:
		return start.move_toward(Vector2.from_angle(on) * CLEAR_M, s)
	s -= lead
	var arc: float = _arc(start, to, turn_sign)
	if s <= CLEAR_M * arc:
		return Vector2.from_angle(on + turn_sign * s / CLEAR_M) * CLEAR_M
	var off := Vector2.from_angle(on + turn_sign * arc) * CLEAR_M
	return off.move_toward(to, s - CLEAR_M * arc)


static func _entry(from: Vector2) -> Vector2:
	var r: float = from.length()
	return from if r >= CLEAR_M else from / r * CLEAR_M


# +1 or −1: the turn about the body that never carries the puck behind him
# (through the direction opposite `facing`). Re-read mid-sweep it holds, since
# what is left of a front sweep has no back in it. The shorter turn when facing
# is degenerate.
static func _front_sign(from: Vector2, to: Vector2, facing: Vector2) -> float:
	var turn: float = wrapf(to.angle() - from.angle(), -PI, PI)
	var short_sign: float = 1.0 if turn >= 0.0 else -1.0
	if facing.length_squared() < 0.0001:
		return short_sign
	var to_back: float = wrapf((-facing).angle() - from.angle(), -PI, PI)
	if to_back * short_sign > 0.0 and absf(to_back) < absf(turn):
		return -short_sign
	return short_sign


# Angle swept on the clearance circle between the two tangent points.
static func _arc(from: Vector2, to: Vector2, turn_sign: float) -> float:
	var sweep: float = wrapf((to.angle() - from.angle()) * turn_sign, 0.0, TAU)
	return maxf(sweep - _tangent_turn(from) - _tangent_turn(to), 0.0)


static func _tangent(p: Vector2) -> float:
	return sqrt(maxf(p.length_squared() - CLEAR_M * CLEAR_M, 0.0))


static func _tangent_turn(p: Vector2) -> float:
	return acos(clampf(CLEAR_M / maxf(p.length(), CLEAR_M), -1.0, 1.0))

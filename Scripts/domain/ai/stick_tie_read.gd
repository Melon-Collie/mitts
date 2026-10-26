class_name AIStickTieRead
extends RefCounted

# Whether a covering defender ties up his man's stick, and where a tied attacker
# pulls his own stick to break it. A tied stick catches nothing, so the tie is
# worth exactly the reception it denies — and it spends the defender's own stick,
# which then intercepts nothing. So he ties only a man the puck is coming to, and
# only when his free stick could not have stopped it on the way.

# How far ahead a loose puck's path is read for a reception: past this the
# receiver has time to see the tie and the defender to do something better.
const FEED_HORIZON_S: float = 1.5
# Extra reach around a receiver's blade that still counts as "the puck reaches
# him" — a receiver steps to a feed by about a blade length.
const RECEIVER_STEP_M: float = GameRules.DEFAULT_BLADE_LENGTH_M


# Time in [0, horizon] at which a puck moving in a straight line passes closest to
# `point` (XZ). Friction is ignored: over the horizon it only shortens the path,
# which errs toward reading a feed that dies short as live.
static func _closest_time(puck_pos: Vector3, puck_vel: Vector3, point: Vector3,
		horizon: float) -> float:
	var v := Vector2(puck_vel.x, puck_vel.z)
	var v_sq: float = v.length_squared()
	if v_sq < 1e-4:
		return 0.0
	var rel := Vector2(point.x - puck_pos.x, point.z - puck_pos.z)
	return clampf(rel.dot(v) / v_sq, 0.0, horizon)


static func path_passes_within(puck_pos: Vector3, puck_vel: Vector3, point: Vector3,
		reach: float, horizon: float = FEED_HORIZON_S) -> bool:
	var t: float = _closest_time(puck_pos, puck_vel, point, horizon)
	return puck_within(puck_pos + puck_vel * t, point, reach)


static func puck_within(puck_pos: Vector3, point: Vector3, reach: float) -> bool:
	return Vector2(puck_pos.x - point.x, puck_pos.z - point.z).length() <= reach


# A carrier's pass lane to the man is open when no defender's stick reaches the
# straight line between them (`defenders` includes the one asking), each by his
# own reach (`reaches`, index-matched).
static func lane_open(carrier_pos: Vector3, man_pos: Vector3,
		defenders: Array[Vector3], reaches: Array[float]) -> bool:
	var a := Vector2(carrier_pos.x, carrier_pos.z)
	var ab := Vector2(man_pos.x, man_pos.z) - a
	var len_sq: float = ab.length_squared()
	if len_sq < 1e-4:
		return true
	for i: int in defenders.size():
		var p := Vector2(defenders[i].x, defenders[i].z)
		var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
		if (a + ab * t).distance_to(p) <= reaches[i]:
			return false
	return true


# The man's shaft within the defender's blade reach (XZ, from his body).
static func shaft_in_reach(self_pos: Vector3, hand: Vector3, blade: Vector3,
		reach: float) -> bool:
	var a := Vector2(hand.x, hand.z)
	var ab := Vector2(blade.x, blade.z) - a
	var p := Vector2(self_pos.x, self_pos.z)
	var len_sq: float = ab.length_squared()
	var t: float = 0.0 if len_sq < 1e-8 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(p) <= reach


# Where a tied attacker pulls his stick: straight away from the stick holding it,
# out to his own reach — the separation that breaks a tie.
static func yank_aim(self_pos: Vector3, self_blade: Vector3, tier_blade: Vector3,
		reach: float) -> Vector3:
	var away := Vector3(self_blade.x - tier_blade.x, 0.0, self_blade.z - tier_blade.z)
	if away.length_squared() < 1e-6:
		away = Vector3(self_blade.x - self_pos.x, 0.0, self_blade.z - self_pos.z)
	if away.length_squared() < 1e-6:
		return self_blade
	var target: Vector3 = self_blade + away.normalized() * reach
	var from_body := Vector3(target.x - self_pos.x, 0.0, target.z - self_pos.z)
	if from_body.length() > reach:
		from_body = from_body.normalized() * reach
	return Vector3(self_pos.x + from_body.x, self_blade.y, self_pos.z + from_body.z)

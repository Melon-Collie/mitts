extends GutTest

# Clearing a puck at his feet (KeeperClear): one an opponent gets to before his
# glove would land on it he sweeps away with the stick when the blade gets
# there first, the blade lying flat on it, turned toe forward in close on his
# blocker side; with nobody near, or his cover first, or the opponent there
# before the stick too, he leaves it to the cover. A clear goes to the corner
# away from the opponent, out its own side from beside a post or from one
# coming at it head on, and never toward his goal line.

const SPEED_M_S: float = 5.0
const READ_S: float = 0.12
const COVER_S: float = 0.4

var _motor: KeeperMotor = null
var _clear: KeeperClear = null


func before_each() -> void:
	_motor = KeeperMotor.new()
	_motor.z = -1.0
	_clear = KeeperClear.new()


# A puck `mine` from him (his space: x across, his glove side −, z ahead −),
# in the net's frame.
func _net(mine: Vector2) -> Vector2:
	return Vector2(_motor.x + mine.x, _motor.z + mine.y)


func _plans(puck: Vector2, them: Array[Vector2]) -> bool:
	return _clear.plan(puck, _motor, false, PackedVector2Array(them), READ_S, SPEED_M_S, COVER_S)


# Where the blade lies with its centre sent to the clear's target, turned as
# the clear turns it, his space.
func _blade() -> Vector3:
	var p := KeeperPose.new()
	_motor.pose(p)
	p.blade_center = _clear.target
	p.blade_yaw = _clear.blade_yaw
	var skel := KeeperSkeleton.new()
	skel.pose(p)
	return KeeperGear.box(skel, KeeperGear.Part.BLADE).origin


func test_a_puck_an_opponent_beats_his_cover_to_he_clears() -> void:
	var puck: Vector2 = _net(Vector2(-0.45, -0.3))
	assert_true(_plans(puck, [puck + Vector2(0.0, -4.0)]), "cleared")
	var blade: Vector3 = _blade()
	assert_lte(Vector2(blade.x + 0.45, blade.z + 0.3).length(), KeeperPoke.ON_PUCK_M, "the blade on it")
	assert_lt(_clear.way.x, 0.0, "head on: out its own side")
	assert_lt(_clear.way.y, 0.0, "away from his goal line")


func test_with_nobody_near_or_his_cover_first_he_leaves_it() -> void:
	var puck: Vector2 = _net(Vector2(-0.45, -0.3))
	assert_false(_plans(puck, []), "nobody near")
	assert_false(_plans(puck, [puck + Vector2(0.0, -12.0)]), "his cover first")


func test_one_the_opponent_gets_to_before_the_stick_he_leaves_to_the_cover() -> void:
	var puck: Vector2 = _net(Vector2(-0.45, -0.3))
	assert_false(_plans(puck, [puck + Vector2(0.0, -1.5)]), "there before the stick")


func test_in_close_on_his_blocker_side_the_blade_turns_toe_forward() -> void:
	var puck: Vector2 = _net(Vector2(0.3, -0.7))
	assert_true(_plans(puck, [puck + Vector2(0.0, -4.0)]), "cleared")
	var stance := KeeperPose.new()
	_motor.pose(stance)
	assert_gt(_clear.blade_yaw, stance.blade_yaw, "toe turned forward")
	var blade: Vector3 = _blade()
	assert_lte(Vector2(blade.x - 0.3, blade.z + 0.7).length(), KeeperPoke.ON_PUCK_M, "the blade on it")


func test_a_clear_goes_away_from_the_opponent_never_toward_his_net() -> void:
	for px: float in [-2.0, -1.2, -0.6, -0.2, 0.2, 0.6, 1.2, 2.0]:
		for pz: float in [-2.5, -1.4, -0.6, -0.2]:
			var puck := Vector2(px, pz)
			for them: Vector2 in [Vector2(-4.0, -4.0), Vector2(0.0, -5.0), Vector2(4.0, -4.0), Vector2(-3.0, -0.5),
					Vector2(3.0, -0.5)]:
				var way: Vector2 = KeeperClear.clear_way(puck, them)
				var what: String = "puck %s, them %s" % [puck, them]
				assert_almost_eq(way.length(), 1.0, 1e-5, what)
				assert_lt(way.y, 0.0, "away from his goal line, " + what)
				var by_post: bool = pz > -KeeperClear.CORNER_OUT_M and absf(px) > GameRules.NET_HALF_WIDTH
				if not by_post and absf(px - them.x) > KeeperClear.HEAD_ON_M:
					assert_eq(signf(way.x), signf(px - them.x), "away from him, " + what)


func test_beside_a_post_or_head_on_it_goes_out_its_own_side() -> void:
	assert_lt(KeeperClear.clear_way(Vector2(-1.2, -0.3), Vector2(-4.0, -0.5)).x, 0.0, "beside the glove post")
	assert_gt(KeeperClear.clear_way(Vector2(1.2, -0.3), Vector2(4.0, -0.5)).x, 0.0, "beside the far post")
	assert_gt(KeeperClear.clear_way(Vector2(0.3, -1.0), Vector2(0.4, -5.0)).x, 0.0, "head on")

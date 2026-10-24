extends GutTest

# Going for a loose puck (KeeperFetch): one a push from him, not behind the
# cage, that no opponent at full sprint gets a stick on before he is down on
# it, with his read as the margin to set out; once going, on while he still
# wins it.

var _motor := KeeperMotor.new()
var _fetch := KeeperFetch.new()
const READ_S: float = 0.13


func before_each() -> void:
	_motor = KeeperMotor.new()
	_motor.x = -0.9
	_motor.z = -0.6


# His own time to be down on a puck at `at`, as the race prices it.
func _his_time(at: Vector2) -> float:
	assert_true(_fetch.plan(at, Vector2.ZERO, _motor, PackedVector2Array(), READ_S, false), "alone: his")
	return KeeperFootwork.push_time(Vector2(_motor.x, _motor.z).distance_to(_fetch.spot), _motor.footwork.t_push_speed,
			_motor.footwork.accel) + _motor.save_move.drop_s


func test_beside_the_post_behind_the_line_it_is_his_but_never_behind_the_cage() -> void:
	assert_true(_fetch.plan(Vector2(-1.6, 0.3), Vector2.ZERO, _motor, PackedVector2Array(), READ_S, false),
			"beside the post")
	assert_lt(_fetch.spot.distance_to(Vector2(-1.6, 0.3)), KeeperFetch.COVER_AHEAD_M + 1e-4, "stopped short of it")
	assert_false(_fetch.plan(Vector2(-0.5, 0.4), Vector2.ZERO, _motor, PackedVector2Array(), READ_S, false),
			"behind the cage")
	var reach: float = _motor.slide.glide_reach(_motor.slide.push_speed) + KeeperFetch.COVER_AHEAD_M
	var far := Vector2(_motor.x, _motor.z) + Vector2(-1.0, -0.2).normalized() * (reach + 0.1)
	assert_false(_fetch.plan(far, Vector2.ZERO, _motor, PackedVector2Array(), READ_S, false), "past a push")


func test_he_races_the_nearest_stick_with_his_read_to_spare() -> void:
	var puck := Vector2(-1.8, -1.2)
	var mine: float = _his_time(puck)
	var stick: float = GameRules.DEFAULT_STICK_LENGTH_M
	var top: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var away := Vector2(-1.0, -1.0).normalized()
	var beats := PackedVector2Array([puck + away * (stick + (mine + READ_S + 0.02) * top)])
	var loses := PackedVector2Array([puck + away * (stick + (mine + READ_S - 0.02) * top)])
	assert_true(_fetch.plan(puck, Vector2.ZERO, _motor, beats, READ_S, false), "he beats him to it")
	assert_false(_fetch.plan(puck, Vector2.ZERO, _motor, loses, READ_S, false), "not by his read: he stays")
	assert_true(_fetch.plan(puck, Vector2.ZERO, _motor, loses, READ_S, true), "but once going, on while he wins")


func test_a_puck_still_sliding_is_gone_for_where_it_stops() -> void:
	var v := Vector2(0.0, -0.6)
	var stops: Vector2 = Vector2(-1.8, -1.0) + v.normalized() * (v.length_squared() / (2.0 * GameRules.PUCK_ICE_DECEL_M_S2))
	assert_true(_fetch.plan(Vector2(-1.8, -1.0), v, _motor, PackedVector2Array(), READ_S, false))
	assert_almost_eq(KeeperPositioning.facing(_fetch.spot, stops), _fetch.facing, 1e-5, "square to where it stops")

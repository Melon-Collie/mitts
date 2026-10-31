extends GutTest

# A puck at his feet an opponent gets to before his glove would land on it he
# clears with the stick (KeeperController, KeeperClear): set square on a puck
# out front, the live keeper and the real puck's tick stepped as the game steps
# them, a puck laid dead at his feet with an opponent closing from out front on
# one side. He sweeps it away to the corner away from the opponent rather than
# covering it, and it never ends up in his net; one by his skate with the man
# on that side he never sweeps across himself. With the opponent far off he
# covers it.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECONDS: float = 2.0
const SET_ON := Vector2(0.0, -6.0)
# From where he stands, his own frame: across (− his glove side), and ahead (+):
# beside his glove skate, and out in front, clear of his stick.
const BY_SKATE := Vector2(-0.7, 0.1)
const OUT_FRONT := Vector2(0.0, 0.6)
# Where the opponent stands from the puck, net frame: out front, off to one
# side, close enough to beat his cover and far enough for the stick.
const CLOSING_M: float = 4.0
# A clear's pace once it is off the blade.
const CLEARED_M_S: float = 0.5 * KeeperClear.SPEED_M_S

var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null
var _opponent: Skater = null
var _covered: bool = false
# The puck's velocity, net frame, the first tick it was going at a clear's pace.
var _cleared := Vector3.ZERO


func before_each() -> void:
	_goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate() as Goalie
	_puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	_opponent = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	_keeper = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_opponent)
	add_child_autofree(_keeper)
	_puck.set_server_mode(true)
	_puck.set_goalie_provider(func() -> Array: return [_goalie])
	_keeper.setup(_goalie, _puck, GameRules.GOAL_LINE_Z, true)
	_keeper.set_skater_getter(func() -> Array: return [_opponent])
	_keeper.puck_covered.connect(func(_team: int) -> void: _covered = true)
	_puck._physics_process(DT)


func test_with_an_opponent_closing_he_clears_it_away_from_him() -> void:
	for c: Array in [[BY_SKATE, 1.0], [OUT_FRONT, 1.0], [OUT_FRONT, -1.0]]:
		var side: float = c[1]
		var what: String = "a puck at %s, the man on his %s" % [c[0], "glove side" if side < 0.0 else "blocker side"]
		_close_on(c[0], side)
		assert_false(_covered, what + ": not covered")
		assert_ne(_cleared, Vector3.ZERO, what + ": cleared")
		assert_eq(signf(_cleared.x), -side, what + ": away from him")
		assert_lt(_cleared.z, 0.0, what + ": away from his goal line")
		assert_lt((_keeper._net.affine_inverse() * _puck.global_position).z, 0.0, what + ": not in his net")


func test_by_his_skate_with_the_man_on_that_side_he_never_sweeps_across_himself() -> void:
	_close_on(BY_SKATE, -1.0)
	assert_true(_cleared == Vector3.ZERO or _cleared.x < 0.0, "not across him")
	assert_lt((_keeper._net.affine_inverse() * _puck.global_position).z, 0.0, "not in his net")


func test_with_the_opponent_far_off_he_covers_it() -> void:
	var laid: Vector2 = _lay(BY_SKATE)
	_opponent.global_position = _keeper._net * Vector3(laid.x, 0.0, laid.y - 15.0)
	_play(SECONDS)
	assert_true(_covered, "covered")


# A puck laid at `spot`, an opponent closing from out front on `side` of it.
func _close_on(spot: Vector2, side: float) -> void:
	var laid: Vector2 = _lay(spot)
	_opponent.global_position = _keeper._net * Vector3(laid.x + side * 1.5, 0.0, laid.y - CLOSING_M)
	_play(SECONDS)


func _play(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds and not _covered:
		_keeper._view.invalidate()
		_keeper._physics_process(DT)
		_goalie._part_velocity_frame = Engine.get_physics_frames() - 1
		_goalie.get_collision_part_velocities()
		_puck._physics_process(DT)
		_puck.drain_contact_events()
		var v: Vector3 = _keeper._net.basis.inverse() * _puck.get_puck_velocity()
		if _cleared == Vector3.ZERO and Vector2(v.x, v.z).length() > CLEARED_M_S:
			_cleared = v
		t += DT


# From a full reset, set on the puck out front, then the puck laid dead at
# `spot` from him in his own frame; where it was laid, net frame.
func _lay(spot: Vector2) -> Vector2:
	_keeper.reset_to_crease()
	_covered = false
	_cleared = Vector3.ZERO
	_opponent.global_position = _keeper._net * Vector3(0.0, 0.0, -30.0)
	var lying: Vector3 = _keeper._net * Vector3(SET_ON.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, SET_ON.y)
	for _i: int in 120:
		_puck.global_position = lying
		_puck.set_puck_velocity(Vector3.ZERO)
		_keeper._view.invalidate()
		_keeper._physics_process(DT)
	var at: Vector3 = Basis(Vector3.UP, _keeper.motor.yaw) * Vector3(spot.x, 0.0, -spot.y) \
			+ Vector3(_keeper.motor.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, _keeper.motor.z)
	_puck.global_position = _keeper._net * at
	_puck.set_puck_velocity(Vector3.ZERO)
	_goalie._part_velocity_frame = -10
	_goalie.get_collision_part_velocities()
	return Vector2(at.x, at.z)

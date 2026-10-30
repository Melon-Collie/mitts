extends GutTest

# Screening in a match (KeeperController): the live keeper, a real skater
# standing between him and the puck. A shot from behind the skater he reads
# later than the same shot with nobody there, by the time the skater hides it
# (GoalieController.screen_delay_for); a skater a little off his line in front
# of a puck in the slot he steps round, until he sees it.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# Net frame (x across, z back into the net).
const SLOT := Vector3(0.0, 0.05, -8.0)
const ON_HIS_LINE := Vector3(0.0, 0.0, -3.5)
const OFF_HIS_LINE := Vector3(0.3, 0.0, -4.5)

var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null
var _skater: Skater = null


func before_each() -> void:
	_goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate() as Goalie
	_puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	_skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	_keeper = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_skater)
	add_child_autofree(_keeper)
	_keeper.setup(_goalie, _puck, GameRules.GOAL_LINE_Z, true)
	_keeper.set_skater_getter(func() -> Array: return [_skater])


func test_a_shot_from_behind_a_body_is_read_later() -> void:
	var clean: float = _read_after(Vector3(0.0, 0.0, -30.0))
	var hidden: float = _read_after(ON_HIS_LINE)
	assert_gt(hidden, clean + DT, "read later behind the body")


func test_a_body_off_his_line_he_steps_round_to_see_the_puck() -> void:
	_settle(OFF_HIS_LINE, 2.0)
	var cfg := GoalieScreenRules.ScreenConfig.new()
	cfg.eye_height = KeeperScreen.eye_height(false)
	assert_true(GoalieScreenRules.hides(OFF_HIS_LINE, Vector3(0.0, 0.0, _keeper.motor.z), SLOT, cfg),
			"square on his angle line, the body would hide it")
	assert_false(_keeper._puck_hidden(), "he sees the puck")
	assert_lt(_keeper.motor.x * signf(OFF_HIS_LINE.x), -0.05, "stepped across, away from the body")
	assert_lte(absf(_keeper.motor.x), KeeperScreen.STEP_MAX_M + 0.05, "no further than half his chest")


# Set on the puck in the slot with the skater at `body`; the seconds from a
# shot along the ice at the middle of the net to his legs' read of it.
func _read_after(body: Vector3) -> float:
	_settle(body, 1.5)
	var start: Vector3 = _keeper._net * SLOT
	var v: Vector3 = (_keeper._net * Vector3(0.0, 0.05, 0.0) - start).normalized() * 25.0
	_puck.global_position = start
	_puck.set_puck_velocity(v)
	_puck.puck_released.emit()
	var t: float = 0.0
	while not _keeper.read.legs_read() and t < 1.0:
		_puck.global_position += v * DT
		_tick()
		t += DT
	return t


func _settle(body: Vector3, seconds: float) -> void:
	_keeper.reset_to_crease()
	_skater.global_position = _keeper._net * body
	var lying: Vector3 = _keeper._net * SLOT
	for _i: int in int(seconds / DT):
		_puck.global_position = lying
		_puck.set_puck_velocity(Vector3.ZERO)
		_tick()


func _tick() -> void:
	_keeper._view.invalidate()
	_keeper._physics_process(DT)

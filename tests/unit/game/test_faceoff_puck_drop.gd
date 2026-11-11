extends GutTest

# The faceoff puck hangs over the dot through the countdown and is thrown down to
# land on the drop: the draw's timing bonus, the bots' swing and the HUD's
# "DROP!" all key off the FACEOFF phase entry, so the puck has to reach the ice
# then, not a fall-time later.

const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0  # a fixed step: the script below is timed in it
const DOT := Vector2(6.7, 20.5)

var _puck: Puck = null
var _sm: GameStateMachine = null
var _coord: PhaseCoordinator = null


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_puck.set_server_mode(true)
	_sm = GameStateMachine.new()
	_coord = PhaseCoordinator.new()
	_coord.setup(
			_sm, PlayerRegistry.new(), [] as Array[Team],
			func() -> Puck: return _puck,
			func() -> Array: return [],
			ShotOnGoalTracker.new(),
			func() -> int: return -1,
			null, null, null,
			null,
			true,
			Callable())


func _tick_puck(ticks: int) -> void:
	for _i: int in ticks:
		_puck._physics_process(DT)


func _height() -> float:
	return _puck.global_position.y - _puck.ice_height


func test_throw_speed_covers_the_height_in_the_time() -> void:
	var h: float = GameRules.FACEOFF_PUCK_HOLD_HEIGHT
	var t: float = GameRules.FACEOFF_PUCK_DROP_TIME
	var v: float = FaceoffDrawRules.drop_throw_speed(h, t, GameRules.GRAVITY_M_S2)
	assert_almost_eq(v * t + 0.5 * GameRules.GRAVITY_M_S2 * t * t, h, 0.0001)
	assert_eq(FaceoffDrawRules.drop_throw_speed(0.1, 1.0, GameRules.GRAVITY_M_S2), 0.0,
			"a fall gravity alone outpaces is never thrown upward")


func test_the_prep_holds_the_puck_over_the_dot() -> void:
	_sm.begin_faceoff_prep(DOT)
	_coord.handle_phase_entered()
	_tick_puck(120)
	assert_true(_puck._held)
	assert_almost_eq(_height(), GameRules.FACEOFF_PUCK_HOLD_HEIGHT, 0.0001,
			"held, not falling")
	assert_almost_eq(Vector2(_puck.global_position.x, _puck.global_position.z), DOT,
			Vector2(0.0001, 0.0001))


func test_the_puck_lands_on_the_drop() -> void:
	_sm.begin_faceoff_prep(DOT)
	_coord.handle_phase_entered()
	_tick_puck(1)
	var ticks: int = 0
	var thrown_early: bool = false
	while _sm.current_phase == GamePhase.Phase.FACEOFF_PREP:
		if _sm.tick(DT):
			_coord.handle_phase_entered()
		_coord.update_faceoff_drop()
		_tick_puck(1)
		ticks += 1
		if _sm.faceoff_prep_time_until_drop() > GameRules.FACEOFF_PUCK_DROP_TIME + DT:
			thrown_early = thrown_early or not _puck._held
	assert_false(thrown_early, "held until the throw")
	assert_false(_puck._held)
	assert_false(_puck.pickup_locked, "live on the drop")
	assert_lt(_height(), GameRules.PUCK_AIRBORNE_HEIGHT_M,
			"on the ice, playable, as the puck goes live")
	assert_true(ticks > int(GameRules.FACEOFF_PREP_DURATION * 120.0) - 2)


func test_a_puck_still_held_at_the_drop_is_thrown_anyway() -> void:
	_sm.begin_faceoff_prep(DOT)
	_coord.handle_phase_entered()
	_tick_puck(1)
	_sm.tick(_sm.faceoff_prep_time_until_drop() + 0.01)  # one hitch past the throw
	assert_eq(_sm.current_phase, GamePhase.Phase.FACEOFF)
	_coord.handle_phase_entered()
	assert_false(_puck._held)
	_tick_puck(12)
	assert_lt(_height(), GameRules.FACEOFF_PUCK_HOLD_HEIGHT, "falling")


func test_a_plain_reset_is_not_held() -> void:
	_puck.reset(DOT, GameRules.FACEOFF_PUCK_HOLD_HEIGHT)
	_puck.reset(DOT)
	_tick_puck(2)
	assert_false(_puck._held)
	assert_almost_eq(_height(), 0.0, 0.0001)

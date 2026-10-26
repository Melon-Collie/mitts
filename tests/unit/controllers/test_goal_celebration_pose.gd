extends GutTest

# The scorer's goal celebration (SkaterShotPoseCoordinator.apply_celebration_pose,
# the window on SkaterController): the stick held up at its own length, the arm
# thrown up, the fist pumped on the knees' hops; nothing posed through the lead
# that keeps it out of the goal clip; nothing of it left on a skater a replay
# drives; and a bot scorer celebrating on the host, where its pose goes on the
# wire.

const DT: float = 1.0 / 120.0
const WINDOW_S: float = 2.0


class StubGameState extends Node:
	var celebrating: bool = false

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func allows_blade_aim_during_lock() -> bool:
		return false

	func is_in_goal_celebration() -> bool:
		return celebrating


var _puck: Puck = null
var _state: StubGameState = null
var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()


func before_each() -> void:
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.global_position = Vector3(20.0, 0.0, 20.0)
	_state = StubGameState.new()
	add_child_autofree(_state)
	_input = InputState.new()
	_input.delta = DT


func _spawn(controller: SkaterController, left_handed: bool = true) -> void:
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.is_left_handed = left_handed
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var attrs := PlayerAttributes.new(73, 201, 1, 1, 1, 1)
	_skater.apply_appearance(attrs)
	_controller = controller
	add_child_autofree(_controller)
	_controller.setup(_skater, _puck, _state)
	_controller.apply_attributes(attrs)


func _tick() -> void:
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)
	_skater._process(DT)


func _arm() -> float:
	return _skater.upper_arm_length + _skater.forearm_length


func _span() -> float:
	return _skater.get_top_hand_position().distance_to(_skater.get_blade_position())


func test_raised_stick_keeps_its_length_through_the_window() -> void:
	_spawn(SkaterController.new())
	for _i: int in 30:
		_tick()
	var stick: float = _controller._ik.solve_stick_length()
	var resting_span: float = _span()
	_controller.start_celebration(WINDOW_S)
	var shortest: float = INF
	for i: int in int(WINDOW_S / DT):
		_tick()
		shortest = minf(shortest, _span())
		if i == int(WINDOW_S / DT) / 2:
			assert_almost_eq(_span(), stick, 0.01,
					"held up, the stick is drawn at its own length")
	assert_gt(shortest, minf(resting_span, stick) - 0.01,
			"the stick never draws shorter than it starts or ends (shortest %.3f m)" % shortest)


func test_stick_arm_is_thrown_up_and_the_fist_pumps() -> void:
	_spawn(SkaterController.new())
	_controller.start_celebration(WINDOW_S)
	var shoulder: Vector3 = _skater.shoulder.position
	var low_fist: float = INF
	var high_fist: float = -INF
	var fist_at_deepest_hop: float = 0.0
	var deepest_pump: float = -1.0
	for i: int in int(WINDOW_S / DT):
		_tick()
		if i < int(SkaterShotPoseCoordinator.CELEBRATION_EASE_S / DT) \
				or i > int((WINDOW_S - SkaterShotPoseCoordinator.CELEBRATION_EASE_S) / DT):
			continue
		var hand: Vector3 = _skater.get_top_hand_position()
		assert_gt(hand.y - shoulder.y, 0.8 * _arm(),
				"the stick hand is overhead, not at the chin")
		var fist: float = _skater.bottom_hand.position.y
		low_fist = minf(low_fist, fist)
		high_fist = maxf(high_fist, fist)
		var pump: float = _controller.celebration_pump()
		if pump > deepest_pump:
			deepest_pump = pump
			fist_at_deepest_hop = fist
	assert_gt(low_fist, _skater.bottom_shoulder.position.y + 0.3 * _arm(),
			"the free fist stays up above the shoulder")
	assert_gt(high_fist - low_fist, 0.1, "the fist pumps (%.3f m)" % (high_fist - low_fist))
	assert_almost_eq(fist_at_deepest_hop, low_fist, 0.02,
			"the fist is drawn in at the bottom of the knees' hop")


func test_the_stick_leans_out_over_its_own_side_for_either_hand() -> void:
	for left_handed: bool in [true, false]:
		_spawn(SkaterController.new(), left_handed)
		_controller.start_celebration(WINDOW_S)
		for _i: int in 60:
			_tick()
		var side: float = signf(_skater.shoulder.position.x)
		var hand: Vector3 = _skater.get_top_hand_position()
		var blade: Vector3 = _skater.get_blade_position()
		assert_gt((hand.x - _skater.shoulder.position.x) * side, 0.0,
				"left-handed %s: the arm goes up on its own side" % left_handed)
		assert_gt((blade.x - hand.x) * side, 0.2,
				"left-handed %s: the shaft leans out, off the helmet" % left_handed)


func test_nothing_is_posed_through_the_lead() -> void:
	_spawn(SkaterController.new())
	for _i: int in 30:
		_tick()
	var lead: float = GoalReplayRules.POST_GOAL_TAIL
	_controller.start_celebration(WINDOW_S, lead)
	var shoulder_y: float = _skater.shoulder.position.y
	for _i: int in int(lead / DT) - 1:
		_tick()
		assert_true(_controller.has_celebration_window())
		assert_false(_controller.is_celebrating(), "the lead poses nothing")
		assert_lt(_skater.get_top_hand_position().y, shoulder_y,
				"the stick stays down through the lead")
	for _i: int in int(0.5 / DT):
		_tick()
	assert_true(_controller.is_celebrating())
	assert_gt(_skater.get_top_hand_position().y, shoulder_y + 0.5 * _arm(),
			"the stick goes up once the lead runs out")


func test_a_replay_ends_a_live_celebration() -> void:
	_spawn(SkaterController.new())
	_controller.start_celebration(WINDOW_S)
	for _i: int in 60:
		_tick()
	assert_gt(_controller._ik._held_free_weight, 0.5, "the fist is up")
	var state := SkaterNetworkState.new()
	_controller.fill_network_state(state)
	_controller.apply_replay_state(state, DT)
	assert_false(_controller.has_celebration_window(),
			"the replayed body is the recorded one, not this window's")
	assert_eq(_controller.celebration_progress(), 0.0)
	assert_eq(_controller._ik._held_free_weight, 0.0, "the free hand is back on the stick")


func test_a_bot_scorer_celebrates_on_the_host() -> void:
	var bot := AIController.new()
	_spawn(bot)
	_state.celebrating = true
	_controller.start_celebration(WINDOW_S)
	var shoulder_y: float = _skater.shoulder.position.y
	for _i: int in int(0.75 / DT):
		assert_false(bot.begin_tick(DT), "a celebrating bot makes no decision")
		_skater._physics_process(DT)
		_skater._process(DT)
	assert_true(_controller.is_celebrating(), "the window ages on the bot's own tick")
	assert_gt(_controller.celebration_progress(), 0.3)
	assert_gt(_skater.get_top_hand_position().y, shoulder_y + 0.5 * _arm(),
			"the bot's stick goes up, where the wire carries it to clients")


func test_a_bot_that_did_not_score_is_left_alone() -> void:
	var bot := AIController.new()
	_spawn(bot)
	_state.celebrating = true
	var hand_before: Vector3 = _skater.get_top_hand_position()
	for _i: int in 30:
		bot.begin_tick(DT)
	assert_eq(_skater.get_top_hand_position(), hand_before,
			"a bot without a window is not posed through the beat")

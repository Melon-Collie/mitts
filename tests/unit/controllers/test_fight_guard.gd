extends GutTest

# The gloves off (FightRules.Role.FIGHTING): the guard owns the hands — the top
# fist at FightGuardRules' guard, eased up into it, the blade marker parked
# under it — and the shot machine stands down; the stick is hidden, the hands
# drawn bare, and the stick and both gloves drop to the ice and lie there until
# the gloves go back on (SkaterDroppedGear).

const DT: float = 1.0 / 120.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func allows_blade_aim_during_lock() -> bool:
		return false

	func is_in_goal_celebration() -> bool:
		return false


var _puck: Puck = null
var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()


func before_each() -> void:
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.global_position = Vector3(20.0, 0.0, 20.0)
	var state := StubGameState.new()
	add_child_autofree(state)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var attrs := PlayerAttributes.new(73, 201, 1, 1, 1, 1)
	_skater.apply_appearance(attrs)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, _puck, state)
	_controller.apply_attributes(attrs)
	_input = InputState.new()
	_input.delta = DT
	_input.mouse_world_pos = _skater.global_position + Vector3(0.0, 0.0, -2.0)


func _tick(n: int = 1) -> void:
	for i: int in n:
		_controller._process_input(_input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)


func test_the_guard_rules_hold_the_fists_up_in_front_inside_the_shoulders() -> void:
	var shoulder := Vector3(0.2, 0.45, 0.0)
	var hand: Vector3 = FightGuardRules.guard_hand(shoulder)
	assert_lt(hand.z, shoulder.z, "in front of the shoulder")
	assert_gt(hand.y, shoulder.y, "above it, at the chin")
	assert_true(absf(hand.x) < absf(shoulder.x) and signf(hand.x) == signf(shoulder.x),
			"inside the shoulder, on its own side")
	var blade: Vector3 = FightGuardRules.parked_blade(hand)
	assert_almost_eq(blade.distance_to(hand), FightGuardRules.PARKED_BLADE_M, 1e-5)
	assert_lt(blade.y, hand.y, "the parked blade hangs under the fist: a thumb-up fist")


func test_the_hands_come_up_into_the_guard() -> void:
	_tick(30)
	var holding: Vector3 = _skater.get_top_hand_position()
	_skater.fight_role = FightRules.Role.FIGHTING
	_tick(1)
	var guard: Vector3 = FightGuardRules.guard_hand(_controller._ik.arm_shoulder())
	assert_gt(_skater.get_top_hand_position().distance_to(guard), 0.05,
			"eased in, not snapped there on the tick the gloves came off")
	assert_true(_skater.get_top_hand_position().distance_to(holding)
			< guard.distance_to(holding), "on its way from where it held the stick")
	_tick(ceili(FightGuardRules.EASE_S / DT) + 2)
	guard = FightGuardRules.guard_hand(_controller._ik.arm_shoulder())
	assert_almost_eq(_skater.get_top_hand_position().distance_to(guard), 0.0, 0.01,
			"then held there")
	assert_almost_eq(_skater.get_blade_position().distance_to(
			FightGuardRules.parked_blade(_skater.get_top_hand_position())), 0.0, 0.01)


func test_no_shot_is_begun_and_none_carries_on() -> void:
	_input.slap_pressed = true
	_input.slap_held = true
	_tick(1)
	_input.slap_pressed = false
	_tick(5)
	assert_eq(_controller.get_shot_state(), SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK,
			"a puckless wind-up before the fight")
	_skater.fight_role = FightRules.Role.FIGHTING
	_tick(1)
	assert_eq(_controller.get_shot_state(), SkaterStateMachine.State.SKATING_WITHOUT_PUCK,
			"called off as the gloves come off")
	_input.shoot_pressed = true
	_input.shoot_held = true
	_tick(3)
	assert_eq(_controller.get_shot_state(), SkaterStateMachine.State.SKATING_WITHOUT_PUCK,
			"and nothing new starts")


func test_the_stick_and_gloves_drop_and_lie_on_the_ice_until_the_fight_is_over() -> void:
	_tick(10)
	assert_true(_skater.stick_mesh.visible)
	_skater.fight_role = FightRules.Role.FIGHTING
	_tick(1)
	assert_false(_skater.stick_mesh.visible, "the stick in hand is hidden")
	assert_false(_skater.blade_mesh_instance().visible)
	assert_eq(_skater._dropped_gear.piece_count(), 3, "the stick and both gloves")
	_tick(roundi(2.0 / DT))
	for piece: SkaterDroppedGear.Piece in _skater._dropped_gear._pieces:
		assert_true(piece.landed, "down on the ice")
		assert_almost_eq(piece.node.global_position.y, piece.rest_y, 1e-4)
		assert_eq(piece.velocity, Vector3.ZERO, "slid to a stop")
	_skater.fight_role = FightRules.Role.NONE
	_tick(1)
	assert_eq(_skater._dropped_gear.piece_count(), 0, "picked up when it is over")
	assert_true(_skater.stick_mesh.visible, "and back in his hands")


func test_the_off_hand_comes_up_into_the_guard_too() -> void:
	_skater.fight_role = FightRules.Role.FIGHTING
	_tick(ceili(FightGuardRules.EASE_S / DT) + 30)
	var bottom: Vector3 = _skater.bottom_hand.position
	assert_lt(bottom.z, _skater.bottom_shoulder.position.z, "in front of its shoulder")
	assert_gt(bottom.y, _skater.bottom_shoulder.position.y, "and up at the chin")

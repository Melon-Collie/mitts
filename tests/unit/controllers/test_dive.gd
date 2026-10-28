extends GutTest

# The dive through the real controller (SkaterController): stance + block from
# puckless skating puts the skater down on the knockdown's rail for DiveRules
# .DOWN_S with no velocity of its own — he slides on the way he was going — laid
# out toward the cursor with his stick along the ice; a block held through the
# get-up becomes the standing block, never a second dive.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = 1.0 / 120.0  # a fixed step: the script below is timed in it


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _c: SkaterController = null


func before_each() -> void:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var puck: Puck = (preload("res://Scenes/Puck.tscn").instantiate()) as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_c = SkaterController.new()
	add_child_autofree(_c)
	_c.setup(skater, puck, gs)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)


func _dive_input(stance: bool, block: bool, cursor: Vector3) -> InputState:
	var input := InputState.new()
	input.stance_held = stance
	input.block_held = block
	input.mouse_world_pos = cursor
	input.delta = DT
	return input


func _skate(ticks: int) -> void:
	for _i: int in ticks:
		var input := _dive_input(false, false, _c.skater.global_position + Vector3(0, 0, -3))
		input.move_vector = Vector2(0.0, -1.0)
		_c._process_input(input, DT)


func test_shift_and_c_dive_and_slide_on_without_a_lunge() -> void:
	_skate(90)
	var before: Vector3 = _c.skater.velocity
	assert_gt(before.length(), 3.0, "the control: he is skating")
	_c._process_input(_dive_input(true, true, _c.skater.global_position + Vector3(3, 0, 0)), DT)
	assert_true(_c.skater.is_diving)
	assert_true(_c.skater.is_knocked_down, "down on the knockdown's rail")
	assert_almost_eq(_c.knockdown_timer, DiveRules.DOWN_S - DT, 1e-4)
	assert_lte(_c.skater.velocity.length(), before.length() + 1e-4, "no lunge")
	assert_gt(_c.skater.velocity.normalized().dot(before.normalized()), 0.999,
			"he slides on the way he was going")
	assert_almost_eq(_c.skater.dive_layout.x, 1.0, 0.05, "laid out toward the cursor")


func test_the_stick_lies_out_along_the_layout() -> void:
	_c._process_input(_dive_input(true, true, _c.skater.global_position + Vector3(3, 0, 0)), DT)
	for _i: int in 30:
		_c._process_input(_dive_input(true, true, _c.skater.global_position + Vector3(3, 0, 0)), DT)
	var contact: Vector3 = _c.skater.get_blade_contact_global()
	var blade: Vector3 = contact - _c.skater.global_position
	assert_gt(blade.x, _c.stick_length, "the blade is out past a stick's length, along the layout")
	assert_lt(contact.y, 0.1, "flat on the ice")


func test_block_held_keeps_him_down_and_letting_go_gets_him_up() -> void:
	_dive_ticks(ceili(3.0 * DiveRules.DOWN_S / DT))
	assert_true(_c.skater.is_diving, "still down three windows in, block held")
	assert_almost_eq(_c.knockdown_timer, _c.knockdown_getup_seconds, 1e-6,
			"held where the get-up would begin")
	for _i: int in ceili(_c.knockdown_getup_seconds / DT) + 1:
		_c._process_input(_dive_input(false, false, _c.skater.global_position + Vector3(3, 0, 0)), DT)
	assert_false(_c.skater.is_knocked_down, "let go, he gets up over the get-up")


func test_letting_go_early_still_spends_the_whole_dive() -> void:
	_dive_ticks(1)
	for _i: int in ceili((DiveRules.DOWN_S - _c.knockdown_getup_seconds) / DT) - 2:
		_c._process_input(_dive_input(false, false, _c.skater.global_position + Vector3(3, 0, 0)), DT)
	assert_true(_c.skater.is_diving, "a dive is at least DOWN_S, whatever the button does")


func test_the_belt_keeps_his_line_and_the_skates_go_out_the_far_side() -> void:
	_skate(90)
	_dive_ticks(60)
	assert_almost_eq(_c.knockdown_fall_tilt(), deg_to_rad(DiveRules.LIE_DEG), 1e-4,
			"the control: lying")
	var root: Transform3D = _c.skater.mesh_root.global_transform
	# MeshRoot's local frame is the standing figure's, its origin the skater's.
	var ice_y: float = -_c.skater.global_position.y
	var belt: Vector3 = root * Vector3(0.0, ice_y + DiveRules.COM_HEIGHT_M, 0.0) \
			- _c.skater.global_position
	var skates: Vector3 = root * Vector3(0.0, ice_y, 0.0) - _c.skater.global_position
	assert_almost_eq(belt.x, 0.0, 0.05, "his belt lies over the line he was skating")
	assert_almost_eq(skates.x, -DiveRules.feet_back_m(), 0.05, "his skates out the far side")


func test_c_alone_still_blocks_standing() -> void:
	_c._process_input(_dive_input(false, true, _c.skater.global_position + Vector3(0, 0, -3)), DT)
	assert_false(_c.skater.is_diving)
	assert_eq(_c._sm.get_state(), SkaterStateMachine.State.SHOT_BLOCKING)


func test_a_carrier_does_not_dive() -> void:
	_c.has_puck = true
	_c._sm.set_state(SkaterStateMachine.State.SKATING_WITH_PUCK)
	_c._process_input(_dive_input(true, true, _c.skater.global_position + Vector3(3, 0, 0)), DT)
	assert_false(_c.skater.is_diving)


func _dive_ticks(ticks: int) -> void:
	for _i: int in ticks:
		_c._process_input(_dive_input(true, true, _c.skater.global_position + Vector3(3, 0, 0)), DT)


func test_the_dive_lands_and_lies_still_until_the_get_up() -> void:
	_skate(90)
	var lie: float = deg_to_rad(DiveRules.LIE_DEG)
	var prev: float = 0.0
	var landed_at: float = -1.0
	var ticks: int = ceili((DiveRules.DOWN_S - _c.knockdown_getup_seconds) / DT) - 1
	for i: int in ticks:
		_dive_ticks(1)
		var tilt: float = _c.knockdown_fall_tilt()
		assert_gte(tilt, prev - 1e-5, "no rebound off the ice (tick %d)" % i)
		prev = tilt
		if landed_at < 0.0 and is_equal_approx(tilt, lie):
			landed_at = (i + 1) * DT
	assert_gt(landed_at, 0.0, "he reaches the ice")
	assert_lt(landed_at, 0.4, "a thrown fall, on the ice early enough to lie there")


func test_the_dive_goes_down_long_not_crumpled() -> void:
	_skate(90)
	_dive_ticks(8)
	assert_eq(_c.knockdown_drop_m(), 0.0, "no buckle: the legs stay long off the skates")
	assert_lt(_c.knockdown_fold_rad(), deg_to_rad(3.0),
			"no curl leaving the skates (a hit curls knockdown_fold_deg)")
	_dive_ticks(50)
	assert_almost_eq(_c.knockdown_fold_rad(), PI / 2.0 - _c.knockdown_fall_tilt(), 1e-4,
			"on the ice the trunk lies flat")


func test_the_lean_settles_while_down() -> void:
	_skate(40)
	var lean: float = _c.skater.balance_tilt().length()
	assert_gt(lean, deg_to_rad(5.0), "the control: leaning into the start")
	_dive_ticks(ceili(DiveRules.DOWN_S / DT) - 2)
	assert_lt(_c.skater.balance_tilt().length(), deg_to_rad(4.0),
			"the slide's friction tips nothing: the lean has settled by the get-up")


func test_the_top_hand_stays_off_the_ice() -> void:
	_skate(90)
	for i: int in ceili((DiveRules.DOWN_S - _c.knockdown_getup_seconds) / DT):
		_dive_ticks(1)
		var hand: Vector3 = _c.skater.upper_body_to_global(_c.skater.get_top_hand_position())
		assert_gte(hand.y, DiveRules.HAND_HEIGHT_M * 0.5, "tick %d" % i)


func test_the_slide_carries_its_momentum_through_the_window() -> void:
	_skate(90)
	var before: float = _c.skater.velocity.length()
	_dive_ticks(ceili(1.0 / DT))
	assert_true(_c.skater.is_knocked_down, "the control: still down")
	assert_gt(_c.skater.velocity.length(), before - 2.5,
			"gear on ice takes a couple of m/s over the second down, not the whole slide")

extends GutTest

# The get-up, through the real controller and the live rig: a downed skater
# comes up onto both knees, steps the free leg up onto its skate, and stands off
# that knee (KnockdownFallRules.lie_share and siblings, GaitKnockdownLayer) —
# then skates staggered for a moment, a hit and a dive alike. Measured through
# the render pass that applies the pose, as test_knockdown_lies_on_the_ice does.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
const LegBone = SkaterMeshBuilder.LegBone


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


# Ticks (and renders) until the down timer has run down to `timer` seconds.
func _run_down_to(timer: float, input: InputState = InputState.new()) -> void:
	while _controller.knockdown_timer > timer:
		input.delta = DT
		_controller._process_input(input, DT)
		_controller._render_pose_update(DT)


# The timer at which `share` of the get-up tail has gone.
func _tail_at(share: float) -> float:
	return _controller.knockdown_getup_seconds * (1.0 - share) - 1e-4


# World height of a bone's origin above the ice, composed by hand (the
# skeleton's own global_transform is stale in a hand-ticked harness).
func _height(bone: int) -> float:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var local: Vector3 = _skater.mesh_root.transform * (body.transform
			* body.get_bone_global_pose(bone).origin)
	return (_skater.global_transform * local).y


func _leg(bone: int) -> int:
	return SkaterBodySkeleton.LEG_BONE_OFFSET + bone


func _report(label: String) -> void:
	gut.p("%s: helmet %.2f pelvis %.2f knees %.2f / %.2f skates %.2f / %.2f" % [label,
			_height(UpperBone.HELMET), _height(UpperBone.PELVIS),
			_height(_leg(LegBone.KNEE_L)), _height(_leg(LegBone.KNEE_R)),
			_height(_leg(LegBone.FOOT_L)), _height(_leg(LegBone.FOOT_R))])


func test_a_hit_gets_up_onto_his_knees_then_one_knee() -> void:
	# Shoved toward +X: he lands on his right side, so the left leg is free.
	_controller._on_body_check_received(Vector3(3.0, 0.0, 0.0))
	_run_down_to(_tail_at(KnockdownFallRules.GETUP_KNEES_END))
	_report("on his knees")
	assert_almost_eq(_controller.knockdown_fall_tilt(), 0.0, 1e-4, "upright off the ice")
	assert_lt(_height(_leg(LegBone.KNEE_L)), 0.15, "the left knee is on the ice")
	assert_lt(_height(_leg(LegBone.KNEE_R)), 0.15, "the right knee is on the ice")
	assert_gt(_height(UpperBone.HELMET), 0.9, "kneeling, not lying")
	_run_down_to(_tail_at(KnockdownFallRules.GETUP_STEP_END))
	_report("on one knee")
	assert_gt(_height(_leg(LegBone.KNEE_L)), 0.3, "the free leg has stepped up")
	assert_lt(_height(_leg(LegBone.KNEE_R)), 0.15, "the leg he fell onto is still down")
	assert_lt(_height(_leg(LegBone.FOOT_L)), 0.2, "its skate on the ice in front of him")
	_run_down_to(0.0)
	_controller._render_pose_update(DT)
	_report("up")
	assert_gt(_height(_leg(LegBone.KNEE_R)), 0.3, "both skates under him")


func test_the_leg_he_fell_onto_is_the_one_that_stays_down() -> void:
	_controller._on_body_check_received(Vector3(-3.0, 0.0, 0.0))
	_run_down_to(_tail_at(KnockdownFallRules.GETUP_STEP_END))
	assert_gt(_height(_leg(LegBone.KNEE_R)), 0.3, "fell to his left, the right leg steps up")
	assert_lt(_height(_leg(LegBone.KNEE_L)), 0.15)


func test_a_hit_gets_up_staggered_leaning_forward() -> void:
	_controller._on_body_check_received(Vector3(0.0, 0.0, 3.0))
	_run_down_to(DT * 1.5)
	assert_eq(_controller.stagger_timer, 0.0, "the hit's own stagger ran out while he was down")
	_run_down_to(0.0)
	assert_almost_eq(_controller.stagger_timer,
			_controller.knockdown_getup_stagger_seconds - DT, 1e-4,
			"back on his skates he finds his legs")
	assert_eq(_controller.stagger_recoil_dir, Vector2(0.0, -1.0),
			"leaning forward over them, whichever way he fell")


func test_a_dive_gets_up_staggered_too() -> void:
	var dive := InputState.new()
	dive.stance_held = true
	dive.block_held = true
	dive.mouse_world_pos = _skater.global_position + Vector3(3.0, 0.0, 0.0)
	dive.delta = DT
	_controller._process_input(dive, DT)
	assert_true(_skater.is_diving, "the control: down in a dive")
	_run_down_to(0.0)
	assert_gt(_controller.stagger_timer, 0.0, "up from a dive he finds his legs as well")


func test_spamming_the_dive_buys_one_per_window() -> void:
	var dive := InputState.new()
	dive.stance_held = true
	dive.block_held = true
	var dives: int = 0
	var was_diving: bool = false
	var ticks: int = roundi(5.0 / DT)
	for i: int in ticks:
		# Both buttons mashed: down every other tick, so a held block never
		# keeps him lying there.
		var mash: bool = i % 2 == 0
		dive.stance_held = mash
		dive.block_held = mash
		dive.mouse_world_pos = _skater.global_position + Vector3(3.0, 0.0, 0.0)
		dive.delta = DT
		_controller._process_input(dive, DT)
		if _skater.is_diving and not was_diving:
			dives += 1
		was_diving = _skater.is_diving
	assert_eq(dives, ceili(5.0 / DiveRules.DOWN_S),
			"five seconds of mashing is a dive every DOWN_S (%.1f s), the get-up included" \
			% DiveRules.DOWN_S)


# Where the blade is on one knee, the cursor held at `cursor` (offset from him).
func _blade_on_one_knee(cursor: Vector3) -> Vector3:
	_controller._on_body_check_received(Vector3(3.0, 0.0, 0.0))
	var input := InputState.new()
	input.mouse_world_pos = _skater.global_position + cursor
	_run_down_to(_tail_at(KnockdownFallRules.GETUP_STEP_END), input)
	return _skater.get_blade_contact_global() - _skater.global_position


func test_the_stick_is_held_out_front_through_the_kneel() -> void:
	var right: Vector3 = _blade_on_one_knee(Vector3(4.0, 0.0, 0.0))
	before_each()
	var left: Vector3 = _blade_on_one_knee(Vector3(-4.0, 0.0, 4.0))
	assert_lt(right.distance_to(left), 0.02,
			"the cursor doesn't wave the stick while he gets up (%s vs %s)" % [right, left])
	var forward: Vector3 = -_skater.global_transform.basis.z
	assert_gt(left.dot(forward), 0.8, "the blade is out in front of him")
	assert_lt(left.y + _skater.global_position.y, 0.1, "on the ice")


func test_a_divers_stick_goes_dead_as_he_starts_to_get_up() -> void:
	var dive := InputState.new()
	dive.stance_held = true
	dive.block_held = true
	dive.mouse_world_pos = _skater.global_position + Vector3(3.0, 0.0, 0.0)
	dive.delta = DT
	_controller._process_input(dive, DT)
	_run_down_to(_controller.knockdown_getup_seconds + 0.05, dive)
	assert_true(_skater.dive_laid_out, "the control: laid out, his stick plays")
	for _i: int in 240:
		_controller._process_input(dive, DT)
	assert_true(_skater.dive_laid_out, "block held, he lies there and it still plays")
	_run_down_to(_controller.knockdown_getup_seconds - 0.01)
	assert_true(_skater.is_knocked_down, "the control: still down")
	assert_false(_skater.dive_laid_out, "getting up, it is as dead as anyone's")

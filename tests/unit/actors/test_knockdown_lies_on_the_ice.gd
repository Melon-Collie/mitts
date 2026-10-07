extends GutTest

# Where the knockdown fall puts the body. KnockdownFallRules models a rod
# tipping about the skates on the ice, so the tilt must pivot there — not at
# the skater's origin, which rides at hip height (GameRules.FACEOFF_SPAWN_HEIGHT).
# Measured on the live rig, through the render pass that applies the tilt.

const DT: float = 1.0 / 120.0
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


func _knock_down(impulse: Vector3, ticks: int) -> void:
	_controller._on_body_check_received(impulse)
	var input := InputState.new()
	for _i: int in ticks:
		_controller._process_input(input, DT)
		_controller._render_pose_update(DT)


# World height of a bone's origin above the ice. Composed by hand: the
# skeleton's own global_transform is stale in a hand-ticked harness.
func _bone_height(bone: int) -> float:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var local: Vector3 = _skater.mesh_root.transform * (body.transform
			* body.get_bone_global_pose(bone).origin)
	return (_skater.global_transform * local).y


func _report(label: String) -> Dictionary:
	var off: int = SkaterBodySkeleton.LEG_BONE_OFFSET
	var h: Dictionary = {
		"helmet": _bone_height(UpperBone.HELMET),
		"pelvis": _bone_height(UpperBone.PELVIS),
		"skate_l": _bone_height(off + LegBone.FOOT_L),
		"skate_r": _bone_height(off + LegBone.FOOT_R),
	}
	gut.p("%s: helmet %.2f pelvis %.2f skates %.2f / %.2f m above the ice" % [
			label, h["helmet"], h["pelvis"], h["skate_l"], h["skate_r"]])
	return h


func test_upright_skates_stand_on_the_ice() -> void:
	_controller._render_pose_update(DT)
	var h: Dictionary = _report("upright")
	assert_lt(absf(h["skate_l"] - h["skate_r"]), 0.02, "level stance")


func test_a_body_shoved_sideways_lies_on_the_ice() -> void:
	_controller._render_pose_update(DT)
	var upright: Dictionary = _report("upright")
	_knock_down(Vector3(3.0, 0.0, 0.0), 100)
	var h: Dictionary = _report("lying, shoved sideways")
	assert_lt(h["pelvis"], 0.45, "the hips are down on the ice")
	assert_lt(h["helmet"], 0.45, "the head is down on the ice")
	assert_gt(h["pelvis"], -0.05, "and not through it")
	assert_gt(h["helmet"], -0.05, "and not through it")
	assert_lt(minf(h["skate_l"], h["skate_r"]), upright["skate_l"] + 0.35,
			"the skates stay near the ice they tipped about")


func test_a_body_shoved_backward_lies_on_the_ice() -> void:
	_knock_down(Vector3(0.0, 0.0, 3.0), 100)
	var h: Dictionary = _report("lying, shoved backward")
	assert_lt(h["pelvis"], 0.45, "the hips are down on the ice")
	assert_lt(h["helmet"], 0.45, "the head is down on the ice")
	assert_gt(h["helmet"], -0.05, "and not through it")


func test_mid_fall_the_skates_stay_planted() -> void:
	_controller._render_pose_update(DT)
	var upright: Dictionary = _report("upright")
	_knock_down(Vector3(3.0, 0.0, 0.0), 30)
	var h: Dictionary = _report("mid-fall")
	assert_lt(maxf(h["skate_l"], h["skate_r"]), upright["skate_l"] + 0.25,
			"a body tipping about its skates does not lift them")

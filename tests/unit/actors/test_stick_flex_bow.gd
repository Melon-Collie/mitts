extends GutTest

# The shaft's cosmetic bow is anchored where the stick is held — the rigid hosel
# and the top hand — and the drawn bottom glove rides it. The shader draws the
# curve on the GPU and SkaterStickRig.bow_profile on the CPU, so the profile's
# formula is checked against the shader source here.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const SHADER_PATH: String = "res://Shaders/stick_flex.gdshader"


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


func _make_controller() -> SkaterController:
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
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, gs)
	controller.apply_attributes(PlayerAttributes.neutral())
	return controller


func test_profile_is_held_at_both_ends() -> void:
	assert_almost_eq(SkaterStickRig.bow_profile(0.0), 0.0, 1e-6, "no offset at the hosel")
	assert_almost_eq(SkaterStickRig.bow_profile(1.0), 0.0, 1e-6, "no offset at the top hand")
	assert_almost_eq(SkaterStickRig.bow_profile(0.5), 1.0, 1e-6, "peak = flex_m mid-span")
	# Zero slope at both anchors, so the shaft leaves the hosel and the glove
	# straight rather than kinking against them.
	var h: float = 0.001
	assert_lt(SkaterStickRig.bow_profile(h) / h, 0.05, "flat off the hosel")
	assert_lt(SkaterStickRig.bow_profile(1.0 - h) / h, 0.05, "flat into the top hand")
	assert_almost_eq(SkaterStickRig.bow_profile(-0.3), 0.0, 1e-6, "below the hosel is unbent")
	assert_almost_eq(SkaterStickRig.bow_profile(1.3), 0.0, 1e-6, "the butt above the hand is unbent")


func test_shader_draws_the_same_curve() -> void:
	var src: String = FileAccess.get_file_as_string(SHADER_PATH)
	assert_true(src.contains("uniform float tip_t"), "the hosel anchor is a uniform")
	assert_true(src.contains("uniform float hand_t"), "the top-hand anchor is a uniform")
	assert_true(src.contains("float w = u * (1.0 - u);")
			and src.contains("VERTEX.x += flex_m * 16.0 * w * w;"),
			"the vertex bow is bow_profile's 16·u²(1−u)²")


func test_bottom_glove_rides_the_bow() -> void:
	var c := _make_controller()
	var skater: Skater = c.skater
	skater.update_stick_mesh()
	skater.current_shot_state = SkaterStateMachine.State.WRISTER_AIM
	skater.shot_charge = 1.0
	# The bow eases toward its target; settle it. update_flex reads the axis
	# update_mesh solved, so re-pose between steps like the render pass does.
	for _i: int in 120:
		skater.update_stick_mesh()
		skater._stick.update_flex(1.0 / 60.0)
	var top: Vector3 = skater.top_hand.position
	# Grip the shaft a quarter of the way down, as the bottom-hand IK does (the
	# static rig never runs that solve).
	var bottom: Vector3 = top.lerp(skater.blade.position, c.bottom_hand_grip_fraction)
	assert_lt(skater.stick_bow_offset(top).length(), 0.005,
			"the shaft stays in the top glove")
	var at_bottom: Vector3 = skater.stick_bow_offset(bottom)
	assert_gt(at_bottom.length(), 0.01, "the bow reaches the bottom hand under load")
	assert_lt(at_bottom.length(), skater.stick_flex_max_m + 0.001,
			"never past the peak bow")
	var far: Vector3 = bottom + Vector3(0.0, 0.6, 0.0)
	assert_eq(skater.stick_bow_offset(far), Vector3.ZERO,
			"a hand off the stick does not ride it")

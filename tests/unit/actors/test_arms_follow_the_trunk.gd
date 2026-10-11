extends GutTest

# Every drawn frame the arms root on the shoulders the trunk is drawn with
# (SkaterArmRig.arm_root), even on a frame where only the body moved: a crouch
# easing in from a standstill moves the spine and nothing gameplay reads.

const DT: float = 1.0 / 120.0
const UpperBone = SkaterMeshBuilder.UpperBone
# The arm root sits on the shoulder to float precision; a frame the arm missed
# leaves it a crouch step behind (millimetres).
const ROOT_TOL_M: float = 0.0005


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func test_the_arms_follow_a_crouch_at_a_standstill() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(2.0, GameRules.FACEOFF_SPAWN_HEIGHT, 8.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, state)
	controller.set_process(false)
	controller.set_physics_process(false)
	for _i: int in 120:
		skater._process(DT)
	controller.stance_active = true
	var body: Skeleton3D = skater._arms._skeleton
	var worst: float = 0.0
	var sank: float = skater.body_drop_below_frame()
	for _i: int in 60:
		skater._process(DT)
		var want: Vector3 = skater._arms.arm_root(skater.shoulder.position, skater.top_hand.position)
		# The bone spans shoulder to elbow about its centre, −Z toward the elbow
		# and Z scaled to the span, so the shoulder end is half of +Z out.
		var upper: Transform3D = body.get_bone_global_pose(UpperBone.TOP_UPPER_ARM)
		var got: Vector3 = upper.origin + upper.basis.z * 0.5
		worst = maxf(worst, got.distance_to(want))
	sank = skater.body_drop_below_frame() - sank
	gut.p("stance from a standstill: body sank %.3f m, arm root off its shoulder by at most %.4f m"
			% [sank, worst])
	assert_gt(sank, 0.02, "the stance crouches the body")
	assert_lt(worst, ROOT_TOL_M, "the arm stays on the shoulder as the body sinks")

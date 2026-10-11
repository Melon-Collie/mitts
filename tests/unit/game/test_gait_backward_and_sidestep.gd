extends GutTest

# The backward C-cut and the side-step, measured where they are drawn.
#  - Skating backward, each push sweeps out from under its hip and ahead of the
#    hips (the body moving away from it), drawing the C out front.
#  - The side-step scissors the skates sideways, half a cycle apart, lifting a
#    skate as it steps toward the travel and pushing it back along the ice.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const LegBone = SkaterMeshBuilder.LegBone
const DT: float = 1.0 / 120.0
const WARMUP_TICKS: int = 300
const MEASURE_TICKS: int = 240


func _coord() -> SkaterSkatingCoordinator:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var controller: SkaterController = SkaterController.new()
	autofree(controller)
	var coord := SkaterSkatingCoordinator.new()
	coord.setup(skater, SkaterStateMachine.new(), controller)
	skater.set_facing(Vector2(0.0, -1.0))
	return coord


func test_a_c_cut_sweeps_out_and_ahead_of_the_hips() -> void:
	var coord := _coord()
	var skater: Skater = coord._skater
	# Facing up-ice, travelling down it with the stick held back.
	skater.velocity = Vector3(0.0, 0.0, 6.0)
	skater.move_intent = Vector2(0.0, 1.0)
	for _i: int in WARMUP_TICKS:
		coord.apply(DT)
	var out: float = 0.0
	var ahead: float = 0.0
	var sk: Skeleton3D = skater._legs._skeleton
	for _i: int in MEASURE_TICKS:
		coord.apply(DT)
		for bone: int in [LegBone.FOOT_L, LegBone.FOOT_R]:
			var at: Vector3 = sk.get_bone_global_pose(SkaterLegRig._OFFSET + bone).origin
			out = maxf(out, absf(at.x) - GaitPose.HIP_HALF_WIDTH)
			ahead = maxf(ahead, -at.z)
	gut.p("c-cut: backward %.2f, out %.2f m past the hip, %.2f m ahead"
			% [coord.locomotion_mix().backward, out, ahead])
	assert_gt(coord.locomotion_mix().backward, 0.9, "skating backward")
	assert_gt(out, 0.08, "the push sweeps out")
	assert_gt(ahead, 0.15, "and ahead of the hips")


func test_a_side_step_lifts_toward_the_travel_and_pushes_away() -> void:
	var loco: SkaterLocomotion = _coord()._locomotion
	loco.mix.clear()
	loco.mix.shuffle = 1.0
	loco.mix.side = 1.0
	loco.intensity = 0.6
	loco.push_scale = 1.0
	var prev_x: float = 0.0
	var lifted_toward: int = 0
	var lifted_away: int = 0
	var span := Vector2(INF, -INF)
	for i: int in 64:
		loco.stride_phase = TAU * float(i) / 64.0
		loco.strokes(DT, Vector2.ZERO)
		if i > 0 and loco.l_dy > 0.005:
			if loco.l_dx > prev_x:
				lifted_toward += 1
			else:
				lifted_away += 1
		prev_x = loco.l_dx
		span = Vector2(minf(span.x, loco.l_dx), maxf(span.y, loco.l_dx))
	gut.p("side-step: skate swings %.2f..%.2f m, lifted %d samples stepping right, %d stepping left"
			% [span.x, span.y, lifted_toward, lifted_away])
	assert_gt(span.y - span.x, 0.12, "the skate scissors sideways")
	assert_gt(lifted_toward, 0, "it lifts stepping toward the travel")
	assert_eq(lifted_away, 0, "and pushes back away from it along the ice")

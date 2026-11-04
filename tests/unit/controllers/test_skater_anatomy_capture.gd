extends GutTest

# The anatomy model read off a built skater (SkaterAnatomyCapture) holds the
# body the rig draws: its trunk, folded, leaned and twisted as a settled carry
# has it, puts both shoulders and the jersey where the skeleton does. And the
# search over it holds a carry a body can, as players hold it too, and names the
# arm's reach for a blade no arm reaches.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const NEAR_M: float = 0.005


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _make() -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater._process(DT)
	return c


# A carry with the cursor at `cursor` (facing frame, m), skating or standing.
func _carry(c: SkaterController, cursor: Vector2, skating: bool) -> void:
	var skater: Skater = c.skater
	c.has_puck = true
	c._sm.set_state(SkaterStateMachine.State.SKATING_WITH_PUCK)
	for _i: int in 150:
		skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		if not skating:
			skater.velocity = Vector3.ZERO
		c._pose.facing = Vector2(0.0, -1.0)
		skater.set_facing(c._pose.facing)
		var input := InputState.new()
		input.delta = DT
		input.move_vector = Vector2(0.0, -1.0) if skating else Vector2.ZERO
		input.mouse_world_pos = skater.global_position + Vector3(cursor.x, 0.0, cursor.y)
		input.mouse_world_pos.y = 0.0
		skater.capture_prev_blade_contact()
		c._process_input(input, DT)
		skater._physics_process(DT)
		skater._process(DT)


func test_the_models_trunk_puts_the_shoulders_and_jersey_where_the_rig_draws_them() -> void:
	var c: SkaterController = _make()
	var skater: Skater = c.skater
	var body: ArmAnatomyBody = SkaterAnatomyCapture.capture(c)
	assert_almost_eq(body.top_shoulder.x, -body.bottom_shoulder.x, 0.001, "shoulders either side")
	var forehand: float = signf(body.bottom_shoulder.x)
	for skating: bool in [false, true]:
		# Round the forehand far enough to twist the trunk.
		_carry(c, Vector2(1.0 * forehand, -0.6), skating)
		var what: String = "skating" if skating else "standing"
		var trunk: ArmAnatomySearch.TrunkState = SkaterAnatomyCapture.trunk_state(skater, body)
		var twist: float = clampf(angle_difference(skater.drawn_lower_body_rotation().y,
				skater.drawn_upper_body_rotation().y), -SkaterSpineRig.TWIST_LIMIT,
				SkaterSpineRig.TWIST_LIMIT)
		assert_gt(absf(twist), deg_to_rad(10.0), what + ": the trunk is twisted")
		var chest: Basis = ArmAnatomySearch.spine_basis(trunk, twist)
		var skel: Skeleton3D = SkaterAnatomyCapture.skeleton(skater)
		var to_hips: Transform3D = SkaterAnatomyCapture.hips_frame(skater).affine_inverse() \
				* skel.global_transform
		for marker: Vector3 in [skater.shoulder.position, skater.bottom_shoulder.position]:
			var drawn: Vector3 = to_hips * (skater.drawn_upper_body() * skater.visible_shoulder(marker))
			var modelled: Vector3 = chest * (body.top_shoulder if marker == skater.shoulder.position
					else body.bottom_shoulder)
			assert_almost_eq(modelled, drawn, Vector3.ONE * NEAR_M, what + ": shoulder")
		var torso: Transform3D = to_hips * skel.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TORSO)
		var model_torso: Transform3D = Transform3D(chest, Vector3.ZERO) * body.torso_in_spine
		assert_almost_eq(model_torso.origin, torso.origin, Vector3.ONE * NEAR_M, what + ": jersey")


func test_the_search_holds_a_carry_and_names_the_arms_reach_past_every_one() -> void:
	var c: SkaterController = _make()
	var body: ArmAnatomyBody = SkaterAnatomyCapture.capture(c)
	var forehand: float = signf(body.bottom_shoulder.x)
	_carry(c, Vector2(0.8 * forehand, -0.6), false)
	var trunk: ArmAnatomySearch.TrunkState = SkaterAnatomyCapture.trunk_state(c.skater, body)
	var ice: float = c.blade_height - SkaterAnatomyCapture.pivot_height(c.skater)
	var search := ArmAnatomySearch.new(body)
	var pose := ArmAnatomySearch.Pose.new()
	search.solve(trunk, Vector3(0.8 * forehand, ice, -0.6), pose)
	assert_true(pose.feasible(), "a blade low on the forehand is held")
	assert_lte(pose.top.violation, 0.0, "both arms in their ranges")
	assert_lte(pose.bottom.violation, 0.0, "both arms in their ranges")
	search.solve(trunk, Vector3(0.0, ice, -3.0), pose)
	assert_false(pose.feasible(), "three metres out is not")
	assert_eq(pose.arm_binding, ArmAnatomy.Limit.REACH, "the arms' reach stops it")
	search.technique = true
	search.solve(trunk, Vector3(0.8 * forehand, ice, -0.6), pose)
	assert_true(pose.feasible(), "and as players hold it")
	search.solve(trunk, Vector3(0.0, ice, -3.0), pose)
	assert_false(pose.feasible(), "three metres out still is not")


# A carrier holds the stick on bent knees, and nothing in a comfortable carry
# asks them for more: the search sits his hips a ready stance under standing,
# less what they already sit under it.
func test_the_search_stands_a_carry_in_a_ready_stance() -> void:
	var c: SkaterController = _make()
	var body: ArmAnatomyBody = SkaterAnatomyCapture.capture(c)
	var trunk: ArmAnatomySearch.TrunkState = SkaterAnatomyCapture.trunk_state(c.skater, body)
	assert_almost_eq(trunk.sunk, 0.0, 0.001, "captured standing")
	trunk.crouch_max = ArmAnatomySearch.DEEPEST_STANCE_M
	var forehand: float = signf(body.bottom_shoulder.x)
	var ice: float = c.blade_height - SkaterAnatomyCapture.pivot_height(c.skater)
	var search := ArmAnatomySearch.new(body)
	search.technique = true
	var pose := ArmAnatomySearch.Pose.new()
	for sunk: float in [0.0, 0.04]:
		trunk.sunk = sunk
		search.solve(trunk, Vector3(0.8 * forehand, ice, -0.8), pose)
		assert_true(pose.feasible(), "held")
		assert_almost_eq(pose.crouch + sunk, ArmAnatomySearch.READY_STANCE_M, 0.02,
				"sunk %.2f: the hips a ready stance under standing" % sunk)


# The search holds the shaft out of the legs as it holds it out of the jersey:
# a blade planted beside a skate stands its shaft in the leg, a carry ahead
# clears both, and a crouch bends each knee with its skate kept on the ice.
func test_the_search_holds_the_shaft_out_of_the_legs() -> void:
	var c: SkaterController = _make()
	var body: ArmAnatomyBody = SkaterAnatomyCapture.capture(c)
	var trunk: ArmAnatomySearch.TrunkState = SkaterAnatomyCapture.trunk_state(c.skater, body)
	assert_eq(trunk.legs.size(), 2, "both legs")
	var forehand: float = signf(body.bottom_shoulder.x)
	var ice: float = c.blade_height - SkaterAnatomyCapture.pivot_height(c.skater)
	var search := ArmAnatomySearch.new(body)
	var pose := ArmAnatomySearch.Pose.new()
	search.hold(trunk, Vector3(0.8 * forehand, ice, -0.6), 0.0, deg_to_rad(40.0),
			atan2(0.8 * forehand, -0.6), -1.0, pose)
	assert_lt(pose.legs_depth, 0.0, "a carry ahead clears the legs")
	var leg: PackedVector3Array = trunk.legs[0]
	var by_skate := Vector3(leg[2].x, ice, leg[2].z)
	var deepest: float = -INF
	for k: int in 8:
		search.hold(trunk, by_skate, 0.0, deg_to_rad(75.0), TAU * float(k) / 8.0, -1.0, pose)
		deepest = maxf(deepest, pose.legs_depth)
	assert_gt(deepest, 0.0, "a shaft stood up from the skate is in the leg")
	var sunk: Vector3 = leg[2] + Vector3.UP * 0.1
	var knee: Vector3 = ArmAnatomySearch.bent_knee(leg, sunk)
	assert_almost_eq(knee.distance_to(leg[0]), leg[0].distance_to(leg[1]), 0.001,
			"the thigh keeps its length")
	assert_almost_eq(knee.distance_to(sunk), leg[1].distance_to(leg[2]), 0.001,
			"the shin keeps its length")
	assert_lt(knee.z, leg[1].z, "the knee comes forward over the skate")

extends GutTest

# How a carrier is drawn holding his stick (StickHoldRules, through
# SkaterIKCoordinator._hold_offset, and the carry's posture): the top hand in
# its pocket off the hip, so the shaft stays near its lie and under the
# shoulder across the distances a puck is carried at; the body come down to
# it, so both elbows bend. Mesh only: the markers the tick placed do not move.
# Driven through the real controller and render pass.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# A lefty's forehand-ahead diagonal, straight ahead, and round his backhand.
const BEARINGS: Array[Vector3] = [Vector3(-0.5, 0.0, -0.87), Vector3(0.0, 0.0, -1.0),
		Vector3(0.5, 0.0, -0.87)]


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _make_carrier() -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	puck.set_carrier(skater)
	c.on_puck_picked_up_network()
	return c


func _hold(c: SkaterController, cursor: Vector3, ticks: int = 150) -> void:
	var sk: Skater = c.skater
	var input := InputState.new()
	for _t: int in ticks:
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = sk.global_position + cursor
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		sk._process(DT)


func _joint(sk: Skater, bone: int) -> Vector3:
	var body: Skeleton3D = sk._arms._skeleton
	return body.global_transform * body.get_bone_global_pose(bone).origin


func _shoulder(sk: Skater) -> Vector3:
	var body: Skeleton3D = sk._arms._skeleton
	var upper: Transform3D = body.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM)
	return body.global_transform * (upper.origin + upper.basis.z * 0.5)


func _shaft_deg(sk: Skater) -> float:
	var shaft: Vector3 = _joint(sk, SkaterMeshBuilder.UpperBone.TOP_HAND) \
			- sk.upper_body_to_global(sk.drawn_blade().origin)
	return rad_to_deg(asin(shaft.y / shaft.length()))


func test_a_carried_puck_is_held_near_the_sticks_lie() -> void:
	for bearing: Vector3 in BEARINGS:
		for out_m: float in [1.1, 1.3, 1.6]:
			var c: SkaterController = _make_carrier()
			_hold(c, bearing.normalized() * out_m)
			var sk: Skater = c.skater
			var what: String = "cursor %.1f m out at (%.1f, %.1f)" % [out_m, bearing.x, bearing.z]
			assert_between(_shaft_deg(sk), sk.blade_lie_deg - 3.0, sk.blade_lie_deg + 12.0,
					"%s: the shaft near its lie" % what)
			var hand: Vector3 = _joint(sk, SkaterMeshBuilder.UpperBone.TOP_HAND)
			assert_gt(_shoulder(sk).y - hand.y, 0.15, "%s: the top hand under its shoulder" % what)


func test_the_hands_hold_the_stick_a_forearm_apart_with_both_elbows_bent() -> void:
	var c: SkaterController = _make_carrier()
	_hold(c, Vector3(-0.3, 0.0, -1.2))
	var sk: Skater = c.skater
	var top: Vector3 = _joint(sk, SkaterMeshBuilder.UpperBone.TOP_HAND)
	var bottom: Vector3 = _joint(sk, SkaterMeshBuilder.UpperBone.BOTTOM_HAND)
	assert_between(top.distance_to(bottom), 0.28, 0.45, "the hands a forearm apart")
	var arm: float = sk.upper_arm_length + sk.forearm_length
	assert_lt(top.distance_to(_shoulder(sk)), arm * 0.8, "the top arm bent, not reaching")


func test_the_body_comes_down_to_the_stick() -> void:
	var c: SkaterController = _make_carrier()
	_hold(c, Vector3(0.0, 0.0, -1.6))
	var standing: float = GameRules.FACEOFF_SPAWN_HEIGHT + c.skater.shoulder.position.y
	assert_lt(_shoulder(c.skater).y, standing - 0.15,
			"the shoulders well under where an upright trunk on straight legs has them")


func test_the_hold_moves_no_marker() -> void:
	var c: SkaterController = _make_carrier()
	_hold(c, Vector3(-0.2, 0.0, -1.15))
	var sk: Skater = c.skater
	var marker: Vector3 = sk.get_top_hand_position()
	var blade: Vector3 = sk.get_blade_position()
	assert_gt(sk.drawn_top_hand().distance_to(marker), 0.05, "the hand is drawn off its marker")
	assert_almost_eq(sk.drawn_top_hand().distance_to(sk.drawn_blade().origin),
			marker.distance_to(blade), 0.002, "the drawn stick is the tick's length")
	sk._process(DT)
	assert_eq(sk.get_top_hand_position(), marker, "the marker stays where the tick put it")
	assert_eq(sk.get_blade_position(), blade, "and the blade")


func test_a_shot_poses_its_own_hands() -> void:
	var c: SkaterController = _make_carrier()
	_hold(c, Vector3(-0.2, 0.0, -1.15))
	assert_gt(c._ik._hold_share, 0.99, "the carry is held")
	c._ik._pump_hold = 0.0
	c._ik._hold_offset(c.skater.get_top_hand_position(), c.skater.get_blade_position(), -1.0)
	assert_eq(c._ik._hold_share, 0.0, "a stick the tracked solve does not own is not")

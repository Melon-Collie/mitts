extends GutTest

# The rebuilt keeper in a match (KeeperController on the Goalie node): the old
# body hidden and its colliders off, his gear's save boxes live where his gear
# is; on either net he goes where the brain puts him, square to the puck; a shot
# at his pad meets a pad box through the puck's own contact test; and a catch is
# held in his glove and covered, then set down.

const DT: float = 1.0 / 120.0

var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null


func _spawn(goal_line_z: float) -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate() as Goalie
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	_keeper = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_keeper)
	_puck.global_position = Vector3(0.0, _puck.ice_height, goal_line_z * 0.7)
	_keeper.setup(_goalie, _puck, goal_line_z, true)


func _run(seconds: float) -> void:
	for i: int in int(seconds / DT):
		_keeper._physics_process(DT)


func _live_boxes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for cs: CollisionShape3D in _goalie.get_collision_parts():
		if not cs.disabled:
			out.append(cs)
	return out


func test_his_gear_is_the_save_geometry_and_the_old_body_is_hidden() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_run(0.5)
	var live: Array[CollisionShape3D] = _live_boxes()
	assert_eq(live.size(), KeeperGear.PART_COUNT, "one live box per piece of his gear")
	var skel: KeeperSkeleton = _keeper._keeper.skeleton
	for part: int in KeeperGear.PART_COUNT:
		var want: Transform3D = _goalie.global_transform * KeeperGear.box(skel, part)
		var found: bool = false
		for box: CollisionShape3D in live:
			if box.global_transform.origin.distance_to(want.origin) < 1e-4 \
					and (box.shape as BoxShape3D).size.is_equal_approx(KeeperGear.half_extents(part) * 2.0):
				found = true
		assert_true(found, "%s's box where his gear is" % KeeperGear.Part.keys()[part])
	for node: Node in _goalie.find_children("*", "VisualInstance3D", true, false):
		if not _keeper._keeper.is_ancestor_of(node):
			assert_false((node as VisualInstance3D).visible, "%s hidden" % node.name)


func test_on_either_net_he_stands_on_the_angle_line_square_to_the_puck() -> void:
	for goal_line_z: float in [GameRules.GOAL_LINE_Z, -GameRules.GOAL_LINE_Z]:
		_spawn(goal_line_z)
		var out: float = -signf(goal_line_z)
		_puck.global_position = Vector3(3.0, _puck.ice_height, goal_line_z + out * 8.0)
		_run(2.0)
		var net := Vector3(0.0, 0.0, goal_line_z)
		var at: Vector3 = _goalie.global_position
		var to_puck: Vector3 = (_puck.global_position - net) * Vector3(1.0, 0.0, 1.0)
		var off_line: float = absf((at - net).cross(to_puck.normalized()).y)
		assert_lt(off_line, KeeperRoute.THERE_M + 0.01, "%.2f: on the angle line" % goal_line_z)
		assert_almost_eq((at - net).length(), KeeperPositioning.crease_edge(Vector2(3.0, 8.0).normalized()),
				KeeperRoute.THERE_M + 0.01, "%.2f: at the top of the crease" % goal_line_z)
		var forward: Vector3 = -_goalie.global_transform.basis.z
		var look: Vector3 = ((_puck.global_position - at) * Vector3(1.0, 0.0, 1.0)).normalized()
		assert_gt(forward.dot(look), cos(deg_to_rad(3.0)), "%.2f: square to the puck" % goal_line_z)


func test_a_shot_at_his_pad_meets_a_pad_box() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_puck.global_position = Vector3(0.0, _puck.ice_height, GameRules.GOAL_LINE_Z - 8.0)
	_run(1.5)
	# The glove-side pad's outer half, over the blade laid along the ice in
	# front of it and wide of the paddle rising to his blocker hand.
	var pad: Transform3D = _goalie.global_transform * KeeperGear.box(_keeper._keeper.skeleton, KeeperGear.Part.PAD_G)
	var aim: Vector3 = pad.origin + pad.basis.x.normalized() * -signf(pad.basis.x.x) * 0.08
	aim.y = 0.35
	var from: Vector3 = aim + Vector3(0.0, 0.0, -2.0)
	var to: Vector3 = aim + Vector3(0.0, 0.0, 0.5)
	var contact := GoalieContactDetector.Contact.new()
	var hit: bool = GoalieContactDetector.nearest([_goalie], from, to, GameRules.PUCK_COLLISION_RADIUS,
			SweptDiscOBB.Result.new(), contact)
	assert_true(hit, "the shot meets him")
	assert_eq(_puck._classify_save_part(contact.part as Node3D), GoalieSaveRules.SavePart.PAD, "on a pad")


func test_a_catch_is_held_in_his_glove_and_covered_then_set_down() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_run(0.5)
	watch_signals(_keeper)
	_puck.puck_caught_by_goalie.emit(_goalie)
	_keeper._physics_process(DT)
	assert_signal_emitted(_keeper, "puck_covered")
	assert_true(_puck.motion_pinned and _puck.pickup_locked, "held")
	assert_almost_eq(_puck.global_position, _goalie.get_glove_world_position(), Vector3.ONE * 1e-4, "in his glove")
	_run(KeeperController.CATCH_HOLD_S + 0.1)
	assert_false(_puck.motion_pinned or _puck.pickup_locked, "set down")
	assert_almost_eq(_puck.global_position.y, _puck.ice_height, 1e-4, "on the ice")

extends GutTest

# The blocker is a glove on the arm: the hand (BlockArm) is posed, and the board
# runs along the forearm from it, face turned out (Goalie._seat_blocker). It is
# a save surface, so these hold the seat on both paths that pose a goalie —
# the host's body config and the client/replay network pose.

const State := GoalieStateMachine.State


func _posed(state: int) -> Goalie:
	var g: Goalie = load("res://Scenes/Goalie.tscn").instantiate()
	add_child_autofree(g)
	var b := GoalieBodyConfigBuilder.new()
	var i := GoalieBodyConfigBuilder.Inputs.new()
	i.state = state
	i.direction_sign = 1
	g.apply_body_config(b.build(i), 1.0)
	return g


func _board_in_goalie(g: Goalie) -> Transform3D:
	var arm: Node3D = g.get_node("BlockArm")
	return arm.transform * (g.get_node("BlockArm/Blocker") as Node3D).transform


func _check_seat(g: Goalie, label: String) -> void:
	var arm: Node3D = g.get_node("BlockArm")
	var board: Transform3D = _board_in_goalie(g)
	var along: Vector3 = (arm.position - g._blocker_elbow).normalized()
	assert_almost_eq(board.basis.y.normalized().dot(along), 1.0, 1e-4,
			"%s: the board runs along the forearm, finger end at the hand" % label)
	var face: Vector3 = -board.basis.z.normalized()
	assert_gt(face.x, 0.0, "%s: the board is on the arm's outer side" % label)
	assert_lt(face.z, 0.0, "%s: and faces the shooter's half" % label)
	var grip_in_board: Vector3 = board.affine_inverse() * arm.position
	assert_almost_eq(grip_in_board, Vector3(0.0, GoalieAnatomy.BLOCKER_BOARD_ALONG_M,
			GoalieAnatomy.BLOCKER_BOARD_OUT_M), Vector3.ONE * 1e-4,
			"%s: the grip sits where the fist is baked" % label)


func test_the_board_rides_the_hand_in_every_stance() -> void:
	for st: int in [State.STANDING, State.READY, State.BUTTERFLY, State.RVH_RIGHT,
			State.HALF_BUTTERFLY_RIGHT]:
		_check_seat(_posed(st), GoalieStateMachine.State.keys()[st])


func test_the_board_follows_the_elbow() -> void:
	var g: Goalie = _posed(State.READY)
	var before: Basis = _board_in_goalie(g).basis
	var arm: Node3D = g.get_node("BlockArm")
	var cfg := GoalieBodyConfigBuilder.new().build(GoalieBodyConfigBuilder.Inputs.new())
	cfg.blocker_pos = arm.position + Vector3(0.12, 0.0, 0.10)
	g.apply_body_config(cfg, 1.0)
	assert_false(_board_in_goalie(g).basis.is_equal_approx(before),
			"moving the hand moves the forearm, and the board moves with it")
	_check_seat(g, "after the reach")


func test_the_network_pose_seats_the_board_too() -> void:
	var g: Goalie = _posed(State.READY)
	var s := GoalieNetworkState.new()
	s.state_enum = State.READY
	s.blocker_offset = Vector3(0.40, 0.75, -0.30)
	g.apply_network_pose(s)
	_check_seat(g, "network pose")

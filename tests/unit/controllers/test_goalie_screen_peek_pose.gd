extends GutTest

# The screen peek is visible: the eyes the sightline reads use
# (GoalieController._eye_position) are where the drawn head is. On his feet the
# pose leans the trunk by exactly the roll that carries the head there, and the
# head rides every lean — so a client, which gets body roll on the wire but not
# the head, rebuilds the same head from the roll.

const State := GoalieStateMachine.State
const DT: float = 1.0 / 120.0
const GoalieScene := preload("res://Scenes/Goalie.tscn")


func _config(state: int, eye_x: float) -> GoalieBodyConfig:
	var i := GoalieBodyConfigBuilder.Inputs.new()
	i.state = state
	i.direction_sign = 1
	i.eye_offset_local_x = eye_x
	return GoalieBodyConfigBuilder.new().build(i)


func test_no_peek_no_lean() -> void:
	var c: GoalieBodyConfig = _config(State.READY, 0.0)
	assert_almost_eq(c.body_rot.z, 0.0, 1e-6)
	assert_almost_eq(c.head_pos.x, GoalieBodyConfigBuilder.READY_HEAD_POS.x, 1e-6)


func test_a_peek_leans_his_head_to_where_his_eyes_are() -> void:
	for eye: float in [0.15, -0.15, 0.06]:
		var c: GoalieBodyConfig = _config(State.READY, eye)
		assert_almost_eq(c.head_pos.x, eye, 1e-4, "head over by %.2f" % eye)
		assert_gt(-signf(eye) * c.body_rot.z, 0.0, "the chest leans that way too")
		assert_lt(absf(c.body_rot.z), 12.0, "a lean, not a fall")


func test_a_client_rebuilds_the_same_head_from_the_rolled_trunk() -> void:
	var c: GoalieBodyConfig = _config(State.READY, 0.12)
	var g: Goalie = GoalieScene.instantiate()
	add_child_autofree(g)
	var s := GoalieNetworkState.new()
	s.state_enum = State.READY
	s.body_pitch = deg_to_rad(c.body_rot.x)
	s.body_roll = deg_to_rad(c.body_rot.z)
	g.apply_network_pose(s)
	assert_almost_eq((g.get_node("Head") as Node3D).position.x, c.head_pos.x, 1e-4)


func test_down_he_does_not_lean_for_a_peek() -> void:
	for st: int in [State.BUTTERFLY, State.RVH_LEFT, State.COVERING]:
		var still: GoalieBodyConfig = _config(st, 0.0)
		var rest_roll: float = still.body_rot.z
		var rest_head: float = still.head_pos.x
		var c: GoalieBodyConfig = _config(st, 0.15)
		assert_almost_eq(c.body_rot.z, rest_roll, 1e-6, State.keys()[st])
		assert_almost_eq(c.head_pos.x, rest_head, 1e-6, State.keys()[st])


func test_the_drawn_head_is_where_the_sightline_reads_look_from() -> void:
	var goalie: Goalie = GoalieScene.instantiate()
	var puck: Node = load("res://Scenes/Puck.tscn").instantiate()
	var ctrl := GoalieController.new()
	for n: Node in [goalie, puck, ctrl]:
		add_child_autofree(n)
	# The puck in front of him, or the far-puck sleep holds the pose still.
	puck.global_position = Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 5.0)
	ctrl.setup(goalie, puck, -GameRules.GOAL_LINE_Z, true)
	ctrl.reset_to_crease()
	ctrl._sm.current = State.READY
	ctrl._eye_offset_x = 0.12
	for _i: int in 240:
		ctrl._update_body_parts(DT)
	var head: Node3D = goalie.get_node("Head")
	assert_almost_eq(head.global_position.x, ctrl._eye_position().x, 0.01,
			"the head he is drawn with is the one he sees from")


func test_the_head_stays_on_its_neck_through_the_lean() -> void:
	# The trunk leans from the hips, so the neck it carries swings with the head
	# rather than the head sliding off it.
	var g: Goalie = GoalieScene.instantiate()
	add_child_autofree(g)
	g.apply_body_config(_config(State.READY, 0.15), 1.0)
	var neck: Node3D = g.find_child("Neck", true, false) as Node3D
	var neck_top: Vector3 = g.to_local(
			neck.global_transform * Vector3(0.0, GoalieMeshBuilder._NECK_TOP_Y, 0.0))
	var head: Vector3 = (g.get_node("Head") as Node3D).position
	assert_almost_eq(head.x, neck_top.x, 0.03, "the head rides the top of its neck")

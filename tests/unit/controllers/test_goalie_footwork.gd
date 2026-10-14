extends GutTest

# The upright goalie's footwork (GoalieFootwork): a shuffle stroke on the trailing
# skate, the T-push's lead turn and trail drive, the edge stop's lean — laid over
# the pads as a step the actor does not smooth, kept on the ice.

const State := GoalieStateMachine.State
const DT: float = 1.0 / 120.0


func _config(fw: GoalieFootwork, state: int = State.READY) -> GoalieBodyConfig:
	var b := GoalieBodyConfigBuilder.new()
	var i := GoalieBodyConfigBuilder.Inputs.new()
	i.state = state
	i.direction_sign = 1
	i.footwork = fw
	return b.build(i)


func _run(fw: GoalieFootwork, seconds: float, speed: float, t_push: bool = false,
		braking: bool = false) -> void:
	for _i: int in int(seconds / DT):
		fw.advance(DT, speed, t_push, braking, 2.0)


# Lowest point of a pad box posed at `pos`/`rot_deg`.
func _pad_bottom(pos: Vector3, rot_deg: Vector3) -> float:
	return pos.y - GoalieAnatomy.pad_center_y_on_ice(rot_deg)


func test_standing_still_has_no_footwork() -> void:
	var c: GoalieBodyConfig = _config(GoalieFootwork.new())
	assert_eq(c.left_pad_step_pos, Vector3.ZERO)
	assert_eq(c.right_pad_step_rot, Vector3.ZERO)
	assert_almost_eq(c.body_rot.z, 0.0, 1e-6)


func test_only_the_upright_stances_have_footwork() -> void:
	var fw := GoalieFootwork.new()
	_run(fw, 0.5, 2.0)
	for st: int in [State.BUTTERFLY, State.RVH_LEFT, State.COVERING, State.PLAYING_PUCK]:
		var c: GoalieBodyConfig = _config(fw, st)
		assert_eq(c.left_pad_step_pos + c.right_pad_step_pos, Vector3.ZERO,
				"%s carries no step" % State.keys()[st])
	assert_eq(_config(null).left_pad_step_pos, Vector3.ZERO, "no footwork, no step")


func test_a_shuffle_pushes_off_the_trailing_skate_and_draws_it_back() -> void:
	# Shuffling right: the left skate trails. Over one stroke it slides out to
	# his left as he pushes, lifts as it recovers, and comes back under him.
	var fw := GoalieFootwork.new()
	_run(fw, 0.4, 2.0)
	var widest: float = 0.0
	var lifted: float = 0.0
	var ticks: int = int(GoalieFootwork.SHUFFLE_STROKE_M / 2.0 / DT)
	for _i: int in ticks:
		fw.advance(DT, 2.0, false, false, 2.0)
		var c: GoalieBodyConfig = _config(fw)
		widest = minf(widest, c.left_pad_step_pos.x)
		lifted = maxf(lifted, c.left_pad_step_pos.y
				- (GoalieAnatomy.pad_center_y_on_ice(c.left_pad_rot + c.left_pad_step_rot)
				- GoalieAnatomy.pad_center_y_on_ice(c.left_pad_rot)))
		assert_almost_eq(c.right_pad_step_pos.x, 0.0, 1e-6, "the lead skate glides")
	assert_lt(widest, -GoalieFootwork.SHUFFLE_PUSH_OUT_M * 0.8, "the trail skate pushes out")
	assert_gt(lifted, GoalieFootwork.SHUFFLE_LIFT_M * 0.8, "and lifts as it recovers")


func test_a_t_push_turns_the_lead_skate_toward_travel_and_drives_the_trail() -> void:
	var fw := GoalieFootwork.new()
	_run(fw, 0.5, 3.8, true)
	var c: GoalieBodyConfig = _config(fw)
	# Travelling right: negative yaw turns the right pad's front toward +x.
	assert_lt(c.right_pad_step_rot.y, -GoalieFootwork.T_PUSH_LEAD_TURN_DEG * 0.9)
	assert_gte(c.right_pad_step_rot.y, -GoalieFootwork.T_PUSH_LEAD_TURN_DEG - 1e-4,
			"a partial turn: most of the pad still faces the shooter")
	assert_lt(c.left_pad_step_pos.x, -GoalieFootwork.T_PUSH_TRAIL_OUT_M * 0.9,
			"the trail leg extends")
	assert_lt(c.body_rot.z, 0.0, "he leans into the push")
	# Mirrored: travelling left turns the left pad toward −x.
	var back := GoalieFootwork.new()
	_run(back, 0.5, -3.8, true)
	assert_gt(_config(back).left_pad_step_rot.y, GoalieFootwork.T_PUSH_LEAD_TURN_DEG * 0.9)


func test_the_edge_stop_plants_the_lead_skate_and_leans_back() -> void:
	var fw := GoalieFootwork.new()
	_run(fw, 0.3, 3.8, true)
	_run(fw, 0.3, 1.0, true, true)
	var c: GoalieBodyConfig = _config(fw)
	assert_gt(c.right_pad_step_pos.x, 0.0, "the lead skate plants out wide")
	assert_gt(c.right_pad_step_rot.z, 0.0, "on its inside edge")
	assert_gt(c.body_rot.z, 0.0, "leaning back against his momentum")
	assert_almost_eq(c.right_pad_step_rot.y, 0.0, 2.0, "the T-push turn comes out of it")


func test_the_pads_stay_on_the_ice_through_a_push() -> void:
	var fw := GoalieFootwork.new()
	_run(fw, 0.5, 3.8, true)
	var c: GoalieBodyConfig = _config(fw)
	assert_almost_eq(_pad_bottom(c.right_pad_pos + c.right_pad_step_pos,
			c.right_pad_rot + c.right_pad_step_rot), 0.0, 0.003)
	assert_almost_eq(_pad_bottom(c.left_pad_pos + c.left_pad_step_pos,
			c.left_pad_rot + c.left_pad_step_rot), 0.0, 0.003)


func test_a_settled_spot_does_not_flip_the_lead_side() -> void:
	var fw := GoalieFootwork.new()
	_run(fw, 0.3, 2.0)
	_run(fw, 0.1, -0.05)
	assert_eq(fw.side, 1.0, "a drift through zero keeps the side he was travelling")


func test_the_actor_lays_the_step_over_its_eased_stance_without_keeping_it() -> void:
	var g: Goalie = load("res://Scenes/Goalie.tscn").instantiate()
	add_child_autofree(g)
	var c: GoalieBodyConfig = _config(null)
	g.apply_body_config(c, 1.0)
	var rest: Vector3 = (g.get_node("LeftPad") as Node3D).position
	c.left_pad_step_pos = Vector3(-0.1, 0.02, 0.0)
	g.apply_body_config(c, 0.05)
	assert_almost_eq((g.get_node("LeftPad") as Node3D).position, rest + c.left_pad_step_pos,
			Vector3.ONE * 1e-5, "the step is laid on unsmoothed")
	c.left_pad_step_pos = Vector3.ZERO
	g.apply_body_config(c, 0.05)
	assert_almost_eq((g.get_node("LeftPad") as Node3D).position, rest, Vector3.ONE * 1e-5,
			"and leaves nothing behind in the stance")

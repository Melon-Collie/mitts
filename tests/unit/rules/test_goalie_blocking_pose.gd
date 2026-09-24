extends GutTest

# The blocking butterfly vs the reaction butterfly (GoalieBodyConfigBuilder).
# A block is tall and tight: chest upright, both hands flush against the trunk
# just above the flat pads. A reaction drop keeps the chest leaning out and the
# hands out in front, ready to reach.

const State := GoalieStateMachine.State


func _build(blocking: bool) -> GoalieBodyConfig:
	var i := GoalieBodyConfigBuilder.Inputs.new()
	i.state = State.BUTTERFLY
	i.direction_sign = 1
	i.blocking_seal = blocking
	# The builder hands back one shared scratch, so copy what we compare.
	return GoalieBodyConfigBuilder.new().build(i)


func test_a_block_is_upright_and_tucked() -> void:
	var c: GoalieBodyConfig = _build(true)
	assert_almost_eq(c.body_rot.x, 0.0, 0.001, "chest upright")
	var hand_x: float = GoalieAnatomy.torso_half_width() + GoalieAnatomy.GLOVE_BOX_WIDTH_M * 0.5
	assert_almost_eq(absf(c.glove_pos.x), hand_x, 0.001, "glove flush against the trunk")
	assert_almost_eq(absf(c.blocker_pos.x), hand_x, 0.001, "blocker flush against the trunk")
	assert_almost_eq(c.glove_pos.y - GoalieAnatomy.hand_vertical_half_extent(),
			GoalieAnatomy.pad_span(true).y, 0.001, "sitting on the pad tops")


func test_a_reaction_drop_leans_out_with_the_hands_ready() -> void:
	var react: GoalieBodyConfig = _build(false)
	var react_pitch: float = react.body_rot.x
	var react_glove: Vector3 = react.glove_pos
	var block: GoalieBodyConfig = _build(true)
	assert_lt(react_pitch, block.body_rot.x, "leaning out over the pads")
	assert_gt(absf(react_glove.x), absf(block.glove_pos.x), "hands wider")
	assert_lt(react_glove.z, block.glove_pos.z, "and further out in front")

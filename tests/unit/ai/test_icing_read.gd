extends GutTest

# AIIcingRead — NHL hybrid icing as a bot reads a release before it makes it.
# Team 0 attacks -Z: our half is z > 0, their goal line z = -GOAL_LINE_Z.

const ATTACK_Z: float = -1.0
const STEP: float = 0.25


func _path(zs: Array[float]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for z: float in zs:
		out.append(Vector3(-12.0, 0.0, z))
	return out


func test_the_crossing_is_the_first_sample_past_their_goal_line() -> void:
	var g: float = GameRules.GOAL_LINE_Z
	assert_almost_eq(AIIcingRead.crossing_s(_path([0.0, -15.0, -g - 0.5, -g - 1.0]),
			STEP, ATTACK_Z), 3.0 * STEP, 1e-6)
	assert_eq(AIIcingRead.crossing_s(_path([0.0, -15.0, -g + 0.5]), STEP, ATTACK_Z), INF,
			"short of the line, it never crosses")
	assert_eq(AIIcingRead.crossing_s(_path([g + 1.0]), STEP, ATTACK_Z), INF,
			"our own goal line is not theirs")


func test_only_a_release_from_our_half_ices() -> void:
	assert_true(AIIcingRead.ices(5.0, ATTACK_Z, 2.0, INF, 3.0, 1.0))
	assert_false(AIIcingRead.ices(-5.0, ATTACK_Z, 2.0, INF, 3.0, 1.0),
			"past centre it is a dump, not an icing")


func test_a_puck_played_before_it_crosses_does_not_ice() -> void:
	assert_false(AIIcingRead.ices(5.0, ATTACK_Z, 2.0, 1.5, 3.0, 1.0))
	assert_true(AIIcingRead.ices(5.0, ATTACK_Z, 2.0, 2.5, 3.0, 1.0))


# The bot's dot race must be the referee's: at the instant the first man
# reaches the dots, InfractionRules.judge_icing_race decides it.
func test_the_dot_race_is_the_referees() -> void:
	for ours: float in [0.5, 1.0, 1.5, 2.0, 3.0]:
		for lead: float in [-0.5, -0.1, 0.0, 0.1, 0.19, 0.21, 0.5]:
			var theirs: float = ours + lead
			var called: bool
			if theirs <= ours:
				called = InfractionRules.judge_icing_race(ours - theirs, 0.0) \
						== InfractionRules.IcingCall.ICING
			else:
				called = InfractionRules.judge_icing_race(0.0, theirs - ours) \
						== InfractionRules.IcingCall.ICING
			assert_eq(AIIcingRead.ices(5.0, ATTACK_Z, 1.0, INF, ours, theirs), called,
					"ours %.2f s, theirs %.2f s" % [ours, theirs])


func test_the_dot_race_is_to_the_line_of_the_dots() -> void:
	var at_dots := Vector3(5.0, 0.0, -GameRules.ICING_FACEOFF_DOT_Z)
	var still: Array[Vector3] = [Vector3.ZERO]
	var none: Array[AISkaterCaps] = []
	var pos: Array[Vector3] = [at_dots + Vector3(0.0, 0.0, 10.0)]
	var t: float = AIIcingRead.first_to_dots(ATTACK_Z, pos, still, none)
	assert_almost_eq(t, AIArrival.time_to_arrive(pos[0], at_dots, Vector3.ZERO,
			AIArrival.SKATER_REF_SPEED_M_S), 1e-6, "straight down the ice to the dots' line")
	pos.append(at_dots + Vector3(-8.0, 0.0, 4.0))
	still.append(Vector3.ZERO)
	assert_lt(AIIcingRead.first_to_dots(ATTACK_Z, pos, still, none), t, "the soonest man")


func test_the_faceoff_is_the_games() -> void:
	for team: int in [0, 1]:
		for x: float in [-4.0, 4.0]:
			var dot: Vector2 = GameRules.icing_faceoff_dot(team, x)
			assert_eq(AIIcingRead.faceoff_spot(team, x), Vector3(dot.x, 0.0, dot.y))

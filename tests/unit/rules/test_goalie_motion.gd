extends GutTest

# AIGoalieModel.goalie_unsettled and the keeper the bots predict: caught moving
# across, squared on a carry, reset given time.
#
# Coordinates mirror real play: attacking goal at -GOAL_LINE_Z, shooter ~6.6 m
# out, goalie ~0.6 m off its line (a representative depth — this exercises the AI
# motion model, which reads the goalie's LIVE position, not the depth_base const).

const GOAL := Vector3(0, 0, -GameRules.GOAL_LINE_Z)   # z = -26.65
const GOALIE_Z := -GameRules.GOAL_LINE_Z + 0.6        # 0.6 m off the line
const SHOOTER := Vector3(2.0, 0, -20.0)               # 2 m lateral, ~6.65 m out


func _goalie_at(x: float) -> Vector3:
	return Vector3(x, 0, GOALIE_Z)


# Arc-match x for a puck at puck_x (goalie tracks ~depth/forward of it).
func _arc_match_x(puck_x: float) -> float:
	var forward: float = SHOOTER.z - GOAL.z   # 6.65
	return GOAL.x + 0.6 * (puck_x - GOAL.x) / forward


# ── goalie_unsettled ────────────────────────────────────────────────────────

func test_set_squared_goalie_is_fully_settled() -> void:
	# Goalie already at its arc-match target for this shooter → no forced motion.
	var goalie := _goalie_at(_arc_match_x(SHOOTER.x))
	var u := AIGoalieModel.goalie_unsettled(goalie, GOAL, 0.26, SHOOTER)
	assert_almost_eq(u, 0.0, 0.001, "a set, square goalie reads as fully settled")


func test_cross_seam_one_timer_catches_goalie_moving() -> void:
	# Goalie was tracking the carrier on the far side (x = -0.18); the puck is
	# one-timed from the near side (x = +2 → target +0.18). With only the pass
	# flight to react (~0.21 s), it can't cover the 0.36 m → caught mid-slide,
	# moving at his push's speed then.
	var goalie := _goalie_at(_arc_match_x(-2.0))
	var u := AIGoalieModel.goalie_unsettled(goalie, GOAL, 0.21, SHOOTER)
	var pushed_s: float = 0.21 - AIGoalieModel.goalie_leg_delay_s
	assert_almost_eq(u, AIGoalieModel.GOALIE_LATERAL_ACCEL_M_S2 * pushed_s
			/ AIGoalieModel.GOALIE_MAX_LATERAL_SPEED_MPS, 0.001,
			"a cross-seam one-timer catches the goalie still accelerating across")


func test_goalie_who_has_not_reacted_is_not_moving() -> void:
	# A release sooner than his reaction finds him standing where he was: off the
	# square (the position prediction's job), but not sliding.
	var goalie := _goalie_at(_arc_match_x(-2.0))
	var u := AIGoalieModel.goalie_unsettled(goalie, GOAL,
			AIGoalieModel.goalie_leg_delay_s * 0.5, SHOOTER)
	assert_eq(u, 0.0, "a goalie who has not reacted is read standing, not caught moving")


func test_goalie_resets_when_given_time() -> void:
	# Same cross-ice swing, but a slow developing play (long release) lets the
	# goalie reach its target and re-set before the shot → settled.
	var goalie := _goalie_at(_arc_match_x(-2.0))
	var u := AIGoalieModel.goalie_unsettled(goalie, GOAL, 0.7, SHOOTER)
	assert_almost_eq(u, 0.0, 0.001,
			"with enough time the goalie re-squares and is no longer unsettled")


func test_unsettled_follows_the_push() -> void:
	# Through one re-square his speed rises from rest, peaks, and is gone once he
	# is set — never past his top speed.
	var goalie := _goalie_at(_arc_match_x(-2.0))
	var peak: float = 0.0
	var peak_t: float = 0.0
	var prev: float = 0.0
	var rising: bool = true
	for i: int in 61:
		var t: float = i * 0.01
		var u := AIGoalieModel.goalie_unsettled(goalie, GOAL, t, SHOOTER)
		assert_between(u, 0.0, 1.0)
		if u > peak:
			peak = u
			peak_t = t
		if not rising:
			assert_true(u <= prev + 0.0001, "past his peak he only slows (t=%.2f)" % t)
		elif u < prev - 0.0001:
			rising = false
		prev = u
	assert_gt(peak, 0.0, "he moves across")
	assert_gt(peak_t, AIGoalieModel.goalie_leg_delay_s, "only after he reacts")
	assert_eq(prev, 0.0, "and is set by the end")


# ── goalie_squared_pos (carry destinations) ─────────────────────────────────

func test_squared_pos_arc_matches_the_puck() -> void:
	# The squared goalie sits at the arc-match x for the puck, at its own depth —
	# no time term (a carry destination: the keeper has tracked it there and is set).
	var goalie := _goalie_at(-1.3)                    # anywhere on its line
	var squared := AIGoalieModel.goalie_squared_pos(goalie, GOAL, SHOOTER)
	assert_almost_eq(squared.x, _arc_match_x(SHOOTER.x), 0.001,
			"squared goalie sits at the shooter's arc-match x")
	assert_almost_eq(squared.z, GOALIE_Z, 0.001, "…at its own depth, unchanged")


func test_squared_pos_reads_fully_settled_by_construction() -> void:
	# A goalie AT its squared position has zero forced motion — the carry model's
	# companion to unsettled=0: a squared keeper is never caught moving.
	var squared := AIGoalieModel.goalie_squared_pos(_goalie_at(0.0), GOAL, SHOOTER)
	var u := AIGoalieModel.goalie_unsettled(squared, GOAL, 0.13, SHOOTER)
	assert_almost_eq(u, 0.0, 0.001, "a squared goalie is fully settled at any release")


func test_squared_pos_ignores_reaction_time_unlike_predict() -> void:
	# The distinction that fixes the crease-chase: predict_goalie_pos (a shot/pass
	# the keeper reacts to) falls short of a fast diagonal relocation, but a carry's
	# squared model tracks it fully. From a standing centre, a quick release leaves
	# predict short of the arc-match while squared is already there.
	var centred := _goalie_at(0.0)
	var predicted := AIGoalieModel.predict_goalie_pos(centred, GOAL, 0.14, SHOOTER)
	var squared := AIGoalieModel.goalie_squared_pos(centred, GOAL, SHOOTER)
	var target: float = _arc_match_x(SHOOTER.x)
	assert_lt(predicted.x, target - 0.01, "react-then-slide falls short on a quick release")
	assert_almost_eq(squared.x, target, 0.001, "the squared carry model tracks all the way")

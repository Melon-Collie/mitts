extends GutTest

# AIOzPossessionTracker — the possession-value plan's measurement of `r`.
# Team 0 attacks -Z, so "deep in the offensive zone" is large negative z.

const TEAM: int = 0
const OPP: int = 1
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DEEP: float = -(GameRules.BLUE_LINE_Z + 6.0)
const OUT: float = -(GameRules.BLUE_LINE_Z - 2.0)
const DT: float = 1.0 / 120.0

var _t: AIOzPossessionTracker


func before_each() -> void:
	_t = AIOzPossessionTracker.new()


# `carrier` is a team_id, or -1 for loose. Runs `n` samples at `z`.
func _run(z: float, carrier: int, n: int = 1) -> void:
	for _i: int in n:
		_t.tick(TEAM, GOAL_Z, Vector3(0.0, 0.0, z), carrier, DT)


func _count(outcome: int) -> int:
	return _t.count(TEAM, outcome)


# ── Arming ───────────────────────────────────────────────────────────────────

func test_a_loose_puck_in_the_zone_does_not_arm() -> void:
	# The episode measures CONTROLLED possession: a puck nobody holds is not ours.
	_run(DEEP, -1, 60)
	_run(OUT, -1, 1)
	assert_eq(_t.total(TEAM), 0, "never controlled, never an episode")


func test_an_opponent_carrying_in_their_zone_does_not_arm() -> void:
	_run(DEEP, OPP, 60)
	assert_eq(_t.total(TEAM), 0)
	assert_false(_t.is_active(TEAM))


func test_a_carrier_on_the_blue_line_does_not_arm() -> void:
	_run(-(GameRules.BLUE_LINE_Z + 0.5), TEAM, 60)
	assert_false(_t.is_active(TEAM), "inside the line but not established")


# ── Outcomes ─────────────────────────────────────────────────────────────────

func test_a_shot_closes_the_episode_with_its_xg() -> void:
	_run(DEEP, TEAM, 120)
	_t.note_shot(TEAM, 0.08, Vector3(0.0, 0.0, DEEP), GOAL_Z, false)
	assert_eq(_count(AIOzPossessionTracker.Outcome.SHOT), 1)
	assert_almost_eq(_t.xg_sum(TEAM), 0.08, 1e-6)
	assert_false(_t.is_active(TEAM), "the shot ends the controlled stretch")


func test_loose_time_inside_an_episode_still_counts() -> void:
	# A pass in flight is still our possession.
	_run(DEEP, TEAM, 60)
	_run(DEEP, -1, 60)
	_run(DEEP, TEAM, 60)
	_t.close_on_stoppage()
	assert_almost_eq(_t.seconds(TEAM), 179.0 * DT, 1e-6,
			"every sample after the arming one is exposure")


func test_an_opponent_carrier_in_the_zone_is_a_turnover() -> void:
	_run(DEEP, TEAM, 30)
	_run(DEEP, OPP, 1)
	assert_eq(_count(AIOzPossessionTracker.Outcome.TURNOVER), 1)


func test_leaving_the_zone_is_an_exit() -> void:
	_run(DEEP, TEAM, 30)
	_run(OUT, TEAM, 1)
	assert_eq(_count(AIOzPossessionTracker.Outcome.EXIT), 1)


func test_stoppage_resolves_an_open_episode() -> void:
	_run(DEEP, TEAM, 30)
	_t.close_on_stoppage()
	assert_eq(_count(AIOzPossessionTracker.Outcome.STOPPAGE), 1)
	_t.close_on_stoppage()
	assert_eq(_t.total(TEAM), 1, "a second stoppage has nothing to close")


func test_a_re_established_carry_after_a_shot_opens_a_new_episode() -> void:
	_run(DEEP, TEAM, 30)
	_t.note_shot(TEAM, 0.05, Vector3(0.0, 0.0, DEEP), GOAL_Z, false)
	_run(DEEP, -1, 30)
	_run(DEEP, TEAM, 30)
	assert_true(_t.is_active(TEAM), "the recovery is a fresh controlled stretch")
	assert_almost_eq(_t.seconds(TEAM), 29.0 * DT, 1e-6,
			"the loose time after the shot is not exposure")


func test_a_shot_with_no_episode_open_is_counted_as_stray() -> void:
	_t.note_shot(TEAM, 0.05, Vector3(0.0, 0.0, DEEP), GOAL_Z, false)
	assert_eq(_t.stray_shots(TEAM), 1)
	assert_eq(_t.total(TEAM), 0)
	assert_almost_eq(_t.xg_sum(TEAM), 0.0, 1e-9, "stray xG never reaches the rate")


# ── The rate ─────────────────────────────────────────────────────────────────

func test_xg_rate_is_xg_over_controlled_seconds() -> void:
	_run(DEEP, TEAM, 241)   # 240 samples of exposure = 2 s
	_t.note_shot(TEAM, 0.10, Vector3(0.0, 0.0, DEEP), GOAL_Z, false)
	_run(DEEP, TEAM, 121)   # 1 s
	_t.note_shot(TEAM, 0.05, Vector3(0.0, 0.0, DEEP), GOAL_Z, false)
	assert_almost_eq(_t.xg_rate(TEAM), 0.15 / 3.0, 1e-6)
	assert_almost_eq(_t.mean_xg_per_shot(TEAM), 0.075, 1e-6)


func test_teams_are_tallied_separately() -> void:
	_t.tick(OPP, -GOAL_Z, Vector3(0.0, 0.0, -DEEP), OPP, DT)
	_t.tick(OPP, -GOAL_Z, Vector3(0.0, 0.0, -DEEP), OPP, DT)
	_t.note_shot(OPP, 0.2, Vector3(0.0, 0.0, -DEEP), -GOAL_Z, false)
	assert_eq(_t.count(OPP, AIOzPossessionTracker.Outcome.SHOT), 1)
	assert_eq(_t.total(TEAM), 0)


# ── Shot classification ──────────────────────────────────────────────────────

func test_long_range_is_beyond_the_tops_of_the_circles() -> void:
	var top: float = -(GameRules.GOAL_LINE_Z - AIZoneCoverage.HOUSE_TOP_DEPTH_M)
	assert_true(AIOzPossessionTracker.is_long_range(
			Vector3(0.0, 0.0, top + 0.5), GOAL_Z), "farther out than the tops")
	assert_false(AIOzPossessionTracker.is_long_range(
			Vector3(0.0, 0.0, top - 0.5), GOAL_Z), "inside the house")


func test_net_front_is_the_zone_coverage_box() -> void:
	var crease := Vector3(0.0, 0.0, GOAL_Z + 2.0)
	assert_true(AIOzPossessionTracker.is_net_front(crease, GOAL_Z))
	assert_false(AIOzPossessionTracker.is_net_front(
			Vector3(AIZoneCoverage.NET_FRONT_HALF_WIDTH_M + 0.5, 0.0, crease.z), GOAL_Z),
			"wide of the box")
	assert_false(AIOzPossessionTracker.is_net_front(
			Vector3(0.0, 0.0, GOAL_Z - 0.5), GOAL_Z), "behind the goal line")


func test_long_range_shots_split_by_net_front_presence() -> void:
	var point := Vector3(0.0, 0.0, -(GameRules.BLUE_LINE_Z + 2.5))
	_run(point.z, TEAM, 10)
	_t.note_shot(TEAM, 0.03, point, GOAL_Z, true)
	_run(point.z, TEAM, 10)
	_t.note_shot(TEAM, 0.02, point, GOAL_Z, false)
	_run(DEEP - 8.0, TEAM, 10)
	_t.note_shot(TEAM, 0.12, Vector3(0.0, 0.0, DEEP - 8.0), GOAL_Z, true)
	assert_eq(_t.long_range_shots(TEAM, true), 1)
	assert_eq(_t.long_range_shots(TEAM, false), 1)
	assert_almost_eq(_t.long_range_xg(TEAM, true), 0.03, 1e-6)


func test_every_outcome_has_a_name() -> void:
	for outcome: int in AIOzPossessionTracker.OUTCOME_COUNT:
		assert_ne(AIOzPossessionTracker.outcome_name(outcome), "?")

extends GutTest

# AIBodyCheck — pure commit-to-a-hit decision for on-puck defensive bots.
# Covers the gates (range, a contact on his arrival clock within the hunt's
# horizon, the hit his stride has built by then),
# the mass differentiation that falls out of the impulse prediction, and the
# self-stagger guard.
#
# The check transfer is flat for every build (0.65); the commit differentiation
# rides mass: the checker's own weight and the carrier's move the reduced-mass
# delivery, so a heavy build hunts hits and a light one declines checks it would
# bounce off a bigger target.

const SELF_POS := Vector3.ZERO
const VMAX: float = 9.0           # league top speed
const ACCEL: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
const TRANSFER: float = 0.65      # Skater.body_check_transfer, flat for every build
const CONTACT: float = 2.0 * AISkaterCaps.LEAGUE_BODY_RADIUS_M
const NEUTRAL_W: float = 1.0
const HEAVY_W: float = 1.28       # top of the mass range
const LIGHT_W: float = 0.79       # bottom of the mass range
# Skating in at speed, 4 m off a carrier ahead.
const SKATING := Vector3(7.0, 0.0, 0.0)
const AHEAD := Vector3(4.0, 0.0, 0.0)


func _eval(carrier_pos: Vector3, carrier_vel: Vector3, self_vel: Vector3 = SKATING,
		self_weight: float = NEUTRAL_W, victim_weight: float = NEUTRAL_W,
		threshold: float = AIBodyCheck.COMMIT_IMPULSE_M_S,
		stagger: float = 0.0) -> AIBodyCheck.Result:
	return AIBodyCheck.evaluate(SELF_POS, self_vel, VMAX, ACCEL, self_weight, TRANSFER,
			stagger, carrier_pos, carrier_vel, CONTACT, threshold, victim_weight)


# ── The hit he can land ──────────────────────────────────────────────────────

func test_commits_on_a_reachable_solid_hit() -> void:
	# Skating in at 7 m/s on a stationary carrier 4 m ahead: he meets him inside
	# the hunt at the speed his stride has built, well past the bar.
	var r: AIBodyCheck.Result = _eval(AHEAD, Vector3.ZERO)
	assert_true(r.commit, "commits to a reachable solid check")
	assert_almost_eq(r.target.x, 4.0, 0.3, "target is the body intercept")


func test_a_hit_from_a_standstill_a_stride_off_lands_soft() -> void:
	# Standing 1.5 m off a stationary carrier: the contact is near, but the stride
	# builds too little speed over 0.8 m to rock him. Priced at top speed, this
	# was a commit.
	var r: AIBodyCheck.Result = _eval(Vector3(1.5, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO)
	assert_false(r.commit, "no hunt for a hit the stride cannot build")


func test_a_standstill_far_off_cannot_reach_him_inside_the_hunt() -> void:
	var r: AIBodyCheck.Result = _eval(AHEAD, Vector3.ZERO, Vector3.ZERO)
	assert_false(r.commit, "4 m from rest is not a contact within the hunt's horizon")


# ── Mass differentiation ─────────────────────────────────────────────────────

func _bar_between(a: float, b: float) -> float:
	return 0.5 * (a + b)


func _kick(self_weight: float, victim_weight: float) -> float:
	# The impulse the reachable hit above delivers, read back through the bar: the
	# highest threshold it still commits at.
	var lo: float = 0.0
	var hi: float = 10.0
	for _i: int in 30:
		var mid: float = 0.5 * (lo + hi)
		if _eval(AHEAD, Vector3.ZERO, SKATING, self_weight, victim_weight, mid).commit:
			lo = mid
		else:
			hi = mid
	return lo


func test_heavier_checker_commits_where_a_lighter_one_bounces() -> void:
	var bar: float = _bar_between(_kick(HEAVY_W, NEUTRAL_W), _kick(LIGHT_W, NEUTRAL_W))
	assert_gt(_kick(HEAVY_W, NEUTRAL_W), _kick(LIGHT_W, NEUTRAL_W))
	assert_true(_eval(AHEAD, Vector3.ZERO, SKATING, HEAVY_W, NEUTRAL_W, bar).commit,
			"a heavy checker commits to the hit")
	assert_false(_eval(AHEAD, Vector3.ZERO, SKATING, LIGHT_W, NEUTRAL_W, bar).commit,
			"a light checker won't leave its feet for the same hit")


func test_heavier_victim_absorbs_the_check() -> void:
	var bar: float = _bar_between(_kick(NEUTRAL_W, LIGHT_W), _kick(NEUTRAL_W, HEAVY_W))
	assert_true(_eval(AHEAD, Vector3.ZERO, SKATING, NEUTRAL_W, LIGHT_W, bar).commit,
			"commits on a lighter carrier")
	assert_false(_eval(AHEAD, Vector3.ZERO, SKATING, NEUTRAL_W, HEAVY_W, bar).commit,
			"declines a heavy carrier that absorbs the hit")


# ── Closing-speed dependence ─────────────────────────────────────────────────

func test_closing_carrier_raises_the_hit() -> void:
	# A carrier skating INTO the check adds his speed to the closing line.
	var still: float = _kick(NEUTRAL_W, NEUTRAL_W)
	var bar: float = still + 0.5
	assert_false(_eval(AHEAD, Vector3.ZERO, SKATING, NEUTRAL_W, NEUTRAL_W, bar).commit,
			"holds vs a stationary carrier under a raised bar")
	assert_true(_eval(AHEAD, Vector3(-4.0, 0.0, 0.0), SKATING, NEUTRAL_W, NEUTRAL_W,
			bar).commit, "commits when the carrier closes on it")


# ── Range and reach ──────────────────────────────────────────────────────────

func test_no_commit_out_of_range() -> void:
	var r: AIBodyCheck.Result = _eval(Vector3(8.0, 0.0, 0.0), Vector3.ZERO)
	assert_false(r.commit, "no commit beyond CHECK_RANGE_M")


func test_no_commit_on_fleeing_carrier() -> void:
	# A carrier fleeing faster than the checker can close is never met.
	var r: AIBodyCheck.Result = _eval(AHEAD, Vector3(12.0, 0.0, 0.0))
	assert_false(r.commit, "no commit when the carrier outruns the closing line")


# ── Self-stagger guard ───────────────────────────────────────────────────────

func test_no_commit_while_staggered() -> void:
	var r: AIBodyCheck.Result = _eval(AHEAD, Vector3.ZERO, SKATING, NEUTRAL_W, NEUTRAL_W,
			AIBodyCheck.COMMIT_IMPULSE_M_S, 0.3)
	assert_false(r.commit, "a staggered checker can't deliver a hit")


# ── Difficulty commit-threshold (check_aggression pace knob) ─────────────────

func test_raised_commit_threshold_suppresses_a_marginal_hit() -> void:
	assert_true(_eval(AHEAD, Vector3.ZERO).commit, "commits at the default threshold")
	var raised: float = _kick(NEUTRAL_W, NEUTRAL_W) + 0.1
	assert_false(_eval(AHEAD, Vector3.ZERO, SKATING, NEUTRAL_W, NEUTRAL_W, raised).commit,
			"declines the same hit once the threshold is raised")


# The commit bar is a check that rocks him, short of what floors a square,
# upright man: the knockdown is the angle's and the moment's.
func test_the_commit_bar_rocks_him_short_of_the_knockdown() -> void:
	var cfg := BodyCheckRules.Config.new()
	assert_gte(AIBodyCheck.COMMIT_IMPULSE_M_S, cfg.ref_impulse)
	assert_lt(AIBodyCheck.COMMIT_IMPULSE_M_S, BodyBalanceRules.Config.new().balance_ref_dv)

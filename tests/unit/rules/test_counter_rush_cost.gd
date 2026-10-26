extends GutTest

# AIActionScoring.counter_rush_cost — the transition-exposure term (plan §6).
# Team 0 defends +Z. The canonical scene: our defenseman weighs a deep
# O-zone carry; the loss point is in THEIR end (where turnover_cost reads
# little) and the question is who beats the counter-rush home. The costs the
# current calibration gives at the reference scenes are the snapshot,
# test_counter_rush_calibration_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/counter_rush.txt"
const NET_Z: float = GameRules.GOAL_LINE_Z
const OUR_NET := Vector3(0.0, 0.0, NET_Z)
const OUR_GOALIE := Vector3(0.0, 0.0, NET_Z - 0.6)
# A loss deep in the offensive zone.
const LOSS_POINT := Vector3(6.0, 0.0, -20.0)
# How much sooner a stretch outlet must bring the counter home to count as one.
const STRETCH_LEAD_S: float = 0.5


func _cost(teammates: Array[Vector3], self_pos: Vector3,
		opponents: Array[Vector3], self_speed: float = 8.0) -> float:
	var opp_vels: Array[Vector3] = []
	var opp_caps: Array = []
	for _i: int in opponents.size():
		opp_vels.append(Vector3.ZERO)
		opp_caps.append(null)
	var self_caps := AISkaterCaps.new()
	self_caps.max_speed = self_speed
	return AIActionScoring.counter_rush_cost(
			LOSS_POINT, 1.0, OUR_NET, OUR_GOALIE, teammates, self_pos, self_caps, opponents,
			opp_vels, opp_caps)


# Their possession of the loss point with nobody of ours to contest it — what
# the carrier's turnover cost prices a loss at (AICarrierField.turnover_cost).
func _local_cost(loss_point: Vector3) -> float:
	var theirs := AIPossessionValue.new()
	var nobody: Array[Vector3] = []
	theirs.fill(OUR_NET, nobody, nobody, [])
	return theirs.at(loss_point)


func test_local_turnover_cost_falls_with_distance_from_our_net() -> void:
	# The premise of the counter term: the loss-point read prices a turnover by
	# where it happens, so it fades as the loss moves straight up-ice from our
	# slot and reads little for a loss deep in their end — which is exactly why
	# the counter must exist.
	# From 14 m out: closer in, the shot's in-tight odds fall toward the net.
	var prev: float = INF
	for z: float in [14.0, 8.0, 0.0, -8.0, -14.0, LOSS_POINT.z]:
		var cost: float = _local_cost(Vector3(0.0, 0.0, z))
		assert_lte(cost, prev + 1e-4, "a loss further up-ice never costs more (z %.0f)" % z)
		prev = cost
	assert_lt(_local_cost(LOSS_POINT),
			_local_cost(Vector3(0.0, 0.0, NET_Z - GameRules.SLOT_DIST_M)),
			"a deep O-zone loss carries less local threat than one in our slot")


# D1 weighs the deep carry with the checker right on the strip point; his
# partner either holds the point (goal-side with a head start on the counter)
# or is pinched deep with him.
func _one_up_one_back() -> Array[float]:
	var opponents: Array[Vector3] = [Vector3(6.0, 0.0, -19.5)]  # the checker
	var d1_deep := Vector3(6.0, 0.0, -20.0)
	var partner_home: Array[Vector3] = [Vector3(-5.0, 0.0, -8.3)]  # at the point
	var partner_deep: Array[Vector3] = [Vector3(-6.0, 0.0, -21.0)]
	return [_cost(partner_home, d1_deep, opponents), _cost(partner_deep, d1_deep, opponents)]


func test_one_up_one_back_is_cheap_both_deep_is_expensive() -> void:
	var costs: Array[float] = _one_up_one_back()
	assert_gt(costs[1], 0.0, "an uncovered counter carries a cost")
	assert_lt(costs[0], costs[1], "a partner holding the point lowers the exposure")


# The covering-set contract with the carrier himself as the racer: same loss at
# centre ice, same collector, no teammates — only where he recovers from moves.
func _self_cover_cost(recover_from: Vector3) -> float:
	var net := Vector3(0, 0, NET_Z)
	var goalie := Vector3(0, 0, NET_Z - 0.8)
	var opps: Array[Vector3] = [Vector3(1, 0, 1)]     # collector on the puck
	var vels: Array[Vector3] = [Vector3.ZERO]
	var no_mates: Array[Vector3] = []
	return AIActionScoring.counter_rush_cost(
			Vector3.ZERO, 1.0, net, goalie, no_mates,
			recover_from, null, opps, vels, [])


func test_covering_self_erases_the_counter_from_a_recoverable_spot() -> void:
	# Standing where he beats the counter home puts him in the covering set;
	# the further up-ice past the play he stands, the less he can cover.
	var prev: float = -INF
	for z: float in [14.0, 8.0, 2.0, -4.0, -10.0, -15.0]:
		var cost: float = _self_cover_cost(Vector3(0, 0, z))
		assert_gte(cost, prev - 1e-4, "recovering from further up-ice never costs less (z %.0f)" % z)
		prev = cost
	assert_lt(_self_cover_cost(Vector3(0, 0, 14)), _self_cover_cost(Vector3(0, 0, -15)),
			"a recoverable spot covers the counter that a spot past the play leaves live")


func test_a_fast_carrier_covers_himself() -> void:
	# Same scene, no teammates back — but a burner recovers in time where a
	# plodder can't. Speed buys activation freedom, straight from the model.
	var opponents: Array[Vector3] = [Vector3(0.0, 0.0, -6.0)]
	var nobody: Array[Vector3] = []
	var slow: float = _cost(nobody, LOSS_POINT, opponents, 5.5)
	var fast: float = _cost(nobody, LOSS_POINT, opponents, 12.0)
	assert_lt(fast, slow, "the faster carrier's own recovery discounts the counter")


func test_no_opponents_no_cost() -> void:
	var nobody: Array[Vector3] = []
	var opps: Array[Vector3] = []
	assert_eq(_cost(nobody, LOSS_POINT, opps), 0.0)


func test_zero_loss_prob_is_free() -> void:
	var opponents: Array[Vector3] = [Vector3(0.0, 0.0, -12.0)]
	var nobody: Array[Vector3] = []
	var opp_vels: Array[Vector3] = [Vector3.ZERO]
	var opp_caps: Array = [null]
	assert_eq(AIActionScoring.counter_rush_cost(
			LOSS_POINT, 0.0, OUR_NET, OUR_GOALIE, nobody, LOSS_POINT, null, opponents, opp_vels,
			opp_caps), 0.0)


func test_sooner_counter_costs_more() -> void:
	# The cost decays over the counter's development time: an opponent
	# already on the loss point (the stripping defender) builds the rush
	# sooner — and prices higher — than one who must skate across the rink
	# to collect it first.
	var nobody: Array[Vector3] = []
	var at_strip: Array[Vector3] = [Vector3(6.0, 0.0, -19.0)]
	var across_rink: Array[Vector3] = [Vector3(-11.0, 0.0, 5.0)]
	var soon_cost: float = _cost(nobody, LOSS_POINT, at_strip, 5.5)
	var late_cost: float = _cost(nobody, LOSS_POINT, across_rink, 5.5)
	assert_gt(soon_cost, late_cost)


func test_stretch_outlet_makes_the_deep_loss_dearer() -> void:
	# The PASS-FORWARD leg: the checker collecting in the corner doesn't lug
	# it 50 m himself — he hits the stretch man already at center, who
	# carries home. The lone-carrier read gave every recovering body the
	# collector's full lug to race; with a genuine outlet ahead, the counter
	# arrives sooner and the same defensive shape covers less. Control: the
	# outlet parked BEHIND the play (deeper than the collector's own carry)
	# adds nothing — the feed only helps when it actually gains ice.
	var opponents_stretch: Array[Vector3] = [
		Vector3(6.0, 0.0, -19.5),   # the checker (collector)
		Vector3(0.0, 0.0, 2.0),     # stretch outlet past center
	]
	var opponents_trailer: Array[Vector3] = [
		Vector3(6.0, 0.0, -19.5),
		Vector3(0.0, 0.0, -24.0),   # a trailer even deeper than the loss
	]
	var d1_deep := Vector3(6.0, 0.0, -20.0)
	# Partner recovering from mid-ice: covers the slow lug, not the strike.
	var partner: Array[Vector3] = [Vector3(-4.0, 0.0, -2.0)]
	var with_stretch: float = _cost(partner, d1_deep, opponents_stretch)
	var with_trailer: float = _cost(partner, d1_deep, opponents_trailer)
	# Same covering set either way, so the whole difference is the CLOCK: the
	# stretch counter must be at least half a second sooner (it measures ~0.83 s).
	# Stated in time, not as a cost ratio, because the ratio is exp(dt / tau) and
	# moves with READ_VALIDITY_TAU_S while the behavior does not.
	assert_gt(with_stretch * AIActionScoring.delay_discount(STRETCH_LEAD_S),
			with_trailer, "a live stretch outlet raises the deep carry's price")


func test_counter_rush_calibration_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	snap.record("local turnover cost, deep O-zone loss", _local_cost(LOSS_POINT))
	var pair: Array[float] = _one_up_one_back()
	snap.record("deep carry, partner holding the point", pair[0])
	snap.record("deep carry, partner pinched deep too", pair[1])
	snap.record("centre-ice loss, carrier recovers from our slot", _self_cover_cost(Vector3(0, 0, 14)))
	snap.record("centre-ice loss, carrier 15 m past the play", _self_cover_cost(Vector3(0, 0, -15)))
	snap.verify(self)


func test_a_collector_skating_away_from_our_net_brings_the_counter_later() -> void:
	# The counter is collect-and-carry on the arrival clock: a man who collects
	# skating up-ice has to turn it home, one already skating home does not.
	var opps: Array[Vector3] = [Vector3(6.0, 0.0, -22.0)]   # just past the loss
	var away: Array[Vector3] = [Vector3(0.0, 0.0, -7.0)]
	var home: Array[Vector3] = [Vector3(0.0, 0.0, 7.0)]
	assert_gt(AIActionScoring.counter_time(LOSS_POINT, OUR_NET, opps, away, [null]),
			AIActionScoring.counter_time(LOSS_POINT, OUR_NET, opps, home, [null]))


func test_the_counter_is_never_home_before_the_puck_is_collected() -> void:
	# A lone opponent nearer our net than the loss cannot feed himself: his
	# counter starts when he has the puck.
	var opps: Array[Vector3] = [Vector3(0.0, 0.0, -6.0)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var t_collect: float = AIArrival.time_to_arrive_caps(opps[0], LOSS_POINT, Vector3.ZERO, null)
	assert_gt(AIActionScoring.counter_time(LOSS_POINT, OUR_NET, opps, vels, [null]), t_collect)


func test_a_mate_covers_by_standing_set_on_his_own_build() -> void:
	# Cover is the mate's arrival on his build and momentum plus his brake: the
	# same spot covers sooner standing than skating away from home.
	var mates: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0)]
	var vels: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 0.0, -8.0)]
	var etas: Array[float] = []
	AIActionScoring.fill_counter_cover_etas(OUR_NET, mates, vels, [null, null], etas)
	assert_lt(etas[0], etas[1], "skating up-ice at full stride he is home later")
	var cp: Vector3 = AIActionScoring.counter_point_for(OUR_NET)
	assert_almost_eq(etas[0], AIArrival.time_to_arrive_caps(mates[0], cp, Vector3.ZERO, null)
			+ AIArrival.set_margin_s(null), 1e-4, "arrival, then the brake to set")

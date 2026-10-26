extends GutTest

# AIPossessionValue — what the puck at a spot is worth to the side attacking a
# net, in the shot field's odds: the shot or a drive in the zone, the best entry
# outside it, each raced against the defence.

const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)

var _none: Array[Vector3] = []


func _read(defenders: Array[Vector3], goal: Vector3 = GOAL) -> AIPossessionValue:
	var v := AIPossessionValue.new()
	var vels: Array[Vector3] = []
	for _d: Vector3 in defenders:
		vels.append(Vector3.ZERO)
	v.fill(goal, defenders, vels, [])
	return v


func test_in_the_zone_it_is_at_least_the_shot() -> void:
	var v: AIPossessionValue = _read(_none)
	for spot: Vector3 in [Vector3(0, 0, -18), Vector3(-6, 0, -20), Vector3(8, 0, -12)]:
		assert_gte(v.at(spot), AIActionScoring.score_shoot_value(spot, GOAL, Vector3.INF, _none)
				- 1e-6, "%s" % spot)


func test_a_defender_on_the_drive_takes_it() -> void:
	# From the corner the shot is nothing: the spot's own play is its drive in.
	var corner := Vector3(-10.0, 0.0, -22.0)
	var open: float = _read(_none)._drive(corner, 0.0)
	assert_gt(open, 0.0, "an open drive from the corner is worth something")
	var home: Array[Vector3] = [Vector3(-4.5, 0.0, -24.4)]
	assert_lt(_read(home)._drive(corner, 0.0), open, "a defender home first takes it away")


func test_closer_to_the_zone_is_worth_more() -> void:
	var v: AIPossessionValue = _read(_none)
	var prev: float = 0.0
	for z: float in [20.0, 10.0, 0.0, -5.0]:
		var here: float = v.at(Vector3(0.0, 0.0, z))
		assert_gt(here, prev, "the middle at z %.0f" % z)
		prev = here


func test_crossing_the_line_never_costs_the_puck_value() -> void:
	# A man just inside the line can still skate to any entry a man just outside
	# it would take, so stepping over the line on any lane never reads lower.
	var v: AIPossessionValue = _read(_none)
	for x: float in [0.0, -4.0, -9.0, -12.0]:
		var prev: float = 0.0
		for z: float in [-5.0, -7.0, -7.5, -8.0, -9.0, -10.0]:
			var here: float = v.at(Vector3(x, 0.0, z))
			assert_gte(here, prev - 1e-6, "x %.0f, z %.0f" % [x, z])
			prev = here


func test_a_body_on_his_stick_costs_him_the_puck_where_the_line_is_his() -> void:
	# Neither defender is set at the line; the one in reach of his skate, standing
	# between him and the zone, takes the puck off it.
	var spot := Vector3(0.0, 0.0, 4.0)
	var on_him: Array[Vector3] = [Vector3(0.8, 0.0, 2.8)]
	var far_back: Array[Vector3] = [Vector3(1.0, 0.0, 16.0)]
	var open: float = _read(_none).at(spot)
	assert_gt(_read(far_back).at(spot), open * 0.8,
			"a man he leaves behind costs him only what his backcheck recovers")
	assert_lt(_read(on_him).at(spot), open * 0.8, "a body on his stick does")


func test_a_defender_who_gets_to_the_entries_first_shuts_them() -> void:
	var spot := Vector3(0.0, 0.0, 5.0)
	var open: float = _read(_none).at(spot)
	var line: Array[Vector3] = [Vector3(-10.0, 0, -9.0), Vector3(0.0, 0, -9.0), Vector3(10.0, 0, -9.0)]
	assert_lt(_read(line).at(spot), open * 0.5, "a defence standing up at its line")


func test_later_is_worth_less() -> void:
	var v: AIPossessionValue = _read(_none)
	var spot := Vector3(4.0, 0.0, -16.0)
	assert_lt(v.at(spot, 1.0), v.at(spot))


func test_both_ends_read_alike() -> void:
	var d: Array[Vector3] = [Vector3(3.0, 0, -10.0), Vector3(-5.0, 0, -18.0)]
	var mirrored: Array[Vector3] = [Vector3(-3.0, 0, 10.0), Vector3(5.0, 0, 18.0)]
	var ours: AIPossessionValue = _read(d)
	var theirs: AIPossessionValue = _read(mirrored, -GOAL)
	for spot: Vector3 in [Vector3(-8, 0, -20), Vector3(2, 0, 4), Vector3(9, 0, 15)]:
		assert_almost_eq(theirs.at(Vector3(-spot.x, 0.0, -spot.z)), ours.at(spot), 1e-4,
				"%s" % spot)


func test_a_man_skating_at_the_zone_is_worth_more_than_one_skating_away() -> void:
	var v: AIPossessionValue = _read(_none)
	var spot := Vector3(0.0, 0.0, 6.0)
	var standing: float = v.at(spot)
	assert_gt(v.at(spot, 0.0, Vector3(0.0, 0.0, -7.0)), standing, "skating at it")
	assert_lt(v.at(spot, 0.0, Vector3(0.0, 0.0, 7.0)), standing, "skating away")


func test_his_speed_carries_the_drive_in() -> void:
	var v: AIPossessionValue = _read(_none)
	var corner := Vector3(-10.0, 0.0, -22.0)
	assert_gt(v.at(corner, 0.0, Vector3(4.0, 0.0, -1.0)), v.at(corner),
			"already moving toward the net, he gets there sooner")


# Entries are priced only when a read could use them, bounded until then by
# their empty-ice worth. Both halves of that are held here: no defence raises an
# entry above the bound, and a lazy read — a body pushed on it included — reads
# what pricing every entry first reads.
func test_entries_priced_on_demand_read_as_priced_up_front() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spots: Array[Vector3] = [Vector3(0, 0, 5), Vector3(-9, 0, -3), Vector3(6, 0, -9),
			Vector3(-12, 0, -12), Vector3(3, 0, -18), Vector3(10, 0, 12)]
	for trial: int in 40:
		var defenders: Array[Vector3] = []
		for _k: int in rng.randi_range(0, 5):
			defenders.append(Vector3(rng.randf_range(-12.0, 12.0), 0.0,
					rng.randf_range(-24.0, 20.0)))
		var body := Vector3(rng.randf_range(-10.0, 10.0), 0.0, rng.randf_range(-20.0, 10.0))
		var eager: AIPossessionValue = _read(defenders.duplicate())
		for i: int in eager._entry_spots.size():
			assert_lte(eager._worth(i), eager._open_worth[i] + 1e-6,
					"trial %d: a defence never raises entry %d" % [trial, i])
		# Cleared, or the lazy read takes the eager one's shared entries.
		AIPossessionValue._shared.clear()
		var lazy: AIPossessionValue = _read(defenders.duplicate())
		for spot: Vector3 in spots:
			assert_almost_eq(lazy.at(spot), eager.at(spot), 1e-6,
					"trial %d at %s" % [trial, spot])
		AIPossessionValue._shared.clear()
		lazy = _read(defenders.duplicate())
		lazy.push_defender(body, Vector3.ZERO, null)
		eager.push_defender(body, Vector3.ZERO, null)
		for spot: Vector3 in spots:
			assert_almost_eq(lazy.at(spot), eager.at(spot), 1e-6,
					"trial %d at %s, a body pushed" % [trial, spot])
		lazy.pop_defender()
		eager.pop_defender()


# Reads of the same defence share their entries' worths. Sharing must never
# change an answer: a read that takes them reads what one priced alone does, a
# different defence never takes them, and a read whose slot went to another
# defence prices its own again.
func test_reads_of_one_defence_share_entries_and_no_other_does() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var spots: Array[Vector3] = [Vector3(0, 0, 5), Vector3(-9, 0, -3), Vector3(10, 0, 12)]
	for trial: int in 20:
		var defenders: Array[Vector3] = []
		for _k: int in rng.randi_range(1, 5):
			defenders.append(Vector3(rng.randf_range(-12.0, 12.0), 0.0,
					rng.randf_range(-24.0, 20.0)))
		AIPossessionValue._shared.clear()
		var alone: Array[float] = []
		var fresh: AIPossessionValue = _read(defenders.duplicate())
		for spot: Vector3 in spots:
			alone.append(fresh.at(spot))
		AIPossessionValue._shared.clear()
		var first: AIPossessionValue = _read(defenders.duplicate())
		for i: int in first._entry_spots.size():
			first._worth(i)
		var second: AIPossessionValue = _read(defenders.duplicate())
		for j: int in spots.size():
			assert_almost_eq(second.at(spots[j]), alone[j], 1e-6,
					"trial %d: a shared read at %s" % [trial, spots[j]])
		assert_true(second._slot == first._slot, "trial %d: the same defence shares" % trial)
		var moved: Array[Vector3] = defenders.duplicate()
		moved[0] += Vector3(0.5, 0.0, 0.0)
		var other: AIPossessionValue = _read(moved)
		other._worth(0)
		assert_false(other._slot == first._slot, "trial %d: another defence does not" % trial)
		# Hand every slot to another defence; the first read prices its own again.
		for k: int in AIPossessionValue.SHARED_ENTRY_SLOTS:
			var evict: Array[Vector3] = [Vector3(float(k), 0.0, 30.0)]
			_read(evict)._worth(0)
		var again: AIPossessionValue = _read(defenders.duplicate())
		for j: int in spots.size():
			assert_almost_eq(again.at(spots[j]), alone[j], 1e-6,
					"trial %d: after eviction at %s" % [trial, spots[j]])
		first._entry_worth.fill(-1.0)
		for j: int in spots.size():
			assert_almost_eq(first.at(spots[j]), alone[j], 1e-6,
					"trial %d: a read whose slot was taken, at %s" % [trial, spots[j]])


# ── The defence's read of a man ──────────────────────────────────────────────

const OUR_NET := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)    # the defence defends +Z
const OUR_KEEPER := Vector3(0.5, 0.0, GameRules.GOAL_LINE_Z - 0.6)
const SCORE: int = AIPossessionValue.Objective.SCORE


func _defence(defenders: Array[Vector3], caps: Array) -> AIPossessionValue:
	var v := AIPossessionValue.new()
	var vels: Array[Vector3] = []
	for _d: Vector3 in defenders:
		vels.append(Vector3.ZERO)
	v.fill(OUR_NET, defenders, vels, caps)
	return v


func test_a_feed_is_covered_by_the_defenders_real_build() -> void:
	# 2.0 m off the lane: inside the league blade's closing reach at this feed's
	# pace, but not saturated, so a long and a short stick both move it.
	var carrier := Vector3(0.0, 0.0, 8.0)
	var receiver := Vector3(0.0, 0.0, 22.0)
	var d: Array[Vector3] = [Vector3(2.0, 0.0, 15.0)]
	var league: float = _defence(d, []).threat_of_feed(carrier, receiver, Vector3.ZERO,
			OUR_KEEPER, SCORE)
	var long_stick := AISkaterCaps.new()
	long_stick.stick_reach = 1.6
	long_stick.max_speed = 12.0
	var short_stick := AISkaterCaps.new()
	short_stick.stick_reach = 1.1
	short_stick.max_speed = 6.0
	assert_lt(_defence(d, [long_stick]).threat_of_feed(carrier, receiver, Vector3.ZERO,
			OUR_KEEPER, SCORE), league, "a long-stick defender covers more of the feed")
	assert_gt(_defence(d, [short_stick]).threat_of_feed(carrier, receiver, Vector3.ZERO,
			OUR_KEEPER, SCORE), league, "a short-stick defender concedes more of it")


func test_a_carrier_threatens_at_least_his_shot_and_his_possession() -> void:
	var none: Array[Vector3] = []
	var v: AIPossessionValue = _defence(none, [])
	var slot := Vector3(0.0, 0.0, 18.0)
	assert_gte(v.threat_of_carrier(slot, Vector3.ZERO, OUR_KEEPER, SCORE), v.at(slot) - 1e-6)
	assert_gte(v.threat_of_carrier(slot, Vector3.ZERO, OUR_KEEPER, SCORE),
			AIActionScoring.score_shoot_value(slot, OUR_NET, OUR_KEEPER, none) - 1e-6)


func test_the_currency_is_where_the_decider_plays() -> void:
	var v: AIPossessionValue = _defence([] as Array[Vector3], [])
	assert_eq(v.objective_at(Vector3(0.0, 0.0, 16.0), OUR_KEEPER), SCORE,
			"in the attacked zone, scoring")
	assert_eq(v.objective_at(Vector3(0.0, 0.0, 0.0), OUR_KEEPER),
			AIPossessionValue.Objective.ENTER, "in the neutral zone, getting in")
	assert_eq(v.objective_at(Vector3(0.0, 0.0, -16.0), OUR_KEEPER),
			AIPossessionValue.Objective.EXIT, "in his own zone, getting out")
	assert_eq(v.objective_at(Vector3(0.0, 0.0, -16.0), Vector3(0.0, 0.0, 10.0)), SCORE,
			"with the keeper off his net, a shot from anywhere: scoring")


func test_outside_the_zone_a_man_threatens_his_odds_of_getting_in() -> void:
	var v: AIPossessionValue = _defence([Vector3(0.0, 0.0, 9.0)] as Array[Vector3], [])
	var man := Vector3(-4.0, 0.0, 2.0)
	var enter: int = AIPossessionValue.Objective.ENTER
	assert_almost_eq(v.threat_of_carrier(man, Vector3.ZERO, OUR_KEEPER, enter),
			v.p_enter(man), 1e-6, "his entry, not a shot dead from there")
	var carrier := Vector3(4.0, 0.0, 0.0)
	assert_lte(v.threat_of_feed(carrier, man, Vector3.ZERO, OUR_KEEPER, enter),
			v.p_enter(man), "a feed to him is worth at most his entry")


func test_a_body_on_the_lane_takes_the_feed() -> void:
	var none: Array[Vector3] = []
	var v: AIPossessionValue = _defence(none, [])
	var carrier := Vector3(-8.0, 0.0, 20.0)
	var receiver := Vector3(3.0, 0.0, 21.0)
	var open: float = v.threat_of_feed(carrier, receiver, Vector3.ZERO, OUR_KEEPER, SCORE)
	v.push_defender(Vector3(-2.5, 0.0, 20.5), Vector3.ZERO, null)
	var covered: float = v.threat_of_feed(carrier, receiver, Vector3.ZERO, OUR_KEEPER, SCORE)
	v.pop_defender()
	assert_lt(covered, open * 0.5, "a stick in the lane")
	assert_almost_eq(v.threat_of_feed(carrier, receiver, Vector3.ZERO, OUR_KEEPER, SCORE), open,
			1e-6, "and off again, the read is as it was")


# ── The contest at the line ──────────────────────────────────────────────────

func test_a_defender_set_at_his_line_shadows_the_carriers_lane_not_the_whole_line() -> void:
	# He takes the carrier→net line at his depth where the carrier is heading;
	# the crossing that carrier picks late is the lunge's to cover, so the far
	# lane stays open however long the skate, until the carrier heads for it.
	var line_z: float = -GameRules.BLUE_LINE_Z
	var v: AIPossessionValue = _read([Vector3(-6.0, 0.0, line_z - 0.4)])
	var carrier := Vector3(0.0, 0.0, 6.0)
	var up_ice := Vector3(0.0, 0.0, -6.0)
	var middle := Vector3(0.0, 0.0, line_z)
	var wide := Vector3(GameRules.RINK_HALF_WIDTH - AIPossessionValue.ENTRY_WALL_INSET_M,
			0.0, line_z)
	assert_lt(v._line_keep(middle, 2.5, carrier, up_ice, line_z), 0.1,
			"the lane the carrier is skating is his")
	assert_gt(v._line_keep(wide, 2.5, carrier, up_ice, line_z), 0.9,
			"the far lane is open to a late choice")
	var at_wide := Vector3(wide.x - carrier.x, 0.0, wide.z - carrier.z).normalized() * 6.0
	assert_lt(v._line_keep(wide, 2.5, carrier, at_wide, line_z), 0.1,
			"and his once the carrier heads for it")


func test_a_defender_gapped_back_leaves_the_line_to_the_drive() -> void:
	var line_z: float = -GameRules.BLUE_LINE_Z
	var middle := Vector3(0.0, 0.0, line_z)
	var gapped: AIPossessionValue = _read([Vector3(0.0, 0.0, line_z - 7.0)])
	assert_gt(gapped._line_keep(middle, 1.0, Vector3(0.0, 0.0, 4.0), Vector3(0.0, 0.0, -6.0), line_z),
			0.9, "he is no wall at the line")
	assert_lt(gapped._drive(Vector3(0.0, 0.0, line_z - AIPossessionValue.ENTRY_LEAD_M), 0.0),
			_read(_none)._drive(Vector3(0.0, 0.0, line_z - AIPossessionValue.ENTRY_LEAD_M), 0.0),
			"the drive in from the crossing is where he costs it")


func test_a_man_up_his_lane_is_no_worse_off_against_a_set_line_than_one_further_back() -> void:
	# The men set inside the line are charged at the line contest alone, however
	# near the skate brings him: nearer the line, the same defence costs no more.
	var line_z: float = -GameRules.BLUE_LINE_Z
	var v: AIPossessionValue = _read([Vector3(4.0, 0.0, line_z - 0.7),
			Vector3(6.0, 0.0, line_z - 0.6)])
	var up_ice := Vector3(0.0, 0.0, -7.0)
	var near: float = v.at(Vector3(8.5, 0.0, -0.2), 0.0, up_ice)
	var far: float = v.at(Vector3(8.5, 0.0, 9.0), 0.0, up_ice)
	assert_gte(near, far, "a stride from the line, up his own lane")


# ── The zone currency (docs/zone-currency-plan.md) ──────────────────────────

func test_a_man_in_the_attacked_zone_has_already_got_in() -> void:
	assert_almost_eq(_read(_none).p_next(Vector3(0.0, 0.0, -15.0)), 1.0, 1e-6)


func test_on_open_ice_nearer_the_line_gets_in_surer() -> void:
	var v: AIPossessionValue = _read(_none)
	var up_ice := Vector3(0.0, 0.0, -6.0)
	var far: float = v.p_next(Vector3(0.0, 0.0, 6.0), 0.0, up_ice)
	var near: float = v.p_next(Vector3(0.0, 0.0, -2.0), 0.0, up_ice)
	assert_gt(far, 0.5, "open ice is an entry")
	assert_gt(near, far, "and the nearer one is surer")


func test_a_man_standing_up_at_the_line_costs_the_entry() -> void:
	var line_z: float = -GameRules.BLUE_LINE_Z
	var spot := Vector3(0.0, 0.0, -1.0)
	var up_ice := Vector3(0.0, 0.0, -6.0)
	var open: float = _read(_none).p_next(spot, 0.0, up_ice)
	var stood: float = _read([Vector3(-3.0, 0.0, line_z - 0.5), Vector3(3.0, 0.0, line_z - 0.5)]) \
			.p_next(spot, 0.0, up_ice)
	assert_lt(stood, open, "a pair standing up at their line takes some of it")


func test_in_our_zone_the_next_line_is_ours_and_a_forechecker_costs_it() -> void:
	var spot := Vector3(3.0, 0.0, 14.0)
	var out_ice := Vector3(0.0, 0.0, -4.0)
	var open: float = _read(_none).p_next(spot, 0.0, out_ice)
	assert_gt(open, 0.5, "an open way out")
	var checked: float = _read([Vector3(3.0, 0.0, 11.0)]).p_next(spot, 0.0, out_ice)
	assert_lt(checked, open, "a forechecker in the way costs the exit")


func test_from_our_zone_getting_in_is_getting_out_and_then_in() -> void:
	var v: AIPossessionValue = _read(_none)
	var spot := Vector3(3.0, 0.0, 14.0)
	var out_ice := Vector3(0.0, 0.0, -4.0)
	var enter: float = v.p_enter(spot, 0.0, out_ice)
	assert_gt(enter, 0.0)
	assert_lte(enter, v.p_next(spot, 0.0, out_ice) + 1e-6, "no surer than getting out")

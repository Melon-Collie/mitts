extends GutTest

# AIRoleSlots is pure-function. Tests cover slot lists per state and
# assignment via state-specific semantic queries (soonest-to-puck,
# soonest-to-net, goal-side gap defender). Elections are momentum-aware
# (time_to_arrive at each peer's Speed cap); stationary peers with
# default caps reduce to distance ordering, which most tests use.

const OUR_NET_Z: float = 26.65
const TEAM_ID: int = 0


func _make_snapshot(skaters: Array, carrier_pid: int = -1, puck_z: float = 0.0,
		puck_x: float = 0.0) -> WorldSnapshot:
	# skaters: Array of [peer_id, team_id, position] or
	# [peer_id, team_id, position, velocity]
	var snap := WorldSnapshot.new()
	for entry: Array in skaters:
		var s := SkaterNetworkState.new()
		s.position = entry[2]
		if entry.size() > 3:
			s.velocity = entry[3]
		snap.skater_states[entry[0]] = s
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = carrier_pid
	if carrier_pid != -1:
		for entry: Array in skaters:
			if entry[0] == carrier_pid:
				puck.position = entry[2]
				break
	else:
		puck.position = Vector3(puck_x, 0.0, puck_z)
	snap.puck_state = puck
	return snap


func _resolver(skaters: Array) -> Dictionary:
	var team_map: Dictionary = {}
	for entry: Array in skaters:
		team_map[entry[0]] = entry[1]
	return team_map


func test_assign_dzone_distributes_slots() -> void:
	# PRESSURE = closest to the puck; the other two MARK a man each. Which
	# marker ends up net-front vs. weak-side is decided downstream by the threat
	# partition, not here — so both non-pressure peers are simply MARK.
	var skaters: Array = [
			[100, 0, Vector3(4.5, 0.0, 22.5)],   # closest to puck → PRESSURE
			[110, 0, Vector3(0.5, 0.0, 25.65)],
			[120, 0, Vector3(-2.0, 0.0, 22.65)],
			[200, 1, Vector3(5.0, 0.0, 22.0)],
	]
	var snap := _make_snapshot(skaters, 200)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.DZONE,
			_resolver(skaters), {})
	assert_eq(assignments[100], AIRoleSlots.Slot.PRESSURE)
	assert_eq(assignments[110], AIRoleSlots.Slot.MARK)
	assert_eq(assignments[120], AIRoleSlots.Slot.MARK)


func test_assign_ozone_carrier_is_fixed() -> void:
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, -22.0)],
			[110, 0, Vector3(-3.0, 0.0, -25.0)],
			[120, 0, Vector3(0.0, 0.0, -16.0)],
	]
	var snap := _make_snapshot(skaters, 100)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.OZONE,
			_resolver(skaters), {})
	assert_eq(assignments[100], AIRoleSlots.Slot.CARRIER)
	assert_true(assignments.has(110))
	assert_true(assignments.has(120))
	# OZONE non-carrier slots are FINISHER and SUPPORT (no OUTLET).
	var non_carrier_slots: Array = [assignments[110], assignments[120]]
	assert_true(AIRoleSlots.Slot.FINISHER in non_carrier_slots)
	assert_true(AIRoleSlots.Slot.SUPPORT in non_carrier_slots)


func test_assign_trans_do_geometry_drives_outlet_and_support() -> void:
	# Carrier at NZ. Bot up-ice in OZ → OUTLET. Bot deep in DZ → SUPPORT.
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, 0.0)],   # carrier (NZ center)
			[110, 0, Vector3(-4.0, 0.0, -13.0)],# up-ice weak-side near OUTLET anchor
			[120, 0, Vector3(0.0, 0.0, 5.0)],   # deeper, near SUPPORT anchor
	]
	var snap := _make_snapshot(skaters, 100)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.TRANS_OFFENSE,
			_resolver(skaters), {})
	assert_eq(assignments[100], AIRoleSlots.Slot.CARRIER)
	assert_eq(assignments[110], AIRoleSlots.Slot.OUTLET, "up-ice bot becomes OUTLET")
	assert_eq(assignments[120], AIRoleSlots.Slot.SUPPORT, "deep bot becomes SUPPORT")


func test_breakout_strong_keeps_the_outlet_role_across_the_handoff() -> void:
	# BREAKOUT→TRANS_OFFENSE renames BREAKOUT_STRONG→OUTLET; the peer that was the
	# up-ice strong-side outlet should STAY the up-ice OUTLET across the flip
	# (hysteresis continuity class), not swap destinations with the trailer.
	# Two peers tied on ETA to the opp net: the pid tiebreak alone would hand
	# OUTLET to the lower pid (110), but 120 held BREAKOUT_STRONG last tick, so
	# the continuity bonus keeps OUTLET on 120.
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, 0.0)],    # carrier at NZ
			[110, 0, Vector3(-3.0, 0.0, -10.0)], # tied ETA to opp net
			[120, 0, Vector3(3.0, 0.0, -10.0)],  # tied ETA to opp net
	]
	var snap := _make_snapshot(skaters, 100)
	var prev: Dictionary = {
			120: AIRoleSlots.Slot.BREAKOUT_STRONG,
			110: AIRoleSlots.Slot.BREAKOUT_WEAK,
	}
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.TRANS_OFFENSE,
			_resolver(skaters), prev)
	assert_eq(assignments[120], AIRoleSlots.Slot.OUTLET,
			"the ex-BREAKOUT_STRONG peer stays the up-ice OUTLET")
	assert_eq(assignments[110], AIRoleSlots.Slot.SUPPORT,
			"the ex-BREAKOUT_WEAK peer stays the trailer")


func test_assign_breakout_strong_goes_to_strong_side_peer() -> void:
	# Carrier deep in our own zone. Strong side is +X (default
	# _strong_x = +1), so the +X non-carrier takes BREAKOUT_STRONG and
	# the -X one takes the weak-side reverse (BREAKOUT_WEAK).
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, 20.0)],   # carrier, deep in our DZ
			[110, 0, Vector3(9.0, 0.0, 12.0)],   # +X side → STRONG
			[120, 0, Vector3(-9.0, 0.0, 20.0)],  # -X side → WEAK
	]
	var snap := _make_snapshot(skaters, 100)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.BREAKOUT,
			_resolver(skaters), {}, 1.0)
	assert_eq(assignments[100], AIRoleSlots.Slot.CARRIER)
	assert_eq(assignments[110], AIRoleSlots.Slot.BREAKOUT_STRONG,
			"+X-side bot takes the strong-side-wall outlet")
	assert_eq(assignments[120], AIRoleSlots.Slot.BREAKOUT_WEAK,
			"-X-side bot takes the weak-side reverse valve")


func test_assign_breakout_strong_follows_strong_x_sign() -> void:
	# Flip the strong side to -X: now the -X peer should take STRONG.
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, 20.0)],
			[110, 0, Vector3(9.0, 0.0, 12.0)],
			[120, 0, Vector3(-9.0, 0.0, 12.0)],
	]
	var snap := _make_snapshot(skaters, 100)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.BREAKOUT,
			_resolver(skaters), {}, -1.0)
	assert_eq(assignments[120], AIRoleSlots.Slot.BREAKOUT_STRONG,
			"with strong side -X, the -X bot takes the strong outlet")
	assert_eq(assignments[110], AIRoleSlots.Slot.BREAKOUT_WEAK)


func test_assign_forecheck_f1_pressures_puck_f3_is_high() -> void:
	# Team 0 forechecking in the opp end (opp net at -Z). Opp 200 carries
	# the puck deep (z = -22). F3 = closest to the opp blue line (highest
	# / least deep), F1 = closest to the puck of the rest, F2 = leftover.
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, -8.0)],   # high, near opp blue (-7.29) → F3
			[110, 0, Vector3(2.0, 0.0, -21.0)],  # deep, near puck → F1
			[120, 0, Vector3(-3.0, 0.0, -14.0)], # mid → F2
			[200, 1, Vector3(0.0, 0.0, -22.0)],  # opp carrier, deep
	]
	var snap := _make_snapshot(skaters, 200)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.FORECHECK,
			_resolver(skaters), {})
	assert_eq(assignments[100], AIRoleSlots.Slot.F3_HIGH, "highest bot is the safety")
	assert_eq(assignments[110], AIRoleSlots.Slot.F1_PRESSURE, "bot nearest the puck pressures")
	assert_eq(assignments[120], AIRoleSlots.Slot.F2_NET, "leftover bot reads in front of the net")


func test_assign_trans_def_fills_our_line_first() -> void:
	# TRANS_DEFENSE is the 1-2, filled from the back: the two bodies soonest to
	# our line's posts hold it, and the one left up the ice is the high "1".
	# Carrier at centre; 110 and 120 are back, 100 is caught up the ice.
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, -8.0)],  # up-ice → NZ_F1
			[110, 0, Vector3(0.0, 0.0, 5.0)],   # at our line
			[120, 0, Vector3(0.0, 0.0, 20.0)],  # deep in our zone
			[200, 1, Vector3(0.0, 0.0, 0.0)],   # opp carrier
	]
	var snap := _make_snapshot(skaters, 200)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.TRANS_DEFENSE,
			_resolver(skaters), {})
	assert_eq(assignments[100], AIRoleSlots.Slot.NZ_F1,
			"the body caught up the ice is the high one")
	for pid: int in [110, 120]:
		assert_true(assignments[pid] in [
				AIRoleSlots.Slot.BACK_STRONG, AIRoleSlots.Slot.BACK_MID],
				"peer %d is back, so he holds our line" % pid)
	assert_ne(assignments[110], assignments[120], "one carrier owner, one middle")


func test_assign_trans_def_back_line_is_momentum_aware() -> void:
	# "Soonest to the post" folds in momentum, not just raw distance: a peer
	# further from the strong post but skating at it beats a nearer one skating
	# away from it.
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, -6.0)],
			[110, 0, Vector3(5.0, 0.0, 0.0), Vector3(0.0, 0.0, 12.0)],   # coming to it
			[120, 0, Vector3(5.0, 0.0, 11.0), Vector3(0.0, 0.0, 12.0)],  # nearer, leaving it
			[200, 1, Vector3(0.0, 0.0, -10.0)],
	]
	var snap := _make_snapshot(skaters, 200)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.TRANS_DEFENSE,
			_resolver(skaters), {})
	assert_eq(assignments[110], AIRoleSlots.Slot.BACK_STRONG,
			"the peer genuinely arriving soonest (momentum) takes the strong post")


# Once nobody can be on our line before the carrier is (a carrier at speed a
# couple of metres off it, both D already back past it), the line is lost and
# BACK_STRONG rides him back: the man in the strong lane keeps him, though he is
# riding back hardest and so has the most to brake out to get back up to the
# post. Raced up to it, the carrier went to the slower man in the middle, and
# the strong-lane D drifted off him to the middle while he drove in.
func test_assign_trans_def_a_lost_line_keeps_the_man_riding_the_strong_lane() -> void:
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, -6.0)],
			[110, 0, Vector3(2.0, 0.0, 8.9), Vector3(-0.9, 0.0, 6.6)],   # strong lane, riding back
			[120, 0, Vector3(-0.4, 0.0, 7.6), Vector3(0.2, 0.0, 4.9)],   # the middle, slower
			[200, 1, Vector3(4.9, 0.0, 4.9), Vector3(-2.2, 0.0, 8.9)],
	]
	var snap := _make_snapshot(skaters, 200)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.TRANS_DEFENSE,
			_resolver(skaters), {})
	assert_eq(assignments[110], AIRoleSlots.Slot.BACK_STRONG,
			"the strong-lane D riding him back keeps the carrier")
	assert_eq(assignments[120], AIRoleSlots.Slot.BACK_MID, "the middle man the middle")


func test_assign_trans_def_when_whole_team_caught_up_ice() -> void:
	# The whole team is beaten up the ice on the turnover — every peer is
	# up-ice of the carrier. The line still fills from the back: the two nearest
	# it race to it, the furthest is the high one.
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, -5.0)],
			[110, 0, Vector3(0.0, 0.0, -10.0)],  # furthest → NZ_F1
			[120, 0, Vector3(0.0, 0.0, -8.0)],
			[200, 1, Vector3(0.0, 0.0, 0.0)],   # opp carrier; all peers are up-ice of it
	]
	var snap := _make_snapshot(skaters, 200)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.TRANS_DEFENSE,
			_resolver(skaters), {})
	assert_eq(assignments[100], AIRoleSlots.Slot.BACK_STRONG,
			"peer nearest our line takes the strong post")
	assert_eq(assignments[110], AIRoleSlots.Slot.NZ_F1, "the furthest is the high one")


func test_assign_hysteresis_flips_exactly_past_the_penalty() -> void:
	# PRESSURE = soonest to the puck, a contender paying HYSTERESIS_PENALTY_S on
	# top of his arrival time. The incumbent (100) holds the slot while the
	# contender (110) is sooner by less than the penalty and loses it once he is
	# sooner by more, wherever the two stand.
	var puck := Vector3(5.0, 0.0, 22.0)
	var incumbent := Vector3(2.0, 0.0, 22.0)
	var ref: float = AIArrival.SKATER_REF_SPEED_M_S
	var t_incumbent: float = AIArrival.time_to_arrive(incumbent, puck, Vector3.ZERO, ref)
	var prev: Dictionary = {
			100: AIRoleSlots.Slot.PRESSURE,
			110: AIRoleSlots.Slot.MARK,
			120: AIRoleSlots.Slot.MARK,
	}
	var held: int = 0
	var flipped: int = 0
	for k: int in range(1, 13):
		var contender := Vector3(5.0, 0.0, 22.0 - 0.25 * k)
		var advantage: float = t_incumbent \
				- AIArrival.time_to_arrive(contender, puck, Vector3.ZERO, ref)
		if absf(advantage - AIRoleSlots.HYSTERESIS_PENALTY_S) < 0.01:
			continue
		var skaters: Array = [
				[100, 0, incumbent],
				[110, 0, contender],
				[120, 0, Vector3(-8.0, 0.0, 10.0)],  # far off, never the soonest
				[200, 1, puck],
		]
		var assignments: Dictionary[int, int] = AIRoleSlots.assign(
				_make_snapshot(skaters, 200), TEAM_ID, OUR_NET_Z,
				AIPossessionState.State.DZONE, _resolver(skaters), prev)
		var flips: bool = advantage > AIRoleSlots.HYSTERESIS_PENALTY_S
		var winner: int = 110 if flips else 100
		assert_eq(assignments[winner], AIRoleSlots.Slot.PRESSURE,
				"contender %.2f s sooner (penalty %.2f s): peer %d holds PRESSURE"
				% [advantage, AIRoleSlots.HYSTERESIS_PENALTY_S, winner])
		if flips:
			flipped += 1
		else:
			held += 1
	assert_gt(held, 0, "the sweep includes contenders inside the penalty")
	assert_gt(flipped, 0, "…and contenders past it")


func test_assign_momentum_beats_raw_distance() -> void:
	# The election is momentum-aware: a nearer peer coasting AWAY from the
	# puck loses PRESSURE to a farther peer already skating at it. This is
	# the raw-distance failure the ETA election replaces (the old metric
	# handed the slot to the wrong body, which then brake-pivoted).
	var skaters: Array = [
			[100, 0, Vector3(3.0, 0.0, 22.0), Vector3(-8.0, 0.0, 0.0)],  # 2 m away, fleeing → ETA 2/(9−8) = 2 s
			[110, 0, Vector3(9.0, 0.0, 22.0), Vector3(-8.0, 0.0, 0.0)],  # 4 m away, closing → ETA 4/17 ≈ 0.24 s
			[120, 0, Vector3(-2.0, 0.0, 25.0)],
			[200, 1, Vector3(5.0, 0.0, 22.0)],
	]
	var snap := _make_snapshot(skaters, 200)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.DZONE,
			_resolver(skaters), {})
	assert_eq(assignments[110], AIRoleSlots.Slot.PRESSURE,
			"the peer skating AT the puck wins over a nearer peer coasting away")
	assert_eq(assignments[100], AIRoleSlots.Slot.MARK)


func test_assign_speed_cap_feeds_election() -> void:
	# Each peer races at its real Speed cap: a faster build farther out
	# arrives sooner and takes the slot. Distances long enough for top
	# speed to engage — the calibrated ETA charges both builds the same
	# power-limited stride, so the cap only pays once the reference build
	# is cruising (~9 m in) and the faster one is still building.
	var skaters: Array = [
			[100, 0, Vector3(5.0, 0.0, -8.0)],   # 30 m from puck at ref 9
			[110, 0, Vector3(5.0, 0.0, -10.0)],  # 32 m from puck at cap 20
			[120, 0, Vector3(-10.0, 0.0, -18.0)],  # far — out of the race
			[200, 1, Vector3(5.0, 0.0, 22.0)],
	]
	var snap := _make_snapshot(skaters, 200)
	var fast_caps := AISkaterCaps.new()
	fast_caps.max_speed = 20.0
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.DZONE,
			_resolver(skaters), {}, 1.0, {110: fast_caps})
	assert_eq(assignments[110], AIRoleSlots.Slot.PRESSURE,
			"a faster Speed build farther out wins the arrival race")


# ─── NEUTRAL assignment ─────────────────────────────────────────────────────

func test_assign_neutral_chase_and_flanks() -> void:
	# Loose puck at center ice. CHASE goes to closest peer; the other
	# two split lateral L/R based on X position.
	var skaters: Array = [
			[100, 0, Vector3(1.0, 0.0, 0.0)],    # closest to puck
			[110, 0, Vector3(-5.0, 0.0, -3.0)],  # left side
			[120, 0, Vector3(5.0, 0.0, -3.0)],   # right side
	]
	var snap := _make_snapshot(skaters, -1, 0.0, 0.0)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.NEUTRAL,
			_resolver(skaters), {})
	assert_eq(assignments[100], AIRoleSlots.Slot.CHASE)
	assert_eq(assignments[110], AIRoleSlots.Slot.FLANK_L)
	assert_eq(assignments[120], AIRoleSlots.Slot.FLANK_R)


func test_assign_neutral_flank_hysteresis_holds_through_center() -> void:
	# Two peers near center — without hysteresis they'd flip L/R any
	# time their X order swaps. With prev assignments preserving
	# their sides, the 1.0 m penalty keeps them stable.
	# Puck placed on top of 100 so 100 wins CHASE (closest); the
	# remaining flank pair near center exercises the hysteresis.
	var skaters: Array = [
			[100, 0, Vector3(0.0, 0.0, 5.0)],    # at puck → CHASE
			[110, 0, Vector3(0.3, 0.0, -3.0)],   # nominally right of center
			[120, 0, Vector3(-0.3, 0.0, -3.0)],  # nominally left of center
	]
	var snap := _make_snapshot(skaters, -1, 5.0, 0.0)
	# Prev: 110 was FLANK_L, 120 was FLANK_R. Their X positions
	# now swap by 0.6 m; hysteresis (1.0 m on each side) keeps
	# them in their previous slots.
	var prev: Dictionary = {
			100: AIRoleSlots.Slot.CHASE,
			110: AIRoleSlots.Slot.FLANK_L,
			120: AIRoleSlots.Slot.FLANK_R,
	}
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.NEUTRAL,
			_resolver(skaters), prev)
	# Effective X: 110 = 0.3 - 1.0 = -0.7. 120 = -0.3 + 1.0 = 0.7.
	# 110 still has lower effective X → keeps FLANK_L.
	assert_eq(assignments[110], AIRoleSlots.Slot.FLANK_L,
			"FLANK_L sticks across a small center crossing")
	assert_eq(assignments[120], AIRoleSlots.Slot.FLANK_R,
			"FLANK_R sticks across a small center crossing")


# ─── Mixed-team behavior ────────────────────────────────────────────────────

func test_mixed_team_human_carrier_bots_fill_other_slots() -> void:
	# Human (real peer 1) has the puck → CARRIER. Two bots fill
	# FINISHER and SUPPORT in OZONE.
	var skaters: Array = [
			[1, 0, Vector3(0.0, 0.0, -22.0)],     # human carrier
			[10000, 0, Vector3(-3.0, 0.0, -25.0)],# bot near FINISHER
			[10001, 0, Vector3(0.0, 0.0, -16.0)], # bot near SUPPORT
	]
	var snap := _make_snapshot(skaters, 1)
	var assignments: Dictionary[int, int] = AIRoleSlots.assign(
			snap, TEAM_ID, OUR_NET_Z, AIPossessionState.State.OZONE,
			_resolver(skaters), {})
	assert_eq(assignments[1], AIRoleSlots.Slot.CARRIER)
	assert_true(assignments.has(10000))
	assert_true(assignments.has(10001))
	assert_ne(assignments[10000], assignments[10001], "bots get different slots")


# Every slot the brain can hand out has a row in the agent's per-slot facts, so a
# new slot cannot silently read as unlabelled, non-reactive and never jabbing.
func test_every_slot_has_its_facts() -> void:
	for slot: int in AIRoleSlots.Slot.values():
		if slot == AIRoleSlots.Slot.NONE:
			assert_eq(AIRoleSlots.label(slot), "-")
			continue
		assert_ne(AIRoleSlots.label(slot), "-",
				"slot %s has no row in AIRoleSlots._SLOT_INFO" % AIRoleSlots.Slot.keys()[slot])

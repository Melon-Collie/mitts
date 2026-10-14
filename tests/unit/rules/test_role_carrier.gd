extends GutTest

# AIRoleCarrier's compete on fixture snapshots: what it picks (shoot, pass and
# its variants, carry, dump, hold) and where, plus its lifecycle (reset,
# clear_intent, cooldown, settle doubt). The evaluators it prices with are
# covered in test_ai_action_scoring and test_reach_safety. The calibrated values
# behind the fixtures whose outcome is tuning rather than doctrine are a reviewed
# snapshot, test_carrier_calibration_snapshot (tests/snapshot.gd).

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/carrier.txt"
const OUR_NET_Z: float = 26.65
const OPP_NET_Z: float = -OUR_NET_Z
const TEAM_ID: int = 0


func _make_ctx(self_pos: Vector3, skaters: Array = []) -> RoleContext:
	# Default snapshot: self at self_pos, no opponents, no goalie.
	# Opponent-empty means score_pass / score_shoot evaluations don't
	# blow up on missing data; carrier handles missing goalie via
	# _goalie_now's null-fallback.
	var snap := WorldSnapshot.new()
	if skaters.is_empty():
		var s := SkaterNetworkState.new()
		s.position = self_pos
		s.facing = Vector2(0.0, -1.0)  # facing -Z (toward opp goal)
		snap.skater_states[1] = s
	else:
		for entry: Array in skaters:
			var sk := SkaterNetworkState.new()
			sk.position = entry[2]
			sk.facing = Vector2(0.0, -1.0)
			sk.is_ghost = entry[3] if entry.size() > 3 else false
			sk.velocity = entry[4] if entry.size() > 4 else Vector3.ZERO
			snap.skater_states[entry[0]] = sk

	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 1   # we're carrying
	puck.position = self_pos
	puck.velocity = Vector3.ZERO
	snap.puck_state = puck

	var team_map: Dictionary = {1: TEAM_ID}
	if not skaters.is_empty():
		team_map.clear()
		for entry: Array in skaters:
			team_map[entry[0]] = entry[1]

	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.self_velocity = Vector3.ZERO
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, OPP_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	return ctx


# ─── breakout: pressured carrier picks the open outlet ──────────────────────

func test_pressured_carrier_in_own_zone_passes_to_open_outlet() -> void:
	# Carrier deep in our own zone, pressured by two forecheckers up-ice; a
	# teammate is a wide-open outlet up the strong-side wall. With carry
	# poke-safety collapsing under pressure, the carrier should rate that
	# outlet as its best pass and choose PASS over carrying into the box.
	# (Verifies the breakout outlet, once well-positioned, actually gets the
	# puck out — no dump needed.)
	var self_pos := Vector3(3, 0, 20)         # off-center, clear of our own slot
	var outlet := Vector3(11, 0, 11)          # open up the strong wall
	var skaters: Array = [
			[1, TEAM_ID, self_pos],               # us, carrying
			[2, TEAM_ID, outlet],                 # open outlet
			[3, 1, Vector3(1.5, 0, 18.0)],        # forechecker pressuring us
			[4, 1, Vector3(3.0, 0, 17.5)],        # second forechecker
	]
	var ctx := _make_ctx(self_pos, skaters)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.debug_pass_peer_id, 2, "best pass targets the open up-wall outlet")
	assert_gt(c.debug_pass_score, 0.0, "the breakout pass has positive value")
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"pressured carrier passes out rather than carrying into the box")


func test_forechecker_closing_the_breakout_lane_devalues_the_pass() -> void:
	# The pass a bot fires is a charged wrister — it leaves the blade ~135 ms
	# after the intent commits — so the lane it threads is the lane as it exists
	# at RELEASE, not at decision time. A forechecker skating hard into a breakout
	# lane has closed real ground (position AND the extra closing time) during that
	# windup; scoring the lane at his CURRENT spot read those feeds as open and
	# shipped the puck into the closing stick (own-zone turnover → goal against).
	# The outlet pass is on with the defender standing clear; the SAME defender
	# skating into the lane devalues it (the release-time projection prices the
	# windup — see _scratch_opponents_release). (Whether the drop flips the whole
	# decision depends on the alternatives; the release-time lane pricing itself is
	# guarded at the primitive level in test_ai_action_scoring.)
	var self_pos := Vector3(4.0, 0.0, 20.0)          # own zone, off-center (clear of our slot)
	var outlet := Vector3(4.0, 0.0, 7.0)             # open outlet straight up the wall

	# Stationary forechecker, 2.6 m off the lane — a full stick clear, so the
	# outlet feed is on.
	var still: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, outlet],
			[11, 1, Vector3(6.6, 0.0, 13.5)],        # beside the lane, standing
	]
	var sc := _make_ctx(self_pos, still)
	var s := AIRoleCarrier.new()
	s.decide(sc)
	assert_eq(s.intended_action, AIRoleCarrier.INTENT_PASS,
			"a defender standing clear of the lane leaves the outlet pass on")
	assert_eq(s.pass_target_peer_id, 2)
	assert_gt(s.debug_pass_score, 0.0)

	# Same start spot, now skating toward the lane (-X). The release-time
	# projection puts him ~1 m closer before the puck even leaves the blade, and
	# he keeps closing over the flight — the feed is worth materially less.
	var closing: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, outlet],
			[11, 1, Vector3(6.6, 0.0, 13.5), false, Vector3(-8.0, 0.0, 0.0)],
	]
	var cc := _make_ctx(self_pos, closing)
	var c := AIRoleCarrier.new()
	c.decide(cc)
	assert_lt(c.debug_pass_score, s.debug_pass_score * 0.9,
			"a forechecker skating into the lane during the windup materially drops the pass value")


func test_forechecker_on_the_hip_contests_the_pass_release() -> void:
	# The cough-up loss mode: a forechecker ON the carrier — off the passing
	# lane, off the receiver — pokes the carried puck during the ~135 ms
	# windup. Before the release contest, he was invisible to the pass EV
	# (lane / miss / reception all miss him), so a swarmed defenseman kept
	# firing "clean" breakout feeds straight into pokes. Same geometry with
	# him a stick clear of the blade leaves the feed's value intact.
	var self_pos := Vector3(4.0, 0.0, 20.0)          # own zone, off-center
	var outlet := Vector3(4.0, 0.0, 7.0)             # open outlet up the wall
	var clear_of_blade: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, outlet],
			[11, 1, self_pos + Vector3(2.6, 0.0, 1.0)],   # near, but stick-clear
	]
	var sc := _make_ctx(self_pos, clear_of_blade)
	var s := AIRoleCarrier.new()
	s.decide(sc)
	var on_hip: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, outlet],
			[11, 1, self_pos + Vector3(1.0, 0.0, 0.4)],   # on the carrier's hip
	]
	var hc := _make_ctx(self_pos, on_hip)
	var h := AIRoleCarrier.new()
	h.decide(hc)
	assert_gt(s.debug_pass_score, 0.0, "the stick-clear feed is a real option")
	assert_lt(h.debug_pass_score, s.debug_pass_score * 0.9,
			"a stick on the carrier contests the release and the same feed "
			+ "is worth materially less; hip=%f clear=%f"
			% [h.debug_pass_score, s.debug_pass_score])


func test_retreating_receiver_is_worth_less_than_a_streaking_one() -> void:
	# Receiver momentum in the post-catch value: the drive-in credit now runs
	# the calibrated arrival model from the receiver's REAL velocity, so a
	# man retreating toward our net pays the full reversal (brake + ramp)
	# before his catch turns into an attack, while the same man in stride
	# toward the opponent net carries his pace into it. Before this, both
	# priced identically (reach / max_speed) — the over-valued backpass to a
	# back-pedalling teammate was exactly this blindness.
	var self_pos := Vector3(3.0, 0.0, 4.0)           # NZ carrier (own net +Z)
	var spot := Vector3(-4.0, 0.0, 6.0)              # teammate slightly behind us
	var streaking: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, spot, false, Vector3(0.0, 0.0, -7.0)],   # in stride, up-ice
	]
	var st := _make_ctx(self_pos, streaking)
	var a := AIRoleCarrier.new()
	a.decide(st)
	var retreating: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, spot, false, Vector3(0.0, 0.0, 7.0)],    # back-pedalling home
	]
	var rt := _make_ctx(self_pos, retreating)
	var b := AIRoleCarrier.new()
	b.decide(rt)
	assert_gt(a.debug_pass_score, b.debug_pass_score + 0.01,
			"the feed to the man in stride out-values the backpass to the "
			+ "retreating one; streak=%f retreat=%f"
			% [a.debug_pass_score, b.debug_pass_score])


func test_turning_receiver_devalues_the_pass_and_the_blind_tier_ignores_it() -> void:
	# Receiver-commitment read: a moving teammate mid-cut curves off the
	# straight-line lead, so the feed to one is priced as riskier. A
	# commitment-blind tier (Easy) is deaf to it and prices the turning receiver
	# exactly like a settled one — it chucks the feed.
	var self_pos := Vector3(3, 0, 20)
	var outlet := Vector3(11, 0, 11)
	var recv_vel := Vector3(0, 0, -6)   # streaking up-ice at 6 m/s
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, outlet, false, recv_vel],
			[3, 1, Vector3(1.5, 0, 18.0)],
			[4, 1, Vector3(3.0, 0, 17.5)],
	]
	# Settled receiver (no heading rotation injected → omega 0).
	var settled_ctx := _make_ctx(self_pos, skaters)
	var cs := AIRoleCarrier.new()
	cs.decide(settled_ctx)
	var settled_score: float = cs.debug_pass_score
	assert_eq(cs.debug_pass_peer_id, 2, "the only teammate is the feed target")
	assert_gt(settled_score, 0.0, "the feed to a settled streaker is on")

	# Same play, receiver now mid-cut (hard heading rotation).
	var turning_ctx := _make_ctx(self_pos, skaters)
	turning_ctx.heading_omega_by_peer = {2: 4.0}
	var ct := AIRoleCarrier.new()
	ct.decide(turning_ctx)
	assert_lt(ct.debug_pass_score, settled_score,
			"a turning receiver is priced as a riskier feed")

	# Commitment-blind tier: same turn, ignored — priced like the settled feed.
	var blind_ctx := _make_ctx(self_pos, skaters)
	blind_ctx.heading_omega_by_peer = {2: 4.0}
	blind_ctx.reads_receiver_commitment = false
	var cb := AIRoleCarrier.new()
	cb.decide(blind_ctx)
	assert_almost_eq(cb.debug_pass_score, settled_score, 0.0001,
			"a commitment-blind bot chucks it — same price as the settled feed")


func test_passes_to_the_open_backdoor_man_over_forcing_a_carry() -> void:
	# The carrier is at a poor wide angle with a wide-open teammate at the far-
	# post backdoor — a feed the goalie's re-square genuinely cannot beat (the
	# arc race across the crease is longer than the pass flight). The pass to
	# him must win over grinding a carry from the bad angle. (Goalie squared
	# to the carrier, as the live keeper is. A stationary man in the dead slot
	# is not this feed: the keeper re-sets over its flight.)
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(6.0, 0.0, -20.0)             # wide angle, poor look
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-2.5, 0.0, -23.5)],     # far-post backdoor, clear lane
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 1.3)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"feeds the open backdoor man instead of forcing a carry from a bad angle")
	assert_eq(c.pass_target_peer_id, 2)


func test_neutral_zone_hits_the_ahead_man_with_a_clearer_path() -> void:
	# The carrier's own path up the middle is contested (two defenders clogging the
	# lane ahead), but a teammate up-ice on the wing has a clear passing lane AND a
	# clear path to keep advancing. The receiver drive-in credit (in NZ/DZ currency:
	# position potential of where they'd advance to) makes that ahead man out-score
	# the carrier's own stalled carry — so the puck moves up to the clearer path.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(0.0, 0.0, 16.0)              # own end / DZ, carrying
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-8.0, 0.0, 6.0)],       # winger ahead, clear lane + path
			[11, 1, Vector3(-1.0, 0.0, 10.0)],           # clogs the middle carry
			[12, 1, Vector3(2.0, 0.0, 9.0)],             # clogs the middle carry
	]
	var ctx := _make_ctx(self_pos, skaters)
	var g := GoalieNetworkState.new()
	g.position_x = 0.0
	g.position_z = net.z + 1.3
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"moves the puck up to the ahead man on the clearer path")
	assert_eq(c.pass_target_peer_id, 2)


const _IMPEDED_OPEN_MATE := Vector3(7.0, 0.0, -6.5)      # ahead and wide, onside
const _IMPEDED_TUCKED_MATE := Vector3(3.0, 0.0, -3.0)    # 3.6 m off the defender ahead
const _DEFENDER_AHEAD := Vector3(0.0, 0.0, -5.0)         # squarely in the path to the zone
const _DEFENDER_BESIDE := Vector3(7.0, 0.0, -2.0)


func _decided(ctx: RoleContext) -> AIRoleCarrier:
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	return c


func _set_keeper(ctx: RoleContext) -> RoleContext:
	var g := GoalieNetworkState.new()
	g.position_z = -GameRules.GOAL_LINE_Z + 1.3
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	return ctx


# A neutral-zone carrier with one mate and one defender, keeper set.
func _impeded_ctx(mate: Vector3, defender: Vector3) -> RoleContext:
	var carrier := Vector3(0.0, 0.0, 2.0)
	return _set_keeper(_make_ctx(carrier, [
			[1, TEAM_ID, carrier], [2, TEAM_ID, mate], [11, 1, defender]]))


func test_forward_pressure_is_directional_and_the_pass_must_be_earned() -> void:
	# Forward pressure is read as controlled space (AICarrySpace.controlled_space),
	# so a defender between the carrier and the zone costs the carry more than the
	# same defender off to the side. And the pass that pressure pushes toward has
	# to be to a mate who is actually clear: one tucked in to that defender is
	# worth less than an open one.
	var ahead: AIRoleCarrier = _decided(_impeded_ctx(_IMPEDED_OPEN_MATE, _DEFENDER_AHEAD))
	var beside: AIRoleCarrier = _decided(_impeded_ctx(_IMPEDED_OPEN_MATE, _DEFENDER_BESIDE))
	assert_gt(beside.debug_carry_score, ahead.debug_carry_score,
			"a side defender leaves the carry worth more than a forward one blocking the path")
	var tucked: AIRoleCarrier = _decided(_impeded_ctx(_IMPEDED_TUCKED_MATE, _DEFENDER_AHEAD))
	assert_lt(tucked.debug_pass_score, ahead.debug_pass_score,
			"a mate tucked in tight to the same defender is worth less than an open one")


const _AHEAD_MAN := Vector3(0.0, 0.0, 10.0)


func _ahead_man_ctx(blocked: bool) -> RoleContext:
	var self_pos := Vector3(0.0, 0.0, 16.0)
	var skaters: Array = [[1, TEAM_ID, self_pos], [2, TEAM_ID, _AHEAD_MAN]]
	if blocked:
		skaters.append([11, 1, Vector3(0.0, 0.0, 4.0)])   # squarely in his drive path
	return _set_keeper(_make_ctx(self_pos, skaters))


func _ahead_man_drive_in(ctx: RoleContext) -> float:
	return _decided(ctx)._receiver_drive_in_value(
			ctx, _AHEAD_MAN, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, null)


func test_a_defender_in_the_drive_path_strips_the_receivers_drive_in() -> void:
	# The drive-in reach is the REACHABLE extent, not a free deep credit: the same
	# man ahead earns less once a defender stands squarely in his forward path.
	var open: float = _ahead_man_drive_in(_ahead_man_ctx(false))
	assert_gt(open, 0.0, "a clear drive toward the net is credited")
	assert_lt(_ahead_man_drive_in(_ahead_man_ctx(true)), open,
			"a defender in the drive path strips the credit")


func test_pass_is_devalued_when_the_receiver_is_blanketed() -> void:
	# A teammate with a clean passing LANE but a defender skating stride-for-stride
	# beside him — off the lane (lane_clear never sees it) and off his forward-to-
	# net cone (his own shot pressure never sees it), yet close enough to strip the
	# catch the instant it arrives. The reception-pressure term must price that:
	# the feed to the blanketed man scores strictly LOWER than the identical feed
	# to the same spot with no one draped on him.
	var self_pos := Vector3(0.0, 0.0, 8.0)
	var receiver := Vector3(0.0, 0.0, -4.0)

	var clean: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, receiver],
	]
	var c_clean := AIRoleCarrier.new()
	c_clean.decide(_make_ctx(self_pos, clean))
	var clean_score: float = c_clean.debug_pass_score

	var blanketed: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, receiver],
			[9, 1, receiver + Vector3(1.8, 0.0, 0.0)],   # defender draped beside him
	]
	var c_cov := AIRoleCarrier.new()
	c_cov.decide(_make_ctx(self_pos, blanketed))
	var covered_score: float = c_cov.debug_pass_score

	assert_gt(clean_score, 0.0, "the open feed has real value")
	assert_lt(covered_score, clean_score,
			"a blanketed receiver's feed is worth less — reception pressure is priced in")


func test_open_receiver_in_a_poor_spot_is_not_over_credited() -> void:
	# The drive-in credit must not turn EVERY open teammate into a must-pass: a man
	# open but in a genuinely poor spot (wide, no drive that improves the look) stays
	# low-value, so the carrier keeps the puck rather than dumping it wide.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(0.0, 0.0, -12.0)             # decent central carrier
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(9.0, 0.0, -14.0)],      # open but wide/poor angle
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 1.3)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"a wide, low-value open man is not worth passing to over keeping the puck")


func test_close_pass_is_a_crisp_charged_wrister() -> void:
	# Every pass is a paced wrister. A short feed to a close open teammate charges
	# (pass_should_charge) and fires at the MAGNET pace (closing speed in the
	# receiver's frame): crisp enough to keep its hang time short, still catchable
	# when the receiver squares up. NZ carrier with a defender clogging the
	# straight carry/shot lane so the close lateral feed wins.
	var self_pos := Vector3(-4, 0, 2)
	var outlet := Vector3(1, 0, -1)                   # ~5.8 m — a close feed, up-ice
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, outlet],
			[11, 1, Vector3(-4, 0, -2)],              # clogs the straight-ahead carry/shot
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS, "picks the close outlet")
	assert_eq(c.pass_target_peer_id, 2)
	assert_true(c.pass_should_charge, "a pass is always a charged wrister")
	assert_gt(c.pass_target_speed, AIPuckLane.PASS_SPEED_M_S,
			"a close feed fires crisp — above quick-pass pace")
	# Backs out of the target arrival at this distance (friction-compensated).
	assert_almost_eq(c.pass_target_speed,
			AIPuckLane.pass_launch_speed(self_pos.distance_to(outlet),
					GameRules.DEFAULT_WRISTER_POWER_MAX_M_S), 0.1,
			"fires at the friction-compensated magnet pace")


# ─── pressure: make a safe play, don't drive into the box ───────────────────

func test_board_pincer_makes_a_safe_play_not_a_turnover() -> void:
	# Carrier pinned on the right wall, two forecheckers converging. There's no
	# separate pass-out-of-pressure bonus: the clean per-action EV resolves this by
	# the carry/pass alternatives' OWN strip cost (carrying into the box goes
	# negative). The bot makes a possession-preserving play — either the lateral
	# outlet pass or a safe evade-carry AWAY from the closing box. What it must NOT
	# do is drive up the wall into the pincer and cough it up. (Pre-removal this
	# asserted the specific outlet pass a relief bonus forced; the evade-carry is an
	# equally valid resolution and what the clean EV prefers here.)
	var self_pos := Vector3(6, 0, 9)                    # right-center, NZ
	var outlet := Vector3(-3, 0, 6)                     # left-center, forward, open
	var d3 := Vector3(4, 0, 4)
	var d4 := Vector3(9, 0, 5)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],                         # us, carrying
			[2, TEAM_ID, outlet],                           # open outlet
			[3, 1, d3, false, Vector3(1.5, 0, 5)],          # inside forechecker closing fast
			[4, 1, d4, false, Vector3(-3, 0, 5)],           # outside forechecker closing (pincer)
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	if c.intended_action == AIRoleCarrier.INTENT_PASS:
		assert_eq(c.debug_pass_peer_id, 2, "if it passes, it feeds the open outlet")
	else:
		# Evade-carry: the destination backs away from the converging pincer rather
		# than driving up-ice into it.
		var pincer_mid: Vector3 = (d3 + d4) * 0.5
		assert_gt(c.debug_carry_pos.distance_to(pincer_mid), self_pos.distance_to(pincer_mid),
				"an evade-carry moves away from the pincer, not into it")


func test_light_pressure_keeps_the_puck_over_a_covered_backpass() -> void:
	# Carrier LIGHTLY pressured with space ahead; the only pass option is a deeper,
	# covered teammate. The backpass is priced on its own weak EV (low receiver
	# value, real turnover cost) and loses to keeping the puck and skating.
	var self_pos := Vector3(2, 0, 12)                    # NZ, our side, space ahead (toward -Z)
	var covered := Vector3(0, 0, 19)                     # deeper teammate, in our end
	var skaters: Array = [
			[1, TEAM_ID, self_pos],                          # us, carrying
			[2, TEAM_ID, covered],                           # deeper outlet — but covered
			[3, 1, Vector3(2, 0, 8), false, Vector3(0, 0, 2)],   # light pressure, slow close
			[4, 1, Vector3(0.6, 0, 19.5)],                       # defender sitting on the outlet
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"light pressure + a covered backpass is not an escape — keep the puck")


# ─── breakout: the risky ground-losing backpass loses to keeping the puck ────

func test_risky_backpass_deep_in_own_zone_loses_to_keeping_the_puck() -> void:
	# Carrier deep in our own zone with a forechecker charging at it. The
	# only pass option is a teammate even DEEPER — a low-upside backpass
	# whose execution-miss mode (pass_miss_prob, loss point past the
	# receiver, right in front of our net) makes its EV worse than just
	# keeping the puck and skating.
	var self_pos := Vector3(2, 0, 21)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-3, 0, 24)],                          # deep valve (backpass bait)
			[3, 1, Vector3(2, 0, 17.5), false, Vector3(0, 0, 5)],      # forechecker charging us
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"a low-upside backpass toward our own net must not beat keeping the puck")


# ─── stand-still pays turnover cost: pressured carrier never freezes ─────────

func test_pressured_carrier_skates_clear_instead_of_freezing() -> void:
	# Carrier deep in our zone with a single forechecker charging straight
	# at it, the flanks OPEN. Stand-still used to be the only carry candidate
	# that paid NO turnover cost, so freezing stayed positive while every
	# escape route went EV-negative — the bot planted itself and ate the
	# check. With the strip probability (1 - poke_safety) now feeding
	# turnover_cost, freezing under a converging forechecker prices its own
	# turnover and loses to the open skating lane; the carrier beats the
	# forecheck up the wall. (A FULL surround with no open lane is a genuine
	# pin — that reads as a DUMP, see test_pinned_dz_carrier_dumps_to_clear.)
	var self_pos := Vector3(2, 0, 21)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(2, 0, 18), false, Vector3(0, 0, 5)],  # charging forechecker
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"an open lane beats both freezing and dumping — this is a carry read")
	assert_ne(c.last_carry_anchor, self_pos,
			"a carrier with a forechecker bearing down must skate clear, not freeze")


# ─── zone entry: open ice at the blue line must beat standing still ──────────

func test_open_carrier_at_blue_line_drives_in_instead_of_freezing() -> void:
	# Carrier at REST just outside the offensive blue line, wide open —
	# no opponents, clear path to the net. Before the potential-
	# realization discount, stand-still held its position_potential
	# undecayed while every movement candidate paid travel decay; the
	# potential gradient out here is shallower than that decay, so
	# stand-still strictly won and the bot PLANTED at the blue line
	# instead of attacking. Now potential pays its realization decay
	# uniformly and open ice ahead always wins the carry argmax.
	var self_pos := Vector3(0.0, 0.0, -6.5)  # ~20 m from opp goal, just outside shot range
	var ctx: RoleContext = _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"nothing to fire from out here — this is a carry read")
	assert_ne(c.last_carry_anchor, self_pos,
			"a wide-open carrier at the blue line must take the space, not freeze")
	assert_lt(c.last_carry_anchor.z, self_pos.z,
			"…and take it TOWARD the attacking net")
	assert_true(
			AIActionScoring.in_offensive_zone(c.last_carry_anchor, ctx.attacking_goal_pos),
			"…all the way across the blue line, entering the offensive zone")


# ─── zone valve: once in the O-zone, don't carry back out ────────────────────

func test_carrier_in_ozone_never_carries_back_out() -> void:
	# Carrier just inside the offensive blue line, swarmed from the front and
	# sides so the safest escape is a RETREAT back across the line. That exit is
	# exactly what the one-way valve forbids: establishing the zone is worth
	# keeping. Every carry candidate that leaves the O-zone is pruned, so the best
	# carry (worst case, stand-still) stays inside it.
	var self_pos := Vector3(0, 0, -9)                      # in the O-zone, near the line
	var skaters: Array = [
			[1, TEAM_ID, self_pos],                           # us, carrying
			[3, 1, Vector3(0, 0, -11), false, Vector3(0, 0, -3)],  # forechecker in front
			[4, 1, Vector3(3, 0, -10)],                       # right pincer
			[5, 1, Vector3(-3, 0, -10)],                      # left pincer
	]
	var ctx: RoleContext = _make_ctx(self_pos, skaters)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_true(
			AIActionScoring.in_offensive_zone(c.last_carry_anchor, ctx.attacking_goal_pos),
			"the best carry keeps the puck in the offensive zone, never retreats out")


# ─── zone valve: once in the O-zone, don't pass back out ─────────────────────

func test_carrier_in_ozone_never_passes_out_to_a_neutral_zone_teammate() -> void:
	# Carrier in the O-zone with its shot screened, and the only pass option is a
	# teammate back in the neutral zone on a wide-open lane — tempting bait. The
	# valve excludes any receiver outside the zone, so that pass is never on the
	# board: the carrier holds/cycles rather than surrendering the blue line.
	var self_pos := Vector3(0, 0, -12)                     # in the O-zone
	var nz_mate := Vector3(6, 0, 0)                        # neutral zone, open lane
	var skaters: Array = [
			[1, TEAM_ID, self_pos],                           # us, carrying
			[2, TEAM_ID, nz_mate],                            # NZ teammate — bait
			[3, 1, Vector3(0, 0, -15)],                       # screens our shot to the net
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"a carrier in the O-zone won't pass the puck back out to the neutral zone")
	assert_eq(c.debug_pass_score, 0.0,
			"the out-of-zone teammate is excluded, so there is no pass on the board")

	# Contrast: a teammate INSIDE the zone, on a clean lane and in scoring ice, is
	# a legal receiver — confirming it was the zone exclusion suppressing the pass
	# above, not a bad lane. The control needs a mate in real scoring ice and a
	# real keeper: a mate level with the carrier on a dead lane scores numerical
	# dust, which says nothing about legality.
	var g := GoalieNetworkState.new()
	g.position_x = 0.0
	g.position_z = -GameRules.GOAL_LINE_Z + 1.3
	var oz_mate := Vector3(6, 0, -19)                      # in the zone, scoring ice
	var skaters_in: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, oz_mate],
			[3, 1, Vector3(0, 0, -15)],
	]
	var ctx_in: RoleContext = _make_ctx(self_pos, skaters_in)
	ctx_in.snapshot.goalie_states[1 - TEAM_ID] = g
	var c2 := AIRoleCarrier.new()
	c2.decide(ctx_in)
	assert_gt(c2.debug_pass_score, AIRoleCarrier.PASS_MIN_VALUE,
			"an in-zone teammate in scoring ice IS a legal pass target, worth firing")


# ─── zone valve: it's the PUCK that takes the zone ──────────────────────────

func test_carrier_whose_puck_has_entered_never_drops_it_back_out() -> void:
	# Carrying in up the wall at speed: the puck rides a stick's reach ahead, so
	# it crosses the blue line before the body does. A trailer in neutral ice
	# with open ice ahead is the bait. Three moments are checked: puck already in
	# with the body still outside, and the puck still outside but due in by the
	# time a pass would leave the blade. A drop pass in either one sends the
	# puck back out.
	var v := Vector3(0, 0, -7.0)
	for puck_z: float in [-7.9, -7.1]:
		var self_pos := Vector3(-8.0, 0, puck_z + 1.1)
		var skaters: Array = [
				[1, TEAM_ID, self_pos, false, v],
				[2, TEAM_ID, Vector3(2.0, 0, self_pos.z + 5.0), false, v],   # NZ trailer
				[3, 1, Vector3(-7.5, 0, puck_z - 2.5), false, Vector3(0, 0, -6.0)],
				[4, 1, Vector3(3.0, 0, self_pos.z - 9.0), false, Vector3(0, 0, -5.0)],
		]
		var ctx: RoleContext = _make_ctx(self_pos, skaters)
		ctx.self_velocity = v
		ctx.snapshot.puck_state.position = Vector3(-8.0, 0, puck_z)
		assert_false(AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos),
				"precondition: the body has not crossed the line")
		var c := AIRoleCarrier.new()
		c.decide(ctx)
		c.decide(ctx)
		assert_ne(c.intended_action, AIRoleCarrier.INTENT_PASS,
				"puck at z %.1f: no drop pass back across the line" % puck_z)
		assert_eq(c.debug_pass_score, 0.0,
				"puck at z %.1f: the neutral-zone trailer is not a legal receiver" % puck_z)

	# Control: a step further back the puck cannot reach the line before
	# release, so the zone is not yet taken and the same trailer is a live drop.
	var back_pos := Vector3(-8.0, 0, -4.0)
	var back_skaters: Array = [
			[1, TEAM_ID, back_pos, false, v],
			[2, TEAM_ID, Vector3(2.0, 0, back_pos.z + 5.0), false, v],
			[3, 1, Vector3(-7.5, 0, back_pos.z - 3.6), false, Vector3(0, 0, -6.0)],
			[4, 1, Vector3(3.0, 0, back_pos.z - 9.0), false, Vector3(0, 0, -5.0)],
	]
	var back_ctx: RoleContext = _make_ctx(back_pos, back_skaters)
	back_ctx.self_velocity = v
	back_ctx.snapshot.puck_state.position = back_pos + Vector3(0, 0, -1.1)
	var c_back := AIRoleCarrier.new()
	c_back.decide(back_ctx)
	c_back.decide(back_ctx)
	assert_gt(c_back.debug_pass_score, 0.0,
			"before the zone is taken the trailer is a legal receiver")


# ─── the entry: being in the zone outranks staying out ──────────────────────

func _entry_ctx(body_z: float, skaters_extra: Array) -> RoleContext:
	var v := Vector3(0, 0, -7.0)
	var self_pos := Vector3(-8.0, 0, body_z)
	var skaters: Array = [
			[1, TEAM_ID, self_pos, false, v],
			[2, TEAM_ID, Vector3(2.0, 0, body_z + 5.0), false, v],   # trailer
	]
	skaters.append_array(skaters_extra)
	var ctx: RoleContext = _make_ctx(self_pos, skaters)
	ctx.self_velocity = v
	ctx.snapshot.puck_state.position = self_pos + Vector3(0, 0, -1.1)
	var g := GoalieNetworkState.new()
	g.position_z = -GameRules.GOAL_LINE_Z + 1.0
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	return ctx


func test_carrier_with_room_at_the_line_carries_in_over_the_drop_pass() -> void:
	# Up the wall at speed, 4.3 m short of the line, the defender gapping 3.5 m
	# ahead and the trailer open in the middle. The carrier can get into the zone
	# with the puck, and what he does from there is worth more than the trailer's
	# drive from 5 m further back.
	var ctx: RoleContext = _entry_ctx(-3.0, [
			[3, 1, Vector3(-7.5, 0, -7.6), false, Vector3(0, 0, -6.0)],
			[4, 1, Vector3(3.0, 0, -12.0), false, Vector3(0, 0, -5.0)],
	])
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	c.decide(ctx)
	assert_gt(c.debug_pass_score, 0.0, "precondition: the drop to the trailer is a live option")
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"with room to enter, the carrier takes the zone himself (pass %.3f vs carry %.3f)"
			% [c.debug_pass_score, c.debug_carry_score])


func test_carrier_with_room_plans_across_the_line_not_up_to_it() -> void:
	# Keeping the puck is not enough: a carrier who only values in-zone ice by the
	# shot he would have just inside the line plans to stop short of it and hovers
	# there. The entry continuation (what he does once in) is what takes his plan
	# into the zone.
	var ctx: RoleContext = _entry_ctx(-4.5, [
			[3, 1, Vector3(-7.5, 0, -9.1), false, Vector3(0, 0, -6.0)],
			[4, 1, Vector3(3.0, 0, -13.5), false, Vector3(0, 0, -5.0)],
	])
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY, "he keeps the puck")
	assert_true(AIActionScoring.in_offensive_zone(c.last_carry_anchor, ctx.attacking_goal_pos),
			"…and his plan crosses the line (anchor z %.1f)" % c.last_carry_anchor.z)


func test_smothered_carrier_at_the_line_still_drops_it_to_the_trailer() -> void:
	# Same rush, but a checker is on his hip and another seals the line ahead:
	# there is no entry for him to make, and the open trailer's is the play.
	var ctx: RoleContext = _entry_ctx(-4.5, [
			[3, 1, Vector3(-6.2, 0, -5.3), false, Vector3(0, 0, -7.0)],
			[4, 1, Vector3(-7.0, 0, -7.5), false, Vector3(0, 0, -2.0)],
	])
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"no entry of his own: the trailer gets it (pass %.3f vs carry %.3f)"
			% [c.debug_pass_score, c.debug_carry_score])
	assert_eq(c.debug_pass_peer_id, 2, "…to the trailer")


# ─── turnover costs are priced in the unit of the gains ─────────────────────

func test_an_in_zone_carrier_prices_a_turnover_in_xg() -> void:
	# A strip at the top of the zone hands the opponent a puck 40 m from our net.
	# In the zone the carrier's gains are xG, so that loss must be priced as the
	# opponent's possession promise in xG; outside, the gains are on the potential
	# scale and so is the cost. Same loss point, two carriers.
	var loss := Vector3(-4.0, 0.0, -15.0)
	var our_net := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)
	var defenders: Array[Vector3] = []
	var expected_xg: float = AIActionScoring.position_potential(loss, our_net, defenders) \
			* AIActionScoring.potential_realization_discount(loss, our_net) \
			* AIActionScoring.XG_SLOT_REF
	var our_goalie := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z - 0.8)

	var inside := Vector3(-8.0, 0.0, -16.0)
	var c_in := AIRoleCarrier.new()
	var ctx_in: RoleContext = _make_ctx(inside)
	c_in.decide(ctx_in)
	assert_almost_eq(c_in._turnover_cost(ctx_in, loss, 1.0, our_goalie), expected_xg, 0.0005,
			"in the zone a turnover costs the opponent's xG promise there")

	var outside := Vector3(-8.0, 0.0, -4.0)
	var c_out := AIRoleCarrier.new()
	var ctx_out: RoleContext = _make_ctx(outside)
	c_out.decide(ctx_out)
	assert_almost_eq(c_out._turnover_cost(ctx_out, loss, 1.0, our_goalie),
			AIActionScoring.threat_surface_shoot(loss, our_net, our_goalie,
					GameRules.NET_HALF_WIDTH, defenders), 0.0005,
			"outside the zone it stays on the potential scale, like the gains")


# ─── drive-in: a clear drive is credited all the way ────────────────────────

func test_a_defender_who_never_covers_the_drive_costs_it_nothing() -> void:
	# Carrier at speed up the wall toward the line, the defender retreating ahead.
	# At 5 m and at 8 m he never gets a stick on the drive, so the drive-in (the
	# shot the carrier skates into) must be the same: the full drive to the net,
	# not a drive stopped halfway because halfway was the closer sample.
	var v := Vector3(0, 0, -7.0)
	var self_pos := Vector3(-8.0, 0, -4.5)
	var drive: Array[float] = []
	for gap: float in [5.0, 8.0]:
		var skaters: Array = [
				[1, TEAM_ID, self_pos, false, v],
				[3, 1, Vector3(-7.5, 0, self_pos.z - 1.1 - gap), false, Vector3(0, 0, -6.0)],
				[4, 1, Vector3(3.0, 0, self_pos.z - 9.0), false, Vector3(0, 0, -5.0)],
		]
		var ctx: RoleContext = _make_ctx(self_pos, skaters)
		ctx.self_velocity = v
		var c := AIRoleCarrier.new()
		c.decide(ctx)
		drive.append(c._receiver_drive_in_value(ctx, self_pos,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, null, v))
	assert_gt(drive[1], 0.0, "precondition: the drive is worth something")
	assert_almost_eq(drive[0], drive[1], 0.005,
			"a defender 5 m ahead who never covers the drive costs it nothing (%.3f vs %.3f)"
			% [drive[0], drive[1]])


func test_the_shot_s_keep_never_discounts_what_the_spot_is_worth_by_position() -> void:
	# Out of the zone with the keeper pulled, _score_at weighs the long shot
	# against the spot's position value. Losing the puck before the press costs
	# the shot, never the position.
	var self_pos := Vector3(0.0, 0.0, 0.0)
	var ctx: RoleContext = _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	var goal: Vector3 = ctx.attacking_goal_pos
	var pos := Vector3(2.0, 0.0, -5.0)
	var none: Array[Vector3] = []
	var pulled := Vector3(0.0, 0.0, 0.0)
	var position_value: float = AIActionScoring.position_potential(pos, goal, none) \
			* AIActionScoring.potential_realization_discount(pos, goal)
	for keep: float in [1.0, 0.5, 0.0]:
		assert_almost_eq(c._score_at(ctx, pos, self_pos, none, pulled,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, 0.0, 10.0,
				GameRules.DEFAULT_LOFT_TAN_HIGH, keep), position_value, 1e-6,
				"keep %.1f" % keep)


func test_in_the_zone_the_keep_discounts_the_shot() -> void:
	var self_pos := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 8.0)
	var ctx: RoleContext = _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	var none: Array[Vector3] = []
	var keeper := ctx.attacking_goal_pos + Vector3(0.0, 0.0, 1.0)
	var kept: float = c._score_at(ctx, self_pos, self_pos, none, keeper,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, 0.0, 0.0,
			GameRules.DEFAULT_LOFT_TAN_HIGH, 1.0)
	assert_gt(kept, 0.0)
	assert_almost_eq(c._score_at(ctx, self_pos, self_pos, none, keeper,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, 0.0, 0.0,
			GameRules.DEFAULT_LOFT_TAN_HIGH, 0.5), kept * 0.5, 1e-6)


# ─── O-zone shot selection: don't fire the long shot on entry ────────────────

func test_carrier_entering_ozone_drives_the_slot_over_a_long_shot() -> void:
	# Carrier just inside the blue line, wide open, with a defending goalie set at a
	# realistic challenge depth. The long shot from the top of the zone is
	# low-danger (foreshortened net, long flight the goalie has time to react to),
	# while driving to the slot is a real look. In the O-zone the bot prices
	# positions by pure xG — there is NO establishment floor inflating a weak shot —
	# so it must CARRY toward the net, not fire from range the moment it crosses the
	# line. This is the guard on "don't shoot as soon as you enter the zone."
	var self_pos := Vector3(0, 0, -9)              # ~2 m inside the blue line
	var ctx := _make_ctx(self_pos)
	var g := GoalieNetworkState.new()
	g.position_x = 0.0
	g.position_z = -24.65                          # challenging ~2 m off the goal line
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"a long shot from the top of the zone loses to driving the slot")
	assert_lt(c.last_carry_anchor.z, self_pos.z,
			"…and the drive heads toward the net")


# ─── O-zone shot selection: get the shot off before running the goalie over ──

func test_bot_driving_the_net_gets_a_shot_off_before_the_goalie() -> void:
	# 1-on-1 drive at the net: as a bot carries straight in on the goalie, there
	# must be a distance at which it commits to the shot — and it must be clear
	# of the goalie, out in the slot, not point-blank in the crease where it would
	# just run the goalie over and get dispossessed. xG peaks around the slot and
	# falls as the goalie's shadow eats the angle point-blank, so carrying closer
	# stops paying and the bot fires. The goalie sits 1 m out — the live keeper's
	# rush BACKFLOW retreats him toward the crease at the carrier's pace, so this
	# is the realistic 1-on-1 depth. (Parked dead-square 2 m out he genuinely
	# walls off the straight fire — the honest read there is the lateral cut /
	# doorstep window, covered by test_1v1_lateral_cut_beats_the_aggressive_goalie
	# below, not a head-on shot.)
	# This drive is DEAD-CENTRE at a square keeper — the zero-angle line no
	# keeper at any depth concedes a corner from (the old model's head-on
	# release here was the phantom in-tight roof window, i.e. the
	# shot-into-the-chest bug). Since carry candidates price ARRIVING AT
	# PACE, the honest finish is a small lateral redirection off his centre
	# line, then fire — a committed finish either way. What must NEVER
	# happen on the drive is the failure this test exists for: carrying
	# straight in and running the keeper over (a near-centre anchor
	# at/inside his depth — the smother).
	var goalie_out: float = 1.0                          # backflowed 1 m off the line
	var goalie_z: float = -GameRules.GOAL_LINE_Z + goalie_out
	var finish_committed: bool = false
	for dist: float in [10.0, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0]:
		var self_pos := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + dist)
		var ctx := _make_ctx(self_pos)
		ctx.self_velocity = Vector3(0.0, 0.0, -6.0)      # driving hard at the net
		var g := GoalieNetworkState.new()
		g.position_x = 0.0
		g.position_z = goalie_z
		ctx.snapshot.goalie_states[1 - TEAM_ID] = g
		var c := AIRoleCarrier.new()
		c.decide(ctx)
		if c.intended_action == AIRoleCarrier.INTENT_SHOOT:
			# A release on the drive must come clear of the goalie, not from
			# point-blank inside his reach.
			assert_gt(dist, goalie_out + 1.0,
					"the drive's release comes clear of the goalie, not inside him")
			finish_committed = true
		elif c.intended_action == AIRoleCarrier.INTENT_CARRY and dist <= 7.0:
			# In tight, a carry commit on the drive must be the deke — a
			# genuine lateral redirection — never a straight-in anchor at the
			# keeper (the run-him-over smother).
			var straight_in: bool = absf(c.last_carry_anchor.x) < 1.2 \
					and c.last_carry_anchor.z <= goalie_z + 0.5
			assert_false(straight_in,
					"drive commit at %.0f m must be a shot or a lateral deke, "
					% dist + "not a straight carry into the smother")
			if absf(c.last_carry_anchor.x) >= 1.5:
				finish_committed = true
	assert_true(finish_committed,
			"somewhere on the drive the 1-on-1 commits a finish (shot or deke cut)")


func test_1v1_lateral_cut_beats_the_aggressive_goalie() -> void:
	# The penalty-shot guarantee: against a keeper challenging way out (2 m,
	# squared), the straight-in fire is correctly walled off — the play is to go
	# HORIZONTAL. The honest 1v1 unfolds in two beats:
	#   1. Cut starting, keeper still square: the drive-side window is already a
	#      real chance, but EXTENDING the cut reads better still — the carrier
	#      keeps driving laterally (never a stall, never a dump).
	#   2. Mid-cut, keeper beaten (lagging the arc race his accel-capped push
	#      lost): the shot commits, and it's a real chance.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 3.0)
	var cutting := _make_ctx(self_pos)
	cutting.self_velocity = Vector3(6.0, 0.0, 0.0)
	cutting.snapshot.skater_states[1].velocity = cutting.self_velocity
	# At that pace the body faces its travel (FacingRules), as it would in play.
	cutting.snapshot.skater_states[1].facing = Vector2(1.0, 0.0)
	cutting.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 2.0)
	var c := AIRoleCarrier.new()
	c.decide(cutting)
	assert_gt(c.debug_shoot_score, 0.3,
			"the cut's drive-side window is a real chance; got %f" % c.debug_shoot_score)
	if c.intended_action == AIRoleCarrier.INTENT_CARRY:
		assert_gt(c.last_carry_anchor.x, 1.0,
				"…and if the bot holds the fire, it's to EXTEND the cut, not stall")
	else:
		assert_eq(c.intended_action, AIRoleCarrier.INTENT_SHOOT)

	# Mid-cut with the keeper beaten: fire commits. (At a slightly longer cut
	# with the keeper closer behind, the compete legitimately prefers another
	# beat of carry — the projected release is past the apex while the current
	# spot still reads richer — so this snapshot is the unambiguous "window is
	# NOW" beat: the keeper a full step behind the arc race.)
	var beaten := _make_ctx(Vector3(1.8, 0.0, -GameRules.GOAL_LINE_Z + 3.0))
	beaten.self_velocity = Vector3(6.0, 0.0, 0.0)
	beaten.snapshot.skater_states[1].velocity = beaten.self_velocity
	beaten.snapshot.skater_states[1].facing = Vector2(1.0, 0.0)
	var lagged := GoalieNetworkState.new()
	lagged.position_x = 0.7   # still chasing — lost the arc race to the cut
	lagged.position_z = -GameRules.GOAL_LINE_Z + 2.0
	beaten.snapshot.goalie_states[1 - TEAM_ID] = lagged
	var cb := AIRoleCarrier.new()
	cb.decide(beaten)
	assert_eq(cb.intended_action, AIRoleCarrier.INTENT_SHOOT,
			"once the cut has beaten the keeper, the 1v1 commits the shot")
	assert_gt(cb.debug_shoot_score, 0.3,
			"…and it's a real chance, not a floor-scraper; got %f" % cb.debug_shoot_score)

	# Flat-footed vs the same 2 m over-challenge: the keeper is only ~1 m off
	# the puck, and from 3 m the steepest rung gets the puck no higher than his
	# pads, so no hold the blade can reach standing still beats him. The play is
	# a carry, and never one into his chest.
	var flat := _make_ctx(self_pos)
	flat.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 2.0)
	var c2 := AIRoleCarrier.new()
	c2.decide(flat)
	assert_lt(c2.debug_shoot_score, AIRoleCarrier.SHOT_MIN_VALUE,
			"flat-footed vs an overcommitted challenge, there is no shot; got %f"
			% c2.debug_shoot_score)
	assert_eq(c2.intended_action, AIRoleCarrier.INTENT_CARRY, "…so the 1v1 carries")
	assert_false(absf(c2.last_carry_anchor.x) < 1.2
			and c2.last_carry_anchor.z < self_pos.z,
			"…and not straight in at him (anchor %s)" % c2.last_carry_anchor)


func test_mid_cut_hold_never_out_prices_the_same_instants_fire() -> void:
	# Stand-still's shot branch shares the shoot-now score (see _best_carry), so
	# a mid-cut carrier can never conclude "holding here beats firing from
	# here". Before the share, stand-still priced its shot at the CURRENT spot
	# (pre-apex of the cut) while the fire priced the projected release (past
	# the apex) — the hold read richer than the fire from the same instant and
	# the bot carried through its own shooting window. If CARRY wins mid-cut it
	# must be a genuine relocation, never the in-place hold.
	for gx: float in [0.4, 0.7, 1.0]:
		var pos := Vector3(2.4, 0.0, -GameRules.GOAL_LINE_Z + 3.0)
		var ctx := _make_ctx(pos)
		ctx.self_velocity = Vector3(6.0, 0.0, 0.0)
		ctx.snapshot.skater_states[1].velocity = ctx.self_velocity
		var g := GoalieNetworkState.new()
		g.position_x = gx
		g.position_z = -GameRules.GOAL_LINE_Z + 2.0
		ctx.snapshot.goalie_states[1 - TEAM_ID] = g
		var c := AIRoleCarrier.new()
		c.decide(ctx)
		assert_gt(c.debug_shoot_score, 0.3,
				"the mid-cut window (goalie at x=%.1f) is a real chance" % gx)
		if c.intended_action == AIRoleCarrier.INTENT_CARRY:
			assert_gt(c.last_carry_anchor.distance_to(pos), 0.5,
					"mid-cut CARRY (goalie at x=%.1f) must be a relocation, not the hold"
					% gx)


func test_standstill_1v1_winds_up_the_cut() -> void:
	# IN TIGHT (3 m, keeper at a 1.3 m challenge), standing still: the steepest
	# rung gets the puck to ~0.5 m from here, under the pads he covers the mouth
	# with (AIShotValue.body_logit), so the shot is thin and the carry back to
	# the slot, where the rung clears him, beats it. The wind-up bootstrap this
	# test pins lives AT RANGE below, where the carry must still commit a real
	# advancing plan.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 3.0)
	var ctx := _make_ctx(self_pos)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 1.3)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"in tight and standing, the shot into a 1.3 m challenge is not the play")
	assert_gt(c.debug_carry_score, c.debug_shoot_score,
			"…the carry to where the puck clears him beats it; %f vs %f"
			% [c.debug_carry_score, c.debug_shoot_score])

	# Ever-receding-cut guard at RANGE: no phantom IMMEDIATE window out there
	# (the reach budget covers the keeper's full deploy), and what the carry
	# prices is the honest plan — work in to the mid-range quick-release band
	# and fire — not an orbit around a window that never arrives. So: the
	# direct shot stays a floor-scraper, the carry beats it, and the committed
	# anchor ADVANCES toward the net.
	var far_pos := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 9.0)
	var far := _make_ctx(far_pos)
	far.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(far_pos, net, 1.3)
	var cf := AIRoleCarrier.new()
	cf.decide(far)
	assert_eq(cf.intended_action, AIRoleCarrier.INTENT_CARRY,
			"at range vs a set keeper the play is still the carry")
	# Compared to the SAME release in tight, above — not to an absolute bar.
	# The currency's ceiling is a property of whichever shot model is wired in;
	# "no real window at range" is a statement about range, so it has to be
	# measured against a range that DOES open one.
	assert_lt(cf.debug_shoot_score, c.debug_shoot_score,
			"…because range opens less of the window than 3 m does; %f vs %f"
			% [cf.debug_shoot_score, c.debug_shoot_score])
	assert_gt(cf.debug_carry_score, cf.debug_shoot_score,
			"…and the priced plan (drive to the shooting band) beats flinging it")
	assert_lt(cf.last_carry_anchor.z, far_pos.z,
			"…with an anchor that advances toward the net, not an orbit")


func test_wing_carrier_with_a_step_curls_toward_the_middle() -> void:
	# The reported bug: a carrier who beat his man down the wing kept gliding
	# the wall to the goal line and turned at 90° — bizarre-looking, and it
	# forfeits every shooting angle. Re-anchored by the #27 compete
	# restructure: the momentum-aware plan may hold ONE full-speed stride
	# down the wall first (the honest cut geometry at 8.5 m/s), so the pin is
	# two-fold — the first committed target never rides to the goal-line
	# corner, and the follow-up decision from that spot bends hard off the
	# wall toward the middle while there is still angle to use.
	var self_pos := Vector3(9.0, 0.0, -14.0)
	var ctx: RoleContext = _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[10, 1 - TEAM_ID, Vector3(9.0, 0.0, -10.0)],   # beaten man, trailing
			[11, 1 - TEAM_ID, Vector3(-2.0, 0.0, -23.0)],  # far-side low cover
	])
	ctx.self_velocity = Vector3(0.0, 0.0, -8.5)            # driving the wing
	ctx.snapshot.skater_states[1].velocity = ctx.self_velocity
	ctx.snapshot.skater_states[10].velocity = Vector3(0.0, 0.0, -8.5)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			self_pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.2)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"still a carry read from the wing")
	# The reported bug was gliding the wall ALL the way to the goal line and
	# turning 90° there — forfeiting every angle. Under the momentum-honest
	# nominal-reach read the carrier may hold ONE full-speed stride down the
	# wall before curling, so the robust pin is that the committed target
	# never rides to the deep goal-line corner: it stays high with real angle
	# left to use, never a drift into the dead corner.
	assert_gt(c.debug_carry_pos.z, -20.0,
			"the committed carry stays off the deep goal-line corner; got %s"
			% c.debug_carry_pos)
	assert_lt(c.debug_carry_pos.z, self_pos.z - 0.5,
			"…while still advancing on the rush, not stalling; got %s"
			% c.debug_carry_pos)
	assert_gt(c.debug_carry_pos.z, OPP_NET_Z + 4.0,
			"…and stays above the goal line (a curl, not a corner dump); got %s"
			% c.debug_carry_pos)


func _squared_goalie(self_pos: Vector3, net: Vector3, depth: float) -> GoalieNetworkState:
	# Goalie arc-matched to the carrier (as the live keeper is — it tracks the
	# current puck-holder), sitting `depth` out from the net.
	var to_sh: Vector3 = self_pos - net
	to_sh.y = 0.0
	var g: Vector3 = net + to_sh.normalized() * depth
	var gs := GoalieNetworkState.new()
	gs.position_x = g.x
	gs.position_z = g.z
	return gs


# ─── where the shot is held (see AIRoleCarrier "Where the shot is held") ─────

func test_shot_holds_relocate_toward_the_open_side() -> void:
	# Goalie displaced onto the carrier's BACKHAND side (RH default: forehand is
	# +x when attacking -z; mirrored carrier at -1.2 with the goalie at -1.1):
	# the full-reach FOREHAND pull opens the far side wider than the puck's
	# own spot sees, and beside the stick hip it is fully loaded. From 3 m out,
	# standing, it still cannot get the puck over him, so whether it is taken is
	# not this test's claim.
	var pos := Vector3(-1.2, 0.0, -23.5)
	var ctx := _make_ctx(pos)
	var g := GoalieNetworkState.new()
	g.position_x = -0.8
	g.position_z = -25.0
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_gt(c.shoot_now_hold.x, 0.3,
			"the winning hold relocates the release toward the open (forehand) side")
	assert_almost_eq(c._shot_sample_share, 1.0, 0.001, "…loaded, at full pace")



func test_a_standstill_tuck_hands_the_keeper_the_time_to_follow() -> void:
	# Carrier tight beside the net at a dead-sharp angle, goalie holding the near
	# post. The tuck, a blade-reach out in front of the crease, pays the
	# backhand's turn standing still, which gives him time to follow, so it never
	# out-prices firing from where the puck is.
	var pos := Vector3(2.4, 0.0, -25.6)
	var ctx := _make_ctx(pos)
	var g := GoalieNetworkState.new()
	g.position_x = 0.85
	g.position_z = -26.1
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_lt(c.shoot_now_hold.z, 0.3, "the winning hold is not the tuck")
	assert_almost_eq(c._shot_sample_speed,
			ctx.self_wrister_shot_speed * c._shot_sample_share, 0.001,
			"…and it is priced at the pace its load carries there")


func test_shot_commit_carries_the_winning_hold() -> void:
	# The mid-cut fire (same snapshot as the 1v1 beaten beat): whatever hold
	# wins the sweep is exactly what the commit exposes to the state machine —
	# where the puck sits at the press and the share its load carries there.
	# The executed shot must be the scored one.
	var pos := Vector3(1.8, 0.0, -GameRules.GOAL_LINE_Z + 3.0)
	var ctx := _make_ctx(pos)
	ctx.self_velocity = Vector3(6.0, 0.0, 0.0)
	ctx.snapshot.skater_states[1].velocity = ctx.self_velocity
	var g := GoalieNetworkState.new()
	g.position_x = 0.7
	g.position_z = -GameRules.GOAL_LINE_Z + 2.0
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_SHOOT, "the mid-cut window fires")
	assert_eq(c.shot_hold_offset, c.shoot_now_hold,
			"the commit exposes exactly the winning hold")
	assert_eq(c.shot_hold_share, c._shot_sample_share, "…and the share it was priced at")


func test_wide_angle_shot_is_not_taken_against_a_squared_goalie() -> void:
	# A shot from a wide angle vs a squared keeper should be a nothing look.
	# Un-pended by the dead-angle post-play extension (#28): the carrier's
	# release sampler derives the predicted seal, and past the erasure
	# threshold (net window narrower than a keeper on the near post) the
	# whole look dies — no phantom far-side window to fire at.
	var self_pos := Vector3(7.0, 0.0, -24.0)               # ~69° off the normal
	var ctx := _make_ctx(self_pos)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			self_pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.2)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_lt(c.debug_shoot_score, 0.3,
			"the wide-angle look reads near-nothing; got %f" % c.debug_shoot_score)
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_SHOOT,
			"…so the carrier does not fire it")


const _DEAD_SLOT := Vector3(0.0, 0.0, -22.0)
const _MID_BAND := Vector3(0.0, 0.0, -18.15)      # 8.5 m out
const _WIDE_SPOT := Vector3(9.0, 0.0, -22.0)


# The carrier's shoot-now score from `shooter`, keeper set 1.3 m out and squared
# to `squared_to`.
func _shoot_now(shooter: Vector3, squared_to: Vector3) -> float:
	var ctx := _make_ctx(shooter)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			squared_to, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	return _decided(ctx).debug_shoot_score


func test_the_slot_beats_the_band_and_displacement_beats_the_set_keeper() -> void:
	# Straight on against a set keeper, the dead slot is worth more than the 8.5 m
	# band; and at the band, a keeper still squared to a spot the shooter left
	# (beaten by a cross-ice relocation) concedes more than one squared to him.
	var set_band: float = _shoot_now(_MID_BAND, _MID_BAND)
	assert_gt(_shoot_now(_DEAD_SLOT, _DEAD_SLOT), set_band,
			"the dead slot is worth more than the mid-range band")
	assert_gt(_shoot_now(_MID_BAND, _WIDE_SPOT), set_band,
			"a keeper still squared to the old spot concedes more than a set one")


# ─── breakout: wall-exit carry route when the middle is clogged ──────────────

func test_wall_exit_carry_wins_when_middle_is_clogged() -> void:
	# Carrier wheeling up the weak-side wall with momentum, forecheck set
	# up through the middle (one opponent pinching the local up-ice steps,
	# another sitting in the diagonal slot-drive lane from this wide start).
	# No teammates → no pass bailout. The zone-exit wall candidate — a real
	# "skate it out along the boards" plan — should win the carry argmax over
	# the myopic 3 m steps and the through-the-middle slot drive.
	var self_pos := Vector3(-10.5, 0, 21)
	var skaters: Array = [
			[1, TEAM_ID, self_pos, false, Vector3(0, 0, -5)],  # us, skating up-ice
			[3, 1, Vector3(-7.5, 0, 16.5)],                    # pinching the up-ice step
			[4, 1, Vector3(-6.5, 0, 6)],                       # sits in the slot-drive lane
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.self_velocity = Vector3(0, 0, -5)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"nothing to shoot at or pass to — this is a carry read")
	# Hugs the boards on OUR side (away from the clogged middle), heading up-ice
	# toward the exit. The bot skates the wall out step-by-step (re-picking each
	# tick) rather than committing to the far exit anchor in one shot — the
	# near boards step decays less, and it's the same "skate it out" behaviour.
	assert_lt(c.last_carry_anchor.x, -10.0,
			"the winning carry anchor hugs our (left) boards, not the clogged middle")
	assert_lt(c.last_carry_anchor.z, self_pos.z,
			"…and moves up-ice toward the zone exit, not deeper or across")


func test_wall_exit_candidates_absent_in_offensive_half() -> void:
	# Wall exits are own-half candidates only. An OZ carrier's anchor must
	# come from the local steps / slot anchor — never a point back at our
	# blue line (own_goal_dir * z > 0 for team 0 is z > 0; the exit z sits
	# at +(BLUE_LINE_Z - lead), which would be BEHIND an OZ carrier).
	var self_pos := Vector3(-8, 0, -15)  # offensive half, wide
	var ctx := _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_lt(c.last_carry_anchor.z, 0.0,
			"an offensive-half carrier never targets the own-half wall-exit point")


# ─── stagger: don't wind up a shot off-balance ──────────────────────────────

func test_staggered_carrier_holds_instead_of_firing() -> void:
	# Reuse the pressured-breakout setup that reliably fires a PASS: carrier
	# boxed by forecheckers with an open up-wall outlet.
	var self_pos := Vector3(3, 0, 20)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(11, 0, 11)],     # open outlet
			[3, 1, Vector3(1.5, 0, 18.0)],        # forechecker
			[4, 1, Vector3(3.0, 0, 17.5)],        # forechecker
	]

	# Not staggered → commits the fire (the breakout pass).
	var c1 := AIRoleCarrier.new()
	c1.decide(_make_ctx(self_pos, skaters))
	assert_ne(c1.intended_action, AIRoleCarrier.INTENT_CARRY,
			"pressured carrier commits a fire (breakout pass) when not staggered")

	# Staggered → holds the puck rather than flailing a release off-balance,
	# even though the fire would otherwise win.
	var ctx_staggered: RoleContext = _make_ctx(self_pos, skaters)
	ctx_staggered.self_stagger_timer = 0.5
	var c2 := AIRoleCarrier.new()
	c2.decide(ctx_staggered)
	assert_eq(c2.intended_action, AIRoleCarrier.INTENT_CARRY,
			"staggered carrier holds instead of committing the fire")


# ─── settle doubt: a fresh carrier's bar for giving the puck up ──────────────

# The same pressured breakout, with the outlet in two different situations. Both
# are legal passes that fire on tick one with no doubt; the strong one is worth
# ~11x PASS_MIN_VALUE, the weak one ~1.9x — inside the 1x-2.5x window Normal's
# doubt holds. The weak outlet is still sliding into the far corner, so his drive
# up the wall has to brake that out first. Both values are future value and so
# scale with READ_VALIDITY_TAU_S against a fixed bar: re-size the weak one's depth
# when that moves, never its slide (past 6 m/s the lane dies outright).
func _settle_skaters(self_pos: Vector3, outlet: Vector3) -> Array:
	var outlet_vel: Vector3 = _MARGINAL_OUTLET_VEL if outlet == _MARGINAL_OUTLET \
			else Vector3.ZERO
	return [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, outlet, false, outlet_vel],
			[3, 1, Vector3(1.5, 0, 18.0)],        # forechecker
			[4, 1, Vector3(3.0, 0, 17.5)],        # forechecker
	]


const _STRONG_OUTLET := Vector3(11, 0, 11)    # open, up the strong wall
const _MARGINAL_OUTLET := Vector3(13, 0, 24.5)  # deep in the far corner
const _MARGINAL_OUTLET_VEL := Vector3(0, 0, 6.0)   # …and still sliding into it


func _settle_ctx(self_pos: Vector3, outlet: Vector3) -> RoleContext:
	var ctx: RoleContext = _make_ctx(self_pos, _settle_skaters(self_pos, outlet))
	ctx.settle_penalty_frac = 0.6   # Normal's own dial
	ctx.settle_penalty_tau_s = 0.3
	return ctx


# The whole reason the settle knob is a raised bar rather than the flat "may not
# commit for N seconds" gate it replaced: on the same fresh touch, under the SAME
# doubt, the obvious play goes at once and the marginal one waits. A flat gate
# can only hold both.

func test_an_obvious_outlet_beats_the_settle_doubt_outright() -> void:
	var self_pos := Vector3(3, 0, 20)
	var c := AIRoleCarrier.new()
	c.decide(_settle_ctx(self_pos, _STRONG_OUTLET))
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"a wide-open outlet is worth the puck on the first touch")


func test_a_marginal_outlet_pays_the_settle_doubt() -> void:
	var self_pos := Vector3(3, 0, 20)
	# Sanity: the weak outlet IS a legal fire — it's the doubt that holds it, not
	# the standing giveaway bar.
	var undoubted := AIRoleCarrier.new()
	undoubted.decide(_make_ctx(self_pos, _settle_skaters(self_pos, _MARGINAL_OUTLET)))
	assert_eq(undoubted.intended_action, AIRoleCarrier.INTENT_PASS,
			"sanity: with no doubt the weak outlet fires on tick one")

	var ctx: RoleContext = _settle_ctx(self_pos, _MARGINAL_OUTLET)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"the weak outlet isn't worth a fresh puck — the raised bar rejects it")
	assert_gt(c.debug_pass_score, 0.0,
			"scores keep computing — the doubt only raises the bar they must clear")
	# Let the doubt decay in real ticks (decide() steps ctx.dispatch_period_ticks
	# = 1 tick per call). 60 ticks = 0.5 s covers the flip plus a re-eval cadence.
	for _i: int in range(60):
		c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"the same outlet is worth the puck once the carrier has settled")


func test_an_obvious_shot_beats_the_settle_doubt_outright() -> void:
	# The open backdoor tap-in the flat gate used to swallow: from the slot with
	# the keeper stranded on the far post, no pressure, the look is worth many
	# times SHOT_MIN_VALUE, so a raised bar is nothing to it.
	var self_pos := Vector3(-1.0, 0.0, -GameRules.GOAL_LINE_Z + 4.5)
	var ctx := _make_ctx(self_pos)
	var g := GoalieNetworkState.new()
	g.position_x = 1.2
	g.position_z = -GameRules.GOAL_LINE_Z + 0.5
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	ctx.settle_penalty_frac = 0.6
	ctx.settle_penalty_tau_s = 0.3
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_gt(c.debug_shoot_score, AIRoleCarrier.SHOT_MIN_VALUE * 4.0,
			"sanity: the look is obvious; got %f" % c.debug_shoot_score)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_SHOOT,
			"an obvious shot fires on tick one despite a deep settle doubt")


func test_settle_doubt_rearms_on_reset_but_not_on_clear_intent() -> void:
	var self_pos := Vector3(3, 0, 20)
	var ctx: RoleContext = _settle_ctx(self_pos, _MARGINAL_OUTLET)
	var c := AIRoleCarrier.new()
	for _i: int in range(61):
		c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS, "sanity: the doubt drained")

	# clear_intent (press-state handoff / bail) is the SAME possession — the
	# next decide may re-commit immediately, with no fresh doubt.
	c.clear_intent()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"a press bail back to CARRY re-fires without re-settling")

	# reset (puck lost) marks the next decide as a NEW possession — the doubt
	# re-arms at full and the marginal outlet is held again.
	c.reset()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"regaining the puck starts a fresh settle doubt")


func test_zero_settle_doubt_is_the_hard_baseline() -> void:
	# ctx default (0.0) must reproduce the pre-knob behavior exactly: the
	# pressured carrier fires on its first decide.
	var self_pos := Vector3(3, 0, 20)
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, _settle_skaters(self_pos, _STRONG_OUTLET)))
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"no settle doubt → the tick-one fire is unchanged")


# ─── reset() ──────────────────────────────────────────────────────────────

func test_reset_clears_all_persistent_state() -> void:
	var c := AIRoleCarrier.new()
	c.intended_action = AIRoleCarrier.INTENT_PASS
	c.pass_target_peer_id = 42
	c.pass_should_charge = true
	c.pass_should_saucer = true
	c.shot_loft_level = ShotMechanics.ELEVATION_HIGH
	c.last_carry_anchor = Vector3(5.0, 0.0, -10.0)

	c.reset()

	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY)
	assert_eq(c.pass_target_peer_id, -1)
	assert_false(c.pass_should_charge)
	assert_false(c.pass_should_saucer)
	assert_eq(c.shot_loft_level, ShotMechanics.ELEVATION_FLAT)
	assert_eq(c.last_carry_anchor, Vector3.ZERO)


# ─── clear_intent() ───────────────────────────────────────────────────────

func test_clear_intent_resets_intent_but_preserves_carry_anchor() -> void:
	var c := AIRoleCarrier.new()
	c.intended_action = AIRoleCarrier.INTENT_SHOOT
	c.pass_target_peer_id = 42
	c.pass_should_charge = true
	c.pass_should_saucer = true
	c.last_carry_anchor = Vector3(5.0, 0.0, -10.0)

	c.clear_intent()

	# Intent + pass target reset; carry anchor preserved (state machine
	# may still be reading it during the press cycle).
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY)
	assert_eq(c.pass_target_peer_id, -1)
	assert_false(c.pass_should_charge)
	assert_false(c.pass_should_saucer)
	assert_eq(c.last_carry_anchor, Vector3(5.0, 0.0, -10.0))


# ─── decide() cooldown ────────────────────────────────────────────────────

func test_decide_throttles_pick_action_at_period_ticks() -> void:
	# First decide() runs _pick_action (cooldown was 0). Subsequent
	# calls within PICK_ACTION_PERIOD_TICKS should NOT re-run
	# _pick_action — last_carry_anchor and intended_action stay
	# fixed. We verify this by mutating intended_action between
	# decides and confirming the second call doesn't overwrite it
	# (because it's still in cooldown).
	var c := AIRoleCarrier.new()
	var ctx: RoleContext = _make_ctx(Vector3(0.0, 0.0, -22.0))  # in slot

	c.decide(ctx)  # tick 0: runs _pick_action, sets cooldown to PERIOD_TICKS

	# Force-flip the persistent intent. If the next decide() ran
	# _pick_action again, it would overwrite this.
	c.intended_action = AIRoleCarrier.INTENT_PASS

	for i in range(AIRoleCarrier.PICK_ACTION_PERIOD_TICKS - 1):
		c.decide(ctx)

	# Still inside cooldown — intent must be the artificially-set value.
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"decide() should NOT re-run _pick_action within the cooldown window")


func test_decide_re_evaluates_after_cooldown_expires() -> void:
	# Same as above, but tick exactly PICK_ACTION_PERIOD_TICKS times
	# so the next decide() re-evaluates. A steady-state re-eval is
	# TIME-SLICED across two dispatches (fire phase, then carry + commit —
	# see the slice doc above _commit_phase_pending), so the new intent
	# lands on the second decide() after the cooldown expires.
	var c := AIRoleCarrier.new()
	var ctx: RoleContext = _make_ctx(Vector3(0.0, 0.0, -22.0))

	c.decide(ctx)  # tick 0: runs _pick_action (first eval = single-call)
	# Drain the cooldown the code actually ARMS, not a nominal period: which one
	# it arms depends on what the compete answered (an empty-rink CARRY is the
	# open-ice LOD case in _arm_pick_cooldown, re-armed at a third of the rate).
	# Draining the wrong one leaves the carrier mid-cooldown and the flip below
	# survives — which reads as "the re-eval never ran" when the truth is "it
	# was not due yet".
	for i in range(AIRoleCarrier.PICK_ACTION_PERIOD_TICKS
			* AIRoleCarrier.OPEN_ICE_LOD_PERIOD_MULT):
		if c._pick_action_cooldown <= 0:
			break
		c.decide(ctx)
	# Force-flip and run the sliced re-eval to its commit: fire phase on the
	# first call, carry + commit (which overwrites our flip) on the second.
	c.intended_action = AIRoleCarrier.INTENT_PASS
	c.decide(ctx)
	c.decide(ctx)

	# After re-eval the carrier picks based on the snapshot. The exact
	# winning intent depends on scoring math (covered in
	# test_ai_action_scoring); the contract here is just "the re-eval
	# ran and overwrote our manual flip."
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"decide() should re-run the compete after cooldown elapses, replacing the manually-set intent")


# ─── decide() return shape ────────────────────────────────────────────────

func test_decide_returns_role_decision_with_target_position() -> void:
	var c := AIRoleCarrier.new()
	var ctx: RoleContext = _make_ctx(Vector3(0.0, 0.0, -22.0))
	var d: RoleDecision = c.decide(ctx)
	# target_position mirrors last_carry_anchor; one of the carry
	# candidates (or stand-still) wins, so it must be a valid Vector3.
	assert_eq(d.target_position, c.last_carry_anchor)


func test_in_motion_toward_slot_scores_higher_than_stationary() -> void:
	# Anticipation: score_shoot is evaluated at the projected RELEASE
	# position (current pos + horizontal_velocity × charge_lookahead).
	# A bot rushing into the slot should score the spot they'll release
	# from — meaning a moving bot OUT of slot range should outscore a
	# stationary bot at the same current pos.
	#
	# Both bots stand at z = -15 (~12 m from opp goal at z = -26.65 —
	# outside ideal but inside SHOT_RANGE_FALLOFF_M). The moving bot
	# travels toward the goal at 8 m/s. With BOT_WRISTER_LOOKAHEAD_S
	# = 0.25, the projected release pos is z ≈ -17 → ~10 m from goal,
	# noticeably better dist_response than 12 m.
	var pos := Vector3(0.0, 0.0, -18.0)
	var stationary_ctx: RoleContext = _make_ctx(pos)
	stationary_ctx.self_velocity = Vector3.ZERO
	var moving_ctx: RoleContext = _make_ctx(pos)
	moving_ctx.self_velocity = Vector3(0.0, 0.0, -8.0)

	var stationary := AIRoleCarrier.new()
	stationary.decide(stationary_ctx)
	var moving := AIRoleCarrier.new()
	moving.decide(moving_ctx)

	assert_gt(moving.debug_shoot_score, stationary.debug_shoot_score,
			"in-motion bot rushing into slot should score the release-pos spot, beating the stationary same-pos shot")


func test_zero_value_fire_does_not_win_in_own_zone() -> void:
	# Carrier buried deep in its own end (z = +22, ~48 m from the opp
	# goal at z = -26.65). Shoot/quick-shot score 0 (far past
	# SHOT_RANGE_FALLOFF_M) and there are no teammates to pass to, so
	# every fire option is 0. Before the positive-value gate the bot
	# fired on the 0-0 fire-vs-carry tie (FIRE WINS TIES); now a zero
	# fire can't win, so it must keep the puck (CARRY).
	var c := AIRoleCarrier.new()
	var ctx: RoleContext = _make_ctx(Vector3(0.0, 0.0, 22.0))
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"a negligible-value fire must not beat holding the puck deep in our own zone")
	assert_lt(c.debug_shoot_score, 0.02,
			"sanity: shoot is negligible from ~48 m (net subtends almost nothing)")


func test_positive_shot_scores_above_zero_in_slot() -> void:
	# Regression guard for the positive-value fire gate. The gate
	# (fire_score >= carry_score AND fire_score > 0) only changes
	# behavior at fire_score == 0; a positive fire is scored exactly as
	# before. We assert the precondition the gate keys on — a slot shot
	# scores well above 0 — rather than that fire WINS the action pick:
	# with an empty net (no goalie/defenders in this minimal ctx) a
	# carry toward the open net legitimately outscores a slot shot, so
	# which action wins is scenario-dependent and not what this gate
	# governs. The zero-case is covered by
	# test_zero_value_fire_does_not_win_in_own_zone.
	var c := AIRoleCarrier.new()
	var ctx: RoleContext = _make_ctx(Vector3(0.0, 0.0, -22.0))  # in slot
	c.decide(ctx)
	assert_gt(c.debug_shoot_score, 0.0,
			"a slot shot scores positive, so the >0 gate never blocks it")


# ─── principled hold: the developing cross-seam EV (no magic numbers) ────────
# _best_developing_feed is the value the carrier weighs against firing now —
# P(keep) × this × decay(held) competes directly in the action max.

func _ctx_with_finisher(fin_pos: Vector3, ready: bool) -> RoleContext:
	# Carrier strong-side in the OZ; a FINISHER-slotted teammate staging at fin_pos.
	var self_pos := Vector3(4, 0, -18)
	var ctx := _make_ctx(self_pos, [[1, TEAM_ID, self_pos], [2, TEAM_ID, fin_pos]])
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = AIRoleSlots.Slot.FINISHER
	if ready:
		brain.set_one_timer_ready(2, true)
	ctx.team_brain = brain
	# A live keeper challenged on the carrier's line: the cross-seam feed's
	# whole value is the traverse he can't finish inside the flight — a
	# keeper parked on the goal line (the fixture default) has no traverse
	# to lose and reads every developing spot as dead.
	var g := GoalieNetworkState.new()
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var dir: Vector3 = (self_pos - net).normalized()
	g.position_x = net.x + dir.x * 1.3
	g.position_z = net.z + dir.z * 1.3
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	return ctx


func test_developing_feed_zero_without_brain() -> void:
	var ctx := _make_ctx(Vector3(4, 0, -18))
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_eq(carrier._best_developing_feed(ctx), 0.0,
			"no team brain → nothing to wait for")


func test_developing_feed_zero_when_finisher_already_ready() -> void:
	# Already-flagged finisher is fed by normal scoring — not something to hold for.
	var ctx := _ctx_with_finisher(Vector3(-2.5, 0, -21.5), true)
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_eq(carrier._best_developing_feed(ctx), 0.0)


func test_developing_feed_positive_for_staging_cross_seam_finisher() -> void:
	var ctx := _ctx_with_finisher(Vector3(-2.5, 0, -21.5), false)
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_gt(carrier._best_developing_feed(ctx), 0.0,
			"a staging cross-seam finisher gives a positive developing feed")


func test_developing_feed_invisible_without_the_cognition_gate() -> void:
	# Same staging finisher the test above values positively — but a tier that
	# doesn't hold for developing plays (Easy) sees nothing: it plays only what
	# exists right now.
	var ctx := _ctx_with_finisher(Vector3(-2.5, 0, -21.5), false)
	ctx.holds_for_developing_feeds = false
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_eq(carrier._best_developing_feed(ctx), 0.0,
			"the developing play is invisible to a tier without the hold read")


func test_goalie_motion_blind_reads_the_keeper_as_always_set() -> void:
	# Goalie parked well off the shooter's arc with a short release window —
	# the re-square race is live, so a motion-reading bot sees a positive
	# unsettled window (the cross-seam one-timer value). A motion-blind tier
	# models him as always set: the same read returns exactly 0.
	var self_pos := Vector3(0.0, 0.0, -18.0)
	var ctx := _make_ctx(self_pos)
	var gs := GoalieNetworkState.new()
	gs.position_x = -2.5                          # ~2.5 m off the square line
	gs.position_z = OPP_NET_Z + 1.2
	ctx.snapshot.goalie_states[1 - TEAM_ID] = gs
	var carrier := AIRoleCarrier.new()
	assert_gt(carrier._goalie_unsettled_at(ctx, 0.2, self_pos), 0.0,
			"an off-square keeper on a short release reads unsettled")
	ctx.reads_goalie_motion = false
	assert_eq(carrier._goalie_unsettled_at(ctx, 0.2, self_pos), 0.0,
			"a motion-blind tier reads the same keeper as set")


func test_developing_feed_zero_for_ghosted_finisher() -> void:
	# An offside (ghosted) finisher can't legally receive — the live pass
	# scoring skips ghosts, so the hold must too, or the carrier waits
	# for a feed it's never allowed to make.
	var self_pos := Vector3(4, 0, -18)
	var ctx := _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-3, 0, -19), true]])  # staging spot, but ghosted
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = AIRoleSlots.Slot.FINISHER
	ctx.team_brain = brain
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_eq(carrier._best_developing_feed(ctx), 0.0,
			"a ghosted finisher isn't a developing play — nothing to hold for")


func test_developing_feed_zero_when_finisher_out_of_offensive_zone() -> void:
	# Finisher back in the neutral zone (z = -5 > -BLUE_LINE_Z) → not a cross-seam.
	var ctx := _ctx_with_finisher(Vector3(-3, 0, -5), false)
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_eq(carrier._best_developing_feed(ctx), 0.0,
			"a finisher outside the OZ isn't a developing cross-seam")


func test_developing_feed_counts_a_finisher_still_crossing_the_line() -> void:
	# A finisher a stride OUTSIDE the blue line driving hard into the zone IS
	# the developing cross-seam — the old current-position gate read exactly 0
	# here, so a carrier fresh off the entry saw nothing worth waiting for and
	# settled for the weak from-the-top shot. Parked at the same spot he still
	# reads 0: the gate opens on where he's GETTING to, not a slot label.
	var fin_pos := Vector3(-5, 0, -(GameRules.BLUE_LINE_Z - 1.0))
	var parked := _ctx_with_finisher(fin_pos, false)
	var c1 := AIRoleCarrier.new()
	c1._scratch_teammate_ids = [2]
	assert_eq(c1._best_developing_feed(parked), 0.0,
			"parked outside the line: nothing developing")
	var driving := _ctx_with_finisher(fin_pos, false)
	driving.snapshot.skater_states[2].velocity = Vector3(1.0, 0, -8.5)
	var c2 := AIRoleCarrier.new()
	c2._scratch_teammate_ids = [2]
	assert_gt(c2._best_developing_feed(driving), 0.0,
			"driving in: the entering finisher is a developing play")


func test_developing_feed_values_the_spot_the_finisher_is_driving_to() -> void:
	# A finisher high in the zone skating hard for the house is priced at the
	# spot he's driving to (velocity projection, same primitive as the
	# developing outlet) — worth more than the same man parked high. The drive
	# heads for the net-front (that's what "driving to the house" is): a drive
	# that stays high and wide reaches a spot the body-occlusion shot model
	# honestly prices at ~0.
	var fin_pos := Vector3(-5, 0, -12.0)
	var parked := _ctx_with_finisher(fin_pos, false)
	var c1 := AIRoleCarrier.new()
	c1._scratch_teammate_ids = [2]
	var feed_parked: float = c1._best_developing_feed(parked)
	var driving := _ctx_with_finisher(fin_pos, false)
	driving.snapshot.skater_states[2].velocity = Vector3(2.5, 0, -6.5)
	var c2 := AIRoleCarrier.new()
	c2._scratch_teammate_ids = [2]
	assert_gt(c2._best_developing_feed(driving), feed_parked,
			"the feed is valued at the spot the finisher is getting to")


func test_fresh_entry_holds_for_the_driving_finisher_over_the_top_shot() -> void:
	# Seconds after a zone entry, box set, carry strangled: the mate driving to
	# the house is the play, so the developing feed must out-value the marginal
	# shot from above the circle and the hold (feed × keep × decay) wins the
	# compete instead of the giveaway.
	var self_pos := Vector3(2, 0, -14.5)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-5, 0, -15.0), false, Vector3(0.8, 0, -7.5)],
			[3, TEAM_ID, Vector3(6, 0, -6.3)],       # support high at the line
			# Set D box, strong side, deliberately clear of the carrier ->
			# driving-finisher lane: a defender parked in that lane makes the
			# feed honestly worse than the shot.
			[11, 1, Vector3(1.5, 0, -20.5)],
			[12, 1, Vector3(2.5, 0, -19.0)],
			[13, 1, Vector3(0.5, 0, -11.3)],         # high man choking the carry
	]
	var ctx := _make_ctx(self_pos, skaters)
	var g := GoalieNetworkState.new()
	g.position_x = 0.45                              # tracking, not dead-set centre
	g.position_z = -26.65 + 1.3
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = AIRoleSlots.Slot.FINISHER
	brain.slot_assignments[3] = AIRoleSlots.Slot.SUPPORT
	ctx.team_brain = brain
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_SHOOT,
			"the marginal top shot is not taken while the play develops")
	assert_gt(c._best_developing_feed(ctx), c.debug_shoot_score,
			"the developing feed out-values the from-the-top shot")


# ─── developing breakout outlet: hold instead of forcing the backpass ────────
# A BREAKOUT_STRONG / OUTLET teammate skating its route is a developing
# feed: _developing_outlet_feed projects it OUTLET_DEVELOP_WINDOW_S along
# its velocity and prices the pass to that spot through the same _pass_ev
# as the live scoring.

func _ctx_with_outlet(outlet_pos: Vector3, outlet_vel: Vector3,
		ghost: bool = false) -> RoleContext:
	# Carrier deep in our own zone; teammate 2 slotted BREAKOUT_STRONG.
	var self_pos := Vector3(2, 0, 20)
	var ctx := _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, outlet_pos, ghost, outlet_vel]])
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = AIRoleSlots.Slot.BREAKOUT_STRONG
	ctx.team_brain = brain
	return ctx


func test_developing_feed_positive_for_outlet_skating_its_route() -> void:
	# Outlet on the strong wall, skating hard up-ice toward the blue line.
	var ctx := _ctx_with_outlet(Vector3(9, 0, 16), Vector3(1.2, 0, -6))
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_gt(carrier._best_developing_feed(ctx), 0.0,
			"an outlet skating up its route is a developing feed worth holding for")


func test_developing_feed_zero_for_stationary_outlet() -> void:
	# A parked outlet offers exactly the spot it's at — the live pass
	# scoring already prices that; nothing is developing.
	var ctx := _ctx_with_outlet(Vector3(9, 0, 16), Vector3.ZERO)
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_eq(carrier._best_developing_feed(ctx), 0.0,
			"a stationary outlet isn't developing anything")


func test_developing_feed_zero_for_ghosted_outlet() -> void:
	var ctx := _ctx_with_outlet(Vector3(9, 0, 16), Vector3(1.2, 0, -6), true)
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_eq(carrier._best_developing_feed(ctx), 0.0,
			"a ghosted outlet can't receive — no developing feed")


func test_developing_outlet_beats_the_spot_it_left_behind() -> void:
	# The whole point of the hold: the pass the outlet is CREATING
	# (projected up its route, toward open ice) out-values the pass to
	# where it currently stands. Compare the developing feed of a moving
	# outlet against one parked at the same spot but projected nowhere.
	var moving := _ctx_with_outlet(Vector3(9, 0, 16), Vector3(1.2, 0, -6))
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	var developing: float = carrier._best_developing_feed(moving)

	# The same feed valued AT the outlet's current spot: reuse _pass_ev
	# directly so both sides run identical pricing.
	var spot := Vector3(9, 0, 16)
	var dist: float = moving.self_pos.distance_to(spot)
	var pass_speed: float = AIPuckLane.pass_launch_speed(
			dist, moving.self_wrister_shot_speed, moving.pass_speed_scale)
	var flight_t: float = clampf(dist / pass_speed, 0.0, AIRoleCarrier.PASS_LEAD_MAX_S)
	var carrier2 := AIRoleCarrier.new()
	carrier2._scratch_teammate_ids = [2]
	var stay_put: float = carrier2._pass_ev(
			moving, spot, pass_speed, flight_t,
			flight_t + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S, flight_t,
			moving.defending_goal_pos)

	assert_gt(developing, stay_put,
			"the projected up-ice spot out-values the spot the outlet is leaving")


func test_pressured_carrier_never_forces_the_backpass_when_outlet_develops() -> void:
	# The user-facing behavior: carrier pressured deep in our zone, a
	# close backpass valve available, and the strong-side outlet skating
	# its route. Acceptable reads are "keep the puck while the breakout
	# develops" or "headman it up-ice to the outlet" — what must never
	# happen is forcing the ground-losing backpass to the deep valve.
	var self_pos := Vector3(2, 0, 20)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(9, 0, 16), false, Vector3(1.2, 0, -6)],  # outlet en route
			[5, TEAM_ID, Vector3(-3, 0, 24)],                             # deep valve (bait)
			[3, 1, Vector3(2, 0, 17.5), false, Vector3(0, 0, 5)],         # forechecker charging
	]
	var ctx := _make_ctx(self_pos, skaters)
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = AIRoleSlots.Slot.BREAKOUT_STRONG
	brain.slot_assignments[5] = AIRoleSlots.Slot.BREAKOUT_WEAK
	ctx.team_brain = brain
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	if c.intended_action == AIRoleCarrier.INTENT_PASS:
		assert_eq(c.pass_target_peer_id, 2,
				"if the carrier passes under pressure, it's up-ice to the outlet — never the deep valve")
	else:
		assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
				"otherwise the carrier keeps the puck while the breakout develops")


# ─── dumping: last-resort relief in two specific spots ───────────────────────

func test_swarmed_own_zone_carrier_squeezes_out_with_possession() -> void:
	# Deep in our slot with the forecheck converging. Re-anchored by the
	# measured meeting-strip band: at BLADE-CONTACT range (all three men
	# ~1.5 m off the puck, flanks OPPOSED so the protect budget splits to
	# nothing) every escape route honestly dies at its crossing — the duel
	# physics strip a carrier at that range — so the clear fires as the true
	# last resort. Loosen the same swarm a stride and a protected route
	# survives, so the compete flips back to fighting for possession. The
	# FLIP is the pin: the clear stays a last resort, never the default.
	# (The clear's GEOMETRY stays pinned by the direct _best_dump test below.)
	var self_pos := Vector3(6, 0, 24)                      # deep slot, swarmed
	var tight: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(6, 0, 22.2), false, Vector3(0, 0, 5)],
			[4, 1, Vector3(4.6, 0, 24.6)],
			[5, 1, Vector3(7.4, 0, 24.6)],
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, tight))
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_DUMP,
			"on-blade opposed swarm: no route survives the measured band — clear it")

	var loose: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(6, 0, 20.0), false, Vector3(0, 0, 5)],
			[4, 1, Vector3(3.2, 0, 24.6)],
			[5, 1, Vector3(8.8, 0, 24.6)],
	]
	var c2 := AIRoleCarrier.new()
	c2.decide(_make_ctx(self_pos, loose))
	assert_ne(c2.intended_action, AIRoleCarrier.INTENT_DUMP,
			"a stride of air and the carrier fights for possession instead")


func test_best_dump_geometry_in_own_zone_is_a_hard_rim_out() -> void:
	# Direct pin on what the DZ clear ACHIEVES, not on the bearing it picks.
	# The clear is a searched release now, so the side it comes off is an
	# outcome of the icing constraint and the ice in front of the carrier, not
	# a formula — what has to hold is that the puck leaves our end and stays in
	# play. dump[4] is the resting spot; dump[1] is only where the stick points.
	var self_pos := Vector3(6, 0, 24)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(6, 0, 22)],
	]
	var ctx: RoleContext = _make_ctx(self_pos, skaters)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var dump: Array = c._best_dump(ctx, AIRoleHelpers.resolve_our_goalie_pos(ctx))
	assert_false(dump[2], "a DZ clear is a chip out, not a soft corner flip")
	var settle: Vector3 = dump[4]
	gut.p("  DZ clear from %s settles at %s" % [self_pos, settle])
	assert_false(
			AIActionScoring.in_offensive_zone(settle, ctx.defending_goal_pos),
			"the clear takes the puck out of our defensive zone")
	# And it does not ice: the release never reaches their goal line.
	assert_lt(absf(settle.z), GameRules.GOAL_LINE_Z,
			"the clear stays in play — no goal-line crossing")


func test_contained_past_center_with_open_backfield_regroups() -> void:
	# Carrier past centre, denied at the blue line, nothing to pass — but the
	# ice BEHIND is open: the play is curling back to regroup, not conceding.
	# The denial has to be genuine: a set stand-up line, head D at gap and
	# flankers bracketing both swing lanes, kills every crossing. A static head
	# D inside ~1.2 m gets stepped around, and a line retreating from a tight gap
	# gets blown through; this head gap sits mid-plateau (the anchor is the same
	# across 1.4-2.0 m).
	var self_pos := Vector3(2, 0, -4)                      # attacking half (attack -Z), pre-blue
	var walled: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(-4, 0, -6)],                     # weak-side flanker
			[4, 1, Vector3(2, 0, -5.5)],                    # head D, set at gap
			[5, 1, Vector3(8, 0, -6)],                      # strong-side flanker
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, walled))
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_DUMP,
			"an open backfield beats conceding the puck")
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY, "regroups with possession")
	assert_gt(c.last_carry_anchor.z, self_pos.z + 2.0,
			"the regroup carries back toward centre, creating space")

	# Contrast: a loose pair is NOT a wall — the compete attacks the seam
	# instead of ceding ice to two beatable bodies.
	var loose: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(2, 0, -5), false, Vector3(0, 0, -4)],  # D backing off us
			[4, 1, Vector3(-1, 0, -5.5)],                      # D wide of the lane
	]
	var c2 := AIRoleCarrier.new()
	c2.decide(_make_ctx(self_pos, loose))
	assert_eq(c2.intended_action, AIRoleCarrier.INTENT_CARRY,
			"two beatable bodies are not denial")
	assert_lt(c2.last_carry_anchor.z, self_pos.z - 2.0,
			"…and the carrier takes the ice they concede")


func test_best_dump_geometry_past_center_is_a_soft_flip_to_the_far_corner() -> void:
	# Direct pin on the dump-in's GEOMETRY (the compete around it is covered
	# by the pincer/regroup tests): past centre, the dump target is a soft
	# flip into the far offensive corner, away from the carrier's side.
	var self_pos := Vector3(2, 0, -4)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(2, 0, -5)],
	]
	var ctx: RoleContext = _make_ctx(self_pos, skaters)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var dump: Array = c._best_dump(ctx, AIRoleHelpers.resolve_our_goalie_pos(ctx))
	assert_true(dump[2], "a dump-in is a soft flip")
	# The dump-in is a searched release scored on the race to where the puck
	# STOPS, so which corner it picks is an outcome of who is closer to what,
	# not a formula. What must hold is that it puts the puck deep.
	var settle: Vector3 = dump[4]
	gut.p("  dump-in from %s settles at %s" % [self_pos, settle])
	assert_true(
			AIActionScoring.in_offensive_zone(settle, ctx.attacking_goal_pos),
			"the dump-in comes to rest in the offensive zone")


func test_dump_in_places_the_puck_by_pace_not_by_banking_off_a_wall() -> void:
	# The dump-in searches BEARING x PACE. Bearing alone cannot place a dump:
	# every pace the bot can produce out-slides the rink several times over, so
	# at a fixed hot pace the only deliveries that die in the offensive zone are
	# the ones banked steeply enough to shed 40-60% on contact — and a centre
	# chip simply squares off the end boards and comes BACK to the neutral zone.
	# With pace on the axis list the delivery lands deep and the launch is soft.
	var self_pos := Vector3(2, 0, -4)
	var ctx: RoleContext = _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(2, 0, -5)]])
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var dump: Array = c._best_dump(ctx, AIRoleHelpers.resolve_our_goalie_pos(ctx))
	var settle: Vector3 = dump[4]
	gut.p("  dump-in settles at %s, launched at %.1f m/s" % [settle, dump[5]])
	assert_true(
			AIActionScoring.in_offensive_zone(settle, ctx.attacking_goal_pos),
			"the dump-in comes to rest in the offensive zone")
	# The pace is a real choice off the ladder, inside the producible release
	# band — not the fixed quick-pass pace the release used to be stuck at.
	assert_between(dump[5], GameRules.DEFAULT_WRISTER_POWER_MIN_M_S,
			ctx.self_wrister_shot_speed,
			"the launch pace sits in the band the release can actually fire")
	# And the puck stops in play, short of the end boards it used to rattle off.
	assert_lt(absf(settle.z), GameRules.GOAL_LINE_Z,
			"a placed dump-in dies in the zone, not off the end wall")


func test_dump_in_will_not_feed_the_keeper() -> void:
	# The missing body in the dump's race. chase_recovery sees skaters only, so
	# a puck dying on the doorstep — the spot position_potential rates highest
	# on the whole rink — used to read as a FREE recovery, and the delivery
	# search aimed there. It is the keeper's puck; he is standing on it.
	var self_pos := Vector3(0, 0, -4)
	var ctx: RoleContext = _make_ctx(self_pos, [[1, TEAM_ID, self_pos]])
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var dump: Array = c._best_dump(ctx, AIRoleHelpers.resolve_our_goalie_pos(ctx))
	var settle: Vector3 = dump[4]
	var keeper: Vector3 = c._goalie_now(ctx)
	gut.p("  dump-in settles at %s, keeper at %s" % [settle, keeper])
	assert_false(
			AIActionScoring.keeper_collects_first(
					settle, keeper, [self_pos] as Array[Vector3],
					AIArrival.SKATER_REF_SPEED_M_S),
			"the chosen dump is not one the keeper simply collects")

	# The primitive itself, both ways: a puck resting in the blue paint with our
	# nearest man twenty metres out is his; the same puck in the corner is not,
	# because 4.2 m/s cannot beat a winger's 9 to it.
	var ours: Array[Vector3] = [Vector3(0, 0, -6)]
	assert_true(AIActionScoring.keeper_collects_first(
			Vector3(0, 0, -24.0), keeper, ours, AIArrival.SKATER_REF_SPEED_M_S),
			"a puck dying on the doorstep belongs to the keeper")
	assert_false(AIActionScoring.keeper_collects_first(
			Vector3(11.5, 0, -23.0), keeper, ours, AIArrival.SKATER_REF_SPEED_M_S),
			"…and a puck in the corner does not — he cannot get there first")


func test_an_easy_entry_is_carried_not_dumped() -> void:
	# The headline behavior. A carrier past centre with the ice in front of him
	# genuinely open — one defender well wide of the lane — must take the entry,
	# not fling it in. Three asymmetries used to hand this to the dump, all of
	# them comparing a dumped puck's WHOLE play against a carry's next second:
	# the settle spot's potential skipped the realization discount every carry
	# candidate pays, the chase clock ran at an instant full-speed sprint no
	# skater can produce, and the compete never saw the drive-in the carrier
	# could simply take.
	var self_pos := Vector3(0, 0, -2)
	for label: String in ["wide D", "wide D, in stride"]:
		var vel: Vector3 = Vector3(0, 0, -8) if label.ends_with("stride") \
				else Vector3.ZERO
		var ctx: RoleContext = _make_ctx(self_pos, [
				[1, TEAM_ID, self_pos],
				[3, 1, Vector3(-12, 0, -9)]])
		ctx.self_velocity = vel
		var c := AIRoleCarrier.new()
		c.decide(ctx)
		gut.p("  %s: intent=%d dump=%.4f carry=%.4f"
				% [label, c.intended_action, c.debug_dump_score, c.debug_carry_score])
		assert_ne(c.intended_action, AIRoleCarrier.INTENT_DUMP,
				"%s: an open entry is skated in, not dumped" % label)

	# The contrast that keeps this honest: the dump must still be REACHABLE.
	# Wall it off with a real stand-up line and the compete stops preferring the
	# carry — this is the flip, not a blanket ban on dumping.
	var walled: RoleContext = _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(-4, 0, -5)],
			[4, 1, Vector3(0, 0, -4.5)],
			[5, 1, Vector3(4, 0, -5)]])
	var cw := AIRoleCarrier.new()
	cw.decide(walled)
	gut.p("  walled: intent=%d dump=%.4f carry=%.4f"
			% [cw.intended_action, cw.debug_dump_score, cw.debug_carry_score])
	assert_lt(cw.debug_carry_score, 0.30,
			"a stand-up wall genuinely collapses the carry's value")


func test_an_unopposed_carrier_never_dumps() -> void:
	# The headline of the residual model. The dump used to be SCORED and entered
	# in the compete, and it beat an open carrier on an EMPTY RINK: its credit
	# reached the slot while the carry's is horizon-capped at RECEIVER_DRIVE_MAX_M,
	# so a soft chip whose landing solve put the puck 17 m up ice out-valued
	# skating the same ground. Nothing on the ice to lose the puck to, and the bot
	# threw it away.
	#
	# A dump is now what is LEFT when retention is worth nothing, so with the rink
	# empty there is nothing for it to be left over from — the search does not
	# even run.
	for z: float in [-1.0, -3.0, -5.0, -7.0]:
		for label: String in ["standing", "in stride"]:
			var self_pos := Vector3(0, 0, z)
			var vel: Vector3 = Vector3(0, 0, -8) if label == "in stride" \
					else Vector3.ZERO
			var ctx: RoleContext = _make_ctx(self_pos, [[1, TEAM_ID, self_pos]])
			ctx.self_velocity = vel
			var c := AIRoleCarrier.new()
			c.decide(ctx)
			assert_ne(c.intended_action, AIRoleCarrier.INTENT_DUMP,
					"z=%.0f %s: an unopposed carrier skates it in" % [z, label])
			assert_eq(c.debug_dump_score, -INF,
					"z=%.0f %s: the delivery search never ran" % [z, label])


# Past centre, IN STRIDE at a three-man stand-up line that walls the entry off,
# optionally with an outlet up the wall. In stride is the geometry a zone entry
# is decided in: from a standstill the retreat ring is cheap and the carrier
# regroups instead.
func _walled_ctx(with_outlet: bool) -> RoleContext:
	var self_pos := Vector3(0, 0, -2)
	var skaters: Array = [[1, TEAM_ID, self_pos]]
	if with_outlet:
		skaters.append([2, TEAM_ID, Vector3(9, 0, -3)])
	skaters.append_array([
			[3, 1, Vector3(-4, 0, -5)],
			[4, 1, Vector3(0, 0, -4.5)],
			[5, 1, Vector3(4, 0, -5)]])
	var ctx: RoleContext = _make_ctx(self_pos, skaters)
	ctx.self_velocity = Vector3(0, 0, -8)
	return ctx


func test_a_qualified_release_outranks_the_dump_rather_than_out_scoring_it() -> void:
	# The ordering, not a comparison: a release that cleared its own giveaway bar
	# is a live play and a dump is what is left when there is none, so with the
	# outlet on the delivery search never runs. The outlet does not have to
	# out-VALUE the concession. (What the lone carrier does at this wall is
	# calibration: the snapshot's walled-off rows.)
	var s: AIRoleCarrier = _decided(_walled_ctx(true))
	assert_gt(s.debug_pass_score, AIRoleCarrier.PASS_MIN_VALUE,
			"precondition: the outlet clears the pass bar")
	assert_eq(s.debug_dump_score, -INF,
			"the delivery search never ran — the release outranked it")


func test_carrier_with_a_clean_outlet_does_not_dump() -> void:
	# Pinned in the DZ by a head-on forecheck, which prices as the strip it is
	# even for a protecting carrier, with a teammate wide open up the strong wall:
	# a real breakout out-scores conceding — pass, don't dump.
	var self_pos := Vector3(8, 0, 20)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(11, 0, 11)],                  # open outlet up the wall
			[3, 1, Vector3(8, 0, 17), false, Vector3(0, 0, 4)],
			[4, 1, Vector3(5.5, 0, 19)],
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_DUMP,
			"a clean breakout outlet beats a dump")
	# With retention hopeless, a qualified pass fires without having to beat the
	# carry that already lost, so the pinned carrier moves the puck to the live
	# outlet instead of flinging it to space past him.
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"the pinned carrier hits the outlet rather than concede")
	assert_eq(c.pass_target_peer_id, 2, "the outlet up the wall is the target")


func test_no_dump_in_own_side_neutral_zone() -> void:
	# Between our own blue line and centre — not our DZ, not past the red line. No
	# dump applies here even under pressure (it would be icing to fire it in, and
	# there's no need to clear from mid-ice).
	var self_pos := Vector3(0, 0, 4)                       # own-side NZ (own net +Z)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(0, 0, 1), false, Vector3(0, 0, 4)],
			[4, 1, Vector3(3, 0, 2)],
			[5, 1, Vector3(-3, 0, 2)],
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_DUMP,
			"no dump from the own-side neutral zone")


# ─── NHL icing and delayed offside ────────────────────────────────────────────

func test_delayed_offside_closes_the_zone_to_the_carry() -> void:
	var self_pos := Vector3(0, 0, -5)  # neutral ice, attacking -Z
	var ctx := _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var goalie: Vector3 = AIRoleHelpers.resolve_our_goalie_pos(ctx)
	var in_zone := Vector3(0, 0, -9)
	assert_gt(c._score_move_candidate_base(ctx, in_zone, goalie), -INF,
			"an open entry is a candidate")
	ctx.zone_entry_blocked = true
	assert_eq(c._score_move_candidate_base(ctx, in_zone, goalie), -INF,
			"with a teammate owing a tag-up, carrying in would be whistled")


func test_delayed_offside_takes_the_dump_in_off_the_table() -> void:
	var self_pos := Vector3(2, 0, -4)
	var ctx: RoleContext = _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(2, 0, -5)]])
	ctx.zone_entry_blocked = true
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var dump: Array = c._best_dump(ctx, AIRoleHelpers.resolve_our_goalie_pos(ctx))
	assert_eq(dump[0], -INF, "a dumped puck nobody may touch is no dump-in")


func test_no_dump_once_in_the_offensive_zone() -> void:
	# Already established in the OZ — the valve keeps the puck in, and there's no
	# dump. Even swarmed, it cycles/holds rather than dumping it away.
	var self_pos := Vector3(0, 0, -12)                     # in the OZ (attack -Z)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(0, 0, -14), false, Vector3(0, 0, -4)],
			[4, 1, Vector3(3, 0, -13)],
			[5, 1, Vector3(-3, 0, -13)],
	]
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos, skaters))
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_DUMP,
			"no dumping once the zone is established")


# ─── _facing_rotation_time: the blade reach cone (Aim-B / B1) ────────────────
# The carrier prices a shot/pass by the body ROTATION it costs. The blade
# reaches anywhere inside the ±reach-cone (ROM + torso twist, ~157°) from the
# current facing, so an in-cone aim fires with NO turn; only the narrow back
# wedge past the cone pays, at the bot's Agility-scaled turn rate. These pin the
# grounded geometry directly (the recursive pass-EV path can't isolate it).

const _CONE_157: float = deg_to_rad(157.0)


func _rot_time(facing_deg: float, target_deg: float, cone: float,
		rate: float) -> float:
	# facing/target given as degrees off +Z (CCW in XZ). Self at origin.
	var c := AIRoleCarrier.new()
	var f := deg_to_rad(facing_deg)
	var t := deg_to_rad(target_deg)
	var facing_xz := Vector2(sin(f), cos(f))
	var target := Vector3(sin(t) * 10.0, 0.0, cos(t) * 10.0)
	return c._facing_rotation_time(facing_xz, Vector3.ZERO, target, cone, rate)


func test_in_cone_aim_costs_no_rotation() -> void:
	# A 120° off-facing target is well inside the ±157° reach cone, so the blade
	# fires from the current facing — zero body-turn cost. Under the OLD ±90° cone
	# this same aim would have paid; widening the cone is the core of B1.
	assert_almost_eq(_rot_time(0.0, 120.0, _CONE_157, 6.0), 0.0, 0.0001,
			"an in-cone (≤157°) aim requires no body rotation")
	assert_almost_eq(_rot_time(0.0, 155.0, _CONE_157, 6.0), 0.0, 0.0001,
			"just inside the cone is still free")


func test_back_wedge_aim_pays_only_the_overshoot() -> void:
	# Directly behind (180°) is 23° past the 157° cone, rotated at 6 rad/s.
	var expected: float = deg_to_rad(180.0 - 157.0) / 6.0
	assert_almost_eq(_rot_time(0.0, 180.0, _CONE_157, 6.0), expected, 0.0001,
			"only the overshoot past the cone costs time")


func test_nimbler_bot_prices_a_back_wedge_turn_cheaper() -> void:
	# Same back-wedge geometry, a faster (higher-Agility) turn rate → less time.
	var slow: float = _rot_time(0.0, 180.0, _CONE_157, 6.0)
	var fast: float = _rot_time(0.0, 180.0, _CONE_157, 12.0)
	assert_lt(fast, slow,
			"a higher facing turn rate resolves the back-wedge turn sooner")
	assert_almost_eq(fast, slow * 0.5, 0.0001,
			"double the turn rate halves the rotation cost")


func test_wider_cone_frees_a_lateral_aim() -> void:
	# The same 120° aim: free under the true ±157° cone, penalized under the old
	# ±90°. This is exactly the behavioural shift B1 introduces.
	var wide: float = _rot_time(0.0, 120.0, _CONE_157, 6.0)
	var narrow: float = _rot_time(0.0, 120.0, deg_to_rad(90.0), 6.0)
	assert_eq(wide, 0.0, "wide cone frees the lateral aim")
	assert_gt(narrow, 0.0, "the old narrow cone would have penalized it")


# ─── Shot measured from the puck, not the body ──────────────────────────────

func test_shot_is_measured_from_the_puck_not_the_body() -> void:
	# The carried puck rides the blade, up to a stick's reach from the body — the
	# shot's view of the net is from the PUCK. Same body position, puck extended
	# toward the net → the release ref moves with it → wider real angles → higher
	# shoot score. (The fixture default puts the puck AT the body, so every other
	# scenario in this file is unchanged.)
	var self_pos := Vector3(0, 0, -17.65)   # 9 m out
	var ctx_body: RoleContext = _make_ctx(self_pos)
	var c1 := AIRoleCarrier.new()
	c1.decide(ctx_body)
	var body_score: float = c1.debug_shoot_score

	var ctx_blade: RoleContext = _make_ctx(self_pos)
	ctx_blade.snapshot.puck_state.position = self_pos + Vector3(0, 0, -1.1)
	var c2 := AIRoleCarrier.new()
	c2.decide(ctx_blade)
	assert_gt(c2.debug_shoot_score, body_score,
			"a puck extended toward the net measures a wider view than the chest")


# ─── Blue line: free entry over tiki-taka ────────────────────────────────────

func test_blue_line_entry_carries_past_a_symmetric_set_defense() -> void:
	# Carrier and a mate level at the blue line, defenders set INSIDE the zone at
	# a normal contain gap — symmetric coverage. The receiver used to escape the
	# forward-pressure discount the carrier paid, so each winger rated the other
	# man's future above his own present and the puck ping-ponged along the line.
	# With the symmetric discount, the man with the puck takes the entry.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(-4, 0, -(GameRules.BLUE_LINE_Z - 1.0))
	var skaters: Array = [
			[1, TEAM_ID, self_pos, false, Vector3(0, 0, -6)],
			[2, TEAM_ID, Vector3(4, 0, self_pos.z), false, Vector3(0, 0, -6)],
			[11, 1, Vector3(-3.5, 0, -12.0)],
			[12, 1, Vector3(3.5, 0, -12.0)],
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.self_velocity = Vector3(0, 0, -6)
	var g := GoalieNetworkState.new()
	g.position_x = 0.0
	g.position_z = net.z + 1.3
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"symmetric coverage at the line → the puck-carrier takes the entry")


# ─── Post-seal stances: the carrier reads the VH wall ────────────────────────

func test_post_seal_x_sign_decodes_the_wire_convention() -> void:
	# Convention lock: the controller enters *_LEFT when puck_local_x =
	# (puck.x − goal.x) · −sign(−goal_z) < 0 — i.e. the sealed post sits at
	# world-x sign(−goal_z). Both nets, both stance families.
	var g := GoalieNetworkState.new()
	g.state_enum = GoalieStateMachine.State.VH_LEFT as int
	assert_eq(g.post_seal_x_sign(-26.65), 1.0, "net at −z: LEFT seals the +x post")
	assert_eq(g.post_seal_x_sign(26.65), -1.0, "net at +z: LEFT seals the −x post")
	assert_true(g.is_post_seal_tall(), "VH is the tall seal")
	g.state_enum = GoalieStateMachine.State.RVH_RIGHT as int
	assert_eq(g.post_seal_x_sign(-26.65), -1.0, "net at −z: RIGHT seals the −x post")
	assert_false(g.is_post_seal_tall(), "RVH is the compressed seal")
	g.state_enum = GoalieStateMachine.State.READY as int
	assert_eq(g.post_seal_x_sign(-26.65), 0.0, "no post stance, no seal")


func test_sharp_angle_shot_into_a_vh_seal_is_never_worth_firing() -> void:
	# The observed over-fire: from a sharp angle the arc-square model read a
	# near-goal-line keeper as roughly centred (his deep arc-x sits near 0),
	# conceding a phantom short side — while the real goalie is parked at the
	# post in VH with the whole near column walled off. With the seal read
	# from the replicated state, the shot from the seal side collapses below
	# the fire floor: whatever the carrier does here, it is never "fire into
	# the VH wall."
	var self_pos := Vector3(4.5, 0, -26.0)   # sharp angle, seal side, in tight
	var ctx_vh := _make_ctx(self_pos)
	var g_vh := GoalieNetworkState.new()
	g_vh.position_x = 0.85                    # parked at the +x post
	g_vh.position_z = -26.55                  # post-seal depth ~0.10
	g_vh.state_enum = GoalieStateMachine.State.VH_LEFT as int   # seals +x here
	ctx_vh.snapshot.goalie_states[1 - TEAM_ID] = g_vh
	var vh := AIRoleCarrier.new()
	vh.decide(ctx_vh)
	# Not exactly zero: the model honestly keeps the thin cross-net window at
	# the FAR post (see the aim test in test_ai_action_scoring) — but the
	# near column is walled off, so nothing here rates as a real chance.
	assert_lt(vh.debug_shoot_score, 0.10,
			"the sealed sharp angle offers no real chance; got %f" % vh.debug_shoot_score)

	# Same carrier, same replicated goalie placement, but STANDING: under the
	# body-occlusion shot model the goalie's DEPTH walls the cross-net lane from
	# a spot this sharp with or without the seal — the obscenely-tight-angle fire
	# is never a real chance, which is exactly the read the seal used to be
	# needed for. (The seal still matters where the angle leaves real lanes —
	# see the VH/RVH hole tests in test_ai_action_scoring.)
	var ctx_up := _make_ctx(self_pos)
	var g_up := GoalieNetworkState.new()
	g_up.position_x = 0.85
	g_up.position_z = -26.55
	g_up.state_enum = GoalieStateMachine.State.STANDING as int
	ctx_up.snapshot.goalie_states[1 - TEAM_ID] = g_up
	var up := AIRoleCarrier.new()
	up.decide(ctx_up)
	assert_lt(up.debug_shoot_score, 0.10,
			"upright from the same sharp spot is no chance either — body depth walls it")


# ─── attacking blue-line keep-out bands ──────────────────────────────────────
# The offside puck-line is the TRUE blue line while the carrier reasons in
# body positions: the pass windup swings the carried puck a stick's reach
# behind the body, and reception plays the puck a reach around the receiver.
# Both bands (OZ_RETREAT_LINE_BUFFER_M / OZ_RECEIVE_LINE_BUFFER_M) exist so
# blue-line slop can't turn a completed play into a zone exit / offside.

func test_oz_valve_prunes_carry_candidates_in_the_blue_line_band() -> void:
	# Carrier established in the OZ (team 0 attacks -Z; OZ is z < -7.29).
	# A retreat candidate INSIDE the keep-out band (on the zone side of the
	# line but within windup reach of it) is pruned outright; a candidate
	# past the band scores normally.
	var self_pos := Vector3(0.0, 0.0, -12.0)
	var ctx := _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var in_band := Vector3(0.0, 0.0,
			-(GameRules.BLUE_LINE_Z + AIRoleCarrier.OZ_RETREAT_LINE_BUFFER_M * 0.5))
	var past_band := Vector3(0.0, 0.0,
			-(GameRules.BLUE_LINE_Z + AIRoleCarrier.OZ_RETREAT_LINE_BUFFER_M + 1.0))
	assert_eq(c._score_move_candidate(ctx, in_band, ctx.defending_goal_pos), -INF,
			"a retreat to within windup reach of the blue line is pruned")
	assert_gt(c._score_move_candidate(ctx, past_band, ctx.defending_goal_pos), -INF,
			"a retreat that keeps the windup envelope inside the zone stays legal")


func test_nz_carrier_may_target_entry_candidates_near_the_line() -> void:
	# The valve (and its band) only binds a carrier ALREADY in the zone —
	# an entry candidate just across the line must stay legal or the
	# carrier could never enter at all.
	var self_pos := Vector3(0.0, 0.0, -5.0)   # neutral zone
	var ctx := _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var just_inside := Vector3(0.0, 0.0, -(GameRules.BLUE_LINE_Z + 0.7))
	assert_gt(c._score_move_candidate(ctx, just_inside, ctx.defending_goal_pos), -INF,
			"an entry candidate in the band is not pruned from outside the zone")


func test_oz_pass_skips_receiver_hugging_the_blue_line() -> void:
	# Carrier in the OZ; the only teammate is wide open but his tape sits
	# just inside the blue line — reception slop there takes the puck out
	# of the zone, so he is excluded as a target entirely. The same open
	# man past the keep-out band is a legal (positive) feed.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(6.0, 0.0, -20.0)
	var at_line := Vector3(-2.5, 0.0, -(GameRules.BLUE_LINE_Z + 0.5))
	var skaters_line: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, at_line],
	]
	var ctx_line := _make_ctx(self_pos, skaters_line)
	ctx_line.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 1.3)
	var c_line := AIRoleCarrier.new()
	c_line._build_action_opponents_lists(ctx_line)
	var res_line: Array = c_line._compute_best_pass(ctx_line, Vector2(0.0, -1.0), [2])
	assert_eq(res_line[1], 0.0,
			"a receiver hugging the blue line is not a pass target from inside the zone")

	# Same carrier, receiver now a genuinely valuable target well past the
	# band (the far-post backdoor the squared goalie can't re-square onto —
	# the same feed test_passes_to_the_open_backdoor_man… proves positive).
	var deep := Vector3(-2.5, 0.0, -23.5)
	var skaters_deep: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, deep],
	]
	var ctx_deep := _make_ctx(self_pos, skaters_deep)
	ctx_deep.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 1.3)
	var c_deep := AIRoleCarrier.new()
	c_deep._build_action_opponents_lists(ctx_deep)
	var res_deep: Array = c_deep._compute_best_pass(ctx_deep, Vector2(0.0, -1.0), [2])
	assert_gt(res_deep[1], 0.0,
			"the same open man past the keep-out band is a legal feed")


# ─── close-quarters saucer variant ───────────────────────────────────────────

func test_close_quarters_pass_saucers_over_a_mid_lane_stick() -> void:
	# An 8 m feed whose flat lane is contested by a stick-range mid-lane
	# defender (off the line by more than a body radius). The old fixed
	# 10 m saucer floor kept this grounded; under the kinematic model a
	# SOFT flip (launch capped by the receivability bound) clears the
	# stick and lands with runway — the saucer variant should win the
	# per-receiver EV compete.
	var self_pos := Vector3(0.0, 0.0, 10.0)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(0.0, 0.0, 2.0)],    # receiver 8 m up-ice
			[3, 1, Vector3(0.7, 0.0, 6.5)],          # mid-lane stick, body off the line
	]
	var ctx := _make_ctx(self_pos, skaters)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var res: Array = c._compute_best_pass(ctx, Vector2(0.0, -1.0), [2])
	assert_gt(res[1], 0.0, "the lofted feed rates as a real pass")
	assert_true(res[2], "close-quarters contested lane picks the saucer variant")


func test_short_feed_below_saucer_floor_stays_grounded() -> void:
	# Same shape at 5.5 m: even the softest legal flip (min wrister pace)
	# can't land with runway that short, so no saucer variant exists and
	# the pass stays flat whatever the lane looks like.
	var self_pos := Vector3(0.0, 0.0, 10.0)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(0.0, 0.0, 4.5)],    # receiver 5.5 m up-ice
			[3, 1, Vector3(0.7, 0.0, 7.5)],          # mid-lane stick
	]
	var ctx := _make_ctx(self_pos, skaters)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var res: Array = c._compute_best_pass(ctx, Vector2(0.0, -1.0), [2])
	assert_false(res[2], "below the physical saucer floor the feed stays grounded")


func test_committed_saucer_pass_caps_launch_at_the_receivability_bound() -> void:
	# Full decide(): a neutral-zone carrier with a 9 m ahead-man behind a
	# mid-lane stick commits the saucer PASS, and the committed launch
	# speed is capped at the receivability bound for the distance — the
	# genuinely soft flip — never the crisp magnet pace that would arrive
	# still airborne and sail over the receiver's blade. A PASS_TO_ME ping
	# biases the compete toward the feed so the test pins the COMMIT path
	# deterministically (the variant selection itself is covered by the
	# _compute_best_pass tests above); the ping is a bias inside the same
	# scoring, so the committed pass is still the winning saucer variant.
	var self_pos := Vector3(3.0, 0.0, 5.0)
	var receiver := Vector3(3.0, 0.0, -4.0)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, receiver],
			[3, 1, Vector3(3.7, 0.0, 0.5)],          # mid-lane stick on the feed
			[4, 1, Vector3(1.5, 0.0, 7.0)],          # forecheckers pressuring the carry
			[5, 1, Vector3(4.5, 0.0, 6.5)],
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.ping_pass_target_peer = 2
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS,
			"pressured carrier feeds the outlet")
	assert_true(c.pass_should_saucer, "the contested lane picks the saucer")
	var bound: float = AIPuckLane.saucer_max_launch_speed(
			self_pos.distance_to(receiver))
	assert_lt(c.pass_target_speed, bound + 0.01,
			"committed saucer launch is capped so the flip lands before the tape")
	assert_gt(c.pass_target_speed,
			GameRules.DEFAULT_WRISTER_POWER_MIN_M_S - 0.01,
			"committed saucer launch stays at/above the soft-touch floor")


# ─── puck-protect mirror (blade shielding read by the state machine) ─────────

func test_no_shot_is_even_scored_from_outside_the_zone() -> void:
	# The shot eval is skipped entirely outside the attacking zone while the
	# keeper is HOME — the same proof threat_surface_shoot and _score_at already
	# run, applied to the eval that costs the most (goalie hole geometry + the
	# three-sample release sweep + the tip read, on every NZ/DZ dispatch, to
	# compute ~0).
	#
	# It is a behavioural guarantee, not only a saving. SHOT_MIN_VALUE already
	# made an own-zone shot unreachable in practice, but only by arithmetic
	# downstream of two multipliers — the fire hysteresis and the smart-ping
	# SHOOT bias — which both scale a live score up BEFORE the bar is checked.
	# With no score computed there is nothing for either to lift.
	var self_pos := Vector3(0.0, 0.0, 20.0)          # deep in our OWN zone
	var ctx := _make_ctx(self_pos, [[1, TEAM_ID, self_pos]])
	var home := GoalieNetworkState.new()
	home.position_x = 0.0
	home.position_z = OPP_NET_Z + 1.0                # keeper home in his crease
	ctx.snapshot.goalie_states[1 - TEAM_ID] = home
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_lt(c.debug_shoot_score, 0.0,
			"no shot is scored at all from our own zone against a home keeper")
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_SHOOT,
			"…so SHOOT cannot win the compete by any route")

	# Even ordered to shoot by a teammate's smart ping, which biases the shot
	# score: the bias multiplies a score that was never computed.
	var pinged := _make_ctx(self_pos, [[1, TEAM_ID, self_pos]])
	pinged.snapshot.goalie_states[1 - TEAM_ID] = home
	pinged.ping_shoot_active = true
	var cp := AIRoleCarrier.new()
	cp.decide(pinged)
	assert_ne(cp.intended_action, AIRoleCarrier.INTENT_SHOOT,
			"a shoot ping cannot manufacture an own-zone shot")

	# The keeper-home condition is load-bearing, and is why this is not a blanket
	# zone gate: a PULLED keeper voids the proof and an empty net genuinely
	# scores from distance, so the shot must still be evaluated out here.
	var empty := _make_ctx(self_pos, [[1, TEAM_ID, self_pos]])
	var pulled := GoalieNetworkState.new()
	pulled.position_x = 0.0
	pulled.position_z = 0.0                          # off for an extra attacker
	empty.snapshot.goalie_states[1 - TEAM_ID] = pulled
	var ce := AIRoleCarrier.new()
	ce.decide(empty)
	assert_gt(ce.debug_shoot_score, 0.0,
			"an empty net is still scored from outside the zone; got %f"
			% ce.debug_shoot_score)


func test_open_ice_carrier_feels_no_protect_gain() -> void:
	# Nobody near the presented forward carry spot: shielding buys nothing, so the
	# gain is 0 and the state machine keeps the plain forward carry aim.
	var ctx := _make_ctx(Vector3(0, 0, 5))
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.protect_gain, 0.0, "open ice: the forward carry is already safe")
	assert_true(c.evade_seam_world.is_finite(),
			"the evasion seam is published for the deke cut")


const _PROTECT_SPOT := Vector3(0, 0, 5)


# The carrier standing at _PROTECT_SPOT with a defender `ahead_m` in front of him
# on the play line (attack is -Z), or alone when `ahead_m` is INF.
func _frontal_threat(ahead_m: float) -> AIRoleCarrier:
	var skaters: Array = [[1, TEAM_ID, _PROTECT_SPOT]]
	if is_finite(ahead_m):
		skaters.append([3, 1, _PROTECT_SPOT + Vector3(0, 0, -ahead_m)])
	return _decided(_make_ctx(_PROTECT_SPOT, skaters))


func test_frontal_stick_threat_pulls_the_puck_behind_the_body() -> void:
	# A defender 1.6 m ahead has his stick on the presented forward puck while the
	# back hip is out of his reach: the shield buys real safety, and the
	# least-committal safe point is behind the body (+Z, body as the shield).
	var c: AIRoleCarrier = _frontal_threat(1.6)
	assert_gt(c.protect_gain, 0.0,
			"a stick on the presented spot, with a safe hip to hide it, earns the shield")
	assert_gt(c.protect_offset.z, 0.0, "the puck pulls behind the body")


func test_the_shield_never_moves_the_puck_toward_the_checker() -> void:
	# Wherever a checker stands on the play line, the protected spot is no nearer
	# him than the presented one (the offset with nobody there): the shield moves
	# the puck away from the threat or leaves it, never into it. The sweep is over
	# the aim, not the gain, because the gain is not monotone in his distance —
	# with him on the body no seam is out of his reach, so a shield buys nothing.
	var presented: Vector3 = _frontal_threat(INF).protect_offset
	for ahead_m: float in [1.0, 1.4, 1.8, 2.2, 2.6, 3.0, 3.5, 4.0]:
		var checker := Vector3(0, 0, -ahead_m)
		var shielded: Vector3 = _frontal_threat(ahead_m).protect_offset
		assert_gte(shielded.distance_to(checker), presented.distance_to(checker) - 1e-4,
				"checker %.1f m ahead: protected %s is no nearer him than presented %s"
				% [ahead_m, shielded, presented])


func test_protect_read_is_gated_by_the_cognition_tier() -> void:
	# Same frontal threat, protects_the_puck false (the Easy tier): the mirror
	# stays zeroed — the naive forward carry, poke-checks work by design.
	var self_pos := Vector3(0, 0, 5)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, self_pos + Vector3(0, 0, -2.2)],
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.protects_the_puck = false
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.protect_gain, 0.0, "the beginner tier never shields")
	assert_eq(c.protect_offset, Vector3.ZERO, "no protect offset on the beginner tier")


func test_beaten_defender_behind_does_not_hold_the_shield() -> void:
	# The reported bug: a carrier keeps protecting the puck (body turned side-on)
	# AFTER it has beaten the man pressuring it. A defender trailing directly
	# behind is within stick-reach of the presented forward puck, so the
	# undirected reach read scored it as full pressure and the shield stayed on —
	# even though the carrier's own body already screens the forward puck from a
	# man behind it. The directional filter drops a beaten/behind defender, so the
	# shield disengages and the carrier is free to square to the net.
	var self_pos := Vector3(0, 0, -15)   # in the offensive zone, driving at -Z net
	var behind: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(0, 0, -14.0)],   # 1 m behind (toward our end) — beaten
	]
	var cb := AIRoleCarrier.new()
	cb.decide(_make_ctx(self_pos, behind))
	assert_eq(cb.protect_gain, 0.0,
			"a beaten defender behind the carrier is screened for free — no shield")

	# Sanity: a stick in FRONT (goal-side) covering the presented puck is a genuine
	# threat and still shields hard, so the filter cuts by direction, not by
	# turning shielding off. 2.2 m ahead — the forward puck is inside his reach,
	# with a safe hip to hide it to.
	var front: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(0, 0, -17.2)],   # 2.2 m ahead, reach over the presented puck
	]
	var cf := AIRoleCarrier.new()
	cf.decide(_make_ctx(self_pos, front))
	assert_gt(cf.protect_gain, 0.5,
			"a stick on the forward puck still earns a strong shield; got %f"
			% cf.protect_gain)


func test_the_shield_goes_only_as_far_off_the_play_line_as_it_must() -> void:
	# The seam is DIRECTED at the presented-forward spot, not a max-clearance
	# read. Asked for pure max clearance it returns the point diametrically
	# opposite the checker — and a checker only makes shielding necessary by
	# being in FRONT, so that point is behind the carrier. Measured on the old
	# read: against any defender the carrier was skating toward, the seam came
	# back 120-180 deg off the carry line at full gain, and the blade sat on the
	# back hip for as long as the man was live. That is the "beats his man, then
	# keeps carrying it behind him" look, and a puck on the back hip is not on a
	# shot or a pass.
	#
	# What has to hold is that the shield GRADES: as the same defender moves off
	# the carry line, the seam walks back toward it rather than staying pinned
	# behind. Carrier driving at the -Z net at 7 m/s, containing defender ahead,
	# swept laterally.
	var self_pos := Vector3(0, 0, -2)
	var vel := Vector3(0, 0, -7)
	var angles: Array[float] = []
	for dx: float in [0.0, 1.0, 2.0]:
		var ctx: RoleContext = _make_ctx(self_pos, [
				[1, TEAM_ID, self_pos, false, vel],
				[3, 1, Vector3(dx, 0, -5.0), false, Vector3(0, 0, -3)]])
		ctx.self_velocity = vel
		var c := AIRoleCarrier.new()
		c.decide(ctx)
		# Signed angle of the seam off the carry line; 0 = on the play line,
		# +/-180 = straight behind the body.
		var off: Vector3 = c.protect_offset
		var deg: float = absf(rad_to_deg(
				Vector2(0, -1).angle_to(Vector2(off.x, off.z))))
		angles.append(deg)
		gut.p("  D %.1f m off the line: gain %.3f, seam %.0f deg off the carry"
				% [dx, c.protect_gain, deg])
	assert_gt(angles[0], 150.0,
			"a checker dead on the carry line leaves only the back hip")
	assert_lt(angles[1], angles[0],
			"…step him off the line and the puck comes back toward it")
	assert_lt(angles[2], 60.0,
			"…and a checker well off the line barely moves the puck at all")


# In the zone with a defender abreast, a stick-reach off the strong-side hip.
func _abreast_shield() -> AIRoleCarrier:
	var self_pos := Vector3(0, 0, -15)
	return _decided(_make_ctx(self_pos, [
			[1, TEAM_ID, self_pos], [3, 1, Vector3(2.2, 0, -15.0)]]))


func test_beaten_side_defender_still_shields() -> void:
	# The filter must not fire too early: a defender even/beside the carrier (not
	# yet skated past) is still a live stick and must keep earning the shield —
	# only a man clearly behind is screened for free. Abreast, the forward puck is
	# covered and the far hip is safer, so shielding buys real safety.
	var c: AIRoleCarrier = _abreast_shield()
	assert_gt(c.protect_gain, 0.0,
			"a defender abreast is not beaten — the shield still engages")


# ─── OZ possession retention: cycle out instead of crashing the net ──────────

func test_covered_oz_carrier_cycles_out_instead_of_crashing() -> void:
	# Sharp-angle corner carrier, goalie set and sealing the angle, a defender
	# boxing out between him and the net: every shot in reach reads ~0. The
	# carrier pulls up and out of the sealed corner with the puck instead of
	# grinding a worthless drive into the crease, and never fires a giveaway.
	var net := Vector3(0.0, 0.0, OPP_NET_Z)
	var self_pos := Vector3(9.0, 0.0, -24.0)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(7.5, 0.0, -24.8)],   # boxing out the net-side path
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 1.3)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"nothing worth firing — keep possession")
	assert_gt(c.last_carry_anchor.z, self_pos.z + 1.0,
			"the carry pulls up out of the sealed corner (cycle), not into the crease")


# ─── behind-the-net: post walkouts ────────────────────────────────────────────

func test_oz_carrier_behind_the_net_walks_out_around_a_post() -> void:
	# Retrieval spot behind the attacking cage: every ordinary candidate's
	# straight route crosses the frame (net-path prune), the possession floor
	# is withheld behind the line, so the post WALKOUT is the play — carry it
	# out front around a post instead of grinding on the mesh.
	var self_pos := Vector3(0.4, 0.0, OPP_NET_Z - 1.9)   # behind the -Z cage
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos))
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"nothing to fire from behind the cage — carry it out")
	assert_gt(absf(c.last_carry_anchor.x), GameRules.NET_HALF_WIDTH,
			"the anchor rounds a post")
	assert_gt(c.last_carry_anchor.z, OPP_NET_Z,
			"…onto the rink side of the goal line")


func test_dz_carrier_behind_own_net_walks_out_around_a_post() -> void:
	# The DZ behind-the-net carry (the regroup they like taking): the way back
	# into the play is the same post walkout — wall exits and the slot anchor
	# all chord through the own cage and prune.
	var self_pos := Vector3(0.4, 0.0, OUR_NET_Z + 1.9)   # behind our +Z cage
	var c := AIRoleCarrier.new()
	c.decide(_make_ctx(self_pos))
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"a clean regroup keeps the puck")
	assert_gt(absf(c.last_carry_anchor.x), GameRules.NET_HALF_WIDTH,
			"the anchor rounds a post")
	assert_lt(c.last_carry_anchor.z, OUR_NET_Z,
			"…out in front of our own goal line")


# ─── space creation: retreat ring + pass optionality ─────────────────────────

func test_pass_option_prefers_the_spot_that_reopens_the_lane() -> void:
	# Pure option read: same cached receiver, two candidate spots — one whose
	# lane to him is walled by a defender, one with a clear lane. The clear
	# spot inherits (a discounted cut of) the receiver's value.
	var ctx := _make_ctx(Vector3.ZERO)
	var c := AIRoleCarrier.new()
	c._scratch_option_receiver_pos.append(Vector3(-8.0, 0.0, 0.0))
	c._scratch_option_receiver_val.append(0.12)
	c._scratch_opponents.append(Vector3(-4.0, 0.0, 0.0))    # parked on the direct lane
	c._scratch_opponent_vels.append(Vector3.ZERO)
	c._scratch_opponent_caps.append(null)
	var blocked: float = c._candidate_pass_option(ctx, Vector3.ZERO)
	var open: float = c._candidate_pass_option(ctx, Vector3(0.0, 0.0, 8.0))
	assert_gt(open, blocked + 0.02,
			"the spot with the reopened lane inherits real receiver value")
	assert_lt(open, 0.12, "the option is a discounted cut, never par with a live pass")


const _PINCH_SPOT := Vector3(0.0, 0.0, -18.0)     # OZ, attacking -Z
const _TIGHT_WALL_HALF_GAP: float = 0.5           # 1.0 m apart: no seam for a body or a puck
const _SPLITTABLE_HALF_GAP: float = 1.8           # 3.6 m up the middle


# A carrier at _PINCH_SPOT with a teammate open wide and two defenders 1.6 m
# ahead, `half_gap` either side of the middle; keeper squared at 1.3 m.
func _pinch(half_gap: float) -> AIRoleCarrier:
	var ctx := _make_ctx(_PINCH_SPOT, [
			[1, TEAM_ID, _PINCH_SPOT],
			[2, TEAM_ID, Vector3(-7.0, 0.0, -17.0)],
			[3, 1, Vector3(-half_gap, 0.0, -19.6)],
			[4, 1, Vector3(half_gap, 0.0, -19.6)]])
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			_PINCH_SPOT, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	return _decided(ctx)


func test_pinched_carrier_peels_out_to_reopen_the_ice() -> void:
	# A GENUINE wall dead ahead: the opposed pair splits the protect budget to
	# nothing, so the grind into the pinch prices as the strip it is and the carry
	# argmax peels OUT of it. (What resolves the pinch — the feed to the open man —
	# is calibration: the snapshot's pinch rows.)
	assert_gt(_pinch(_TIGHT_WALL_HALF_GAP).debug_carry_pos.z, _PINCH_SPOT.z + 2.0,
			"the carry argmax peels OUT of the pinch, never the grind into it")


func test_carrier_splits_a_beatable_gap_to_the_slot() -> void:
	# The same pair leaving a real gap up the middle: the slot-ward drive
	# out-scores backing out, so the carrier attacks the seam toward the net.
	assert_lt(_pinch(_SPLITTABLE_HALF_GAP).last_carry_anchor.z, _PINCH_SPOT.z - 1.0,
			"drives the seam toward the net rather than backing out of it")


func test_a_wider_gap_never_pulls_the_carry_plan_away_from_the_net() -> void:
	# Between the pinch and the split, opening the gap only ever gives the carrier
	# more room to attack: his planned anchor never moves away from the net.
	var prev_z: float = INF
	for half_gap: float in [_TIGHT_WALL_HALF_GAP, 0.7, 0.9, 1.1, 1.3, 1.5, _SPLITTABLE_HALF_GAP]:
		var z: float = _pinch(half_gap).last_carry_anchor.z
		assert_lte(z, prev_z + 1e-4,
				"gap %.1f m: the anchor backs off the net (z %.2f after %.2f)"
				% [2.0 * half_gap, z, prev_z])
		prev_z = z


func test_carrier_does_not_park_at_the_dead_angle_goal_line() -> void:
	# Entering down the wing in stride with a defender on the inside lane, the
	# carrier works toward the middle at a real angle instead of drifting down the
	# boards to the dead-angle goal-line corner, where no shot exists. The second
	# leg of a corner-then-slot plan is read against a defense that collapses onto
	# the slot during the first leg's dwell (_project_opponents_collapsing), so the
	# corner does not inherit the slot's value; and the entry's net-ward momentum
	# makes the middle-ward cut cheap to reach and the boards drift a reversal.
	var self_pos := Vector3(8.0, 0.0, -18.0)               # wing entry, OZ
	var vel := Vector3(-1.0, 0.0, -3.0)                    # driving in off the wing
	var skaters: Array = [
			[1, TEAM_ID, self_pos, false, vel],
			[3, 1, Vector3(3.0, 0.0, -20.0)],              # defender on the inside lane
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.self_velocity = vel
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			self_pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	# Not parked down at the goal line: the winning carry keeps a real shooting
	# angle, well up off the dead corner.
	assert_lt(absf(c.last_carry_anchor.z), GameRules.GOAL_LINE_Z - 3.0,
			"the carry stays off the goal line instead of drifting to the dead corner")
	assert_lte(absf(c.last_carry_anchor.x), self_pos.x + 0.01,
			"and works toward the middle, not further into the boards")


# ─── fake-then-cut deke mirror ────────────────────────────────────────────────

func test_patient_container_arms_the_deke_read() -> void:
	# A league-agility defender parked in the duel range dead ahead on the
	# objective line, nobody moving — the classic containment stalemate. The
	# carrier's re-eval should arm the deke: fake one way, cut the other
	# (the two committed directions oppose laterally by construction).
	var self_pos := Vector3(0.0, 0.0, -14.0)             # OZ, attacking -Z
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(0.0, 0.0, -17.6)],            # ~2.3 m off the carried puck
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.protects_the_puck = true
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_true(c.deke_go, "a patient container in range arms the manufactured-opening read")
	assert_lt(c.deke_fake_dir.dot(c.deke_cut_dir), 0.0,
			"the fake sells one side, the cut explodes the other")


func test_no_deke_read_against_a_committed_charger() -> void:
	# Same spot, but the defender is charging in hard — committed pressure is
	# the brake check / seam's moment, not a fake's (he's already biting).
	var self_pos := Vector3(0.0, 0.0, -14.0)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(0.0, 0.0, -17.6), false, Vector3(0, 0, 7)],
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.protects_the_puck = true
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_false(c.deke_go, "committed pressure never reads as a fake target")


# ─── carry continuation credit (the two-ply read) ─────────────────────────────
# A candidate is worth the best thing it lets the carrier DO next
# (_carry_continuation_value — the pass option's skating twin): the opening a
# beaten man concedes only prices in on the step after the cut.

const _SPUN_OFF_SPOT := Vector3(6.0, 0.0, -15.0)


# The moment after beating a man: driving net-ward off the wing, the beaten
# defender dead in the water behind; keeper squared at 1.3 m.
func _spun_off_ctx() -> RoleContext:
	var vel := Vector3(-2.0, 0.0, -4.0)
	var ctx := _make_ctx(_SPUN_OFF_SPOT, [
			[1, TEAM_ID, _SPUN_OFF_SPOT, false, vel],
			[3, 1, Vector3(4.5, 0.0, -14.0), false, Vector3.ZERO]])
	ctx.self_velocity = vel
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			_SPUN_OFF_SPOT, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	return ctx


# 3 m straight at the net from _SPUN_OFF_SPOT.
func _spun_off_cut_in() -> Vector3:
	return _SPUN_OFF_SPOT + (Vector3(0.0, 0.0, OPP_NET_Z) - _SPUN_OFF_SPOT).normalized() * 3.0


func _move_score(c: AIRoleCarrier, ctx: RoleContext, spot: Vector3) -> float:
	return c._score_move_candidate(ctx, spot, Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z))


func test_spun_off_carrier_attacks_the_opening() -> void:
	# The continuation credit turns the drive into a committed route TOWARD the
	# net instead of a safety orbit around the perimeter. Momentum matters:
	# time_to_arrive charges the cost of shedding sideways speed, so this carrier's
	# momentum already points at the cut; one moving laterally away could not reach
	# it before the beaten man recovered (test_continuation_credit_respects_live_
	# containment).
	var net := Vector3(0.0, 0.0, OPP_NET_Z)
	var ctx: RoleContext = _spun_off_ctx()
	var c: AIRoleCarrier = _decided(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"no direct shot from the wing vs a set keeper — the play is the route")
	assert_gt(_SPUN_OFF_SPOT.distance_to(net) - c.last_carry_anchor.distance_to(net), 1.0,
			"the committed anchor cuts IN toward the net, not around the perimeter")
	var cut_score: float = _move_score(c, ctx, _spun_off_cut_in())
	assert_gt(cut_score, _move_score(c, ctx, Vector3(8.2, 0.0, -17.0)),
			"the cut-in's continuation beats the lateral escape's marginal safety")
	# Stand-still is the noise floor, and it is in the compete already: the plan
	# has to beat doing nothing. (By how much is calibration: the snapshot.)
	var stand_score: float = _move_score(c, ctx, _SPUN_OFF_SPOT)
	assert_gt(cut_score, stand_score,
			"…and it is a real plan, not argmax-over-noise; %f vs %f" % [cut_score, stand_score])


func test_continuation_credit_respects_live_containment() -> void:
	# Same net-ward drive, but the defender is LIVE in the cut lane — ahead on the
	# inside, skating with the carrier to hold it. The continuation collapses
	# through the second leg's reach safety (no phantom aggression): the cut reads
	# contested and the compete keeps cycling to space instead of forcing it.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(6.0, 0.0, -15.0)
	var vel := Vector3(-2.0, 0.0, -4.0)
	var skaters: Array = [
			[1, TEAM_ID, self_pos, false, vel],
			[3, 1, Vector3(3.5, 0.0, -18.0), false, Vector3(-1.5, 0.0, -1.5)],
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.self_velocity = vel
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(self_pos, net, 1.3)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	var our_goalie := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)
	var cut_in: Vector3 = self_pos + (net - self_pos).normalized() * 3.0
	var lateral := Vector3(8.2, 0.0, -17.0)
	assert_gt(c._score_move_candidate(ctx, lateral, our_goalie),
			c._score_move_candidate(ctx, cut_in, our_goalie),
			"a live defender in the cut lane still owns it — cycle, don't force")


# ─── Phase B (docs/breakout-plan.md): wheel, rim family, the Over ────────────

func test_behind_net_carrier_wheels_to_the_far_wall_in_5v5() -> void:
	# Retriever behind our own net with a committed chaser closing from the
	# +x side and the strong-side front covered — the wheel around the cage
	# to the far half-wall is the researched out, and only the two-leg apex
	# candidate can represent it (every straight far-side route crosses the
	# cage and prunes).
	# The wheel's real trigger: the retriever is already moving with a step
	# on his chaser, who trails in his wake (committed to the same line —
	# the escape gate reads him as beaten). The strong-side front is
	# covered, so turning up the near side means the wall battle.
	var self_pos := Vector3(2.0, 0, 27.6)
	var self_vel := Vector3(-4.0, 0, 0.4)
	var skaters: Array = [
		[1, TEAM_ID, self_pos, false, self_vel],
		[3, 1, Vector3(4.6, 0, 27.4), false, Vector3(-4.2, 0, 0)],
		[4, 1, Vector3(4.5, 0, 22.0)],
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.self_velocity = self_vel
	ctx.team_size = 5
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY,
			"the wheel is a carry, not a panic release")
	assert_lt(c.last_carry_anchor.x, -5.0,
			"the carry exits on the FAR side of the cage")
	assert_lt(c.last_carry_anchor.z, 22.0,
			"...up the far wall, not a near-post step")


func test_wheel_is_5v5_exclusive() -> void:
	# The identical situation in 3v3 has no wheel candidate (plan §5:
	# possession-first 3v3 keeps its shipped option set).
	var self_pos := Vector3(2.0, 0, 27.6)
	var self_vel := Vector3(-4.0, 0, 0.4)
	var skaters: Array = [
		[1, TEAM_ID, self_pos, false, self_vel],
		[3, 1, Vector3(4.6, 0, 27.4), false, Vector3(-4.2, 0, 0)],
		[4, 1, Vector3(4.5, 0, 22.0)],
	]
	var ctx := _make_ctx(self_pos, skaters)
	ctx.self_velocity = self_vel
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_false(c.last_carry_anchor.x < -5.0 and c.last_carry_anchor.z < 22.0,
			"no far-wall wheel exit exists in 3v3")


func _rim_ctx(team_size: int, wall_lane_blocked: bool) -> RoleContext:
	# Carrier pinned on our own wall by two forecheckers; the wall winger is
	# posted up the boards on the rim's path; the rest of the ice is deep.
	# The forecheck pins from the INSIDE shoulder (angling the carrier to
	# the wall — the real geometry), which is exactly what leaves the wall
	# lane itself as the one protected out.
	#
	# The bodies are placed against where the clear actually COMES TO REST. With
	# the winger posted up the strong wall the search rims to him and the puck
	# dies just past centre on that side (~(11.7, -2.8)), so the camped body is
	# their retreating D standing on that spot. Both are derived from the
	# delivery, not assumed: the release search is blind to skaters, so every
	# scene here shares one candidate set and only the RACE for it moves — the
	# camped test prints the settle it read, so a physics change that moves the
	# landing shows the stale placement instead of hiding it.
	var self_pos := Vector3(10.5, 0, 24.0)
	var skaters: Array = [
		[1, TEAM_ID, self_pos],
		[2, TEAM_ID, Vector3(11.5, 0, 6.0)],
		[3, 1, Vector3(8.8, 0, 23.0)],
		[4, 1, Vector3(9.0, 0, 25.8)],
		[5, 1, Vector3(0.0, 0, 15.0)],
	]
	if wall_lane_blocked:
		skaters.append([6, 1, Vector3(11.7, 0, -2.8)])
	var ctx := _make_ctx(self_pos, skaters)
	ctx.team_size = team_size
	return ctx


func test_own_zone_clear_is_worth_more_with_a_winger_posted_to_win_it() -> void:
	# The clear is not a pure concession: what it is worth is what we are likely
	# to win back. A teammate posted where the puck comes to rest turns it into
	# a completed breakout, and the value has to see that.
	#
	# This replaces a pin on the retired FLAT-rim delivery flag. The rim/chip
	# choice no longer exists as a branch — a launch angled into the near boards
	# IS the rim, and the landing solver walks its real carom — so what is
	# assertable is the consequence, not the label. It is also no longer 5v5-only:
	# the delivery value comes from the race, which every roster size runs.
	var ctx := _rim_ctx(5, false)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var with_winger: Array = c._best_dump(ctx, ctx.defending_goal_pos)
	# Same scene with the wall post unmanned.
	var bare := _make_ctx(Vector3(10.5, 0, 24.0), [
			[1, TEAM_ID, Vector3(10.5, 0, 24.0)],
			[3, 1, Vector3(8.8, 0, 23.0)],
			[4, 1, Vector3(9.0, 0, 25.8)],
			[5, 1, Vector3(0.0, 0, 15.0)]])
	# Unmanned, our only chaser is the carrier himself — 44 m behind the resting
	# puck and a full rink-length worse than their nearest body, so the race is
	# lost outright and the clear pays its whole concession.
	bare.team_size = 5
	var c_bare := AIRoleCarrier.new()
	c_bare._build_action_opponents_lists(bare)
	var without: Array = c_bare._best_dump(bare, bare.defending_goal_pos)
	gut.p("  clear value: winger posted %.4f vs unmanned %.4f"
			% [with_winger[0], without[0]])
	assert_gt(with_winger[0], without[0],
			"a manned post makes the clear worth more than an unmanned one")


# Retriever BEHIND our net with the forecheck committed, the wall winger posted
# — the breakout harness's compete moment.
func _behind_net_clear_ctx() -> RoleContext:
	var self_pos := Vector3(2.0, 0, 28.2)
	var ctx := _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(10.5, 0, 14.0)],      # wall winger posted
			[3, 1, Vector3(3.5, 0, 25.8)],             # F1 chasing net-front
			[4, 1, Vector3(6.5, 0, 22.0)],             # F2 inside shoulder
			[5, 1, Vector3(0.0, 0, 15.0)]])            # high man in the middle
	ctx.team_size = 5
	return ctx


# [the clear's value, where it comes to rest, the cost of instead losing the puck
# in our slot]: the searched clear and a turnover, priced by one carrier.
func _behind_net_clear() -> Array:
	var ctx: RoleContext = _behind_net_clear_ctx()
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var r: Array = c._best_dump(ctx, ctx.defending_goal_pos)
	var our_slot: Vector3 = ctx.defending_goal_pos + Vector3(0, 0, -6.0)
	return [r[0], r[4], c._turnover_cost(ctx, our_slot, 1.0, ctx.defending_goal_pos)]


func test_behind_net_clear_is_a_real_play_under_a_committed_forecheck() -> void:
	# Doctrine says clearing is the right play here, and it has to price that way:
	# the searched release is the flown path, it is a pure concession (never a
	# credit), it leaves our zone, and it concedes less than surrendering the puck
	# in front of our own net would.
	var clear: Array = _behind_net_clear()
	gut.p("  behind-net clear settles at %s, value %.4f" % [clear[1], clear[0]])
	assert_lte(clear[0], 0.0, "a clear is priced as a concession, never a credit")
	assert_gt(clear[0], -clear[2],
			"the clear concedes less than a turnover in our slot (%.4f)" % clear[2])
	assert_false(
			AIActionScoring.in_offensive_zone(clear[1], Vector3(0, 0, OUR_NET_Z)),
			"and it actually leaves our zone")


func test_the_clear_rims_to_the_wall_our_man_can_win() -> void:
	# The search's whole job: among launches that are legal to make, take the one
	# we concede least by. Which wall that is depends on who is standing there, so
	# moving the posted winger across the ice moves the clear across with him —
	# nothing else in the scene changes, and the release search itself is blind to
	# skaters, so the candidate set is byte-identical in both runs.
	#
	# This is what the depth objective could not do. Ranked on metres-to-the-blue-
	# line the two runs are the SAME ranking, so the clear fired at the same wall
	# whether or not anyone was there to win it (#650).
	var self_pos := Vector3(10.5, 0, 24.0)
	var forecheck: Array = [
		[3, 1, Vector3(8.8, 0, 23.0)],
		[4, 1, Vector3(9.0, 0, 25.8)],
		[5, 1, Vector3(0.0, 0, 15.0)],
	]
	var settles: Array[Vector3] = []
	for post: Vector3 in [Vector3(11.5, 0, 6.0), Vector3(-11.5, 0, 6.0)]:
		var skaters: Array = [[1, TEAM_ID, self_pos], [2, TEAM_ID, post]]
		skaters.append_array(forecheck)
		var ctx := _make_ctx(self_pos, skaters)
		ctx.team_size = 5
		var c := AIRoleCarrier.new()
		c._build_action_opponents_lists(ctx)
		settles.append(c._best_dump(ctx, ctx.defending_goal_pos)[4])
	gut.p("  clear settles: strong-side post %s vs far-side post %s"
			% [settles[0], settles[1]])
	assert_gt(settles[0].x, 0.0, "with the winger up the strong wall, rim it there")
	assert_lt(settles[1].x, 0.0, "post him on the far wall and the rim follows him")


func test_a_camped_wall_lane_makes_the_clear_worth_less() -> void:
	# A body sitting where the clear comes to rest is priced by the race, not by
	# a lane test on a modelled route: he is simply nearer the resting puck, so
	# our recovery odds drop and the clear is worth less. Same scene, one
	# opponent added on the resting spot (see _rim_ctx). The candidate set is
	# identical in both runs — the release search reads only geometry — so what
	# this measures is purely the race: either the same clear costs more with him
	# standing on it, or the search backs off to a different wall that costs more
	# than the one he took away. Both are the assertion below.
	var open_ctx := _rim_ctx(5, false)
	var c_open := AIRoleCarrier.new()
	c_open._build_action_opponents_lists(open_ctx)
	var open_r: Array = c_open._best_dump(open_ctx, open_ctx.defending_goal_pos)
	var ctx := _rim_ctx(5, true)
	var c := AIRoleCarrier.new()
	c._build_action_opponents_lists(ctx)
	var r: Array = c._best_dump(ctx, ctx.defending_goal_pos)
	gut.p("  clear settles open %s camped %s" % [open_r[4], r[4]])
	gut.p("  clear value: open lane %.4f vs camped %.4f" % [open_r[0], r[0]])
	assert_lt(r[0], open_r[0],
			"a body camped where the clear lands lowers our odds of winning it")


func test_developing_feed_watches_the_over_valve_in_5v5() -> void:
	# The OVER: the partner D swinging across the TOP of our zone (the legal
	# D-to-D lane over the slot box's upper edge) is a developing feed worth
	# a beat of protection — same primitive as the wall outlet, now watched
	# for BREAKOUT_D2 (5v5-inherent: the slot only exists there). The
	# behind-net Over remains unrepresentable by the own-goal-risk zeros
	# (lead-past-our-line + net-blocker) — pended in the plan doc.
	# Lane staged above the HOME-PLATE slot veto's upper edge (widened to
	# 2.75 × 6.0 in 534f534 — the watch prices the future feed through the
	# same veto, so a lane inside the deeper rect now honestly reads dead).
	var self_pos := Vector3(10.0, 0, 20.0)
	var ctx := _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-4.0, 0, 19.2), false, Vector3(-2.0, 0, 0.6)]])
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = AIRoleSlots.Slot.BREAKOUT_D2
	ctx.team_brain = brain
	var carrier := AIRoleCarrier.new()
	carrier._scratch_teammate_ids = [2]
	assert_gt(carrier._best_developing_feed(ctx), 0.0,
			"a partner skating to the net-back valve is a developing Over")


func test_no_direct_shot_from_on_or_behind_the_goal_line() -> void:
	# The "skate past the goal line and clank the outer bar" bug: a carrier whose
	# body is BEHIND the goal line, skating out, had its velocity-projected blade
	# release land a hair in front and clamp to a phantom point-blank open net —
	# scoring a zero-angle rip off the outer pipe. The mouth faces up-ice; from back
	# there the only play is a wrap/walk-out carry, so the direct shot must not
	# score at all.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var behind := Vector3(0.6, 0.0, -(GameRules.GOAL_LINE_Z + 0.6))   # behind the net
	var ctx := _make_ctx(behind, [[1, TEAM_ID, behind]])
	ctx.self_velocity = Vector3(0.0, 0.0, 6.0)                        # skating out toward the line
	ctx.snapshot.puck_state.position = behind
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(behind, net, 1.0)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_lt(c.debug_shoot_score, 0.001,
			"no direct shot is scored from on/behind the goal line; got %f" \
			% c.debug_shoot_score)
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_SHOOT,
			"the behind-the-net carrier wraps/carries, never rips the outer pipe")


func test_in_front_shot_still_scores_through_the_gate() -> void:
	# The gate is position-specific, not a blanket shot kill: a carrier genuinely in
	# front (in tight, with the keeper beaten to one side) still gets a real shot.
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var slot := Vector3(0.0, 0.0, -(GameRules.GOAL_LINE_Z - 5.0))     # 5 m out, dead slot
	var ctx := _make_ctx(slot, [[1, TEAM_ID, slot]])
	ctx.snapshot.puck_state.position = slot
	var g := GoalieNetworkState.new()
	g.position_x = 0.75                                              # beaten to the +x side
	g.position_z = net.z + 1.3
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_gt(c.debug_shoot_score, 0.0,
			"an in-tight look at a beaten keeper still scores a shot; got %f" \
			% c.debug_shoot_score)


# ── Behind the net: a carrier back there needs moves to choose between ───────
# The candidate rings used to prune everything past the goal line, which left a
# carrier behind the cage with two post walkouts and stand-still. Under pressure
# both walkouts read unsafe and the compete fell to stand-still — the bot planted
# itself on the end wall and got stripped. These pin the representation, not a
# preference: the lateral walk back there exists, and the cage is still a wall.

func test_behind_net_candidates_exist_for_a_carrier_behind_the_goal_line() -> void:
	# Behind the opposing cage: |z| is BEYOND the goal line, so z is more
	# negative than OPP_NET_Z.
	var behind := Vector3(3.0, 0.0, OPP_NET_Z - 1.6)
	var c := AIRoleCarrier.new()
	assert_true(c._candidate_ice_legal(
			Vector3(-3.0, 0.0, behind.z), true),
			"the walk across the back of the cage is a representable move")
	assert_true(c._candidate_ice_legal(
			Vector3(6.0, 0.0, behind.z + 1.0), true),
			"so is working out toward the corner")


func test_the_cage_itself_is_still_not_a_place_to_stand() -> void:
	var c := AIRoleCarrier.new()
	assert_false(c._candidate_ice_legal(
			Vector3(0.0, 0.0, OPP_NET_Z - GameRules.NET_DEPTH * 0.5), true),
			"inside the goal frame is not ice")


func test_behind_net_candidates_stay_on_the_playing_surface() -> void:
	var c := AIRoleCarrier.new()
	assert_false(c._candidate_ice_legal(
			Vector3(3.0, 0.0, -(GameRules.INNER_HALF_LENGTH + 0.5)), true),
			"through the end boards is not ice")
	assert_false(c._candidate_ice_legal(
			Vector3(GameRules.CORNER_CENTER_X + GameRules.INNER_CORNER_RADIUS,
					0.0, GameRules.CORNER_CENTER_Z + 3.0), true),
			"and the rounded corner is honoured, not a bounding box")


func test_a_carrier_out_front_keeps_the_old_goal_line_clamp() -> void:
	# Scoped change: nothing about front-of-net carrying moves.
	var c := AIRoleCarrier.new()
	assert_false(c._candidate_ice_legal(
			Vector3(3.0, 0.0, OPP_NET_Z - 1.6), false),
			"a carrier in front never plans a step past the goal line")
	assert_true(c._candidate_ice_legal(Vector3(3.0, 0.0, -18.0), false))


# ── The rim pass (AIRimPass) ─────────────────────────────────────────────────
# Our D behind our own net, a forechecker on his hip and another sitting in the
# straight lane to the strong half-wall winger. The boards are the open lane:
# rimmed round the corner, the puck reaches the winger before anybody of theirs.

func _rim_breakout_ctx(lane_blocked: bool) -> RoleContext:
	var self_pos := Vector3(3.0, 0, 28.0)
	var skaters: Array = [
		[1, TEAM_ID, self_pos],
		[2, TEAM_ID, Vector3(11.5, 0, 14.0)],      # strong half-wall winger
		[3, 1, Vector3(1.5, 0, 28.5)],             # on the D's hip
		[5, 1, Vector3(-3.0, 0, 18.0)],
	]
	if lane_blocked:
		skaters.append([4, 1, Vector3(7.0, 0, 21.0)])   # in the straight lane
	return _make_ctx(self_pos, skaters)


func test_a_blocked_breakout_lane_is_rimmed_round_the_boards() -> void:
	var ctx := _rim_breakout_ctx(true)
	var c := AIRoleCarrier.new()
	c._pick_fire_phase(ctx)
	gut.p("  best pass %.4f to %d, rim %s at %.1f m/s" % [c._phase_best_pass_score,
			c._phase_best_pass_peer, c._phase_best_pass_rim_dir, c._phase_best_pass_rim_pace])
	assert_eq(c._phase_best_pass_peer, 2, "the winger is the target")
	assert_ne(c._phase_best_pass_rim_dir, Vector3.ZERO,
			"...by the boards, not through the forechecker")
	assert_gt(c._phase_best_pass_rim_pace, AIPuckLane.PASS_SPEED_M_S,
			"a rim needs more than quick-pass pace — the corner bleeds it")


func test_a_rim_is_fired_as_soft_as_the_race_allows() -> void:
	var ctx := _rim_breakout_ctx(true)
	var c := AIRoleCarrier.new()
	c._pick_fire_phase(ctx)
	var best: float = 0.0
	for k: int in AIRimPass.count:
		best = maxf(best, c._rim_sure_by_k[k])
	var softest: float = INF
	var hardest: float = 0.0
	for k: int in AIRimPass.count:
		if c._rim_sure_by_k[k] >= best * AIRoleCarrier.RIM_SOFT_SHARE:
			softest = minf(softest, AIRimPass.paces[k])
			hardest = maxf(hardest, AIRimPass.paces[k])
	gut.p("  rim fired at %.1f m/s (near-best band %.1f..%.1f)"
			% [c._phase_best_pass_rim_pace, softest, hardest])
	assert_gt(best, 0.0, "some rim reaches the winger")
	assert_eq(c._phase_best_pass_rim_pace, softest,
			"the softest launch nearly as sure as the best is the one fired")


func test_a_rim_commits_as_a_flat_charged_release_along_its_bearing() -> void:
	var ctx := _rim_breakout_ctx(true)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_DUMP,
			"pinned on his own goal line with the lane cut, he rims it")
	assert_true(c.dump_is_rim, "the dump release fires FLAT as a rim")
	assert_false(c.dump_is_soft)
	assert_eq(c.pass_target_peer_id, c._phase_best_pass_peer, "…to the receiver it was priced to")
	assert_eq(c.dump_launch_speed, c._phase_best_pass_rim_pace, "…at its searched pace")
	var puck: Vector3 = ctx.snapshot.puck_state.position
	assert_almost_eq((c.dump_target - puck).normalized().dot(c._phase_best_pass_rim_dir), 1.0,
			1e-4, "…along its searched bearing")


func test_an_open_breakout_lane_is_passed_straight() -> void:
	var ctx := _rim_breakout_ctx(false)
	var c := AIRoleCarrier.new()
	c._pick_fire_phase(ctx)
	gut.p("  best pass %.4f to %d, rim %s" % [c._phase_best_pass_score,
			c._phase_best_pass_peer, c._phase_best_pass_rim_dir])
	assert_gt(c._phase_best_pass_score, 0.0)
	assert_eq(c._phase_best_pass_rim_dir, Vector3.ZERO,
			"an open lane takes the tape-to-tape feed")


# ── The reviewed calibration ─────────────────────────────────────────────────
# What the current calibration decides and measures at the fixtures above whose
# outcome is tuning, not doctrine. Rewrite with MITTS_UPDATE_SNAPSHOTS=1
# (tests/snapshot.gd) and review the diff.

func _intent_name(intent: int) -> String:
	if intent == AIRoleCarrier.INTENT_CARRY:
		return "CARRY"
	if intent == AIRoleCarrier.INTENT_SHOOT:
		return "SHOOT"
	if intent == AIRoleCarrier.INTENT_PASS:
		return "PASS"
	if intent == AIRoleCarrier.INTENT_DUMP:
		return "DUMP"
	return str(intent)


func test_carrier_calibration_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	snap.record("walled off at speed, nobody to hit: intent",
			_intent_name(_decided(_walled_ctx(false)).intended_action))
	var walled: AIRoleCarrier = _decided(_walled_ctx(true))
	snap.record("walled off at speed, outlet up the wall: intent",
			_intent_name(walled.intended_action))
	snap.record("walled off at speed, outlet up the wall: pass value", walled.debug_pass_score)
	snap.record("impeded by a defender ahead, open mate wide: intent", _intent_name(
			_decided(_impeded_ctx(_IMPEDED_OPEN_MATE, _DEFENDER_AHEAD)).intended_action))
	snap.record("ahead man, clear path: drive-in credit", _ahead_man_drive_in(_ahead_man_ctx(false)))
	snap.record("ahead man, defender in his path: drive-in credit",
			_ahead_man_drive_in(_ahead_man_ctx(true)))
	snap.record("ahead man, defender in his path: intent",
			_intent_name(_decided(_ahead_man_ctx(true)).intended_action))
	var frontal: AIRoleCarrier = _frontal_threat(1.6)
	snap.record("stick 1.6 m ahead on the presented puck: protect gain", frontal.protect_gain)
	snap.record("stick 1.6 m ahead on the presented puck: offset behind the body",
			frontal.protect_offset.z)
	snap.record("defender abreast 2.2 m off the hip: protect gain", _abreast_shield().protect_gain)
	var clear: Array = _behind_net_clear()
	var rest: Vector3 = clear[1]
	snap.record("behind-net clear under a committed forecheck: value", clear[0])
	snap.record("behind-net clear under a committed forecheck: rests at x", rest.x)
	snap.record("behind-net clear under a committed forecheck: rests at z", rest.z)
	var pinch: AIRoleCarrier = _pinch(_TIGHT_WALL_HALF_GAP)
	snap.record("tight-wall pinch, open man wide: intent", _intent_name(pinch.intended_action))
	snap.record("tight-wall pinch, open man wide: pass target", pinch.pass_target_peer_id)
	snap.record("dead slot over the 8.5 m band, set keeper: shoot-now ratio",
			_shoot_now(_DEAD_SLOT, _DEAD_SLOT) / _shoot_now(_MID_BAND, _MID_BAND))
	var spun_ctx: RoleContext = _spun_off_ctx()
	var spun: AIRoleCarrier = _decided(spun_ctx)
	snap.record("spun-off carrier, cut-in over standing still: move-score ratio",
			_move_score(spun, spun_ctx, _spun_off_cut_in())
			/ _move_score(spun, spun_ctx, _SPUN_OFF_SPOT))
	snap.verify(self)

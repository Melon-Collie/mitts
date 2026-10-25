extends GutTest

# AIRoleCarrier's compete on fixture snapshots: what it picks (shoot, pass and
# its variants and the rim, carry, hold) and where, plus its lifecycle (reset,
# clear_intent, cooldown, settle doubt). The evaluators it prices with are
# covered in test_ai_action_scoring and test_reach_safety. A pick asserted here
# is doctrine (Scripts/domain/ai/CLAUDE.md, Scripts/ai/CLAUDE.md, the design
# docs); what the carrier picks at a fixture whose outcome is tuning, and the
# calibrated values behind it, are a reviewed snapshot,
# test_carrier_calibration_snapshot (tests/snapshot.gd).

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


# ─── pricing the feed ───────────────────────────────────────────────────────

# Our D off-centre in our own zone, an open outlet straight up the wall past
# the red line — far enough ahead that the forechecker can never race him to
# the zone, so only the lane reads him — and a forechecker starting 2.6 m off
# the lane (a full stick clear) at `vel`.
func _lane_forechecker_ctx(vel: Vector3) -> RoleContext:
	var self_pos := Vector3(4.0, 0.0, 20.0)
	return _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(4.0, 0.0, -1.0)],
			[11, 1, Vector3(6.6, 0.0, 13.5), false, vel]])


func test_forechecker_closing_the_breakout_lane_devalues_the_pass() -> void:
	# The pass a bot fires is a charged wrister — it leaves the blade ~135 ms
	# after the intent commits — so the lane it threads is the lane as it exists
	# at RELEASE, not at decision time. The same defender skating into the lane
	# (-X) is ~1 m closer before the puck leaves the blade and keeps closing over
	# the flight (_scratch_opponents_release). The release-time lane pricing itself
	# is guarded at the primitive level in test_ai_action_scoring.
	var s: AIRoleCarrier = _decided(_lane_forechecker_ctx(Vector3.ZERO))
	assert_gt(s.debug_pass_score, 0.0, "precondition: the feed past a standing man is on")
	var c: AIRoleCarrier = _decided(_lane_forechecker_ctx(Vector3(-8.0, 0.0, 0.0)))
	assert_lt(c.debug_pass_score, s.debug_pass_score,
			"a forechecker skating into the lane during the windup drops the pass value")


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


const _BACKDOOR_CARRIER := Vector3(6.0, 0.0, -20.0)     # wide angle, poor look
const _BACKDOOR_MATE := Vector3(-2.5, 0.0, -23.5)       # far-post backdoor, clear lane


# The carrier wide in the zone with one mate at `mate`, the keeper squared to the
# carrier 1.3 m out (as the live keeper is).
func _backdoor_ctx(mate: Vector3) -> RoleContext:
	var ctx := _make_ctx(_BACKDOOR_CARRIER, [[1, TEAM_ID, _BACKDOOR_CARRIER], [2, TEAM_ID, mate]])
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			_BACKDOOR_CARRIER, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	return ctx


# Our end, two defenders clogging the middle carry, a winger ahead with a clear
# lane and a clear path on; keeper set.
func _clogged_middle_ctx() -> RoleContext:
	var self_pos := Vector3(0.0, 0.0, 16.0)
	return _set_keeper(_make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-8.0, 0.0, 6.0)],
			[11, 1, Vector3(-1.0, 0.0, 10.0)],
			[12, 1, Vector3(2.0, 0.0, 9.0)]]))


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
	_place_keeper(ctx, g)
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
	return _decided(ctx)._field.receiver_drive_in_value(
			ctx, _AHEAD_MAN, null)


func test_a_defender_in_the_drive_path_strips_the_receivers_drive_in() -> void:
	# The drive-in reach is the REACHABLE extent, not a free deep credit: the same
	# man ahead earns less once a defender stands squarely in his forward path.
	var open: float = _ahead_man_drive_in(_ahead_man_ctx(false))
	assert_gt(open, 0.0, "a clear drive toward the net is credited")
	assert_lt(_ahead_man_drive_in(_ahead_man_ctx(true)), open,
			"a defender in the drive path strips the credit")


func test_a_drive_into_a_defender_in_our_half_pays_the_turnover() -> void:
	# The drive is priced in the carry's currency: a strip is the opponent's
	# possession where it happens. Straight into a man just outside our blue line,
	# what the drive can earn is far less than what losing it there costs.
	var self_pos := Vector3(0.0, 0.0, 9.0)
	var ctx: RoleContext = _set_keeper(_make_ctx(self_pos, [
			[1, TEAM_ID, self_pos], [11, 1, Vector3(0.0, 0.0, 6.5)]]))
	var c: AIRoleCarrier = _decided(ctx)
	assert_lt(c._field.receiver_drive_in_value(ctx, self_pos, null, Vector3.ZERO,
			Vector3.INF, 0.0, true), 0.0)


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


# A central carrier in the zone with one mate open but wide at a poor angle;
# keeper squared 1.3 m out.
func _poor_spot_mate_ctx() -> RoleContext:
	var self_pos := Vector3(0.0, 0.0, -12.0)
	var ctx := _make_ctx(self_pos, [[1, TEAM_ID, self_pos], [2, TEAM_ID, Vector3(9.0, 0.0, -14.0)]])
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			self_pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	return ctx


const _CLOSE_PASSER := Vector3(-4, 0, 2)
const _CLOSE_OUTLET := Vector3(1, 0, -1)          # ~5.8 m — a close feed, up-ice


# Neutral ice, a defender clogging the straight carry/shot lane, a close outlet.
func _close_outlet_ctx() -> RoleContext:
	return _make_ctx(_CLOSE_PASSER, [
			[1, TEAM_ID, _CLOSE_PASSER],
			[2, TEAM_ID, _CLOSE_OUTLET],
			[11, 1, Vector3(-4, 0, -2)]])


func test_close_pass_fires_at_the_pace_it_was_priced_at() -> void:
	# Every pass is a paced wrister, fired at the pace the search priced it at
	# (AIPuckLane.PASS_PACE_FRACS): what is priced is what is fired. A close feed
	# to an open teammate goes soft — the full pace's settle costs him more than
	# the softer flight does. The PASS_TO_ME ping commits the feed — any
	# remotely reasonable order wins (docs/gameplay-design.md, smart ping); whether
	# it wins unasked is the snapshot's row.
	var self_pos: Vector3 = _CLOSE_PASSER
	var outlet: Vector3 = _CLOSE_OUTLET
	var ctx: RoleContext = _close_outlet_ctx()
	ctx.ping_pass_target_peer = 2
	var c: AIRoleCarrier = _decided(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS, "the pinged feed is committed")
	assert_eq(c.pass_target_peer_id, 2)
	assert_lt(c._pass.best_pace_frac, 1.0, "a close open feed goes soft")
	assert_almost_eq(c.pass_target_speed,
			AIPuckLane.pass_launch_speed(self_pos.distance_to(outlet),
					GameRules.DEFAULT_WRISTER_POWER_MAX_M_S,
					ctx.pass_speed_scale * c._pass.best_pace_frac), 0.1,
			"fires at the friction-compensated pace it was priced at")


const _FEED_PASSER := Vector3(-4, 0, 6)
const _FEED_RECEIVER := Vector3(-4, 0, -6)     # 12 m up-ice


# The bobble odds of the feed the search picked, at the pace it fires.
func _picked_feed_bobble_prob(defender: Vector3) -> float:
	var ctx: RoleContext = _make_ctx(_FEED_PASSER, [
			[1, TEAM_ID, _FEED_PASSER],
			[2, TEAM_ID, _FEED_RECEIVER],
			[11, 1, defender]])
	var c: AIRoleCarrier = _decided(ctx)
	assert_eq(c._pass.best_peer, 2, "the feed is still worth pricing")
	var speed: float = AIPuckLane.pass_launch_speed(_FEED_PASSER.distance_to(_FEED_RECEIVER),
			GameRules.DEFAULT_WRISTER_POWER_MAX_M_S, ctx.pass_speed_scale * c._pass.best_pace_frac)
	return AIFeedReception.receiver_bobble_prob(
			AIFeedReception.arrival_closing_speed(_FEED_PASSER, _FEED_RECEIVER, speed, Vector3.ZERO))


# A bobble is a loose puck its receiver must win back after his lockout
# (AIFeedReception.bobble_regather_s), so a defender who can race him to it makes
# the feed go at a pace he catches.
func test_a_defender_off_the_receiver_softens_a_feed_off_full_pace() -> void:
	assert_lt(_picked_feed_bobble_prob(Vector3(-7, 0, -9)), 1.0,
			"full pace bobbles every time, into a defender's reach")


func test_a_defender_behind_the_receiver_softens_a_feed_to_a_sure_catch() -> void:
	assert_eq(_picked_feed_bobble_prob(Vector3(-4, 0, -13)), 0.0,
			"a man 7 m behind still wins the race to a bobble")


# ─── keeping or moving the puck under pressure ──────────────────────────────
# What the carrier picks at these is calibration: the snapshot's rows.

# Neutral ice on the right, two forecheckers converging in a pincer, an open
# outlet left-centre.
func _pincer_ctx() -> RoleContext:
	var self_pos := Vector3(6, 0, 9)
	return _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-3, 0, 6)],
			[3, 1, Vector3(4, 0, 4), false, Vector3(1.5, 0, 5)],
			[4, 1, Vector3(9, 0, 5), false, Vector3(-3, 0, 5)]])


# Lightly pressured on our side of centre with space ahead; the only mate is
# deeper, in our end, with a defender sitting on him.
func _covered_backpass_ctx() -> RoleContext:
	var self_pos := Vector3(2, 0, 12)
	return _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(0, 0, 19)],
			[3, 1, Vector3(2, 0, 8), false, Vector3(0, 0, 2)],
			[4, 1, Vector3(0.6, 0, 19.5)]])


const _DEEP_CARRIER := Vector3(2, 0, 21)


# Deep in our zone, a forechecker charging, the only mate even deeper (a
# backpass toward our own net).
func _deep_backpass_ctx() -> RoleContext:
	return _make_ctx(_DEEP_CARRIER, [
			[1, TEAM_ID, _DEEP_CARRIER],
			[2, TEAM_ID, Vector3(-3, 0, 24)],
			[3, 1, Vector3(2, 0, 17.5), false, Vector3(0, 0, 5)]])


# Deep in our zone, alone, one forechecker charging straight at us, flanks open.
func _lone_forechecker_ctx() -> RoleContext:
	return _make_ctx(_DEEP_CARRIER, [
			[1, TEAM_ID, _DEEP_CARRIER],
			[3, 1, Vector3(2, 0, 18), false, Vector3(0, 0, 5)]])


const _SHORT_OF_THE_BLUE_LINE := Vector3(0.0, 0.0, -6.5)   # alone, at rest


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
	_place_keeper(ctx_in, g)
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

	# Control: further back the puck cannot reach the line before release, so the
	# zone is not yet taken and the same trailer is a live drop.
	var back_pos := Vector3(-8.0, 0, -3.0)
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


# ─── the entry at the blue line (what he picks there: the snapshot) ─────────

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
	_place_keeper(ctx, g)
	return ctx


# Up the wall at speed 4.3 m short of the line: the defender gapping 3.5 m
# ahead, the trailer open in the middle 5 m back.
func _room_at_the_line_ctx() -> RoleContext:
	return _entry_ctx(-3.0, [
			[3, 1, Vector3(-7.5, 0, -7.6), false, Vector3(0, 0, -6.0)],
			[4, 1, Vector3(3.0, 0, -12.0), false, Vector3(0, 0, -5.0)]])


# The same rush a stride further on, with the same room to enter.
func _room_to_plan_in_ctx() -> RoleContext:
	return _entry_ctx(-4.5, [
			[3, 1, Vector3(-7.5, 0, -9.1), false, Vector3(0, 0, -6.0)],
			[4, 1, Vector3(3.0, 0, -13.5), false, Vector3(0, 0, -5.0)]])


# The same rush with a checker on his hip and another sealing the line ahead.
func _smothered_at_the_line_ctx() -> RoleContext:
	return _entry_ctx(-4.5, [
			[3, 1, Vector3(-6.2, 0, -5.3), false, Vector3(0, 0, -7.0)],
			[4, 1, Vector3(-7.0, 0, -7.5), false, Vector3(0, 0, -2.0)]])


func _decided_twice(ctx: RoleContext) -> AIRoleCarrier:
	var c: AIRoleCarrier = _decided(ctx)
	c.decide(ctx)
	return c


# ─── turnover costs are priced in the unit of the gains ─────────────────────

func test_a_turnover_costs_the_opponents_possession_wherever_the_carrier_is() -> void:
	# The carrier's gains are odds of scoring on both sides of the line, so a loss
	# costs the opponent's possession of the spot in odds (AIPossessionValue), for
	# a carrier inside the zone and outside it alike. Same loss point, two carriers.
	var loss := Vector3(-4.0, 0.0, -15.0)
	var c_in := AIRoleCarrier.new()
	c_in.decide(_make_ctx(Vector3(-8.0, 0.0, -16.0)))
	var c_out := AIRoleCarrier.new()
	c_out.decide(_make_ctx(Vector3(-8.0, 0.0, -4.0)))
	var cost_in: float = c_in._field.turnover_cost(loss, 1.0)
	assert_almost_eq(cost_in, c_in._field._theirs.at(loss), 1e-6,
			"a certain loss costs the opponent's possession there")
	assert_almost_eq(c_out._field.turnover_cost(loss, 1.0), cost_in, 1e-6,
			"the same loss costs the same odds from outside the zone")
	assert_gt(c_in._field.turnover_cost(Vector3(-4.0, 0.0, 20.0), 1.0), cost_in,
			"and more in front of our net")


# ─── drive-in: a clear drive is credited all the way ────────────────────────

func test_a_defender_who_never_covers_the_drive_costs_it_nothing() -> void:
	# Carrier at speed up the wall toward the line, the defender retreating ahead.
	# At 5 m and at 8 m he never gets a stick on the drive, so the drive-in (the
	# shot the carrier skates into) must be the same: the full drive to the net,
	# not a drive stopped halfway because halfway was the closer sample.
	# Starting just short of the line: from further back the drive ends where a
	# set keeper concedes nothing, and the comparison reads 0 against 0.
	var v := Vector3(0, 0, -7.0)
	var self_pos := Vector3(-8.0, 0, -6.5)
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
		drive.append(c._field.receiver_drive_in_value(ctx, self_pos, null, v))
	assert_gt(drive[1], 0.0, "precondition: the drive is worth something")
	assert_almost_eq(drive[0], drive[1], 0.005,
			"a defender 5 m ahead who never covers the drive costs it nothing (%.3f vs %.3f)"
			% [drive[0], drive[1]])


func test_the_shot_s_keep_never_discounts_what_the_spot_is_worth_by_position() -> void:
	# Out of the zone with the keeper pulled, value_at weighs the long shot
	# against the spot's horizon value. Losing the puck before the press costs
	# the shot, never the position.
	var self_pos := Vector3(0.0, 0.0, 0.0)
	var ctx: RoleContext = _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	c._field.fill(ctx)
	var pos := Vector3(2.0, 0.0, -5.0)
	var none: Array[Vector3] = []
	var pulled := Vector3(0.0, 0.0, 0.0)
	var position_value: float = c._field.horizon_value(pos)
	var prev: float = INF
	for keep: float in [1.0, 0.5, 0.0]:
		var v: float = c._field.value_at(ctx, pos, self_pos, none, pulled, 0.0, keep)
		assert_gte(v, position_value - 1e-6, "keep %.1f never takes the position value" % keep)
		assert_lte(v, prev + 1e-6, "keep %.1f only ever discounts the shot" % keep)
		prev = v
	assert_almost_eq(c._field.value_at(ctx, pos, self_pos, none, pulled, 0.0, 0.0),
			position_value, 1e-6, "with no keep the spot is worth its position")


func test_in_the_zone_the_keep_discounts_the_shot() -> void:
	var self_pos := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 8.0)
	var ctx: RoleContext = _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	var none: Array[Vector3] = []
	var keeper := ctx.attacking_goal_pos + Vector3(0.0, 0.0, 1.0)
	var kept: float = c._field.value_at(ctx, self_pos, self_pos, none, keeper, 0.0, 1.0)
	assert_gt(kept, 0.0)
	assert_almost_eq(c._field.value_at(ctx, self_pos, self_pos, none, keeper, 0.0, 0.5),
			kept * 0.5, 1e-6)


# ─── O-zone shot selection (what he picks at these: the snapshot) ────────────

# Just inside the blue line, wide open, keeper challenging 2 m off his line.
func _fresh_entry_keeper_ctx() -> RoleContext:
	var ctx := _make_ctx(Vector3(0, 0, -9))
	var g := GoalieNetworkState.new()
	g.position_z = -24.65
	_place_keeper(ctx, g)
	return ctx


# Driving dead-centre at the net at 6 m/s from `dist` out, the keeper backflowed
# 1 m off his line (the live keeper retreats at the carrier's pace).
func _head_on_drive_ctx(dist: float) -> RoleContext:
	var ctx := _make_ctx(Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + dist))
	ctx.self_velocity = Vector3(0.0, 0.0, -6.0)
	var g := GoalieNetworkState.new()
	g.position_z = -GameRules.GOAL_LINE_Z + 1.0
	_place_keeper(ctx, g)
	return ctx


const _ONE_V_ONE_SPOT := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 3.0)


# 3 m out, the keeper squared to the carrier 0.9 m off his line (where the live
# goalie settles on a carrier there); cutting across at 6 m/s with the body
# facing its travel (FacingRules), or flat-footed.
func _one_v_one_ctx(cutting: bool) -> RoleContext:
	var ctx := _make_ctx(_ONE_V_ONE_SPOT)
	if cutting:
		ctx.self_velocity = Vector3(6.0, 0.0, 0.0)
		ctx.snapshot.skater_states[1].velocity = ctx.self_velocity
		ctx.snapshot.skater_states[1].facing = Vector2(1.0, 0.0)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			_ONE_V_ONE_SPOT, Vector3(0.0, 0.0, OPP_NET_Z), 0.9)
	return ctx


# Mid-cut, 1.8 m across at 6 m/s, the keeper a full step behind the arc race
# his accel-capped push lost.
func _beaten_keeper_ctx() -> RoleContext:
	var ctx := _make_ctx(Vector3(1.8, 0.0, -GameRules.GOAL_LINE_Z + 3.0))
	ctx.self_velocity = Vector3(6.0, 0.0, 0.0)
	ctx.snapshot.skater_states[1].velocity = ctx.self_velocity
	ctx.snapshot.skater_states[1].facing = Vector2(1.0, 0.0)
	var lagged := GoalieNetworkState.new()
	lagged.position_x = 0.7
	lagged.position_z = -GameRules.GOAL_LINE_Z + 0.9
	_place_keeper(ctx, lagged)
	return ctx


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
		_place_keeper(ctx, g)
		var c := AIRoleCarrier.new()
		c.decide(ctx)
		assert_gt(c.debug_shoot_score, 0.3,
				"the mid-cut window (goalie at x=%.1f) is a real chance" % gx)
		if c.intended_action == AIRoleCarrier.INTENT_CARRY:
			assert_gt(c.last_carry_anchor.distance_to(pos), 0.5,
					"mid-cut CARRY (goalie at x=%.1f) must be a relocation, not the hold"
					% gx)


# Standing `dist` out dead-centre, the keeper squared 1.3 m off his line.
func _standstill_ctx(dist: float) -> RoleContext:
	var pos := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + dist)
	var ctx := _make_ctx(pos)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	return ctx


func test_range_opens_less_of_the_window_than_in_tight() -> void:
	# Standing against a set keeper there is no phantom IMMEDIATE window at range
	# (the reach budget covers his full deploy). Compared to the same release in
	# tight, not to an absolute bar: the currency's ceiling is a property of
	# whichever shot model is wired in, so "no real window at range" has to be
	# measured against a range that does open one. (What he does at either: the
	# snapshot.)
	var near: float = _decided(_standstill_ctx(3.0)).debug_shoot_score
	var far: float = _decided(_standstill_ctx(9.0)).debug_shoot_score
	assert_lt(far, near, "range opens less of the window than 3 m does; %f vs %f" % [far, near])


# Beat his man down the wing at 8.5 m/s, the beaten man trailing at the same
# pace, far-side low cover, keeper squared 1.2 m out.
func _wing_step_ctx() -> RoleContext:
	var self_pos := Vector3(9.0, 0.0, -14.0)
	var ctx: RoleContext = _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[10, 1 - TEAM_ID, Vector3(9.0, 0.0, -10.0)],
			[11, 1 - TEAM_ID, Vector3(-2.0, 0.0, -23.0)]])
	ctx.self_velocity = Vector3(0.0, 0.0, -8.5)
	ctx.snapshot.skater_states[1].velocity = ctx.self_velocity
	ctx.snapshot.skater_states[10].velocity = Vector3(0.0, 0.0, -8.5)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			self_pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.2)
	return ctx


func _squared_goalie(self_pos: Vector3, net: Vector3, depth: float) -> GoalieNetworkState:
	# Goalie arc-matched to the carrier (as the live keeper is — it tracks the
	# current puck-holder), sitting `depth` out from the net.
	var to_sh: Vector3 = self_pos - net
	to_sh.y = 0.0
	var g: Vector3 = net + to_sh.normalized() * depth
	var gs := GoalieNetworkState.new()
	gs.position_x = g.x
	gs.position_z = g.z
	_face(gs, self_pos)
	return gs


# Turns `g` to face `at`, as the live keeper turns to his threat.
func _face(g: GoalieNetworkState, at: Vector3) -> void:
	g.rotation_y = atan2(-(at.x - g.position_x), -(at.z - g.position_z))


# The opposing keeper at `ctx`, facing the puck.
func _place_keeper(ctx: RoleContext, g: GoalieNetworkState) -> void:
	_face(g, ctx.snapshot.puck_state.position if ctx.snapshot.puck_state != null
			else ctx.self_pos)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g


# ─── where the shot is held (see AIRoleCarrier "Where the shot is held") ─────

# Standing 3 m out with the goalie displaced onto the carrier's BACKHAND side
# (RH default: forehand is +x when attacking -z).
func _backhand_side_keeper_ctx() -> RoleContext:
	var ctx := _make_ctx(Vector3(-1.2, 0.0, -23.5))
	var g := GoalieNetworkState.new()
	g.position_x = -0.8
	g.position_z = -25.0
	_place_keeper(ctx, g)
	return ctx


# Tight beside the net at a dead-sharp angle, the goalie holding the near post.
func _tuck_ctx() -> RoleContext:
	var ctx := _make_ctx(Vector3(2.4, 0.0, -25.6))
	var g := GoalieNetworkState.new()
	g.position_x = 0.85
	g.position_z = -26.1
	_place_keeper(ctx, g)
	return ctx


func test_shot_commit_carries_the_winning_hold() -> void:
	# The mid-cut fire: whatever hold wins the sweep is exactly what the commit
	# exposes to the state machine — where the puck sits at the press and the
	# share its load carries there. The executed shot must be the scored one. The
	# SHOOT ping commits it (a remotely reasonable order wins,
	# docs/gameplay-design.md, smart ping); whether it fires unasked is the
	# snapshot's row.
	var ctx: RoleContext = _beaten_keeper_ctx()
	ctx.ping_shoot_active = true
	var c: AIRoleCarrier = _decided(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_SHOOT, "the pinged mid-cut window fires")
	assert_eq(c.shot_hold_offset, c.shoot_now_hold,
			"the commit exposes exactly the winning hold")
	assert_eq(c.shot_hold_share, c._shot_sample_share, "…and the share it was priced at")


# ~69° off the normal, the keeper squared 1.2 m out.
func _wide_angle_ctx() -> RoleContext:
	var self_pos := Vector3(7.0, 0.0, -24.0)
	var ctx := _make_ctx(self_pos)
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			self_pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.2)
	return ctx


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


# ─── breakout: wall-exit carry routes ───────────────────────────────────────

# Wheeling up the weak-side wall at 5 m/s, no mates, the forecheck set up
# through the middle: one pinching the local up-ice step, another in the
# diagonal slot-drive lane from this wide start.
func _wall_exit_ctx() -> RoleContext:
	var self_pos := Vector3(-10.5, 0, 21)
	var ctx := _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos, false, Vector3(0, 0, -5)],
			[3, 1, Vector3(-7.5, 0, 16.5)],
			[4, 1, Vector3(-6.5, 0, 6)]])
	ctx.self_velocity = Vector3(0, 0, -5)
	return ctx


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
	# A staggered bot does not START a fire: winding up through a body check's
	# stagger flails the release (Scripts/domain/ai/DECISIONS.md, the carrier's
	# commitment: "never while staggered"). The pressured breakout, which fires
	# its pass unstaggered (the snapshot's row), holds the puck instead.
	var ctx: RoleContext = _strong_outlet_ctx()
	ctx.self_stagger_timer = 0.5
	assert_eq(_decided(ctx).intended_action, AIRoleCarrier.INTENT_CARRY,
			"staggered carrier holds instead of committing the fire")


func test_settling_carrier_holds_instead_of_firing() -> void:
	# A carrier still settling a hard catch can't release (the settle lock would
	# only queue the press), so the same breakout holds until the settle ends.
	var ctx: RoleContext = _strong_outlet_ctx()
	ctx.self_settle_s = 0.2
	assert_eq(_decided(ctx).intended_action, AIRoleCarrier.INTENT_CARRY,
			"settling carrier holds instead of committing the fire")


# ─── settle doubt: a fresh carrier's bar for giving the puck up ──────────────

# The same pressured breakout, with the outlet in two different situations. Both
# are legal passes that fire on tick one with no doubt; the strong one is worth
# ~10x PASS_MIN_VALUE, the weak one ~0.9x. Boxed in, the carrier would lose the
# puck where he stands, so the bar's own PASS_MIN_VALUE is off it and what Normal
# holds is under its doubt's raise (1.5x). The weak outlet is still sliding into
# the far corner, so his drive up the wall has to brake that out first. Both
# values are future value and so scale with READ_VALIDITY_TAU_S against a fixed
# bar: re-size the weak one's depth when that moves, never its slide (past 6 m/s
# the lane dies outright).
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
const _MARGINAL_OUTLET := Vector3(9.0, 0, 22.5)  # deep below the dot
const _MARGINAL_OUTLET_VEL := Vector3(0, 0, 0.5)   # …and still drifting into the corner


func _settle_ctx(self_pos: Vector3, outlet: Vector3) -> RoleContext:
	var ctx: RoleContext = _make_ctx(self_pos, _settle_skaters(self_pos, outlet))
	ctx.settle_penalty_frac = 0.6   # Normal's own dial
	ctx.settle_penalty_tau_s = 0.3
	return ctx


# Deep in our zone, boxed by two forecheckers, the strong outlet open up the
# wall; no settle doubt.
func _strong_outlet_ctx() -> RoleContext:
	var self_pos := Vector3(3, 0, 20)
	return _make_ctx(self_pos, _settle_skaters(self_pos, _STRONG_OUTLET))


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
	_place_keeper(ctx, g)
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


# ─── reset() ──────────────────────────────────────────────────────────────

func test_reset_clears_all_persistent_state() -> void:
	var c := AIRoleCarrier.new()
	c.intended_action = AIRoleCarrier.INTENT_PASS
	c.pass_target_peer_id = 42
	c.pass_should_saucer = true
	c.shot_loft_level = ShotMechanics.ELEVATION_HIGH
	c.last_carry_anchor = Vector3(5.0, 0.0, -10.0)

	c.reset()

	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY)
	assert_eq(c.pass_target_peer_id, -1)
	assert_false(c.pass_should_saucer)
	assert_eq(c.shot_loft_level, ShotMechanics.ELEVATION_FLAT)
	assert_eq(c.last_carry_anchor, Vector3.ZERO)


# ─── clear_intent() ───────────────────────────────────────────────────────

func test_clear_intent_resets_intent_but_preserves_carry_anchor() -> void:
	var c := AIRoleCarrier.new()
	c.intended_action = AIRoleCarrier.INTENT_SHOOT
	c.pass_target_peer_id = 42
	c.pass_should_saucer = true
	c.last_carry_anchor = Vector3(5.0, 0.0, -10.0)

	c.clear_intent()

	# Intent + pass target reset; carry anchor preserved (state machine
	# may still be reading it during the press cycle).
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_CARRY)
	assert_eq(c.pass_target_peer_id, -1)
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

func _ctx_with_finisher(fin_pos: Vector3, finisher_ready: bool,
		slot: int = AIRoleSlots.Slot.FINISHER) -> RoleContext:
	# Carrier strong-side in the OZ; a teammate in `slot` staging at fin_pos.
	var self_pos := Vector3(4, 0, -18)
	var ctx := _make_ctx(self_pos, [[1, TEAM_ID, self_pos], [2, TEAM_ID, fin_pos]])
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = slot
	if finisher_ready:
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
	_place_keeper(ctx, g)
	return ctx


func test_developing_feed_zero_without_brain() -> void:
	var ctx := _make_ctx(Vector3(4, 0, -18))
	var carrier := AIRoleCarrier.new()
	carrier._field.teammate_ids = [2]
	assert_eq(carrier._pass.developing_feed_value(ctx), 0.0,
			"no team brain → nothing to wait for")


func test_developing_feed_zero_when_finisher_already_ready() -> void:
	# Already-flagged finisher is fed by normal scoring — not something to hold for.
	var ctx := _ctx_with_finisher(Vector3(-2.5, 0, -21.5), true)
	var carrier := AIRoleCarrier.new()
	carrier._field.teammate_ids = [2]
	assert_eq(carrier._pass.developing_feed_value(ctx), 0.0)


func test_developing_feed_positive_for_staging_cross_seam_finisher() -> void:
	var ctx := _ctx_with_finisher(Vector3(-2.5, 0, -21.5), false)
	var carrier := AIRoleCarrier.new()
	carrier._field.teammate_ids = [2]
	assert_gt(carrier._pass.developing_feed_value(ctx), 0.0,
			"a staging cross-seam finisher gives a positive developing feed")


func test_the_net_front_man_is_waited_for_like_the_finisher() -> void:
	# 5v5's NET_FRONT runs the finisher's role, so a feed he is still skating
	# into is the same developing play.
	var fin := AIRoleCarrier.new()
	fin._field.teammate_ids = [2]
	var nf := AIRoleCarrier.new()
	nf._field.teammate_ids = [2]
	var spot := Vector3(-2.5, 0, -21.5)
	assert_almost_eq(
			nf._pass.developing_feed_value(
					_ctx_with_finisher(spot, false, AIRoleSlots.Slot.NET_FRONT)),
			fin._pass.developing_feed_value(_ctx_with_finisher(spot, false)), 1e-6)


func test_developing_feed_invisible_without_the_cognition_gate() -> void:
	# Same staging finisher the test above values positively — but a tier that
	# doesn't hold for developing plays (Easy) sees nothing: it plays only what
	# exists right now.
	var ctx := _ctx_with_finisher(Vector3(-2.5, 0, -21.5), false)
	ctx.holds_for_developing_feeds = false
	var carrier := AIRoleCarrier.new()
	carrier._field.teammate_ids = [2]
	assert_eq(carrier._pass.developing_feed_value(ctx), 0.0,
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
	_place_keeper(ctx, gs)
	assert_gt(AICarrierField.goalie_unsettled_at(ctx, 0.2, self_pos), 0.0,
			"an off-square keeper on a short release reads unsettled")
	ctx.reads_goalie_motion = false
	assert_eq(AICarrierField.goalie_unsettled_at(ctx, 0.2, self_pos), 0.0,
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
	carrier._field.teammate_ids = [2]
	assert_eq(carrier._pass.developing_feed_value(ctx), 0.0,
			"a ghosted finisher isn't a developing play — nothing to hold for")


func test_developing_feed_zero_when_finisher_out_of_offensive_zone() -> void:
	# Finisher back in the neutral zone (z = -5 > -BLUE_LINE_Z) → not a cross-seam.
	var ctx := _ctx_with_finisher(Vector3(-3, 0, -5), false)
	var carrier := AIRoleCarrier.new()
	carrier._field.teammate_ids = [2]
	assert_eq(carrier._pass.developing_feed_value(ctx), 0.0,
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
	c1._field.teammate_ids = [2]
	assert_eq(c1._pass.developing_feed_value(parked), 0.0,
			"parked outside the line: nothing developing")
	var driving := _ctx_with_finisher(fin_pos, false)
	driving.snapshot.skater_states[2].velocity = Vector3(1.0, 0, -8.5)
	var c2 := AIRoleCarrier.new()
	c2._field.teammate_ids = [2]
	assert_gt(c2._pass.developing_feed_value(driving), 0.0,
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
	c1._field.teammate_ids = [2]
	var feed_parked: float = c1._pass.developing_feed_value(parked)
	var driving := _ctx_with_finisher(fin_pos, false)
	driving.snapshot.skater_states[2].velocity = Vector3(2.5, 0, -6.5)
	var c2 := AIRoleCarrier.new()
	c2._field.teammate_ids = [2]
	assert_gt(c2._pass.developing_feed_value(driving), feed_parked,
			"the feed is valued at the spot the finisher is getting to")


# Seconds after a zone entry: box set, the carry strangled by a high man, the
# FINISHER driving to the house, SUPPORT high at the line, the keeper tracking.
# The set D box sits strong side, deliberately clear of the carrier → finisher
# lane: a defender parked in that lane makes the feed honestly worse than the shot.
func _fresh_entry_finisher_ctx() -> RoleContext:
	var self_pos := Vector3(2, 0, -14.5)
	var ctx := _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(-5, 0, -15.0), false, Vector3(0.8, 0, -7.5)],
			[3, TEAM_ID, Vector3(6, 0, -6.3)],
			[11, 1, Vector3(1.5, 0, -20.5)],
			[12, 1, Vector3(2.5, 0, -19.0)],
			[13, 1, Vector3(0.5, 0, -11.3)]])
	var g := GoalieNetworkState.new()
	g.position_x = 0.45
	g.position_z = -26.65 + 1.3
	_place_keeper(ctx, g)
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = AIRoleSlots.Slot.FINISHER
	brain.slot_assignments[3] = AIRoleSlots.Slot.SUPPORT
	ctx.team_brain = brain
	return ctx


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
	carrier._field.fill(ctx)
	carrier._field.teammate_ids = [2]
	assert_gt(carrier._pass.developing_feed_value(ctx), 0.0,
			"an outlet skating up its route is a developing feed worth holding for")


func test_developing_feed_zero_for_stationary_outlet() -> void:
	# A parked outlet offers exactly the spot it's at — the live pass
	# scoring already prices that; nothing is developing.
	var ctx := _ctx_with_outlet(Vector3(9, 0, 16), Vector3.ZERO)
	var carrier := AIRoleCarrier.new()
	carrier._field.teammate_ids = [2]
	assert_eq(carrier._pass.developing_feed_value(ctx), 0.0,
			"a stationary outlet isn't developing anything")


func test_developing_feed_zero_for_ghosted_outlet() -> void:
	var ctx := _ctx_with_outlet(Vector3(9, 0, 16), Vector3(1.2, 0, -6), true)
	var carrier := AIRoleCarrier.new()
	carrier._field.teammate_ids = [2]
	assert_eq(carrier._pass.developing_feed_value(ctx), 0.0,
			"a ghosted outlet can't receive — no developing feed")


func test_developing_outlet_beats_the_spot_it_left_behind() -> void:
	# The whole point of the hold: the pass the outlet is CREATING
	# (projected up its route, toward open ice) out-values the pass to
	# where it currently stands. Compare the developing feed of a moving
	# outlet against one parked at the same spot but projected nowhere.
	var moving := _ctx_with_outlet(Vector3(9, 0, 16), Vector3(1.2, 0, -6))
	var carrier := AIRoleCarrier.new()
	carrier._field.fill(moving)
	carrier._field.teammate_ids = [2]
	var developing: float = carrier._pass.developing_feed_value(moving)

	# The same feed valued AT the outlet's current spot: reuse _pass_ev
	# directly so both sides run identical pricing.
	var spot := Vector3(9, 0, 16)
	var dist: float = moving.self_pos.distance_to(spot)
	var pass_speed: float = AIPuckLane.pass_launch_speed(
			dist, moving.self_wrister_shot_speed, moving.pass_speed_scale)
	var flight_t: float = clampf(dist / pass_speed, 0.0, AICarrierPassSearch.PASS_LEAD_MAX_S)
	var carrier2 := AIRoleCarrier.new()
	carrier2._field.fill(moving)
	carrier2._field.teammate_ids = [2]
	var stay_put: float = carrier2._pass._pass_ev(
			moving, spot, pass_speed, flight_t,
			flight_t + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S, flight_t,
			moving.defending_goal_pos)

	assert_gt(developing, stay_put,
			"the projected up-ice spot out-values the spot the outlet is leaving")


# Pressured deep in our zone by a charging forechecker: the strong-side outlet
# skating its route, and a deep valve behind us as backpass bait.
func _developing_outlet_and_valve_ctx() -> RoleContext:
	var self_pos := Vector3(2, 0, 20)
	var ctx := _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(9, 0, 16), false, Vector3(1.2, 0, -6)],
			[5, TEAM_ID, Vector3(-3, 0, 24)],
			[3, 1, Vector3(2, 0, 17.5), false, Vector3(0, 0, 5)]])
	var brain := TeamBrain.new(TEAM_ID, ctx.team_id_by_peer)
	brain.slot_assignments[2] = AIRoleSlots.Slot.BREAKOUT_STRONG
	brain.slot_assignments[5] = AIRoleSlots.Slot.BREAKOUT_WEAK
	ctx.team_brain = brain
	return ctx


# ─── under pressure: the snapshot's relief fixtures ──────────────────────────

# Deep in our slot with three forecheckers converging, flanks opposed so the
# protect budget splits: on the blade (`tight`), or a stride looser.
func _own_slot_swarm_ctx(tight: bool) -> RoleContext:
	var self_pos := Vector3(6, 0, 24)
	if tight:
		return _make_ctx(self_pos, [
				[1, TEAM_ID, self_pos],
				[3, 1, Vector3(6, 0, 22.2), false, Vector3(0, 0, 5)],
				[4, 1, Vector3(4.6, 0, 24.6)],
				[5, 1, Vector3(7.4, 0, 24.6)]])
	return _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(6, 0, 20.0), false, Vector3(0, 0, 5)],
			[4, 1, Vector3(3.2, 0, 24.6)],
			[5, 1, Vector3(8.8, 0, 24.6)]])


# Past centre, short of their blue line, nothing to pass to: a set stand-up line
# (head D at gap, flankers bracketing both swing lanes), or a loose pair — one D
# backing off, one wide of the lane.
func _contained_past_centre_ctx(walled: bool) -> RoleContext:
	var self_pos := Vector3(2, 0, -4)
	if walled:
		return _make_ctx(self_pos, [
				[1, TEAM_ID, self_pos],
				[3, 1, Vector3(-4, 0, -6)],
				[4, 1, Vector3(2, 0, -5.5)],
				[5, 1, Vector3(8, 0, -6)]])
	return _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[3, 1, Vector3(2, 0, -5), false, Vector3(0, 0, -4)],
			[4, 1, Vector3(-1, 0, -5.5)]])


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


# Pinned in the DZ by a head-on forecheck, a teammate wide open up the strong wall.
func _pinned_with_an_outlet_ctx() -> RoleContext:
	var self_pos := Vector3(8, 0, 20)
	return _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(11, 0, 11)],
			[3, 1, Vector3(8, 0, 17), false, Vector3(0, 0, 4)],
			[4, 1, Vector3(5.5, 0, 19)]])


# ─── NHL icing and delayed offside ────────────────────────────────────────────

func test_delayed_offside_closes_the_zone_to_the_carry() -> void:
	var self_pos := Vector3(0, 0, -5)  # neutral ice, attacking -Z
	var ctx := _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	c._field.fill(ctx)
	var goalie: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var in_zone := Vector3(0, 0, -9)
	assert_gt(c._carry._score_move_candidate_base(ctx, in_zone, goalie), -INF,
			"an open entry is a candidate")
	ctx.zone_entry_blocked = true
	assert_eq(c._carry._score_move_candidate_base(ctx, in_zone, goalie), -INF,
			"with a teammate owing a tag-up, carrying in would be whistled")


# ─── AICarrierPassSearch._facing_rotation_time: the blade reach cone (Aim-B / B1) ────────────────
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
	return c._pass._facing_rotation_time(facing_xz, Vector3.ZERO, target, cone, rate)


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
	# 6 m out, where the puck's own spot is the winning hold (further out a side
	# pocket wins either way, and the read cannot see which point it came from).
	var self_pos := Vector3(0, 0, -20.65)
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


# ─── Blue line: a mate level at the line ────────────────────────────────────

# Carrier and a mate level a metre short of the blue line at 6 m/s, defenders set
# inside the zone at a normal contain gap (symmetric coverage), keeper set.
func _symmetric_entry_ctx() -> RoleContext:
	var self_pos := Vector3(-4, 0, -(GameRules.BLUE_LINE_Z - 1.0))
	var ctx := _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos, false, Vector3(0, 0, -6)],
			[2, TEAM_ID, Vector3(4, 0, self_pos.z), false, Vector3(0, 0, -6)],
			[11, 1, Vector3(-3.5, 0, -12.0)],
			[12, 1, Vector3(3.5, 0, -12.0)]])
	ctx.self_velocity = Vector3(0, 0, -6)
	return _set_keeper(ctx)


# ─── Post-seal stances: the carrier reads the VH wall ────────────────────────

func test_post_seal_x_sign_decodes_the_wire_convention() -> void:
	# Convention lock: the sealed post of a *_LEFT stance sits at world-x
	# sign(−goal_z). Both nets, both stance families.
	var g := GoalieNetworkState.new()
	g.state_enum = GoalieStateMachine.State.VH_LEFT as int
	assert_eq(g.post_seal_x_sign(-26.65), 1.0, "net at −z: LEFT seals the +x post")
	assert_eq(g.post_seal_x_sign(26.65), -1.0, "net at +z: LEFT seals the −x post")
	g.state_enum = GoalieStateMachine.State.RVH_RIGHT as int
	assert_eq(g.post_seal_x_sign(-26.65), -1.0, "net at −z: RIGHT seals the −x post")
	g.state_enum = GoalieStateMachine.State.READY as int
	assert_eq(g.post_seal_x_sign(-26.65), 0.0, "no post stance, no seal")


func test_sharp_angle_shot_into_an_rvh_seal_is_never_worth_firing() -> void:
	# In tight at a sharp angle with the keeper sealed in the RVH on the near
	# post (the field's WRAP cells measure him there), the shot into the seal
	# from where the carrier stands is no chance. x = 4 is a measured column of
	# the field. (Pulling the puck off the line first is a different shot,
	# priced from the field's decoy cells.)
	var self_pos := Vector3(4.0, 0, -26.0)
	var goal := Vector3(0.0, 0.0, OPP_NET_Z)
	# His net frame is the world's turned half round for a net at −z: his
	# −x post is the world's +x one.
	var sealed: Vector2 = KeeperPost.new().seal_spot(Vector2(-GameRules.NET_HALF_WIDTH, 0.0), -1.0)
	var g_rvh := GoalieNetworkState.new()
	g_rvh.position_x = goal.x - sealed.x
	g_rvh.position_z = goal.z - sealed.y
	g_rvh.state_enum = GoalieStateMachine.State.RVH_LEFT as int   # seals +x here
	_face(g_rvh, self_pos)
	var keeper := Vector3(g_rvh.position_x, 0.0, g_rvh.position_z)
	var into_the_seal: float = AIActionScoring.score_shoot_value(
			AIGoalieModel.release_ahead_of_goalie(self_pos, goal, keeper), goal, keeper,
			[] as Array[Vector3], 0.0, AIShotOdds.stance_of(g_rvh, goal),
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, [], -1.0, g_rvh.rotation_y)
	assert_gt(keeper.x, 0.0, "sealed on the +x post")
	assert_lt(into_the_seal, AIRoleCarrier.SHOT_MIN_VALUE,
			"the shot into the seal offers no real chance; got %f" % into_the_seal)


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
	c._field.fill(ctx)
	var in_band := Vector3(0.0, 0.0,
			-(GameRules.BLUE_LINE_Z + AICarrierCarrySearch.OZ_RETREAT_LINE_BUFFER_M * 0.5))
	var past_band := Vector3(0.0, 0.0,
			-(GameRules.BLUE_LINE_Z + AICarrierCarrySearch.OZ_RETREAT_LINE_BUFFER_M + 1.0))
	assert_eq(c._carry._score_move_candidate(ctx, in_band, ctx.defending_goal_pos), -INF,
			"a retreat to within windup reach of the blue line is pruned")
	assert_gt(c._carry._score_move_candidate(ctx, past_band, ctx.defending_goal_pos), -INF,
			"a retreat that keeps the windup envelope inside the zone stays legal")


func test_nz_carrier_may_target_entry_candidates_near_the_line() -> void:
	# The valve (and its band) only binds a carrier ALREADY in the zone —
	# an entry candidate just across the line must stay legal or the
	# carrier could never enter at all.
	var self_pos := Vector3(0.0, 0.0, -5.0)   # neutral zone
	var ctx := _make_ctx(self_pos)
	var c := AIRoleCarrier.new()
	c._field.fill(ctx)
	var just_inside := Vector3(0.0, 0.0, -(GameRules.BLUE_LINE_Z + 0.7))
	assert_gt(c._carry._score_move_candidate(ctx, just_inside, ctx.defending_goal_pos), -INF,
			"an entry candidate in the band is not pruned from outside the zone")


# The carrier's pass search for mate 2 at `ctx`.
func _best_pass_to_mate(ctx: RoleContext) -> AICarrierPassSearch:
	var c := AIRoleCarrier.new()
	c._field.fill(ctx)
	c._pass.search(ctx, Vector2(0.0, -1.0), [2])
	return c._pass


func test_oz_pass_skips_receiver_hugging_the_blue_line() -> void:
	# Carrier in the OZ; the only teammate is wide open but his tape sits
	# just inside the blue line — reception slop there takes the puck out
	# of the zone, so he is excluded as a target entirely. The same open
	# man past the keep-out band (the far-post backdoor the squared goalie
	# can't re-square onto) is a legal (positive) feed.
	var at_line := Vector3(-2.5, 0.0, -(GameRules.BLUE_LINE_Z + 0.5))
	assert_eq(_best_pass_to_mate(_backdoor_ctx(at_line)).best_score, 0.0,
			"a receiver hugging the blue line is not a pass target from inside the zone")
	assert_gt(_best_pass_to_mate(_backdoor_ctx(_BACKDOOR_MATE)).best_score, 0.0,
			"the same open man past the keep-out band is a legal feed")


# ─── close-quarters saucer variant ───────────────────────────────────────────

# A feed straight up-ice from (0, 0, 10) to a receiver at `receiver_z`, a
# defender's stick mid-lane at `stick_z` with his body 0.7 m off the line.
func _mid_lane_feed_ctx(receiver_z: float, stick_z: float) -> RoleContext:
	var self_pos := Vector3(0.0, 0.0, 10.0)
	return _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(0.0, 0.0, receiver_z)],
			[3, 1, Vector3(0.7, 0.0, stick_z)]])


func test_short_feed_below_saucer_floor_stays_grounded() -> void:
	# At 5.5 m even the softest legal flip (min wrister pace) can't land with
	# runway, so no saucer variant exists and the pass stays flat whatever the
	# lane looks like. (Which variant the 8 m feed takes is the snapshot's row.)
	assert_false(_best_pass_to_mate(_mid_lane_feed_ctx(4.5, 7.5)).best_is_saucer,
			"below the physical saucer floor the feed stays grounded")


const _SAUCER_PASSER := Vector3(3.0, 0.0, 5.0)
const _SAUCER_RECEIVER := Vector3(3.0, 0.0, -4.0)


# Neutral ice, a 9 m ahead-man behind a mid-lane stick, two forecheckers
# pressuring the carry, and the receiver's PASS_TO_ME ping.
func _pinged_saucer_ctx() -> RoleContext:
	var ctx := _make_ctx(_SAUCER_PASSER, [
			[1, TEAM_ID, _SAUCER_PASSER],
			[2, TEAM_ID, _SAUCER_RECEIVER],
			[3, 1, Vector3(3.7, 0.0, 2.5)],
			[4, 1, Vector3(1.5, 0.0, 7.0)],
			[5, 1, Vector3(4.5, 0.0, 6.5)]])
	ctx.ping_pass_target_peer = 2
	return ctx


func test_committed_saucer_pass_caps_launch_at_the_receivability_bound() -> void:
	# Full decide(): a committed saucer's launch speed is capped at the
	# receivability bound for the distance — the genuinely soft flip — never the
	# crisp magnet pace that would arrive still airborne and sail over the
	# receiver's blade. The PASS_TO_ME ping commits the feed (a remotely
	# reasonable order wins, docs/gameplay-design.md, smart ping); which variant
	# wins is the snapshot's row.
	var c: AIRoleCarrier = _decided(_pinged_saucer_ctx())
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_PASS, "the pinged feed is committed")
	if not c.pass_should_saucer:
		pending("the fixture no longer commits the saucer (see the snapshot); the cap is untested")
		return
	var bound: float = AIPuckLane.saucer_max_launch_speed(
			_SAUCER_PASSER.distance_to(_SAUCER_RECEIVER))
	assert_lt(c.pass_target_speed, bound + 0.01,
			"committed saucer launch is capped so the flip lands before the tape")
	assert_gt(c.pass_target_speed,
			AIPuckLane.SOFTEST_FEED_M_S - 0.01,
			"committed saucer launch stays at/above the softest feed")


# ─── puck-protect mirror (blade shielding read by the state machine) ─────────

func test_no_shot_is_even_scored_from_outside_the_zone() -> void:
	# The shot eval is skipped entirely outside the attacking zone while the
	# keeper is HOME — the same proof threat_of_carrier and _score_at already
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
	_place_keeper(ctx, home)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_lt(c.debug_shoot_score, 0.0,
			"no shot is scored at all from our own zone against a home keeper")
	assert_ne(c.intended_action, AIRoleCarrier.INTENT_SHOOT,
			"…so SHOOT cannot win the compete by any route")

	# Even ordered to shoot by a teammate's smart ping, which biases the shot
	# score: the bias multiplies a score that was never computed.
	var pinged := _make_ctx(self_pos, [[1, TEAM_ID, self_pos]])
	_place_keeper(pinged, home)
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
	_place_keeper(empty, pulled)
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


const _PROTECT_SPOT := Vector3(0, 0, 5)


# The carrier standing at _PROTECT_SPOT with a defender `ahead_m` in front of him
# on the play line (attack is -Z), or alone when `ahead_m` is INF.
func _frontal_threat(ahead_m: float) -> AIRoleCarrier:
	var skaters: Array = [[1, TEAM_ID, _PROTECT_SPOT]]
	if is_finite(ahead_m):
		skaters.append([3, 1, _PROTECT_SPOT + Vector3(0, 0, -ahead_m)])
	return _decided(_make_ctx(_PROTECT_SPOT, skaters))


func test_a_frontal_stick_threat_earns_the_shield() -> void:
	# A defender 1.6 m ahead has his stick on the presented forward puck while the
	# back hip is out of his reach: the shield buys real safety. (Where it pulls
	# the puck is the snapshot's row.)
	assert_gt(_frontal_threat(1.6).protect_gain, 0.0,
			"a stick on the presented spot, with a safe hip to hide it, earns the shield")


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


# Degrees between the protect seam and the carry line (0 = on the play line,
# 180 = straight behind the body), for a carrier driving at the -Z net at 7 m/s
# with a containing defender 3 m ahead and `dx` off the line.
func _shield_seam_deg(dx: float) -> float:
	var self_pos := Vector3(0, 0, -2)
	var vel := Vector3(0, 0, -7)
	var ctx: RoleContext = _make_ctx(self_pos, [
			[1, TEAM_ID, self_pos, false, vel],
			[3, 1, Vector3(dx, 0, -5.0), false, Vector3(0, 0, -3)]])
	ctx.self_velocity = vel
	var off: Vector3 = _decided(ctx).protect_offset
	return absf(rad_to_deg(Vector2(0, -1).angle_to(Vector2(off.x, off.z))))


func test_the_shield_goes_only_as_far_off_the_play_line_as_it_must() -> void:
	# The seam is DIRECTED at the presented-forward spot, not a max-clearance
	# read, which against any checker in front returns the back hip — on neither
	# a shot nor a pass. So the shield GRADES: as the same defender moves off the
	# carry line, the seam walks back toward it rather than staying pinned behind.
	# (Where it sits at each: the snapshot's rows.)
	var on_line: float = _shield_seam_deg(0.0)
	var stepped_off: float = _shield_seam_deg(1.0)
	assert_lt(stepped_off, on_line,
			"step him off the line and the puck comes back toward it (%.0f vs %.0f deg)"
			% [stepped_off, on_line])


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


# ─── OZ possession retention (what he picks: the snapshot) ──────────────────

# Sharp-angle corner carrier, the keeper squared and sealing the angle, a
# defender boxing out the net-side path.
func _sealed_corner_ctx() -> RoleContext:
	var self_pos := Vector3(9.0, 0.0, -24.0)
	var ctx := _make_ctx(self_pos, [[1, TEAM_ID, self_pos], [3, 1, Vector3(7.5, 0.0, -24.8)]])
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			self_pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	return ctx


# ─── behind the net ─────────────────────────────────────────────────────────

const _BEHIND_THEIR_CAGE := Vector3(0.4, 0.0, OPP_NET_Z - 1.9)
const _BEHIND_OUR_CAGE := Vector3(0.4, 0.0, OUR_NET_Z + 1.9)


func test_oz_carrier_behind_the_net_carries_it() -> void:
	# A release on or behind the goal line scores 0 — the wraparound is a carry,
	# not a shot (Scripts/domain/ai/CLAUDE.md, shot geometry) — and alone there is
	# nobody to pass to, so behind their cage the carrier carries. (Which way —
	# the post walkout or along the back of the cage — is the snapshot's row.)
	assert_eq(_decided(_make_ctx(_BEHIND_THEIR_CAGE)).intended_action,
			AIRoleCarrier.INTENT_CARRY, "nothing to fire from behind the cage — carry it")


# ─── space creation: retreat ring + pass optionality ─────────────────────────

func test_pass_option_prefers_the_spot_that_reopens_the_lane() -> void:
	# Pure option read: same cached receiver, two candidate spots — one whose
	# lane to him is walled by a defender, one with a clear lane. The clear
	# spot inherits (a discounted cut of) the receiver's value.
	var ctx := _make_ctx(Vector3.ZERO)
	var c := AIRoleCarrier.new()
	c._field.receiver_pos.append(Vector3(-8.0, 0.0, 0.0))
	c._field.receiver_val.append(0.12)
	c._field.opponents.append(Vector3(-4.0, 0.0, 0.0))    # parked on the direct lane
	c._field.opponent_vels.append(Vector3.ZERO)
	c._field.opponent_caps.append(null)
	var blocked: float = c._field.pass_option_from(ctx, Vector3.ZERO)
	var open: float = c._field.pass_option_from(ctx, Vector3(0.0, 0.0, 8.0))
	assert_gt(open, blocked + 0.02,
			"the spot with the reopened lane inherits real receiver value")
	assert_lt(open, 0.12, "the option is a discounted cut, never par with a live pass")


const _PINCH_SPOT := Vector3(0.0, 0.0, -18.0)     # OZ, attacking -Z
const _TIGHT_WALL_HALF_GAP: float = 0.5           # 1.0 m apart: no seam for a body or a puck
# 6 m up the middle: each man ~3 m off the carrier's line, past his full reach
# and the poke's contact (AICarrySpace._crossing_span), so the seam is real.
const _SPLITTABLE_HALF_GAP: float = 3.0


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


func test_a_wider_gap_never_makes_the_carry_worth_less() -> void:
	# Between the pinch and the split, opening the gap only ever gives the carrier
	# more room: the carry is never worth less.
	var prev: float = -INF
	for half_gap: float in [_TIGHT_WALL_HALF_GAP, 0.9, 1.3, 1.7, 2.1, 2.5, _SPLITTABLE_HALF_GAP]:
		var v: float = _pinch(half_gap)._carry.raw_value
		assert_gte(v, prev - 1e-4,
				"gap %.1f m: the carry is worth less (%.3f after %.3f)"
				% [2.0 * half_gap, v, prev])
		prev = v


# Entering down the wing in stride, a defender on the inside lane, the keeper
# squared 1.3 m out.
func _wing_entry_inside_d_ctx() -> RoleContext:
	var self_pos := Vector3(8.0, 0.0, -18.0)
	var vel := Vector3(-1.0, 0.0, -3.0)
	var ctx := _make_ctx(self_pos, [[1, TEAM_ID, self_pos, false, vel], [3, 1, Vector3(3.0, 0.0, -20.0)]])
	ctx.self_velocity = vel
	ctx.snapshot.goalie_states[1 - TEAM_ID] = _squared_goalie(
			self_pos, Vector3(0.0, 0.0, OPP_NET_Z), 1.3)
	return ctx


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
	return c._carry._score_move_candidate(ctx, spot, Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z))


func test_spun_off_carrier_prices_the_cut_in_over_escape_and_standing() -> void:
	# The continuation credit makes the drive TOWARD the net worth more than a
	# safety orbit around the perimeter. Momentum matters: time_to_arrive charges
	# the cost of shedding sideways speed, so this carrier's momentum already
	# points at the cut; one moving laterally away could not reach it before the
	# beaten man recovered (test_continuation_credit_respects_live_containment).
	# (Where he commits, and by how much the cut beats standing: the snapshot.)
	var ctx: RoleContext = _spun_off_ctx()
	var c: AIRoleCarrier = _decided(ctx)
	var cut_score: float = _move_score(c, ctx, _spun_off_cut_in())
	assert_gt(cut_score, _move_score(c, ctx, Vector3(8.2, 0.0, -17.0)),
			"the cut-in's continuation beats the lateral escape's marginal safety")
	# Stand-still is the noise floor, and it is in the compete already: the plan
	# has to beat doing nothing.
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
	assert_gt(c._carry._score_move_candidate(ctx, lateral, our_goalie),
			c._carry._score_move_candidate(ctx, cut_in, our_goalie),
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
	assert_true(AICarrierDestinations.is_wheel(c._carry.destination_kind),
			"it carries for the wheel")
	assert_lt(c._carry.destination.x, -5.0, "out the FAR side of the cage")
	assert_lt(c._carry.destination.z, 22.0, "...up the far wall, not a near-post step")
	assert_lt(c.last_carry_anchor.x, self_pos.x, "and skates across behind the cage to it")
	assert_gt(c.last_carry_anchor.z, GameRules.GOAL_LINE_Z, "...round the back, not into it")


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
	carrier._field.fill(ctx)
	carrier._field.teammate_ids = [2]
	assert_gt(carrier._pass.developing_feed_value(ctx), 0.0,
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
	_place_keeper(ctx, g)
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
	assert_true(c._carry._candidate_ice_legal(
			Vector3(-3.0, 0.0, behind.z), true),
			"the walk across the back of the cage is a representable move")
	assert_true(c._carry._candidate_ice_legal(
			Vector3(6.0, 0.0, behind.z + 1.0), true),
			"so is working out toward the corner")


func test_the_cage_itself_is_still_not_a_place_to_stand() -> void:
	var c := AIRoleCarrier.new()
	assert_false(c._carry._candidate_ice_legal(
			Vector3(0.0, 0.0, OPP_NET_Z - GameRules.NET_DEPTH * 0.5), true),
			"inside the goal frame is not ice")


func test_behind_net_candidates_stay_on_the_playing_surface() -> void:
	var c := AIRoleCarrier.new()
	assert_false(c._carry._candidate_ice_legal(
			Vector3(3.0, 0.0, -(GameRules.INNER_HALF_LENGTH + 0.5)), true),
			"through the end boards is not ice")
	assert_false(c._carry._candidate_ice_legal(
			Vector3(GameRules.CORNER_CENTER_X + GameRules.INNER_CORNER_RADIUS,
					0.0, GameRules.CORNER_CENTER_Z + 3.0), true),
			"and the rounded corner is honoured, not a bounding box")


func test_a_carrier_out_front_keeps_the_old_goal_line_clamp() -> void:
	# Scoped change: nothing about front-of-net carrying moves.
	var c := AIRoleCarrier.new()
	assert_false(c._carry._candidate_ice_legal(
			Vector3(3.0, 0.0, OPP_NET_Z - 1.6), false),
			"a carrier in front never plans a step past the goal line")
	assert_true(c._carry._candidate_ice_legal(Vector3(3.0, 0.0, -18.0), false))


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
		best = maxf(best, c._pass._rim_sure_by_k[k])
	var softest: float = INF
	var hardest: float = 0.0
	for k: int in AIRimPass.count:
		if c._pass._rim_sure_by_k[k] >= best * AICarrierPassSearch.RIM_SOFT_SHARE:
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


# A spot on the ice as (x, z), rounded to 10 cm; adding 0.0 folds a -0.0 into 0.0.
func _spot(v: Vector3) -> String:
	return "(%.1f, %.1f)" % [snappedf(v.x, 0.1) + 0.0, snappedf(v.z, 0.1) + 0.0]


# The committed intent with its target: the receiver of a pass, the anchor of a
# carry.
func _pick(c: AIRoleCarrier) -> String:
	if c.intended_action == AIRoleCarrier.INTENT_PASS:
		return "PASS to %d" % c.pass_target_peer_id
	if c.intended_action == AIRoleCarrier.INTENT_CARRY:
		return "CARRY to %s" % _spot(c.last_carry_anchor)
	return _intent_name(c.intended_action)


func _variant(saucer: bool) -> String:
	return "SAUCER" if saucer else "FLAT"


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
	var pinch: AIRoleCarrier = _pinch(_TIGHT_WALL_HALF_GAP)
	snap.record("tight-wall pinch, open man wide: intent", _intent_name(pinch.intended_action))
	snap.record("tight-wall pinch, open man wide: pass target", pinch.pass_target_peer_id)
	snap.record("dead slot over the 8.5 m band, set keeper: shoot-now ratio",
			_shoot_now(_DEAD_SLOT, _DEAD_SLOT) / _shoot_now(_MID_BAND, _MID_BAND))
	var spun_ctx: RoleContext = _spun_off_ctx()
	var spun: AIRoleCarrier = _decided(spun_ctx)
	snap.record("spun-off carrier, cut-in over standing still: move-score margin",
			_move_score(spun, spun_ctx, _spun_off_cut_in())
			- _move_score(spun, spun_ctx, _SPUN_OFF_SPOT))
	snap.record("tight-wall pinch, open man wide: carry anchor", _spot(pinch.last_carry_anchor))
	snap.record("spun-off carrier, beaten man behind: pick", _pick(spun))
	_record_feed_and_pressure_picks(snap)
	_record_entry_and_finish_picks(snap)
	_record_relief_and_breakout_picks(snap)
	_record_zone_play_picks(snap)
	snap.verify(self)


func _record_feed_and_pressure_picks(snap: Snapshot) -> void:
	snap.record("pressured deep in our zone, open outlet up the strong wall: pick",
			_pick(_decided(_strong_outlet_ctx())))
	snap.record("outlet straight up the wall, forechecker standing off the lane: pick",
			_pick(_decided(_lane_forechecker_ctx(Vector3.ZERO))))
	snap.record("wide in the zone, open man at the far-post backdoor: pick",
			_pick(_decided(_backdoor_ctx(_BACKDOOR_MATE))))
	snap.record("our end, middle clogged, winger ahead with a clear path: pick",
			_pick(_decided(_clogged_middle_ctx())))
	snap.record("central in the zone, open mate wide at a poor angle: intent",
			_intent_name(_decided(_poor_spot_mate_ctx()).intended_action))
	snap.record("neutral ice, straight lane clogged, close outlet up-ice: pick",
			_pick(_decided(_close_outlet_ctx())))
	snap.record("8 m feed past a mid-lane stick: variant",
			_variant(_best_pass_to_mate(_mid_lane_feed_ctx(2.0, 6.5)).best_is_saucer))
	snap.record("pinged ahead man 9 m out behind a mid-lane stick: variant",
			_variant(_decided(_pinged_saucer_ctx()).pass_should_saucer))
	snap.record("board pincer closing, open outlet across: pick", _pick(_decided(_pincer_ctx())))
	snap.record("light pressure, only a covered mate behind: intent",
			_intent_name(_decided(_covered_backpass_ctx()).intended_action))
	snap.record("deep in our zone, forechecker charging, only a deeper mate: intent",
			_intent_name(_decided(_deep_backpass_ctx()).intended_action))
	snap.record("deep in our zone, alone, forechecker charging, flanks open: pick",
			_pick(_decided(_lone_forechecker_ctx())))
	snap.record("pressured deep, outlet en route, deeper valve as bait: pick",
			_pick(_decided(_developing_outlet_and_valve_ctx())))


func _record_entry_and_finish_picks(snap: Snapshot) -> void:
	snap.record("alone at rest 0.8 m short of the blue line: pick",
			_pick(_decided(_make_ctx(_SHORT_OF_THE_BLUE_LINE))))
	snap.record("rush up the wall 4.3 m short of the line, room to enter: intent",
			_intent_name(_decided_twice(_room_at_the_line_ctx()).intended_action))
	snap.record("rush up the wall 5.8 m short of the line, room to enter: pick",
			_pick(_decided_twice(_room_to_plan_in_ctx())))
	snap.record("rush up the wall, smothered at the line, trailer open: pick",
			_pick(_decided_twice(_smothered_at_the_line_ctx())))
	snap.record("level with a mate at the blue line, symmetric set D: intent",
			_intent_name(_decided(_symmetric_entry_ctx()).intended_action))
	snap.record("2 m inside the blue line, open, keeper 2 m out: pick",
			_pick(_decided(_fresh_entry_keeper_ctx())))
	var fresh_ctx: RoleContext = _fresh_entry_finisher_ctx()
	var fresh: AIRoleCarrier = _decided(fresh_ctx)
	snap.record("fresh entry, finisher driving the house: intent",
			_intent_name(fresh.intended_action))
	snap.record("fresh entry, finisher driving the house: developing feed",
			fresh._pass.developing_feed_value(fresh_ctx))
	snap.record("fresh entry, finisher driving the house: shoot-now value", fresh.debug_shoot_score)
	for dist: float in [10.0, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0]:
		snap.record("head-on drive at 6 m/s, keeper 1 m out, from %.0f m: pick" % dist,
				_pick(_decided(_head_on_drive_ctx(dist))))
	var cut: AIRoleCarrier = _decided(_one_v_one_ctx(true))
	snap.record("1v1 cutting across 3 m out, keeper squared 0.9 m out: pick", _pick(cut))
	snap.record("1v1 cutting across 3 m out, keeper squared 0.9 m out: shoot-now value",
			cut.debug_shoot_score)
	var beaten: AIRoleCarrier = _decided(_beaten_keeper_ctx())
	snap.record("1v1 mid-cut, keeper lagging the arc: intent", _intent_name(beaten.intended_action))
	snap.record("1v1 mid-cut, keeper lagging the arc: shoot-now value", beaten.debug_shoot_score)
	snap.record("1v1 flat-footed 3 m out, keeper squared 0.9 m out: carry anchor",
			_spot(_decided(_one_v_one_ctx(false)).last_carry_anchor))
	snap.record("standing 3 m out, keeper squared 1.3 m out: intent",
			_intent_name(_decided(_standstill_ctx(3.0)).intended_action))
	snap.record("standing 9 m out, keeper squared 1.3 m out: pick",
			_pick(_decided(_standstill_ctx(9.0))))
	var held: AIRoleCarrier = _decided(_backhand_side_keeper_ctx())
	snap.record("standing 3 m out, keeper displaced to the backhand side: winning hold",
			_spot(held.shoot_now_hold))
	snap.record("standing 3 m out, keeper displaced to the backhand side: hold load share",
			held._shot_sample_share)
	snap.record("dead-sharp beside the net, keeper on the near post: winning hold",
			_spot(_decided(_tuck_ctx()).shoot_now_hold))
	var wide: AIRoleCarrier = _decided(_wide_angle_ctx())
	snap.record("69 deg off the normal, keeper squared 1.2 m out: intent",
			_intent_name(wide.intended_action))
	snap.record("69 deg off the normal, keeper squared 1.2 m out: shoot-now value",
			wide.debug_shoot_score)


func _record_relief_and_breakout_picks(snap: Snapshot) -> void:
	snap.record("swarmed on the blade in our slot: intent",
			_intent_name(_decided(_own_slot_swarm_ctx(true)).intended_action))
	snap.record("swarmed in our slot a stride looser: intent",
			_intent_name(_decided(_own_slot_swarm_ctx(false)).intended_action))
	snap.record("past centre, stand-up line at gap, open backfield: pick",
			_pick(_decided(_contained_past_centre_ctx(true))))
	snap.record("past centre, a loose pair ahead: pick",
			_pick(_decided(_contained_past_centre_ctx(false))))
	snap.record("pinned in our zone by a head-on forecheck, outlet up the wall: pick",
			_pick(_decided(_pinned_with_an_outlet_ctx())))
	snap.record("wheeling up the weak wall, middle clogged: pick", _pick(_decided(_wall_exit_ctx())))
	snap.record("behind our cage, empty rink: pick", _pick(_decided(_make_ctx(_BEHIND_OUR_CAGE))))


func _record_zone_play_picks(snap: Snapshot) -> void:
	snap.record("beat his man down the wing at 8.5 m/s: pick", _pick(_decided(_wing_step_ctx())))
	snap.record("wing entry in stride, defender on the inside lane: carry anchor",
			_spot(_decided(_wing_entry_inside_d_ctx()).last_carry_anchor))
	snap.record("sharp-angle corner, keeper sealing, defender boxing out: pick",
			_pick(_decided(_sealed_corner_ctx())))
	snap.record("behind their cage, empty rink: carry anchor",
			_spot(_decided(_make_ctx(_BEHIND_THEIR_CAGE)).last_carry_anchor))
	snap.record("splittable gap up the middle, open man wide: carry anchor",
			_spot(_pinch(_SPLITTABLE_HALF_GAP).last_carry_anchor))
	snap.record("checker dead on the carry line: seam degrees off the carry", _shield_seam_deg(0.0))
	snap.record("checker 2 m off the carry line: seam degrees off the carry", _shield_seam_deg(2.0))


func test_a_down_keeper_is_priced_down_only_for_a_shot_before_he_can_rise() -> void:
	# The carry candidates price their shot at arrival in the keeper's stance at
	# the release (AICarrierField.keeper_stance_at), as shoot-now reads it live.
	var self_pos := Vector3(-1.0, 0.0, -GameRules.GOAL_LINE_Z + 9.0)
	var ctx := _make_ctx(self_pos)
	var g := GoalieNetworkState.new()
	g.position_z = -GameRules.GOAL_LINE_Z + 0.6
	g.state_enum = GoalieStateMachine.State.BUTTERFLY as int
	_place_keeper(ctx, g)
	var c := AIRoleCarrier.new()
	c._field.fill(ctx)
	assert_eq(c._field.keeper_stance_at(0.0), AIShotOdds.Stance.DOWN, "down now")
	assert_eq(c._field.keeper_stance_at(AIGoalieModel.GOALIE_RECOVERY_S * 0.9),
			AIShotOdds.Stance.DOWN, "still down for a shot before he could stand up")
	assert_eq(c._field.keeper_stance_at(AIGoalieModel.GOALIE_RECOVERY_S),
			AIShotOdds.Stance.UPRIGHT, "after it, his rise is his call: priced upright")


# ─── pass pace: a hard feed leaves the receiver settling ─────────────────────

# The same open feed, short and long. Short, the softer pace's flight costs less
# than the full pace's settle, so it goes soft; long (~28 m), a softer pace would
# outrun the lead horizon and is not priced, so it goes at full pace.
func _feed_ctx(mate: Vector3) -> RoleContext:
	return _make_ctx(Vector3(0, 0, 10), [
			[1, TEAM_ID, Vector3(0, 0, 10)],
			[2, TEAM_ID, mate],
			[3, 1, Vector3(-12, 0, 24)]])


func test_a_short_feed_goes_soft() -> void:
	var c := _decided(_feed_ctx(Vector3(5, 0, 9)))
	assert_eq(c._pass.best_peer, 2, "the feed is priced")
	assert_lt(c._pass.best_pace_frac, 1.0, "softer than full pace")


func test_a_long_feed_goes_at_full_pace() -> void:
	var c := _decided(_feed_ctx(Vector3(10, 0, -16)))
	assert_eq(c._pass.best_peer, 2, "the feed is priced")
	assert_eq(c._pass.best_pace_frac, 1.0)

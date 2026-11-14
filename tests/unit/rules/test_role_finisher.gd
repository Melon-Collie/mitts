extends GutTest

# AIRoleFinisher has a two-mode decision tree:
#   1. REACTIVE — incoming shot detected → tip / step-out.
#   2. POSITIONING — no shot threat → argmax score_pass over
#      candidate set.
# Tests cover both modes plus the bail-out cases (null puck,
# no carrier).

# Where the staging argmax currently puts each fixture is the snapshot,
# test_finisher_staging_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/role_finisher.txt"
# Team 0 defends +Z; opp goal at -Z.
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z
const OPP_NET_Z: float = -OUR_NET_Z
const TEAM_ID: int = 0


func _make_skater(pid: int, team: int, pos: Vector3,
		is_elevated: bool = false) -> Array:
	# is_elevated maps to loft level: true -> HIGH (2), false -> flat (0).
	return [pid, team, pos, 2 if is_elevated else 0]


func _make_ctx(self_pos: Vector3,
		puck_pos: Vector3, puck_vel: Vector3,
		skaters: Array = []) -> RoleContext:
	# Build a snapshot with the given puck and skaters. If `skaters`
	# is empty, just include self at self_pos so _last_shooter_is_elevated
	# has someone to look at.
	var snap := WorldSnapshot.new()
	if skaters.is_empty():
		var s := SkaterNetworkState.new()
		s.position = self_pos
		s.elevation_level = 0
		snap.skater_states[1] = s
	else:
		for entry: Array in skaters:
			var sk := SkaterNetworkState.new()
			sk.position = entry[2]
			sk.elevation_level = entry[3]
			snap.skater_states[entry[0]] = sk
	var puck := PuckNetworkState.new()
	puck.position = puck_pos
	puck.velocity = puck_vel
	puck.carrier_peer_id = -1
	snap.puck_state = puck

	var team_map: Dictionary = {}
	if skaters.is_empty():
		team_map[1] = TEAM_ID
	else:
		for entry: Array in skaters:
			team_map[entry[0]] = entry[1]

	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	# Team 0: own net at +Z, attacking -Z.
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, OPP_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	return ctx


# ─── HOLD: no incoming shot ───────────────────────────────────────────────

func test_hold_when_puck_too_slow() -> void:
	# Puck heading at our offensive goal but below INCOMING_SHOT_SPEED.
	var anchor := Vector3(-2.0, 0.0, -22.0)  # back-door anchor in OZ
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -8.0))  # 8 m/s — below 12 m/s gate
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_eq(d.target_position, anchor)
	assert_false(d.has_aim_override)


func test_hold_when_puck_heading_away_from_goal() -> void:
	# Fast puck but moving toward +Z (back at our defensive net), not
	# toward our offensive goal.
	var anchor := Vector3(-2.0, 0.0, -22.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, 20.0))
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_eq(d.target_position, anchor)
	assert_false(d.has_aim_override)


func test_hold_when_no_puck_state() -> void:
	var anchor := Vector3(-2.0, 0.0, -22.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			Vector3.ZERO, Vector3.ZERO)
	ctx.snapshot.puck_state = null
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_eq(d.target_position, anchor)


# ─── TIP: fast ground shot ────────────────────────────────────────────────

# Where the tip the decision sets up sends the puck: the turn the body→blade
# bearing asks of PuckCollisionRules.tip_turn — the puck's own physics — applied
# to its line at the blade, carried to the goal line.
func _tipped_x_at_goal(d: RoleDecision, puck_vel: Vector3) -> float:
	var turn: float = PuckCollisionRules.tip_turn(puck_vel,
			d.aim_world_pos - d.target_position, AIRoleFinisher.TIP_MAX_TURN_RAD)
	var out: Vector2 = Vector2(puck_vel.x, puck_vel.z).normalized().rotated(turn)
	return d.aim_world_pos.x + out.x * (OPP_NET_Z - d.aim_world_pos.z) / out.y


# The blade on the path at the tip point, the body a blade's ring back of it.
func _assert_blade_on_the_path(d: RoleDecision, tip_x: float) -> void:
	assert_true(d.has_aim_override)
	assert_almost_eq(d.aim_world_pos.x, tip_x, 0.05, "the blade waits on the path")
	assert_almost_eq(d.aim_world_pos.z, -22.0, 0.001)
	assert_almost_eq(Vector2(d.aim_world_pos.x - d.target_position.x,
			d.aim_world_pos.z - d.target_position.z).length(),
			AIRoleFinisher.TIP_BLADE_OUT_M, 0.001, "the body a ring back of it")


func test_tip_puts_the_blade_on_the_path_and_turns_it_at_the_middle() -> void:
	# Fast ground shot on net from a teammate at (2.3, 0, -15). Finisher
	# (peer 1) is at (-2, 0, -22) — back door. Puck vel (-3, 0, -15) —
	# speed ≈ 15 m/s, heading toward our offensive goal at -Z, crossing its
	# line at x ≈ 0. Path crosses our z (-22) at t ≈ 0.467 s,
	# x ≈ 2.3 + (-3)(0.467) ≈ 0.9.
	var teammate_pos := Vector3(2.3, 0.0, -15.0)
	var vel := Vector3(-3.0, 0.0, -15.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			teammate_pos, vel,
			[
				_make_skater(1, TEAM_ID, Vector3(-2.0, 0.0, -22.0), false),
				_make_skater(2, TEAM_ID, teammate_pos, false),  # not elevated
			])
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	_assert_blade_on_the_path(d, 0.9)
	assert_almost_eq(_tipped_x_at_goal(d, vel), 0.0, 0.02,
			"the tip goes at the middle of the net")


func test_a_wide_shot_a_tip_can_bring_back_is_tipped_in() -> void:
	# The same line from 1.7 m further right crosses the goal line ~0.8 m
	# outside the mouth: under a tip's turn from the blade, so it is tipped,
	# and as far as a tip turns it lands inside the mouth.
	# He stands where his stick can be on it in time (from the back door's 4.6 m
	# it is past before he could reach).
	var vel := Vector3(-3.0, 0.0, -15.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(1.0, 0.0, -22.0),
			Vector3(4.0, 0.0, -15.0), vel)
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	_assert_blade_on_the_path(d, 2.6)
	assert_true(d.deflect)
	assert_lt(absf(_tipped_x_at_goal(d, vel)), GameRules.NET_ENTRY_HALF_WIDTH,
			"the tip puts it on net")


func test_a_shot_wider_than_a_tip_turns_is_not_tipped() -> void:
	# From (8, -15) nearly straight down the ice it crosses the goal line ~7 m
	# wide: no tip turns it back, and the same line is a teammate's pass, so the
	# finisher holds his station rather than stepping in to redirect it.
	var anchor := Vector3(-2.0, 0.0, -22.0)
	var ctx: RoleContext = _make_ctx(
			anchor,
			Vector3(8.0, 0.0, -15.0), Vector3(-1.0, 0.0, -15.0))
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_false(d.has_aim_override, "no tip off a puck no tip brings back")
	assert_false(d.deflect)
	assert_eq(d.target_position, anchor)


# ─── TIP + LIFT: elevated shot ────────────────────────────────────────────

func test_an_elevated_shot_is_tipped_down() -> void:
	# Same geometry as the TIP test but the shooting teammate has
	# is_elevated = true. Finisher still sets up the same tip, holding the
	# deflect — whose press takes the blade up to the airborne puck — and tips
	# it down, off the plane the keeper read.
	var teammate_pos := Vector3(2.3, 0.0, -15.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			teammate_pos, Vector3(-3.0, 0.0, -15.0),
			[
				_make_skater(1, TEAM_ID, Vector3(-2.0, 0.0, -22.0), false),
				_make_skater(2, TEAM_ID, teammate_pos, true),  # elevated
			])
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	_assert_blade_on_the_path(d, 0.9)
	assert_true(d.deflect, "an incoming shot is tipped, not caught")
	assert_false(d.deflect_up, "a raised shot is tipped down")


func test_a_ground_shot_is_tipped_up() -> void:
	# A fast GROUND shot is deflected too — the press keeps the blade on the
	# ice for a puck met there — and tipped up.
	var teammate_pos := Vector3(2.3, 0.0, -15.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			teammate_pos, Vector3(-3.0, 0.0, -15.0),
			[
				_make_skater(1, TEAM_ID, Vector3(-2.0, 0.0, -22.0), false),
				_make_skater(2, TEAM_ID, teammate_pos, false),  # NOT elevated
			])
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_true(d.deflect, "an incoming shot is tipped, not caught")
	assert_true(d.deflect_up, "a shot on the ice is tipped up")


func test_the_deflect_waits_for_the_press_to_read_the_shot() -> void:
	# The same ground shot from twice as far: it reaches our z-plane past the
	# press's read horizon, so the finisher sets up the tip without the
	# deflect yet — held from there, the press would read nothing.
	var teammate_pos := Vector3(5.1, 0.0, -1.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			teammate_pos, Vector3(-3.0, 0.0, -15.0),
			[
				_make_skater(1, TEAM_ID, Vector3(-2.0, 0.0, -22.0), false),
				_make_skater(2, TEAM_ID, teammate_pos, false),
			])
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_true(d.has_aim_override, "still a tip: the blade to the path")
	assert_false(d.deflect, "too early to press")


# ─── HOLD: puck won't reach our z-plane ───────────────────────────────────

func test_hold_when_puck_path_crossing_is_in_past() -> void:
	# Fast puck heading toward opp goal — but it's ALREADY past the
	# back-door bot's z plane. The bot is BEHIND the puck-line
	# (less deep toward opp goal), so t_to_my_z is negative and the
	# reactive returns null. With no carrier set up, positioning
	# falls back to self_pos = anchor.
	var anchor := Vector3(-2.0, 0.0, -21.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -21.0),
			Vector3(0.0, 0.0, -23.0),  # puck DEEPER (more -Z) than back-door
			Vector3(0.0, 0.0, -15.0))  # heading further toward opp goal — away from us
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_eq(d.target_position, anchor)


# ─── POSITIONING (no incoming shot) ───────────────────────────────────────

func test_positioning_falls_back_to_self_pos_when_no_carrier() -> void:
	# No teammate carrier means no offensive context — positioning
	# falls back to self_pos (hold position; brain re-tick will
	# reassign within a frame).
	var self_pos := Vector3(-2.0, 0.0, -22.0)
	var ctx: RoleContext = _make_ctx(
			self_pos,
			Vector3(0.0, 0.0, -10.0), Vector3.ZERO)  # slow puck → reactive returns null
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_eq(d.target_position, self_pos,
			"slow puck + no carrier → positioning falls back to self_pos")
	assert_false(d.has_aim_override)


func test_positioning_picks_legal_position_when_carrier_present() -> void:
	# Teammate carrier in OZ corner. Slow puck so reactive doesn't
	# fire (puck speed 0). FINISHER should run positioning argmax
	# and pick a legal back-door / slot candidate.
	var carrier_pos := Vector3(5.0, 0.0, -22.0)  # OZ corner, strong-side
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			carrier_pos, Vector3.ZERO,  # carrier holds puck, no shot in flight
			[
				_make_skater(1, TEAM_ID, Vector3(-2.0, 0.0, -22.0), false),
				_make_skater(100, TEAM_ID, carrier_pos, false),
			])
	# Wire the puck carrier_peer_id to the teammate.
	ctx.snapshot.puck_state.carrier_peer_id = 100
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	# Position is legal: in-rink, not in crease, not past goal line.
	assert_true(absf(d.target_position.x) <= GameRules.RINK_HALF_WIDTH,
			"x within rink bounds")
	assert_true(absf(d.target_position.z) <= GameRules.GOAL_LINE_Z,
			"z within goal-line bounds")
	# No aim override — positioning doesn't tip.
	assert_false(d.has_aim_override)


# A live opposing keeper challenging on the carrier's arc (~1.1 m off his
# line). Without him the staging fixtures modeled a goalie parked dead-center
# ON the goal line — and against THAT keeper a center-doorstep feed honestly
# reads as the best look on the ice (it would be!), which swamps the
# weak-side staging these tests lock. Realistic coverage → realistic staging.
func _add_opp_goalie(ctx: RoleContext, carrier_pos: Vector3,
		depth: float = 1.1) -> void:
	var g := GoalieNetworkState.new()
	var to_carrier: Vector3 = carrier_pos - Vector3(0.0, 0.0, OPP_NET_Z)
	to_carrier.y = 0.0
	var dir: Vector3 = to_carrier.normalized()
	g.position_x = dir.x * depth
	g.position_z = OPP_NET_Z + dir.z * depth
	ctx.snapshot.goalie_states[1 - TEAM_ID] = g


func _stage_x_for_strong_side(strong_x: float) -> float:
	# Same carrier and skaters; only the strong-side sign differs, isolating the
	# weak-side search bias.
	var carrier_pos := Vector3(6.0, 0.0, -20.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(0.0, 0.0, -20.0),
			carrier_pos, Vector3.ZERO,
			[
				_make_skater(1, TEAM_ID, Vector3(0.0, 0.0, -20.0), false),
				_make_skater(100, TEAM_ID, carrier_pos, false),
			])
	ctx.snapshot.puck_state.carrier_peer_id = 100
	ctx.strong_x = strong_x
	_add_opp_goalie(ctx, carrier_pos)
	return AIRoleFinisher.decide(ctx).target_position.x


func test_positioning_bias_follows_strong_side() -> void:
	# The weak-side staging bias keys off strong_x: when the puck's strong side
	# is +X the FINISHER stages further to the weak (-X) side than when it's -X.
	# Validates the bias is wired without overfitting an absolute spot (the exact
	# depth is a tuning matter — angle vs goalie-slide trade off).
	var x_strong_plus: float = _stage_x_for_strong_side(1.0)
	var x_strong_minus: float = _stage_x_for_strong_side(-1.0)
	assert_lt(x_strong_plus, x_strong_minus,
			"strong-side +X should stage weaker (lower x) than strong-side -X")


func test_positioning_does_not_stack_on_carrier_side() -> void:
	# With a strong-side carrier at x=6, the FINISHER should stage well across to
	# the slot/weak side rather than crowding the puck-side wall.
	var x: float = _stage_x_for_strong_side(1.0)
	assert_lt(x, 3.0, "FINISHER stages cross-ice from a strong-side carrier, not stacked on it")


func test_positioning_stages_weak_side_of_a_strong_side_carrier() -> void:
	# 2-on-0 read: wide strong-side (+X) carrier, no defenders. The weak-side
	# search-center bias plus the seven-hole feed geometry (a cross-seam one-timer
	# catches the goalie sliding) should stage the FINISHER on the weak (-X) side,
	# opposite the carrier — the far-post tap-in, not crowding the puck side.
	var x: float = _stage_x_for_strong_side(1.0)
	assert_lt(x, 0.0,
			"FINISHER stages weak-side, opposite the carrier; got x=%f" % x)


# ─── NAMED-STATION STAGING (the one-timer geography) ──────────────────────

func _cycle_ctx(skaters: Array) -> RoleContext:
	# Settled cycle: carrier (peer 2) holds the puck on the strong-side
	# half-wall; the finisher (peer 1) reads its staging spot. Puck carried
	# (not a shot), so positioning mode runs.
	var ctx: RoleContext = _make_ctx(
			Vector3(-3.0, 0.0, -20.0),
			Vector3(8.0, 0.0, -20.0), Vector3.ZERO, skaters)
	ctx.snapshot.puck_state.carrier_peer_id = 2
	ctx.strong_x = 1.0
	_add_opp_goalie(ctx, Vector3(8.0, 0.0, -20.0))
	return ctx


# The coverage that genuinely concedes the far post: bumper covered, the
# net-front/tip man boxed out goal-side, and the keeper CAUGHT out challenging
# the wall carrier beyond his backdoor depth cap (priced at the real cross-seam
# feed speed, the cap tops out short of this 2.2 m challenge) — his re-square
# covers only cap/r of the lateral gap, so the far-post one-timer finishes
# behind him and the cross-seam lane is the one feed this box leaves open.
# (Against a HOME, cap-respecting keeper the pre-armed feed read deflates the
# backdoor and the finisher stages the tip/net-front station instead — see
# test_finisher_parks_the_tip_station… for that regime.)
func _open_backdoor_target() -> Vector3:
	var ctx: RoleContext = _cycle_ctx([
			_make_skater(1, TEAM_ID, Vector3(-3.0, 0.0, -20.0)),
			_make_skater(2, TEAM_ID, Vector3(8.0, 0.0, -20.0)),   # carrier, wall
			_make_skater(10, 1, Vector3(-0.8, 0.0, -21.5)),       # bumper cover
			_make_skater(11, 1, Vector3(2.2, 0.0, -25.3)),        # net-front box-out
	])
	var out_goalie: GoalieNetworkState = ctx.snapshot.goalie_states[1 - TEAM_ID]
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var challenge: Vector3 = (Vector3(8.0, 0.0, -20.0) - net).normalized() * 2.2
	out_goalie.position_x = net.x + challenge.x
	out_goalie.position_z = net.z + challenge.z
	return AIRoleFinisher.decide(ctx).target_position


func test_finisher_stages_the_open_backdoor() -> void:
	var target: Vector3 = _open_backdoor_target()
	assert_lt(target.x, -GameRules.NET_HALF_WIDTH,
			"stages beyond the far post, not mid-slot; got %s" % target)
	assert_lt(absf(target.z - OPP_NET_Z), GameRules.SLOT_DIST_M,
			"…deep at the backdoor, inside the slot's depth; got %s" % target)


# Point carrier, a full box+1 manning every feed office, and the goalie pinned
# deep on his line (what a screened keeper does — buy time). Carrier wide at
# the point so his rip line clears the office coverers' shot-block reach — the
# scenario is "offices dead, rip lane clean", not "rip through the box".
const TIP_CARRIER := Vector3(6.0, 0.0, -9.0)


func _dead_offices_ctx() -> RoleContext:
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -21.0),
			TIP_CARRIER, Vector3.ZERO,
			[
				_make_skater(1, TEAM_ID, Vector3(-2.0, 0.0, -21.0)),
				_make_skater(2, TEAM_ID, TIP_CARRIER),
				_make_skater(10, 1, Vector3(-2.3, 0.0, -24.6)),   # backdoor cover
				_make_skater(11, 1, Vector3(-1.2, 0.0, -21.2)),   # bumper cover
				_make_skater(12, 1, Vector3(2.3, 0.0, -13.1)),    # ON the high-slot feed lane
			])
	ctx.snapshot.puck_state.carrier_peer_id = 2
	ctx.strong_x = 1.0
	_add_opp_goalie(ctx, TIP_CARRIER, 0.4)
	return ctx


func _dead_offices_target() -> Vector3:
	return AIRoleFinisher.decide(_dead_offices_ctx()).target_position


func test_finisher_stages_for_a_tip_when_offices_die_and_goalie_sits_deep() -> void:
	# Every one-timer feed is dead, so the staging argmax stages for the tip of
	# the point blast (tip_ev): where he stands is worth its tip, not its feed,
	# and no less a tip than the TIP/SCREEN station on the carrier→net line at
	# crease-edge depth. Which spot wins is the shot field's read.
	var ctx: RoleContext = _dead_offices_ctx()
	var target: Vector3 = AIRoleFinisher.decide(ctx).target_position
	var goal: Vector3 = ctx.attacking_goal_pos
	var to_c: Vector3 = TIP_CARRIER - goal
	to_c.y = 0.0
	var station: Vector3 = goal + to_c * (AIRoleFinisher.TIP_STATION_DIST_M / to_c.length())
	var goalie: Vector3 = AIRoleReads.resolve_opp_goalie_pos(ctx)
	var opps: Array[Vector3] = ctx.scratch_opp_positions
	AIRoleReads.collect_opponents(ctx, opps, ctx.scratch_opp_states)
	var release: Vector3 = AIPuckLane.release_point_toward(TIP_CARRIER, goal)
	var tip := func(at: Vector3) -> float:
		return AIActionScoring.tip_ev(release, at, goal, goalie, opps,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, ctx.scratch_opp_caps, ctx.caps_by_peer.get(ctx.peer_id))
	var feed: float = AIActionScoring.score_pass_value(TIP_CARRIER, target, goal, goalie, opps,
			AIPuckLane.expected_pass_speed(TIP_CARRIER, target), ctx.scratch_opp_caps, true)
	assert_gt(tip.call(target), feed, "staged for the tip, not a feed; got %s" % target)
	assert_gte(tip.call(target), tip.call(station) - 1e-6,
			"no worse a tip than the shot-line post; got %s" % target)


func test_finisher_stays_off_a_covered_feed_lane() -> void:
	# A defender camped on the backdoor lane (and near the spot): the feed
	# there is dead, so the argmax stages a spot the carrier can actually
	# reach — the chosen station's feed must out-value the covered backdoor.
	var backdoor := Vector3(-2.3, 0.0, -25.15)
	var ctx: RoleContext = _cycle_ctx([
			_make_skater(1, TEAM_ID, Vector3(-3.0, 0.0, -20.0)),
			_make_skater(2, TEAM_ID, Vector3(8.0, 0.0, -20.0)),
			_make_skater(10, 1, Vector3(2.0, 0.0, -22.3)),        # on the seam lane
			_make_skater(11, 1, backdoor + Vector3(0.3, 0.0, 0.5)),
	])
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_gt(d.target_position.distance_to(backdoor), 2.0,
			"does not camp a dead backdoor; got %s" % d.target_position)


# ─── RUSH-AWARE STAGING ───────────────────────────────────────────────────

const RUSH_VEL := Vector3(0.0, 0.0, -8.0)


func _rush_ctx(carrier_vel: Vector3) -> RoleContext:
	# Stationary finisher at center-ice depth; a wide strong-side teammate
	# carrier with the given velocity. Slow puck so reactive stays off and
	# positioning runs. strong_x = +1 so the weak side is -X.
	var carrier_pos := Vector3(6.0, 0.0, -18.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(0.0, 0.0, -18.0),
			carrier_pos, Vector3.ZERO,
			[
				_make_skater(1, TEAM_ID, Vector3(0.0, 0.0, -18.0), false),
				_make_skater(100, TEAM_ID, carrier_pos, false),
			])
	ctx.snapshot.puck_state.carrier_peer_id = 100
	ctx.snapshot.skater_states[100].velocity = carrier_vel
	ctx.strong_x = 1.0
	_add_opp_goalie(ctx, carrier_pos)
	return ctx


func test_rush_factor_zero_for_stationary_carrier() -> void:
	assert_almost_eq(AIRoleFinisher._rush_factor(_rush_ctx(Vector3.ZERO)), 0.0, 0.001)


func test_rush_factor_zero_for_carrier_skating_away_from_net() -> void:
	# Team 0 attacks -Z; a +Z carrier velocity is away from the opp net,
	# which is never a rush.
	assert_almost_eq(
			AIRoleFinisher._rush_factor(_rush_ctx(Vector3(0.0, 0.0, 8.0))), 0.0, 0.001)


func test_rush_factor_one_for_fast_closing_carrier() -> void:
	# A -Z carrier velocity above RUSH_SPEED_HI_M_S is a full rush.
	assert_almost_eq(
			AIRoleFinisher._rush_factor(_rush_ctx(Vector3(0.0, 0.0, -8.0))), 1.0, 0.001)


func test_rush_stages_finisher_at_a_net_crash() -> void:
	# Same wide strong-side (+X) carrier; only its velocity differs. The rush
	# blend pulls the generic station in (stage_dist: SLOT_DIST_M →
	# RUSH_NET_DRIVE_DIST_M), so a rushing carrier stages the FINISHER as a
	# genuine second attacker at the net — a rebound / backdoor-tap threat.
	# There is no rush-vs-cycle depth ordering (an uncontested set cycle may
	# park the backdoor, at the net, too); the invariant is that the rush never
	# strands the finisher at the perimeter.
	var set_pos: Vector3 = AIRoleFinisher.decide(_rush_ctx(Vector3.ZERO)).target_position
	var rush_pos: Vector3 = AIRoleFinisher.decide(_rush_ctx(RUSH_VEL)).target_position
	assert_lt(absf(rush_pos.z - OPP_NET_Z), GameRules.SLOT_DIST_M,
			"a rushing carrier stages the FINISHER inside the slot's depth, crashing the net;"
			+ " got %s" % rush_pos)
	assert_lt(set_pos.x, 0.0, "the set cycle still stages weak-side")
	assert_lt(rush_pos.x, 0.0, "…and the rush crash stays weak-side too")


func test_reactive_fires_on_loose_shots_and_defers_while_the_puck_reads_held() -> void:
	# A held puck is never an incoming shot — a carrier skating it fast must
	# not flip the FINISHER into tip mode, and the carrier-reaction debounce
	# window right after a release (a live feed still nominally reads held)
	# must run positioning too: the reactive not-ready decision used to tear
	# down one-timer readiness on every feed. Reactive TIP fires the tick the
	# fast on-net puck reads loose.
	var teammate_pos := Vector3(2.3, 0.0, -15.0)
	var ctx: RoleContext = _make_ctx(
			Vector3(-2.0, 0.0, -22.0),
			teammate_pos, Vector3(-3.0, 0.0, -15.0),  # fast ground shot
			[
				_make_skater(1, TEAM_ID, Vector3(-2.0, 0.0, -22.0), false),
				_make_skater(2, TEAM_ID, teammate_pos, false),
			])
	ctx.snapshot.puck_state.carrier_peer_id = 2
	var held: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_false(held.has_aim_override,
			"a held puck runs positioning, never tip mode")
	ctx.snapshot.puck_state.carrier_peer_id = -1
	var loose: RoleDecision = AIRoleFinisher.decide(ctx)
	assert_true(loose.has_aim_override,
			"reactive TIP fires once the fast on-net puck reads loose")
	assert_true(loose.deflect)


func test_finisher_staging_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	var rows: Dictionary = {
		"2-on-0, strong-side carrier": AIRoleFinisher.decide(_rush_ctx(Vector3.ZERO)).target_position,
		"2-on-0, strong-side carrier rushing": AIRoleFinisher.decide(_rush_ctx(RUSH_VEL)).target_position,
		"cycle, keeper caught out, open backdoor": _open_backdoor_target(),
		"point carrier, offices dead, deep keeper": _dead_offices_target(),
	}
	for key: String in rows:
		var target: Vector3 = rows[key]
		snap.record("%s, target x" % key, target.x)
		snap.record("%s, target z" % key, target.z)
	snap.record("weak-side stage x, strong side +X", _stage_x_for_strong_side(1.0))
	snap.verify(self)


# ─── CRASH: our shot on its way ──────────────────────────────────────────────

class SlotStub extends TeamStrategyView:
	var slots: Dictionary = {}

	func get_slot(peer_id: int) -> int:
		return slots.get(peer_id, AIRoleSlots.Slot.NONE)


const SHOOTER := 2
const POINT_SHOT_FROM := Vector3(-6.0, 0.0, -9.0)


# Our point man (peer 2) has just let a shot go at their net; me (peer 1) on
# `slot`, standing at `me`, behind the puck so no tip is on.
func _crash_ctx(slot: int, me: Vector3 = Vector3(3.0, 0.0, -8.5),
		puck_vel: Vector3 = Vector3.INF) -> RoleContext:
	var goal := Vector3(0.0, 0.0, OPP_NET_Z)
	var from: Vector3 = POINT_SHOT_FROM + Vector3(0.4, 0.0, -0.8)
	var vel: Vector3 = (goal - from).normalized() * 25.0 if not puck_vel.is_finite() else puck_vel
	var ctx: RoleContext = _make_ctx(me, from, vel,
			[_make_skater(1, TEAM_ID, me), _make_skater(SHOOTER, TEAM_ID, POINT_SHOT_FROM)])
	ctx.snapshot.loose_puck_released_by = SHOOTER
	var slots := SlotStub.new()
	slots.slots = {1: slot, SHOOTER: AIRoleSlots.Slot.POINT_WEAK}
	ctx.team_brain = slots
	return ctx


func test_the_net_front_man_crashes_to_where_the_rebound_sits() -> void:
	var ctx: RoleContext = _crash_ctx(AIRoleSlots.Slot.NET_FRONT)
	var d: RoleDecision = AIRoleFinisher.decide(ctx)
	var goal := Vector3(0.0, 0.0, OPP_NET_Z)
	var want: Vector3 = AIReboundField.crash_point(
			AIReboundField.spot_of(POINT_SHOT_FROM, goal), false, goal)
	assert_true(want.is_finite(), "the point shot's spot has rebounds to play")
	assert_lt(Vector2(d.target_position.x - want.x, d.target_position.z - want.z).length(), 1.0,
			"to the measured contest point; got %s for %s" % [d.target_position, want])
	assert_true(AIStationSearch.is_legal_position(d.target_position), "never in the crease")
	assert_true(d.arrive_at_speed, "he gets there at speed")
	assert_eq(d.battle_spot, d.target_position, "and boxes out whoever is on it")


func test_the_finisher_takes_the_late_rebound_in_the_slot() -> void:
	var goal := Vector3(0.0, 0.0, OPP_NET_Z)
	var d: RoleDecision = AIRoleFinisher.decide(_crash_ctx(AIRoleSlots.Slot.FINISHER))
	var late: Vector3 = AIReboundField.crash_point(
			AIReboundField.spot_of(POINT_SHOT_FROM, goal), true, goal)
	assert_lt(Vector2(d.target_position.x - late.x, d.target_position.z - late.z).length(), 1.0,
			"to the measured late point; got %s for %s" % [d.target_position, late])


func test_no_crash_on_their_release_or_a_puck_going_away() -> void:
	var ctx: RoleContext = _crash_ctx(AIRoleSlots.Slot.NET_FRONT)
	ctx.team_id_by_peer[SHOOTER] = 1
	assert_false(AIRoleFinisher.decide(ctx).arrive_at_speed, "their shot is not ours to crash")
	var away: RoleContext = _crash_ctx(AIRoleSlots.Slot.NET_FRONT, Vector3(3.0, 0.0, -8.5),
			Vector3(0.0, 0.0, 20.0))
	assert_false(AIRoleFinisher.decide(away).arrive_at_speed, "a puck going up the ice is no shot")


func test_a_tip_he_cannot_make_is_a_crash() -> void:
	# Ahead of the puck but 9 m across from its line: the shot is past his line
	# before he could be on it.
	var d: RoleDecision = AIRoleFinisher.decide(
			_crash_ctx(AIRoleSlots.Slot.NET_FRONT, Vector3(8.0, 0.0, -20.0)))
	assert_false(d.has_aim_override, "no tip")
	assert_true(d.arrive_at_speed, "the crash")



# ─── NET FRONT: ice in front of one of our shots ─────────────────────────────

const SLOT_TOP_MATE := Vector3(0.5, 0.0, OPP_NET_Z + 10.0)


# Our carrier (peer 2) at `carrier`, me (peer 1) low on the weak side, their
# three in the house; with `mate` our man at the slot's top (peer 3).
func _screen_ctx(carrier: Vector3, mate: bool) -> RoleContext:
	var g: float = OPP_NET_Z
	var me := Vector3(-3.0, 0.0, g + 5.0)
	var sk: Array = [
		_make_skater(1, TEAM_ID, me),
		_make_skater(2, TEAM_ID, carrier),
		_make_skater(10, 1, Vector3(-2.3, 0.0, g + 1.5)),
		_make_skater(11, 1, Vector3(-0.8, 0.0, g + 6.0)),
		_make_skater(12, 1, Vector3(1.2, 0.0, g + 3.0)),
	]
	if mate:
		sk.append(_make_skater(3, TEAM_ID, SLOT_TOP_MATE))
	var ctx: RoleContext = _make_ctx(me, carrier, Vector3.ZERO, sk)
	ctx.snapshot.puck_state.carrier_peer_id = 2
	_add_opp_goalie(ctx, carrier)
	return ctx


func test_he_fights_for_ice_in_front_while_the_carrier_works_the_wall() -> void:
	var d: RoleDecision = AIRoleFinisher.decide(
			_screen_ctx(Vector3(8.0, 0.0, OPP_NET_Z + 6.0), true))
	assert_true(d.battle_spot.is_finite(), "the spot is published")
	assert_eq(d.battle_spot, d.target_position, "it is the ice he holds")


# net_front_value over the plays _screen_ctx's carrier and team make.
func _front_at(ctx: RoleContext, carrier: Vector3, at: Vector3) -> float:
	var goalie: Vector3 = AIRoleReads.resolve_opp_goalie_pos(ctx)
	var opps: Array[Vector3] = ctx.scratch_opp_positions
	AIRoleReads.collect_opponents(ctx, opps, ctx.scratch_opp_states)
	var mates: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, mates)
	AIStationSearch.fill_shot_plays(ctx, carrier, goalie, opps, mates)
	return AIStationSearch.net_front_value(ctx, at)


func test_a_man_at_the_slot_top_makes_his_line_worth_holding() -> void:
	# The carrier low on the wall has no shot a screen helps; our man at the
	# slot's top has a one-timer off the feed, which a body on his line hides.
	var carrier := Vector3(8.0, 0.0, OPP_NET_Z + 6.0)
	var goal := Vector3(0.0, 0.0, OPP_NET_Z)
	var along: float = AIScreenField.best_station_along(SLOT_TOP_MATE, goal)
	var on_line: Vector3 = goal + (SLOT_TOP_MATE - goal).normalized() * along
	var with_him: float = _front_at(_screen_ctx(carrier, true), carrier, on_line)
	var without: float = _front_at(_screen_ctx(carrier, false), carrier, on_line)
	assert_gt(with_him, without, "his shot is the one a body there screens")


func test_ice_far_from_the_net_adds_nothing_in_front() -> void:
	var ctx: RoleContext = _screen_ctx(Vector3(0.0, 0.0, OPP_NET_Z + 11.0), false)
	var goalie: Vector3 = AIRoleReads.resolve_opp_goalie_pos(ctx)
	var opps: Array[Vector3] = ctx.scratch_opp_positions
	AIRoleReads.collect_opponents(ctx, opps, ctx.scratch_opp_states)
	var mates: Array[Vector3] = ctx.scratch_teammates
	AIRoleReads.collect_teammates_excluding_self(ctx, mates)
	AIStationSearch.fill_shot_plays(ctx, Vector3(0.0, 0.0, OPP_NET_Z + 11.0), goalie, opps, mates)
	assert_eq(AIStationSearch.net_front_value(ctx, Vector3(-9.0, 0.0, OPP_NET_Z + 18.0)), 0.0)
	assert_gt(AIStationSearch.net_front_value(ctx, Vector3(0.0, 0.0, OPP_NET_Z + 2.5)), 0.0,
			"the crease top screens him and plays his rebound")


func test_a_point_shot_gets_its_rebound_station_and_no_screen() -> void:
	# The field measured a screen worth nothing from the points, so nobody is
	# sent onto its line; its rebound is still played where it comes out.
	var from := Vector3(-8.0, 0.0, OPP_NET_Z + 19.5)
	var ctx: RoleContext = _screen_ctx(from, false)
	var goalie: Vector3 = AIRoleReads.resolve_opp_goalie_pos(ctx)
	var opps: Array[Vector3] = ctx.scratch_opp_positions
	AIRoleReads.collect_opponents(ctx, opps, ctx.scratch_opp_states)
	var none: Array[Vector3] = []
	AIStationSearch.fill_shot_plays(ctx, from, goalie, opps, none)
	var stations: Array[Vector3] = []
	AIStationSearch.append_net_front_stations(ctx, stations)
	var goal := Vector3(0.0, 0.0, OPP_NET_Z)
	var crash: Vector3 = AIReboundField.crash_point(AIReboundField.spot_of(
			AIPuckLane.release_point_toward(from, goal), goal), false, goal)
	assert_eq(stations, [crash] as Array[Vector3])

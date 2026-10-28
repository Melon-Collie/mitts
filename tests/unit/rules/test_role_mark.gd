extends GutTest

# AIRoleMark — the unified off-puck man-marker (DZONE + TRANS_DEFENSE), replacing the
# old ANCHOR / COVER / BACKCHECK, which had converged to identical man-marking.
#
# Primary path (brain assigned a man): the shared cover stand,
# AIDefensiveVerbs.cover_threat — goal-side of that opponent, in the carrier→man
# feed lane, riding his cut. Tests:
#   - Assigned man drives coverage to that man's side (DZONE + TRANS_DEFENSE).
#   - Coverage stays ATTACHED to the man (near his cover anchor, not from the slot).
#   - Coverage is goal-side of the man, and rides his cut rather than leading it.
#
# Fallback path (unassigned — more markers than receivers, loose puck, no brain):
# recover to the most dangerous ice via a shot-threat minimax centered on the
# midpoint between puck and our net (adaptive across both zones). Tests:
#   - Bail-out (no opps) → self_pos.
#   - DZONE positioning lands near our net.
#   - Lane-blocking + cross-crease shading toward the dominant threat.
#   - Fallback center is puck-adaptive (midpoint), not pinned to a fixed slot.
# Underlying score_shoot primitive is tested in test_ai_action_scoring. Where
# the fallback currently lands each fixture is the snapshot,
# test_mark_fallback_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/role_mark.txt"
const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z   # Team 0 defends +Z
# A lone opposing carrier straight out from our net in the D-zone, and the
# fallback marker off to his side.
const DZONE_CARRIER := Vector3(0, 0, 22)
const DZONE_MARKER := Vector3(8, 0, 18)
# A carrier who just took it back deep in their end (TRANS_DEFENSE).
const DEEP_LOSS_CARRIER := Vector3(0, 0, -15)


# `skaters` entries are [peer_id, team_id, position] (velocity optional as [3]).
func _make_ctx(self_pos: Vector3, skaters: Array = [],
		carrier_pid: int = -1) -> RoleContext:
	var snap := WorldSnapshot.new()
	if skaters.is_empty():
		var s := SkaterNetworkState.new()
		s.position = self_pos
		snap.skater_states[1] = s
	else:
		for entry: Array in skaters:
			var sk := SkaterNetworkState.new()
			sk.position = entry[2]
			snap.skater_states[entry[0]] = sk
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = carrier_pid
	if carrier_pid != -1:
		for entry: Array in skaters:
			if entry[0] == carrier_pid:
				puck.position = entry[2]
				break
	else:
		puck.position = Vector3.ZERO
	snap.puck_state = puck

	var team_map: Dictionary = {1: TEAM_ID}
	if not skaters.is_empty():
		team_map.clear()
		for entry: Array in skaters:
			team_map[entry[0]] = entry[1]

	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -OUR_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	return ctx


# ── Primary: man-on-threat coverage ────────────────────────────────────────

func test_assigned_man_drives_coverage_side_dzone() -> void:
	# Carrier at center, two receivers wide. Assigned the LEFT receiver → cover
	# the left side; the RIGHT receiver flips it right. Proves the threat
	# partition — not a global-max minimax — drives which man this marker takes.
	var carrier := Vector3(0, 0, 20)
	var left_man := Vector3(-7, 0, 19)
	var right_man := Vector3(7, 0, 19)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(0, 0, 16), Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier, Vector3.ZERO],
		[210, 1 - TEAM_ID, left_man, Vector3.ZERO],
		[220, 1 - TEAM_ID, right_man, Vector3.ZERO],
	]

	var ctx_left: RoleContext = _make_ctx(Vector3(0, 0, 16), skaters, 200)
	ctx_left.assigned_threat_peer = 210
	var left_target: Vector3 = AIRoleMark.decide(ctx_left).target_position
	assert_lt(left_target.x, 0.0,
			"assigned the left man → cover the left side; got x=%f" % left_target.x)

	var ctx_right: RoleContext = _make_ctx(Vector3(0, 0, 16), skaters, 200)
	ctx_right.assigned_threat_peer = 220
	var right_target: Vector3 = AIRoleMark.decide(ctx_right).target_position
	assert_gt(right_target.x, 0.0,
			"assigned the right man → cover the right side; got x=%f" % right_target.x)

	# Goal-side of the assigned man (between him and our net, not out past him).
	assert_gt(left_target.z, left_man.z - 0.01,
			"coverage is goal-side of the man; got z=%f" % left_target.z)


# The covered man is what the agent's stick tie reads (skater_agent_stick_play.gd
# tie_aim): a marker publishes him, a marker with nobody assigned publishes nobody.
func test_the_marker_publishes_the_man_it_covers() -> void:
	var skaters: Array = [
		[1, TEAM_ID, Vector3(0, 0, 16), Vector3.ZERO],
		[200, 1 - TEAM_ID, Vector3(0, 0, 20), Vector3.ZERO],
		[210, 1 - TEAM_ID, Vector3(-7, 0, 19), Vector3.ZERO],
	]
	var ctx: RoleContext = _make_ctx(Vector3(0, 0, 16), skaters, 200)
	ctx.assigned_threat_peer = 210
	assert_eq(AIRoleMark.decide(ctx).locked_man_pid, 210)
	ctx.assigned_threat_peer = -1
	assert_eq(AIRoleMark.decide(ctx).locked_man_pid, -1,
			"the unassigned fallback covers ice, not a man")


func test_assigned_man_drives_coverage_side_trans_od() -> void:
	# Rush: carrier in NZ, a receiver wide on +X. Assigned that man, MARK covers
	# his side goal-side of him — the same behavior the old BACKCHECK had.
	var carrier := Vector3(0, 0, 0)
	var man := Vector3(9, 0, 12)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(0, 0, 20), Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier, Vector3.ZERO],
		[210, 1 - TEAM_ID, man, Vector3.ZERO],
	]
	var ctx: RoleContext = _make_ctx(Vector3(0, 0, 20), skaters, 200)
	ctx.assigned_threat_peer = 210
	var d: RoleDecision = AIRoleMark.decide(ctx)
	assert_gt(d.target_position.x, 0.0,
			"assigned the +X man → cover his side; got x=%f" % d.target_position.x)
	assert_gt(d.target_position.z,
			man.z - AIDefensiveVerbs.COVER_GOAL_SIDE_TOLERANCE_M - 0.01,
			"coverage is goal-side of the man; got z=%f" % d.target_position.z)


func test_assigned_man_is_covered_tight_not_from_the_slot() -> void:
	# Coverage must be ATTACHED to the man — the search centers on the threat
	# partition's cover anchor (COVER_DEPTH_M goal-side of him), so the target
	# sits within the anchor + one candidate ring of his body. A midpoint-to-net
	# centering would "cover" this man from ~11 m away, which is how bots lost
	# their man.
	var carrier := Vector3(-3, 0, -2)
	var man := Vector3(5, 0, 2)   # ~25 m from our net
	var skaters: Array = [
		[1, TEAM_ID, Vector3(2, 0, 8), Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier, Vector3.ZERO],
		[210, 1 - TEAM_ID, man, Vector3.ZERO],
	]
	var ctx: RoleContext = _make_ctx(Vector3(2, 0, 8), skaters, 200)
	ctx.assigned_threat_peer = 210
	var d: RoleDecision = AIRoleMark.decide(ctx)
	var max_attach: float = AIThreatAssignment.COVER_DEPTH_M \
			+ AIStationSearch.SEARCH_STEP_M + 0.5
	assert_lt(d.target_position.distance_to(man), max_attach,
			"man coverage stays attached to the man; got %s for man at %s" \
			% [d.target_position, man])
	assert_gt(d.target_position.z,
			man.z - AIDefensiveVerbs.COVER_GOAL_SIDE_TOLERANCE_M - 0.01,
			"…and on the defensive side of him; got z=%f" % d.target_position.z)


func test_man_coverage_rides_a_moving_man_instead_of_leading_him() -> void:
	# Same assigned man, stationary vs cutting toward center (+x). The
	# anticipation is real but it lives in the FRAME, not in the point: the
	# stand is never led downrange of his real body (his options from where he
	# is may tighten it on him), and the route flies it at his velocity
	# (AISteering's moving-frame pursuit). Doing both — aiming the
	# anchor downrange AND riding him — double-counts his motion and covers
	# him from further off the faster he skates, which is the defect the gap
	# ladder and the backchecker's hip were already fixed for.
	var carrier := Vector3(0, 0, 20)
	var man := Vector3(-7, 0, 19)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(0, 0, 16), Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier, Vector3.ZERO],
		[210, 1 - TEAM_ID, man, Vector3.ZERO],
	]
	var ctx_still: RoleContext = _make_ctx(Vector3(0, 0, 16), skaters, 200)
	ctx_still.assigned_threat_peer = 210
	var still: RoleDecision = AIRoleMark.decide(ctx_still)

	var ctx_move: RoleContext = _make_ctx(Vector3(0, 0, 16), skaters, 200)
	ctx_move.assigned_threat_peer = 210
	var cut := Vector3(10, 0, 0)  # cutting +x
	ctx_move.snapshot.skater_states[210].velocity = cut
	var moved: RoleDecision = AIRoleMark.decide(ctx_move)

	assert_lte(moved.target_position.x, still.target_position.x + 0.001,
			"the stand is never aimed downrange of his body")
	assert_eq(still.target_velocity, Vector3.ZERO,
			"a still man's stand does not move")
	assert_eq(moved.target_velocity, cut,
			"a cutting man's stand rides him at his own pace")


func test_wide_man_coverage_stays_in_the_sealing_lane() -> void:
	# Man wide near the goal-line-extended: "behind him in Z" and "between
	# him and the net" point different ways. The old Z-axis goal-side test
	# let the marker park BESIDE the man on the boards side (a spot that
	# kills the cross-ice feed lane by standing past his tape, off the
	# sealing lane) — one burst and he walks to the net. Goal-side is now
	# the projection onto the man→our-net line, so wherever the argmax
	# lands, it must be in front of him toward the net (tolerance slack
	# aside), never past him toward the boards.
	var carrier := Vector3(-6, 0, 18)
	var man := Vector3(8, 0, 24)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(4, 0, 22), Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier, Vector3.ZERO],
		[210, 1 - TEAM_ID, man, Vector3.ZERO],
	]
	var ctx: RoleContext = _make_ctx(Vector3(4, 0, 22), skaters, 200)
	ctx.assigned_threat_peer = 210
	var target: Vector3 = AIRoleMark.decide(ctx).target_position
	var to_net: Vector3 = (ctx.defending_goal_pos - man).normalized()
	var proj: float = (target.x - man.x) * to_net.x + (target.z - man.z) * to_net.z
	assert_gt(proj, -AIDefensiveVerbs.COVER_GOAL_SIDE_TOLERANCE_M - 0.01,
			"coverage seals the man→net lane, not the space beside him;"
			+ " got %s (lane projection %f)" % [target, proj])


# ── Fallback: bail-out ─────────────────────────────────────────────────────

func test_falls_back_to_self_pos_when_no_opps() -> void:
	# No opps means no shot threat to defend against.
	var self_pos := Vector3(0, 0, 21)
	var ctx: RoleContext = _make_ctx(self_pos)
	var d: RoleDecision = AIRoleMark.decide(ctx)
	assert_eq(d.target_position, self_pos,
			"no opps → fall back to self_pos")


func test_unassigned_falls_back_even_with_a_live_carrier() -> void:
	# A live carrier but no assigned man (more markers than receivers) → the
	# marker still runs the recovery fallback instead of standing still.
	var skaters: Array = [
		[1, TEAM_ID, Vector3(0, 0, 18), Vector3.ZERO],
		[200, 1 - TEAM_ID, Vector3(0, 0, 22), Vector3.ZERO],  # carrier, unassigned to us
	]
	var ctx: RoleContext = _make_ctx(Vector3(0, 0, 18), skaters, 200)
	# assigned_threat_peer defaults to -1 (unassigned).
	var d: RoleDecision = AIRoleMark.decide(ctx)
	assert_ne(d.target_position, ctx.self_pos,
			"unassigned marker recovers to dangerous ice, not self_pos")


# ── Fallback: DZONE positioning near our net ───────────────────────────────

func _lone_carrier_target(self_pos: Vector3, carrier: Vector3) -> Vector3:
	var skaters: Array = [
		[1, TEAM_ID, self_pos, Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier, Vector3.ZERO],
	]
	return AIRoleMark.decide(_make_ctx(self_pos, skaters, 200)).target_position


func test_fallback_target_is_near_our_net_in_dzone() -> void:
	# DZONE: the fallback centres on midpoint(puck, our net), so it recovers
	# goal-side of the carrier rather than out toward him.
	var target: Vector3 = _lone_carrier_target(Vector3(0, 0, 18), DZONE_CARRIER)
	assert_gt(target.z, DZONE_CARRIER.z,
			"target stays goal-side of the carrier, near our net; got z=%f" % target.z)


func test_fallback_blocks_shot_lane_for_single_opp() -> void:
	# A lone carrier shooting from straight out: the fallback steps from the
	# side into his shot lane (between the posts' lines) — placement on the lane
	# reduces his threat.
	var target: Vector3 = _lone_carrier_target(DZONE_MARKER, DZONE_CARRIER)
	assert_lt(absf(target.x), GameRules.NET_HALF_WIDTH,
			"target stands in the shot lane; got x=%f" % target.x)


func test_fallback_shades_toward_dominant_threat() -> void:
	# Two opp threats — one on-axis (clean shot lane), one off to the side. The
	# on-axis opp carries the puck (dominant shot threat). Adding it should shade
	# the fallback target toward x=0 to cover the on-axis lane.
	var off_axis_opp := Vector3(8, 0, 20)

	var skaters_off: Array = [
		[1, TEAM_ID, Vector3(0, 0, 18), Vector3.ZERO],
		[200, 1 - TEAM_ID, off_axis_opp, Vector3.ZERO],
	]
	var ctx_a: RoleContext = _make_ctx(Vector3(0, 0, 18), skaters_off, 200)
	var off_only_target: Vector3 = AIRoleMark.decide(ctx_a).target_position

	var on_axis_opp := Vector3(0, 0, 22)
	var skaters_both: Array = [
		[1, TEAM_ID, Vector3(0, 0, 18), Vector3.ZERO],
		[200, 1 - TEAM_ID, off_axis_opp, Vector3.ZERO],
		[210, 1 - TEAM_ID, on_axis_opp, Vector3.ZERO],
	]
	var ctx_b: RoleContext = _make_ctx(Vector3(0, 0, 18), skaters_both, 210)
	var both_target: Vector3 = AIRoleMark.decide(ctx_b).target_position

	assert_true(absf(both_target.x) <= absf(off_only_target.x) + 0.01,
			"adding on-axis carrier shades the fallback toward center; got both=%s off-only=%s" % [both_target, off_only_target])


# ── Fallback: puck-adaptive centering (both zones) ─────────────────────────

func test_fallback_center_is_puck_adaptive_not_fixed_slot() -> void:
	# TRANS_DEFENSE: puck up-ice (we just lost it deep). The fallback centres on
	# midpoint(puck, our net), so the recovery target sits nearer that midpoint
	# than the fixed slot the old BACKCHECK used — grounded in the developing play
	# instead of a hard-coded home spot.
	var target: Vector3 = _lone_carrier_target(Vector3(0, 0, -10), DEEP_LOSS_CARRIER)
	var slot_z: float = OUR_NET_Z - GameRules.SLOT_DIST_M
	var midpoint_z: float = (DEEP_LOSS_CARRIER.z + OUR_NET_Z) * 0.5
	assert_lt(absf(target.z - midpoint_z), absf(target.z - slot_z),
			"fallback centres on the puck→net midpoint, not the fixed slot;"
			+ " got z=%f (slot=%f, midpoint=%f)" % [target.z, slot_z, midpoint_z])


func test_fallback_far_cover_reads_the_brain_threat_memo() -> void:
	# The far-from-region fallback skates at the cover of the biggest BASE
	# threat directly, so it is fully bases-driven — the seam that proves the
	# marker consumes TeamBrain's shared threat memo (ctx.threat_shoot_base_by_
	# opp) instead of recomputing the surfaces. Opp 200 is the true dominant
	# threat (on-axis slot carrier); 210 is parked wide. The exact local bases
	# cover 200; a memo declaring 210 the bigger surface must flip the cover
	# onto 210's lane.
	var skaters: Array = [
		[1, TEAM_ID, Vector3(0, 0, -20), Vector3.ZERO],        # us, far up-ice
		[200, 1 - TEAM_ID, Vector3(0, 0, 20), Vector3.ZERO],   # slot — dominant
		[210, 1 - TEAM_ID, Vector3(12, 0, 25), Vector3.ZERO],  # wide, weak angle
	]
	var ctx_exact: RoleContext = _make_ctx(Vector3(0, 0, -20), skaters, 200)
	var exact_target: Vector3 = AIRoleMark.decide(ctx_exact).target_position
	assert_lt(absf(exact_target.x), 1.0,
			"exact bases cover the on-axis dominant threat; got %s" % exact_target)

	var ctx_memo: RoleContext = _make_ctx(Vector3(0, 0, -20), skaters, 200)
	var memo: Dictionary[int, float] = {200: 0.01, 210: 0.9}
	ctx_memo.threat_shoot_base_by_opp = memo
	var memo_target: Vector3 = AIRoleMark.decide(ctx_memo).target_position
	assert_gt(memo_target.x, 1.0,
			"memo bases flip the cover onto the wide man's lane; got %s" % memo_target)


# ── Helper: lead clamp ─────────────────────────────────────────────────────

func test_lead_threat_clamps_long_lead() -> void:
	var p := Vector3.ZERO
	# Slow: leads along velocity (3 m/s × 0.3 s = 0.9 m), unclamped.
	var slow: Vector3 = AIRoleReads.lead_threat(p, Vector3(3, 0, 0))
	assert_almost_eq(slow.x, 0.9, 0.001, "slow lead is vel × horizon")
	# Fast: 50 m/s × 0.3 = 15 m → clamped to the max.
	var fast: Vector3 = AIRoleReads.lead_threat(p, Vector3(50, 0, 0))
	assert_almost_eq(fast.x, AIRoleReads.DEFENSIVE_ANTICIPATION_MAX_M, 0.001,
			"long lead clamps to DEFENSIVE_ANTICIPATION_MAX_M")


func test_mark_fallback_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	var rows: Dictionary = {
		"DZONE lone carrier, marker in the slot": _lone_carrier_target(Vector3(0, 0, 18), DZONE_CARRIER),
		"DZONE lone carrier, marker off to the side": _lone_carrier_target(DZONE_MARKER, DZONE_CARRIER),
		"TRANS_DEFENSE, carrier deep in their end":
				_lone_carrier_target(Vector3(0, 0, -10), DEEP_LOSS_CARRIER),
	}
	for key: String in rows:
		var target: Vector3 = rows[key]
		snap.record("%s, target x" % key, target.x)
		snap.record("%s, target z" % key, target.z)
	snap.verify(self)

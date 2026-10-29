extends GutTest

# AIRolePressure — DZONE + TRANS_DEFENSE puck pressurer. Tests cover:
#   - Loose puck (no carrier) → pressures the puck, never freezes.
#   - Goal-side filter rejects wrong-side candidates.
#   - Argmax picks a position that blocks the shot lane when
#     carrier has a clear shot.
# Underlying score_shoot / score_pass primitives are tested in
# test_ai_action_scoring. Where the argmax currently stands for the reference
# fixtures is the snapshot, test_pressure_calibration_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/role_pressure.txt"
const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z   # Team 0 defends +Z
# A lone opposing carrier straight out from our net with a clear shot, and the
# pressurer off to his side.
const SHOOTER := Vector3(0, 0, 22)
const PRESSURER_START := Vector3(8, 0, 18)


func _make_ctx(self_pos: Vector3, carrier_pid: int = -1,
		skaters: Array = []) -> RoleContext:
	var snap := WorldSnapshot.new()
	if skaters.is_empty():
		var s := SkaterNetworkState.new()
		s.position = self_pos
		snap.skater_states[1] = s
	else:
		for entry: Array in skaters:
			var sk := SkaterNetworkState.new()
			sk.position = entry[2]
			sk.velocity = entry[3] if entry.size() > 3 else Vector3.ZERO
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


# ── Body check commit ────────────────────────────────────────────────────────

# A pressurer 2 m from a stationary carrier, head-on, at `transfer`, with a
# teammate home behind him unless `last_man`.
func _head_on_check(transfer: float, last_man: bool = false) -> RoleDecision:
	var self_pos := Vector3(0, 0, 18)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[200, 1 - TEAM_ID, Vector3(0, 0, 20)],
	]
	if not last_man:
		skaters.append([2, TEAM_ID, Vector3(0, 0, OUR_NET_Z - 2.0)])
	var ctx: RoleContext = _make_ctx(self_pos, 200, skaters)
	ctx.self_max_speed = 9.0
	ctx.self_body_check_transfer = transfer
	return AIRolePressure.decide(ctx)


func test_commits_exactly_when_the_hit_would_separate() -> void:
	# A reachable head-on carrier: the pressurer commits iff the collision
	# resolver's own kick at his closing speed clears the separating-hit bar, so
	# a heavy hitter hunts it and a light one keeps containing. Committed, he
	# steers at the carrier's body, not the cutoff point.
	var defaults := RoleContext.new()
	var committed: int = 0
	for k: int in range(1, 21):
		var transfer: float = 0.05 * k
		var d: RoleDecision = _head_on_check(transfer)
		var kick: float = SkaterCollisionRules.victim_kick(9.0, defaults.self_weight,
				AIBodyCheck.LEAGUE_VICTIM_WEIGHT, transfer)
		var separates: bool = kick >= AIBodyCheck.COMMIT_IMPULSE_M_S / defaults.check_aggression
		assert_eq(d.commit_check, separates,
				"transfer %.2f (kick %.2f m/s) commits iff the hit separates" % [transfer, kick])
		if d.commit_check:
			committed += 1
			assert_almost_eq(d.target_position.z, 20.0, 0.5, "steers at the carrier's body intercept")
	assert_between(committed, 1, 19, "the sweep spans both sides of the bar")


func test_the_last_man_back_never_commits() -> void:
	# A hit that separates with a layer home is a breakaway without one.
	assert_true(_head_on_check(1.0).commit_check, "the fixture's hit separates")
	assert_false(_head_on_check(1.0, true).commit_check)


func test_no_body_check_on_loose_puck() -> void:
	# No live carrier → never a hit target; normal (loose-puck) pressure.
	var self_pos := Vector3(0, 0, 18)
	var ctx: RoleContext = _make_ctx(self_pos)   # carrier_pid -1, loose puck
	ctx.self_body_check_transfer = 0.61
	var d: RoleDecision = AIRolePressure.decide(ctx)
	assert_false(d.commit_check, "no body check without a live opponent carrier")


# ── Bail-outs ───────────────────────────────────────────────────────────────

func test_pressures_loose_puck_instead_of_freezing() -> void:
	# Loose puck (in-flight pass / contested moment). PRESSURE used to
	# freeze at self_pos here — the "stuck on the heels" bug. It must now
	# orient off the puck and close it goal-side. Bot starts up-ice on
	# the wrong side of the puck; the chosen target must be goal-side of
	# the loose puck, never self_pos.
	var self_pos := Vector3(6, 0, -4)   # up-ice, wrong side of the puck
	var ctx: RoleContext = _make_ctx(self_pos)   # loose puck at origin
	var d: RoleDecision = AIRolePressure.decide(ctx)
	assert_ne(d.target_position, self_pos,
			"loose puck → pressure the puck, don't freeze at self_pos")
	assert_true(d.target_position.z >= -0.01,
			"chosen target is goal-side of the loose puck; got z=%f" % d.target_position.z)


# ── Goal-side filter ────────────────────────────────────────────────────────

func test_chosen_target_is_goal_side_of_carrier() -> void:
	# Team 0 defends +Z. Carrier at (0, 0, 22) deep in our DZ. Our
	# net at (0, 0, 26.65). PRESSURE must pick a candidate with
	# z >= 22 (goal-side, between carrier and our net).
	var carrier_pos := Vector3(0, 0, 22)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(0, 0, 18), Vector3.ZERO],   # us (PRESSURE)
		[200, 1 - TEAM_ID, carrier_pos, Vector3.ZERO],   # opp carrier
	]
	var ctx: RoleContext = _make_ctx(Vector3(0, 0, 18), 200, skaters)
	var d: RoleDecision = AIRolePressure.decide(ctx)
	assert_true(d.target_position.z >= carrier_pos.z - 0.01,
			"chosen target must be on the our-net side of the carrier; got z=%f vs carrier.z=%f" % [d.target_position.z, carrier_pos.z])


# ── Argmax denies the carrier's best option ─────────────────────────────────

func _shot_lane_target() -> Vector3:
	var skaters: Array = [
		[1, TEAM_ID, PRESSURER_START, Vector3.ZERO],   # us, off to the side
		[200, 1 - TEAM_ID, SHOOTER, Vector3.ZERO],     # opp carrier
	]
	return AIRolePressure.decide(_make_ctx(PRESSURER_START, 200, skaters)).target_position


func test_argmax_blocks_shot_lane_when_no_pass_options() -> void:
	# Solo opp carrier with a clear shot at our net and no teammates, so his only
	# option is to shoot: PRESSURE stands goal-side of him in that shot lane
	# (between the posts' lines; the lane runs along +Z here).
	var target: Vector3 = _shot_lane_target()
	assert_true(target.z >= SHOOTER.z - 0.01,
			"target is goal-side of carrier (z=%f)" % target.z)
	assert_lt(absf(target.x), GameRules.NET_HALF_WIDTH,
			"target stands in the shot lane; got x=%f" % target.x)


# ── Target switch-hysteresis ────────────────────────────────────────────────

func test_standing_target_sticks_within_margin() -> void:
	# A standing target whose re-scored value is within TARGET_SWITCH_MARGIN
	# of the fresh argmax is kept — the anti-flicker guarantee. Solo carrier,
	# straight shot: first decide picks a spot on the shot lane; a prev
	# target nudged 0.15 m along the same lane blocks essentially the same
	# shot, so decide must return the prev, not re-jump to the argmax.
	# (0.15 m, not more: the release-contest read grades distance from the
	# carrier's blade steeply — one stick length spans full-to-no contest —
	# so "near-equal" on this lane is a genuinely small span.)
	var carrier_pos := Vector3(0, 0, 22)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(8, 0, 18), Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier_pos, Vector3.ZERO],
	]
	var ctx: RoleContext = _make_ctx(Vector3(8, 0, 18), 200, skaters)
	var first: Vector3 = AIRolePressure.decide(ctx).target_position
	var prev: Vector3 = first + Vector3(0, 0, 0.15)  # a hair deeper on the lane
	var ctx2: RoleContext = _make_ctx(Vector3(8, 0, 18), 200, skaters)
	ctx2.prev_role_target = prev
	var second: Vector3 = AIRolePressure.decide(ctx2).target_position
	assert_eq(second, prev,
			"a near-equal standing target is kept through hysteresis")


func test_standing_target_dropped_when_clearly_beaten() -> void:
	# A standing target well off the shot lane blocks nothing; the fresh
	# argmax beats it past the margin and the pressurer re-anchors.
	var carrier_pos := Vector3(0, 0, 22)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(8, 0, 18), Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier_pos, Vector3.ZERO],
	]
	var ctx: RoleContext = _make_ctx(Vector3(8, 0, 18), 200, skaters)
	ctx.prev_role_target = Vector3(9.0, 0, 23.5)  # goal-side but far off the lane
	var target: Vector3 = AIRolePressure.decide(ctx).target_position
	assert_ne(target, ctx.prev_role_target,
			"a clearly-beaten standing target is abandoned")
	assert_lt(absf(target.x), 3.5, "re-anchors onto the shot lane")


func test_standing_target_ignored_when_wrong_side() -> void:
	# A standing target that fails the goal-side filter (carrier skated past
	# it) is dropped outright — hysteresis never holds a lost position.
	var carrier_pos := Vector3(0, 0, 22)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(0, 0, 18), Vector3.ZERO],
		[200, 1 - TEAM_ID, carrier_pos, Vector3.ZERO],
	]
	var ctx: RoleContext = _make_ctx(Vector3(0, 0, 18), 200, skaters)
	ctx.prev_role_target = Vector3(0, 0, 20.0)  # opp-net side of the carrier
	var target: Vector3 = AIRolePressure.decide(ctx).target_position
	assert_true(target.z >= carrier_pos.z - 0.01,
			"wrong-side standing target is ignored, argmax runs fresh")


func test_candidate_set_includes_inner_ring() -> void:
	# PRESSURE samples at half step too (18 candidates: center + self +
	# 8 outer + 8 inner) so the cut-off can correct in small moves.
	var candidates: Array[Vector3] = AIStationSearch.generate_candidates_around(
			Vector3.ZERO, Vector3(5, 0, 5), true)
	assert_eq(candidates.size(), 18)
	var default_set: Array[Vector3] = AIStationSearch.generate_candidates_around(
			Vector3.ZERO, Vector3(5, 0, 5))
	assert_eq(default_set.size(), 10, "inner ring is opt-in")


# ── Wrong-side filter ───────────────────────────────────────────────────────

func test_wrong_side_candidates_are_filtered() -> void:
	# Carrier at (0, 0, 0). Polar samples include (0, 0, -3) (angle
	# 270° — toward opp net for Team 0). That candidate is between
	# carrier and the OPP net, the wrong side. PRESSURE must never
	# pick it; chosen target.z >= carrier.z.
	var carrier_pos := Vector3(0, 0, 0)
	var skaters: Array = [
		[1, TEAM_ID, Vector3(-3, 0, -2), Vector3.ZERO],  # us, currently on wrong side
		[200, 1 - TEAM_ID, carrier_pos, Vector3.ZERO],
	]
	var ctx: RoleContext = _make_ctx(Vector3(-3, 0, -2), 200, skaters)
	var d: RoleDecision = AIRolePressure.decide(ctx)
	assert_true(d.target_position.z >= carrier_pos.z - 0.01,
			"wrong-side candidates must be filtered; chosen target.z=%f vs carrier.z=%f" % [d.target_position.z, carrier_pos.z])


# ── The last-man step-up clamp (AILastManDiscipline.settable_stand_depth) ──────────
# PRESSURE's cut-off sits one stick goal-side of where the carrier is GOING —
# a challenge position, and the right one while a layer is home behind. As the
# genuine LAST man it is also a step-up, and a rush at pace is exactly when that
# step-up cannot be made.
#
# That bound is now RETIRED for a live carrier and survives only for a loose puck
# — see test_the_last_man_bound_is_retired_for_a_live_carrier below for why. What
# these pin instead is the GAP LADDER (docs/transition-defense-plan.md §6), which
# PRESSURE never had: ~3 sticks at their blue line, 1 stick at ours, "1 stick /
# contact — you are on him" inside our own zone. §2.5 is the sentence it restores
# — "the D who gapped a carrier through the neutral zone KEEPS HIM into the zone;
# there is no handoff at the line" — since RUSH_D1 and PRESSURE now size the same
# gap off the same ladder.
#
# These pin the DOCTRINE, not the arithmetic. The clamp has been re-derived twice
# and then retired; the properties below are what must survive any version.

# Depth of the chosen stand, goal-side of the carrier along the carrier→our-net
# line. Larger = deeper = further from the carrier.
func _stand_depth(d: RoleDecision, carrier: Vector3) -> float:
	var to_net: Vector3 = Vector3(0.0, 0.0, OUR_NET_Z) - carrier
	var n: float = sqrt(to_net.x * to_net.x + to_net.z * to_net.z)
	if n < 0.001:
		return 0.0
	return ((d.target_position.x - carrier.x) * to_net.x
			+ (d.target_position.z - carrier.z) * to_net.z) / n


# A last man 12 m goal-side of a carrier flying at our net, vs the same
# geometry with a teammate home behind him.
func _rush_ctx(support_behind: bool, carrier_speed: float) -> Dictionary:
	return _rush_ctx_at(Vector3(0.0, 0.0, 0.0), carrier_speed, support_behind)


# The same, with the carrier placed explicitly — the ladder is a function of
# where he is, so its cases need to move him.
func _rush_ctx_at(carrier: Vector3, carrier_speed: float,
		support_behind: bool = true) -> Dictionary:
	var self_pos := Vector3(0.0, 0.0, 12.0)
	var vel := Vector3(0.0, 0.0, carrier_speed)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[200, 1 - TEAM_ID, carrier, vel],
	]
	if support_behind:
		skaters.append([2, TEAM_ID, Vector3(0.0, 0.0, 22.0)])
	var ctx: RoleContext = _make_ctx(self_pos, 200, skaters)
	ctx.self_max_speed = 9.0
	# Keep the body-check path out of it — this is about the stand.
	ctx.check_aggression = 0.0
	return {"ctx": ctx, "carrier": carrier}


func test_the_stand_is_the_gap_ladder() -> void:
	# The doctrine distance, and the defect it replaced. PRESSURE used to hold a
	# fixed one-stick stand-off measured off the carrier's LED position, so the
	# real cushion was `one stick + pace x lookahead` — 3+ sticks at a rush pace,
	# which is docs/transition-defense-plan.md §2.4 verbatim: "the correct gap for
	# the offensive blue line, applied at the defensive blue line". The ladder
	# (§6) is a function of ICE REMAINING and reads ~1 stick in our own zone.
	var ctx: Dictionary = _rush_ctx(true, 7.0)
	var d: RoleDecision = AIRolePressure.decide(ctx["ctx"])
	var ap := AICarrierApproach.new()
	AIDefensiveVerbs.fill_approach(ctx["ctx"], ctx["carrier"], Vector3(0.0, 0.0, 7.0), ap)
	var want: float = AIRoleRushD.ladder_gap_m(
			ctx["carrier"], 1.0, ctx["ctx"].self_blade_reach,
			AIRoleRushD.ramp_cushion_m(ctx["ctx"], ap, 200))
	assert_almost_eq(_stand_depth(d, ctx["carrier"]), want, 1.2,
			"the cut-off distance is the gap ladder; wanted ~%.2f m" % want)


func test_the_ladder_tightens_as_the_carrier_gets_deeper() -> void:
	# ~3 sticks at their blue line, 1 stick at ours. The old fixed stand-off could
	# not express this at all, which is why the bot held an O-zone gap at its own
	# net.
	var far: Dictionary = _rush_ctx_at(Vector3(0.0, 0.0, -7.29), 7.0)
	var near: Dictionary = _rush_ctx_at(Vector3(0.0, 0.0, 7.29), 7.0)
	assert_gt(_stand_depth(AIRolePressure.decide(far["ctx"]), far["carrier"]),
			_stand_depth(AIRolePressure.decide(near["ctx"]), near["carrier"]),
			"the gap must tighten as the carrier eats the ice")


func test_the_stand_rides_the_carrier() -> void:
	# The route is flown in the carrier's frame (AISteering's moving-frame
	# pursuit), which is what lets a ~1-stick gap be HELD rather than lunged at.
	var ctx: Dictionary = _rush_ctx(true, 7.0)
	var d: RoleDecision = AIRolePressure.decide(ctx["ctx"])
	assert_almost_eq(d.target_velocity.z, 7.0, 0.01,
			"the cut-off rides the man it is cutting off")
	assert_eq(d.engaged_peer_id, 200,
			"the man we are closing on is dropped from the proximity repel")


func test_the_last_man_bound_is_retired_for_a_live_carrier() -> void:
	# It exists because a parked-point seek could only reach a stand by charging
	# it; the moving-frame route regulates the approach instead, so running both
	# is two controllers on one axis — and the second wins in the worst place, by
	# naming a stand at wherever the body already is. That is what walked the
	# pressurer to his own goal line: a defender whose stand is always where he
	# stands can never close, so the carrier simply pushes him back. Same
	# retirement, same reason, as AIRoleRushD._settable_gap. The bound only ever
	# deepens a stand; the man behind may still move the bearing the argmax
	# picks, since he is part of the defence it prices the carrier against.
	var alone: Dictionary = _rush_ctx(false, 7.0)
	var layered: Dictionary = _rush_ctx(true, 7.0)
	assert_lte(
			_stand_depth(AIRolePressure.decide(alone["ctx"]), alone["carrier"]),
			_stand_depth(AIRolePressure.decide(layered["ctx"]), layered["carrier"]) + 0.05,
			"the last man reads the ladder, not a depth bound")


func test_a_body_in_his_lane_takes_the_drive_standing_or_riding() -> void:
	# A body 1.8 m in front of a carrier at speed takes most of his drive whether
	# he stands there (the carrier skates into his full reach) or rides it at the
	# carrier's pace. PRESSURE still prices its stands at the ride it skates them
	# at (a moving frame); this holds that neither reading lets the carrier
	# through a man in his lane.
	var our_net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var keeper := our_net + Vector3(0.0, 0.0, 0.8)
	# The routing sweep's z -20 / x -6 rush, the tick it went wrong: the stand the
	# gap ladder named, a little inside his line to the net.
	var carrier := Vector3(-3.66, 0.0, -15.02)
	var carrier_vel := Vector3(1.7, 0.0, -8.3)
	var in_lane := Vector3(-2.34, 0.0, -16.49)
	var nobody: Array[Vector3] = []
	var still: Array[Vector3] = []
	var poss := AIPossessionValue.new()
	poss.fill(our_net, nobody, still, [])
	var receivers: Array[Vector3] = []
	var bases: Array[float] = []
	AIDefensiveVerbs.carrier_option_bases(poss, carrier, carrier_vel, keeper, receivers,
			bases)
	var standing: float = AIDefensiveVerbs.carrier_best_option(poss, in_lane,
			Vector3.ZERO, null, carrier, carrier_vel, keeper, receivers, bases)
	var riding: float = AIDefensiveVerbs.carrier_best_option(poss, in_lane,
			carrier_vel, null, carrier, carrier_vel, keeper, receivers, bases)
	gut.p("  open %.3f | standing in his lane %.3f | riding it %.3f"
			% [bases[0], standing, riding])
	assert_lt(riding, bases[0] * 0.5, "a body at his pace in his lane takes the drive")
	assert_lt(standing, bases[0] * 0.5, "a body standing in his lane takes the drive")


func test_a_loose_puck_keeps_the_last_man_bound() -> void:
	# No man to ride means the route is a point seek again, and the trip to the
	# stand genuinely needs bounding.
	var alone: Dictionary = _rush_ctx(false, 7.0)
	alone["ctx"].snapshot.puck_state.carrier_peer_id = -1
	alone["ctx"].snapshot.puck_state.position = alone["carrier"]
	alone["ctx"].snapshot.puck_state.velocity = Vector3(0.0, 0.0, 7.0)
	var layered: Dictionary = _rush_ctx(true, 7.0)
	layered["ctx"].snapshot.puck_state.carrier_peer_id = -1
	layered["ctx"].snapshot.puck_state.position = layered["carrier"]
	layered["ctx"].snapshot.puck_state.velocity = Vector3(0.0, 0.0, 7.0)
	var bounded: float = _stand_depth(
			AIRolePressure.decide(alone["ctx"]), alone["carrier"])
	var free: float = _stand_depth(
			AIRolePressure.decide(layered["ctx"]), layered["carrier"])
	assert_gt(bounded, free,
			"the last man still holds ice he cannot cover set; %.2f vs %.2f"
			% [bounded, free])


func test_pressure_calibration_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	var target: Vector3 = _shot_lane_target()
	snap.record("lone shooter, pressurer from the side, target x", target.x)
	snap.record("lone shooter, pressurer from the side, target z", target.z)
	var lightest: float = NAN
	for k: int in range(1, 21):
		if is_nan(lightest) and _head_on_check(0.05 * k).commit_check:
			lightest = 0.05 * k
	snap.record("lightest transfer that commits a head-on check from 2 m", lightest)
	snap.verify(self)


# ── The angle's finish: a lone pressurer the carrier has drawn level with ────
# The last man (no support behind) at (0, 12) in our zone, the carrier driving
# our net at `speed` from `carrier`.

func _level_ctx(carrier: Vector3, speed: float, aggression: float = 0.0) -> RoleContext:
	var ctx: RoleContext = _rush_ctx_at(carrier, speed, false)["ctx"]
	ctx.check_aggression = aggression
	return ctx


func test_level_with_a_carrier_driving_the_net_he_steps_into_his_path() -> void:
	var carrier := Vector3(1.5, 0.0, 11.5)
	var d: RoleDecision = AIRolePressure.decide(_level_ctx(carrier, 8.0))
	assert_true(d.pressures_puck, "the angle's finish plays the man")
	assert_false(d.face_travel, "still in front of him, he faces him")
	assert_lt(d.target_position.distance_to(carrier), 1.0,
			"at contact, in his path; got %s" % d.target_position)


func test_beaten_by_a_carrier_driving_the_net_he_skates_onto_his_hip() -> void:
	var carrier := Vector3(1.5, 0.0, 13.0)
	var d: RoleDecision = AIRolePressure.decide(_level_ctx(carrier, 8.0))
	assert_true(d.face_travel, "behind him, he turns and skates")
	assert_lt(d.target_position.distance_to(carrier), 1.0,
			"onto his hip; got %s" % d.target_position)


func test_a_carrier_still_a_gap_away_is_not_finished() -> void:
	var d: RoleDecision = AIRolePressure.decide(_level_ctx(Vector3(1.5, 0.0, 8.5), 8.0))
	assert_false(d.pressures_puck, "with ice to hold, the ladder holds it")


func test_a_carrier_standing_level_is_not_finished() -> void:
	# Not coming at our net: there is time to get goal-side of him instead.
	var d: RoleDecision = AIRolePressure.decide(_level_ctx(Vector3(1.5, 0.0, 11.5), 0.0))
	assert_false(d.pressures_puck)


func test_the_last_man_checks_a_carrier_drawn_level_but_not_one_a_gap_away() -> void:
	var level: RoleDecision = AIRolePressure.decide(_level_ctx(Vector3(1.0, 0.0, 11.0), 8.0, 1.0))
	assert_true(level.commit_check, "level, the inside is lost: the check is his play")
	var away: RoleDecision = AIRolePressure.decide(_level_ctx(Vector3(1.0, 0.0, 8.5), 8.0, 1.0))
	assert_false(away.commit_check, "a gap away, the last man never throws one")

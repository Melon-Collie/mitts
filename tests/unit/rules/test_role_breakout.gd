extends GutTest

# AIRoleBreakout's decide() integrates existing primitives (lane_clear + our
# possession read) over a side-gated candidate set. These tests cover the
# structural contracts rather than re-testing the scoring math (covered in
# test_ai_action_scoring and test_possession_value):
#   - Bail-out when there's no puck.
#   - STRONG sets up on the strong side; WEAK on the weak side.
#   - WEAK stays goal-side of the carrier (reverse valve); STRONG may
#     advance up-ice past the carrier.
# Where the argmax currently stages each fixture is the snapshot,
# test_breakout_staging_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/role_breakout.txt"
const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z   # Team 0 defends +Z, attacks -Z
const DEEP_CARRIER_Z: float = 24.0
const STRONG_START := Vector3(11, 0, 22)
# Parked in the mid-seam lane near the blue line; his closing reach also
# brushes the high-wall lane, so both high spots are dead.
const HIGH_LANE_FORECHECKER := Vector3(6, 0, 13.0)
const WHEEL_START := Vector3(10, 0, 18)
const WHEELING_CARRIER := Vector3(11, 0, 22)
const OPP_NET_Z: float = -OUR_NET_Z


func _make_ctx(self_pos: Vector3, carrier_pid: int, skaters: Array,
		strong_x: float = 1.0) -> RoleContext:
	var snap := WorldSnapshot.new()
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
	snap.puck_state = puck

	var team_map: Dictionary = {}
	for entry: Array in skaters:
		team_map[entry[0]] = entry[1]

	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, OPP_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	ctx.strong_x = strong_x
	return ctx


func test_no_puck_stands_still() -> void:
	var self_pos := Vector3(5, 0, 20)
	var ctx := _make_ctx(self_pos, -1, [[1, TEAM_ID, self_pos]])
	ctx.snapshot.puck_state = null
	var d: RoleDecision = AIRoleBreakout.decide(ctx, true)
	assert_eq(d.target_position, self_pos, "no puck → stand still")


func test_strong_sets_up_on_strong_side() -> void:
	# Carrier deep in our own zone, strong side +X. The STRONG outlet
	# should target the +X half of the ice.
	var self_pos := Vector3(2, 0, 18)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],              # us (STRONG)
			[100, TEAM_ID, Vector3(0, 0, 24)],   # carrier, deep
			[200, 1, Vector3(0, 0, 10)],         # opp forechecker
	]
	var ctx := _make_ctx(self_pos, 100, skaters, 1.0)
	var d: RoleDecision = AIRoleBreakout.decide(ctx, true)
	assert_gt(d.target_position.x, 0.0, "strong outlet sets up on the +X strong side")


func test_weak_sets_up_on_weak_side() -> void:
	# Same setup; the WEAK outlet works the -X side when strong is +X.
	var self_pos := Vector3(-2, 0, 22)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],              # us (WEAK)
			[100, TEAM_ID, Vector3(0, 0, 24)],   # carrier, deep
			[200, 1, Vector3(0, 0, 10)],         # opp forechecker
	]
	var ctx := _make_ctx(self_pos, 100, skaters, 1.0)
	var d: RoleDecision = AIRoleBreakout.decide(ctx, false)
	assert_lt(d.target_position.x, 0.0, "weak outlet sets up on the -X weak side")


func test_weak_stays_goal_side_of_carrier() -> void:
	# The weak-side reverse valve must not drift up-ice past the carrier
	# (beyond the tolerance) — it's the safety release. own_goal_dir * z
	# grows toward our net, so the target's z must be >= carrier.z minus
	# the tolerance.
	var carrier_z: float = 20.0
	var self_pos := Vector3(-3, 0, 22)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[100, TEAM_ID, Vector3(0, 0, carrier_z)],
			[200, 1, Vector3(0, 0, 12)],
	]
	var ctx := _make_ctx(self_pos, 100, skaters, 1.0)
	var d: RoleDecision = AIRoleBreakout.decide(ctx, false)
	assert_gte(d.target_position.z,
			carrier_z - AIRoleSupport.GOAL_SIDE_TOLERANCE_M - 0.001,
			"weak valve stays goal-side of (no further up-ice than) the carrier")


func _strong_target(carrier_z: float, opp: Vector3) -> Vector3:
	var skaters: Array = [
			[1, TEAM_ID, STRONG_START],                   # us (STRONG)
			[100, TEAM_ID, Vector3(0, 0, carrier_z)],     # carrier, deep
			[200, 1, opp],
	]
	return AIRoleBreakout.decide(_make_ctx(STRONG_START, 100, skaters, 1.0), true).target_position


# The zone exit is our blue line; a stretch reads nearer it than the carrier.
func _assert_stretches_toward_the_exit(target: Vector3, carrier_z: float) -> void:
	assert_lt(absf(target.z - GameRules.BLUE_LINE_Z), absf(target.z - carrier_z),
			"stretches toward the zone exit rather than a short lead; got %s" % target)


func test_strong_stretches_toward_the_exit_when_open() -> void:
	# Carrier deep; the strong-side wall is open (the opponent is off it).
	var target: Vector3 = _strong_target(DEEP_CARRIER_Z, Vector3(-6, 0, 10))
	_assert_stretches_toward_the_exit(target, DEEP_CARRIER_Z)


func test_strong_drops_back_when_high_lanes_covered() -> void:
	# Same carrier, but a forechecker covers both high lanes: STRONG can't thread
	# either, so it picks a deeper open spot — lane_clear gates the stretch.
	var open_z: float = _strong_target(DEEP_CARRIER_Z, Vector3(-6, 0, 10)).z
	var covered_z: float = _strong_target(DEEP_CARRIER_Z, HIGH_LANE_FORECHECKER).z
	assert_gt(covered_z, open_z,
			"covered high lanes → STRONG drops to a deeper open spot; open z=%f covered z=%f" % [open_z, covered_z])


# STRONG on the wall while the carrier wheels up that same wall at 6 m/s.
func _wheel_target(opp: Vector3) -> Vector3:
	var skaters: Array = [
			[1, TEAM_ID, WHEEL_START],
			[100, TEAM_ID, WHEELING_CARRIER, Vector3(0, 0, -6)],
			[200, 1, opp],
	]
	return AIRoleBreakout.decide(_make_ctx(WHEEL_START, 100, skaters, 1.0), true).target_position


func _assert_in_the_mid_seam(target: Vector3) -> void:
	assert_gt(target.x, 0.0, "still works the strong side")
	assert_lt(target.x, GameRules.RINK_HALF_WIDTH - AIRoleBreakout.WALL_INSET_M - 1.0,
			"…but off the carrier's wall lane, into the mid-seam; got x=%f" % target.x)


func test_strong_offers_mid_seam_when_carrier_wheels_the_wall_unpressured() -> void:
	# No coverage on either column. The wall spots offer no lane advantage over
	# the mid-seam ones (the wall lane is the carrier's own route), so the outlet
	# gives him a diagonal give-option in the middle instead of camping in his
	# skating lane.
	var target: Vector3 = _wheel_target(Vector3(-6, 0, 10))
	_assert_in_the_mid_seam(target)
	_assert_stretches_toward_the_exit(target, WHEELING_CARRIER.z)


func test_strong_swings_mid_seam_when_wall_route_is_covered() -> void:
	# An NZ forechecker parked on the high strong wall: the wall column is dead
	# (the carrier's own route AND covered), so the outlet swings to the mid-seam
	# and keeps presenting up-ice rather than hanging deep beside the carrier.
	var target: Vector3 = _wheel_target(Vector3(10.5, 0, 9))
	_assert_in_the_mid_seam(target)
	_assert_stretches_toward_the_exit(target, WHEELING_CARRIER.z)


func test_strong_keeps_skating_route_when_every_lane_is_dead() -> void:
	# A forechecker draped right on the carrier blocks EVERY pass lane at
	# the release point (reachability model: a defender within a stick of
	# the origin blocks all lanes). With no feed to read, the spots rank by the
	# possession read (AIFeedStationPick), so the outlet never freezes at self_pos.
	var self_pos := Vector3(9, 0, 20)
	var carrier_pos := Vector3(0, 0, 24)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[100, TEAM_ID, carrier_pos],
			[200, 1, carrier_pos],   # forechecker stick-on-stick with the carrier
	]
	var ctx := _make_ctx(self_pos, 100, skaters, 1.0)
	var d: RoleDecision = AIRoleBreakout.decide(ctx, true)
	assert_ne(d.target_position, self_pos,
			"dead lanes must not freeze the outlet in place")
	assert_lt(d.target_position.z, self_pos.z,
			"the outlet keeps working up-ice toward the zone exit; got z=%f" % d.target_position.z)


func test_strong_follows_strong_x_flip() -> void:
	# Flip strong side to -X: STRONG now works the -X half.
	var self_pos := Vector3(-2, 0, 18)
	var skaters: Array = [
			[1, TEAM_ID, self_pos],
			[100, TEAM_ID, Vector3(0, 0, 24)],
			[200, 1, Vector3(0, 0, 10)],
	]
	var ctx := _make_ctx(self_pos, 100, skaters, -1.0)
	var d: RoleDecision = AIRoleBreakout.decide(ctx, true)
	assert_lt(d.target_position.x, 0.0, "strong outlet follows the flipped (-X) strong side")


# ── 5v5 wall post (breakout plan §C.1) ───────────────────────────────────────
# In 5v5 the STRONG outlet is a WALL POST: it adjusts along the boards and
# yields the mid-seam only when the carrier's own route occupies the wall
# lane (his wheel). 3v3 keeps both columns (the rover swing).

func test_5v5_strong_holds_the_wall_past_a_half_wall_camper() -> void:
	# A forechecker camped on the half-wall lane: the 3v3 argmax would swing
	# inside; the 5v5 post holds the boards and slides along them instead.
	var self_pos := Vector3(11.0, 0, 15.0)
	var carrier := Vector3(3.0, 0, 24.0)
	var ctx := _make_ctx(self_pos, 2, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, carrier],
			[10, 1, Vector3(10.5, 0, 16.0)]])
	ctx.team_size = 5
	var d: RoleDecision = AIRoleBreakout.decide(ctx, true)
	assert_gt(d.target_position.x, GameRules.RINK_HALF_WIDTH - 2.5,
			"the 5v5 winger is a wall post — he slides ALONG the boards")


func test_5v5_strong_yields_the_wall_to_the_carriers_own_route() -> void:
	# The carrier himself is driving up the wall lane (his wheel exit): the
	# post yields — the mid-seam column reopens so the outlet swings inside
	# instead of standing in the carrier's road.
	var self_pos := Vector3(11.0, 0, 15.0)
	var carrier := Vector3(11.2, 0, 22.0)
	var ctx := _make_ctx(self_pos, 2, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, carrier],
			[10, 1, Vector3(10.5, 0, 16.0)]])
	ctx.team_size = 5
	var d: RoleDecision = AIRoleBreakout.decide(ctx, true)
	assert_lt(d.target_position.x, GameRules.RINK_HALF_WIDTH - 2.5,
			"the wall is the carrier's road — the outlet swings inside")


func _camped_wall_target(team_size: int) -> Vector3:
	var self_pos := Vector3(11.0, 0, 15.0)
	var ctx := _make_ctx(self_pos, 2, [
			[1, TEAM_ID, self_pos],
			[2, TEAM_ID, Vector3(3.0, 0, 24.0)],
			[10, 1, Vector3(10.5, 0, 16.0)]])
	ctx.team_size = team_size
	return AIRoleBreakout.decide(ctx, true).target_position


func test_3v3_strong_keeps_the_two_column_swing() -> void:
	# The camped-wall setup the 5v5 post holds against: 3v3 keeps both columns,
	# so its outlet is never bound to the boards the way the post is.
	assert_lt(_camped_wall_target(3).x, _camped_wall_target(5).x,
			"3v3 keeps the inside swing the 5v5 wall post gives up")


func test_strong_wall_stance_leaves_the_rim_line_in_blade_reach() -> void:
	# The STRONG outlet is the designated rim receiver: his wall stance must
	# keep the boards line (where a rim actually travels) inside a
	# comfortable blade extension — the old 2.0 m inset left the rim
	# physically untouchable and every rim-around sailed past the post man.
	var stance_x: float = GameRules.RINK_HALF_WIDTH - AIRoleBreakout.WALL_INSET_M
	var reach: float = GameRules.DEFAULT_STICK_LENGTH_M \
			+ GameRules.DEFAULT_BLADE_LENGTH_M - 0.2
	assert_lt(GameRules.INNER_HALF_WIDTH - stance_x, reach,
			"wall stance keeps the rim line within the blade's receive reach")


func test_breakout_staging_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	var rows: Dictionary = {
		"STRONG, open wall": _strong_target(DEEP_CARRIER_Z, Vector3(-6, 0, 10)),
		"STRONG, both high lanes covered": _strong_target(DEEP_CARRIER_Z, HIGH_LANE_FORECHECKER),
		"STRONG, carrier wheels the wall unpressured": _wheel_target(Vector3(-6, 0, 10)),
		"STRONG, carrier wheels a covered wall": _wheel_target(Vector3(10.5, 0, 9)),
		"STRONG 3v3, half-wall camper": _camped_wall_target(3),
		"STRONG 5v5, half-wall camper": _camped_wall_target(5),
	}
	for key: String in rows:
		var target: Vector3 = rows[key]
		snap.record("%s, target x" % key, target.x)
		snap.record("%s, target z" % key, target.z)
	snap.verify(self)

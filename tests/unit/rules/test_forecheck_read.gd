extends GutTest

# AIForecheckRead — can we get on their puck before it is out of their zone?
# And TeamBrain's use of it: forecheck when we can, set up the neutral zone when
# we cannot. Team 0 defends +Z and attacks -Z; their zone is z < -BLUE_LINE_Z.

const OUR_NET_Z: float = GameRules.GOAL_LINE_Z
const TEAM_ID: int = 0


# skaters: [peer, team, position, velocity?]
func _snap(skaters: Array, carrier_pid: int, puck_pos: Vector3 = Vector3.INF) -> WorldSnapshot:
	var snap := WorldSnapshot.new()
	for e: Array in skaters:
		var s := SkaterNetworkState.new()
		s.position = e[2]
		s.velocity = e[3] if e.size() > 3 else Vector3.ZERO
		snap.skater_states[e[0]] = s
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = carrier_pid
	puck.position = snap.skater_states[carrier_pid].position \
			if carrier_pid != -1 else puck_pos
	snap.puck_state = puck
	return snap


func _teams(skaters: Array) -> Dictionary:
	var m: Dictionary = {}
	for e: Array in skaters:
		m[e[0]] = e[1]
	return m


func _margin(skaters: Array, carrier_pid: int, puck_pos: Vector3 = Vector3.INF) -> float:
	return AIForecheckRead.pressure_margin_s(_snap(skaters, carrier_pid, puck_pos),
			TEAM_ID, OUR_NET_Z, _teams(skaters), {}, {}, false)


func test_a_carrier_behind_his_net_with_us_close_is_forechecked() -> void:
	var skaters: Array = [
		[1, 0, Vector3(2.0, 0.0, -18.0)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
	]
	assert_true(AIForecheckRead.can_forecheck(_margin(skaters, 200), false),
			"we are on him before he is out")


func test_a_carrier_already_skating_out_past_us_is_not() -> void:
	# He is at his line with speed, our nearest man deep behind him.
	var skaters: Array = [
		[1, 0, Vector3(0.0, 0.0, -24.0)],
		[200, 1, Vector3(3.0, 0.0, -10.0), Vector3(0.0, 0.0, 8.0)],
	]
	assert_false(AIForecheckRead.can_forecheck(_margin(skaters, 200), false),
			"he is gone: set up instead")


func test_a_far_forechecker_loses_the_race() -> void:
	# Our nearest is back at our own line; he is retrieving at his.
	var skaters: Array = [
		[1, 0, Vector3(0.0, 0.0, 8.0)],
		[200, 1, Vector3(-4.0, 0.0, -24.0), Vector3(0.0, 0.0, 3.0)],
	]
	assert_false(AIForecheckRead.can_forecheck(_margin(skaters, 200), false),
			"nobody can get there")


func test_the_margin_grows_as_our_man_gets_closer() -> void:
	var near: float = _margin([
		[1, 0, Vector3(0.0, 0.0, -16.0)],
		[200, 1, Vector3(0.0, 0.0, -24.0), Vector3(0.0, 0.0, 3.0)]], 200)
	var far: float = _margin([
		[1, 0, Vector3(0.0, 0.0, 6.0)],
		[200, 1, Vector3(0.0, 0.0, -24.0), Vector3(0.0, 0.0, 3.0)]], 200)
	assert_gt(near, far, "a nearer forechecker has more time in hand")


func test_hysteresis_holds_a_forecheck_inside_its_band() -> void:
	var m: float = (AIForecheckRead.ENTER_MARGIN_S + AIForecheckRead.HOLD_MARGIN_S) * 0.5
	assert_false(AIForecheckRead.can_forecheck(m, false), "not enough to start one")
	assert_true(AIForecheckRead.can_forecheck(m, true), "enough to keep one going")


func test_only_a_forward_can_be_the_5v5_f1() -> void:
	# Our only body near him is a D (lobby slot 3): in 5v5 he holds the line.
	var skaters: Array = [
		[1, 0, Vector3(2.0, 0.0, -18.0)],
		[2, 0, Vector3(0.0, 0.0, 10.0)],
		[200, 1, Vector3(0.0, 0.0, -24.0), Vector3(0.0, 0.0, 3.0)],
	]
	var snap: WorldSnapshot = _snap(skaters, 200)
	var teams: Dictionary = _teams(skaters)
	var any_body: float = AIForecheckRead.pressure_margin_s(snap, TEAM_ID, OUR_NET_Z,
			teams, {}, {1: 3, 2: 0}, false)
	var forwards: float = AIForecheckRead.pressure_margin_s(snap, TEAM_ID, OUR_NET_Z,
			teams, {}, {1: 3, 2: 0}, true)
	assert_gt(any_body, forwards, "the D is not counted as a forechecker in 5v5")


func test_the_puck_outside_their_zone_is_no_forecheck() -> void:
	var skaters: Array = [
		[1, 0, Vector3(2.0, 0.0, -2.0)],
		[200, 1, Vector3(0.0, 0.0, 0.0)],
	]
	assert_eq(_margin(skaters, 200), -INF)


func test_a_loose_puck_we_tie_for_is_ours_to_chase() -> void:
	# A 50/50 in their end: equal trips, so the contest band decides it for us.
	var skaters: Array = [
		[1, 0, Vector3(-4.0, 0.0, -20.0)],
		[200, 1, Vector3(4.0, 0.0, -20.0)],
	]
	var m: float = _margin(skaters, -1, Vector3(0.0, 0.0, -20.0))
	assert_gt(m, AIForecheckRead.ENTER_MARGIN_S,
			"a tie for the puck is a forecheck; margin %.2f s" % m)


# ── The brain picks the shape ────────────────────────────────────────────────

func _brain_state(skaters: Array, carrier_pid: int) -> int:
	var brain := TeamBrain.new(TEAM_ID, _teams(skaters), {}, 3)
	brain.force_retick()
	brain.tick(0.01, _snap(skaters, carrier_pid))
	return brain.state


func test_the_brain_forechecks_a_carrier_it_can_get_on() -> void:
	assert_eq(_brain_state([
		[1, 0, Vector3(2.0, 0.0, -18.0)],
		[2, 0, Vector3(-2.0, 0.0, -10.0)],
		[3, 0, Vector3(0.0, 0.0, -4.0)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
	], 200), AIPossessionState.State.FORECHECK)


func test_the_brain_sets_up_against_a_carrier_it_cannot() -> void:
	assert_eq(_brain_state([
		[1, 0, Vector3(2.0, 0.0, 10.0)],
		[2, 0, Vector3(-2.0, 0.0, 14.0)],
		[3, 0, Vector3(0.0, 0.0, 18.0)],
		[200, 1, Vector3(0.0, 0.0, -20.0), Vector3(0.0, 0.0, 6.0)],
	], 200), AIPossessionState.State.TRANS_DEFENSE)

extends GutTest

# AIForecheckRead — can we get a stick on their puck before its carrier can
# move it? And TeamBrain's use of it: forecheck when we can, set up the neutral
# zone when we cannot. Team 0 defends +Z and attacks -Z; their zone is z < -BLUE_LINE_Z.

const OUR_NET_Z: float = GameRules.GOAL_LINE_Z
const TEAM_ID: int = 0


# skaters: [peer, team, position, velocity?]
func _snap(skaters: Array, carrier_pid: int, puck_pos: Vector3 = Vector3.INF,
		puck_vel: Vector3 = Vector3.ZERO) -> WorldSnapshot:
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
	puck.velocity = puck_vel
	snap.puck_state = puck
	return snap


func _teams(skaters: Array) -> Dictionary:
	var m: Dictionary = {}
	for e: Array in skaters:
		m[e[0]] = e[1]
	return m


func _margin(skaters: Array, carrier_pid: int, puck_pos: Vector3 = Vector3.INF,
		puck_vel: Vector3 = Vector3.ZERO) -> float:
	return AIForecheckRead.pressure_margin_s(_snap(skaters, carrier_pid, puck_pos, puck_vel),
			TEAM_ID, OUR_NET_Z, _teams(skaters), {}, {}, false)


func test_a_carrier_behind_his_net_with_us_on_him_is_forechecked() -> void:
	var skaters: Array = [
		[1, 0, Vector3(1.0, 0.0, -27.0)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
	]
	assert_true(AIForecheckRead.can_forecheck(_margin(skaters, 200), false),
			"our stick is on the puck before he can move it")


func test_a_carrier_with_time_to_make_his_pass_is_not() -> void:
	# Our man is coming from the circle top, but the D behind his net has the
	# puck settled: the stretch pass is away before we get there.
	var skaters: Array = [
		[1, 0, Vector3(4.0, 0.0, -18.0), Vector3(0.0, 0.0, -6.0)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
	]
	assert_false(AIForecheckRead.can_forecheck(_margin(skaters, 200), false),
			"he has the time to move it: set up")


func test_a_carrier_who_has_just_got_it_is_pressured_one_who_has_read_it_is_not() -> void:
	# Our man two metres off: on a carrier still looking up, not on one who has
	# had the puck long enough to pick his pass.
	var skaters: Array = [
		[1, 0, Vector3(1.5, 0.0, -26.5)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
	]
	var snap: WorldSnapshot = _snap(skaters, 200)
	var fresh: float = AIForecheckRead.pressure_margin_s(snap, TEAM_ID, OUR_NET_Z,
			_teams(skaters), {}, {}, false, 0.0)
	var settled: float = AIForecheckRead.pressure_margin_s(snap, TEAM_ID, OUR_NET_Z,
			_teams(skaters), {}, {}, false, AIForecheckRead.CARRIER_READ_S)
	assert_true(AIForecheckRead.can_forecheck(fresh, false), "fresh: %.2f s" % fresh)
	assert_false(AIForecheckRead.can_forecheck(settled, false), "settled: %.2f s" % settled)


func test_a_loose_puck_he_must_still_pick_up_is_forechecked() -> void:
	# The same two bodies, but the puck is loose in the corner: picking it up and
	# settling it buys our man the time he lacked against a carried puck.
	var skaters: Array = [
		[1, 0, Vector3(4.0, 0.0, -18.0), Vector3(0.0, 0.0, -6.0)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
	]
	assert_true(AIForecheckRead.can_forecheck(
			_margin(skaters, -1, Vector3(6.0, 0.0, -26.0)), false),
			"we are on him as he collects it")


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


# A dump from the red line into their strong-side corner, our winger flying down
# that wall from `winger_z` at `winger_vz`; their D at `d_pos`.
func _dump_race(winger_z: float, winger_vz: float,
		d_pos: Vector3 = Vector3(-3.0, 0.0, -24.0)) -> float:
	return _margin([
		[1, 0, Vector3(9.0, 0.0, winger_z), Vector3(0.0, 0.0, winger_vz)],
		[200, 1, d_pos],
	], -1, Vector3(2.0, 0.0, -1.0), Vector3(5.0, 0.0, -16.0))


func test_a_dump_is_raced_where_it_is_played_not_where_it_is() -> void:
	# Still in the neutral zone, but our winger is on it in their corner.
	assert_true(AIForecheckRead.can_forecheck(_dump_race(-6.0, -8.0), false),
			"a dump our winger wins is a forecheck from the release")


func test_a_dump_into_their_d_with_nobody_following_is_lost() -> void:
	# Their D stands in its path inside his line; our only man is back in our
	# zone, standing: the D plays it and is gone.
	assert_false(AIForecheckRead.can_forecheck(
			_dump_race(16.0, 0.0, Vector3(6.0, 0.0, -12.0)), false),
			"nobody gets on their D before he is out: set up")


func test_a_pass_we_take_before_their_line_is_no_forecheck() -> void:
	# A feed up the middle to a man in the neutral zone is played there.
	assert_eq(_margin([
		[1, 0, Vector3(0.0, 0.0, -6.0)],
		[200, 1, Vector3(0.0, 0.0, -24.0)],
	], -1, Vector3(0.0, 0.0, 6.0), Vector3(0.0, 0.0, -14.0)), -INF)


# ── The brain picks the shape ────────────────────────────────────────────────

func _brain_state(skaters: Array, carrier_pid: int) -> int:
	var brain := TeamBrain.new(TEAM_ID, _teams(skaters), {}, 3)
	brain.force_retick()
	brain.tick(0.01, _snap(skaters, carrier_pid))
	return brain.state


func test_the_brain_forechecks_a_carrier_it_can_get_on() -> void:
	assert_eq(_brain_state([
		[1, 0, Vector3(1.0, 0.0, -27.0)],
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


# Our carrier releases at `release_z` toward their corner, our winger flying down
# the wall and their D back at his net; the brain's shape with it in flight.
func _shape_after_release(release_z: float) -> int:
	var skaters: Array = [
		[1, 0, Vector3(2.0, 0.0, release_z)],
		[2, 0, Vector3(9.0, 0.0, release_z - 4.0), Vector3(0.0, 0.0, -8.0)],
		[3, 0, Vector3(-4.0, 0.0, release_z + 8.0)],
		[200, 1, Vector3(-4.0, 0.0, -26.0)],
	]
	var brain := TeamBrain.new(TEAM_ID, _teams(skaters), {}, 3)
	brain.force_retick()
	brain.tick(0.01, _snap(skaters, 1))
	var loose: WorldSnapshot = _snap(skaters, -1, Vector3(2.5, 0.0, release_z - 1.0),
			Vector3(5.0, 0.0, -16.0))
	loose.loose_puck_released_by = 1
	brain.force_retick()
	brain.tick(0.01, loose)
	return brain.state


func test_a_dump_in_opens_the_forecheck_at_the_release() -> void:
	assert_eq(_shape_after_release(-1.0), AIPossessionState.State.FORECHECK,
			"the point of a dump is the forecheck it starts")


func test_the_same_release_inside_their_zone_keeps_the_attack() -> void:
	assert_eq(_shape_after_release(-12.0), AIPossessionState.State.OZONE,
			"a puck moved inside their zone is still our attack")


# ── Pressure restarts his read ───────────────────────────────────────────────

func test_a_man_a_stick_off_him_is_on_him_one_at_the_circle_is_not() -> void:
	var on: Array = [[1, 0, Vector3(1.5, 0.0, -27.0)], [200, 1, Vector3(0.0, 0.0, -28.0)]]
	var off: Array = [[1, 0, Vector3(4.0, 0.0, -20.0)], [200, 1, Vector3(0.0, 0.0, -28.0)]]
	assert_true(AIForecheckRead.carrier_pressured(_snap(on, 200), TEAM_ID, _teams(on), {}))
	assert_false(AIForecheckRead.carrier_pressured(_snap(off, 200), TEAM_ID, _teams(off), {}))


func test_our_own_carrier_is_never_pressured_by_us() -> void:
	var skaters: Array = [[1, 0, Vector3(1.5, 0.0, -27.0)], [2, 0, Vector3(0.0, 0.0, -28.0)]]
	assert_false(AIForecheckRead.carrier_pressured(_snap(skaters, 2), TEAM_ID,
			_teams(skaters), {}))


# Their D settled behind his net with his wingers up the ice, so only the
# pressure race can start a forecheck; our F1 at `f1`, our other two at
# `support_z`.
func _settled(f1: Vector3, support_z: float = 0.0) -> Array:
	return [
		[1, 0, f1],
		[2, 0, Vector3(-4.0, 0.0, support_z - 2.0)],
		[3, 0, Vector3(4.0, 0.0, support_z + 2.0)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
		[201, 1, Vector3(-9.0, 0.0, 0.0)],
		[202, 1, Vector3(9.0, 0.0, 0.0)],
	]


# The brain ticked `s` seconds on the settled carrier with our F1 at `f1`.
func _run(brain: TeamBrain, f1: Vector3, s: float, support_z: float = 0.0) -> void:
	var snap: WorldSnapshot = _snap(_settled(f1, support_z), 200)
	for _i: int in int(s / 0.02):
		brain.tick(0.02, snap)


func _settled_brain() -> TeamBrain:
	return TeamBrain.new(TEAM_ID, _teams(_settled(Vector3.ZERO)), {}, 3)


func test_a_settled_carrier_our_f1_gets_on_is_forechecked_again() -> void:
	var brain: TeamBrain = _settled_brain()
	_run(brain, Vector3(4.0, 0.0, -14.0), 1.5)
	assert_eq(brain.state, AIPossessionState.State.TRANS_DEFENSE,
			"he had the time: set up")
	_run(brain, Vector3(1.2, 0.0, -27.2), 0.5)
	assert_eq(brain.state, AIPossessionState.State.FORECHECK,
			"our F1 on him takes his look away: forecheck again")


func test_a_carrier_who_gets_free_again_reads_it_and_we_set_up() -> void:
	var brain: TeamBrain = _settled_brain()
	# Our other two up the ice with F1, so the depth read does not hold it.
	_run(brain, Vector3(1.2, 0.0, -27.2), 0.5, -14.0)
	assert_eq(brain.state, AIPossessionState.State.FORECHECK)
	_run(brain, Vector3(4.0, 0.0, -14.0), 1.5, -14.0)
	assert_eq(brain.state, AIPossessionState.State.TRANS_DEFENSE,
			"free long enough to read it, with a man up the ice to hit; depth %.2f s"
					% brain.forecheck_depth_margin_s)


# ── Depth holds a forecheck we are running ───────────────────────────────────

# Their D settled behind his net, his wingers at `wing_z`; our F1 off him at the
# circle, our other two back at the top of their zone.
func _depth_skaters(wing_z: float) -> Array:
	return [
		[1, 0, Vector3(4.0, 0.0, -18.0)],
		[2, 0, Vector3(-3.0, 0.0, -16.0)],
		[3, 0, Vector3(3.0, 0.0, -14.0)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
		[201, 1, Vector3(-9.0, 0.0, wing_z)],
		[202, 1, Vector3(9.0, 0.0, wing_z)],
	]


func _depth_margin(wing_z: float) -> float:
	var skaters: Array = _depth_skaters(wing_z)
	return AIForecheckRead.depth_margin_s(_snap(skaters, 200), TEAM_ID, OUR_NET_Z,
			_teams(skaters), {}, {}, false, AIForecheckRead.CARRIER_READ_S)


func test_with_everyone_of_theirs_deep_dropping_back_buys_nothing_yet() -> void:
	var m: float = _depth_margin(-24.0)
	assert_gt(m, AIForecheckRead.HOLD_MARGIN_S, "deep: our back two are home first; %.2f s" % m)


func test_a_winger_up_the_ice_is_a_play_our_back_line_must_meet() -> void:
	var m: float = _depth_margin(2.0)
	assert_lt(m, AIForecheckRead.HOLD_MARGIN_S, "a stretch pass beats them; %.2f s" % m)


func test_the_depth_margin_shrinks_as_their_wingers_go_up_the_ice() -> void:
	assert_gt(_depth_margin(-24.0), _depth_margin(-12.0))
	assert_gt(_depth_margin(-12.0), _depth_margin(0.0))


func test_the_5v5_back_line_is_the_d_pair() -> void:
	# The D pair caught at their line, a forward back home: the D still have to
	# get back, so the forward being home does not make the line set.
	var skaters: Array = [
		[1, 0, Vector3(-3.0, 0.0, -8.0)],
		[2, 0, Vector3(3.0, 0.0, -8.0)],
		[3, 0, Vector3(0.0, 0.0, 10.0)],
		[4, 0, Vector3(0.0, 0.0, 12.0)],
		[200, 1, Vector3(0.0, 0.0, -28.0)],
		[201, 1, Vector3(-9.0, 0.0, -12.0)],
	]
	var snap: WorldSnapshot = _snap(skaters, 200)
	var positions: Dictionary = {1: 3, 2: 4, 3: 0, 4: 1}
	var d_pair: float = AIForecheckRead.depth_margin_s(snap, TEAM_ID, OUR_NET_Z,
			_teams(skaters), {}, positions, true, AIForecheckRead.CARRIER_READ_S)
	var anyone: float = AIForecheckRead.depth_margin_s(snap, TEAM_ID, OUR_NET_Z,
			_teams(skaters), {}, positions, false, AIForecheckRead.CARRIER_READ_S)
	assert_lt(d_pair, anyone, "the D still have to get back")


func test_depth_holds_a_forecheck_but_never_starts_one() -> void:
	assert_false(AIForecheckRead.can_forecheck(-1.0, false, 5.0), "no pressure: no forecheck")
	assert_true(AIForecheckRead.can_forecheck(-1.0, true, 5.0), "running: held while it is cheap")
	assert_false(AIForecheckRead.can_forecheck(-1.0, true, -1.0), "neither: set up")


func test_the_brain_holds_a_deep_forecheck_its_f1_has_lost() -> void:
	for wing_z: float in [-24.0, 2.0]:
		var skaters: Array = _depth_skaters(wing_z)
		var brain := TeamBrain.new(TEAM_ID, _teams(skaters), {}, 3)
		# On him first: a forecheck.
		var on: Array = skaters.duplicate(true)
		on[0][2] = Vector3(1.2, 0.0, -27.2)
		for _i: int in 20:
			brain.tick(0.02, _snap(on, 200))
		assert_eq(brain.state, AIPossessionState.State.FORECHECK)
		# Then off him long enough for his read.
		var off: WorldSnapshot = _snap(skaters, 200)
		for _i: int in 75:
			brain.tick(0.02, off)
		assert_eq(brain.state, AIPossessionState.State.FORECHECK if wing_z < -20.0
				else AIPossessionState.State.TRANS_DEFENSE,
				"wingers at %.0f" % wing_z)

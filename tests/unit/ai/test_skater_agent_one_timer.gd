extends GutTest

# SkaterAgentOneTimer's reads against fabricated WorldSnapshots: the feed's
# remaining flight and the live-line settle anchor. The press state that acts on
# them is held through the state machine in test_one_timer_chain.gd and
# test_skater_agent_state_machine.gd.

# peer 1 = self (team 0, attacking -Z), peer 2 = teammate.
const SELF_ID := 1
const TEAMMATE_ID := 2
const ATTACKING_GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
var _team_map := {1: 0, 2: 0, 11: 1, 12: 1}

var ot: SkaterAgentOneTimer


func before_each() -> void:
	ot = SkaterAgentOneTimer.new()
	ot.setup(SELF_ID, 0, _team_map, false)


func _add_skater(s: WorldSnapshot, peer_id: int, pos: Vector3) -> void:
	var st := SkaterNetworkState.new()
	st.position = pos
	s.skater_states[peer_id] = st


func _feed_snap(puck_pos: Vector3, puck_vel: Vector3) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = puck_pos
	s.puck_state.velocity = puck_vel
	s.puck_state.carrier_peer_id = -1
	return s


func test_feed_time_reads_the_remaining_flight() -> void:
	# Puck 8 m up-line at 16 m/s → my perpendicular foot in 0.5 s: the aim
	# reads the goalie at feed ARRIVAL, not where he stands mid-re-square.
	var s := _feed_snap(Vector3(-8, 0, -1.5), Vector3(16, 0, 0))
	assert_almost_eq(SkaterAgentOneTimer.feed_time_s(s, Vector3.ZERO), 0.5, 0.01)
	# A dead/held puck reads as arriving now.
	var dead := _feed_snap(Vector3.ZERO, Vector3.ZERO)
	assert_almost_eq(SkaterAgentOneTimer.feed_time_s(dead, Vector3.ZERO), 0.0, 0.001)


# ── One-timer line settle: the anchor tracks the LIVE feed line ──────────────
# The physical catch needs the blade contact within the pickup radius of the
# puck's REAL path; the settle anchor is what puts the net-aimed blade there.

func test_line_anchor_puts_the_slapper_zone_on_the_live_line() -> void:
	# Team 0 attacks -Z. A hard feed crosses 1.5 m net-side of the bot along +X.
	# The slapper zone is the strike spot of a RH body whose hips have set
	# side-on for a shot at the net; the anchor is the nearest body spot that
	# puts it on the line — straight across the line, since the zone can meet
	# the puck anywhere along it.
	var foot := Vector3(0, 0, -1.5)
	var snap := _feed_snap(Vector3(-8, 0, foot.z), Vector3(16, 0, 0))
	var anchor: Vector3 = ot.line_anchor(snap, Vector3.ZERO, ATTACKING_GOAL)
	assert_true(anchor.is_finite(), "a live inbound feed defines a settle anchor")
	var to_net: Vector3 = ATTACKING_GOAL - foot
	to_net.y = 0.0
	var f: Vector3 = to_net.normalized()
	var off: Vector2 = SlapperRules.strike_offset(Vector2(f.x, f.z),
			AISkaterCaps.new().slapper_strike_local, 1.0, PI * 0.5)
	var zone: Vector3 = anchor + Vector3(off.x, 0.0, off.y)
	assert_almost_eq(zone.z, foot.z, 0.01, "the armed slapper ZONE sits exactly ON the line")
	assert_almost_eq(anchor.x, 0.0, 0.0001, "the body steps straight across the line")


func test_line_anchor_defers_to_a_better_positioned_teammate() -> void:
	# The feed crosses nearer a teammate — it's theirs; don't get dragged off
	# the station (mirror of SkaterAgentReception.incoming_pass's filter).
	var snap := _feed_snap(Vector3(-8, 0, -1.5), Vector3(16, 0, 0))
	_add_skater(snap, TEAMMATE_ID, Vector3(0.2, 0, -1.5))   # right at the crossing
	assert_false(ot.line_anchor(snap, Vector3.ZERO, ATTACKING_GOAL).is_finite(),
			"a teammate nearer the crossing owns the feed")


func test_line_anchor_follows_a_shifted_feed() -> void:
	# The same feed released one metre off the anticipated line: the anchor
	# shifts with it — a live re-read, never a latched prediction.
	var a1: Vector3 = ot.line_anchor(
			_feed_snap(Vector3(-8, 0, -1.5), Vector3(16, 0, 0)), Vector3.ZERO, ATTACKING_GOAL)
	var a2: Vector3 = ot.line_anchor(
			_feed_snap(Vector3(-8, 0, -2.5), Vector3(16, 0, 0)), Vector3.ZERO, ATTACKING_GOAL)
	assert_almost_eq(a2.z - a1.z, -1.0, 0.01,
			"the settle anchor tracks the feed's actual line")


func test_line_anchor_ignores_non_feeds() -> void:
	var held := _feed_snap(Vector3(-8, 0, -1.5), Vector3(16, 0, 0))
	held.real_puck_carrier_peer_id = 7
	assert_false(ot.line_anchor(held, Vector3.ZERO, ATTACKING_GOAL).is_finite(),
			"a held puck is not a feed")
	assert_false(ot.line_anchor(
			_feed_snap(Vector3(-8, 0, -1.5), Vector3(5, 0, 0)), Vector3.ZERO, ATTACKING_GOAL).is_finite(),
			"a drifting puck is not a feed to settle on")
	assert_false(ot.line_anchor(
			_feed_snap(Vector3(8, 0, -1.5), Vector3(16, 0, 0)), Vector3.ZERO, ATTACKING_GOAL).is_finite(),
			"already past our level — the chase owns it")
	assert_false(ot.line_anchor(
			_feed_snap(Vector3(-8, 0, -7.0), Vector3(16, 0, 0)), Vector3.ZERO, ATTACKING_GOAL).is_finite(),
			"a feed crossing far away doesn't drag us off the spot")


func test_a_feed_on_the_one_timer_tape_needs_no_shuffle() -> void:
	# The passer aims a ready one-timer man's feed at AIPassLead.one_timer_tape,
	# the zone his stance sets for the net, so the feed's line already runs
	# through it and the settle anchor is where he stands. Either hand.
	var passer := Vector3(8.0, 0.0, -12.0)
	for lefty: bool in [false, true]:
		var caps := AISkaterCaps.new()
		caps.is_left_handed = lefty
		ot.setup(SELF_ID, 0, _team_map, lefty)
		ot.set_caps(caps)
		for body: Vector3 in [Vector3(-2.5, 0, -24.45), Vector3(-4, 0, -21.65),
				Vector3(5, 0, -18)]:
			var tape: Vector3 = AIPassLead.one_timer_tape(body, caps, ATTACKING_GOAL)
			assert_almost_eq(tape, ot.zone_center(body, ATTACKING_GOAL), Vector3.ONE * 1e-4,
					"lefty %s at %s: the tape is the zone his stance sets" % [lefty, body])
			var dir: Vector3 = (tape - passer).normalized()
			var s := _feed_snap(tape - dir * 6.0, dir * 18.0)
			_add_skater(s, SELF_ID, body)
			var anchor: Vector3 = ot.line_anchor(s, body, ATTACKING_GOAL)
			assert_lt(anchor.distance_to(body), ot.ONE_TIMER_SHUFFLE_ARRIVE_M,
					"lefty %s at %s: nothing to shuffle" % [lefty, body])

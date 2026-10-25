extends GutTest

# SkaterAgentReception's reads against fabricated WorldSnapshots: which fast
# loose puck is a pass to this bot, where its blade parks for one, the wall
# kill, when it gives with the feed, and the stance a receiver skating into the
# feed takes. The steering it drives is held through the
# state machine in test_skater_agent_state_machine.gd.

# peer 1 = self (team 0), peer 2 = teammate (team 0), peers 11/12 = team 1.
const SELF_ID := 1
const TEAMMATE_ID := 2
const OPP_ID := 11
const BLADE_REACH: float = AIBotMechanics.BLADE_REACH_M
var _team_map := {1: 0, 2: 0, 11: 1, 12: 1}

var rec: SkaterAgentReception


func before_each() -> void:
	rec = SkaterAgentReception.new()
	rec.setup(SELF_ID, 0, _team_map, {}, false)


func _add_skater(s: WorldSnapshot, peer_id: int, pos: Vector3) -> void:
	var st := SkaterNetworkState.new()
	st.position = pos
	s.skater_states[peer_id] = st


# ── Reception: pass anticipation ────────────────────────────────────────────────

func _pass_snap(puck_pos: Vector3, puck_vel: Vector3, carrier: int) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = puck_pos
	s.puck_state.velocity = puck_vel
	s.puck_state.carrier_peer_id = carrier
	return s


func test_incoming_pass_fires_for_a_fast_pass_heading_at_us() -> void:
	# Loose puck at (0,0,10) ripping toward -Z at magnet pace; self at the origin is
	# on its line, ahead of it — a pass at us.
	var s := _pass_snap(Vector3(0, 0, 10), Vector3(0, 0, -21), -1)
	assert_true(rec.incoming_pass(s, Vector3.ZERO))


func test_incoming_pass_ignores_slow_carried_or_away_pucks() -> void:
	# Too slow to be a pass.
	var slow: float = SkaterAgentReception.RECEIVE_TRIGGER_PUCK_SPEED_M_S - 1.0
	assert_false(rec.incoming_pass(
			_pass_snap(Vector3(0, 0, 10), Vector3(0, 0, -slow), -1), Vector3.ZERO),
			"a slow loose puck isn't a pass to receive")
	# The softest feed a bot fires still is one.
	assert_true(rec.incoming_pass(_pass_snap(Vector3(0, 0, 10),
			Vector3(0, 0, -GameRules.DEFAULT_WRISTER_POWER_MIN_M_S), -1), Vector3.ZERO),
			"a soft feed is a pass to receive")
	# Carried — not loose.
	assert_false(rec.incoming_pass(
			_pass_snap(Vector3(0, 0, 10), Vector3(0, 0, -21), OPP_ID), Vector3.ZERO),
			"a carried puck is not an incoming pass")
	# Heading AWAY (we're behind its travel).
	assert_false(rec.incoming_pass(
			_pass_snap(Vector3(0, 0, 0), Vector3(0, 0, -21), -1), Vector3(0, 0, 10)),
			"a puck travelling away from us is not incoming")
	# On the line but too far to the side.
	assert_false(rec.incoming_pass(
			_pass_snap(Vector3(0, 0, 10), Vector3(0, 0, -21), -1),
			Vector3(SkaterAgentReception.RECEIVE_TRIGGER_LATERAL_M + 2.0, 0, 0)),
			"a pass whose line runs well wide of us is not ours to receive")


func test_incoming_pass_defers_to_a_closer_teammate() -> void:
	# A fast puck heading down the line, but a teammate is nearer to where it crosses
	# our level — they anticipate it, not us, so a shot/pass past several bots doesn't
	# pull them all out of position.
	var s := _pass_snap(Vector3(0, 0, 10), Vector3(0, 0, -21), -1)
	_add_skater(s, SELF_ID, Vector3(3, 0, 0))          # 3 m off the line at our level
	_add_skater(s, TEAMMATE_ID, Vector3(1, 0, 0))      # closer to the line
	assert_false(rec.incoming_pass(s, Vector3(3, 0, 0)),
			"a teammate nearer the puck's crossing point is the one who receives")
	# Remove the closer teammate → now it's ours.
	s.skater_states.erase(TEAMMATE_ID)
	assert_true(rec.incoming_pass(s, Vector3(3, 0, 0)))


# ── blade_gate ─────────────────────────────────────────────────────────────
# The gate: park the blade at the earliest point on an incoming puck's travel
# line the blade can touch, instead of chasing the puck's position (which the
# Hands-capped cursor can't keep up with — the pass transits reach untouched).

func test_blade_gate_parks_on_the_line_at_the_entry_point() -> void:
	# Puck at origin travelling +X at 20; bot 1 m off the line at x=10. The gate
	# must sit ON the line (z = 0), BEFORE the perpendicular foot (x < 10) — the
	# front edge of reach, so the puck is met at the earliest touchable point —
	# and at the comfortable extension from the body.
	var self_pos := Vector3(10, 0, 1)
	var gate: Vector3 = SkaterAgentReception.blade_gate(
			self_pos, Vector3.ZERO, Vector3.ZERO, Vector3(20, 0, 0), BLADE_REACH)
	assert_almost_eq(gate.z, 0.0, 0.001, "gate sits on the puck's travel line")
	assert_lt(gate.x, 10.0, "gate sits ahead of the perpendicular foot (early contact)")
	assert_almost_eq(self_pos.distance_to(gate), SkaterAgentReception.gate_reach(BLADE_REACH), 0.001,
			"gate sits at the blade's comfortable extension")


func test_blade_gate_head_on_parks_in_front() -> void:
	# Bot standing exactly on the line: the gate is a full comfortable reach IN
	# FRONT of the body, toward the incoming puck — blade out to meet it.
	var gate: Vector3 = SkaterAgentReception.blade_gate(
			Vector3(10, 0, 0), Vector3.ZERO, Vector3.ZERO, Vector3(20, 0, 0), BLADE_REACH)
	assert_almost_eq(gate.z, 0.0, 0.001)
	assert_almost_eq(gate.x, 10.0 - SkaterAgentReception.gate_reach(BLADE_REACH), 0.001,
			"head-on gate is one comfortable reach toward the puck")


func test_blade_gate_reaches_toward_the_line_when_still_closing() -> void:
	# Line runs 3 m to the side — outside reach. Best effort: the perpendicular
	# foot (nearest point of the line), held while the body closes.
	var gate: Vector3 = SkaterAgentReception.blade_gate(
			Vector3(10, 0, 3), Vector3.ZERO, Vector3.ZERO, Vector3(20, 0, 0), BLADE_REACH)
	assert_almost_eq(gate.x, 10.0, 0.001)
	assert_almost_eq(gate.z, 0.0, 0.001,
			"out-of-reach line → aim at its nearest point while closing")


func test_blade_gate_chases_a_puck_that_is_genuinely_leaving() -> void:
	# Puck 5 m up-ice of the bot and running for the far end at pace: nothing on
	# its board-aware path comes back inside the horizon, so there is no gate to
	# park at and the fallback is the puck itself (chase from behind).
	#
	# "Past our level" is NOT the test — that was the straight-ray model's
	# version of this invariant, and inside a closed rink it is simply false: a
	# puck ringing off the wall a metre away is past our level and coming
	# straight back to us, which is a gate, not a chase. What still means "gone"
	# is a path that never closes.
	var puck_pos := Vector3(0, 0, 5)
	var gate: Vector3 = SkaterAgentReception.blade_gate(
			Vector3.ZERO, Vector3.ZERO, puck_pos, Vector3(0, 0, 20), BLADE_REACH)
	assert_eq(gate, puck_pos, "a puck genuinely leaving is chased, not gated")


func test_blade_gate_parks_for_a_puck_ringing_back_off_the_boards() -> void:
	# The other half of the invariant above, and the reason it had to change: a
	# puck heading INTO the near boards a couple of metres away caroms straight
	# back through the bot's reach. Board-aware, that is the most gateable puck
	# on the ice — park the blade and let it come.
	var self_pos := Vector3(GameRules.INNER_HALF_WIDTH - 2.5, 0, 1)
	var puck_pos := Vector3(GameRules.INNER_HALF_WIDTH - 1.0, 0, 0)
	var gate: Vector3 = SkaterAgentReception.blade_gate(
			self_pos, Vector3.ZERO, puck_pos, Vector3(20, 0, 0), BLADE_REACH)
	assert_ne(gate, puck_pos, "the carom back into reach is gated, not chased")
	assert_lt(self_pos.distance_to(gate), SkaterAgentReception.gate_reach(BLADE_REACH) + 0.001,
			"and the gate sits inside the blade's comfortable extension")


func test_blade_gate_clamps_a_corner_rim_line_into_the_rink() -> void:
	# Rim heading into the corner: the puck's straight continuation exits the
	# rink (mid-corner its velocity points at the glass), so the un-clamped
	# perpendicular foot lands PAST the boards — a phantom point the blade
	# would park on while the real puck curls the arc inside. The gate must
	# sit on/inside the rink inner surface.
	var puck_pos := Vector3(12.5, 0, 19.0)          # riding high on the +X wall
	var puck_vel := Vector3(9.9, 0, 9.9)            # angling into the +X/+Z corner
	var self_pos := Vector3(12.6, 0, 23.5)          # downstream, waiting on the rim
	var gate: Vector3 = SkaterAgentReception.blade_gate(self_pos, Vector3.ZERO, puck_pos, puck_vel, BLADE_REACH)
	var inside: Vector2 = GameRules.clamp_to_rink_inner(Vector2(gate.x, gate.z))
	assert_almost_eq(inside.distance_to(Vector2(gate.x, gate.z)), 0.0, 0.01,
			"gate parks on the rink inner surface, not past the glass; got %s"
			% gate)


func test_blade_gate_stationary_puck_is_the_puck() -> void:
	var puck_pos := Vector3(5, 0, 5)
	var gate: Vector3 = SkaterAgentReception.blade_gate(
			Vector3(10, 0, 1), Vector3.ZERO, puck_pos, Vector3.ZERO, BLADE_REACH)
	assert_eq(gate, puck_pos, "no travel line without velocity — aim at the puck")


# ── Wall kill: the blade goes ON the glass, not out on the puck's line ───────

func test_wall_kill_puts_the_blade_on_the_boards_for_a_rim() -> void:
	# A gate riding the boards is played by sealing the blade against the glass
	# — a blade parked on the path line leaves exactly the gap the puck squirts
	# through, which is the "can't retrieve off the boards" failure.
	var on_path := Vector3(GameRules.INNER_HALF_WIDTH - 0.35, 0, 4.0)
	var aim: Vector3 = SkaterAgentReception.wall_kill_aim(on_path)
	assert_almost_eq(aim.x, GameRules.INNER_HALF_WIDTH, 0.01,
			"the blade target seals against the inner wall")
	assert_almost_eq(aim.z, on_path.z, 0.01, "…without sliding along it")


func test_wall_kill_honours_the_rounded_corners() -> void:
	# In the corner the "wall" is an arc, so a straight per-axis distance would
	# push the aim to the wrong place. Radially out from the corner centre is
	# what the clamp gives us.
	var centre := Vector2(GameRules.CORNER_CENTER_X, GameRules.CORNER_CENTER_Z)
	var dir: Vector2 = Vector2(1, 1).normalized()
	var on_path: Vector2 = centre + dir * (GameRules.INNER_CORNER_RADIUS - 0.4)
	var aim: Vector3 = SkaterAgentReception.wall_kill_aim(
			Vector3(on_path.x, 0, on_path.y))
	assert_almost_eq(Vector2(aim.x, aim.z).distance_to(centre),
			GameRules.INNER_CORNER_RADIUS, 0.01,
			"the corner aim lands on the arc, not on a phantom straight wall")


func test_wall_kill_leaves_open_ice_alone() -> void:
	var mid := Vector3(0, 0, 0)
	assert_eq(SkaterAgentReception.wall_kill_aim(mid), mid,
			"nothing to seal against in open ice")


func test_wall_kill_band_catches_a_puck_riding_exactly_on_the_boards() -> void:
	# The band test must not be inferred from "did the aim move" — a rim already
	# flush against the glass has zero gap, moves nowhere, and is the MOST
	# boards-hugging case there is. It still has to read as a wall play.
	var flush := Vector2(GameRules.INNER_HALF_WIDTH, 3.0)
	assert_lte(SkaterAgentReception.board_normal_and_gap(flush).y,
			SkaterAgentReception.WALL_KILL_BAND_M, "a puck flush on the boards is a wall kill")
	assert_gt(SkaterAgentReception.board_normal_and_gap(Vector2(0.0, 0.0)).y,
			SkaterAgentReception.WALL_KILL_BAND_M, "centre ice is not")


func test_board_normal_points_into_the_rink() -> void:
	var board: Vector3 = SkaterAgentReception.board_normal_and_gap(
			Vector2(GameRules.INNER_HALF_WIDTH - 0.4, 3.0))
	assert_almost_eq(board.y, 0.4, 0.01, "gap to the wall")
	assert_almost_eq(board.x, -1.0, 0.01, "normal points back toward centre ice")


# ── Give with the puck ───────────────────────────────────────────────────────

func test_a_receiver_gives_when_his_own_skating_would_bobble_the_feed() -> void:
	assert_true(SkaterAgentReception.gives_with(Vector3(16, 0, 0), Vector3(-3, 0, 0)),
			"16 m/s met at 19: stopping brings it back under the bobble line")
	assert_false(SkaterAgentReception.gives_with(Vector3(16, 0, 0), Vector3.ZERO),
			"standing, it arrives under the line")
	assert_false(SkaterAgentReception.gives_with(Vector3(20, 0, 0), Vector3(0, 0, -6)),
			"a feed past the line on its own bobbles however he skates: in stride")


# ── Reception in stride ──────────────────────────────────────────────────────
# A receiver driving up the ice, the feed coming across his path, its line in
# HIS frame passing a blade off him: his own skating carries him to the meet.

func _driving_receiver_snap(self_vel: Vector3) -> WorldSnapshot:
	var s := _pass_snap(Vector3(-6, 0, -4.45), Vector3(12, 0, 0), -1)
	_add_skater(s, SELF_ID, Vector3.ZERO)
	s.skater_states[SELF_ID].velocity = self_vel
	return s


func test_a_receiver_driving_into_the_feed_stands_where_his_skating_takes_him() -> void:
	var body_offset: float = BLADE_REACH - AIBotMechanics.BLADE_REACH_BUFFER_M \
			- SkaterAgentReception.RECEIVE_BODY_INSET_M
	var self_vel := Vector3(0, 0, -6)
	assert_true(rec.read_pass(_driving_receiver_snap(self_vel), Vector3.ZERO,
			BLADE_REACH, body_offset, 8.0), "the feed is his")
	assert_false(rec.pass_overruns, "taken in stride, no brake")
	var drift: Vector3 = self_vel * AITrajectory.gate_time_s
	var anchor: Vector3 = rec.pass_body_anchor
	assert_lt(anchor.distance_to(drift), 0.25,
			"the stance is where he is skating, not out on the puck's own line")
	# Square across the shaft: a stance off the puck's path in HIS frame.
	var meet: Vector3 = AITrajectory.gate_point
	var rel: Vector3 = (AITrajectory.gate_velocity - self_vel).normalized()
	var off: Vector3 = anchor - meet
	assert_almost_eq((off - rel * off.dot(rel)).length(), body_offset, 0.01,
			"a stance off the relative line through the meet")



func test_a_feed_reaching_where_he_skates_is_his_however_far_off_it_he_is_now() -> void:
	# 5.5 m off the feed's line now, past the trigger, but driving onto it: by
	# the time the puck reaches his level he is a stride off it.
	var s := _pass_snap(Vector3(-8, 0, -5.5), Vector3(12, 0, 0), -1)
	_add_skater(s, SELF_ID, Vector3.ZERO)
	s.skater_states[SELF_ID].velocity = Vector3(0, 0, -6)
	assert_true(rec.incoming_pass(s, Vector3.ZERO), "the feed is coming to him")
	var body_offset: float = BLADE_REACH - AIBotMechanics.BLADE_REACH_BUFFER_M \
			- SkaterAgentReception.RECEIVE_BODY_INSET_M
	assert_true(rec.read_pass(s, Vector3.ZERO, BLADE_REACH, body_offset, 8.0),
			"and he sets for it in stride")
	# Inside the trigger now, but skating away: by then he is well off it.
	var away := _pass_snap(Vector3(-8, 0, -4.5), Vector3(12, 0, 0), -1)
	_add_skater(away, SELF_ID, Vector3.ZERO)
	away.skater_states[SELF_ID].velocity = Vector3(0, 0, 3)
	assert_false(rec.incoming_pass(away, Vector3.ZERO), "skating away from it, it is not his")

func _slot_feed_snap(self_vel: Vector3) -> WorldSnapshot:
	var s := _pass_snap(Vector3(-9, 0, -20), Vector3(15, 0, 0), -1)
	_add_skater(s, SELF_ID, Vector3(1.5, 0, -19))
	s.skater_states[SELF_ID].velocity = self_vel
	return s


func test_the_net_forward_catch_is_only_for_a_body_that_gets_behind_it() -> void:
	var goal := Vector3(0, 0, -GameRules.GOAL_LINE_Z)
	var self_pos := Vector3(1.5, 0, -19)
	assert_true(rec.read_shot(_slot_feed_snap(Vector3.ZERO), self_pos, BLADE_REACH, goal),
			"standing in the slot, he steps back behind the catch")
	assert_false(rec.read_shot(_slot_feed_snap(Vector3(0, 0, -6)), self_pos, BLADE_REACH, goal),
			"driving at the net, he takes it in stride instead of skating back up the ice")

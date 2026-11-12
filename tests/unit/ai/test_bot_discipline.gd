extends GutTest

# SkaterAgentDiscipline and AIFoulRead: a bot lets up on a check that would be
# called a foul, and only on one. Us skating at an opponent, by hand.

const SELF_ID := 1
const MAN_ID := 11
const CLOSING: float = 6.0   # m/s: a full check at league weight
const TTC: float = 0.3

var _team_map := {SELF_ID: 0, MAN_ID: 1}
var _agent: SkaterAgentDiscipline


func before_each() -> void:
	_agent = SkaterAgentDiscipline.new()
	_agent.setup(SELF_ID, 0, _team_map, {})


# Us closing on `man_at` along +X at `closing`, `ttc` seconds from touching him.
func _snap(man_at: Vector3, man_facing: Vector2, carrier: int,
		closing: float = CLOSING, ttc: float = TTC, at_time: float = 10.0) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.fouls_called = true
	s.host_timestamp = at_time
	var man := SkaterNetworkState.new()
	man.position = man_at
	man.facing = man_facing
	var me := SkaterNetworkState.new()
	me.position = man_at - Vector3(AIPinThreatRead.TOUCHING_M + ttc * closing, 0.0, 0.0)
	me.velocity = Vector3(closing, 0.0, 0.0)
	s.skater_states[SELF_ID] = me
	s.skater_states[MAN_ID] = man
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(0.0, 0.0, 20.0)
	s.puck_state.carrier_peer_id = carrier
	return s


func _held_after(snapshot: WorldSnapshot) -> bool:
	var input := InputState.new()
	input.hit_held = true
	_agent.apply(input, snapshot)
	return input.hit_held


func _by_the_boards() -> Vector3:
	var at: Vector2 = GameRules.clamp_to_rink_inner(Vector2(100.0, 0.0), 0.35 + 0.5)
	return Vector3(at.x, 0.0, at.y)


# ── Clean checks stay on ─────────────────────────────────────────────────────

func test_the_carrier_in_open_ice_is_hit() -> void:
	assert_true(_held_after(_snap(Vector3.ZERO, Vector2(-1.0, 0.0), MAN_ID)))


func test_a_carrier_who_sees_it_is_hit_into_the_boards() -> void:
	assert_true(_held_after(_snap(_by_the_boards(), Vector2(-1.0, 0.0), MAN_ID)))


func test_a_slow_lean_on_a_man_without_the_puck_stays_on() -> void:
	assert_true(_held_after(_snap(Vector3.ZERO, Vector2(-1.0, 0.0), -1, 1.0)),
			"the press has no closing speed to foul with")


func test_a_contact_still_a_way_off_is_not_called_off_yet() -> void:
	assert_true(_held_after(_snap(Vector3.ZERO, Vector2(-1.0, 0.0), -1, CLOSING,
			AIFoulRead.CONTACT_HORIZON_S + 0.2)))


func test_nothing_is_called_off_where_no_fouls_are_called() -> void:
	var snapshot: WorldSnapshot = _snap(Vector3.ZERO, Vector2(-1.0, 0.0), -1)
	snapshot.fouls_called = false
	assert_true(_held_after(snapshot))


# ── Fouls are let up on ──────────────────────────────────────────────────────

func test_a_man_without_the_puck_is_not_hit() -> void:
	assert_false(_held_after(_snap(Vector3.ZERO, Vector2(-1.0, 0.0), -1)))


func test_a_carrier_with_his_back_turned_at_the_boards_is_not_hit() -> void:
	assert_false(_held_after(_snap(_by_the_boards(), Vector2(1.0, 0.0), MAN_ID)))


# ── Finishing a check ────────────────────────────────────────────────────────

# The bot watches him carry, then sees the puck leave him at t = 10.0.
func _watch_him_pass() -> void:
	_held_after(_snap(Vector3.ZERO, Vector2(-1.0, 0.0), MAN_ID, CLOSING, 0.5, 9.9))
	_held_after(_snap(Vector3.ZERO, Vector2(-1.0, 0.0), -1, 1.0, 0.5, 10.0))


func test_a_check_that_lands_just_after_the_pass_is_finished() -> void:
	_watch_him_pass()
	assert_true(_held_after(_snap(Vector3.ZERO, Vector2(-1.0, 0.0), -1, CLOSING, 0.2, 10.1)),
			"0.1 s since the pass and 0.2 s to go is inside the grace")


func test_a_check_that_would_land_long_after_the_pass_is_let_up() -> void:
	_watch_him_pass()
	assert_false(_held_after(_snap(Vector3.ZERO, Vector2(-1.0, 0.0), -1, CLOSING, 0.45, 10.3)),
			"0.3 s since the pass and 0.45 s to go is past the grace")

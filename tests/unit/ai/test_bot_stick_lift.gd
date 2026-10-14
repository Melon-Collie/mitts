extends GutTest

# The on-puck pressurer's reach-in: a jab at an open puck, a stick lift when the
# carrier's body blocks the jab. Drives the real state machine's reach-in
# (_poke_jab_aim) and its per-tick button hold (apply_stick_lift_input).

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")
const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

const SELF_ID := 1
const OPP_ID := 11
var _team_map := {1: 0, 11: 1}

var sm: SkaterAgentStateMachine


func before_each() -> void:
	sm = Agent.new()
	sm.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)
	sm._current_strategy = sm._strategy()
	var decision := RoleDecision.new()
	decision.pressures_puck = true
	sm._cached_role_decision = decision


# An opposing carrier at the origin skating -z, puck on his blade ahead, his
# shaft running from the hands down to it.
func _carrier_snap() -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(0.0, 0.0, -1.2)
	s.puck_state.carrier_peer_id = OPP_ID
	var c := SkaterNetworkState.new()
	c.position = Vector3.ZERO
	c.top_hand_world = Vector3(0.0, 1.0, -0.3)
	c.blade_contact_world = Vector3(0.0, 0.03, -1.4)
	s.skater_states[OPP_ID] = c
	return s


func _held_ticks() -> int:
	var held: int = 0
	var pressed: int = 0
	for _i: int in SkaterAgentStickPlay.STICK_LIFT_HOLD_TICKS + 5:
		var input := InputState.new()
		sm.apply_stick_lift_input(input)
		held += 1 if input.stick_check_held else 0
		pressed += 1 if input.stick_check_pressed else 0
	assert_lte(pressed, 1, "one press edge per lift")
	return held


func test_a_shielded_puck_draws_a_lift_from_behind() -> void:
	var s: WorldSnapshot = _carrier_snap()
	# From here the puck is out of the jab's reach but the shaft is not.
	var aim: Vector3 = sm._poke_jab_aim(s, Vector3(0.0, 0.0, 1.2))
	assert_true(aim.is_finite(), "the shaft in reach: the bot reaches in")
	var lift_point: Vector3 = AIStickLiftRead.shaft_lift_point(
			s.skater_states[OPP_ID].top_hand_world, s.skater_states[OPP_ID].blade_contact_world)
	assert_almost_eq(aim.distance_to(lift_point), 0.0, 1e-4, "it aims under the shaft")
	assert_eq(_held_ticks(), SkaterAgentStickPlay.STICK_LIFT_HOLD_TICKS, "and holds the button through the hook")


func test_an_open_puck_draws_the_jab() -> void:
	var s: WorldSnapshot = _carrier_snap()
	var aim: Vector3 = sm._poke_jab_aim(s, Vector3(1.4, 0.0, -1.2))
	assert_almost_eq(aim.distance_to(s.puck_state.position), 0.0, 1e-4, "it jabs the puck")
	assert_eq(_held_ticks(), 0, "no lift")


func test_the_beginner_tier_only_jabs() -> void:
	sm._lifts_sticks = false
	var s: WorldSnapshot = _carrier_snap()
	# Behind and close enough that the puck is inside the jab's reach.
	var aim: Vector3 = sm._poke_jab_aim(s, Vector3(0.0, 0.0, 0.6))
	assert_almost_eq(aim.distance_to(s.puck_state.position), 0.0, 1e-4,
			"a shielded puck still draws only the jab")
	assert_eq(_held_ticks(), 0)


func test_the_lift_hook_ends_inside_the_fast_drop_window() -> void:
	# Held past HOOK_MAX_S the lift would end in the slow recovery instead.
	var hook_s: float = float(SkaterAgentStickPlay.STICK_LIFT_HOLD_TICKS) / 120.0 - StickCheckRules.RISE_S
	assert_gt(hook_s, StickCheckRules.HOOK_MIN_S)
	assert_lt(hook_s, StickCheckRules.HOOK_MAX_S)


# ── The tie ──────────────────────────────────────────────────────────────────
# A man at the origin with his stick out toward +x, and a loose feed running
# down the x = 0.9 line onto his blade.
func _feed_snap() -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(0.9, 0.0, 10.0)
	s.puck_state.velocity = Vector3(0.0, 0.0, -12.0)
	s.puck_state.carrier_peer_id = -1
	var man := SkaterNetworkState.new()
	man.position = Vector3.ZERO
	man.top_hand_world = Vector3(0.3, 1.0, 0.0)
	man.blade_contact_world = Vector3(0.9, 0.03, -0.6)
	s.skater_states[OPP_ID] = man
	var me := SkaterNetworkState.new()
	s.skater_states[SELF_ID] = me
	return s


func _covering_the_man() -> RoleDecision:
	var d := RoleDecision.new()
	d.locked_man_pid = OPP_ID
	return d


func test_a_covering_bot_ties_the_man_a_feed_is_coming_to() -> void:
	var s: WorldSnapshot = _feed_snap()
	# Out of reach of the feed's line, but the man's shaft is in reach.
	var x: float = 0.9 + (sm._blade_reach + sm._stick_lift_reach) * 0.5
	var me := Vector3(x, 0.0, -0.6)
	s.skater_states[SELF_ID].position = me
	var aim: Vector3 = sm._stick_tie_aim(s, me, s.skater_states[SELF_ID], _covering_the_man())
	assert_true(aim.is_finite(), "the bot goes for the man's stick")
	var input := InputState.new()
	sm.apply_stick_lift_input(input)
	assert_true(input.stick_check_held and input.stick_check_pressed, "and holds the button")


func test_a_bot_that_can_reach_the_feed_does_not_tie() -> void:
	var s: WorldSnapshot = _feed_snap()
	var me := Vector3(1.4, 0.0, 3.0)
	s.skater_states[SELF_ID].position = me
	assert_false(sm._stick_tie_aim(s, me, s.skater_states[SELF_ID], _covering_the_man()).is_finite(),
			"its free stick stops the feed itself")


func test_a_bot_ties_nobody_with_the_puck_nowhere_near_the_man() -> void:
	var s: WorldSnapshot = _feed_snap()
	s.puck_state.velocity = Vector3(12.0, 0.0, 0.0)
	var x: float = 0.9 + (sm._blade_reach + sm._stick_lift_reach) * 0.5
	var me := Vector3(x, 0.0, -0.6)
	assert_false(sm._stick_tie_aim(s, me, s.skater_states[SELF_ID], _covering_the_man()).is_finite())


func test_a_puck_already_on_his_blade_starts_no_tie() -> void:
	# Loose for a tick under his own stickhandle or a contested pickup, the puck
	# sitting on his blade still reads as a path reaching him. It is his puck,
	# not a feed: tying him then is a stick check on the handler.
	var s: WorldSnapshot = _feed_snap()
	s.puck_state.position = s.skater_states[OPP_ID].blade_contact_world
	s.puck_state.velocity = Vector3(0.0, 0.0, -6.0)
	var x: float = 0.9 + (sm._blade_reach + sm._stick_lift_reach) * 0.5
	var me := Vector3(x, 0.0, -0.6)
	s.skater_states[SELF_ID].position = me
	assert_false(sm._stick_tie_aim(s, me, s.skater_states[SELF_ID], _covering_the_man()).is_finite(),
			"a puck already at his blade is not a feed to deny")


func test_a_tie_already_made_holds_through_the_arrival() -> void:
	# The other half: once tied, the feed reaching his blade is the reception
	# the tie exists to deny, so the hold must not let go as it lands.
	var s: WorldSnapshot = _feed_snap()
	s.puck_state.position = Vector3(0.9, 0.0, 0.0)
	var x: float = 0.9 + (sm._blade_reach + sm._stick_lift_reach) * 0.5
	var me := Vector3(x, 0.0, -0.6)
	s.skater_states[SELF_ID].position = me
	s.skater_states[SELF_ID].stick_tied = true
	s.skater_states[OPP_ID].stick_tied = true
	assert_true(sm._stick_tie_aim(s, me, s.skater_states[SELF_ID], _covering_the_man()).is_finite(),
			"the tie holds while the feed arrives")


func test_a_tied_bot_the_feed_is_coming_to_pulls_its_stick_away() -> void:
	var s: WorldSnapshot = _feed_snap()
	var me: SkaterNetworkState = s.skater_states[SELF_ID]
	me.position = Vector3(3.0, 0.0, 0.0)
	me.top_hand_world = Vector3(3.0, 1.0, -0.3)
	me.blade_contact_world = Vector3(3.0, 0.03, -1.2)
	me.stick_tied = true
	s.puck_state.position = Vector3(3.0, 0.0, 10.0)
	var tier: SkaterNetworkState = s.skater_states[OPP_ID]
	tier.stick_tied = true
	tier.blade_contact_world = Vector3(2.6, 0.03, -1.2)
	var aim: Vector3 = sm._tie_yank_aim(s, me.position, me)
	assert_true(aim.is_finite())
	assert_gt(aim.x, me.blade_contact_world.x, "away from the stick holding it")
	sm._ties_sticks = false
	assert_false(sm._tie_yank_aim(s, me.position, me).is_finite(), "the beginner tier just waits")


func test_a_tied_bot_the_feed_is_not_for_holds_on() -> void:
	var s: WorldSnapshot = _feed_snap()
	var me: SkaterNetworkState = s.skater_states[SELF_ID]
	me.position = Vector3(3.0, 0.0, 0.0)
	me.top_hand_world = Vector3(3.0, 1.0, -0.3)
	me.blade_contact_world = Vector3(3.0, 0.03, -1.2)
	me.stick_tied = true
	s.puck_state.position = Vector3(-6.0, 0.0, 10.0)
	s.skater_states[OPP_ID].stick_tied = true
	assert_false(sm._tie_yank_aim(s, me.position, me).is_finite(), "no pull")
	sm._state = SkaterAgentStateMachine.State.OFF_PUCK
	var input := InputState.new()
	sm.apply_stick_lift_input(input)
	assert_true(input.stick_check_held, "it holds the defender's stick out of the play")
	assert_false(input.stick_check_pressed, "the tie is already made: no new lift")


func test_a_covering_bot_keeps_holding_the_tie_it_made() -> void:
	var s: WorldSnapshot = _feed_snap()
	var x: float = 0.9 + (sm._blade_reach + sm._stick_lift_reach) * 0.5
	var me := Vector3(x, 0.0, -0.6)
	s.skater_states[SELF_ID].position = me
	s.skater_states[SELF_ID].stick_tied = true
	s.skater_states[OPP_ID].stick_tied = true
	assert_true(sm._stick_tie_aim(s, me, s.skater_states[SELF_ID], _covering_the_man()).is_finite(),
			"his man tied with him is the tie this read keeps alive")
	var input := InputState.new()
	sm.apply_stick_lift_input(input)
	assert_true(input.stick_check_held)
	assert_false(input.stick_check_pressed)


func test_a_bot_holding_a_tie_follows_the_mans_stick_late() -> void:
	# A first-order follow whose time constant is the lag budget: it closes
	# 1 - 1/e of a step in the man's stick over TIE_LAG_BUDGET_S, never at once
	# and never past it.
	var play := SkaterAgentStickPlay.new()
	var man: SkaterNetworkState = _feed_snap().skater_states[OPP_ID]
	var first: Vector3 = play.step_tie_follow(man)
	man.top_hand_world += Vector3(1.0, 0.0, 0.0)
	man.blade_contact_world += Vector3(1.0, 0.0, 0.0)
	var ticks: int = roundi(StickCheckRules.TIE_LAG_BUDGET_S * _PhysicsConstants.PHYSICS_TICK)
	var moved: float = 0.0
	for i: int in ticks:
		var now: float = play.step_tie_follow(man).x - first.x
		assert_true(now > moved and now < 1.0,
				"tick %d: the follow closes on the stick without reaching it" % i)
		moved = now
	assert_almost_eq(moved, 1.0 - exp(-1.0), 0.01,
			"one lag budget closes 1 - 1/e of the step: a bot reads a pull as late as a human holder")

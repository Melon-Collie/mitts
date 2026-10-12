extends GutTest

# The on-puck pressurer's reach-in: a jab at an open puck, a stick lift when the
# carrier's body blocks the jab. Drives the real state machine's reach-in
# (_poke_jab_aim) and its per-tick button hold (apply_stick_lift_input).

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")

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
	for _i: int in Agent.STICK_LIFT_HOLD_TICKS + 5:
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
	assert_eq(_held_ticks(), Agent.STICK_LIFT_HOLD_TICKS, "and holds the button through the hook")


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
	var hook_s: float = float(Agent.STICK_LIFT_HOLD_TICKS) / 120.0 - StickCheckRules.RISE_S
	assert_gt(hook_s, StickCheckRules.HOOK_MIN_S)
	assert_lt(hook_s, StickCheckRules.HOOK_MAX_S)

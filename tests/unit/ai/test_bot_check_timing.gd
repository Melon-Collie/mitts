extends GutTest

# SkaterAgentStandUp's timing of a hunted check: the button stays down through
# the hunt, and comes up just ahead of the throw only when the drive has
# re-armed, so the press that follows is a fresh one.

const SELF_ID := 1
const MAN_ID := 11
var _team_map := {SELF_ID: 0, MAN_ID: 1}
var _agent: SkaterAgentStandUp


func before_each() -> void:
	_agent = SkaterAgentStandUp.new()
	_agent.setup(SELF_ID, 0, _team_map, {})


# Us closing on the carrier at `closing` m/s, `ttc` seconds from touching him.
func _snap(ttc: float, closing: float, phase: int, elapsed: float) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	var man := SkaterNetworkState.new()
	man.position = Vector3(0.0, 0.0, -10.0)
	var me := SkaterNetworkState.new()
	me.position = man.position + Vector3(0.0, 0.0, AIPinThreatRead.TOUCHING_M + ttc * closing)
	me.velocity = Vector3(0.0, 0.0, -closing)
	me.check_drive_phase = phase
	me.check_drive_elapsed = elapsed
	s.skater_states[SELF_ID] = me
	s.skater_states[MAN_ID] = man
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = man.position
	s.puck_state.carrier_peer_id = MAN_ID
	return s


func _held_after(ttc: float, phase: int, elapsed: float) -> bool:
	var input := InputState.new()
	input.hit_held = true
	_agent.apply(input, _snap(ttc, 2.0, phase, elapsed), 1.0)
	return input.hit_held


func test_the_button_stays_down_through_the_hunt() -> void:
	var rearmed: float = CheckDriveRules.REARM_S
	assert_true(_held_after(1.0, CheckDriveRules.Phase.SPENT, rearmed), "far from the contact")
	assert_true(_held_after(AIStandUpRead.THROW_S + 2.0 * SkaterAgentStandUp.REPRESS_S,
			CheckDriveRules.Phase.SPENT, rearmed), "still ahead of the throw")
	assert_true(_held_after(1.0, CheckDriveRules.Phase.DRIVE, 0.1))


func test_it_comes_up_just_ahead_of_the_throw_when_the_drive_has_rearmed() -> void:
	var ttc: float = AIStandUpRead.THROW_S + 0.5 * SkaterAgentStandUp.REPRESS_S
	assert_false(_held_after(ttc, CheckDriveRules.Phase.SPENT, CheckDriveRules.REARM_S))
	assert_true(_held_after(ttc, CheckDriveRules.Phase.SPENT, 0.5 * CheckDriveRules.REARM_S),
			"not re-armed: letting go would only drop the shoulder")
	assert_true(_held_after(ttc, CheckDriveRules.Phase.DRIVE, 0.1), "the drive is still running")
	assert_true(_held_after(ttc, CheckDriveRules.Phase.IDLE, 0.0), "this press is the fresh one")


func test_it_is_down_again_for_the_throw() -> void:
	assert_true(_held_after(0.5 * AIStandUpRead.THROW_S, CheckDriveRules.Phase.SPENT,
			CheckDriveRules.REARM_S))


func test_the_window_fits_inside_the_drive() -> void:
	assert_lt(AIStandUpRead.THROW_S + SkaterAgentStandUp.REPRESS_S, CheckDriveRules.DRIVE_S,
			"a press at the window's start still has its drive running at the contact")

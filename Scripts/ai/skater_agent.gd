class_name SkaterAgent
extends RefCounted

# Per-bot decision loop. Owned by AIController. Owns the InputState scratch
# buffer and forwards to a SkaterAgentStateMachine that holds the transition
# logic and per-state behavior.

var _scratch_input: InputState = InputState.new()
var _sm: SkaterAgentStateMachine = SkaterAgentStateMachine.new()


func setup(peer_id: int, team_id: int, brain: TeamBrain, team_id_by_peer: Dictionary,
		is_left_handed: bool, caps_by_peer: Dictionary = {}) -> void:
	_sm.setup(peer_id, team_id, brain, team_id_by_peer, is_left_handed, caps_by_peer)


# Called by AIController.setup_agent right after setup(), before the first
# tick. carrier_reaction_delay_s is consumed by GameManager (the debounced
# carrier) and by the state machine as its chase reaction delay. Null
# leaves the perfect-bot defaults in place.
func apply_profile(profile: BotSkillProfile) -> void:
	if profile == null:
		return
	_sm.apply_profile(profile)


# This bot's attribute-scaled self-capabilities. Called by
# AIController.apply_attributes on spawn and on free-play picker changes.
func apply_capabilities(caps: AISkaterCaps) -> void:
	_sm.apply_capabilities(caps)


# Main thread only, after dispatch: the worker never writes team state.
func push_one_timer_ready() -> void:
	_sm.push_one_timer_ready()


# Returns the InputState for this physics tick. Caller must not retain a
# reference past the next tick — same scratch buffer is reused.
#
# Never smooth the SM's cursor here (Scripts/ai/CLAUDE.md → "The blade cursor
# leaves the agent untouched").
func tick(snapshot: WorldSnapshot, delta: float, host_timestamp: float) -> InputState:
	zero_input(_scratch_input, delta, host_timestamp)
	_sm.dispatch(_scratch_input, snapshot)
	_sm.apply_stick_lift_input(_scratch_input)
	_sm.apply_board_play(_scratch_input, snapshot)
	_sm.apply_shot_block(_scratch_input, snapshot)
	_sm.apply_cross_check(_scratch_input, snapshot)
	_sm.apply_offside_guard(_scratch_input, snapshot)
	return _scratch_input


func get_state() -> SkaterAgentStateMachine.State:
	return _sm.get_state()


# ── Debug accessors ───────────────────────────────────────────────────────────
# Read by AIController to populate the floating per-bot debug label.


func debug_role() -> String:
	return _sm.debug_role()


func debug_last_decision() -> String:
	return _sm.debug_last_decision


func debug_shoot_score() -> float:
	return _sm.debug_shoot_score


func debug_shoot_label() -> String:
	return "SHOOT"


func debug_pass_score() -> float:
	return _sm.debug_pass_score


func debug_pass_slot() -> String:
	return _sm.debug_pass_slot()


func debug_carry_score() -> float:
	return _sm.debug_carry_score


func debug_carry_dir(snapshot: WorldSnapshot) -> String:
	if snapshot == null or not snapshot.skater_states.has(_sm._peer_id):
		return "—"
	return _sm.debug_carry_dir(snapshot.skater_states[_sm._peer_id].position)


func debug_winner() -> String:
	return _sm.debug_winner()


func debug_intent() -> String:
	return _sm.debug_intent()


# Resets every field each tick: the scratch buffer is reused, so a value one
# state set last tick would otherwise leak into a state that doesn't touch it.
static func zero_input(input: InputState, delta: float, host_timestamp: float) -> void:
	input.delta = delta
	input.host_timestamp = host_timestamp
	input.move_vector = Vector2.ZERO
	input.mouse_world_pos = Vector3.ZERO
	input.mouse_screen_pos = Vector2.ZERO
	input.shoot_pressed = false
	input.shoot_held = false
	input.slap_pressed = false
	input.slap_held = false
	input.brake = false
	# The SM re-decides stance each full dispatch and restores its cache on
	# throttled ticks.
	input.stance_held = false
	# The loft level is absolute per input frame (no sticky controller state).
	input.elevation_level = 0
	input.block_held = false
	input.stick_lift_held = false
	# A leaked true would keep a bot bracing, off its edges, after the check.
	input.hit_held = false
	# Fire-once edge: nothing else clears it, so a latched true would fire a
	# quick pass on every subsequent carry tick.
	input.quick_pass_pressed = false
	input.stick_check_held = false
	input.stick_check_pressed = false
	input.stick_lift_pressed = false
	# The committed charge power and its flag are re-set by every press tick
	# that reads them; between presses they hold their defaults.
	input.bot_wrister_power_t = 1.0
	input.commit_wrister_power = false
	# ZERO = not committed; a latched aim would be read as a stale bot aim.
	input.bot_wrister_aim_dir = Vector3.ZERO
	input.bot_slapper_aim_dir = Vector3.ZERO
	input.bot_shuffle = false

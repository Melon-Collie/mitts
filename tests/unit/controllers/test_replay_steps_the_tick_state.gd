extends GutTest

# Skater steps some state itself each tick that the controller's next tick
# reads: the stick-check timers and the blade-lift and check-commit eases (the
# check lead moves the loaded blade, and the twist follows it). The reconcile
# replay used to read them frozen at their live, end-of-window values, so a
# replay through a check commit turned the shoulders where the host's never
# went and the next ack reconciled again. It now adopts them as they stood at
# the ack and steps them (Skater.step_tick_state).
#
# Forced with a vertical offset: the reconcile runs, and nothing in the plane —
# where the cursor and the twist live — is corrected.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const T0: float = 10.0
const COMMIT_AT: int = 20
const ACK_AT: int = 22
const TICKS: int = 45


class StubGameState extends Node:
	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


var _c: LocalController = null


func before_each() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_facing(Vector2(0.0, -1.0))
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_c = load("res://Scenes/LocalController.tscn").instantiate() as LocalController
	add_child_autofree(_c)
	_c.setup(skater, puck, state)
	_c.set_process(false)
	_c.set_physics_process(false)


# One live tick as the game runs it: the controller, then the skater's own
# physics step, which records the prediction.
func _tick(i: int) -> void:
	var input := InputState.new()
	input.delta = DT
	input.host_timestamp = T0 + float(i) * DT
	input.move_vector = Vector2(0.7, -0.7)
	input.hit_held = i >= COMMIT_AT
	input.mouse_world_pos = _c.skater.global_position + Vector3(1.5, 0.0, -3.0)
	_c._current_input = input
	_c._snapshot_pending = true
	_c._process_input(input, DT)
	_c.skater._physics_process(DT)
	_c._input_history.append(input)


func test_a_replay_through_a_check_commit_twists_as_the_live_ticks_did() -> void:
	var server := SkaterNetworkState.new()
	for i: int in TICKS:
		_tick(i)
		if i == ACK_AT:
			_c.fill_network_state(server)
	assert_true(_c.skater.hit_committed, "the control: committed to the check")
	assert_gt(absf(_c.skater.get_check_lead()), 0.01, "the control: the lead is in")
	var live: Dictionary = {}
	for p: PredictedState in _c._prediction_history:
		live[p.host_timestamp] = p.upper_body_rotation_y
	server.last_processed_host_timestamp = T0 + float(ACK_AT) * DT
	server.position += Vector3(0.0, 0.06, 0.0)
	_c.reconcile(server)
	var replayed: int = 0
	var worst: float = 0.0
	for p: PredictedState in _c._prediction_history:
		if p.was_replay_rerecorded and live.has(p.host_timestamp):
			replayed += 1
			worst = maxf(worst, absf(angle_difference(p.upper_body_rotation_y,
					live[p.host_timestamp] as float)))
	assert_gt(replayed, 10, "the control: the replay re-recorded the window")
	assert_lt(worst, 0.01, "replayed ticks twist as the live ones did (worst %.4f rad)" % worst)


# Out of a follow-through the blade smoother is seeded from the finish, and the
# next tick's blade reads that seed. The replay skipped it, so its blade snapped
# to the cursor where the live one eased out of the finish, and stayed off it.
# SkaterPoseBridge's ease is live-only by design (a replay would play it
# twice), so the two differ through that ease and must agree once it is over.
func test_a_replay_leaves_a_follow_through_as_the_live_tick_did() -> void:
	var live: SkaterController = _pair_member(false)
	var replay: SkaterController = _pair_member(true)
	var skating_since: int = -1
	var worst_after_ease: float = 0.0
	var ease_ticks: int = ceili(SkaterPoseBridge.SPAN_S / DT) + 2
	for i: int in 240:
		var input := InputState.new()
		input.delta = DT
		input.slap_pressed = i == 0
		input.slap_held = i < 40  # a puckless wind-up, swung at nothing
		var a: float = float(i) * 0.05
		input.mouse_world_pos = live.skater.global_position + Vector3(2.5 * cos(a), 0.0, -2.5)
		var was: SkaterStateMachine.State = live._sm.get_state()
		live._process_input(input, DT)
		replay._process_input(input, DT)
		if was == SkaterStateMachine.State.FOLLOW_THROUGH \
				and live._sm.get_state() == SkaterStateMachine.State.SKATING_WITHOUT_PUCK:
			skating_since = i
		if skating_since >= 0 and i >= skating_since + ease_ticks:
			worst_after_ease = maxf(worst_after_ease, live.skater.get_blade_position().distance_to(
					replay.skater.get_blade_position()))
	assert_gt(skating_since, 0, "the control: the swing finished and skated on")
	assert_lt(skating_since, 240 - ease_ticks - 30, "the control: with ticks left to compare")
	assert_lt(worst_after_ease, 0.001,
			"past the bridge's ease the replayed blade is the live one (worst %.3f m)" % worst_after_ease)


func _pair_member(replaying: bool) -> SkaterController:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_facing(Vector2(0.0, -1.0))
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, state)
	c.set_process(false)
	c.set_physics_process(false)
	c.is_replaying = replaying
	return c


# The replay needs every unacked input: rtt, the 28 ms stamp margin, up to a
# broadcast interval's wait for the ack, and up to the host's 67 ms queue slip.
func test_the_input_history_covers_the_unacked_window() -> void:
	for rtt_ms: float in [0.0, 20.0, 50.0, 80.0, 100.0, 150.0, 200.0]:
		var window_s: float = rtt_ms / 1000.0 + NetworkManager.INPUT_LEAD_SEC \
				+ 1.0 / float(Constants.STATE_RATE) + 0.067
		assert_gt(float(LocalController.input_history_cap(rtt_ms)) * DT, window_s,
				"the history must outlast the unacked window at %d ms" % int(rtt_ms))

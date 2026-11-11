extends GutTest

# The host broadcasts the upper-body FRAME's yaw — the tracked twist plus the
# follow spring's whip — so the client's reconcile history has to hold the same
# quantity. A client and host running identical code on one input stream must
# then never reconcile, however hard the twist whips; a genuine twist desync
# must still reconcile, and settle.

class StubGameState extends Node:
	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false

	func allows_blade_aim_during_lock() -> bool:
		return false


const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# The ack the client receives trails its live tick by about an RTT plus the
# input lead; the host broadcasts every other tick.
const LAG_TICKS: int = 6
const BROADCAST_EVERY: int = 2
const TICKS: int = 360
const KICK_TICK: int = 120
# A 2 Hz side-to-side dangle: well past the twist rate (~1.5 rad/s) at which
# the whip alone exceeds the reconcile threshold.
const DANGLE_HZ: float = 2.0
const DANGLE_AMP_M: float = 0.8


var _host: LocalController = null
var _client: LocalController = null


func before_each() -> void:
	var state := StubGameState.new()
	add_child_autofree(state)
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(25.0, 0.0, 25.0)
	_host = _make_controller(puck, state)
	_client = _make_controller(puck, state)


func _make_controller(puck: Puck, state: Node) -> LocalController:
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var ctrl: LocalController = load("res://Scenes/LocalController.tscn").instantiate() as LocalController
	add_child_autofree(ctrl)
	ctrl.setup(skater, puck, state)
	ctrl.set_process(false)
	ctrl.set_physics_process(false)
	ctrl.teleport_to(Vector3(0.0, 0.0, 12.0), Vector2(0.0, -1.0))
	return ctrl


# A function of time only, so both peers see the identical cursor.
func _input_at(tick: int) -> InputState:
	var t: float = float(tick) * DT
	var i := InputState.new()
	i.host_timestamp = 1.0 + t
	i.delta = DT
	i.move_vector = Vector2(0.0, -0.6)
	i.mouse_world_pos = Vector3(DANGLE_AMP_M * sin(TAU * DANGLE_HZ * t), 0.0, 12.0 - 3.0 * t - 1.4)
	return i


# One live tick the way LocalController._physics_process and the skater's own
# tick run it; `record` keeps the client's input and prediction histories.
func _tick(ctrl: LocalController, input: InputState, record: bool) -> void:
	ctrl.skater.capture_prev_blade_contact()
	if record:
		ctrl._current_input = input
		ctrl._input_history.append(input)
	ctrl._process_input(input, DT)
	ctrl._snapshot_pending = record
	ctrl.skater._physics_process(DT)


# Returns the tick of every reconcile the client fired.
func _run(twist_kick: float) -> Array[int]:
	var host_states: Array[SkaterNetworkState] = []
	var fired: Array[int] = []
	for tick: int in TICKS:
		if tick == KICK_TICK:
			_host._pose.upper_body_angle += twist_kick
		_tick(_host, _input_at(tick), false)
		_tick(_client, _input_at(tick), true)
		_host.last_processed_host_timestamp = 1.0 + float(tick) * DT
		var s := SkaterNetworkState.new()
		_host.fill_network_state(s)
		s.shot_state = _host._sm.get_state() as int
		host_states.append(s)
		if tick < LAG_TICKS or tick % BROADCAST_EVERY != 0:
			continue
		_client.last_reconcile_error = -1.0
		_client.reconcile(host_states[tick - LAG_TICKS])
		if _client.last_reconcile_error >= 0.0:
			fired.append(tick)
	return fired


func test_the_whip_is_on_the_wire() -> void:
	# The premise: the host's broadcast yaw is not the tracked angle mid-dangle.
	var widest: float = 0.0
	for tick: int in TICKS:
		_tick(_host, _input_at(tick), false)
		widest = maxf(widest, absf(angle_difference(
				_host._pose.upper_body_angle, _host.skater.get_upper_body_rotation())))
	assert_gt(widest, _client.reconcile_upper_body_rotation_threshold,
			"the whip alone exceeds the threshold (%.3f rad)" % widest)


# The broadcast rate is the tangent every receiver's hermite and extrapolation
# lays on the broadcast yaw, so it must be that yaw's own rate, whip included.
func test_the_broadcast_rate_is_the_broadcast_yaws_rate() -> void:
	var prev := SkaterNetworkState.new()
	var cur := SkaterNetworkState.new()
	var worst: float = 0.0
	for tick: int in TICKS:
		_tick(_host, _input_at(tick), false)
		_host.fill_network_state(cur)
		if tick > 0:
			var yaw_rate: float = angle_difference(
					prev.upper_body_rotation_y, cur.upper_body_rotation_y) / DT
			worst = maxf(worst, absf(cur.upper_body_angular_velocity - yaw_rate))
		var swap: SkaterNetworkState = prev
		prev = cur
		cur = swap
	assert_lt(worst, 1e-3, "broadcast rate off the yaw's own by up to %.3f rad/s" % worst)


func test_a_client_in_lockstep_with_its_host_never_reconciles() -> void:
	var fired: Array[int] = _run(0.0)
	assert_eq(fired.size(), 0, "reconciles at ticks %s" % [fired])


func test_a_twist_desync_reconciles_and_settles() -> void:
	var fired: Array[int] = _run(0.4)
	assert_gt(fired.size(), 0, "the desync was caught")
	var settled_by: int = KICK_TICK + LAG_TICKS + 60
	assert_lt(fired.back(), settled_by, "still reconciling half a second on (ticks %s)" % [fired])

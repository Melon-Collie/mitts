extends GutTest

# The reconcile replay runs an unacked window after the inputs it re-runs, and
# by then the puck and the goalie have moved on. What the live tick read of
# them is recorded on its PredictedState and played back at that input
# (LocalController._replay_view), so the replay re-runs each input against the
# world it was first run against: the shot block's facing snap toward the puck,
# and the body held off the goalie's gear.
#
# Forced with a vertical offset, as test_replay_steps_the_tick_state.gd does: the
# reconcile runs, and nothing in the plane is corrected.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const T0: float = 10.0
const ACK_AT: int = 8
const TICKS: int = 70


class StubGameState extends Node:
	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


var _c: LocalController = null
var _goalie_body := PackedFloat32Array()


func before_each() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(2.0, 0.0, -2.0)
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_facing(Vector2(0.0, -1.0))
	skater.set_process(false)
	skater.set_physics_process(false)
	skater.set_goalie_boxes_provider(func() -> PackedFloat32Array: return _goalie_body)
	var state := StubGameState.new()
	add_child_autofree(state)
	_c = load("res://Scenes/LocalController.tscn").instantiate() as LocalController
	add_child_autofree(_c)
	_c.setup(skater, puck, state)
	_c.set_process(false)
	_c.set_physics_process(false)


# A standing pad, its face toward the skater (−z of it), at `z`.
func _pad_at(z: float) -> PackedFloat32Array:
	var b := Basis.IDENTITY
	return PackedFloat32Array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
			0.0, 0.4, z, 0.5, 0.4, 0.1])


# One live tick as the game runs it: the controller, then the skater's own
# physics step, which records the prediction.
func _tick(i: int, move: Vector2, block_from: int) -> void:
	var input := InputState.new()
	input.delta = DT
	input.host_timestamp = T0 + float(i) * DT
	input.move_vector = move
	input.block_held = block_from >= 0 and i >= block_from
	input.mouse_world_pos = _c.skater.global_position + Vector3(0.0, 0.0, -3.0)
	_c._current_input = input
	_c._snapshot_pending = true
	_c._process_input(input, DT)
	_c.skater._physics_process(DT)
	_c._input_history.append(input)


# Runs the live window, lets `then` move the world on, reconciles at the ack and
# returns the worst gap between a replayed entry and its live one, read by `read`.
func _worst_replayed_gap(move: Vector2, block_from: int, then: Callable, read: Callable) -> float:
	var server := SkaterNetworkState.new()
	for i: int in TICKS:
		_tick(i, move, block_from)
		if i == ACK_AT:
			_c.fill_network_state(server)
	var live: Dictionary = {}
	for p: PredictedState in _c._prediction_history:
		live[p.host_timestamp] = read.call(p)
	then.call()
	server.last_processed_host_timestamp = T0 + float(ACK_AT) * DT
	server.position += Vector3(0.0, 0.06, 0.0)
	_c.reconcile(server)
	var replayed: int = 0
	var worst: float = 0.0
	for p: PredictedState in _c._prediction_history:
		if p.was_replay_rerecorded and live.has(p.host_timestamp):
			replayed += 1
			worst = maxf(worst, (read.call(p) as Vector2).distance_to(live[p.host_timestamp] as Vector2))
	assert_gt(replayed, TICKS - ACK_AT - 5, "the control: the replay re-recorded the window")
	return worst


func test_a_replayed_block_faces_the_puck_where_it_was() -> void:
	var block_from: int = 30
	var worst: float = _worst_replayed_gap(Vector2.ZERO, block_from,
			func() -> void:
				assert_eq(_c._sm.get_state(), SkaterStateMachine.State.SHOT_BLOCKING,
						"the control: blocking")
				assert_lt(_c._pose.facing.distance_to(Vector2(1.0, -1.0).normalized()), 0.01,
						"the control: the live block snapped toward the puck where it was")
				_c.puck.global_position = Vector3(-2.0, 0.0, 2.0),
			func(p: PredictedState) -> Vector2: return p.facing)
	assert_lt(worst, 0.001, "replayed facings are the live ones (worst %.4f)" % worst)


func test_a_replayed_skater_stops_on_the_goalie_where_he_was() -> void:
	_goalie_body = _pad_at(-1.4)
	var worst: float = _worst_replayed_gap(Vector2(0.0, -1.0), -1,
			func() -> void:
				var face: float = -1.4 + 0.1 + _c.skater.collision_radius()
				assert_almost_eq(_c.skater.global_position.z, face, 0.02,
						"the control: the live skater stopped on the pad")
				_goalie_body = _pad_at(-6.0),
			func(p: PredictedState) -> Vector2: return Vector2(p.position.x, p.position.z))
	assert_lt(worst, 0.001, "replayed positions are the live ones (worst %.4f m)" % worst)

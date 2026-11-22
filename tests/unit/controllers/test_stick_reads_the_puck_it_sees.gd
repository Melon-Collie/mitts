extends GutTest

# The empty stick reaches when the puck is coming within reach (the reach
# purpose, SkaterIKCoordinator._reach_purpose and the blade pass's port of it),
# judged from the puck's flight. It reads that flight where the controller reads
# the puck (SkaterController.read_puck_view): on a client the drawn flight —
# its puck node's linear_velocity is whatever it last fired — and in a reconcile
# replay the flight the live tick read.

const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_AT := Vector3(4.0, 0.0, 0.0)
const STALE := Vector3(0.0, 0.0, 30.0)   # the client's own last shot
const FEED := Vector3(-12.0, 0.0, 0.0)   # the pass actually coming at him
const CURSOR_FAR := Vector3(0.0, 0.0, -40.0)


class StubGameState extends Node:
	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


var _c: LocalController = null
var _pc: PuckController = null
var _saved_pc: PuckController = null


func before_each() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = PUCK_AT
	puck.linear_velocity = STALE
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_c = load("res://Scenes/LocalController.tscn").instantiate() as LocalController
	add_child_autofree(_c)
	_c.setup(skater, puck, state)
	_c.set_process(false)
	_c.set_physics_process(false)
	_pc = PuckController.new()
	_pc.rendered_loose_velocity = FEED
	_saved_pc = GameManager.puck_controller
	GameManager.puck_controller = _pc


func after_each() -> void:
	GameManager.puck_controller = _saved_pc
	_pc.free()


# The reach purpose for a puck at `at` with flight `vel`, the cursor far off.
func _purpose_for(at: Vector3, vel: Vector3) -> float:
	var body := Vector2(_c.skater.global_position.x, _c.skater.global_position.z)
	return ReachPurposeRules.purpose(body, _c._ik.full_blade_reach(), Vector2(at.x, at.z),
			Vector2(vel.x, vel.z), _c.reach_purpose_lookahead_s, _c.reach_purpose_near_m,
			_c.reach_purpose_far_m)


func _read() -> float:
	return _c._ik._reach_purpose(_c.skater.global_position, CURSOR_FAR)


func test_a_client_reaches_for_the_flight_it_draws() -> void:
	_c._is_host = false
	assert_gt(absf(_purpose_for(PUCK_AT, FEED) - _purpose_for(PUCK_AT, STALE)), 0.5,
			"the control: the feed and the stale shot read differently")
	assert_almost_eq(_read(), _purpose_for(PUCK_AT, FEED), 1e-6)


func test_the_host_reaches_for_its_live_puck() -> void:
	_c._is_host = true
	assert_almost_eq(_read(), _purpose_for(PUCK_AT, STALE), 1e-6)


func test_a_replay_reaches_for_the_puck_its_live_tick_read() -> void:
	_c._is_host = false
	var then := PredictedState.new()
	then.puck_position = Vector3(-4.0, 0.0, 0.0)
	then.puck_velocity = Vector3(12.0, 0.0, 0.0)
	_c._replay_view = then
	_c.is_replaying = true
	var replayed: float = _read()
	_c.is_replaying = false
	_c._replay_view = null
	assert_almost_eq(replayed, _purpose_for(then.puck_position, then.puck_velocity), 1e-6)
	assert_almost_eq(_read(), _purpose_for(PUCK_AT, FEED), 1e-6, "and live again after it")

extends GutTest

# Skater contact against the boards (Skater._resolve_player_collisions with
# BoardPinRules): the same committed check lands harder on a victim with the
# boards behind him. (The pin's onset is BoardPinTracker's — see
# test_board_pin_tracker.gd.) Real Skater scenes, resolved by hand from the
# checker's side.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")

var _checker: Skater = null
var _victim: Skater = null
var _received: Array[Vector3] = []


func before_each() -> void:
	_checker = _spawn()
	_victim = _spawn()
	var both: Array = [_checker, _victim]
	_checker.set_skater_collision_provider(func() -> Array: return both)
	_victim.set_skater_collision_provider(func() -> Array: return both)
	_checker.is_host_machine = true
	_victim.is_host_machine = true
	_checker.hit_committed = true
	_checker.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_received.clear()
	_victim.body_check_received.connect(func(i: Vector3) -> void: _received.append(i))


func _spawn() -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.set_physics_process(false)
	s.set_process(false)
	return s


# The checker overlapping the victim from -x, closing at `speed`; the victim's
# centre at `victim_x`.
func _check_at(victim_x: float, speed: float) -> void:
	var y: float = GameRules.FACEOFF_SPAWN_HEIGHT
	_victim.global_position = Vector3(victim_x, y, 0.0)
	_victim.velocity = Vector3.ZERO
	_checker.global_position = Vector3(victim_x - 0.6, y, 0.0)
	_checker.velocity = Vector3(speed, 0.0, 0.0)
	_checker._resolve_player_collisions()


func _wall_x() -> float:
	return GameRules.INNER_HALF_WIDTH - _victim.collision_radius() - 0.02


func test_a_check_into_the_boards_lands_harder_than_in_open_ice() -> void:
	_check_at(0.0, 6.0)
	assert_eq(_received.size(), 1, "the open-ice control landed")
	var open_ice: float = _received[0].length()
	_received.clear()
	_check_at(_wall_x(), 6.0)
	assert_eq(_received.size(), 1)
	assert_gt(_received[0].length(), open_ice * 1.2, "the boards take the recoil")

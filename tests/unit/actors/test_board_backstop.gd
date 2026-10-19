extends GutTest

# Skater contact against the boards (Skater._resolve_player_collisions with
# BoardPinRules): the same committed check lands harder on a victim with the
# boards behind him — for the stagger, which reads how hard it landed, not for
# the knockdown, which reads how far his body was driven. (The pin's onset is BoardPinTracker's — see
# test_board_pin_tracker.gd.) Real Skater scenes, resolved by hand from the
# checker's side.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")

var _checker: Skater = null
var _victim: Skater = null
var _received: Array[Vector3] = []
var _strengths: Array[float] = []


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
	_strengths.clear()
	_victim.body_check_received.connect(func(i: Vector3, strength: float) -> void:
		_received.append(i)
		_strengths.append(strength))


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
	var open_ice: float = _strengths[0]
	var open_ice_dv: float = _received[0].length()
	assert_almost_eq(open_ice, open_ice_dv, 1e-5, "in open ice, how hard is how far")
	_received.clear()
	_strengths.clear()
	_check_at(_wall_x(), 6.0)
	assert_eq(_received.size(), 1)
	assert_gt(_strengths[0], open_ice * 1.2, "the boards take the recoil")
	assert_almost_eq(_received[0].length(), open_ice_dv, 1e-5,
			"his body is driven no further: the knockdown reads that")


func test_a_pinner_driving_in_presses_his_man_into_the_wall_not_along_it() -> void:
	var y: float = GameRules.FACEOFF_SPAWN_HEIGHT
	_victim.global_position = Vector3(_wall_x(), y, 0.0)
	_victim.velocity = Vector3.ZERO
	_victim.pin_role = BoardPinRules.Role.PINNED
	_checker.pin_role = BoardPinRules.Role.PINNER
	_checker.hit_committed = false
	var touching: float = _victim.collision_radius() + _checker.collision_radius()
	# Off his line by half the escape: two discs would squeeze him along the wall.
	_checker.global_position = Vector3(_wall_x() - touching + 0.03, y,
			-0.5 * BoardPinRules.PIN_ESCAPE_OFFSET_M)
	_checker.velocity = Vector3(1.5, 0.0, 0.0)
	var z_before: float = _victim.global_position.z
	_checker._resolve_player_collisions()
	assert_gt(_victim.velocity.x, 0.0, "pressed into the boards")
	assert_eq(_victim.velocity.z, 0.0, "not along them")
	assert_eq(_victim.global_position.z, z_before)


# A carrier checked at a closing speed that leaves him the puck in open ice
# loses it crushed square into the boards: the strip reads how hard it landed.
func test_a_carrier_crushed_into_the_boards_loses_the_puck() -> void:
	var y: float = GameRules.FACEOFF_SPAWN_HEIGHT
	var closing: float = 3.5
	for case: Array in [[0.0, false], [_wall_x(), true]]:
		var puck: Puck = PUCK_SCENE.instantiate() as Puck
		add_child_autofree(puck)
		puck.set_physics_process(false)
		puck.set_process(false)
		puck._is_server = true
		_victim.global_position = Vector3(case[0], y, 0.0)
		puck.set_carrier(_victim)
		puck.on_body_check(_checker, _victim, _checker.weight * closing, Vector3(1.0, 0.0, 0.0))
		assert_eq(puck.carrier == null, case[1],
				"against the boards" if case[1] else "the open-ice control keeps it")

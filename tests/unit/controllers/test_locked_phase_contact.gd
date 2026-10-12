extends GutTest

# Skater-vs-skater contact is off while movement is locked. Every body then is
# frozen or on a scripted glide (the faceoff skate-in, the period skate-off), so
# a glide crossing the centre at skating speed is not a check: it must not
# stagger or knock him down into the drop, and must not shove him off the dot.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")


class StubGameState extends Node:
	var locked: bool = true

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return locked


var _state: StubGameState = null
var _puck: Puck = null
var _skaters: Array[Skater] = []


func before_each() -> void:
	_state = StubGameState.new()
	add_child_autofree(_state)
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_skaters = []


func _skater(pos: Vector3, vel: Vector3, tiebreak: int) -> Skater:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	skater.is_host_machine = true
	skater.collision_tiebreak_id = tiebreak
	var c := SkaterController.new()
	add_child_autofree(c)
	c.set_physics_process(false)
	c.set_process(false)
	c.setup(skater, _puck, _state)
	skater.global_position = pos
	skater.velocity = vel
	_skaters.append(skater)
	skater.set_skater_collision_provider(_all_skaters)
	return skater


func _all_skaters() -> Array:
	return _skaters


# A winger gliding through a centre who is set on the dot.
func _crossing() -> Array[Skater]:
	var center: Skater = _skater(Vector3.ZERO, Vector3.ZERO, 1)
	var winger: Skater = _skater(Vector3(-0.3, 0.0, 0.0), Vector3(9.0, 0.0, 0.0), 2)
	return [center, winger]


func test_a_glide_through_the_set_centre_is_not_a_check() -> void:
	var pair: Array[Skater] = _crossing()
	var center: Skater = pair[0]
	watch_signals(center)
	pair[1]._resolve_player_collisions()
	assert_signal_not_emitted(center, "body_check_received",
			"no stagger or knockdown carried into the drop")
	assert_eq(center.global_position, Vector3.ZERO, "the centre stays on his dot")
	assert_eq(center.velocity, Vector3.ZERO)


func test_the_same_crossing_in_live_play_is_a_check() -> void:
	# The control: without it the test above passes on a pair that never touched.
	_state.locked = false
	var pair: Array[Skater] = _crossing()
	var center: Skater = pair[0]
	watch_signals(center)
	pair[1]._resolve_player_collisions()
	assert_signal_emitted(center, "body_check_received")
	assert_ne(center.global_position, Vector3.ZERO)

extends GutTest

# A client-rendered remote carrier holds the host's slapshot pin, so the puck
# PuckController pins to him (get_carry_target_global) stays where the host's
# lay off him rather than under the raised blade — through a wind-up and through
# the recovery after one is called off. The spot is the packet's own puck
# (slapshot_pin_offset, world XZ), turned into the body's frame as drawn, so it
# has to land in the world where the host had it whichever way he faces.

const _OFFSET := Vector2(0.6, -1.1)


class StubGameState extends Node:
	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


func test_the_pinned_puck_lands_where_the_hosts_lay_at_any_facing() -> void:
	var rc: RemoteController = _remote()
	var skater: Skater = rc.skater
	for facing: Vector2 in [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(-0.6, 0.8)]:
		skater.set_facing(facing)
		rc._adopt_slapshot_pin(_state(true))
		assert_true(skater.is_slapshot_pinning(), "the wire's pin is held")
		var at: Vector3 = skater.get_carry_target_global()
		var want := Vector2(skater.global_position.x, skater.global_position.z) + _OFFSET
		assert_almost_eq(Vector2(at.x, at.z), want, Vector2(0.001, 0.001),
				"facing %s: the puck sits where the host's did off him" % facing)


func test_the_pin_lets_go_with_the_wire() -> void:
	var rc: RemoteController = _remote()
	rc._adopt_slapshot_pin(_state(true))
	rc._adopt_slapshot_pin(_state(false))
	assert_false(rc.skater.is_slapshot_pinning(), "the carry takes the puck back")


func _state(pinned: bool) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.slapshot_pinned = pinned
	s.slapshot_pin_offset = _OFFSET
	return s


func _remote() -> RemoteController:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(2.0, GameRules.FACEOFF_SPAWN_HEIGHT, -3.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var game_state := StubGameState.new()
	add_child_autofree(game_state)
	var rc := RemoteController.new()
	add_child_autofree(rc)
	rc.setup(skater, puck, game_state)
	rc.set_process(false)
	rc.set_physics_process(false)
	return rc

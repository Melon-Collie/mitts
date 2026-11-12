extends GutTest

# A stick without the puck is the top hand's alone: on the line from its
# shoulder to the blade, which is the reach solve's own hand, and as near in as
# that solve brings it. The two-handed pocket (test_carry_hold.gd) comes on with
# the puck over the grip's ease, and a defender takes his bottom hand off.
# Driven through the real controller and render pass.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _puck: Puck


func _make(at: Vector3, team: int) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_team_id_resolver(func() -> int: return team)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, _puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(at.x, GameRules.FACEOFF_SPAWN_HEIGHT, at.z)
	return c


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.global_position = Vector3(20.0, 0.0, 20.0)


func _hold(c: SkaterController, cursor: Vector3, ticks: int = 120) -> void:
	var sk: Skater = c.skater
	var input := InputState.new()
	for _t: int in ticks:
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = sk.global_position + cursor
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		sk._process(DT)


func test_the_hand_is_the_reach_solves_own() -> void:
	var c: SkaterController = _make(Vector3.ZERO, 0)
	for cursor: Vector3 in [Vector3(0.0, 0.0, -2.5), Vector3(-0.2, 0.0, -1.1),
			Vector3(0.6, 0.0, -0.4), Vector3(-1.2, 0.0, 0.3)]:
		_hold(c, cursor)
		assert_lt(c.skater.get_top_hand_position().distance_to(c._ik.reach_hand_local), 0.001,
				str(cursor))


func test_it_comes_in_nearer_than_a_carried_puck() -> void:
	var c: SkaterController = _make(Vector3.ZERO, 0)
	_hold(c, Vector3(0.0, 0.0, -0.5))
	var sk: Skater = c.skater
	var contact: Vector3 = sk.get_blade_contact_global() - sk.global_position
	assert_lt(Vector2(contact.x, contact.z).length(), c.carry_reach_min_m - 0.2,
			"an empty blade plays a puck inside the carry's floor")


func test_the_pocket_comes_on_with_the_puck_and_not_in_a_tick() -> void:
	var c: SkaterController = _make(Vector3.ZERO, 0)
	var cursor := Vector3(-0.2, 0.0, -1.15)
	_hold(c, cursor)
	var sk: Skater = c.skater
	_puck.set_carrier(sk)
	c.on_puck_picked_up_network()
	var prev: Vector3 = sk.get_top_hand_position()
	var furthest: float = 0.0
	for _t: int in 90:
		_hold(c, cursor, 1)
		furthest = maxf(furthest, sk.get_top_hand_position().distance_to(prev))
		prev = sk.get_top_hand_position()
	assert_gt(sk.get_top_hand_position().distance_to(c._ik.reach_hand_local), 0.05,
			"a carrier's hand is in its pocket")
	assert_lt(furthest, 0.03, "and went there at a hand's pace: %.3f m in its fastest tick" % furthest)


func test_a_defender_carries_his_stick_in_the_top_hand() -> void:
	var defender: SkaterController = _make(Vector3.ZERO, 0)
	var other: SkaterController = _make(Vector3(0.0, 0.0, -8.0), 1)
	var cursor := Vector3(0.0, 0.0, -2.0)
	_hold(defender, cursor)
	assert_lt(defender._ik._bh_release, 0.05, "a loose puck has both hands ready for it")
	_puck.set_carrier(other.skater)
	other.on_puck_picked_up_network()
	_hold(defender, cursor)
	assert_gt(defender._ik._bh_release, 0.95, "their puck, and the bottom hand is off the stick")
	defender.skater.set_team_id_resolver(func() -> int: return 1)
	_hold(defender, cursor)
	assert_lt(defender._ik._bh_release, 0.05, "his own team's, and it is back on")

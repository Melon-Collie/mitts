extends GutTest

# The cross-check on the host (CrossCheckTracker) and the victim's answer to it
# (SkaterController.take_cross_check): a shover in the push lands it once per
# throw on the nearest free opponent in reach and in front of him; the victim
# takes what his edges and stride don't hold, as a Δv and a stagger. Real
# Skater scenes and controllers, never ticked; phases and positions by hand.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const Phase = CrossCheckRules.Phase
const DT: float = 1.0 / 120.0


class HostStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _registry: PlayerRegistry = null
var _tracker: CrossCheckTracker = null
var _ctrl_by_skater: Dictionary = {}
var _shover: SkaterController = null
var _victim: SkaterController = null
var _landed: Array = []


func before_each() -> void:
	_ctrl_by_skater.clear()
	_landed.clear()
	_shover = _make(Vector3(0.0, 0.0, 0.0))
	_victim = _make(Vector3(0.9, 0.0, 0.0))
	_registry = PlayerRegistry.new()
	_registry._skaters_cache = [_shover.skater, _victim.skater] as Array[Skater]
	_registry.team_id_by_skater = {_shover.skater: 1, _victim.skater: 0}
	_tracker = CrossCheckTracker.new()
	_tracker.setup(_registry, func(s: Skater) -> SkaterController: return _ctrl_by_skater.get(s))
	_tracker.landed.connect(func(s: Skater, v: Skater, dv: float, d: Vector3) -> void:
		_landed.append([s, v, dv, d]))
	_shover.skater.set_facing(Vector2(1.0, 0.0))   # at the victim
	_victim.skater.set_facing(Vector2(1.0, 0.0))   # back to him: the push is along his blades


func _make(pos: Vector3) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var host := HostStub.new()
	add_child_autofree(host)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, host)
	skater.is_host_machine = true
	skater.global_position = Vector3(pos.x, GameRules.FACEOFF_SPAWN_HEIGHT, pos.z)
	_ctrl_by_skater[skater] = c
	return c


func _push() -> void:
	_shover.skater.cross_check_phase = Phase.EXTEND
	_tracker.tick(true)


func test_a_push_in_reach_lands_once_along_the_line_between_them() -> void:
	_push()
	assert_eq(_landed.size(), 1)
	assert_eq(_landed[0][1], _victim.skater)
	assert_gt(_victim.skater.velocity.x, 0.5, "pushed away along his blades")
	assert_gt(_victim.stagger_timer, 0.0, "and rattled")
	_tracker.tick(true)
	assert_eq(_landed.size(), 1, "one per throw")
	_shover.skater.cross_check_phase = Phase.RECOVER
	_tracker.tick(true)
	_push()
	assert_eq(_landed.size(), 2, "the next throw lands again")


func test_nothing_out_of_reach_behind_or_on_a_teammate() -> void:
	_victim.skater.global_position.x = 0.7 + CrossCheckRules.REACH_M + 0.1
	_push()
	assert_eq(_landed.size(), 0, "out of reach")
	_victim.skater.global_position.x = -0.9
	_shover.skater.cross_check_phase = Phase.REARM
	_tracker.tick(true)
	_push()
	assert_eq(_landed.size(), 0, "behind him")
	_victim.skater.global_position.x = 0.9
	_registry.team_id_by_skater[_victim.skater] = 1
	_shover.skater.cross_check_phase = Phase.REARM
	_tracker.tick(true)
	_push()
	assert_eq(_landed.size(), 0, "a teammate")


func test_nobody_in_a_pin_down_or_ghosted_is_shoved() -> void:
	for setup: Callable in [
			func() -> void: _victim.skater.pin_role = BoardPinRules.Role.PINNED,
			func() -> void: _victim.skater.is_knocked_down = true,
			func() -> void: _victim.skater.is_ghost = true,
			func() -> void: _shover.skater.is_ghost = true]:
		before_each()
		setup.call()
		_push()
		assert_eq(_landed.size(), 0)


func test_the_claim_lands_a_throw_the_present_has_not_and_only_once() -> void:
	_victim.skater.global_position.x = 3.0   # out of reach at present time
	_push()
	assert_eq(_landed.size(), 0)
	assert_true(_tracker.try_land(_shover.skater, _victim.skater), "the client saw him in reach")
	assert_false(_tracker.try_land(_shover.skater, _victim.skater), "and only once")
	assert_eq(_landed.size(), 1)


func test_a_set_man_across_his_blades_gives_less_than_one_pushed_along_them() -> void:
	_push()
	var along: float = _landed[0][2]
	before_each()
	_victim.skater.set_facing(Vector2(0.0, 1.0))   # side-on: the push is across his blades
	_victim.stance_active = true
	_push()
	assert_lt(_landed[0][2], along)


func test_the_ctrl_press_throws_only_from_puckless_skating_and_holding_is_the_commit() -> void:
	var input := InputState.new()
	input.hit_pressed = true
	input.hit_held = true
	_shover._advance_cross_check(input, DT)
	assert_eq(_shover.skater.cross_check_phase, Phase.EXTEND)
	_shover._apply_movement(input, DT)
	assert_true(_shover.skater.hit_committed, "still held: the commit")
	var carrier: SkaterController = _victim
	carrier.has_puck = true
	carrier._advance_cross_check(input, DT)
	assert_eq(carrier.skater.cross_check_phase, Phase.IDLE, "a carrier's Ctrl is the brace")

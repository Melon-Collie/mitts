extends GutTest

# The cross-check on the host (CrossCheckTracker) and the victim's answer to it
# (SkaterController.take_cross_check): a shover in the push lands it once per
# throw on the nearest free opponent on his shaft, along the aim he pressed it
# with; the victim takes what his edges and stride don't hold, as a Δv and a
# stagger. Real
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


# The throw at `elapsed`: by default the punch's first tick, past the load.
func _push(aim: Vector2 = Vector2(1.0, 0.0),
		elapsed: float = CrossCheckRules.LOAD_S) -> void:
	_shover.skater.cross_check_phase = Phase.THROW
	_shover.skater.cross_check_elapsed = elapsed
	_shover.skater.cross_check_aim = aim
	_tracker.tick(true)


func test_drawing_in_it_lands_nothing_and_the_punch_lands() -> void:
	_push(Vector2(1.0, 0.0), 0.5 * CrossCheckRules.LOAD_S)
	assert_eq(_landed.size(), 0, "the shaft is coming in")
	_push()
	assert_eq(_landed.size(), 1, "and lands going out")


func test_a_push_in_reach_lands_once() -> void:
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


func _chord() -> InputState:
	var input := InputState.new()
	input.hit_held = true
	input.stick_check_pressed = true
	return input


func test_the_chord_throws_only_from_puckless_skating_and_holding_is_the_commit() -> void:
	var input: InputState = _chord()
	_shover._advance_cross_check(input, DT)
	assert_eq(_shover.skater.cross_check_phase, Phase.THROW)
	_shover._apply_movement(input, DT)
	assert_true(_shover.skater.hit_committed, "Ctrl still held: the commit")
	var carrier: SkaterController = _victim
	carrier.has_puck = true
	carrier._advance_cross_check(input, DT)
	assert_eq(carrier.skater.cross_check_phase, Phase.IDLE, "a carrier's Ctrl is the brace")


func test_ctrl_alone_braces_and_f_alone_lifts() -> void:
	var brace := InputState.new()
	brace.hit_held = true
	_shover._advance_cross_check(brace, DT)
	assert_eq(_shover.skater.cross_check_phase, Phase.IDLE, "holding Ctrl throws nothing")
	var lift := InputState.new()
	lift.stick_check_pressed = true
	lift.stick_check_held = true
	_victim._advance_cross_check(lift, DT)
	_victim._advance_stick_check(lift, DT)
	assert_eq(_victim.skater.cross_check_phase, Phase.IDLE, "F alone is no cross-check")
	assert_ne(_victim.skater.stick_check_phase, StickCheckRules.Phase.IDLE, "it is the lift")


func test_the_chord_starts_no_lift() -> void:
	var input: InputState = _chord()
	input.stick_check_held = true
	_shover._advance_cross_check(input, DT)
	_shover._advance_stick_check(input, DT)
	assert_eq(_shover.skater.cross_check_phase, Phase.THROW)
	assert_eq(_shover.skater.stick_check_phase, StickCheckRules.Phase.IDLE)
	_shover.skater.cross_check_phase = Phase.REARM
	_shover._cross_check.phase = Phase.REARM
	_shover._advance_cross_check(input, DT)
	_shover._advance_stick_check(input, DT)
	assert_eq(_shover.skater.stick_check_phase, StickCheckRules.Phase.IDLE,
			"nor while it rearms: F with Ctrl down is the cross-check's")


func test_the_push_goes_where_it_was_aimed() -> void:
	var aim: Vector2 = Vector2(1.0, 0.0).rotated(deg_to_rad(55.0))
	var across: Vector2 = -aim.orthogonal() * 0.35   # on the shaft, off the chest's centre
	_victim.skater.global_position = Vector3(aim.x * 0.9 + across.x,
			GameRules.FACEOFF_SPAWN_HEIGHT, aim.y * 0.9 + across.y)
	_victim.skater.set_facing(aim)   # back to him along the aim
	_push()
	assert_eq(_landed.size(), 0, "off the square-on shaft")
	_shover.skater.cross_check_phase = Phase.REARM
	_tracker.tick(true)
	_push(aim)
	assert_eq(_landed.size(), 1, "the shaft turned to him")
	var push := Vector2(_victim.skater.velocity.x, _victim.skater.velocity.z).normalized()
	assert_almost_eq(push.angle_to(aim), 0.0, 1e-4, "and along the aim, not the line to him")


func test_the_press_latches_the_cursors_aim_for_the_throw() -> void:
	var input: InputState = _chord()
	var at := Vector3(1.0, 0.0, 1.0)
	input.mouse_world_pos = _shover.skater.global_position + at
	_shover._advance_cross_check(input, DT)
	var latched: Vector2 = _shover.skater.cross_check_aim
	assert_almost_eq(latched.angle_to(Vector2(at.x, at.z)), 0.0, 1e-4, "where the cursor was")
	input.stick_check_pressed = false
	input.mouse_world_pos = _shover.skater.global_position + Vector3(0.0, 0.0, -1.0)
	_shover._advance_cross_check(input, DT)
	assert_eq(_shover.skater.cross_check_aim, latched, "wherever the cursor goes after")
	input.mouse_world_pos = _shover.skater.global_position + Vector3(-1.0, 0.0, 0.1)
	_shover.skater.cross_check_phase = Phase.IDLE
	_shover._cross_check.reset()
	input.stick_check_pressed = true
	_shover._advance_cross_check(input, DT)
	assert_almost_eq(absf(Vector2(1.0, 0.0).angle_to(_shover.skater.cross_check_aim)),
			deg_to_rad(_shover.upper_body_max_twist_deg), 1e-4,
			"behind him: as far round as his chest turns")

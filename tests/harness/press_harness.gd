class_name PressHarness
extends RefCounted

# Two real SkaterControllers in contact at a standstill, ticked in the live
# order (every controller, then every skater's own physics tick): the attacker drives into the man in front of him. The
# man faces +z (up ice); "behind" puts the attacker between him and the net,
# pushing along his blades, "beside" off his side, pushing across them.
# Read by test_press.gd and the net-front press instrument.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0
const SETTLE_TICKS: int = 10


class HostStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


# What each body does through the press.
class Spec:
	var man_lbs: int = 201
	var attacker_lbs: int = 201
	var side: String = "behind"
	var man_stance: bool = false
	var man_back: bool = false      # skates back into the attacker
	var man_brake: bool = false
	var man_stagger_s: float = 0.0  # a stagger he starts the press under
	var attacker: String = "skate commit"   # "skate", "skate commit", "skate stance"


class Result:
	var gave_1s: float = 0.0        # m the man was moved along the push after 1 s
	var gave: float = 0.0           # ... at the end
	var went: float = 0.0           # m the attacker travelled along the push
	var gap_end: float = 0.0        # body edge to body edge along the push at the end
	var man_speed: float = 0.0      # the man's speed along the push at the end
	var peak_stagger: float = 0.0
	var knocked: bool = false


var man: SkaterController = null
var attacker: SkaterController = null
var _test: GutTest = null


func _init(test: GutTest) -> void:
	_test = test


func _make(lbs: int) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	_test.add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	_test.add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	var host := HostStub.new()
	_test.add_child_autofree(host)
	var c := SkaterController.new()
	_test.add_child_autofree(c)
	c.setup(skater, puck, host)
	c.apply_attributes(PlayerAttributes.new(PlayerAttributes.HEIGHT_MEDIUM, lbs))
	skater.is_host_machine = true
	return c


func _rig(spec: Spec) -> void:
	man = _make(spec.man_lbs)
	attacker = _make(spec.attacker_lbs)
	var both: Array = [man.skater, attacker.skater]
	man.skater.set_skater_collision_provider(func() -> Array: return both)
	attacker.skater.set_skater_collision_provider(func() -> Array: return both)


func _tick(mi: InputState, ai: InputState) -> void:
	mi.delta = DT
	ai.delta = DT
	mi.host_timestamp += DT
	ai.host_timestamp += DT
	mi.mouse_world_pos = man.skater.global_position + Vector3(0.0, 0.0, 3.0)
	man._process_input(mi, DT)
	attacker._process_input(ai, DT)
	man.skater._physics_process(DT)
	attacker.skater._physics_process(DT)


func _face(c: SkaterController, facing: Vector2) -> void:
	c._pose.facing = facing
	c.skater.set_facing(facing)


func run(spec: Spec, seconds: float) -> Result:
	_rig(spec)
	var push := Vector3(0.0, 0.0, 1.0) if spec.side == "behind" else Vector3(1.0, 0.0, 0.0)
	var mi := InputState.new()
	var ai := InputState.new()
	# Both set, in contact and still, before the press starts: the man faces up
	# ice, the attacker the push.
	var home := Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_face(man, Vector2(0.0, 1.0))
	_face(attacker, Vector2(push.x, push.z))
	for i: int in SETTLE_TICKS:
		ai.mouse_world_pos = attacker.skater.global_position + push * 3.0
		_tick(mi, ai)
		var gap: float = man.skater.collision_radius() + attacker.skater.collision_radius()
		man.skater.global_position = home
		man.skater.velocity = Vector3.ZERO
		attacker.skater.global_position = home - push * gap
		attacker.skater.velocity = Vector3.ZERO
	man.stagger_timer = spec.man_stagger_s
	var r := Result.new()
	var man_from: Vector3 = man.skater.global_position
	var attacker_from: Vector3 = attacker.skater.global_position
	for i: int in int(seconds / DT):
		mi.stance_held = spec.man_stance
		mi.brake = spec.man_brake
		mi.move_vector = Vector2(-push.x, -push.z) if spec.man_back else Vector2.ZERO
		ai.mouse_world_pos = attacker.skater.global_position + push * 3.0
		ai.stance_held = spec.attacker.contains("stance")
		ai.hit_held = spec.attacker.contains("commit")
		ai.move_vector = Vector2(push.x, push.z)
		_tick(mi, ai)
		r.peak_stagger = maxf(r.peak_stagger, man.stagger_timer)
		r.knocked = r.knocked or man.knockdown_timer > 0.0
		if i == int(1.0 / DT) - 1:
			r.gave_1s = (man.skater.global_position - man_from).dot(push)
	r.gave = (man.skater.global_position - man_from).dot(push)
	r.went = (attacker.skater.global_position - attacker_from).dot(push)
	r.gap_end = (man.skater.global_position - attacker.skater.global_position).dot(push) \
			- man.skater.collision_radius() - attacker.skater.collision_radius()
	r.man_speed = man.skater.velocity.dot(push)
	return r

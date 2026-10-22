extends GutTest

# What a sustained press moves today: two real SkaterControllers in contact at a
# standstill, ticked in the live order (every controller, then every skater's
# own physics tick, then the host's cross-check tracker), the attacker skating
# into the man in front of him for two seconds. Prints how far the man gives
# ground and how far the attacker gets, against what the cross-check buys from
# the same spot. Read by docs/net-front-battles-plan.md; asserts nothing.
#
# The man faces +z (up ice, the point); the net is behind him at -z. "behind"
# puts the attacker between him and the net, pushing along his blades; "beside"
# puts him off the man's side, pushing across them.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0
const PRESS_S: float = 2.0
const SETTLE_TICKS: int = 60


class HostStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _man: SkaterController = null
var _attacker: SkaterController = null
var _shoves: CrossCheckTracker = null


func _make(lbs: int) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(30.0, 0.0, 30.0)
	var host := HostStub.new()
	add_child_autofree(host)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, host)
	c.apply_attributes(PlayerAttributes.new(PlayerAttributes.HEIGHT_MEDIUM, lbs))
	skater.is_host_machine = true
	return c


func _rig(man_lbs: int, attacker_lbs: int, side: String) -> void:
	_man = _make(man_lbs)
	_attacker = _make(attacker_lbs)
	var both: Array = [_man.skater, _attacker.skater]
	_man.skater.set_skater_collision_provider(func() -> Array: return both)
	_attacker.skater.set_skater_collision_provider(func() -> Array: return both)
	var reg := PlayerRegistry.new()
	reg._skaters_cache = [_man.skater, _attacker.skater] as Array[Skater]
	reg.team_id_by_skater = {_man.skater: 0, _attacker.skater: 1}
	var controller_of: Dictionary = {_man.skater: _man, _attacker.skater: _attacker}
	_shoves = CrossCheckTracker.new()
	_shoves.setup(reg, func(s: Skater) -> SkaterController: return controller_of.get(s))
	var gap: float = _man.skater.collision_radius() + _attacker.skater.collision_radius()
	_man.skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	var offset := Vector3(0.0, 0.0, -gap) if side == "behind" else Vector3(-gap, 0.0, 0.0)
	_attacker.skater.global_position = _man.skater.global_position + offset


func _tick(man_in: InputState, attacker_in: InputState) -> void:
	man_in.delta = DT
	attacker_in.delta = DT
	man_in.host_timestamp += DT
	attacker_in.host_timestamp += DT
	man_in.mouse_world_pos = _man.skater.global_position + Vector3(0.0, 0.0, 3.0)
	_man._process_input(man_in, DT)
	_attacker._process_input(attacker_in, DT)
	_man.skater._physics_process(DT)
	_attacker.skater._physics_process(DT)
	_shoves.tick(true)


# One row: the man's posture and push-back, the attacker's posture, for
# PRESS_S. The attacker aims and skates along `push` (+z behind, +x beside).
# "shove" throws one cross-check instead of skating in.
func _row(label: String, man_lbs: int, attacker_lbs: int, side: String,
		man_stance: bool, man_back: bool, attacker_mode: String, man_brake: bool = false) -> String:
	_rig(man_lbs, attacker_lbs, side)
	var push := Vector3(0.0, 0.0, 1.0) if side == "behind" else Vector3(1.0, 0.0, 0.0)
	var mi := InputState.new()
	var ai := InputState.new()
	# Both set before contact matters: the man faces up ice, the attacker the push.
	for i: int in SETTLE_TICKS:
		ai.mouse_world_pos = _attacker.skater.global_position + push * 3.0
		_tick(mi, ai)
		_man.skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		_man.skater.velocity = Vector3.ZERO
		var gap: float = _man.skater.collision_radius() + _attacker.skater.collision_radius()
		_attacker.skater.global_position = _man.skater.global_position - push * gap
		_attacker.skater.velocity = Vector3.ZERO
	var man_from: Vector3 = _man.skater.global_position
	var attacker_from: Vector3 = _attacker.skater.global_position
	var max_stagger: float = 0.0
	var knocked: bool = false
	var gave_at_1s: float = 0.0
	for i: int in int(PRESS_S / DT):
		mi.stance_held = man_stance
		mi.brake = man_brake
		mi.move_vector = Vector2(-push.x, -push.z) if man_back else Vector2.ZERO
		ai.mouse_world_pos = _attacker.skater.global_position + push * 3.0
		ai.stance_held = attacker_mode.contains("stance")
		ai.hit_held = attacker_mode.contains("commit") or attacker_mode == "shove"
		ai.stick_check_pressed = attacker_mode == "shove" and i == 0
		ai.move_vector = Vector2(push.x, push.z) if attacker_mode != "shove" else Vector2.ZERO
		_tick(mi, ai)
		max_stagger = maxf(max_stagger, _man.stagger_timer)
		knocked = knocked or _man.knockdown_timer > 0.0
		if i == int(1.0 / DT) - 1:
			gave_at_1s = (_man.skater.global_position - man_from).dot(push)
	var gave: float = (_man.skater.global_position - man_from).dot(push)
	var went: float = (_attacker.skater.global_position - attacker_from).dot(push)
	var gap_end: float = (_man.skater.global_position - _attacker.skater.global_position).dot(push) \
			- _man.skater.collision_radius() - _attacker.skater.collision_radius()
	return "| %s | %d / %d | %s | %s | %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %s |" % [
			label, man_lbs, attacker_lbs, side,
			("stance" if man_stance else "upright") + (", backing in" if man_back else "")
					+ (", braking" if man_brake else ""),
			attacker_mode, gave_at_1s, gave, went, gap_end,
			_man.skater.velocity.dot(push), max_stagger, "yes" if knocked else "no"]


func test_print_the_press_table() -> void:
	var rows: Array[String] = [
		"| case | man / attacker lb | side | man | attacker | gave 1 s (m) | gave 2 s (m) | attacker went (m) | gap at end (m) | man speed at end (m/s) | peak stagger (s) | down |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|",
	]
	var cases: Array = [
		# label, man lb, attacker lb, side, man stance, man backs in, attacker mode
		["skate in", 201, 201, "behind", false, false, "skate"],
		["skate in, committed", 201, 201, "behind", false, false, "skate commit"],
		["skate in, stance", 201, 201, "behind", false, false, "skate stance"],
		["man anchored", 201, 201, "behind", true, false, "skate commit"],
		["man backs in", 201, 201, "behind", false, true, "skate commit"],
		["man backs in, uncommitted attacker", 201, 201, "behind", false, true, "skate"],
		["man brakes", 201, 201, "behind", false, false, "skate commit", true],
		["man brakes, stance", 201, 201, "behind", true, false, "skate commit", true],
		["man brakes, from the side", 201, 201, "beside", false, false, "skate commit", true],
		["man brakes, heavy uncommitted attacker", 170, 235, "behind", false, false, "skate", true],
		["cross-check, man brakes", 201, 201, "behind", false, false, "shove", true],
		["man anchored, backs in", 201, 201, "behind", true, true, "skate commit"],
		["heavy on light", 170, 235, "behind", false, false, "skate commit"],
		["light on heavy", 235, 170, "behind", false, false, "skate commit"],
		["light on heavy, anchored", 235, 170, "behind", true, true, "skate commit"],
		["from the side", 201, 201, "beside", false, false, "skate commit"],
		["from the side, anchored", 201, 201, "beside", true, false, "skate commit"],
		["cross-check", 201, 201, "behind", false, false, "shove"],
		["cross-check, anchored", 201, 201, "behind", true, false, "shove"],
		["cross-check, side", 201, 201, "beside", false, false, "shove"],
		["cross-check, side, anchored", 201, 201, "beside", true, false, "shove"],
	]
	for c: Array in cases:
		rows.append(_row(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c.size() > 7 and bool(c[7])))
	gut.p("\n" + "\n".join(rows))
	assert_true(true)

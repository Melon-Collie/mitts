extends GutTest

# Parity: the blade pass in C++ (NativeBladePass) against its GDScript reference
# (SkaterIKCoordinator.apply_blade_toward), skated side by side through the real
# controller. Every tick's top hand, blade, reach target and reach purpose, and
# every puck released mid-pass, must agree: across open ice, a reach for a loose
# puck, a carry swept round both sides with a wrister wound up, the boards, the
# net, the goalies, and a commit stance.
#
# Tolerance is the native kernels' (test_native_ik_parity.gd): both sides keep
# GDScript's precision model, so they part only by roundoff.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const TICKS: int = 240
const TOLERANCE: float = 0.001


class GameStateStub:
	extends Node

	var goalies: Array[Dictionary] = []

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func get_goalie_data() -> Array[Dictionary]:
		return goalies


class Scenario:
	var start := Vector3.ZERO
	var move := Vector2(0.0, -1.0)
	var carry: bool = false
	var puck_on_line: bool = false
	# Ticks the wrister is held over, and the commit (hit) held over.
	var shoot_from: int = -1
	var shoot_to: int = -1
	var hit_from: int = -1
	var hit_to: int = -1
	# Cursor reach off the body, metres, and its sweep (radians either side).
	var reach: float = 1.6
	var sweep: float = 2.6
	# The bearing the sweep centres on, radians from -Z toward +X.
	var aim: float = 0.0
	var goalies: Array[Dictionary] = []
	# Whether a release takes the puck off him, as the host's listener does.
	var release_clears: bool = false
	# The wall pin's squeeze (Skater.wall_squeeze_threshold); the board reach
	# limit keeps a sweep well under the shipped one.
	var squeeze_threshold: float = -1.0


func _native_missing() -> bool:
	if ClassDB.class_exists(&"NativeBladePass"):
		return false
	NativeParityGuard.report_missing(self, "NativeBladePass")
	return true


# Every tick's hand, blade, reach target and (purpose, 0, 0); every release's
# direction and (power, tick, 0).
func _run(native: bool, sc: Scenario) -> Dictionary:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	gs.goalies = sc.goalies
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	c._ik.native_pass_enabled = native
	if native:
		assert_not_null(c._ik._native_pass, "the native pass is wired")
	skater.global_position = Vector3(sc.start.x, GameRules.FACEOFF_SPAWN_HEIGHT, sc.start.z)
	if sc.squeeze_threshold >= 0.0:
		skater.wall_squeeze_threshold = sc.squeeze_threshold
	if sc.carry:
		c.has_puck = true
		c._sm.set_state(SkaterStateMachine.State.SKATING_WITH_PUCK)
	var releases := PackedVector3Array()
	var tick: int = 0
	c.puck_release_requested.connect(
			func(dir: Vector3, power: float, _slapper: bool) -> void:
				releases.append(dir)
				releases.append(Vector3(power, tick, 0.0))
				if sc.release_clears:
					c.has_puck = false)
	var out := PackedVector3Array()
	var walls: int = 0
	var nets: int = 0
	var input := InputState.new()
	for i: int in TICKS:
		tick = i
		var a: float = sc.aim + sin(float(i) * 0.05) * sc.sweep
		var dir := Vector3(sin(a), 0.0, -cos(a))
		input.delta = DT
		input.host_timestamp += DT
		input.move_vector = sc.move
		input.shoot_held = i >= sc.shoot_from and i < sc.shoot_to
		input.shoot_pressed = i == sc.shoot_from
		input.hit_held = i >= sc.hit_from and i < sc.hit_to
		input.mouse_world_pos = skater.global_position \
				+ dir * (sc.reach * (0.7 + 0.5 * absf(cos(float(i) * 0.031))))
		input.mouse_world_pos.y = 0.0
		if sc.puck_on_line:
			puck.global_position = skater.global_position + dir * 1.8
			puck.global_position.y = 0.0
		c._process_input(input, DT)
		skater._physics_process(DT)
		out.append(skater.get_top_hand_position())
		out.append(skater.get_blade_position())
		out.append(c._ik.last_target_blade_world)
		out.append(Vector3(c._ik.reach_purpose, 0.0, 0.0))
		if skater.get_blade_wall_normal() != Vector3.ZERO:
			walls += 1
		if not native and c._ik._net_result.hit():
			nets += 1
	skater.free()
	return {"ticks": out, "releases": releases, "walls": walls, "nets": nets}


# The reference run, for the coverage a scenario is there to give.
func _assert_parity(sc: Scenario, label: String) -> Dictionary:
	if _native_missing():
		return {}
	var ref: Dictionary = _run(false, sc)
	var nat: Dictionary = _run(true, sc)
	assert_eq(nat["walls"], ref["walls"], "%s: ticks on the boards" % label)
	var a: PackedVector3Array = ref["ticks"]
	var b: PackedVector3Array = nat["ticks"]
	var worst: float = 0.0
	var first: int = -1
	for i: int in a.size():
		var d: float = a[i].distance_to(b[i])
		if d > worst:
			worst = d
		if first < 0 and d > TOLERANCE:
			first = i
	assert_lt(worst, TOLERANCE, "%s: worst %f, first over at tick %d (row %d)" % [
			label, worst, first / 4, first % 4])
	var ra: PackedVector3Array = ref["releases"]
	var rb: PackedVector3Array = nat["releases"]
	assert_eq(rb.size(), ra.size(), "%s: releases %d vs %d" % [label, rb.size() / 2, ra.size() / 2])
	for i: int in mini(ra.size(), rb.size()):
		assert_lt(ra[i].distance_to(rb[i]), TOLERANCE, "%s: release row %d" % [label, i])
	return ref


func test_open_ice() -> void:
	_assert_parity(Scenario.new(), "open ice")


func test_a_loose_puck_on_the_line() -> void:
	var sc := Scenario.new()
	sc.move = Vector2(0.3, -0.6)
	sc.puck_on_line = true
	_assert_parity(sc, "loose puck")


func test_a_carry_round_both_sides_with_a_wrister() -> void:
	var sc := Scenario.new()
	sc.move = Vector2(-0.4, -1.0)
	sc.carry = true
	sc.shoot_from = 150
	sc.shoot_to = 200
	_assert_parity(sc, "carry")


func test_carrying_into_the_boards() -> void:
	var sc := Scenario.new()
	sc.start = Vector3(GameRules.INNER_HALF_WIDTH - 1.5, 0.0, 0.0)
	sc.move = Vector2(1.0, -0.4)
	sc.carry = true
	sc.reach = 2.6
	sc.sweep = 1.0
	sc.aim = PI * 0.5
	sc.squeeze_threshold = 0.01
	var ref: Dictionary = _assert_parity(sc, "boards")
	if not ref.is_empty():
		assert_gt(ref["walls"], 0, "the blade met the boards")
		assert_gt((ref["releases"] as PackedVector3Array).size(), 0, "the boards pinned the puck off")


func test_round_the_net() -> void:
	var sc := Scenario.new()
	sc.start = Vector3(-2.0, 0.0, GameRules.GOAL_LINE_Z + 0.5)
	sc.move = Vector2(1.0, 0.0)
	sc.reach = 2.0
	var ref: Dictionary = _assert_parity(sc, "net")
	if not ref.is_empty():
		assert_gt(ref["nets"], 0, "the blade met the net")


func test_into_the_goalies_reach() -> void:
	for clears: bool in [false, true]:
		var sc := Scenario.new()
		sc.start = Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z - 3.0)
		sc.move = Vector2(0.0, 0.6)
		sc.carry = true
		sc.release_clears = clears
		sc.goalies = [
			{"position": Vector3(0.6, 0.0, GameRules.GOAL_LINE_Z - 1.2), "is_butterfly": true,
				"rotation_y": 0.3},
			{"position": Vector3(-0.4, 0.0, GameRules.GOAL_LINE_Z - 0.9), "is_butterfly": false,
				"rotation_y": 0.0},
		]
		_assert_parity(sc, "goalies, release clears %s" % clears)


func test_a_commit_stance() -> void:
	var sc := Scenario.new()
	sc.hit_from = 40
	sc.hit_to = 160
	_assert_parity(sc, "commit")

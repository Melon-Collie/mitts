extends GutTest

# Where today's gameplay hands can be held, all round the body
# (docs/held-hands-plan.md, phase 1). The live controller carrying, the cursor
# held at each bearing and reach off the facing (+ forehand), standing with the
# facing held and skating up-ice, a fresh carrier for each. On the last tick of
# each settle the top hand gameplay placed (the anchor) is scored by
# SkaterHoldModel against the body as drawn (the trunk SkaterArmRig puts on
# screen), and the stick's sphere round the blade is searched for a hand that
# body holds. Grids, bearings down and reaches across:
#   anchor  metres past every limit, summed (mm), and the one furthest past:
#           f fist, F fold (hand on its shoulder), k knob, s shaft, r reach,
#           e top sleeve, R bottom arm's reach, E bottom sleeve; "." is held
#   tick    the same against the trunk the tick sees (SkaterIKCoordinator.
#           fill_hold_body), which sits higher than the drawn one
#   best    the least any hand on the sphere reaches (mm)
#   move    how far the nearest hand the body holds outright lies from the
#           anchor (cm), "--" where none does within the search
# Then the cursor swept round at a carry's pace, sampled every third tick.
#
# Asserts nothing: run it when the question is "can the hands be held".
#   bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments/actors -gselect=test_hold_map
# HOLD_MAP_SWEEPS_ONLY=1 runs the sweeps alone.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const ANGLES_DEG: Array[float] = [-150.0, -120.0, -90.0, -60.0, -30.0, 0.0, 30.0, 60.0,
		90.0, 120.0, 150.0]
const RADII_M: Array[float] = [0.8, 1.1, 1.4, 1.8]
const SETTLE_TICKS: int = 120
const SKATE_WARMUP_TICKS: int = 180
const SKATE_START_Z: float = 26.0
const SWEEP_RATE_DEG_S: float = 90.0
const SWEEP_TICKS: int = int(300.0 / SWEEP_RATE_DEG_S / DT)
const SWEEP_SETTLE_TICKS: int = 60
const SWEEP_EVERY: int = 3
# A pose this far past its limits (summed) counts as not held.
const BROKEN_M: float = 0.005
const CODES: Dictionary = {"": ".", "fist": "f", "fold": "F", "knob": "k", "shaft": "s",
		"reach": "r", "sleeve": "e", "b.reach": "R", "b.sleeve": "E"}


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _controller: SkaterController
var _drawn := SkaterHoldModel.Body.new()
var _tick := SkaterHoldModel.Body.new()
var _report := SkaterHoldModel.Report.new()
var _scratch := SkaterHoldModel.Report.new()
var _search := SkaterHoldModel.Search.new()


func test_hold_map() -> void:
	if OS.get_environment("HOLD_MAP_SWEEPS_ONLY") != "1":
		for skating: bool in [false, true]:
			gut.p(_map(skating))
	for skating: bool in [false, true]:
		for r: float in [0.6, 1.2]:
			gut.p(_sweep(r, skating))
	assert_true(true)


func _map(skating: bool) -> String:
	var rows: Array[String] = []
	var broken: int = 0
	var unheld: int = 0
	var moves := PackedFloat64Array()
	var binds: Dictionary = {}
	for a: float in ANGLES_DEG:
		var row: String = "  %+5.0f° " % a
		for r: float in RADII_M:
			_build(skating)
			var input := InputState.new()
			for _i: int in SETTLE_TICKS:
				_step(input, _aim(a, r), skating)
			var cell: Dictionary = _cell()
			row += "%s | " % _fmt_cell(cell)
			if cell["anchor"] > BROKEN_M:
				broken += 1
				binds[cell["bind"]] = int(binds.get(cell["bind"], 0)) + 1
				if cell["move"] < 0.0:
					unheld += 1
				else:
					moves.append(cell["move"])
			_free()
		rows.append(row)
	moves.sort()
	var head: String = "\n══ %s: anchor/tick mm, best mm, move cm per reach %s" % [
			"skating up-ice" if skating else "standing, facing held", RADII_M]
	var tail: String = "\n  %d of %d cells not held (by %s); of those %d held by a hand on the sphere, moved %s cm, %d by none" % [
			broken, ANGLES_DEG.size() * RADII_M.size(), binds, moves.size(), _quantiles(moves),
			unheld]
	return head + "\n" + "\n".join(rows) + tail


# The anchor against both trunks, and the sphere searched on the drawn one.
func _cell() -> Dictionary:
	_controller._ik.fill_hold_body(_tick)
	_controller._ik.fill_hold_body(_drawn)
	_skater.fill_drawn_trunk(_drawn)
	var hand: Vector3 = _skater.top_hand.position
	var blade: Vector3 = _skater.blade.position
	SkaterHoldModel.evaluate(_tick, hand, blade, _report)
	var tick_total: float = _report.total()
	SkaterHoldModel.evaluate(_drawn, hand, blade, _report)
	var cell: Dictionary = {"anchor": _report.total(), "bind": _report.binding(),
			"tick": tick_total, "best": 0.0, "move": 0.0}
	if _report.total() > BROKEN_M:
		SkaterHoldModel.search(_drawn, hand, blade, _scratch, _search)
		cell["best"] = _search.best_total
		cell["move"] = _search.held_hand.distance_to(hand) if _search.held_found else -1.0
	return cell


func _fmt_cell(cell: Dictionary) -> String:
	if cell["anchor"] <= BROKEN_M:
		return "   .  %4.0f           " % (cell["tick"] * 1000.0)
	return "%4.0f%s %4.0f %4.0f %5s" % [cell["anchor"] * 1000.0, CODES[cell["bind"]],
			cell["tick"] * 1000.0, cell["best"] * 1000.0,
			"--" if cell["move"] < 0.0 else "%.0f" % (cell["move"] * 100.0)]


func _quantiles(sorted: PackedFloat64Array) -> String:
	if sorted.is_empty():
		return "-"
	var at := func(q: float) -> float: return sorted[mini(int(q * sorted.size()), sorted.size() - 1)] * 100.0
	return "median %.0f, 90%% %.0f, max %.0f" % [at.call(0.5), at.call(0.9), sorted[sorted.size() - 1] * 100.0]


func _sweep(r: float, skating: bool) -> String:
	_build(skating)
	var input := InputState.new()
	for _i: int in SWEEP_SETTLE_TICKS:
		_step(input, _aim(-150.0, r), skating)
	var samples: int = 0
	var broken: int = 0
	var unheld: int = 0
	var moves := PackedFloat64Array()
	var binds: Dictionary = {}
	for i: int in SWEEP_TICKS:
		_step(input, _aim(-150.0 + SWEEP_RATE_DEG_S * DT * i, r), skating)
		if i % SWEEP_EVERY != 0:
			continue
		samples += 1
		var cell: Dictionary = _cell()
		if cell["anchor"] > BROKEN_M:
			broken += 1
			binds[cell["bind"]] = int(binds.get(cell["bind"], 0)) + 1
			if cell["move"] < 0.0:
				unheld += 1
			else:
				moves.append(cell["move"])
	_free()
	moves.sort()
	return "\n══ sweep at %.1f m, %s: %d of %d samples not held (by %s); of those %d held by a hand on the sphere, moved %s cm, %d by none" % [
			r, "skating" if skating else "standing", broken, samples, binds, moves.size(),
			_quantiles(moves), unheld]


func _aim(deg: float, r: float) -> Vector3:
	var a: float = deg_to_rad(deg)
	var fh: float = signf(_skater.bottom_shoulder.position.x)
	return Vector3(sin(a) * r * fh, 0.0, -cos(a) * r)


func _build(skating: bool) -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, gs)
	_controller.apply_attributes(PlayerAttributes.neutral())
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT,
			SKATE_START_Z if skating else 0.0)
	_skater._process(DT)
	puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	if skating:
		var input := InputState.new()
		for _i: int in SKATE_WARMUP_TICKS:
			_step(input, Vector3(0.0, 0.0, -1.2), true)


func _free() -> void:
	_skater.get_parent().remove_child(_skater)
	_skater.queue_free()


func _step(input: InputState, aim: Vector3, skating: bool) -> void:
	input.delta = DT
	input.host_timestamp += DT
	input.move_vector = Vector2(0.0, -1.0) if skating else Vector2.ZERO
	if not skating:
		_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		_skater.velocity = Vector3.ZERO
		_controller._pose.facing = Vector2(0.0, -1.0)
		_skater.set_facing(_controller._pose.facing)
	input.mouse_world_pos = _skater.global_position + _skater.global_transform.basis * aim
	input.mouse_world_pos.y = 0.0
	_skater.capture_prev_blade_contact()
	_controller._process_input(input, DT)
	_skater._physics_process(DT)
	_skater._process(DT)

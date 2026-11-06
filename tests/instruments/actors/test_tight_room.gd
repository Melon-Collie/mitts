extends GutTest

# How close in the blade can come with a hand a body holds (docs/held-hands-
# plan.md §13): per bearing off the facing, standing with the facing held and
# skating up-ice, the cursor walked in from well out to the skates and the
# blade carried there settled at each step. Each blade is then searched for any
# top hand that holds it (SkaterHoldModel.search_lie: the shaft at the blade's
# lie ± its window (15°, TIGHT_LIE_WINDOW), against the trunk the tick sees), with the top hand
# free to ride anywhere and held HAND_BELOW_SHOULDER_M under its shoulder.
# Per bearing (where the blade went, m from the body's centre):
#   today   the closest the carry brings the blade
#   free    the closest blade some hand holds, no height rule
#   low     the same with the hand held under the chest
#   gaps    reaches out past `low` that no hand holds (the rule's floor is not
#           one line there)
#
# Asserts nothing: run it when the question is "what does the rule cost in tight".
#   bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments/actors -gselect=test_tight_room
# TIGHT_LIE_WINDOW=<deg> widens the lie window (default 15).

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const BEARINGS_DEG: Array[float] = [-150.0, -135.0, -120.0, -105.0, -90.0, -75.0, -60.0,
		-45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0, 105.0, 120.0, 135.0, 150.0]
const REACHES_M: Array[float] = [1.6, 1.4, 1.2, 1.1, 1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4]
const SETTLE_TICKS: int = 120
const SKATE_WARMUP_TICKS: int = 180
const SKATE_START_Z: float = 26.0
var _lie_window_deg: float = float(OS.get_environment("TIGHT_LIE_WINDOW")) if OS.has_environment("TIGHT_LIE_WINDOW") else 15.0
const HAND_BELOW_SHOULDER_M: float = 0.2


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _controller: SkaterController
var _body := SkaterHoldModel.Body.new()
var _scratch := SkaterHoldModel.Report.new()
var _search := SkaterHoldModel.Search.new()


func test_tight_room() -> void:
	for skating: bool in [false, true]:
		gut.p(_room(skating))
	assert_true(true)


func _room(skating: bool) -> String:
	var out: String = "\n══ %s: bearing → blade's bearing, then m from the body's centre\n  cursor  blade   today   free    low   lost  gaps" % [
			"skating up-ice" if skating else "standing, facing held"]
	var lost_total: float = 0.0
	var lost_n: int = 0
	for bearing: float in BEARINGS_DEG:
		var today: float = INF
		var free: float = INF
		var low: float = INF
		var blade_bearing: float = 0.0
		var cells: Array[Vector3] = []
		for r: float in REACHES_M:
			_build(skating)
			var input := InputState.new()
			for _i: int in SETTLE_TICKS:
				_step(input, _aim(bearing, r), skating)
			var d: float = _blade_out()
			blade_bearing = _blade_bearing()
			var held: Vector2 = _held()
			today = minf(today, d)
			if held.x > 0.0:
				free = minf(free, d)
			if held.y > 0.0:
				low = minf(low, d)
			cells.append(Vector3(d, held.x, held.y))
			_free()
		var gaps: int = 0
		for c: Vector3 in cells:
			if c.x > low + 0.01 and c.z <= 0.0:
				gaps += 1
		var lost: float = low - today
		if is_finite(lost):
			lost_total += lost
			lost_n += 1
		out += "\n  %+5.0f° %+5.0f° %6.2f %6.2f %6.2f %6.2f %4d" % [bearing, blade_bearing, today,
				free, low, lost, gaps]
	out += "\n  mean room lost under the rule: %.2f m over %d bearings" % [
			lost_total / maxf(lost_n, 1), lost_n]
	return out


# Whether some hand holds this blade, without and with the height rule (1 or 0).
func _held() -> Vector2:
	_controller._ik.fill_hold_body(_body)
	var hand: Vector3 = _skater.top_hand.position
	var blade: Vector3 = _skater.blade.position
	var length: float = hand.distance_to(blade)
	var lie: float = deg_to_rad(_skater.blade_lie_deg)
	var window: float = deg_to_rad(_lie_window_deg)
	_body.hand_below_shoulder = INF
	SkaterHoldModel.search_lie(_body, blade, length, lie, window, _scratch, _search)
	var free: float = 1.0 if _search.held_found else 0.0
	_body.hand_below_shoulder = HAND_BELOW_SHOULDER_M
	SkaterHoldModel.search_lie(_body, blade, length, lie, window, _scratch, _search)
	return Vector2(free, 1.0 if _search.held_found else 0.0)


func _blade_rel() -> Vector3:
	var world: Vector3 = _skater.upper_body_to_global(_skater.blade.position)
	return _skater.global_transform.basis.inverse() * (world - _skater.global_position)


func _blade_out() -> float:
	var rel: Vector3 = _blade_rel()
	return Vector2(rel.x, rel.z).length()


# Degrees off the facing, + toward the forehand.
func _blade_bearing() -> float:
	var rel: Vector3 = _blade_rel()
	var fh: float = signf(_skater.bottom_shoulder.position.x)
	return rad_to_deg(atan2(rel.x * fh, -rel.z))


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

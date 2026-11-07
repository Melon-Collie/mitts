extends GutTest

# SkaterHoldModel on a standing skater's own body (SkaterIKCoordinator.
# fill_hold_body): a fist in the chest reads past its limit by how far it is in,
# the score is a function of its inputs alone, the sphere search finds the held
# hand an anchor pressed into the jersey's side lacks without moving the blade,
# and leaves a held hand where it is.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _body := SkaterHoldModel.Body.new()
var _report := SkaterHoldModel.Report.new()


func before_each() -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(_skater, puck, gs)
	controller.set_process(false)
	controller.set_physics_process(false)
	_skater._process(DT)
	controller._ik.fill_hold_body(_body)


# A carry a body holds: the top hand in front of its hip, the blade a stick away
# ahead of it across the body.
func _carry_pose() -> Array[Vector3]:
	var top: Vector3 = _body.shoulders[0]
	var hand := Vector3(top.x * 0.6, top.y - 0.35, -0.35)
	var blade := Vector3(-top.x * 3.3, -0.95, -1.2)
	blade = hand + (blade - hand).normalized() * 1.4
	return [hand, blade]


# That carry's hand swung round the same blade into the front of the chest.
func _pressed() -> Array[Vector3]:
	var pose: Array[Vector3] = _carry_pose()
	var top: Vector3 = _body.shoulders[0]
	var length: float = pose[0].distance_to(pose[1])
	var into := Vector3(top.x * 0.2, top.y - 0.3, -0.12)
	return [pose[1] + (into - pose[1]).normalized() * length, pose[1]]


# The shaft's rise off the ice from `blade` to `hand`, radians.
func _lie(hand: Vector3, blade: Vector3) -> float:
	return asin((hand.y - blade.y) / hand.distance_to(blade))


func test_a_fist_in_the_chest_reads_by_how_far_it_is_in() -> void:
	var pose: Array[Vector3] = _carry_pose()
	var shallow := Vector3(0.0, _body.shoulders[0].y - 0.3, -0.17)
	var deep := Vector3(0.0, _body.shoulders[0].y - 0.3, -0.05)
	SkaterHoldModel.evaluate(_body, shallow, pose[1], _report)
	var in_shallow: float = _report.fist
	SkaterHoldModel.evaluate(_body, deep, pose[1], _report)
	assert_gt(in_shallow, 0.0, "a fist on the chest's surface is past contact")
	assert_almost_eq(_report.fist - in_shallow, 0.12, 0.02,
			"and 12 cm deeper in reads 12 cm further past")


func test_the_score_is_a_function_of_its_inputs() -> void:
	var pose: Array[Vector3] = _carry_pose()
	var hand: Vector3 = pose[0] + Vector3(0.2, 0.0, 0.3)
	SkaterHoldModel.evaluate(_body, hand, pose[1], _report)
	var first: float = _report.total()
	SkaterHoldModel.evaluate(_body, pose[0], pose[1], _report)
	SkaterHoldModel.evaluate(_body, hand, pose[1], _report)
	assert_eq(_report.total(), first)


func test_the_search_finds_a_held_hand_round_the_same_blade() -> void:
	var pose: Array[Vector3] = _pressed()
	var length: float = pose[0].distance_to(pose[1])
	SkaterHoldModel.evaluate(_body, pose[0], pose[1], _report)
	assert_gt(_report.total(), 0.01, "the pressed hand is not held")
	var search := SkaterHoldModel.Search.new()
	SkaterHoldModel.search(_body, pose[0], pose[1], SkaterHoldModel.Report.new(), search)
	assert_true(search.held_found, "a held hand is on the sphere")
	assert_almost_eq(search.held_hand.distance_to(pose[1]), length, 0.0005,
			"a stick's length from the same blade")
	SkaterHoldModel.evaluate(_body, search.held_hand, pose[1], _report)
	assert_lt(_report.total(), SkaterHoldModel.HELD_M)


func test_the_search_leaves_a_held_hand_where_it_is() -> void:
	var pose: Array[Vector3] = _carry_pose()
	var search := SkaterHoldModel.Search.new()
	var scratch := SkaterHoldModel.Report.new()
	SkaterHoldModel.search(_body, pose[0], pose[1], scratch, search)
	assert_true(search.held_found, "the case has a held hand")
	var held: Vector3 = search.held_hand
	SkaterHoldModel.search(_body, held, pose[1], scratch, search)
	assert_eq(search.held_hand, held)


func test_the_projection_leaves_a_held_hand_where_it_is() -> void:
	var pose: Array[Vector3] = _carry_pose()
	var search := SkaterHoldModel.Search.new()
	SkaterHoldModel.search(_body, pose[0], pose[1], SkaterHoldModel.Report.new(), search)
	var held: Vector3 = search.held_hand
	assert_almost_eq(SkaterHoldModel.project(_body, held, pose[1], _lie(held, pose[1]), _report)
			.distance_to(held), 0.0, 0.00001)


func test_the_projection_holds_the_pressed_hand_on_the_same_sphere() -> void:
	var pose: Array[Vector3] = _pressed()
	var length: float = pose[0].distance_to(pose[1])
	var hand: Vector3 = SkaterHoldModel.project(_body, pose[0], pose[1], _lie(pose[0], pose[1]),
			_report)
	assert_almost_eq(hand.distance_to(pose[1]), length, 0.0005, "a stick's length from the blade")
	var lie0: float = asin((pose[0].y - pose[1].y) / length)
	var lie: float = asin((hand.y - pose[1].y) / length)
	assert_lt(absf(lie - lie0), deg_to_rad(SkaterHoldModel.PROJECT_LIE_DEG) + 0.001,
			"its lie within the window")
	SkaterHoldModel.evaluate(_body, hand, pose[1], _report)
	assert_lt(_report.total(), 0.005, "held, to within 5 mm (binding %s)" % _report.binding())
	var search := SkaterHoldModel.Search.new()
	SkaterHoldModel.search(_body, pose[0], pose[1], SkaterHoldModel.Report.new(), search)
	assert_lt(hand.distance_to(pose[0]), search.held_hand.distance_to(pose[0]) * 1.5 + 0.02,
			"moved about as far as the nearest held hand lies")


func test_the_projection_moves_with_the_anchor_without_a_jump() -> void:
	# The anchor swung from the held carry in to the pressed one, a millimetre a
	# step: the held hand never moves more than a few times what the anchor did.
	var from: Vector3 = _carry_pose()[0]
	var to: Vector3 = _pressed()[0]
	var blade: Vector3 = _carry_pose()[1]
	var length: float = from.distance_to(blade)
	var steps: int = int(from.distance_to(to) / 0.001)
	var lie: float = _lie(from, blade)
	var prev: Vector3 = SkaterHoldModel.project(_body, from, blade, lie, _report)
	var worst: float = 0.0
	for i: int in range(1, steps + 1):
		var anchor: Vector3 = blade + (from.lerp(to, float(i) / steps) - blade).normalized() * length
		var hand: Vector3 = SkaterHoldModel.project(_body, anchor, blade, lie, _report)
		worst = maxf(worst, hand.distance_to(prev))
		prev = hand
	assert_lt(worst, 0.005, "the held hand's largest step for 1 mm of anchor")


func test_a_stick_stood_past_its_lie_is_laid_back_into_the_window() -> void:
	# The carry's blade with the hand stood up over it, the shaft at 80°.
	var blade: Vector3 = _carry_pose()[1]
	var length: float = _carry_pose()[0].distance_to(blade)
	var up: Vector3 = blade + Vector3(0.0, sin(deg_to_rad(80.0)), cos(deg_to_rad(80.0))) * length
	var lie: float = deg_to_rad(43.0)
	var hand: Vector3 = SkaterHoldModel.project(_body, up, blade, lie, _report)
	assert_lt(_lie(hand, blade), lie + deg_to_rad(SkaterHoldModel.PROJECT_LIE_DEG) + 0.001)
	assert_almost_eq(hand.distance_to(blade), length, 0.0005)


func test_the_height_rule_brings_a_hand_under_the_chest() -> void:
	var pose: Array[Vector3] = _carry_pose()
	var top: Vector3 = _body.shoulders[0]
	var length: float = pose[0].distance_to(pose[1])
	# The carry's hand raised round its blade to 0.1 m under the shoulder.
	var dir: Vector3 = pose[0] - pose[1]
	var rise: float = top.y - 0.1 - pose[1].y
	var flat := Vector2(dir.x, dir.z).normalized() * sqrt(length * length - rise * rise)
	var high: Vector3 = pose[1] + Vector3(flat.x, rise, flat.y)
	_body.hand_below_shoulder = SkaterHoldModel.HAND_BELOW_SHOULDER_M
	SkaterHoldModel.evaluate(_body, high, pose[1], _report)
	assert_almost_eq(_report.high, 0.1, 0.002, "the raised hand is 10 cm past the rule")
	var hand: Vector3 = SkaterHoldModel.project(_body, high, pose[1], deg_to_rad(43.0), _report)
	assert_lt(hand.y, top.y - SkaterHoldModel.HAND_BELOW_SHOULDER_M + 0.003)

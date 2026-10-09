extends GutTest

# The pickup snap and the goal line. A stick reached into the cage through the
# mouth, a puck lying beside the post outside the side twine, a pickup between
# them: that snap scored, from a puck that never went near the mouth.
#
# Two things had to be true for it, and this runs the real tick order to hold
# both shut:
#   - the goal tracker runs before Puck pins, so it must sample a carried puck at
#     its pin (GoalCrossingTracker.advance → Puck.pinned_position), never at
#     global_position, which on the pickup tick is still the loose spot;
#   - the carried pin's net collision must sweep from where the puck was picked
#     up (Puck.picked_up_from), so a pin can't start on the far side of the twine.
# Pickup itself refuses to reach through the net (test_net_reach_occlusion.gd);
# the cases here grant it anyway, the way a lag-comp claim judged on a rewound
# view can, so this file holds the backstop on its own.
#
# The tick order mirrors the live one: SkaterController (−1), GameManager
# (autoload, 0 — goal check, then deferred claims), Skater (0), Puck (+1), then
# PuckController's present-time pickup (+1, after Puck).

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0
const G: float = GameRules.GOAL_LINE_Z

enum Grant { PRESENT_TIME, LAG_COMP }


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _c: SkaterController
var _puck: Puck
var _tracker: GoalCrossingTracker
var _goals: int = 0


func before_each() -> void:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_c = SkaterController.new()
	add_child_autofree(_c)
	_c.setup(skater, _puck, gs)
	_tracker = GoalCrossingTracker.new()
	_goals = 0


func _tick(cursor: Vector3, grant: Grant = Grant.PRESENT_TIME, pickup: bool = false) -> void:
	var sk: Skater = _c.skater
	sk.capture_prev_blade_contact()
	var input := InputState.new()
	input.delta = DT
	input.mouse_world_pos = cursor
	_c._process_input(input, DT)
	if _tracker.advance(_puck) and GoalDetectionRules.crossed_into_net(
			_tracker.segment_start, _tracker.segment_end, G, 1.0,
			GameRules.NET_HALF_WIDTH, GameRules.NET_HEIGHT, GameRules.NET_POST_RADIUS,
			GameRules.PUCK_COLLISION_RADIUS, GameRules.PUCK_COLLISION_HALF_HEIGHT,
			GameRules.NET_DEPTH):
		_goals += 1
	if pickup and grant == Grant.LAG_COMP:
		_grant()
	sk._physics_process(DT)
	if _puck.carrier != null:
		_puck.global_position = _puck.pinned_position()
	if pickup and grant == Grant.PRESENT_TIME:
		_grant()


func _grant() -> void:
	_puck.set_carrier(_c.skater)
	_c.on_puck_picked_up_network()


# Stand in front of the crease and sweep the stick into the cage through the
# mouth, to `cursor`; returns the blade's resting contact.
func _reach_in(skater_at: Vector3, cursor: Vector3) -> Vector3:
	var sk: Skater = _c.skater
	sk.global_position = skater_at
	sk.velocity = Vector3.ZERO
	sk.set_facing(Vector2(0.0, 1.0))
	_c._ik.reset_blade_smoothing()
	var park := skater_at + Vector3(0.0, 0.0, 0.3)
	for i: int in 5:
		_tick(park)
	sk.reseed_blade_history()
	for i: int in 40:
		_tick(park.lerp(cursor, minf(1.0, float(i) / 30.0)))
	return sk.get_blade_contact_global()


func _in_cage(p: Vector3) -> bool:
	return GoalDetectionRules.center_inside_net(p, G, 1.0, GameRules.NET_HALF_WIDTH,
			GameRules.NET_HEIGHT, GameRules.NET_POST_RADIUS, GameRules.PUCK_COLLISION_RADIUS,
			GameRules.PUCK_COLLISION_HALF_HEIGHT, GameRules.NET_DEPTH)


func _across_the_side_twine(grant: Grant) -> void:
	var cursor := Vector3(0.8, 0.0, G + 0.15)
	var blade: Vector3 = _reach_in(Vector3(-0.6, 0.0, G - 0.7), cursor)
	assert_true(_in_cage(blade), "precondition: the stick is in the cage — %s" % blade)
	_puck.global_position = Vector3(1.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, G + 0.02)
	_tracker.reset()
	_tick(cursor)
	_tick(cursor, grant, true)
	for i: int in 30:
		_tick(cursor)
		assert_false(_in_cage(_puck.global_position),
				"tick %d: the pin crossed the twine to %s" % [i, _puck.global_position])
	assert_eq(_goals, 0, "a puck picked up beside the post is not a goal")


func test_present_time_pickup_across_the_twine_never_scores() -> void:
	_across_the_side_twine(Grant.PRESENT_TIME)


func test_lag_comp_pickup_across_the_twine_never_scores() -> void:
	_across_the_side_twine(Grant.LAG_COMP)


func test_a_puck_pulled_through_the_mouth_onto_a_stick_in_the_net_scores() -> void:
	# The snap is part of the puck's path. From in front of the mouth to a blade
	# already in the cage, that path is through the opening — a goal, not a puck
	# left sitting un-scored in the net.
	var cursor := Vector3(0.2, 0.0, G + 0.3)
	var blade: Vector3 = _reach_in(Vector3(0.0, 0.0, G - 1.1), cursor)
	assert_true(_in_cage(blade), "precondition: the stick is in the cage — %s" % blade)
	_puck.global_position = Vector3(0.2, GameRules.PUCK_COLLISION_HALF_HEIGHT, G - 0.12)
	_tracker.reset()
	_tick(cursor)
	_tick(cursor, Grant.PRESENT_TIME, true)
	for i: int in 5:
		_tick(cursor)
	assert_eq(_goals, 1, "scored once, on the snap")


func test_carried_puck_is_sampled_at_its_pin() -> void:
	_puck.global_position = Vector3(5.0, 0.0175, 5.0)
	_puck.set_carrier(_c.skater)
	_tracker.advance(_puck)
	assert_true(_tracker.advance(_puck))
	assert_eq(_tracker.segment_end, _puck.pinned_position(),
			"the carried sample is the pin, not the stale global_position")

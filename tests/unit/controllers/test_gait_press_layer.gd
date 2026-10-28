extends GutTest

# The press reads (GaitPressLayer) from replicated state: touching another body,
# the one committed and skating into him leans into him and sets a lunge; the one
# braking sits deeper than his stance and leans back into the push. Skating away
# from him, or nobody touching, is no press.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION

var _skater: Skater = null
var _other: Skater = null
var _controller: SkaterController = null
var _coord: SkaterSkatingCoordinator = null


func before_each() -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_physics_process(false)
	_skater.set_process(false)
	_other = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_other)
	_other.set_physics_process(false)
	_other.set_process(false)
	_controller = SkaterController.new()
	autofree(_controller)
	_coord = SkaterSkatingCoordinator.new()
	_coord.setup(_skater, SkaterStateMachine.new(), _controller)
	_skater.set_facing(Vector2(0.0, -1.0))
	var both: Array = [_skater, _other]
	_skater.set_skater_collision_provider(func() -> Array: return both)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)


# The other body touching ours, `along` (unit XZ) from us, or far off.
func _place_other(along: Vector3, touching: bool = true) -> void:
	var gap: float = _skater.collision_radius() + _other.collision_radius()
	_other.global_position = _skater.global_position + along * (gap if touching else gap + 3.0)


func _settle() -> void:
	for _i: int in 90:
		_coord.apply(DT)


func test_a_driver_leans_into_the_man() -> void:
	_skater.hit_committed = true
	_skater.move_intent = Vector2(0.0, -1.0)
	_place_other(Vector3(0.0, 0.0, -1.0), false)
	_settle()
	var committed_only: float = _coord.trunk_pitch_add
	_place_other(Vector3(0.0, 0.0, -1.0))
	_settle()
	assert_eq(_coord._press._role, GaitPressLayer.Role.DRIVE)
	assert_lt(_coord.trunk_pitch_add, committed_only - deg_to_rad(_controller.press_drive_lean_deg) * 0.9,
			"folded forward into the man by the drive's lean")


func test_skating_away_is_no_press() -> void:
	_skater.hit_committed = true
	_skater.move_intent = Vector2(0.0, 1.0)
	_place_other(Vector3(0.0, 0.0, -1.0))
	_settle()
	assert_true(_coord._press.is_quiet())


func test_dug_in_he_sits_deeper_and_leans_back_into_the_push() -> void:
	_controller.stance_active = true
	_skater.brake_intent = true
	_place_other(Vector3(0.0, 0.0, 1.0), false)
	_settle()
	var stance_drop: float = _coord.crouch_drop
	var stance_pitch: float = _coord.trunk_pitch_add
	_place_other(Vector3(0.0, 0.0, 1.0))
	_settle()
	assert_eq(_coord._press._role, GaitPressLayer.Role.ANCHOR)
	assert_gt(_coord.crouch_drop, stance_drop, "sat deeper than the stance")
	assert_gt(_coord.trunk_pitch_add, stance_pitch + deg_to_rad(_controller.press_anchor_lean_deg) * 0.9,
			"leaning back toward the man pushing him")

extends GutTest

# How a skater looks at a given speed comes from his body (height, through leg
# length), never from his skating stats: two skaters of one body on different
# skates, at the same speed, stride and lean identically.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const SPEED_M_S: float = 7.0


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return false

	func is_movement_locked() -> bool:
		return false


var _controller: SkaterController


func before_each() -> void:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var puck: Puck = (preload("res://Scenes/Puck.tscn").instantiate()) as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(skater, puck, gs)


# The gait's speed fraction and the settled posture lean, skating straight
# ahead at SPEED_M_S on `attrs`.
func _picture(attrs: PlayerAttributes) -> Vector2:
	_controller.apply_attributes(attrs)
	var skater: Skater = _controller.skater
	skater.velocity = -skater.global_transform.basis.z * SPEED_M_S
	var loco: SkaterLocomotion = _controller._skating._locomotion
	loco.sense(1.0 / 60.0, false, 0.0)
	for _i: int in 600:
		_controller._pose.apply_velocity_lean(1.0 / 120.0)
	return Vector2(loco._speed_t, _controller._pose.velocity_lean_x)


func test_skates_do_not_change_the_picture() -> void:
	var power: Vector2 = _picture(PlayerAttributes.new(73, 201, PlayerAttributes.PROFILE_POWER))
	var agility: Vector2 = _picture(PlayerAttributes.new(73, 201, PlayerAttributes.PROFILE_AGILITY))
	assert_ne(PlayerAttributes.new(73, 201, PlayerAttributes.PROFILE_POWER).top_speed_mult(),
			PlayerAttributes.new(73, 201, PlayerAttributes.PROFILE_AGILITY).top_speed_mult(),
			"the two builds really do skate at different top speeds")
	assert_almost_eq(power.x, agility.x, 1e-6, "same stride at the same speed")
	assert_almost_eq(power.y, agility.y, 1e-6, "same posture lean at the same speed")


func test_longer_legs_stride_easier_at_the_same_speed() -> void:
	var short: Vector2 = _picture(PlayerAttributes.new(67, 0))
	var tall: Vector2 = _picture(PlayerAttributes.new(80, 0))
	assert_lt(tall.x, short.x, "a tall skater is further from full pace at the same speed")


func test_neutral_reads_its_top_speed_as_full_pace() -> void:
	_controller.apply_attributes(PlayerAttributes.neutral())
	assert_almost_eq(_controller.gait_full_speed * _controller._skating.leg_scale,
			_controller.max_speed, 1e-4, "the neutral build renders exactly as before")

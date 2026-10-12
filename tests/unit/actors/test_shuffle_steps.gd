extends GutTest

# The brake's shuffle, measured on the live rig: a side-stepping blade points
# along the facing, so its edge grips across the travel and it cannot glide.
# Whichever skate is down has to hold its place on the ice while the body moves
# over it, at any shuffle speed; the cadence is what makes that so
# (SkaterLocomotion._shuffle_rate).

const DT: float = 1.0 / 120.0
const LegBone = SkaterMeshBuilder.LegBone
const SETTLE_TICKS: int = 120
const MEASURE_TICKS: int = 120
# A boot this close to its lowest point over the window is on the ice, metres.
const DOWN_BAND_M: float = 0.008


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 20.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))


func _step(input: InputState, stick: Vector2) -> void:
	input.move_vector = stick
	input.brake = true
	input.mouse_world_pos = _skater.global_position + Vector3(0.0, 0.0, -6.0)
	input.mouse_world_pos.y = 0.0
	input.delta = DT
	_controller._process_input(input, DT)
	_skater.global_position += _skater.velocity * DT
	_skater._process(DT)


func _boot(left: bool) -> Vector3:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	return (_skater.mesh_root.transform * body.transform * body.get_bone_global_pose(
			SkaterBodySkeleton.LEG_BONE_OFFSET + (LegBone.FOOT_L if left else LegBone.FOOT_R))).origin


# Mean sideways speed over the ice of each skate while it is down, against the
# body's own, for a shuffle to the right at `stick`.
func _planted_slip(stick: Vector2) -> Vector2:
	var input := InputState.new()
	for _i: int in SETTLE_TICKS:
		_step(input, stick)
	var local: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var world: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var body_speed: float = 0.0
	for _i: int in MEASURE_TICKS:
		_step(input, stick)
		body_speed += _skater.velocity.x / MEASURE_TICKS
		for k: int in 2:
			var boot: Vector3 = _boot(k == 0)
			local[k].append(boot)
			world[k].append(_skater.global_transform * boot)
	var slip := Vector2.ZERO
	for k: int in 2:
		var lowest: float = INF
		for p: Vector3 in local[k]:
			lowest = minf(lowest, p.y)
		var travel: float = 0.0
		var ticks: int = 0
		for i: int in range(1, MEASURE_TICKS):
			if local[k][i].y < lowest + DOWN_BAND_M and local[k][i - 1].y < lowest + DOWN_BAND_M:
				travel += absf(world[k][i].x - world[k][i - 1].x)
				ticks += 1
		assert_gt(ticks, MEASURE_TICKS / 4, "skate %d spends a share of the cycle down" % k)
		slip[k] = travel / maxf(ticks * DT, DT) / maxf(body_speed, 0.001)
	gut.p("shuffle at %.2f m/s: planted skates slide at %.0f%% / %.0f%% of it"
			% [body_speed, slip.x * 100.0, slip.y * 100.0])
	return slip


func test_a_planted_skate_holds_the_ice_at_the_top_shuffle_speed() -> void:
	var slip: Vector2 = _planted_slip(Vector2(1.0, 0.0))
	assert_lt(maxf(slip.x, slip.y), 0.15)


func test_a_planted_skate_holds_the_ice_at_a_half_stick_shuffle() -> void:
	var slip: Vector2 = _planted_slip(Vector2(0.5, 0.0))
	assert_lt(maxf(slip.x, slip.y), 0.15)

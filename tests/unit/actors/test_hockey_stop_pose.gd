extends GutTest

# The hockey stop, measured on the live rig: both skates planted wide along the
# line of travel, both turned across it, both on the edges that dig in (the
# boot's bottom toward the travel, its top leaning back against it), and the
# second-foot plant left with little to correct because the pose put both blades
# on the ice itself. The joint-space stop it replaced measured 0.37 m apart,
# 29° off across, the back skate at −24° (on the edge that catches) and a 0.70
# rad plant correction.

const DT: float = 1.0 / 120.0
const LegBone = SkaterMeshBuilder.LegBone
const WARMUP_TICKS: int = 300
# Measured over the settled stop: a quarter second in until the speed runs down.
const SETTLE_TICKS: int = 30
const MEASURE_TICKS: int = 40


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


func _step(input: InputState, stopping: bool) -> void:
	input.move_vector = Vector2.ZERO if stopping else Vector2(0.0, -1.0)
	input.brake = stopping
	input.mouse_world_pos = _skater.global_position + Vector3(0.0, 0.0, -6.0)
	input.mouse_world_pos.y = 0.0
	input.delta = DT
	_controller._process_input(input, DT)
	_skater.global_position += _skater.velocity * DT
	_skater._process(DT)


# A boot's pose in the skater's own frame.
func _boot(left: bool) -> Transform3D:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	return _skater.mesh_root.transform * body.transform * body.get_bone_global_pose(
			SkaterBodySkeleton.LEG_BONE_OFFSET + (LegBone.FOOT_L if left else LegBone.FOOT_R))


func test_the_stop_plants_both_skates_wide_across_travel_on_digging_edges() -> void:
	var input := InputState.new()
	for _i: int in WARMUP_TICKS:
		_step(input, false)
	for _i: int in SETTLE_TICKS:
		_step(input, true)
	var spread: float = INF
	var across: float = 0.0
	var edge: float = INF
	var correction: float = 0.0
	for _i: int in MEASURE_TICKS:
		_step(input, true)
		var v := Vector3(_skater.velocity.x, 0.0, _skater.velocity.z)
		var travel: Vector3 = (_skater.global_transform.basis.inverse() * v).normalized()
		var l: Transform3D = _boot(true)
		var r: Transform3D = _boot(false)
		spread = minf(spread, absf((l.origin - r.origin).dot(travel)))
		for boot: Transform3D in [l, r]:
			# The FOOT frame: the toe is −Y, the runner's bottom +Z.
			var length: Vector3 = (boot.basis * Vector3.DOWN).normalized()
			var down: Vector3 = (boot.basis * Vector3.BACK).normalized()
			across = maxf(across, absf(length.dot(travel)))
			# Positive: the bottom tips toward the travel, the top leans back.
			edge = minf(edge, rad_to_deg(asin(clampf(down.dot(travel), -1.0, 1.0))))
		var legs: SkaterLegRig = _skater._legs
		correction = maxf(correction, maxf(absf(legs._plant_eased[0]), absf(legs._plant_eased[1])))
	gut.p("stop: skates %.2f m apart along travel, blades within %.0f° of across it, edges %.0f°+, plant correction %.2f rad"
			% [spread, rad_to_deg(asin(across)), edge, correction])
	assert_gt(spread, 0.32, "planted wide along the line of travel")
	assert_lt(across, sin(deg_to_rad(15.0)), "both blades turned across the travel")
	assert_gt(edge, 5.0, "both blades on the edges that dig in, never the ones that catch")
	assert_lt(correction, 0.25, "the pose put both blades on the ice; the plant only trims")


# The skid — the stick pulled back against travel at speed — is a snowplow: the
# skates out wide of the hips, the legs splayed so both blades sit on their
# inside edges against the travel.
func test_the_skid_is_a_snowplow_on_both_inside_edges() -> void:
	var input := InputState.new()
	for _i: int in WARMUP_TICKS:
		_step(input, false)
	var widest: float = 0.0
	var inside: float = INF
	var skid: float = 0.0
	for _i: int in 24:
		input.move_vector = Vector2(0.0, 1.0)
		input.brake = false
		input.mouse_world_pos = _skater.global_position + Vector3(0.0, 0.0, -6.0)
		input.mouse_world_pos.y = 0.0
		input.delta = DT
		_controller._process_input(input, DT)
		_skater.global_position += _skater.velocity * DT
		_skater._process(DT)
		var m: LocomotionRules.Mix = _controller._skating.locomotion_mix()
		if m.skid < 0.6:
			continue
		skid = maxf(skid, m.skid)
		var l: Transform3D = _boot(true)
		var r: Transform3D = _boot(false)
		widest = maxf(widest, absf(l.origin.x - r.origin.x))
		for boot: Transform3D in [l, r]:
			# Positive: the boot's bottom tips out past it, the top in: its inside edge.
			var down: Vector3 = (boot.basis * Vector3.BACK).normalized()
			inside = minf(inside, rad_to_deg(asin(clampf(down.x * signf(boot.origin.x), -1.0, 1.0))))
	gut.p("skid %.2f: skates %.2f m apart, inside edges %.0f°+" % [skid, widest, inside])
	assert_gt(skid, 0.6, "pulling back at speed skids")
	assert_gt(widest, 0.40, "the skates go out wide")
	assert_gt(inside, 5.0, "both blades on their inside edges")

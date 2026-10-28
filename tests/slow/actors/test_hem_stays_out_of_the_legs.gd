extends GutTest

# The jersey's tail (SkaterHemFlaps) across a skated run through the real
# controller — a start, a stride at speed, a crouch on the move, a hard stop, a
# deep crouch at a standstill and a turn — measured every frame against the
# thighs and pants as the legs are posed that frame (SkaterHemColliders.depth).
# A rigid tail went up to 7 cm inside the legs on this run; the drape's whole
# job is that nothing of it does — nothing loose, that is: a tucked column is
# inside the pants by design. Seconds of skating the real controller, so slow.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# The solver keeps its points a fabric margin outside; this is what is left of
# it once the legs have moved on within the frame.
const CLIP_M: float = 0.004

# [ticks, input]: move, aim (relative to the skater), stance, brake.
const RUN: Array = [
	[60, {"aim": Vector3(0.0, 0.0, -3.0)}],
	[200, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
	[40, {"move": Vector2(0.0, -1.0), "stance": true, "aim": Vector3(0.0, 0.0, -3.0)}],
	[80, {"brake": true, "aim": Vector3(0.0, 0.0, -3.0)}],
	[80, {"stance": true, "aim": Vector3(0.0, 0.0, -3.0)}],
	[120, {"move": Vector2(1.0, -0.2), "aim": Vector3(3.0, 0.0, 0.5)}],
]


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func is_faceoff_prep() -> bool:
		return false


var _cull_was: bool = true


func before_all() -> void:
	_cull_was = SkaterCameraCull.enabled
	SkaterCameraCull.enabled = false


func after_all() -> void:
	SkaterCameraCull.enabled = _cull_was


func _worst_clip(tuck: int, colliding: bool = true) -> float:
	var state := StubGameState.new()
	add_child_autofree(state)
	var puck: Puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.set_process(false)
	var skater: Skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	skater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var gear := GearStyleConfig.new()
	gear.jersey_tuck = tuck
	skater.set_gear_style(gear)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, state)
	controller.apply_attributes(PlayerAttributes.neutral())
	var rig: Skeleton3D = skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var flaps: SkaterHemFlaps = skater._arms._hem
	if not colliding:
		flaps.colliding_iterations = 0
		flaps.configure_native()
	var probe := SkaterHemColliders.new()
	var input := InputState.new()
	var worst: float = 0.0
	for step: Array in RUN:
		var spec: Dictionary = step[1]
		for t: int in int(step[0]):
			input.delta = DT
			input.host_timestamp += DT
			input.move_vector = spec.get("move", Vector2.ZERO)
			input.mouse_world_pos = skater.global_position + (spec["aim"] as Vector3)
			input.stance_held = spec.get("stance", false)
			input.brake = spec.get("brake", false)
			controller._process_input(input, DT)
			skater._physics_process(DT)
			skater._process(DT)
			probe.update(rig)
			var points: PackedVector3Array = flaps.hem_points()
			for i: int in points.size():
				if _loose(flaps, i):
					worst = maxf(worst, probe.depth(points[i]))
	return worst


# Whether hem_points' sample `i` is loose cloth: its column untucked, and for a
# sample toward the next column (the last two), that one too — a facet with a
# tucked edge runs into the pants by design.
func _loose(flaps: SkaterHemFlaps, i: int) -> bool:
	var k: int = floori(float(i) / SkaterHemFlaps.POINTS_PER_COLUMN)
	if flaps.tuck_share[k] > 0.0:
		return false
	return i % SkaterHemFlaps.POINTS_PER_COLUMN < 4 \
			or flaps.tuck_share[(k + 1) % flaps.columns] == 0.0


func test_the_loose_tail_never_goes_inside_the_legs() -> void:
	assert_lt(_worst_clip(GearModelRegistry.TUCK_NONE), CLIP_M)


func test_a_corner_tuck_never_goes_inside_the_legs() -> void:
	assert_lt(_worst_clip(GearModelRegistry.TUCK_RIGHT), CLIP_M)


# The run has teeth: the same drape that never collides goes well inside the
# legs on it.
func test_without_its_collisions_the_tail_clips_on_this_run() -> void:
	assert_gt(_worst_clip(GearModelRegistry.TUCK_NONE, false), 0.02)

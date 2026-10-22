extends GutTest

# The cross-check draws the shaft in to the chest, not through it: through the
# wind-up and the push the drawn shaft stays out of the sweater above the waist,
# measured against the torso's own lathe rings on the live rig, for small,
# neutral and big builds, stood and skating, from a stick at rest in both hands
# and from a one-handed reach at a loose puck. And it does come in to it.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0
const REST_TICKS: int = 120
# _TORSO_PROFILE's waist ring: the chest is the sweater above it.
const _WAIST_STATION: int = 4
# The load's closest approach: a wind-up, not a stick held off at arm's length.
const LOAD_REACHES_M: float = 0.10


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


# How far `p` (the torso bone's mesh space) lies inside the ring polygon at its
# height, in mesh units; negative outside, -INF off the chest (collar to waist).
func _depth_inside(p: Vector3) -> float:
	for station: int in _WAIST_STATION:
		var hi: PackedVector3Array = SkaterMeshBuilder.torso_ring(station, GearModelRegistry.TUCK_NONE)
		var lo: PackedVector3Array = SkaterMeshBuilder.torso_ring(station + 1, GearModelRegistry.TUCK_NONE)
		if p.y > hi[0].y or p.y < lo[0].y:
			continue
		var t: float = (hi[0].y - p.y) / maxf(hi[0].y - lo[0].y, 1e-6)
		var centre := Vector2.ZERO
		var ring := PackedVector2Array()
		for k: int in hi.size() - 1:
			var v: Vector3 = hi[k].lerp(lo[k], t)
			ring.append(Vector2(v.x, v.z))
			centre += Vector2(v.x, v.z)
		centre /= float(ring.size())
		var q := Vector2(p.x, p.z)
		var depth: float = INF
		for k: int in ring.size():
			var a: Vector2 = ring[k]
			var b: Vector2 = ring[(k + 1) % ring.size()]
			var n: Vector2 = (b - a).orthogonal().normalized()
			if n.dot(a - centre) < 0.0:
				n = -n
			depth = minf(depth, n.dot(a - q))
		return depth
	return -INF


# The deepest the drawn shaft's surface goes into the chest, metres.
func _shaft_depth(skater: Skater) -> float:
	var skel: Skeleton3D = skater._arms._skeleton
	var torso: Transform3D = skel.global_transform \
			* skel.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TORSO)
	var to_torso: Transform3D = torso.affine_inverse()
	var girth: float = torso.basis.get_scale().x
	var shaft: Transform3D = skater.upper_body.global_transform * skater.stick_mesh.transform
	var radius: float = skater.stick_mesh.mesh.get_aabb().size.x * 0.5
	var worst: float = -INF
	for k: int in 41:
		var p: Vector3 = to_torso * (shaft * Vector3(0.0, 0.0, k / 40.0 - 0.5))
		worst = maxf(worst, _depth_inside(p) * girth + radius)
	return worst


func _deepest(attrs: PlayerAttributes, move: Vector2, puck_at: Vector3) -> float:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = puck_at
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, gs)
	controller.apply_attributes(attrs)
	var input := InputState.new()
	var throw_ticks: int = ceili(CrossCheckRules.THROW_S / DT) + 1
	var worst: float = -INF
	for i: int in REST_TICKS + throw_ticks:
		input.delta = DT
		input.host_timestamp += DT
		input.move_vector = move
		input.mouse_world_pos = skater.global_position + Vector3(0.0, 0.0, -3.0)
		input.hit_held = i >= REST_TICKS
		input.stick_check_pressed = i == REST_TICKS
		controller._process_input(input, DT)
		skater._physics_process(DT)
		skater._process(DT)
		if skater.cross_check_phase == CrossCheckRules.Phase.THROW:
			worst = maxf(worst, _shaft_depth(skater))
	return worst


func test_the_shaft_stays_out_of_the_chest() -> void:
	for build: Vector2i in [Vector2i(66, 160), Vector2i(72, 195), Vector2i(78, 240)]:
		var attrs := PlayerAttributes.new(build.x, build.y, 1, 1, 1, 1)
		for move: Vector2 in [Vector2.ZERO, Vector2(0.0, -1.0)]:
			for puck_at: Vector3 in [Vector3(30.0, 0.0, 30.0), Vector3.ZERO]:
				var depth: float = _deepest(attrs, move, puck_at)
				var label: String = "%d in, %d lb, %s, puck %s" % [build.x, build.y,
						"skating" if move != Vector2.ZERO else "stood", puck_at]
				assert_lt(depth, 0.0, "%s: %.1f cm into the chest" % [label, depth * 100.0])
				assert_gt(depth, -LOAD_REACHES_M, "%s: the load comes in to the chest" % label)

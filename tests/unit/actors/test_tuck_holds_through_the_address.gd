extends GutTest

# The pants' top under the jersey at the centre's faceoff address, the deepest
# fold in play (GaitFaceoffLayer): the body skinned on the CPU in the WAIST's
# frame, the pants' waistband rings measured against the jersey over them. A
# tuck stands its rim proud of the jersey going in behind it, so standing is the
# reference: the fold must bring no part of the rim further out through the
# jersey than standing does. Before the waistband held the tucked jersey above
# it (SkaterJerseyHem.tucked_hang) a full tuck's rim stood 6 cm out through the
# back of the address, a corner tuck's 3 cm.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# The pants' rings from the belt up, bind space (SkaterConnectedPants._PANTS).
const WAISTBAND_FROM_M: float = 0.075
# What a ring standing inside the jersey may come out to before it shows.
const TOUCH_M: float = 0.002
# Under a loose jersey the rim is drawn in out of sight; the fold over the dot
# must leave it this far under the cloth.
const LOOSE_CLEAR_M: float = 0.005


class StubGameState extends Node:
	var faceoff_prep: bool = true

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return faceoff_prep

	func is_faceoff_prep() -> bool:
		return faceoff_prep


var _cull_was: bool = true


func before_all() -> void:
	_cull_was = SkaterCameraCull.enabled
	SkaterCameraCull.enabled = false


func after_all() -> void:
	SkaterCameraCull.enabled = _cull_was


func _skater(tuck: int, center: bool, prep: bool) -> Skater:
	var state := StubGameState.new()
	state.faceoff_prep = prep
	add_child_autofree(state)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.set_process(false)
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	skater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_physics_process(false)
	skater.set_process(false)
	skater.is_faceoff_center = center
	var gear := GearStyleConfig.new()
	gear.jersey_tuck = tuck
	skater.set_gear_style(gear)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.set_physics_process(false)
	c.set_process(false)
	c.setup(skater, puck, state)
	c.apply_attributes(PlayerAttributes.new())
	var target := Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	var input := InputState.new()
	input.delta = DT
	input.mouse_world_pos = Vector3(0.0, 0.0, -c.faceoff_center_distance())
	if prep:
		c.begin_approach(target + Vector3(-1.5, 0.0, 7.0), target, Vector2(0.0, -1.0), 1.0)
	for _i: int in 240:
		input.host_timestamp += DT
		if prep:
			if not c.tick_faceoff_approach(DT):
				skater.velocity = Vector3.ZERO
				c.apply_blade_aim_only(input, DT)
		else:
			c._process_input(input, DT)
		skater._physics_process(DT)
		skater._process(DT)
	return skater


# Every skin vertex as posed, in the WAIST bone's frame.
func _posed(skater: Skater, tuck: int) -> PackedVector3Array:
	var body: Skeleton3D = skater._arms._skeleton
	var a: Array = SkaterConnectedMesh.shared_mesh(tuck).surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var skin: Skin = SkaterConnectedMesh.shared_skin()
	var xforms: Array[Transform3D] = []
	for i: int in skin.get_bind_count():
		xforms.append(body.get_bone_global_pose(skin.get_bind_bone(i)) * skin.get_bind_pose(i))
	var waist: Transform3D = body.get_bone_global_pose(SkaterBodySkeleton.WAIST_BONE).affine_inverse()
	var out := PackedVector3Array()
	out.resize(verts.size())
	for v: int in verts.size():
		var p := Vector3.ZERO
		for j: int in 4:
			var w: float = weights[v * 4 + j]
			if w > 0.0:
				p += xforms[bones[v * 4 + j]] * verts[v] * w
		out[v] = waist * p
	return out


# How far the pants' waistband stands out through the jersey, by rest vertex:
# its distance off the waist's axis less the outermost jersey face a level ray
# from the axis through it meets (negative: under the jersey).
func _rim_through(tuck: int, center: bool, prep: bool) -> Dictionary:
	var skater: Skater = _skater(tuck, center, prep)
	var a: Array = SkaterConnectedMesh.shared_mesh(tuck).surface_get_arrays(0)
	var rest: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var posed: PackedVector3Array = _posed(skater, tuck)
	var torso: int = SkaterConnectedMesh.zone(SkaterMeshBuilder.UpperSurface.TORSO)
	var pelvis_zone: int = SkaterConnectedMesh.zone(SkaterMeshBuilder.UpperSurface.PELVIS)
	var res: Dictionary = {}
	for v: int in rest.size():
		var z: int = roundi(zones[v].x)
		if z == torso or z == pelvis_zone or rest[v].y < WAISTBAND_FROM_M \
				or bones[v * 4] != SkaterConnectedMesh.Bind.PELVIS or weights[v * 4] < 0.999:
			continue
		var p: Vector3 = posed[v]
		var from := Vector3(0.0, p.y, 0.0)
		var dir := Vector3(p.x, 0.0, p.z).normalized()
		var out: float = -INF
		for t: int in range(0, rest.size(), 3):
			if roundi(zones[t].x) != torso:
				continue
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir,
					posed[t], posed[t + 1], posed[t + 2])
			if hit != null:
				out = maxf(out, ((hit as Vector3) - from).length())
		if out == -INF:
			continue
		res[rest[v]] = Vector2(p.x, p.z).length() - out
	return res


# Rest vertices where the address brings the rim further out than standing.
func _pushed_out(tuck: int) -> Array[String]:
	var stand: Dictionary = _rim_through(tuck, false, false)
	var address: Dictionary = _rim_through(tuck, true, true)
	var out: Array[String] = []
	for key: Vector3 in address:
		if stand.has(key) and maxf(address[key], 0.0) > maxf(stand[key], 0.0) + TOUCH_M:
			out.append("%.3v: %.3f standing, %.3f at the address" % [key, stand[key], address[key]])
	return out


func test_a_full_tuck_holds_its_rim_under_the_jersey_over_the_dot() -> void:
	var out: Array[String] = _pushed_out(GearModelRegistry.TUCK_FULL)
	assert_eq(out.size(), 0, "\n".join(out))


func test_a_corner_tuck_holds_its_rim_under_the_jersey_over_the_dot() -> void:
	var out: Array[String] = _pushed_out(GearModelRegistry.TUCK_RIGHT)
	assert_eq(out.size(), 0, "\n".join(out))


func test_a_loose_jersey_keeps_the_waistband_out_of_sight_over_the_dot() -> void:
	var address: Dictionary = _rim_through(GearModelRegistry.TUCK_NONE, true, true)
	assert_gt(address.size(), 0)
	var worst: float = -INF
	for key: Vector3 in address:
		worst = maxf(worst, address[key])
	assert_lt(worst, -LOOSE_CLEAR_M)

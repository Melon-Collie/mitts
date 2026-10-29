extends GutTest

# The jersey's tuck on the body's skin (SkaterConnectedMesh): a tuck is which
# shared mesh the skater wears, the two corners are one tuck worn on either side,
# and changing it keeps the paint.

const _SCENE: String = "res://Scenes/Skater.tscn"


# A tuck's jersey vertices, bind space.
func _jersey(tuck: int) -> PackedVector3Array:
	var arrays: Array = SkaterConnectedMesh.shared_mesh(tuck).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zone_of: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var torso: int = SkaterConnectedMesh.zone(SkaterMeshBuilder.UpperSurface.TORSO)
	var out := PackedVector3Array()
	for v: int in verts.size():
		if roundi(zone_of[v].x) == torso:
			out.append(verts[v])
	return out


func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 1e4), roundi(v.y * 1e4), roundi(v.z * 1e4))


func test_the_left_and_right_tucks_mirror() -> void:
	var left: Dictionary = {}
	for v: Vector3 in _jersey(GearModelRegistry.TUCK_LEFT):
		left[_key(v)] = true
	var right: PackedVector3Array = _jersey(GearModelRegistry.TUCK_RIGHT)
	assert_gt(right.size(), 0)
	var unmatched: int = 0
	for v: Vector3 in right:
		if not left.has(_key(Vector3(-v.x, v.y, v.z))):
			unmatched += 1
	assert_eq(unmatched, 0, "every vertex of the right tuck's jersey has its mirror in the left's")


func test_every_tuck_is_its_own_mesh() -> void:
	var meshes: Dictionary = {}
	for tuck: int in [GearModelRegistry.TUCK_NONE, GearModelRegistry.TUCK_FULL,
			GearModelRegistry.TUCK_LEFT, GearModelRegistry.TUCK_RIGHT]:
		meshes[SkaterConnectedMesh.shared_mesh(tuck)] = true
	assert_eq(meshes.size(), 4)


# The tuck is which shared mesh the skater's body wears, and changing it keeps
# the paint: the body material on its one surface, and the jersey's record.
func test_a_gear_change_dresses_the_tuck_and_keeps_the_paint() -> void:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	skater.set_uniform(TeamColorRegistry.get_colors(0, 0))
	var body_mesh: MeshInstance3D = skater.mesh_root.find_child("Body", true, false) \
			as MeshInstance3D
	assert_not_null(body_mesh)
	assert_eq(body_mesh.mesh, SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_NONE))
	var body: Material = body_mesh.get_surface_override_material(0)
	assert_not_null(body)
	var jersey: StandardMaterial3D = skater.upper_surface_material(
			SkaterMeshBuilder.UpperSurface.TORSO)
	var gear := GearStyleConfig.new()
	gear.jersey_tuck = GearModelRegistry.TUCK_FULL
	skater.set_gear_style(gear)
	assert_eq(body_mesh.mesh, SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_FULL))
	assert_eq(body_mesh.get_surface_override_material(0), body, "the body material stays on")
	assert_eq(skater.upper_surface_material(SkaterMeshBuilder.UpperSurface.TORSO), jersey,
			"the jersey's paint stays on")

extends GutTest

# A quad of the body's skin is one facet (ConnectedSkinBuilder): both its halves
# carry the quad's normal and the corner kinds the shader lights it by, so its
# split never shows. Held here on the builder, on the body mesh it is merged
# into, and on the two sleeves, which must split as each other's mirror.

const _CHANNELS: int = ConnectedSkinBuilder.FACET_CHANNELS


# A quad of four fresh vertices in order round it, `inside` under it.
func _one_quad(corners: Array[Vector3]) -> Array:
	var b := ConnectedSkinBuilder.new()
	var ids := PackedInt32Array()
	for p: Vector3 in corners:
		ids.append(b.vertex(p, [0], [1.0]))
	b.quad(ids[0], ids[1], ids[2], ids[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
			Vector2.ZERO, 0, Vector3(0.5, -1.0, 0.5))
	return b.commit().surface_get_arrays(0)


# The positions both triangles of a two-triangle list share: its split.
func _split_of(verts: PackedVector3Array) -> Array[Vector3]:
	var shared: Array[Vector3] = []
	for i: int in 3:
		for j: int in range(3, 6):
			if verts[i].is_equal_approx(verts[j]):
				shared.append(verts[i])
	return shared


func test_a_quads_halves_carry_one_normal_and_its_corner_kinds() -> void:
	var arrays: Array = _one_quad([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1),
			Vector3(0, 0, 1)])
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var facets: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	assert_eq(verts.size(), 6)
	assert_eq(facets.size(), 6 * _CHANNELS)
	var split: Array[Vector3] = _split_of(verts)
	assert_eq(split.size(), 2, "the halves share the split's two ends")
	for v: int in 6:
		# A stored normal is packed to 16 bits a component.
		assert_almost_eq(normals[v], Vector3.UP, Vector3.ONE * 1e-3)
		assert_eq(facets[v * _CHANNELS + 2], 1.0, "corner %d is a quad's" % v)
		var first_end: bool = verts[v].is_equal_approx(split[0])
		var second_end: bool = verts[v].is_equal_approx(split[1])
		# One end of the split reads (1, 0) in both halves and the other (0, 1),
		# which is what lets the shader find the split's middle from either.
		assert_eq(facets[v * _CHANNELS] + facets[v * _CHANNELS + 1],
				1.0 if first_end or second_end else 0.0, "corner %d" % v)
		if second_end:
			assert_eq(facets[v * _CHANNELS], facets[_corner_at(verts, split[1]) * _CHANNELS],
					"an end reads the same in both halves")


func _corner_at(verts: PackedVector3Array, p: Vector3) -> int:
	for v: int in verts.size():
		if verts[v].is_equal_approx(p):
			return v
	return -1


func test_a_lone_triangle_is_no_facet() -> void:
	var b := ConnectedSkinBuilder.new()
	var ids := PackedInt32Array()
	for p: Vector3 in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		ids.append(b.vertex(p, [0], [1.0]))
	b.tri(ids[0], ids[1], ids[2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0, Vector3(0, -1, 0))
	var facets: PackedFloat32Array = b.commit().surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	for f: float in facets:
		assert_eq(f, 0.0)


func test_a_bent_quad_splits_along_its_proud_diagonal_either_way_round() -> void:
	# b and d stand up off a and c: the ridge runs b–d, whichever corner the quad
	# is handed in from.
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, 0.2, 0)
	var c := Vector3(1, 0, 1)
	var d := Vector3(0, 0.2, 1)
	for corners: Array[Vector3] in [[a, b, c, d] as Array[Vector3], [b, c, d, a] as Array[Vector3],
			[d, c, b, a] as Array[Vector3]]:
		var verts: PackedVector3Array = _one_quad(corners)[Mesh.ARRAY_VERTEX]
		var split: Array[Vector3] = _split_of(verts)
		assert_eq(split.size(), 2)
		for p: Vector3 in split:
			assert_almost_eq(p.y, 0.2, 1e-6, "the split is the raised diagonal")


func test_facet_pairs_makes_a_quad_of_two_triangles_that_share_an_edge() -> void:
	var verts := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0.3, 1),
		Vector3(0, 0, 0), Vector3(1, 0.3, 1), Vector3(0, 0, 1),
		# A pair with no edge in common stays two triangles.
		Vector3(5, 0, 0), Vector3(6, 0, 0), Vector3(6, 0, 1),
		Vector3(8, 0, 0), Vector3(9, 0, 0), Vector3(9, 0, 1),
	])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var facets: PackedFloat32Array = ConnectedSkinBuilder.facet_pairs(verts, normals, 2)
	assert_eq(facets.size(), verts.size() * _CHANNELS)
	for v: int in 6:
		assert_eq(facets[v * _CHANNELS + 2], 1.0)
		assert_almost_eq(normals[v], normals[0], Vector3.ONE * 1e-6, "one normal over the pair")
	assert_eq(facets[0], facets[3 * _CHANNELS], "the shared corner reads the same in both")
	assert_eq(facets[2 * _CHANNELS + 1], facets[4 * _CHANNELS + 1])
	assert_eq(facets[0] + facets[1], 1.0)
	assert_eq(facets[1 * _CHANNELS] + facets[1 * _CHANNELS + 1], 0.0, "the corner off the split")
	for v: int in range(6, 12):
		assert_eq(facets[v * _CHANNELS + 2], 0.0)


func test_the_body_mesh_keeps_the_skins_facets_and_the_helmets() -> void:
	var skin: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE) \
			.surface_get_arrays(0)
	var body: Array = SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_NONE).surface_get_arrays(0)
	var skin_facets: PackedFloat32Array = skin[Mesh.ARRAY_CUSTOM0]
	var body_facets: PackedFloat32Array = body[Mesh.ARRAY_CUSTOM0]
	var body_verts: PackedVector3Array = body[Mesh.ARRAY_VERTEX]
	assert_eq(body_facets.size(), body_verts.size() * _CHANNELS)
	assert_eq(body_facets.slice(0, skin_facets.size()), skin_facets,
			"the skin's corners come first, as it laid them")
	var zones: PackedVector2Array = body[Mesh.ARRAY_TEX_UV2]
	var shell: int = SkaterMeshBuilder.UPPER_ZONE_BASE + SkaterMeshBuilder.UpperSurface.HELMET_SHELL
	var shell_quads: int = 0
	var other_rigid: int = 0
	@warning_ignore("integer_division")
	for v: int in range(skin_facets.size() / _CHANNELS, body_verts.size()):
		if body_facets[v * _CHANNELS + 2] > 0.5:
			if int(round(zones[v].x)) == shell:
				shell_quads += 1
			else:
				other_rigid += 1
	assert_gt(shell_quads, 0, "the helmet's shell is lit a quad at a time")
	assert_eq(other_rigid, 0, "no other rigid part claims a facet")


# A zone's quads, x mirrored by `mirror`: each its four corners, sorted, and for
# one bent past `_BENT_RAD` the two ends of its split as well. A flat quad is
# the same surface split either way, so its split is left out.
const _BENT_RAD: float = deg_to_rad(1.0)


func _zone_quads(arrays: Array, zone: int, mirror: float) -> Array[String]:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var facets: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var out: Array[String] = []
	var t: int = 0
	while t < verts.size():
		if facets[t * _CHANNELS + 2] < 0.5:
			t += 3
			continue
		if int(round(zones[t].x)) == zone:
			var corners: Array[String] = []
			var split: Array[String] = []
			for c: int in 6:
				var p: Vector3 = verts[t + c] * Vector3(mirror, 1.0, 1.0)
				var key: String = "%.4f,%.4f,%.4f" % [p.x, p.y, p.z]
				if not corners.has(key):
					corners.append(key)
				var on_split: bool = facets[(t + c) * _CHANNELS] \
						+ facets[(t + c) * _CHANNELS + 1] > 0.5
				if on_split and not split.has(key):
					split.append(key)
			corners.sort()
			split.sort()
			var n1: Vector3 = (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t])
			var n2: Vector3 = (verts[t + 5] - verts[t + 3]).cross(verts[t + 4] - verts[t + 3])
			var bent: bool = n1.angle_to(n2) > _BENT_RAD
			out.append("|".join(corners) + (" split " + "|".join(split) if bent else ""))
		t += 6
	out.sort()
	return out


func test_the_sleeves_split_as_each_others_mirror() -> void:
	var arrays: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE) \
			.surface_get_arrays(0)
	var left: Array[String] = _zone_quads(arrays,
			SkaterConnectedMesh.zone(SkaterConnectedMesh.sleeve_surface(-1.0)), -1.0)
	var right: Array[String] = _zone_quads(arrays,
			SkaterConnectedMesh.zone(SkaterConnectedMesh.sleeve_surface(1.0)), 1.0)
	assert_gt(left.size(), 0)
	var bent: int = 0
	for quad: String in left:
		if quad.contains(" split "):
			bent += 1
	assert_gt(bent, 0, "the sleeve has quads out of plane to hold")
	assert_eq(left, right, "the left sleeve's quads are the right's, mirrored, split alike")

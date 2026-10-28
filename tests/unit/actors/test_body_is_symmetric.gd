extends GutTest

# The body is built symmetric, left for right, and flat-shaded, so a facet the
# two sides cut into triangles differently shows: a quad that is not flat
# creases along whichever diagonal cuts it. Every triangle mirrored across the
# body's middle has to be a triangle of the mesh, or lie flat in the plane of
# one it shares an edge with (a flat quad, cut either way, looks the same).

const UpperSurface = SkaterMeshBuilder.UpperSurface
# Mirror pairs: [surface, its mirror's surface] in the upper skin, at rest.
const _PAIRS: Array = [
	[UpperSurface.TORSO, UpperSurface.TORSO],
	[UpperSurface.SHOULDER_L, UpperSurface.SHOULDER_R],
	[UpperSurface.TOP_UPPER_ARM, UpperSurface.BOTTOM_UPPER_ARM],
	[UpperSurface.TOP_ELBOW, UpperSurface.BOTTOM_ELBOW],
	[UpperSurface.TOP_FOREARM, UpperSurface.BOTTOM_FOREARM],
]
# How far off a twin's plane a mirrored corner may sit and still read as flat.
const _FLAT_M: float = 1e-4


func test_the_upper_body_is_cut_alike_left_and_right() -> void:
	var mesh: ArrayMesh = SkaterMeshBuilder.shared_upper_skin_mesh()
	for pair: Array in _PAIRS:
		var odd: int = _unmatched(mesh.surface_get_arrays(pair[0])[Mesh.ARRAY_VERTEX],
				mesh.surface_get_arrays(pair[1])[Mesh.ARRAY_VERTEX])
		assert_eq(odd, 0, "upper surface %d: %d triangles cut unlike their mirror"
				% [pair[0], odd])


func test_the_torso_and_pants_are_cut_alike_left_and_right() -> void:
	for tuck: int in [GearModelRegistry.TUCK_NONE, GearModelRegistry.TUCK_FULL]:
		for mesh: ArrayMesh in [SkaterMeshBuilder.shared_torso(tuck),
				SkaterMeshBuilder.shared_pelvis(tuck)]:
			var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			assert_eq(_unmatched(verts, verts), 0, "tuck %d" % tuck)


# Triangles of `ours` whose mirror is neither a triangle of `theirs` nor flat in
# the plane of one sharing an edge with it.
func _unmatched(ours: PackedVector3Array, theirs: PackedVector3Array) -> int:
	var by_edge: Dictionary = {}
	var whole: Dictionary = {}
	for t: int in range(0, theirs.size(), 3):
		var keys: Array[Vector3i] = [_key(theirs[t]), _key(theirs[t + 1]), _key(theirs[t + 2])]
		var sorted: Array[Vector3i] = keys.duplicate()
		sorted.sort()
		whole[sorted] = true
		for e: int in 3:
			var edge: Array[Vector3i] = [keys[e], keys[(e + 1) % 3]]
			edge.sort()
			if not by_edge.has(edge):
				by_edge[edge] = []
			by_edge[edge].append(t)
	var odd: int = 0
	for t: int in range(0, ours.size(), 3):
		var tri: Array[Vector3] = [_mirror(ours[t]), _mirror(ours[t + 1]), _mirror(ours[t + 2])]
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).length() < 1e-9:
			continue
		var keys: Array[Vector3i] = [_key(tri[0]), _key(tri[1]), _key(tri[2])]
		var sorted: Array[Vector3i] = keys.duplicate()
		sorted.sort()
		if whole.has(sorted) or _flat_beside(tri, keys, by_edge, theirs):
			continue
		odd += 1
	return odd


func _flat_beside(tri: Array[Vector3], keys: Array[Vector3i], by_edge: Dictionary,
		theirs: PackedVector3Array) -> bool:
	for e: int in 3:
		var edge: Array[Vector3i] = [keys[e], keys[(e + 1) % 3]]
		edge.sort()
		for t: int in by_edge.get(edge, []):
			var plane := Plane(theirs[t], theirs[t + 1], theirs[t + 2])
			if absf(plane.distance_to(tri[(e + 2) % 3])) < _FLAT_M:
				return true
	return false


func _mirror(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, p.z)


func _key(p: Vector3) -> Vector3i:
	return Vector3i((p * 10000.0).round())

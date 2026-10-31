extends GutTest

# The skate's upper is one shell (SkateUpperMesh): cuff, heel, quarter and toe
# cap joined edge to edge, the sock going into its cuff and the holder bolted
# under its sole.

const _Surface = SkateUpperMesh.Surface
const _SCENE: String = "res://Scenes/Skater.tscn"
const _SHELL: Array[int] = [_Surface.COLLAR, _Surface.STRIPE, _Surface.QUARTER, _Surface.TOE]


# Every edge of the shell, whichever zone it is painted in, is shared by exactly
# two faces running it opposite ways: closed, consistently wound, no seam open
# between zones.
func test_the_shell_is_closed_across_its_zones() -> void:
	var edges: Dictionary = {}
	for tri: Array in _shell_triangles():
		for e: int in 3:
			var key: String = _edge_key(tri[e], tri[(e + 1) % 3])
			edges[key] = int(edges.get(key, 0)) + 1
	var open: int = 0
	for key: String in edges:
		var back: String = _reverse_key(key)
		if int(edges[key]) != 1 or int(edges.get(back, 0)) != 1:
			open += 1
	assert_eq(open, 0, "every edge has its one opposite twin")


# One piece: every face reaches every other across shared edges.
func test_the_shell_is_one_piece() -> void:
	var tris: Array = _shell_triangles()
	var by_edge: Dictionary = {}
	for t: int in tris.size():
		for e: int in 3:
			var key: String = _undirected_key(tris[t][e], tris[t][(e + 1) % 3])
			if not by_edge.has(key):
				by_edge[key] = []
			(by_edge[key] as Array).append(t)
	var seen: Dictionary = {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var t: int = stack.pop_back()
		for e: int in 3:
			for other: int in by_edge[_undirected_key(tris[t][e], tris[t][(e + 1) % 3])]:
				if not seen.has(other):
					seen[other] = true
					stack.append(other)
	assert_eq(seen.size(), tris.size(), "one connected shell")


func test_the_shell_the_laces_and_the_tongue_are_wound_outward() -> void:
	var shell: float = 0.0
	for tri: Array in _shell_triangles():
		shell += _signed(tri)
	assert_lt(shell, -1e-5, "the shell is an outward-wound solid (negative signed volume)")
	var laces: float = 0.0
	for tri: Array in _triangles(_Surface.LACES):
		laces += _signed(tri)
	assert_lt(laces, -1e-8, "the lace rungs are outward-wound solids")
	var tongue: float = 0.0
	for tri: Array in _triangles(_Surface.TONGUE):
		tongue += _signed(tri)
	assert_lt(tongue, -1e-8, "the tongue is an outward-wound solid")


func test_the_foot_frame_is_the_scenes() -> void:
	var skater: Node = (load(_SCENE) as PackedScene).instantiate()
	for side: String in ["L", "R"]:
		var shin: Node3D = skater.get_node("MeshRoot/LowerBody/Leg%s/Shin%s" % [side, side])
		var skate: Transform3D = (shin.get_node("Skate" + side) as Node3D).transform
		var foot: Transform3D = (shin.get_node("Foot" + side) as Node3D).transform
		var rel: Transform3D = skate.affine_inverse() * foot
		assert_true(rel.is_equal_approx(SkateUpperMesh.SKATE_FROM_FOOT),
				"side %s: %s against %s" % [side, rel, SkateUpperMesh.SKATE_FROM_FOOT])
	skater.free()


# The sock (SkaterConnectedPants) runs down into the cuff and ends inside it: at
# each of its rings below the cuff's top, the cuff's loop clears it all round.
func test_the_sock_goes_into_the_cuff() -> void:
	var skater: Node = (load(_SCENE) as PackedScene).instantiate()
	var leg: Node3D = skater.get_node("MeshRoot/LowerBody/LegL")
	var origin_y: float = leg.position.y + (leg.get_node("ShinL") as Node3D).position.y \
			+ (leg.get_node("ShinL/SkateL") as Node3D).position.y
	skater.free()
	var cuff: Array[PackedVector3Array] = []
	for loop: PackedVector3Array in SkateUpperMesh.loops():
		if absf(loop[0].y - loop[SkateUpperMesh.POINTS / 2].y) < 1e-6:
			cuff.append(loop)
	var checked: int = 0
	for ring: Vector3 in SkaterConnectedPants.leg_stations(true):
		var y: float = ring.x - origin_y
		if y > cuff[0][0].y or y <= cuff[cuff.size() - 1][0].y:
			continue
		var below: int = 0
		while cuff[below + 1][0].y > y:
			below += 1
		var w: float = (cuff[below][0].y - y) / (cuff[below][0].y - cuff[below + 1][0].y)
		var at := PackedVector3Array()
		for k: int in SkateUpperMesh.POINTS:
			at.append(cuff[below][k].lerp(cuff[below + 1][k], w))
		var clear: float = _inradius(at)
		assert_gt(clear, ring.y + 0.004, "the cuff clears the sock's ring at y %.3f" % y)
		checked += 1
	assert_gt(checked, 0, "some of the sock is inside the cuff")


# The holder's towers tuck up into the sole: straight above each end of each
# tower the boot's underside is a little lower than the tower's top.
func test_the_holder_seats_into_the_sole() -> void:
	var holder: PackedVector3Array = SkaterMeshBuilder.shared_skate_blade().surface_get_arrays(
			SkaterMeshBuilder.BLADE_PART_HOLDER)[Mesh.ARRAY_VERTEX]
	var top: float = -INF
	var ends: Array[float] = [INF, -INF]
	var half_w: float = 0.0
	for v: Vector3 in holder:
		var p: Vector3 = SkateUpperMesh.SKATE_FROM_FOOT * v
		top = maxf(top, p.y)
		ends[0] = minf(ends[0], p.z)
		ends[1] = maxf(ends[1], p.z)
		half_w = maxf(half_w, absf(p.x))
	var tris: Array = _shell_triangles()
	for z: float in ends:
		for x: float in [-half_w, half_w]:
			var under: float = _lowest_hit(tris, x, z)
			assert_lt(under, top, "the boot's underside at z %.3f is below the tower's top" % z)
			assert_gt(under, top - 0.012, "and only just, at z %.3f" % z)


# The cuff's rim rides the leg and the sole the foot.
func test_the_ankle_blends_from_the_foot_to_the_leg() -> void:
	var loops: Array[PackedVector3Array] = SkateUpperMesh.loops()
	for p: Vector3 in loops[0]:
		assert_eq(SkateUpperMesh.foot_share(p), 0.0, "the rim is the leg's")
	for loop: PackedVector3Array in loops.slice(SkateUpperMesh.loops().size() - 5):
		assert_eq(SkateUpperMesh.foot_share(loop[SkateUpperMesh.POINTS / 2]), 1.0,
				"the sole is the foot's")


func _shell_triangles() -> Array:
	var out: Array = []
	for s: int in _SHELL:
		out.append_array(_triangles(s))
	return out


func _triangles(surface: int) -> Array:
	var arrays: Array = SkateUpperMesh.shared().surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i: int in verts.size():
			indices.append(i)
	var out: Array = []
	for t: int in range(0, indices.size(), 3):
		var tri: Array[Vector3] = [verts[indices[t]], verts[indices[t + 1]], verts[indices[t + 2]]]
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).length() > 1e-10:
			out.append(tri)
	return out


func _signed(tri: Array) -> float:
	return (tri[0] as Vector3).dot((tri[1] as Vector3).cross(tri[2] as Vector3)) / 6.0


func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 1e5), roundi(p.y * 1e5), roundi(p.z * 1e5)]


func _edge_key(a: Vector3, b: Vector3) -> String:
	return _key(a) + ">" + _key(b)


func _reverse_key(key: String) -> String:
	var parts: PackedStringArray = key.split(">")
	return parts[1] + ">" + parts[0]


func _undirected_key(a: Vector3, b: Vector3) -> String:
	var ka: String = _key(a)
	var kb: String = _key(b)
	return ka + "|" + kb if ka < kb else kb + "|" + ka


# The lowest point where the vertical line through (x, z) meets the shell.
func _lowest_hit(tris: Array, x: float, z: float) -> float:
	var lowest: float = INF
	var at := Vector2(x, z)
	for tri: Array in tris:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var a2 := Vector2(a.x, a.z)
		var e1 := Vector2(b.x, b.z) - a2
		var e2 := Vector2(c.x, c.z) - a2
		var det: float = e1.cross(e2)
		if absf(det) < 1e-12:
			continue
		var u: float = (at - a2).cross(e2) / det
		var v: float = e1.cross(at - a2) / det
		if u >= 0.0 and v >= 0.0 and u + v <= 1.0:
			lowest = minf(lowest, a.y + (b.y - a.y) * u + (c.y - a.y) * v)
	return lowest


# The nearest a level loop's edges come to the leg's axis.
func _inradius(loop: PackedVector3Array) -> float:
	var best: float = INF
	for k: int in loop.size():
		var a := Vector2(loop[k].x, loop[k].z)
		var b := Vector2(loop[(k + 1) % loop.size()].x, loop[(k + 1) % loop.size()].z)
		var t: float = clampf(-a.dot(b - a) / maxf((b - a).length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, (a + (b - a) * t).length())
	return best

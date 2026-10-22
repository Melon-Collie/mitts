extends GutTest

# Lettering is sized in metres and drawn through each decal's texel density,
# which the decals state as the size of the part they wrap: the skater's back
# (JerseyDecal) and cap (ShoulderDecal), the goalie's floater
# (GoalieUniformCoordinator). Nothing else connects those numbers to the
# meshes, so a reshape that moved one would quietly stretch the name, the back
# number or a sleeve number — this measures the meshes and holds them.


# Side rings of a lathe-convention mesh, keyed by V: {v: {u: vertex}}.
func _rings(mesh: ArrayMesh, v_max: float) -> Dictionary:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var rings: Dictionary = {}
	for i: int in verts.size():
		if uvs[i].y > v_max + 0.001:
			continue
		var ring: Dictionary = rings.get_or_add(snappedf(uvs[i].y, 0.0001), {})
		ring[snappedf(uvs[i].x, 0.0001)] = verts[i]
	return rings


func _perimeter(ring: Dictionary) -> float:
	var us: Array = ring.keys()
	us.sort()
	var total: float = 0.0
	for k: int in us.size() - 1:
		var a: Vector3 = ring[us[k]]
		var b: Vector3 = ring[us[k + 1]]
		total += Vector2(b.x - a.x, b.z - a.z).length()
	return total


func test_the_back_is_as_tall_as_the_torso_side() -> void:
	var rings: Dictionary = _rings(SkaterMeshBuilder.shared_torso(), 0.5)
	var ys: Array[float] = []
	for v: float in rings:
		ys.append((rings[v].values()[0] as Vector3).y)
	assert_almost_eq(ys.max() - ys.min(), JerseyDecal.BACK_HEIGHT_M, 0.001)


# Through the name and number — the side's upper three quarters.
func test_the_back_girth_is_the_torso_through_the_lettering() -> void:
	var rings: Dictionary = _rings(SkaterMeshBuilder.shared_torso(), 0.5)
	var sum: float = 0.0
	var count: int = 0
	for v: float in rings:
		if v >= 0.025 and v <= 0.375:
			sum += _perimeter(rings[v])
			count += 1
	assert_gt(count, 1, "the band must cover several rings")
	assert_almost_eq(sum / count, JerseyDecal.BACK_GIRTH_M, JerseyDecal.BACK_GIRTH_M * 0.04)


# The torso turns half a facet so its back is a flat face, and the material's
# offset lands the decal's back-centre column on that face's centre.
func test_the_back_centre_is_a_face_centre() -> void:
	var rings: Dictionary = _rings(SkaterMeshBuilder.shared_torso(), 0.5)
	var ring: Dictionary = rings[rings.keys().min()]
	var behind: Array = []
	for u: float in ring:
		var p: Vector3 = ring[u]
		if p.z > 0.0:
			behind.append([absf(p.x), u, p.x])
	behind.sort()
	var a: Array = behind[0]
	var b: Array = behind[1]
	assert_gt(a[0], 0.01, "no ring vertex sits on the back's centre line")
	assert_almost_eq(float(a[2]), -float(b[2]), 1e-4, "the two nearest straddle it evenly")
	var ua: float = a[1]
	var ub: float = b[1]
	if absf(ua - ub) > 0.5:  # straddling the seam, where U jumps 1 → 0
		if ua < ub:
			ua += 1.0
		else:
			ub += 1.0
	var sampled: float = fposmod((ua + ub) * 0.5 + JerseyDecal.UV_OFFSET_X, 1.0)
	assert_almost_eq(sampled * JerseyDecal.IMG_W, float(JerseyDecal.BACK_CENTER_X), 0.5)


func test_the_cap_girth_is_its_equator() -> void:
	var rings: Dictionary = _rings(SkaterMeshBuilder.shared_shoulder_cap(), 1.0)
	assert_almost_eq(_perimeter(rings[0.5]), ShoulderDecal.CAP_GIRTH_M,
			ShoulderDecal.CAP_GIRTH_M * 0.03)


# Metres of meridian per unit V, through the number band.
func test_the_cap_meridian_matches_its_v_scale() -> void:
	var rings: Dictionary = _rings(SkaterMeshBuilder.shared_shoulder_cap(), 1.0)
	var vs: Array = []
	for v: float in rings:
		if v >= 0.3 and v <= 0.85:
			vs.append(v)
	vs.sort()
	var length: float = 0.0
	for i: int in vs.size() - 1:
		length += (rings[vs[i]][0.0] as Vector3).distance_to(rings[vs[i + 1]][0.0])
	assert_almost_eq(length / (vs.back() - vs.front()), ShoulderDecal.CAP_M_PER_V,
			ShoulderDecal.CAP_M_PER_V * 0.08)


# The goalie's shoulder floater: the shared joint ball scaled by its semi-axes.
func _floater_rings() -> Dictionary:
	var rings: Dictionary = _rings(SkaterMeshBuilder.shared_joint_ball(), 1.0)
	for v: float in rings:
		var ring: Dictionary = rings[v]
		for u: float in ring:
			ring[u] = (ring[u] as Vector3) * GoalieLimbRig.FLOATER_SEMI_AXES
	return rings


func test_the_floater_girth_is_its_equator() -> void:
	assert_almost_eq(_perimeter(_floater_rings()[0.5]), GoalieUniformCoordinator.FLOATER_GIRTH_M,
			GoalieUniformCoordinator.FLOATER_GIRTH_M * 0.03)


# Through the number band, on the outward (+X) meridian the number faces.
func test_the_floater_meridian_matches_its_v_scale() -> void:
	var rings: Dictionary = _floater_rings()
	var outward: float = 0.25
	var length: float = (rings[0.5][outward] as Vector3).distance_to(rings[0.75][outward])
	assert_almost_eq(length / 0.25, GoalieUniformCoordinator.FLOATER_M_PER_V,
			GoalieUniformCoordinator.FLOATER_M_PER_V * 0.03)


# The yoke runs off the body's sides over each floater, so the V the floater's
# yoke ends at must sit at the body's yoke line, measured on the faceted mesh
# (V is linear between its rings, not the sphere's cos⁻¹).
func test_the_floater_yoke_meets_the_body_yoke() -> void:
	var rings: Dictionary = _floater_rings()
	var vs: Array = rings.keys()
	vs.sort()
	var v: float = GoalieUniformCoordinator.floater_yoke_v()
	var height: float = NAN
	for i: int in vs.size() - 1:
		if v >= vs[i] and v <= vs[i + 1]:
			var a: float = (rings[vs[i]][0.0] as Vector3).y
			var b: float = (rings[vs[i + 1]][0.0] as Vector3).y
			height = lerpf(a, b, (v - vs[i]) / (vs[i + 1] - vs[i]))
	var floater_center: float = GoalieAnatomy.SHOULDER_OFFSET.y + GoalieLimbRig.FLOATER_OUTSET.y
	assert_almost_eq(floater_center + height,
			GoalieMeshBuilder.BODY_TOP_Y - GoalieMeshBuilder.YOKE_DEPTH_M, 0.01)


extends GutTest

# Lettering is sized in metres and drawn through each decal's texel density,
# which the decals state as the size of the part they wrap: the skater's back
# (JerseyDecal) and sleeve (SleeveDecal). Nothing else connects those numbers to
# the body's skin (SkaterConnectedMesh), so a reshape that moved one would
# quietly stretch the name, the back number or a sleeve number — this measures
# the skin and holds them.


# The skin's rings in one paint zone, keyed by V: {v: {u: vertex}}, bind space.
func _rings(surface: int, v_max: float) -> Dictionary:
	var arrays: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE) \
			.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var zone_of: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var zone: int = SkaterConnectedMesh.zone(surface)
	var rings: Dictionary = {}
	for i: int in verts.size():
		if roundi(zone_of[i].x) != zone or uvs[i].y > v_max + 0.001:
			continue
		var ring: Dictionary = rings.get_or_add(snappedf(uvs[i].y, 0.0001), {})
		ring[snappedf(uvs[i].x, 0.0001)] = verts[i]
	return rings


# The torso's rings that go all the way round (the armholes cut those beside
# them), keyed by V.
func _torso_rings() -> Dictionary:
	var out: Dictionary = {}
	var rings: Dictionary = _rings(SkaterMeshBuilder.UpperSurface.TORSO, 0.5)
	for v: float in rings:
		if (rings[v] as Dictionary).size() == SkaterConnectedMesh.TAIL_COLUMNS + 1:
			out[v] = rings[v]
	return out


func _perimeter(ring: Dictionary) -> float:
	var us: Array = ring.keys()
	us.sort()
	var total: float = 0.0
	for k: int in us.size() - 1:
		var a: Vector3 = ring[us[k]]
		var b: Vector3 = ring[us[k + 1]]
		total += a.distance_to(b)
	return total


func _name_size() -> int:
	return roundi(JerseyDecal.NAME_EM_M * JerseyDecal.PX_PER_M.y)


func _fitted_width_m(s: String) -> float:
	var fit: Vector2 = JerseyDecal.fit_lettering(JerseyDecal.NAME_FONT, s, _name_size(),
			JerseyDecal.NAME_MAX_WIDTH_M * JerseyDecal.PX_PER_M.y)
	var width: float = JerseyDecal.NAME_FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(fit.x)).x
	return width * fit.y / JerseyDecal.PX_PER_M.y


func test_a_name_that_fits_is_set_as_drawn() -> void:
	var fit: Vector2 = JerseyDecal.fit_lettering(JerseyDecal.NAME_FONT, "LIME", _name_size(),
			JerseyDecal.NAME_MAX_WIDTH_M * JerseyDecal.PX_PER_M.y)
	assert_eq(fit, Vector2(_name_size(), 1.0))


# Every name lands between the shoulders, however long, and is never squeezed
# past the floor.
func test_a_long_name_fits_between_the_shoulders() -> void:
	for s: String in ["POMEGRANATE", "VAN RIEMSDYK", "CHRISTOPHERSON-LAFRENIERE"]:
		var fit: Vector2 = JerseyDecal.fit_lettering(JerseyDecal.NAME_FONT, s, _name_size(),
				JerseyDecal.NAME_MAX_WIDTH_M * JerseyDecal.PX_PER_M.y)
		assert_lte(_fitted_width_m(s), JerseyDecal.NAME_MAX_WIDTH_M + 0.001, s)
		assert_gte(fit.y, JerseyDecal.NAME_MIN_SQUEEZE - 0.001, s + " squeeze")


func test_a_name_only_shrinks_once_squeezing_runs_out() -> void:
	var fit: Vector2 = JerseyDecal.fit_lettering(JerseyDecal.NAME_FONT, "POMEGRANATE",
			_name_size(), JerseyDecal.NAME_MAX_WIDTH_M * JerseyDecal.PX_PER_M.y)
	assert_eq(int(fit.x), _name_size(), "a name a little long keeps its size")
	assert_lt(fit.y, 1.0, "and is set narrower")


# Metres down the back per unit V below the shoulders (the collar is drawn up
# round the neck), over the side's half of the texture: the decal's
# BACK_HEIGHT_M.
func test_the_back_runs_down_its_v_scale() -> void:
	var rings: Dictionary = _torso_rings()
	var vs: Array = rings.keys().filter(func(v: float) -> bool:
		return v >= SkaterMeshBuilder.TORSO_YOKE_SIDE_FRACTION * 0.5)
	vs.sort()
	var top: float = _back(rings[vs.front()]).y
	var bottom: float = _back(rings[vs.back()]).y
	assert_almost_eq((top - bottom) / (vs.back() - vs.front()) * 0.5, JerseyDecal.BACK_HEIGHT_M,
			0.001)


# A ring's point at the back's centre line.
func _back(ring: Dictionary) -> Vector3:
	var best := Vector3(0.0, 0.0, -INF)
	for p: Vector3 in ring.values():
		if p.z > best.z:
			best = p
	return best


# Through the name and number — the side's upper three quarters.
func test_the_back_girth_is_the_torso_through_the_lettering() -> void:
	var rings: Dictionary = _torso_rings()
	var sum: float = 0.0
	var count: int = 0
	for v: float in rings:
		if v >= 0.025 and v <= 0.375:
			sum += _perimeter(rings[v])
			count += 1
	assert_gt(count, 1, "the band must cover several rings")
	assert_almost_eq(sum / count, JerseyDecal.BACK_GIRTH_M, JerseyDecal.BACK_GIRTH_M * 0.04)


# The material's offset lands the decal's back-centre column on the torso's
# back-centre line.
func test_the_back_centre_column_is_on_the_back() -> void:
	var rings: Dictionary = _torso_rings()
	var ring: Dictionary = rings[rings.keys().max()]
	var back := Vector3(0.0, 0.0, -INF)
	var back_u: float = 0.0
	for u: float in ring:
		var p: Vector3 = ring[u]
		if p.z > back.z:
			back = p
			back_u = u
	assert_almost_eq(back.x, 0.0, 1e-4, "a ring vertex sits on the back's centre line")
	var sampled: float = fposmod(back_u + JerseyDecal.UV_OFFSET_X, 1.0)
	assert_almost_eq(sampled * JerseyDecal.IMG_W, float(JerseyDecal.BACK_CENTER_X), 0.5)


# Round the arm where the number goes: the sleeve's first ring off the armhole.
func test_the_sleeve_girth_is_the_arm_under_the_number() -> void:
	for side: float in [-1.0, 1.0]:
		var rings: Dictionary = _rings(SkaterConnectedMesh.sleeve_surface(side), 1.0)
		var first: float = INF
		for v: float in rings:
			if (rings[v] as Dictionary).size() > SkaterConnectedMesh.LIMB_SIDES:
				first = minf(first, v)
		assert_almost_eq(_perimeter(rings[first]), SleevePaint.GIRTH_M,
				SleevePaint.GIRTH_M * 0.05, "side %d" % side)


# Metres down the arm per unit V: the decal's SleevePaint.LENGTH_M, through
# the upper arm.
func test_the_sleeve_runs_down_its_v_scale() -> void:
	for side: float in [-1.0, 1.0]:
		var rings: Dictionary = _rings(SkaterConnectedMesh.sleeve_surface(side), 1.0)
		var vs: Array = []
		for v: float in rings:
			if (rings[v] as Dictionary).size() > SkaterConnectedMesh.LIMB_SIDES \
					and v < SleevePaint.pos_of(SleevePaint.ELBOW_M) - 0.05:
				vs.append(v)
		vs.sort()
		assert_gt(vs.size(), 2)
		var length: float = _centre(rings[vs.front()]).distance_to(_centre(rings[vs.back()]))
		assert_almost_eq(length / (vs.back() - vs.front()), SleevePaint.LENGTH_M,
				SleevePaint.LENGTH_M * 0.05, "side %d" % side)


func _centre(ring: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	for p: Vector3 in ring.values():
		sum += p
	return sum / float(ring.size())

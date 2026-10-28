extends GutTest

# Hair rides between two shells it must not cross: the head under it and the
# helmet and face gear over it. A style tuned to read better pokes through the
# visor or the shell without anything else noticing.

const _CENTRE := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)


func _verts(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _scalps() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for style: int in HairStyleRegistry.hair_count():
		var mesh: ArrayMesh = SkaterHairMesh.shared_hair(style)
		if mesh != null:
			out.append(mesh)
	return out


const _FACES: Array[int] = [GearModelRegistry.FACE_NONE, GearModelRegistry.FACE_VISOR,
	GearModelRegistry.FACE_CAGE, GearModelRegistry.FACE_FISHBOWL]


# Every facial shell, once each: a style may wear a different one under a
# different piece of face gear.
func _facials() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for face: int in _FACES:
		for style: int in HairStyleRegistry.facial_count():
			var mesh: ArrayMesh = SkaterHairMesh.shared_facial_hair(style, face)
			if mesh != null and not out.has(mesh):
				out.append(mesh)
	return out


# How far off the helmet's centre a face piece stands, and the height of its
# lower edge, below which it is open.
func _gear_bound(face: int) -> Vector2:
	match face:
		GearModelRegistry.FACE_VISOR:
			return Vector2(SkaterMeshBuilder._FACE_SHIELD_RADIUS, SkaterMeshBuilder
					._FACE_SHIELD_RADIUS * cos(PI * SkaterMeshBuilder._VISOR_V1))
		GearModelRegistry.FACE_CAGE:
			return Vector2(SkaterMeshBuilder._CAGE_RADIUS,
					SkaterMeshBuilder._CAGE_RADIUS * cos(PI * SkaterMeshBuilder._CAGE_V1))
		_:
			return Vector2(SkaterMeshBuilder._FACE_SHIELD_RADIUS, SkaterMeshBuilder
					._FACE_SHIELD_RADIUS * cos(PI * SkaterMeshBuilder._FISHBOWL_V1))


func test_every_style_but_the_bare_ones_has_geometry() -> void:
	for style: int in HairStyleRegistry.hair_count():
		var mesh: ArrayMesh = SkaterHairMesh.shared_hair(style)
		if style == HairStyleRegistry.HAIR_BALD:
			assert_null(mesh, "bald grows nothing")
		else:
			assert_not_null(mesh, "hair style %d has a shell" % style)
			assert_gt(_verts(mesh).size(), 0)
	for face: int in _FACES:
		for style: int in HairStyleRegistry.facial_count():
			var mesh: ArrayMesh = SkaterHairMesh.shared_facial_hair(style, face)
			if style == HairStyleRegistry.FACIAL_NONE:
				assert_null(mesh, "no facial hair grows nothing")
			else:
				assert_not_null(mesh, "facial style %d has a shell under face %d" % [style, face])
	assert_eq(SkaterHairMesh.shared_hair(HairStyleRegistry.HAIR_LONG),
			SkaterHairMesh.shared_hair(HairStyleRegistry.HAIR_SHAGGY),
			"a retired style is drawn as its stand-in")
	assert_null(SkaterHairMesh.shared_hair(99), "a forged index renders bald")
	assert_null(SkaterHairMesh.shared_facial_hair(-1, GearModelRegistry.FACE_NONE),
			"a forged index renders clean")


# Under the helmet the scalp fills the room between the head and the shell, and
# no further: along the ray from the helmet's centre through any vertex, the
# shell is farther out than the hair.
func test_the_scalp_stays_inside_the_helmet_shell() -> void:
	var shell: PackedVector3Array = SkaterMeshBuilder.helmet_shell_triangles()
	for mesh: ArrayMesh in _scalps():
		var covered: int = 0
		var worst: float = INF
		for v: Vector3 in _verts(mesh):
			var dir: Vector3 = v.normalized()
			var room: float = INF
			for i: int in range(0, shell.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3.ZERO, dir,
						shell[i], shell[i + 1], shell[i + 2])
				if hit != null:
					room = minf(room, (hit as Vector3).length())
			if room == INF:
				continue
			covered += 1
			worst = minf(worst, room - v.length())
		assert_gt(covered, 0, "the scalp carries on under the shell")
		assert_gt(worst, 0.001, "the scalp comes within %.4f m of the shell" % worst)


# The face gear rides a sphere a centimetre or so off the head (the same bound
# test_skater_face_mesh.gd holds the face to), down to its lower edge. Facial
# hair worn under a piece lives inside it above that edge, and may hang out
# past it below; scalp hair only meets it at the sideburns, inside the
# fishbowl's footprint — the widest and deepest of the three pieces.
func test_hair_stays_inside_the_face_gear() -> void:
	for face: int in _FACES.slice(1):
		var bound: Vector2 = _gear_bound(face)
		var worn: Array[ArrayMesh] = [SkaterHairMesh.shared_brows()]
		for style: int in range(1, HairStyleRegistry.facial_count()):
			worn.append(SkaterHairMesh.shared_facial_hair(style, face))
		for mesh: ArrayMesh in worn:
			var worst: float = 0.0
			for v: Vector3 in _verts(mesh):
				if v.y > bound.y:
					worst = maxf(worst, v.length())
			assert_lt(worst, bound.x - 0.001,
					"facial hair under face %d reaches %.4f m from the helmet centre" % [face, worst])
	var gear_r: float = minf(SkaterMeshBuilder._CAGE_RADIUS,
			SkaterMeshBuilder._FACE_SHIELD_RADIUS) - 0.001
	var gear_floor: float = _gear_bound(GearModelRegistry.FACE_FISHBOWL).y
	for mesh: ArrayMesh in _scalps():
		var worst: float = 0.0
		for v: Vector3 in _verts(mesh):
			var off_front: float = absf(wrapf(atan2(v.x, v.z) - PI, -PI, PI))
			if off_front < SkaterMeshBuilder._FISHBOWL_HALF_ARC and v.y > gear_floor:
				worst = maxf(worst, v.length())
		assert_lt(worst, gear_r,
				"a sideburn reaches %.4f m from the helmet centre" % worst)


func test_facial_hair_leaves_the_mouth_bare() -> void:
	var mouth: Vector3 = SkaterFaceMesh._MOUTH   # (y, half width, half height)
	var facials: Array[ArrayMesh] = _facials()
	for i: int in facials.size():
		var covering: int = 0
		for v: Vector3 in _verts(facials[i]):
			if absf(v.x) < mouth.y and absf(v.y - mouth.x) < mouth.z and v.z < 0.0:
				covering += 1
		assert_eq(covering, 0, "facial shell %d keeps off the mouth" % i)


# Where the hair shows it must stand off the skin, or the head shows through it.
# Sampled where each style is fullest: the nape on the scalp, the chin on a beard.
func test_visible_hair_stands_off_the_head() -> void:
	var ball: ArrayMesh = SkaterMeshBuilder.shared_head_ball()
	var head_far: float = 0.0
	for v: Vector3 in _verts(ball):
		# The ball's own mesh is in head-local space, its centre at the origin.
		if v.z > 0.05 and v.y < -0.105:
			head_far = maxf(head_far, v.z)
	for style: int in [HairStyleRegistry.HAIR_SHORT, HairStyleRegistry.HAIR_MEDIUM,
			HairStyleRegistry.HAIR_MULLET,
			HairStyleRegistry.HAIR_SHAGGY]:
		var reach: float = 0.0
		for v: Vector3 in _verts(SkaterHairMesh.shared_hair(style)):
			if absf(v.x) < 0.01 and v.y < -0.105 and v.y > -0.118:
				reach = maxf(reach, v.z - _CENTRE.z)
		assert_gt(reach, head_far, "style %d covers the nape" % style)


# The hair-coloured brows have to cover the face's own skin-tinted ones: over
# every tinted brow vertex there is one of theirs, a hair further out.
func test_the_brows_cover_the_faces_own() -> void:
	var face: ArrayMesh = SkaterFaceMesh.build(SkaterMeshBuilder.HEAD_RADIUS,
			SkaterMeshBuilder.HEAD_LON, SkaterMeshBuilder.HEAD_LAT)
	var face_verts: PackedVector3Array = _verts(face)
	var tints: PackedColorArray = face.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var over: PackedVector3Array = _verts(SkaterHairMesh.shared_brows())
	var tinted: int = 0
	for i: int in face_verts.size():
		if absf(tints[i].r - SkaterFaceMesh.BROW_TINT.r) > 0.01:
			continue
		tinted += 1
		var p: Vector3 = face_verts[i] + _CENTRE   # head-local → helmet-local
		var nearest: float = 1.0
		var nearest_v := Vector3.ZERO
		for v: Vector3 in over:
			if v.distance_to(p) < nearest:
				nearest = v.distance_to(p)
				nearest_v = v
		assert_lt(nearest, 0.003, "a hair-coloured brow lies over tinted vertex %d" % i)
		assert_gt((nearest_v - _CENTRE).length(), (p - _CENTRE).length(),
				"and stands off it")
	assert_gt(tinted, 0, "the face has tinted brows to cover")


func _tris(mesh: ArrayMesh, offset: Vector3) -> PackedVector3Array:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	if arrays[Mesh.ARRAY_INDEX] == null:
		for v: Vector3 in verts:
			out.append(v + offset)
	else:
		for i: int in arrays[Mesh.ARRAY_INDEX]:
			out.append(verts[i] + offset)
	return out


# The ray from the head's centre that meets its sphere at height y.
func _toward(theta: float, y: float) -> Vector3:
	var r: float = SkaterMeshBuilder.HEAD_RADIUS
	var across: float = sqrt(r * r - y * y)
	return Vector3(sin(theta) * across, y, cos(theta) * across).normalized()


# Farthest hit along the ray from the head's centre, or 0 for a miss.
func _reach(tris: PackedVector3Array, dir: Vector3) -> float:
	var best: float = 0.0
	for i: int in range(0, tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(_CENTRE, dir,
				tris[i], tris[i + 1], tris[i + 2])
		if hit != null:
			best = maxf(best, ((hit as Vector3) - _CENTRE).length())
	return best


# Wherever a sheet shows, the skin under it must not: along every ray from the
# head's centre that meets the sheet, the sheet is farther out than the head and
# the face's features. A grid row that spans a facet crease cuts into the ridge
# and fails this as a row of teeth; a chin the beard does not rise over fails it
# as a bare patch.
func test_no_skin_shows_through_the_facial_hair() -> void:
	var skin: PackedVector3Array = _tris(SkaterMeshBuilder.shared_head_ball(), _CENTRE)
	var facials: Array[ArrayMesh] = _facials()
	for style: int in facials.size():
		var sheet: PackedVector3Array = _tris(facials[style], Vector3.ZERO)
		var hits: int = 0
		for i: int in 24:
			for j: int in 12:
				var theta: float = PI + deg_to_rad(lerpf(-58.0, 58.0, float(i) / 23.0))
				var y: float = lerpf(-0.002, -0.125, float(j) / 11.0)
				var dir: Vector3 = _toward(theta, y)
				var hair: float = _reach(sheet, dir)
				if hair == 0.0:
					continue
				hits += 1
				assert_gt(hair, _reach(skin, dir),
						"facial shell %d clears the skin at θ %.2f, y %.3f" % [style, theta, y])
		assert_gt(hits, 4, "facial shell %d was sampled" % style)


# Every style but bald is a whole head of hair, as it would be with the helmet
# off: from the crown down past the rim all round the back and sides.
func test_no_skin_shows_through_the_scalp() -> void:
	var skin: PackedVector3Array = _tris(SkaterMeshBuilder.shared_head_ball(), _CENTRE)
	for style: int in HairStyleRegistry.hair_count():
		var mesh: ArrayMesh = SkaterHairMesh.shared_hair(style)
		if mesh == null:
			continue
		var sheet: PackedVector3Array = _tris(mesh, Vector3.ZERO)
		var hits: int = 0
		for i: int in 24:
			for j: int in 12:
				var theta: float = deg_to_rad(lerpf(-177.3, 177.3, float(i) / 23.0))
				var y: float = lerpf(0.13, -0.02, float(j) / 11.0)
				var below_rim: bool = y < SkaterMeshBuilder.helmet_rim_y(theta) - 0.004
				# The crown all round, and below it the back and sides.
				if y < 0.09 and absf(wrapf(theta, -PI, PI)) > deg_to_rad(110.0):
					continue
				var dir: Vector3 = _toward(theta, y)
				var hair: float = _reach(sheet, dir)
				var head: float = _reach(skin, dir)
				if head == 0.0:
					continue
				hits += 1
				assert_gt(hair, head, "hair style %d covers the skin at θ %.2f, y %.3f%s"
						% [style, theta, y, " (below the rim)" if below_rim else ""])
		assert_gt(hits, 100, "hair style %d was sampled" % style)


func test_stubble_and_a_buzz_are_translucent_and_hair_is_not() -> void:
	var hair: StandardMaterial3D = SkaterHairMesh.make_material(1, false)
	assert_eq(hair.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "hair is opaque")
	assert_eq(hair.cull_mode, BaseMaterial3D.CULL_DISABLED, "hair sheets render two-sided")
	var stubble: StandardMaterial3D = SkaterHairMesh.make_material(1, true)
	assert_eq(stubble.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_almost_eq(stubble.albedo_color.a, SkaterHairMesh.STUBBLE_ALPHA, 0.001)
	assert_true(SkaterHairMesh.is_translucent(HairStyleRegistry.FACIAL_STUBBLE))
	assert_false(SkaterHairMesh.is_translucent(HairStyleRegistry.FACIAL_BEARD))
	assert_true(SkaterHairMesh.is_scalp_translucent(HairStyleRegistry.HAIR_BUZZ))
	assert_false(SkaterHairMesh.is_scalp_translucent(HairStyleRegistry.HAIR_SHORT))

extends GutTest

# The jersey's tail against the pants it hangs over or is tucked into — two
# lathes built apart (SkaterMeshBuilder's torso and pelvis profiles) in two
# frames (the torso's, raised by the scene's torso origin, and the waist's),
# whose agreement nothing else states: loose, the tail covers the hips; tucked,
# it is inside the pants; and a corner tuck is that corner's and no other.

const _SCENE: String = "res://Scenes/Skater.tscn"

var _torso_origin_y: float = 0.0
var _hip_centre: Vector2 = Vector2.ZERO


func before_all() -> void:
	var st: SceneState = (load(_SCENE) as PackedScene).get_state()
	for i: int in st.get_node_count():
		var path: String = "%s/%s" % [st.get_node_path(i, true), st.get_node_name(i)]
		for p: int in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) != "transform":
				continue
			var origin: Vector3 = (st.get_node_property_value(i, p) as Transform3D).origin
			if path == "./MeshRoot/UpperBody/UpperBodyMesh":
				_torso_origin_y = origin.y
			elif path == "./MeshRoot/LowerBody/LegL":
				_hip_centre = Vector2(absf(origin.x), origin.y)


func _verts(tuck: int) -> PackedVector3Array:
	return SkaterMeshBuilder.shared_torso(tuck).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


# A lathe profile's (radius, rear sway) at height `y`, linearly between its
# stations; x < 0 outside its span.
func _ring(profile: Array[Vector2], sway: Array[float], y: float) -> Vector2:
	for i: int in profile.size() - 1:
		var hi: Vector2 = profile[i]
		var lo: Vector2 = profile[i + 1]
		if y <= hi.x and y >= lo.x:
			var t: float = (hi.x - y) / maxf(hi.x - lo.x, 1e-6)
			return Vector2(lerpf(hi.y, lo.y, t), lerpf(sway[i], sway[i + 1], t))
	return Vector2(-1.0, 0.0)


# ── Loose ────────────────────────────────────────────────────────────────────

# The loose tail hangs OVER the pants, so where it shares a height with a thigh's
# hip dome, its side is out past the dome's. A sphere about the hip pivot is the
# one part of the leg that does not move with it, so this holds in every stride.
func test_the_loose_tail_covers_the_hip_domes() -> void:
	var dome_r: float = SkaterMeshBuilder._THIGH_DOME_RADIUS
	var checked: int = 0
	var y: float = SkaterJerseyHem.BELT_Y_M
	while y >= SkaterJerseyHem.HEM_Y_M:
		var dy: float = y + _torso_origin_y - _hip_centre.y
		if absf(dy) < dome_r:
			var side: float = _ring(SkaterMeshBuilder._TORSO_PROFILE,
					SkaterMeshBuilder._TORSO_REAR_SWAY, y).x * SkaterMeshBuilder._TORSO_X_SCALE
			assert_gt(side, _hip_centre.x + sqrt(dome_r * dome_r - dy * dy),
					"at torso y %.3f the hip dome pokes out through the jersey's side" % y)
			checked += 1
		y -= 0.005
	assert_gt(checked, 10, "the tail and the domes must share a real span of height")


# ── Tucked ───────────────────────────────────────────────────────────────────

# All the way in, every ring of the tail from the belt down sits inside the
# pants at its height — at the waistband rim and below it, the rear sway of
# both lathes included. Tail and pants both hang from the waist, so what is
# inside at rest is inside in every pose.
func test_a_full_tuck_is_inside_the_pants() -> void:
	var verts: PackedVector3Array = _verts(GearModelRegistry.TUCK_FULL)
	var rest: PackedVector3Array = _verts(GearModelRegistry.TUCK_NONE)
	var xs: float = SkaterMeshBuilder._TORSO_X_SCALE
	var zs: float = SkaterMeshBuilder._TORSO_Z_SCALE
	var checked: int = 0
	for i: int in verts.size():
		if rest[i].y > SkaterJerseyHem.BELT_Y_M + 1e-5:
			continue
		var v: Vector3 = verts[i]
		var pants: Vector2 = _ring(SkaterMeshBuilder._PELVIS_PROFILE,
				SkaterMeshBuilder._PELVIS_REAR_SWAY, v.y + _torso_origin_y)
		assert_gt(pants.x, 0.0, "a tucked vertex at torso y %.3f is above the pants" % v.y)
		var reach: float = pow(v.x / (pants.x * xs), 2.0) \
				+ pow((v.z - pants.y) / (pants.x * zs), 2.0)
		assert_lt(reach, 1.0, "a tucked vertex at %s pokes out through the pants" % v)
		checked += 1
	assert_gt(checked, 20)


# The pants' top is where a tuck goes in, so it is the ring the belt line
# reaches up to: above the jersey's belt ring, under the ring that goes in under
# a tuck's pad — and the pad, stood up, is over that ring and under the bunch.
func test_the_waistband_is_at_the_belt_line() -> void:
	var top: float = SkaterMeshBuilder._PELVIS_PROFILE[0].x - _torso_origin_y
	assert_gt(top, SkaterJerseyHem.BELT_Y_M)
	assert_lt(top, SkaterJerseyHem.PAD_Y_M)
	var pad: float = top + SkaterJerseyHem.PAD_RISE_M
	assert_gt(pad, SkaterJerseyHem.PAD_Y_M)
	assert_lt(pad, SkaterJerseyHem.BUNCH_Y_M)


# Under a full tuck the jersey goes in under the stood-up pad: its ring at the
# pad's height sits inside the pad there, rear sway included, and the ring
# above it stands out past the pad's rim.
func test_a_full_tuck_goes_in_under_the_pad() -> void:
	var tuck: int = GearModelRegistry.TUCK_FULL
	var pants: PackedVector3Array = SkaterMeshBuilder.shared_pelvis(tuck).surface_get_arrays(
			0)[Mesh.ARRAY_VERTEX]
	var pad_top: float = -INF
	for v: Vector3 in pants:
		pad_top = maxf(pad_top, v.y)
	assert_almost_eq(pad_top, SkaterMeshBuilder._PELVIS_PROFILE[0].x + SkaterJerseyHem.PAD_RISE_M,
			1e-5, "the pad stands the waistband up")
	var pad_r: float = SkaterMeshBuilder._PELVIS_PROFILE[0].y + SkaterJerseyHem.PAD_FLARE_M
	var torso: PackedVector3Array = _verts(tuck)
	var rest: PackedVector3Array = _verts(GearModelRegistry.TUCK_NONE)
	var under: int = 0
	for i: int in torso.size():
		if absf(rest[i].y - SkaterJerseyHem.PAD_Y_M) > 1e-5:
			continue
		var p: Vector3 = torso[i]
		var reach: float = pow(p.x / (pad_r * SkaterMeshBuilder._TORSO_X_SCALE), 2.0) + pow(
				(p.z - SkaterMeshBuilder._PELVIS_REAR_SWAY[0]) / (pad_r * SkaterMeshBuilder._TORSO_Z_SCALE), 2.0)
		assert_lt(reach, 1.0, "the ring under the pad is inside its rim, at %s" % p)
		under += 1
	assert_gt(under, 0)


# A corner tuck tucks its own hip's front: there the hem is lifted to the belt,
# the far front and the whole back still hang to the hem. The wearer's right is
# +X and the front is −Z, the lathe's own frame.
func test_a_corner_tuck_is_its_own_front_corner() -> void:
	var rest: PackedVector3Array = _verts(GearModelRegistry.TUCK_NONE)
	var sway: float = SkaterMeshBuilder._TORSO_REAR_SWAY[SkaterMeshBuilder._TORSO_REAR_SWAY.size() - 1]
	var tucked_hem: float = SkaterJerseyHem.BELT_Y_M \
			+ (SkaterJerseyHem.HEM_Y_M - SkaterJerseyHem.BELT_Y_M) * SkaterJerseyHem.TUCKED_LENGTH_SHARE
	for tuck: int in [GearModelRegistry.TUCK_RIGHT, GearModelRegistry.TUCK_LEFT]:
		var verts: PackedVector3Array = _verts(tuck)
		var side: float = 1.0 if tuck == GearModelRegistry.TUCK_RIGHT else -1.0
		var tucked: int = 0
		for i: int in rest.size():
			if absf(rest[i].y - SkaterJerseyHem.HEM_Y_M) > 1e-5 or absf(rest[i].x) < 1e-4:
				continue
			var x: float = rest[i].x * side
			var z: float = rest[i].z - sway
			if x > 0.1 and z < -0.05:
				assert_gt(verts[i].y, lerpf(SkaterJerseyHem.HEM_Y_M, tucked_hem, 0.75),
						"the tucked corner's hem is lifted to the belt")
				tucked += 1
			elif z > 0.05 or x < -0.15:
				assert_almost_eq(verts[i], rest[i], Vector3.ONE * 1e-5,
						"the back and the far side hang loose")
		assert_gt(tucked, 0, "tuck %d tucks some of its corner" % tuck)


# The two corners are one tuck worn on either side.
func test_the_left_and_right_tucks_mirror() -> void:
	var right: PackedVector3Array = _verts(GearModelRegistry.TUCK_RIGHT)
	var left: Dictionary = {}
	for v: Vector3 in _verts(GearModelRegistry.TUCK_LEFT):
		left[_key(v)] = true
	for v: Vector3 in right:
		assert_true(left.has(_key(Vector3(-v.x, v.y, v.z))),
				"the right tuck's %s has no mirror in the left's" % v)


func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 1e4), roundi(v.y * 1e4), roundi(v.z * 1e4))


# ── Worn ─────────────────────────────────────────────────────────────────────

# The tuck is which shared mesh the skater's upper body wears, and changing it
# keeps the paint, which lives in surface overrides on that mesh's instance.
func test_a_gear_change_dresses_the_tuck_and_keeps_the_paint() -> void:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	skater.set_uniform(TeamColorRegistry.get_colors(0, 0))
	var upper: MeshInstance3D = skater.mesh_root.get_node("BodyRig/UpperMesh") as MeshInstance3D
	assert_eq(upper.mesh, SkaterMeshBuilder.shared_upper_skin_mesh(GearModelRegistry.TUCK_NONE))
	var paint: Material = upper.get_surface_override_material(
			SkaterMeshBuilder.UpperSurface.TORSO)
	assert_not_null(paint)
	var gear := GearStyleConfig.new()
	gear.jersey_tuck = GearModelRegistry.TUCK_FULL
	skater.set_gear_style(gear)
	assert_eq(upper.mesh, SkaterMeshBuilder.shared_upper_skin_mesh(GearModelRegistry.TUCK_FULL))
	assert_eq(upper.get_surface_override_material(SkaterMeshBuilder.UpperSurface.TORSO), paint,
			"the jersey's paint stays on")

extends GutTest

# SkaterMeshBuilder invariants a display-less run can still check. Three
# things break silently if a generator drifts, and each is pinned here:
#
#   1. Winding — Godot front faces are clockwise-from-outside, so an outward-
#      wound closed solid has NEGATIVE signed volume. An inside-out part still
#      "works" headless but renders as a hollow shell in game.
#   2. UV conventions — the parts keep the engine primitive layouts (cylinder
#      side V ∈ [0, 0.5], sphere equirect V ∈ [0, 1], everything inside
#      [0, 1]). A part whose UVs drift out of range wraps its paint somewhere
#      unintended.
#   3. Envelope — each part must stay inside the primitive it replaced (plus
#      millimetres), because ice contact, board clearance, and the gear that
#      overlaps it were all tuned around the primitive silhouettes.
#
# Proportion changes inside those bounds are free — this suite deliberately
# pins none of the shaping.

const _EPS: float = 0.005  # envelope tolerance, metres


class PartSpec:
	var label: String
	var mesh: ArrayMesh
	var max_size: Vector3
	var side_only_v: bool  # lathed part: side V capped at 0.5 (caps use the rest)
	# Which surface of `mesh` carries this piece. A part that splits into
	# separately-paintable pieces (the boot's quarter and toe cap, the blade's
	# holder and runner, the fist's back and fingers) is ONE mesh of several
	# surfaces, and every piece has to hold the winding/UV/envelope contract on
	# its own — a split that leaves a half open is invisible until it renders.
	var surface: int

	func _init(p_label: String, p_mesh: ArrayMesh, p_max: Vector3, p_side: bool,
			p_surface: int = 0) -> void:
		label = p_label
		mesh = p_mesh
		max_size = p_max
		side_only_v = p_side
		surface = p_surface


# Envelopes come from the primitives in Scenes/Skater.tscn: helmet sphere
# r 0.155. The skate's upper has its own test (test_skate_upper.gd).
# The glove's meshes are unit-sized (the bone's scale is the real dimension),
# so their bounds are the nominal unit envelopes.
func _parts() -> Array[PartSpec]:
	return [
		PartSpec.new("helmet", SkaterMeshBuilder._build_helmet(),
				Vector3(0.31, 0.31, 0.31), false),
		PartSpec.new("head", SkaterMeshBuilder._build_ball(
				SkaterMeshBuilder.HEAD_RADIUS, 10, 5, 1.0),
				Vector3(0.27, 0.27, 0.27), false),
		PartSpec.new("neck", SkaterMeshBuilder._build_neck(),
				Vector3(0.19, 0.10, 0.19), true),
		PartSpec.new("blade_holder", SkaterMeshBuilder._build_skate_blade(),
				Vector3(0.023, 0.21, 0.06), false, SkaterMeshBuilder.BLADE_PART_HOLDER),
		PartSpec.new("blade_runner", SkaterMeshBuilder._build_skate_blade(),
				Vector3(0.01, 0.22, 0.04), false, SkaterMeshBuilder.BLADE_PART_RUNNER),
		# Its depth takes the back of the hand's pad, as deep as the fist is wide.
		PartSpec.new("glove_back", SkaterMeshBuilder.shared_glove_fist(),
				Vector3(2.2, 1.0, 2.2), false, SkaterMeshBuilder.FIST_PART_BACK),
		PartSpec.new("glove_fingers", SkaterMeshBuilder.shared_glove_fist(),
				Vector3(2.2, 1.0, 2.0), false, SkaterMeshBuilder.FIST_PART_FINGERS),
		PartSpec.new("glove_thumb", SkaterMeshBuilder.shared_glove_fist(),
				Vector3(0.85, 1.15, 1.35), false, SkaterMeshBuilder.FIST_PART_THUMB),
		PartSpec.new("cuff", SkaterMeshBuilder.shared_cuff(),
				Vector3(2.0, SkaterMeshBuilder.CUFF_HEIGHT_M, 2.0), false),
		PartSpec.new("knob", SkaterMeshBuilder.shared_knob(),
				Vector3(0.07, SkaterMeshBuilder.KNOB_HEIGHT_M, 0.07), true),
	]


func test_every_part_is_wound_outward() -> void:
	for part: PartSpec in _parts():
		var vol: float = _signed_volume(part.mesh, part.surface)
		assert_lt(vol, -1e-7,
				"%s should be a closed outward-wound solid (negative signed volume)"
				% part.label)


func test_every_part_has_unit_flat_normals() -> void:
	# Degenerate pole quads are allowed a zero-area filler triangle; every
	# triangle with real area must carry a unit normal (flat shading gives one
	# normal per face, so a bad one shows as a black facet).
	for part: PartSpec in _parts():
		var arrays: Array = part.mesh.surface_get_arrays(part.surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bad: int = 0
		for i in range(0, verts.size(), 3):
			var area2: float = (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).length()
			if area2 > 1e-9 and absf(normals[i].length() - 1.0) > 0.01:
				bad += 1
		assert_eq(bad, 0, "%s should have unit normals on every real face" % part.label)


func test_uvs_stay_inside_painter_conventions() -> void:
	for part: PartSpec in _parts():
		var arrays: Array = part.mesh.surface_get_arrays(part.surface)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var v_side_max: float = 0.0
		for uv: Vector2 in uvs:
			assert_between(uv.x, 0.0, 1.0, "%s U inside [0, 1]" % part.label)
			assert_between(uv.y, 0.0, 1.0, "%s V inside [0, 1]" % part.label)
			if part.side_only_v and uv.y <= 0.5:
				v_side_max = maxf(v_side_max, uv.y)
		if part.side_only_v:
			# The side band should actually reach (near) the 0.5 boundary —
			# a shrunken V range would squash the stripe bands visibly.
			assert_gt(v_side_max, 0.45,
					"%s side V should span up to ~0.5 like the engine cylinder" % part.label)


func test_every_part_stays_inside_its_primitive_envelope() -> void:
	for part: PartSpec in _parts():
		var size: Vector3 = _surface_bounds(part.mesh, part.surface).size
		for axis in 3:
			assert_lt(size[axis], part.max_size[axis] + _EPS,
					"%s axis %d should stay inside the replaced primitive's envelope"
					% [part.label, axis])


func test_arm_rig_meshes_keep_their_placement_dimensions() -> void:
	# These heights are PLACEMENT inputs, not just looks: the cuff and knob sit
	# offset along their bone by half their baked height (Skater reads the
	# CUFF_HEIGHT_M / KNOB_HEIGHT_M constants). A drifted mesh height slides
	# every cuff off the wrist silently.
	assert_almost_eq(SkaterMeshBuilder.shared_cuff().get_aabb().size.y,
			SkaterMeshBuilder.CUFF_HEIGHT_M, 0.001,
			"cuff mesh height must match CUFF_HEIGHT_M")
	assert_almost_eq(SkaterMeshBuilder.shared_knob().get_aabb().size.y,
			SkaterMeshBuilder.KNOB_HEIGHT_M, 0.001,
			"knob mesh height must match KNOB_HEIGHT_M")


# The torso's clearance query measures the rings the jersey is built on: each
# ring's corners lie on it, its middle is inside, and a corner pushed out along
# its radius clears it by the push.
func test_torso_clearance_measures_the_rest_rings() -> void:
	for station: int in SkaterMeshBuilder.TORSO_HEM_STATION + 1:
		var ring: PackedVector3Array = SkaterMeshBuilder.torso_ring(station)
		var middle := Vector3.ZERO
		for k: int in ring.size() - 1:
			middle += ring[k]
		middle /= float(ring.size() - 1)
		assert_lt(SkaterMeshBuilder.torso_clearance(middle), -0.1,
				"station %d's middle is inside" % station)
		for k: int in ring.size() - 1:
			var corner: Vector3 = ring[k]
			assert_almost_eq(SkaterMeshBuilder.torso_clearance(corner), 0.0, 0.0005,
					"station %d corner %d is on the surface" % [station, k])
			var out: Vector3 = corner - middle
			out.y = 0.0
			assert_almost_eq(SkaterMeshBuilder.torso_clearance(
					corner + out.normalized() * 0.05), 0.05, 0.005,
					"station %d corner %d pushed out 5 cm clears by 5 cm" % [station, k])


func test_helmet_opens_at_the_face() -> void:
	# The helmet shell's rim must sit brow-high at the front (−Z, exposing
	# the head ball's face) and reach lower at the back — the asymmetry that
	# makes it read as a helmet over a head rather than a full ball. Compare
	# the lowest vertex on each half.
	var mesh: ArrayMesh = SkaterMeshBuilder._build_helmet()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var front_min_y: float = INF
	var back_min_y: float = INF
	for v: Vector3 in verts:
		if v.z < -0.05:
			front_min_y = minf(front_min_y, v.y)
		elif v.z > 0.05:
			back_min_y = minf(back_min_y, v.y)
	assert_gt(front_min_y, back_min_y + 0.03,
			"the helmet rim should sit meaningfully higher at the face than the back")


func test_skate_blade_reaches_the_lifted_ice_depth() -> void:
	# The foot node's local +Z is down; the replaced foot sphere bottomed out
	# at z = +0.08 ≈ the ice, and the on-skates stance lifts the body roots by
	# SKATE_LIFT_M with the steel reaching correspondingly deeper. The runner
	# must land exactly there (shallower floats the skate, deeper sinks it).
	var aabb: AABB = SkaterMeshBuilder._build_skate_blade().get_aabb()
	assert_almost_eq(aabb.position.z + aabb.size.z,
			0.08 + SkaterMeshBuilder.SKATE_LIFT_M, 0.002,
			"the steel runner should bottom out at the lifted ice-contact depth")
	# The boot itself must stay well above the ice — the blade carries it.
	var upper: ArrayMesh = SkateUpperMesh.shared()
	var foot_from_skate: Transform3D = SkateUpperMesh.SKATE_FROM_FOOT.affine_inverse()
	var sole: float = -INF
	for s: int in upper.get_surface_count():
		for v: Vector3 in upper.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			sole = maxf(sole, (foot_from_skate * v).z)
	assert_lt(sole, 0.05, "the boot sole should ride on the blade, clear of the ice")


# Face gear is the one open-sheet family (millimetre glazing and cage wire —
# no closed solid to sign-check), so it gets its own contract instead of a
# PartSpec row: bare and forged picks carry no mesh, and every real piece
# stays on the face — inside the shield radius, in the helmet's front half
# (the face is −Z), and below the brow rim so nothing pokes through the shell
# dome. The visor-vs-fishbowl depth split is design intent worth pinning too:
# a visor that reaches the chin IS a fishbowl.
func test_face_gear_pieces_sit_on_the_face() -> void:
	assert_null(SkaterMeshBuilder.shared_face_gear(GearModelRegistry.FACE_NONE),
			"bare carries no mesh")
	assert_null(SkaterMeshBuilder.shared_face_gear(-1), "forged picks carry no mesh")
	assert_null(SkaterMeshBuilder.shared_face_gear(99), "forged picks carry no mesh")
	var brow_y: float = 0.158 * cos(PI * 0.40) + 0.005
	for option: int in [GearModelRegistry.FACE_VISOR, GearModelRegistry.FACE_CAGE,
			GearModelRegistry.FACE_FISHBOWL]:
		var mesh: ArrayMesh = SkaterMeshBuilder.shared_face_gear(option)
		assert_not_null(mesh, "option %d has a mesh" % option)
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_gt(verts.size(), 0, "option %d has geometry" % option)
		for v: Vector3 in verts:
			assert_lt(v.length(), 0.158 + 0.001,
					"option %d stays inside the shield radius" % option)
			assert_lt(v.z, 0.001, "option %d stays on the face half" % option)
			assert_lt(v.y, brow_y, "option %d stays under the brow rim" % option)
	var visor: AABB = _surface_bounds(
			SkaterMeshBuilder.shared_face_gear(GearModelRegistry.FACE_VISOR), 0)
	var bowl: AABB = _surface_bounds(
			SkaterMeshBuilder.shared_face_gear(GearModelRegistry.FACE_FISHBOWL), 0)
	assert_gt(visor.position.y, -0.05, "the visor stops above the mouth")
	assert_lt(bowl.position.y, -0.10, "the fishbowl covers past the chin")


# One surface's own bounds. ArrayMesh.get_aabb() unions every surface, which
# would let a piece drift outside its envelope as long as a sibling covered it.
func _surface_bounds(mesh: ArrayMesh, surface: int) -> AABB:
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var bounds := AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		bounds = bounds.expand(v)
	return bounds


func _signed_volume(mesh: ArrayMesh, surface: int = 0) -> float:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var total: float = 0.0
	for i in range(0, verts.size(), 3):
		total += verts[i].dot(verts[i + 1].cross(verts[i + 2])) / 6.0
	return total


# The rigid parts (SkaterRigidParts) are rigid: every vertex weight 1.0 on one
# bone and nothing on the other three, so a bone pose places its part exactly.
# The skate's upper is the exception: its weight is split between its side's
# SKATE bone and the foot's bind (SKATE_UPPER_FOOT_BIND), summing to 1.0, in
# whichever order the mesh keeps them.
# Cheap to check here, invisible in a render.
func test_the_rigid_parts_are_rigidly_weighted() -> void:
	for rig: Array in [
			["upper", SkaterRigidParts.upper_body_mesh(), SkaterMeshBuilder.UPPER_BONE_COUNT],
			["leg", SkaterRigidParts.leg_body_mesh(), SkaterMeshBuilder.LEG_BONE_COUNT]]:
		var arrays: Array = (rig[1] as ArrayMesh).surface_get_arrays(0)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var verts: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		assert_eq(bones.size(), verts * 4, "%s: four influences per vertex" % rig[0])
		var bad: int = 0
		var bent: int = 0
		for v: int in verts:
			if weights[v * 4 + 2] != 0.0 or weights[v * 4 + 3] != 0.0:
				bad += 1
			elif rig[0] == "leg" and _ankle_weighted(bones, weights, v):
				bent += 1
			elif bones[v * 4] < 0 or bones[v * 4] >= int(rig[2]) \
					or not is_equal_approx(weights[v * 4], 1.0) or weights[v * 4 + 1] != 0.0:
				bad += 1
		assert_eq(bad, 0, "%s: every vertex weight 1.0 on one bone in range" % rig[0])
		if rig[0] == "leg":
			assert_gt(bent, 0, "the skate uppers bend across the ankle")


func _ankle_weighted(bones: PackedInt32Array, weights: PackedFloat32Array, v: int) -> bool:
	for side: int in 2:
		var skate: int = SkaterMeshBuilder.LegBone.SKATE_L if side == 0 \
				else SkaterMeshBuilder.LegBone.SKATE_R
		var foot: int = SkaterRigidParts.SKATE_UPPER_FOOT_BIND + side
		var pair: Array[int] = [bones[v * 4], bones[v * 4 + 1]]
		var named: bool = pair == [skate, foot] or pair == [foot, skate] \
				or (weights[v * 4 + 1] == 0.0 and (pair[0] == skate or pair[0] == foot))
		if named:
			# Stored at 16 bits a weight.
			return absf(weights[v * 4] + weights[v * 4 + 1] - 1.0) < 1e-3
	return false


# The head sits a centimetre or two inside the shell all round; where the rim's
# cut twists a shell quad, a fold the wrong way cuts through the temple.
func test_the_head_stays_inside_the_helmet_shell() -> void:
	var shell: PackedVector3Array = SkaterMeshBuilder.helmet_shell_triangles()
	var ball: PackedVector3Array = SkaterMeshBuilder.shared_head() \
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var centre := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var crossings: int = 0
	for i: int in range(0, ball.size(), 3):
		for e: int in 3:
			var a: Vector3 = ball[i + e] + centre
			var b: Vector3 = ball[i + (e + 1) % 3] + centre
			for t: int in range(0, shell.size(), 3):
				if Geometry3D.segment_intersects_triangle(a, b, shell[t], shell[t + 1],
						shell[t + 2]) != null:
					crossings += 1
	assert_eq(crossings, 0, "head edges crossing the shell")

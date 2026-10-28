extends GutTest

# Each sleeve is one skin from an armhole in the torso to the wrist
# (SkaterMeshBuilder._sleeve, docs/upper-body-skin-plan.md): authored in the
# torso's frame at rest and bound to its bones by their rest poses, so it blends
# across the shoulder. These hold what that needs and nothing on screen shows
# until it breaks: the binds put every vertex back where it was authored when
# the bones rest, the sleeve's surfaces and the torso meet ring for ring with the
# same weights, the facets face out, and each handedness's skin rides the arm on
# its side.

const UpperBone = SkaterMeshBuilder.UpperBone
const UpperSurface = SkaterMeshBuilder.UpperSurface
const SleevePart = SkaterMeshBuilder.SleevePart
# The sleeve's surfaces per side (left, right) in the order the skin appends them.
const _SLEEVE_SURFACES: Array = [
	[UpperSurface.SHOULDER_L, UpperSurface.TOP_UPPER_ARM, UpperSurface.TOP_ELBOW,
			UpperSurface.TOP_FOREARM],
	[UpperSurface.SHOULDER_R, UpperSurface.BOTTOM_UPPER_ARM, UpperSurface.BOTTOM_ELBOW,
			UpperSurface.BOTTOM_FOREARM],
]


func test_the_rest_lengths_are_the_skaters() -> void:
	var sk := Skater.new()
	assert_almost_eq(SkaterMeshBuilder.UPPER_ARM_REST_M, sk.upper_arm_length, 1e-6)
	assert_almost_eq(SkaterMeshBuilder.FOREARM_REST_M, sk.forearm_length, 1e-6)
	assert_almost_eq(SkaterMeshBuilder.SLEEVE_RADIUS_M, sk.arm_mesh_thickness * 0.5, 1e-6,
			"the arm prisms rest at the sleeve's radius")
	assert_almost_eq(SkaterMeshBuilder.ELBOW_PAD_RADIUS_M, sk.elbow_sphere_radius, 1e-6)
	sk.free()


# A bind's pose undoes its bone's rest, so with every bone at rest each sleeve
# vertex skins to where it was authored — whatever bones it blends.
func test_rest_poses_put_the_sleeve_where_it_was_authored() -> void:
	var skin: Skin = SkaterMeshBuilder.shared_upper_skin()
	var torso_rest := Transform3D(Basis.IDENTITY, SkaterMeshBuilder.TORSO_REST_POS)
	for side_i: int in 2:
		for part: int in SkaterMeshBuilder.SLEEVE_PARTS:
			var bind: int = SkaterMeshBuilder.sleeve_bind(side_i, part)
			var at_rest: Transform3D = SkaterMeshBuilder.sleeve_rest(side_i, part) \
					* skin.get_bind_pose(bind)
			for axis: int in 3:
				assert_almost_eq(at_rest.basis[axis], torso_rest.basis[axis],
						Vector3.ONE * 1e-5, "side %d part %d basis" % [side_i, part])
			assert_almost_eq(at_rest.origin, torso_rest.origin, Vector3.ONE * 1e-5,
					"side %d part %d origin" % [side_i, part])
	assert_eq(skin.get_bind_pose(UpperBone.TORSO), Transform3D.IDENTITY,
			"the torso's bind is identity: its mesh is the sleeve's authoring frame")


# Where two of a side's surfaces (or a sleeve and the torso) share a position,
# they share its influences, or the skin tears there the moment the arm moves.
func test_the_sleeve_meets_itself_and_the_torso_ring_for_ring() -> void:
	var mesh: ArrayMesh = SkaterMeshBuilder.shared_upper_skin_mesh()
	var torso: Dictionary = _influences(mesh, UpperSurface.TORSO)
	for side_i: int in 2:
		var seen: Dictionary = {}
		var shared: int = 0
		var on_torso: int = 0
		for surface: int in _SLEEVE_SURFACES[side_i]:
			var here: Dictionary = _influences(mesh, surface)
			for key: Vector3i in here:
				if seen.has(key) and seen[key] != surface:
					shared += 1
				seen[key] = surface
				if torso.has(key):
					on_torso += 1
					assert_eq(here[key], torso[key],
							"side %d: an armhole corner skins as the torso's own does" % side_i)
		assert_gt(shared, 0, "side %d: its surfaces share rings" % side_i)
		assert_eq(on_torso, 8, "side %d: the armhole is the torso's eight corners" % side_i)
		var influences: Dictionary = {}
		for surface: int in _SLEEVE_SURFACES[side_i]:
			var here: Dictionary = _influences(mesh, surface)
			for key: Vector3i in here:
				if influences.has(key):
					assert_eq(here[key], influences[key],
							"side %d: a shared ring carries one set of weights" % side_i)
				influences[key] = here[key]


# Every sleeve triangle with area at rest faces the way it is lit: its front
# (Godot's, wound clockwise seen from it) is the side its normal points to. A
# triangle facing the other way draws black, or not at all.
func test_every_sleeve_triangle_faces_its_normal() -> void:
	var mesh: ArrayMesh = SkaterMeshBuilder.shared_upper_skin_mesh()
	for side_i: int in 2:
		var against: int = 0
		var checked: int = 0
		for surface: int in _SLEEVE_SURFACES[side_i]:
			if surface == UpperSurface.TOP_ELBOW or surface == UpperSurface.BOTTOM_ELBOW:
				continue  # its rings lie in one plane at rest; it is lit as it bends
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for t: int in range(0, verts.size(), 3):
				var face: Vector3 = (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t])
				if face.length() < 1e-7:
					continue
				checked += 1
				if face.dot(normals[t]) > 0.0:
					against += 1
		assert_gt(checked, 0)
		assert_eq(against, 0, "side %d: %d of %d triangles face away from their normal"
				% [side_i, against, checked])


# Down the arm, those normals point out of it.
func test_the_arm_is_lit_from_outside() -> void:
	var mesh: ArrayMesh = SkaterMeshBuilder.shared_upper_skin_mesh()
	for side_i: int in 2:
		var pivot: Vector3 = SkaterMeshBuilder._sleeve_pivot(side_i) \
				- SkaterMeshBuilder.TORSO_REST_POS
		var down: Vector3 = -SkaterMeshBuilder.shoulder_cap_rest(
				SkaterMeshBuilder._side_sign(side_i)).y
		for surface: int in [_SLEEVE_SURFACES[side_i][1], _SLEEVE_SURFACES[side_i][3]]:
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var inward: int = 0
			for v: int in verts.size():
				var off_axis: Vector3 = verts[v] - pivot
				off_axis -= down * off_axis.dot(down)
				if off_axis.length() < 1e-4 or absf(normals[v].dot(down)) > 0.9:
					continue  # the wrist's end disc faces down the arm
				if normals[v].dot(off_axis) < 0.0:
					inward += 1
			assert_eq(inward, 0, "side %d surface %d: normals pointing into the arm"
					% [side_i, surface])


func test_each_skin_rides_the_arm_on_its_side() -> void:
	for top_on_right: bool in [true, false]:
		var skin: Skin = SkaterMeshBuilder.shared_upper_skin(top_on_right)
		for side_i: int in 2:
			var top: bool = (side_i == 1) == top_on_right
			var bone: int = skin.get_bind_bone(
					SkaterMeshBuilder.sleeve_bind(side_i, SleevePart.UPPER_ARM))
			assert_eq(bone, UpperBone.TOP_UPPER_ARM if top else UpperBone.BOTTOM_UPPER_ARM,
					"top on the %s: side %d's upper arm" % [
						"right" if top_on_right else "left", side_i])
			assert_eq(skin.get_bind_bone(SkaterMeshBuilder.sleeve_bind(side_i, SleevePart.DELTOID)),
					SkaterBodySkeleton.DELTOID_L_BONE if side_i == 0
					else SkaterBodySkeleton.DELTOID_R_BONE)


func test_the_rig_wears_the_skin_for_its_handedness() -> void:
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.set_process(false)
	sk.set_physics_process(false)
	for left: bool in [true, false, true]:
		sk.is_left_handed = left
		var mesh: MeshInstance3D = sk._arms._mesh
		assert_eq(mesh.skin, SkaterMeshBuilder.shared_upper_skin(sk.shoulder.position.x > 0.0),
				"left-handed %s" % left)


# Position (quantized to 0.1 mm) → [bones, weights] of a surface's vertices.
func _influences(mesh: ArrayMesh, surface: int) -> Dictionary:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var out: Dictionary = {}
	for v: int in verts.size():
		var key := Vector3i((verts[v] * 10000.0).round())
		var found: Array = []
		for j: int in 4:
			if weights[v * 4 + j] > 0.0:
				found.append([bones[v * 4 + j], snappedf(weights[v * 4 + j], 1e-4)])
		found.sort()
		out[key] = found
	return out

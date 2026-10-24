class_name KeeperBodyRig
extends Skeleton3D

# Draws the keeper's gear as ONE skinned mesh: a bone per gear piece, posed on
# its save box each update, so the pieces' fifty-odd surfaces cost a draw per
# material instead of one each. The plain slots are zones of one surface that
# BodyZonePaint draws (zone = slot). A surface the kit shader paints keeps its
# material on a surface of its own, each vertex carrying its place and normal in
# its piece's box frame in CUSTOM0 and CUSTOM1: the shader paints by those, and
# skinning moves VERTEX. A right-catcher's pieces are built turned over on their
# own x with their winding reversed, since skinning will not flip it
# (KeeperSkeleton.mirrored).

# Round him in any stance: the skinned mesh is culled by this, not by its rest.
const _BOUNDS := AABB(Vector3(-1.6, -0.1, -1.6), Vector3(3.2, 2.4, 3.2))

var paint: BodyZonePaint = null
var _mesh: MeshInstance3D = null


func _init() -> void:
	name = "BodyRig"
	for part: int in KeeperGear.PART_COUNT:
		add_bone(KeeperGear.Part.keys()[part])


# Builds the body from the plain slots' material records (`slots`, a zone each)
# and `kit_material`, (part, slot) -> the kit-shader material that surface
# wears, or null for its slot's.
func build(slots: Array[StandardMaterial3D], kit_material: Callable, mirrored: bool) -> void:
	var turn := Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)) if mirrored else Basis.IDENTITY,
			Vector3.ZERO)
	var zones := BodyZoneMesh.new()
	var painted: Dictionary = {}
	var order: Array[ShaderMaterial] = []
	for part: int in KeeperGear.PART_COUNT:
		var piece: ArrayMesh = KeeperGearMeshes.mesh(part)
		var piece_slots: PackedInt32Array = KeeperMeshKit.surface_slots(piece)
		for s: int in piece_slots.size():
			var arrays: Array = piece.surface_get_arrays(s)
			var kit: ShaderMaterial = kit_material.call(part, piece_slots[s]) as ShaderMaterial
			if kit == null:
				zones.add(arrays, piece_slots[s], part, turn)
				continue
			if not painted.has(kit):
				painted[kit] = _Painted.new()
				order.append(kit)
			(painted[kit] as _Painted).add(arrays, part, mirrored)
	var mesh: ArrayMesh = zones.commit()
	paint = BodyZonePaint.new(slots.size())
	for z: int in slots.size():
		paint.set_zone(z, slots[z])
	mesh.surface_set_material(0, paint.material)
	for kit: ShaderMaterial in order:
		kit.set_shader_parameter("skinned", true)
		(painted[kit] as _Painted).commit_into(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, kit)
	var skin := Skin.new()
	for part: int in KeeperGear.PART_COUNT:
		skin.add_bind(part, Transform3D.IDENTITY)
	if _mesh != null:
		_mesh.free()
	_mesh = MeshInstance3D.new()
	_mesh.name = "BodyMesh"
	_mesh.mesh = mesh
	_mesh.skin = skin
	_mesh.custom_aabb = _BOUNDS
	add_child(_mesh)
	_mesh.skeleton = NodePath("..")


func update(skel: KeeperSkeleton) -> void:
	for part: int in KeeperGear.PART_COUNT:
		set_bone_pose(part, KeeperGear.box(skel, part))


func body_mesh() -> MeshInstance3D:
	return _mesh


# The surfaces one kit-shader material paints, rigid on their pieces' bones.
class _Painted:
	extends RefCounted

	var _verts := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _colors := PackedColorArray()
	var _bones := PackedInt32Array()
	var _weights := PackedFloat32Array()
	var _place := PackedFloat32Array()
	var _facing := PackedFloat32Array()
	var _indices := PackedInt32Array()

	func add(arrays: Array, bone: int, mirrored: bool) -> void:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: Variant = arrays[Mesh.ARRAY_COLOR]
		var base: int = _verts.size()
		var turn := Vector3(-1.0 if mirrored else 1.0, 1.0, 1.0)
		for i: int in verts.size():
			_verts.append(verts[i] * turn)
			_normals.append(normals[i] * turn)
			_colors.append((colors as PackedColorArray)[i] if colors != null else Color.WHITE)
			_bones.append_array([bone, 0, 0, 0])
			_weights.append_array([1.0, 0.0, 0.0, 0.0])
			_place.append_array([verts[i].x, verts[i].y, verts[i].z])
			_facing.append_array([normals[i].x, normals[i].y, normals[i].z])
		for t: int in range(0, verts.size(), 3):
			_indices.append(base + t)
			_indices.append(base + t + (2 if mirrored else 1))
			_indices.append(base + t + (1 if mirrored else 2))

	func commit_into(mesh: ArrayMesh) -> void:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_BONES] = _bones
		arrays[Mesh.ARRAY_WEIGHTS] = _weights
		arrays[Mesh.ARRAY_CUSTOM0] = _place
		arrays[Mesh.ARRAY_CUSTOM1] = _facing
		arrays[Mesh.ARRAY_INDEX] = _indices
		var format: int = (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)

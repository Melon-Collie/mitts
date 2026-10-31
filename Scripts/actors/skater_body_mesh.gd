class_name SkaterBodyMesh
extends RefCounted

# The whole body as ONE surface, so it is one draw in every pass it is in — the
# view and each shadow map that holds it: the skin (SkaterConnectedMesh) with
# the rigid parts (SkaterRigidParts) appended. The skin's binds come first;
# after them the rigid parts bind to their own bones at identity, upper then
# legs, so a rigid vertex is its bone's pose alone, as on its own mesh; last,
# the skate upper's feet, which read it from the SKATE bone's frame.

static var _cache: Dictionary = {}
static var _skin: Skin = null


# One per GearModelRegistry TUCK_* option, as the skin is, and per TONGUE_*
# option, as the skates' uppers are.
static func shared_mesh(tuck: int, tongue: int = GearModelRegistry.TONGUE_TUCKED) -> ArrayMesh:
	var skin_mesh: ArrayMesh = SkaterConnectedMesh.shared_mesh(tuck)
	if SkaterConnectedMesh.preview_pants_only:
		return skin_mesh
	var legs: ArrayMesh = SkaterRigidParts.leg_body_mesh(tongue)
	var key: Vector2i = Vector2i(skin_mesh.get_instance_id(), legs.get_instance_id())
	var built: ArrayMesh = _cache.get(key)
	if built == null:
		built = _build(skin_mesh, legs)
		_cache[key] = built
	return built


static func shared_skin() -> Skin:
	if _skin == null:
		_skin = SkaterConnectedMesh.shared_skin().duplicate() as Skin
		for bone: int in SkaterMeshBuilder.UPPER_BONE_COUNT:
			_skin.add_bind(bone, Transform3D.IDENTITY)
		for bone: int in SkaterMeshBuilder.LEG_BONE_COUNT:
			_skin.add_bind(SkaterBodySkeleton.LEG_BONE_OFFSET + bone, Transform3D.IDENTITY)
		# SkaterRigidParts.SKATE_UPPER_FOOT_BIND, left then right.
		var foot_from_skate: Transform3D = SkateUpperMesh.SKATE_FROM_FOOT.affine_inverse()
		for foot: int in [SkaterMeshBuilder.LegBone.FOOT_L, SkaterMeshBuilder.LegBone.FOOT_R]:
			_skin.add_bind(SkaterBodySkeleton.LEG_BONE_OFFSET + foot, foot_from_skate)
	return _skin


# The bind the upper rigid parts' bone 0 is moved to; the legs' follow theirs.
static func upper_bind_base() -> int:
	return SkaterConnectedMesh.shared_skin().get_bind_count()


static func _build(skin_mesh: ArrayMesh, legs: ArrayMesh) -> ArrayMesh:
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for a: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
		out[a] = PackedVector3Array()
	for a: int in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		out[a] = PackedVector2Array()
	out[Mesh.ARRAY_COLOR] = PackedColorArray()
	out[Mesh.ARRAY_BONES] = PackedInt32Array()
	out[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array()
	out[Mesh.ARRAY_INDEX] = PackedInt32Array()
	var upper: int = upper_bind_base()
	_append(out, skin_mesh.surface_get_arrays(0), 0)
	_append(out, SkaterRigidParts.upper_body_mesh().surface_get_arrays(0), upper)
	_append(out, legs.surface_get_arrays(0),
			upper + SkaterMeshBuilder.UPPER_BONE_COUNT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


# `src`'s vertices after `out`'s, its bind indices moved up by `bind_offset`.
static func _append(out: Array, src: Array, bind_offset: int) -> void:
	var base: int = (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var n: int = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	# A packed array held in an Array comes out a copy: each is taken out,
	# appended to and put back.
	for a: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
		var v3: PackedVector3Array = out[a]
		v3.append_array(src[a])
		out[a] = v3
	for a: int in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		var v2: PackedVector2Array = out[a]
		v2.append_array(src[a])
		out[a] = v2
	var colors: PackedColorArray = out[Mesh.ARRAY_COLOR]
	colors.append_array(src[Mesh.ARRAY_COLOR])
	out[Mesh.ARRAY_COLOR] = colors
	var weights: PackedFloat32Array = out[Mesh.ARRAY_WEIGHTS]
	weights.append_array(src[Mesh.ARRAY_WEIGHTS])
	out[Mesh.ARRAY_WEIGHTS] = weights
	var bones: PackedInt32Array = out[Mesh.ARRAY_BONES]
	var src_bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
	for b: int in src_bones:
		bones.append(b + bind_offset)
	out[Mesh.ARRAY_BONES] = bones
	var indices: PackedInt32Array = out[Mesh.ARRAY_INDEX]
	var src_indices: Variant = src[Mesh.ARRAY_INDEX]
	if src_indices == null or (src_indices as PackedInt32Array).is_empty():
		for i: int in n:
			indices.append(base + i)
	else:
		for i: int in src_indices:
			indices.append(base + i)
	out[Mesh.ARRAY_INDEX] = indices

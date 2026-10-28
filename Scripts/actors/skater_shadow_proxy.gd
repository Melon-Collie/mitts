class_name SkaterShadowProxy
extends RefCounted

# The skater's shadow, cast by one stand-in mesh instead of by the figure itself.
#
# The figure is two skinned meshes of ~38 surfaces, and a surface is a draw call
# in every pass it takes part in. Each shadowed light in range is a pass, so the
# figure cost ~38 draws per light per frame. The proxy is the same geometry,
# skinned to the same skeleton, merged into ONE surface and drawn only into
# shadow maps (SHADOWS_ONLY), while the figure itself stops casting. Same
# shadow, one draw per light.
#
# Parts that are not on the skeleton stay what they are: the stick and blade
# keep casting (each is one surface already), and the small ones a shadow map
# cannot resolve — the knob, the tape, the face gear — are created not casting
# where they are created.

# The player's Video setting (set_enabled); a skater built later reads it in
# build().
static var enabled: bool = true

static var _merged: ArrayMesh = null
static var _skin: Skin = null
# Every built proxy, so a settings change reaches the skaters already on the ice.
static var _live: Array[WeakRef] = []

var _proxy: MeshInstance3D = null
var _stick: GeometryInstance3D = null
var _blade: GeometryInstance3D = null
var _ghost: bool = false


# `skeleton` already carries the rigs' meshes (LegMesh, UpperMesh), which stop
# casting here; the proxy joins them.
func build(skeleton: Skeleton3D, stick: GeometryInstance3D, blade: GeometryInstance3D) -> void:
	for child: Node in skeleton.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stick = stick
	_blade = blade
	_proxy = MeshInstance3D.new()
	_proxy.name = "ShadowProxy"
	_proxy.mesh = shared_mesh()
	_proxy.skin = shared_skin()
	_proxy.skeleton = NodePath("..")
	_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	skeleton.add_child(_proxy)
	_live.append(weakref(self))
	refresh()


static func set_enabled(on: bool) -> void:
	enabled = on
	var kept: Array[WeakRef] = []
	for ref: WeakRef in _live:
		var proxy: SkaterShadowProxy = ref.get_ref() as SkaterShadowProxy
		if proxy != null:
			proxy.refresh()
			kept.append(ref)
	_live = kept


# A ghost is drawn translucent, and translucent surfaces cast no shadow; the
# proxy is opaque, so it goes with the ghost.
func set_ghost(ghost: bool) -> void:
	_ghost = ghost
	refresh()


func refresh() -> void:
	if _proxy == null:
		return
	_proxy.visible = enabled and not _ghost
	var cast: GeometryInstance3D.ShadowCastingSetting = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _stick != null:
		_stick.cast_shadow = cast
	if _blade != null:
		_blade.cast_shadow = cast


# The upper and leg skin meshes as one surface, with every vertex weighted to
# its body-skeleton bone index, so one identity-bind skin over the whole
# skeleton poses it exactly as the two rig skins pose their halves.
static func shared_mesh() -> ArrayMesh:
	if _merged == null:
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = PackedVector3Array()
		out[Mesh.ARRAY_NORMAL] = PackedVector3Array()
		out[Mesh.ARRAY_BONES] = PackedInt32Array()
		out[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array()
		out[Mesh.ARRAY_INDEX] = PackedInt32Array()
		var tail: Dictionary = {SkaterMeshBuilder.UPPER_TAIL_BIND: SkaterBodySkeleton.TAIL_BONE}
		for bind: int in 2 * SkaterMeshBuilder.TORSO_SIDES:
			tail[SkaterMeshBuilder.UPPER_COLUMN_BIND_BASE + bind] = \
					SkaterBodySkeleton.COLUMN_BONE_BASE + bind
		tail[SkaterMeshBuilder.UPPER_DELTOID_BIND] = SkaterBodySkeleton.DELTOID_L_BONE
		tail[SkaterMeshBuilder.UPPER_DELTOID_BIND + 1] = SkaterBodySkeleton.DELTOID_R_BONE
		_append_mesh(out, SkaterMeshBuilder.shared_upper_skin_mesh(), 0, tail)
		_append_mesh(out, SkaterMeshBuilder.shared_leg_skin_mesh(),
				SkaterBodySkeleton.LEG_BONE_OFFSET)
		_merged = ArrayMesh.new()
		_merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return _merged


static func shared_skin() -> Skin:
	if _skin == null:
		_skin = Skin.new()
		for bone: int in SkaterBodySkeleton.BODY_BONE_COUNT:
			_skin.add_bind(bone, Transform3D.IDENTITY)
	return _skin


# `bone_offset` turns a rig skin's bind index into the body skeleton's bone
# index (the rig skins bind index i to bone offset + i), except the binds in
# `extra`, which name their own bones (the upper skin's jersey tail and
# deltoids).
static func _append_mesh(out: Array, src: ArrayMesh, bone_offset: int,
		extra: Dictionary = {}) -> void:
	var verts: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = out[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = out[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = out[Mesh.ARRAY_INDEX]
	for surface: int in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(surface)
		var base: int = verts.size()
		var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		verts.append_array(src_verts)
		normals.append_array(arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)
		var src_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for i: int in src_bones.size():
			src_bones[i] = int(extra.get(src_bones[i], src_bones[i] + bone_offset))
		bones.append_array(src_bones)
		weights.append_array(arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array)
		var src_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
				if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if src_indices.is_empty():
			for i: int in src_verts.size():
				indices.append(base + i)
		else:
			for index: int in src_indices:
				indices.append(base + index)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	out[Mesh.ARRAY_INDEX] = indices

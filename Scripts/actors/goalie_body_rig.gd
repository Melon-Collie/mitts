class_name GoalieBodyRig
extends Skeleton3D

# Draws the goalie's rigid parts as ONE skinned mesh, so the ~20 part meshes cost
# one draw a pass instead of one each (docs/body-draw-calls-plan.md).
#
# The part nodes stay what they are: the StaticBody3Ds carry colliders the saves
# read, and every part keeps its transform, its visibility and its material as
# their owners set them. This rig only reads them. Each drawn part is a bone, its
# surfaces are zones of the merged mesh (BodyZoneMesh, BodyZonePaint), and the
# originals move to render layer 0, so nothing draws them twice. A part wearing
# anything but an opaque StandardMaterial3D — the jersey's ShaderMaterial — is not
# merged and draws itself. GoalieUniformCoordinator owns it and rebuilds it after
# every repaint.

var _goalie: Node3D
var _mesh: MeshInstance3D = null
var _shadow: MeshInstance3D = null
var _paint: BodyZonePaint = null
var _parts: Array[MeshInstance3D] = []
# Per part, the stretch its build-time transform carried, baked into its
# vertices; its bone carries the rest (see _stretch).
var _unbake: Array[Transform3D] = []
# Render layers of every part this rig took off screen, to hand back.
var _hidden_layers: Dictionary = {}


func _init(goalie: Node3D) -> void:
	_goalie = goalie
	name = "BodyRig"
	# After Goalie._process, which places the connectors and arm joints this
	# copies.
	process_priority = 1


func _process(_delta: float) -> void:
	if SkaterCameraCull.sees(_goalie):
		update()


# Re-reads every part — its mesh, its material, whether it casts — and rebuilds
# the merged body from them. Run after anything repaints or reshapes a part.
func rebuild() -> void:
	_restore_parts()
	_parts.clear()
	_unbake.clear()
	_collect(_goalie)
	clear_bones()
	var skin := Skin.new()
	var body := BodyZoneMesh.new()
	var casters := BodyZoneMesh.new()
	var zones: Array[StandardMaterial3D] = []
	var root_inv: Transform3D = _goalie.global_transform.affine_inverse()
	for bone: int in _parts.size():
		var mesh_part: MeshInstance3D = _parts[bone]
		add_bone("%d_%s" % [bone, mesh_part.name])
		skin.add_bind(bone, Transform3D.IDENTITY)
		var bake := Transform3D(_stretch((root_inv * mesh_part.global_transform).basis), Vector3.ZERO)
		_unbake.append(bake.affine_inverse())
		for s: int in mesh_part.mesh.get_surface_count():
			var arrays: Array = mesh_part.mesh.surface_get_arrays(s)
			body.add(arrays, zones.size(), bone, bake)
			if mesh_part.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casters.add(arrays, zones.size(), bone, bake)
			var mat: StandardMaterial3D = mesh_part.get_active_material(s) as StandardMaterial3D
			zones.append(mat if mat != null else StandardMaterial3D.new())
		_hidden_layers[mesh_part] = mesh_part.layers
		mesh_part.layers = 0
	_paint = BodyZonePaint.new(zones.size())
	for z: int in zones.size():
		_paint.set_zone(z, zones[z])
	_mesh = _replace(_mesh, "BodyMesh", body, skin)
	_mesh.set_surface_override_material(0, _paint.material)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow = _replace(_shadow, "BodyShadow", casters, skin)
	if _shadow != null:
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	update()


# Poses every bone where its part is drawn this frame: the part's interpolated
# transform in the goalie's interpolated frame, so the merged body moves exactly
# as the parts would have. A hidden part's bone collapses.
func update() -> void:
	var root_inv: Transform3D = _goalie.get_global_transform_interpolated().affine_inverse()
	for bone: int in _parts.size():
		var mesh_part: MeshInstance3D = _parts[bone]
		if mesh_part.is_visible_in_tree():
			set_bone_pose(bone, root_inv * mesh_part.get_global_transform_interpolated() * _unbake[bone])
		else:
			set_bone_pose(bone, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func part_count() -> int:
	return _parts.size()


func part(bone: int) -> MeshInstance3D:
	return _parts[bone]


func body_mesh() -> MeshInstance3D:
	return _mesh


func shadow_mesh() -> MeshInstance3D:
	return _shadow


func paint() -> BodyZonePaint:
	return _paint


func _collect(node: Node) -> void:
	if node is SubViewport or node is GoalieVFX or node == self:
		return
	if node is MeshInstance3D and _mergeable(node as MeshInstance3D):
		_parts.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect(child)


static func _mergeable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0 \
			or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return false
	for s: int in mi.mesh.get_surface_count():
		var mat: Material = mi.get_active_material(s)
		if mat == null:
			continue
		if not mat is StandardMaterial3D:
			return false
		if (mat as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
	return true


# The part of a basis that is not a rotation: what a part's node scaled it by,
# with any mirror in it. Baked into the vertices, it leaves its bone a proper
# rotation, so skinning — which neither flips winding for a mirror nor corrects
# normals for a non-uniform scale — draws the part as its node did.
static func _stretch(b: Basis) -> Basis:
	if absf(b.determinant()) < 1e-9:
		return Basis.IDENTITY
	var rot: Basis = b.orthonormalized()
	if rot.determinant() < 0.0:
		rot = rot * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	return rot.inverse() * b


func _replace(old: MeshInstance3D, node_name: String, built: BodyZoneMesh,
		skin: Skin) -> MeshInstance3D:
	if old != null:
		old.free()
	if built.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = built.commit()
	mi.skin = skin
	add_child(mi)
	mi.skeleton = NodePath("..")
	return mi


func _restore_parts() -> void:
	for p: Variant in _hidden_layers:
		if is_instance_valid(p):
			(p as MeshInstance3D).layers = _hidden_layers[p]
	_hidden_layers.clear()

class_name PingMarker
extends Node3D

# What a smart ping points at, drawn flat on the ice for the pinger's team: a
# ring that drops onto a spot or rides a skater or the puck, and a line to it
# from whoever called. Built from code, self-animating, self-freeing. The
# words are the pinger's PingCallout; this is the "who" and the "where".

const _RING_SEGMENTS: int = 48
# A spot's ring is the size it always was; one round a skater has to clear
# his slot ring and nameplate.
const _SPOT_INNER_R: float = 0.60
const _SPOT_OUTER_R: float = 0.72
const _TARGET_INNER_R: float = 0.97
const _TARGET_OUTER_R: float = 1.07
# The dark rim under the accent: amber alone has no contrast on white ice.
const _RIM_M: float = 0.045
const _ICE_Y: float = 0.05          # the skater HUD's ice-decal height
const _RIM_Y: float = 0.045
const _FADE_S: float = 0.6
const _DROP_S: float = 0.22
const _DROP_FROM_SCALE: float = 2.4
const _PULSE_HZ: float = 1.6
const _PULSE_SCALE_MAX: float = 1.10
# A spot keeps sending rings out for as long as it stands, so it is found
# again by an eye that looked away.
const _RIPPLE_PERIOD_S: float = 1.1
const _RIPPLE_SCALE_MAX: float = 2.3
const _RIPPLE_ALPHA: float = 0.7
const _LINK_HALF_W: float = 0.035
const _LINK_ALPHA: float = 0.75
# The line starts and ends clear of both bodies, and is not drawn at all
# between two things this close.
const _LINK_SOURCE_GAP_M: float = 0.9
const _LINK_MIN_M: float = 0.8
# A held marker is a ping not sent yet: fainter than one that was, and still.
const _HELD_ALPHA: float = 0.8

var _follow: Node3D = null
var _follows: bool = false
var _source: Node3D = null
var _hold_s: float = 0.0
var _age: float = 0.0
var _outer_r: float = _SPOT_OUTER_R
var _held: bool = false
var _held_scale: float = 1.0

var _ring_root: Node3D = null
var _ripple: MeshInstance3D = null
var _link: Node3D = null
var _accent_mat: StandardMaterial3D = null
var _rim_mat: StandardMaterial3D = null
var _ripple_mat: StandardMaterial3D = null
var _link_mat: StandardMaterial3D = null
var _link_rim_mat: StandardMaterial3D = null


# A ring dropped on open ice at `pos`.
static func at_spot(pos: Vector3, source: Node3D, hold_s: float) -> PingMarker:
	var marker := PingMarker.new()
	marker.position = Vector3(pos.x, 0.0, pos.z)
	marker._build(source, hold_s, _SPOT_INNER_R, _SPOT_OUTER_R, true)
	return marker


# A ring that rides `follow` (a skater or the puck) until it fades or `follow`
# leaves the tree.
static func on_node(follow: Node3D, source: Node3D, hold_s: float) -> PingMarker:
	var marker := PingMarker.new()
	marker._follow = follow
	marker._follows = true
	marker._build(source, hold_s, _TARGET_INNER_R, _TARGET_OUTER_R, false)
	return marker


# A marker with no life of its own. Its owner aims it every frame it is shown
# (aim_at_spot / aim_at_node) and frees it.
static func held() -> PingMarker:
	var marker := PingMarker.new()
	marker._held = true
	marker._build(null, INF, _TARGET_INNER_R, _TARGET_OUTER_R, false)
	return marker


func aim_at_spot(pos: Vector3) -> void:
	_follow = null
	_follows = false
	_held_scale = _SPOT_OUTER_R / _TARGET_OUTER_R
	global_position = Vector3(pos.x, 0.0, pos.z)
	_animate()


func aim_at_node(node: Node3D) -> void:
	_follow = node
	_follows = true
	_held_scale = 1.0
	_animate()


# The ring's outer radius as a held marker draws it.
func held_radius() -> float:
	return _TARGET_OUTER_R * _held_scale


func _build(source: Node3D, hold_s: float, inner_r: float, outer_r: float,
		ripples: bool) -> void:
	# Placed at render rate from interpolated poses.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_source = source if source != _follow else null
	_hold_s = hold_s
	_outer_r = outer_r
	_accent_mat = _flat_material(PingCallout.ACCENT)
	_rim_mat = _flat_material(MenuStyle.HUD_ICE)

	_ring_root = Node3D.new()
	add_child(_ring_root)
	_ring_root.add_child(_mesh_node(
			_annulus_mesh(inner_r - _RIM_M, outer_r + _RIM_M), _rim_mat, _RIM_Y))
	_ring_root.add_child(_mesh_node(_annulus_mesh(inner_r, outer_r), _accent_mat, _ICE_Y))
	if ripples:
		_ripple_mat = _flat_material(PingCallout.ACCENT)
		_ripple = _mesh_node(_annulus_mesh(outer_r - 0.05, outer_r), _ripple_mat, _RIM_Y)
		add_child(_ripple)
	if _source != null:
		_link_mat = _flat_material(PingCallout.ACCENT)
		_link_rim_mat = _flat_material(MenuStyle.HUD_ICE)
		_link = Node3D.new()
		_link.add_child(_mesh_node(
				_strip_mesh(_LINK_HALF_W + _RIM_M * 0.5), _link_rim_mat, _RIM_Y))
		_link.add_child(_mesh_node(_strip_mesh(_LINK_HALF_W), _link_mat, _ICE_Y))
		add_child(_link)


func _ready() -> void:
	_animate()


func _process(delta: float) -> void:
	if _held:
		return
	_age += delta
	if _age >= _hold_s + _FADE_S or NetworkManager.is_replay_mode() \
			or (_follows and not is_instance_valid(_follow)):
		queue_free()
		return
	_animate()


func _animate() -> void:
	if _follows:
		var at: Vector3 = ground_of(_follow)
		global_position = Vector3(at.x, 0.0, at.z)
	if _held:
		_ring_root.scale = Vector3(_held_scale, 1.0, _held_scale)
		_accent_mat.albedo_color.a = _HELD_ALPHA
		_rim_mat.albedo_color.a = MenuStyle.HUD_OPACITY * _HELD_ALPHA
		return
	var fade: float = 1.0 - clampf((_age - _hold_s) / _FADE_S, 0.0, 1.0)
	var drop_t: float = clampf(_age / _DROP_S, 0.0, 1.0)
	var eased: float = 1.0 - (1.0 - drop_t) * (1.0 - drop_t)
	var pulse: float = lerpf(1.0, _PULSE_SCALE_MAX,
			0.5 + 0.5 * sin((_age - _DROP_S) * TAU * _PULSE_HZ))
	var s: float = lerpf(_DROP_FROM_SCALE, 1.0, eased) if drop_t < 1.0 else pulse
	_ring_root.scale = Vector3(s, 1.0, s)
	_accent_mat.albedo_color.a = eased * fade
	_rim_mat.albedo_color.a = MenuStyle.HUD_OPACITY * eased * fade
	if _ripple != null:
		var ripple_t: float = fposmod(_age, _RIPPLE_PERIOD_S) / _RIPPLE_PERIOD_S
		var rs: float = lerpf(1.0, _RIPPLE_SCALE_MAX, ripple_t)
		_ripple.scale = Vector3(rs, 1.0, rs)
		_ripple_mat.albedo_color.a = _RIPPLE_ALPHA * (1.0 - ripple_t) * fade
	if _link != null:
		_place_link(eased * fade)


# From just off the pinger to the ring's edge, stretched along local -Z.
func _place_link(alpha: float) -> void:
	if not is_instance_valid(_source):
		_link.visible = false
		return
	var from: Vector3 = ground_of(_source)
	var to: Vector3 = global_position
	var span := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length: float = span.length() - _LINK_SOURCE_GAP_M - _outer_r
	_link.visible = length >= _LINK_MIN_M
	if not _link.visible:
		return
	var dir: Vector3 = span.normalized()
	var start: Vector3 = Vector3(from.x, 0.0, from.z) + dir * _LINK_SOURCE_GAP_M
	_link.global_transform = Transform3D(
			Basis.looking_at(dir, Vector3.UP).scaled_local(Vector3(1.0, 1.0, length)), start)
	_link_mat.albedo_color.a = _LINK_ALPHA * alpha
	_link_rim_mat.albedo_color.a = _LINK_ALPHA * MenuStyle.HUD_OPACITY * alpha


# Where `node` is DRAWN this frame, which for a skater or the puck is between
# ticks.
static func ground_of(node: Node3D) -> Vector3:
	var skater := node as Skater
	if skater != null:
		return skater.render_transform().origin
	return node.get_global_transform_interpolated().origin


static func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


static func _mesh_node(mesh: Mesh, mat: Material, y: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = Vector3(0.0, y, 0.0)
	return node


# Flat annulus in the local XZ plane.
static func _annulus_mesh(inner_r: float, outer_r: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i: int in _RING_SEGMENTS:
		var a0: float = TAU * float(i) / float(_RING_SEGMENTS)
		var a1: float = TAU * float(i + 1) / float(_RING_SEGMENTS)
		var base: int = verts.size()
		verts.append(Vector3(cos(a0) * inner_r, 0.0, sin(a0) * inner_r))
		verts.append(Vector3(cos(a0) * outer_r, 0.0, sin(a0) * outer_r))
		verts.append(Vector3(cos(a1) * outer_r, 0.0, sin(a1) * outer_r))
		verts.append(Vector3(cos(a1) * inner_r, 0.0, sin(a1) * inner_r))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return _flat_mesh(verts, indices)


# A unit-long strip from the origin along -Z, `half_w` to each side.
static func _strip_mesh(half_w: float) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-half_w, 0.0, 0.0), Vector3(half_w, 0.0, 0.0),
		Vector3(half_w, 0.0, -1.0), Vector3(-half_w, 0.0, -1.0),
	])
	return _flat_mesh(verts, PackedInt32Array([0, 1, 2, 0, 2, 3]))


static func _flat_mesh(verts: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

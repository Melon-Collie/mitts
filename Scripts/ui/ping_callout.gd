class_name PingCallout
extends Node3D

# A skater's spoken call, drawn as a speech bubble: white text on a dark plate
# with an accent edge and a tail down to whoever said it. The owner places the
# node each frame (the tail's tip is the node's origin); the callout pops in,
# holds and fades by itself.

# The one colour of everything a ping draws. Amber, because the ice is white
# and the slot rings already spend green, blue and red on who is who.
const ACCENT := Color(1.0, 0.74, 0.10, 1.0)

const _HOLD_S: float = 2.4
const _FADE_S: float = 0.5
const _POP_S: float = 0.16
const _POP_FROM: float = 0.55
const _POP_OVERSHOOT: float = 1.10

const _FONT_SIZE: int = 46
const _PIXEL_SIZE: float = 0.005
# Metres, in the billboard's own plane (+Y is up the screen).
const _PAD_X: float = 0.16
const _PAD_Y: float = 0.07
const _CORNER_R: float = 0.11
const _CORNER_STEPS: int = 5
const _TAIL_H: float = 0.16
const _TAIL_HALF_W: float = 0.10
const _EDGE: float = 0.03
const _PLATE_ALPHA: float = 0.92
# A held call is one not made yet, and drawn fainter than one that was.
const _HELD_ALPHA: float = 0.8

var _label: Label3D = null
var _plate: MeshInstance3D = null
var _edge: MeshInstance3D = null
var _plate_mat: StandardMaterial3D = null
var _edge_mat: StandardMaterial3D = null
var _time_left: float = 0.0
var _age: float = 0.0
var _held: bool = false


func _init() -> void:
	top_level = true
	# Written at render rate from an interpolated pose (Skater.render_transform).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	_edge_mat = _billboard_material(ACCENT, 0)
	_plate_mat = _billboard_material(MenuStyle.BROADCAST_BG, 1)
	_edge = MeshInstance3D.new()
	_edge.material_override = _edge_mat
	add_child(_edge)
	_plate = MeshInstance3D.new()
	_plate.material_override = _plate_mat
	add_child(_plate)
	_label = Label3D.new()
	_label.font = MenuStyle.NAME_FONT
	_label.font_size = _FONT_SIZE
	_label.pixel_size = _PIXEL_SIZE
	_label.outline_size = 0
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 2
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func say(text: String) -> void:
	_lay_out(text)
	_held = false
	_time_left = _HOLD_S + _FADE_S
	_age = 0.0
	visible = true
	_apply(0.0)


# Shows `text` with no time of its own, until dismissed or replaced.
func hold(text: String) -> void:
	if not _held or _label.text != text:
		_lay_out(text)
	_held = true
	_time_left = 0.0
	visible = true
	scale = Vector3.ONE
	_set_alpha(_HELD_ALPHA)


func dismiss() -> void:
	_held = false
	_time_left = 0.0
	visible = false


func is_live() -> bool:
	return _held or _time_left > 0.0


func _lay_out(text: String) -> void:
	_label.text = text
	var text_px: Vector2 = MenuStyle.NAME_FONT.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _FONT_SIZE)
	var half_w: float = text_px.x * _PIXEL_SIZE * 0.5 + _PAD_X
	var half_h: float = text_px.y * _PIXEL_SIZE * 0.5 + _PAD_Y
	var centre_y: float = _TAIL_H + half_h
	_label.offset = Vector2(0.0, centre_y / _PIXEL_SIZE)
	_plate.mesh = _bubble_mesh(half_w, half_h, centre_y, 0.0)
	_edge.mesh = _bubble_mesh(half_w, half_h, centre_y, _EDGE)


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_apply(delta)


func _apply(delta: float) -> void:
	_time_left -= delta
	_age += delta
	if _time_left <= 0.0:
		visible = false
		return
	_set_alpha(clampf(_time_left / _FADE_S, 0.0, 1.0))
	var pop: float = _pop_scale(_age / _POP_S)
	scale = Vector3(pop, pop, pop)


func _set_alpha(alpha: float) -> void:
	_label.modulate.a = alpha
	_plate_mat.albedo_color.a = _PLATE_ALPHA * alpha
	_edge_mat.albedo_color.a = alpha


# Out past full size and back: the overshoot is what catches the eye.
static func _pop_scale(t: float) -> float:
	if t >= 1.0:
		return 1.0
	if t < 0.6:
		return lerpf(_POP_FROM, _POP_OVERSHOOT, t / 0.6)
	return lerpf(_POP_OVERSHOOT, 1.0, (t - 0.6) / 0.4)


static func _billboard_material(color: Color, priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.no_depth_test = true
	mat.render_priority = priority
	mat.albedo_color = color
	return mat


# A rounded plate centred on (0, centre_y) with a tail down to the origin, in
# the XY plane; `grow` pushes the whole outline out, which is how the edge is
# the same shape a little larger.
static func _bubble_mesh(half_w: float, half_h: float, centre_y: float,
		grow: float) -> ArrayMesh:
	var hw: float = half_w + grow
	var hh: float = half_h + grow
	var r: float = minf(_CORNER_R + grow, minf(hw, hh))
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.append(Vector3(0.0, centre_y, 0.0))
	var corners: Array[Vector2] = [
		Vector2(hw - r, hh - r), Vector2(-hw + r, hh - r),
		Vector2(-hw + r, -hh + r), Vector2(hw - r, -hh + r),
	]
	for c: int in corners.size():
		for i: int in _CORNER_STEPS + 1:
			var a: float = (float(c) + float(i) / float(_CORNER_STEPS)) * PI * 0.5
			verts.append(Vector3(corners[c].x + cos(a) * r,
					centre_y + corners[c].y + sin(a) * r, 0.0))
	var rim: int = verts.size() - 1
	for i: int in rim:
		indices.append_array([0, 1 + i, 1 + (i + 1) % rim])
	var tail: int = verts.size()
	var base_y: float = centre_y - hh + 0.01
	verts.append(Vector3(-_TAIL_HALF_W - grow, base_y, 0.0))
	verts.append(Vector3(_TAIL_HALF_W + grow, base_y, 0.0))
	verts.append(Vector3(0.0, -grow * 1.6, 0.0))
	indices.append_array([tail, tail + 1, tail + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

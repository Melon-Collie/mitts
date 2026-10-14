extends Node

# The goalie concept as a skin over a live Goalie: hides the scene's own
# visuals, hangs the concept's parts on the same part nodes (so the pose
# builder, the colliders and the blocker/blade seats are the real ones), and
# solves what joins them — thighs, arms, skate ankles — every frame. Add it as
# a child of the Goalie after the Goalie is ready, then call `dress(colors)`.

const Parts := preload("res://tools/goalie_concept/concept_parts.gd")

# Joints in their parts' frames.
const _HIP_IN_BODY := Vector3(0.13, -0.26, 0.02)
const _KNEE_IN_PAD := Vector3(0.0, 0.20, 0.05)
const _ANKLE_IN_PAD := Vector3(0.0, -0.33, 0.07)
const _GLOVE_WRIST_IN_GLOVE := Vector3(0.0, -0.03, 0.07)
const _FLOATER_IN_BODY := Vector3(0.27, 0.36, 0.0)
# A flat pad (butterfly, RVH) points the toe down the pad's length, sole to the
# back: plantar flexion at full flatness.
const _ANKLE_FLAT_DEG: float = -80.0
# Stick paint: a carbon shaft and paddle, white tape on the blade.
const _STICK_CARBON := Color(0.13, 0.13, 0.14)
const _STICK_TAPE := Color(0.94, 0.94, 0.92)

var _goalie: Node3D
var _body: Node3D
var _pads: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _thighs: Array[MeshInstance3D] = []
var _uppers: Array[MeshInstance3D] = []
var _fores: Array[MeshInstance3D] = []
var _elbows: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D


func dress(colors: Dictionary) -> void:
	_goalie = get_parent()
	_body = _goalie.get_node("Body")
	_hide_scene_visuals()
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.85
	BodyRim.apply(_mat)
	var pal: Dictionary = Parts.palette(colors)

	for side: int in 2:
		var pad: Node3D = _goalie.get_node("LeftPad" if side == 0 else "RightPad")
		_pads.append(pad)
		_add(pad, Parts.pad(pal, 1.0 if side == 0 else -1.0))
		var ankle := Node3D.new()
		ankle.position = _ANKLE_IN_PAD
		pad.add_child(ankle)
		_ankles.append(ankle)
		_add(ankle, Parts.skate())
		_thighs.append(_add(_goalie, Parts.thigh(pal)))
		_uppers.append(_add(_goalie, Parts.sleeve_upper(pal)))
		_fores.append(_add(_goalie, Parts.sleeve_fore(pal)))
		_elbows.append(_add(_goalie, Parts.elbow(pal)))
		var floater: MeshInstance3D = _add(_body, Parts.floater(pal))
		floater.position = Vector3(_FLOATER_IN_BODY.x * (-1.0 if side == 0 else 1.0),
				_FLOATER_IN_BODY.y, _FLOATER_IN_BODY.z)

	_add(_body, Parts.pants(pal))
	_add(_body, Parts.jersey(pal))
	_add(_body, Parts.neck())
	_add(_goalie.get_node("Head"), Parts.mask(pal))
	_add(_goalie.get_node("Glove"), Parts.trapper(pal))
	_add(_goalie.get_node("BlockArm/Blocker"), Parts.blocker_board(pal))
	_add(_goalie.get_node("BlockArm"), Parts.blocker_hand(pal))
	_restyle_stick()
	_back_lettering(colors)
	update()


func _process(_delta: float) -> void:
	if _goalie != null:
		update()


func update() -> void:
	var bt: Transform3D = _body.transform
	for side: int in 2:
		var sx: float = -1.0 if side == 0 else 1.0
		var pad: Node3D = _pads[side]
		var hip: Vector3 = bt * Vector3(_HIP_IN_BODY.x * sx, _HIP_IN_BODY.y, _HIP_IN_BODY.z)
		_lay(_thighs[side], hip, pad.transform * _KNEE_IN_PAD)
		var up: Vector3 = pad.transform.basis.y.normalized()
		var flat: float = clampf(1.0 - absf(up.y), 0.0, 1.0)
		_ankles[side].rotation = Vector3(deg_to_rad(_ANKLE_FLAT_DEG * flat), 0.0, 0.0)

	var off: Vector3 = GoalieAnatomy.SHOULDER_OFFSET
	var glove_shoulder: Vector3 = bt * Vector3(-off.x, off.y, off.z)
	var blocker_shoulder: Vector3 = bt * off
	var glove: Node3D = _goalie.get_node("Glove")
	var wrist: Vector3 = glove.transform * _GLOVE_WRIST_IN_GLOVE
	var clear: float = GoalieAnatomy.TORSO_BOX_WIDTH_M * 0.5 - off.x + 0.09
	var glove_elbow: Vector3 = TwoBoneIK.solve_elbow_hanging(glove_shoulder, wrist,
			GoalieAnatomy.ARM_UPPER_M, GoalieAnatomy.ARM_FOREARM_M,
			Vector3.FORWARD, Vector3.LEFT, clear)
	var blocker_elbow: Vector3 = _goalie.get("_blocker_elbow")
	var grip: Vector3 = (_goalie.get_node("BlockArm") as Node3D).position
	_lay(_uppers[0], glove_shoulder, glove_elbow)
	_lay(_fores[0], glove_elbow, wrist)
	_elbows[0].position = glove_elbow
	_lay(_uppers[1], blocker_shoulder, blocker_elbow)
	_lay(_fores[1], blocker_elbow, grip)
	_elbows[1].position = blocker_elbow


func thigh_length(side: int) -> float:
	return _thighs[side].transform.basis.y.length()


# A limb authored from y = 0 down to y = −1, laid from `near` to `far`.
static func _lay(mi: MeshInstance3D, near: Vector3, far: Vector3) -> void:
	var span: Vector3 = near - far
	var length: float = span.length()
	if length < 1e-4:
		return
	var y: Vector3 = span / length
	var ref: Vector3 = Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y)
	mi.transform = Transform3D(Basis(x, y * length, z), near)


func _add(parent: Node, mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	parent.add_child(mi)
	return mi


# Every scene mesh goes dark except the stick, which keeps its geometry.
func _hide_scene_visuals() -> void:
	for n: Node in _goalie.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.get_parent().name == "Stick":
			continue
		mi.layers = 0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Stand-in for the jersey shader's nameplate: the real integration keeps the
# shader, which projects onto the back's flat facets.
func _back_lettering(colors: Dictionary) -> void:
	for row: Array in [["MELON", 0.20, 34], ["31", 0.04, 110]]:
		var l := Label3D.new()
		l.text = row[0]
		l.font_size = row[2]
		l.pixel_size = 0.0016
		l.modulate = colors.text
		l.outline_modulate = colors.text_outline
		l.outline_size = 10
		l.position = Vector3(0.0, row[1], 0.158)
		l.double_sided = false
		_body.add_child(l)


func _restyle_stick() -> void:
	for n: Node in _goalie.get_node("BlockArm/Stick").get_children():
		var mi := n as MeshInstance3D
		if mi == null or mi.name == "StickKnob":
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = _STICK_TAPE if mi.name == "StickBladeMesh" else _STICK_CARBON
		m.roughness = 0.7
		BodyRim.apply(m)
		mi.material_override = m

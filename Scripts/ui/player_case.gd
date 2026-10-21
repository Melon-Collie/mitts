class_name PlayerCase
extends VBoxContainer

# The player screen's display case: an inset well holding its own 3D world, the
# LockerMannequin standing on an ice disc, and a camera that dollies to whatever
# piece the player is working on. The hint underneath names the turn/zoom
# gesture for whichever device is driving.
#
# The host calls `frame` with the focus the reached row asks for. Nothing
# focused (FULL) holds the whole figure at a slow turn; a focused shot holds
# still so the piece can be read.

const _CASE_SIZE := Vector2(360, 500)
const _CASE_FOV: float = 45.0
# Breathing room around whatever a framing has to contain.
const _FRAME_MARGIN: float = 1.12

# Camera easing. The dolly is quick enough to feel like a response to the row
# you landed on, slow enough that walking a column with the pad doesn't strobe.
const _EASE_PER_S: float = 7.0
const _IDLE_RAD_PER_S: float = 0.35
const _DRAG_RAD_PER_PX: float = 0.008
# Drag up pulls in, drag down pushes out. Multiplicative, so the rate feels the
# same nose-to-nose with a skate as it does on the wide shot.
const _DRAG_ZOOM_PER_PX: float = 0.004
const _ZOOM_NEAR_M: float = 0.22
const _ZOOM_FAR_M: float = 4.5
# The pad's right stick does the drag's two jobs as a RATE (per second at full
# deflection). Stick Y is positive DOWN like screen space, so pushing up zooms
# in — the same gesture as dragging up. Deadzone matches FreeCamera's.
const _PAD_DEADZONE: float = 0.15
const _PAD_RAD_PER_S: float = 2.2
const _PAD_ZOOM_PER_S: float = 0.8

var _viewport: SubViewport = null
var _mannequin: LockerMannequin = null
var _camera: Camera3D = null
var _hint: Label = null
var _focus: int = LockerMannequin.Focus.FULL
# Eased camera state — the target is whatever the current focus asks for.
var _anchor: Vector3 = Vector3.ZERO
var _dist: float = 2.45
var _pitch: float = 0.0
var _yaw: float = 0.0
var _target_yaw: float = 0.0
# Hand zoom on top of the framing's own distance, 1.0 = what the framing asked
# for. Cleared when the focus moves, like the presented yaw is.
var _zoom: float = 1.0
var _dragging: bool = false
# Cached like every other pad reader: get_connected_joypads() is not free, and
# device 0 is not a safe assumption. -1 = no pad.
var _pad_device: int = -1
# True on any frame the right stick is live, so the idle turn gets out of the
# way while the player is aiming the case themselves.
var _pad_looking: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build()
	Input.joy_connection_changed.connect(
			func(_d: int, _c: bool) -> void: _refresh_pad_device())
	_refresh_pad_device()
	InputDeviceTracker.device_changed.connect(
			func(_is_gamepad: bool) -> void: _refresh_hint())
	_refresh_hint()


func dress(attrs: PlayerAttributes, gear: GearStyleConfig, tape: StickTapeConfig,
		team_colors: Dictionary, skin_tone: int, is_left_handed: bool) -> void:
	_mannequin.apply(attrs, gear, tape, team_colors, skin_tone, is_left_handed)


func set_jersey_info(player_name: String, jersey_number: int) -> void:
	_mannequin.set_jersey_info(player_name, jersey_number)


# Re-aims only on a CHANGE, which is what lets a drag hold its angle: the
# presented yaw is a starting point for the piece, not a per-frame target.
func frame(focus: int) -> void:
	if focus == _focus:
		return
	_focus = focus
	_target_yaw = _mannequin.focus_yaw(focus)
	_zoom = 1.0


# Cut straight to `focus`, already settled rather than swinging in.
func settle(focus: int) -> void:
	_focus = focus
	_target_yaw = _mannequin.focus_yaw(focus)
	_yaw = _target_yaw
	_zoom = 1.0
	_dist = _framed_distance()
	_pitch = _mannequin.focus_pitch(focus)
	_anchor = _mannequin.focus_anchor(focus)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _mannequin == null:
		return
	_read_pad_look(delta)
	if _focus == LockerMannequin.Focus.FULL and not _dragging and not _pad_looking:
		_target_yaw += _IDLE_RAD_PER_S * delta
	var t: float = minf(_EASE_PER_S * delta, 1.0)
	_yaw = lerpf(_yaw, _target_yaw, t)
	_dist = lerpf(_dist, _framed_distance(), t)
	_pitch = lerpf(_pitch, _mannequin.focus_pitch(_focus), t)
	_anchor = _anchor.lerp(_mannequin.focus_anchor(_focus), t)
	_mannequin.rotation.y = _yaw
	# The anchor is a point ON the figure, so it swings with the turn; the
	# camera itself stays in the case's own plane and only ever dollies.
	var aimed: Vector3 = Basis(Vector3.UP, _yaw) * _anchor
	_camera.position = aimed + Vector3(0.0, sin(_pitch), -cos(_pitch)) * _dist
	_camera.look_at(aimed)


# How far back the current framing has to sit. The case is PORTRAIT, so a wide
# subject (the skate pair) is bound by the horizontal angle while a tall one
# (the whole stick) is bound by the vertical — take whichever needs more room.
func _base_distance() -> float:
	var extent: Vector2 = _mannequin.focus_extent(_focus)
	var v_tan: float = tan(deg_to_rad(_CASE_FOV * 0.5))
	var h_tan: float = v_tan * (_CASE_SIZE.x / _CASE_SIZE.y)
	return maxf(extent.y / v_tan, extent.x / h_tan) * _FRAME_MARGIN


func _framed_distance() -> float:
	return clampf(_base_distance() * _zoom, _ZOOM_NEAR_M, _ZOOM_FAR_M)


func _refresh_pad_device() -> void:
	var pads: Array = Input.get_connected_joypads()
	_pad_device = int(pads[0]) if not pads.is_empty() else -1


# Gated on the one device flag every surface reads, so a controller the player
# has switched off in Options is ignored entirely.
func _read_pad_look(delta: float) -> void:
	_pad_looking = false
	if _pad_device < 0 or not InputDeviceTracker.is_gamepad_active():
		return
	var look: Vector2 = GamepadAimRules.apply_radial_deadzone(Vector2(
			Input.get_joy_axis(_pad_device, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(_pad_device, JOY_AXIS_RIGHT_Y)), _PAD_DEADZONE)
	if look == Vector2.ZERO:
		return
	_pad_looking = true
	_target_yaw += look.x * _PAD_RAD_PER_S * delta
	_zoom_by(look.y * _PAD_ZOOM_PER_S * delta)


func _refresh_hint() -> void:
	if _hint != null:
		_hint.text = ControllerGlyphs.prompt(
				tr(&"PLAYER_CASE_HINT_MOUSE"), tr(&"PLAYER_CASE_HINT_PAD"))


func _on_case_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_target_yaw += motion.relative.x * _DRAG_RAD_PER_PX
		_zoom_by(motion.relative.y * _DRAG_ZOOM_PER_PX)


# Positive `exponent` pushes out, negative pulls in. Clamped against THIS
# framing's own distance rather than as a free multiplier: wound past the stop,
# the zoom would stop responding until wound all the way back.
func _zoom_by(exponent: float) -> void:
	var base: float = _base_distance()
	if base <= 0.0:
		return
	_zoom = clampf(_zoom * exp(exponent),
			minf(_ZOOM_NEAR_M / base, 1.0), maxf(_ZOOM_FAR_M / base, 1.0))


func _build() -> void:
	var case_panel := PanelContainer.new()
	var case_style := StyleBoxFlat.new()
	case_style.bg_color = MenuStyle.SURFACE_INPUT
	case_style.set_corner_radius_all(6)
	case_style.set_border_width_all(1)
	case_style.border_color = MenuStyle.TEAL_DIM
	case_style.set_content_margin_all(4)
	case_panel.add_theme_stylebox_override("panel", case_style)
	add_child(case_panel)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = _CASE_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.gui_input.connect(_on_case_input)
	case_panel.add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.fov = _CASE_FOV
	_viewport.add_child(_camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	_viewport.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -140.0, 0.0)
	fill.light_energy = 0.5
	_viewport.add_child(fill)

	var floor_disc := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.75
	disc.bottom_radius = 0.75
	disc.height = 0.02
	disc.radial_segments = 48
	floor_disc.mesh = disc
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = MenuStyle.SURFACE_ELEV
	disc_mat.roughness = 0.35
	floor_disc.material_override = disc_mat
	floor_disc.position = Vector3(0.0, -0.011, 0.0)
	_viewport.add_child(floor_disc)

	# The mannequin's origin IS the ice plane, so it sits on the disc unposed.
	_mannequin = LockerMannequin.new()
	_viewport.add_child(_mannequin)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", MenuStyle.TEXT_MUTED)
	_hint.add_theme_font_size_override("font_size", 11)
	add_child(_hint)

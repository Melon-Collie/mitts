class_name MenuIntro
extends Control

signal intro_finished

var _overlay_alpha: float = 1.0
var _stick_alpha: float = 0.0
var _puck_alpha: float = 0.0
var _flash_alpha: float = 0.0
var _spray: Array[Dictionary] = []
var _grip: Vector2 = Vector2.ZERO
var _shaft_angle: float = 0.0
var _puck: Vector2 = Vector2.ZERO
var _active: bool = true
var _tween: Tween = null

const _SHAFT_LEN: float = 280.0
const _BLADE_LEN: float = 68.0
const _SHAFT_ANGLE_ENTRY: float = 0.4887  # 28 degrees
const _BLADE_OFFSET_RAD: float = -0.6283  # blade is -36 degrees from shaft

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()
		_skip()
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		_skip()

func _skip() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_active = false
	_overlay_alpha = 0.0
	_stick_alpha = 0.0
	_puck_alpha = 0.0
	_flash_alpha = 0.0
	_spray.clear()
	queue_redraw()
	intro_finished.emit()

func _run() -> void:
	var sz: Vector2 = get_viewport_rect().size
	var px: float = sz.x
	var py: float = sz.y

	_puck = Vector2(px * 0.48, py * 0.52)
	_shaft_angle = _SHAFT_ANGLE_ENTRY

	var shaft_dir := Vector2(cos(_shaft_angle), sin(_shaft_angle))
	var blade_dir := Vector2(cos(_shaft_angle + _BLADE_OFFSET_RAD), sin(_shaft_angle + _BLADE_OFFSET_RAD))
	var grip_contact: Vector2 = _puck - blade_dir * _BLADE_LEN - shaft_dir * _SHAFT_LEN

	_grip = Vector2(-300.0, py * 0.35)
	var grip_windup: Vector2 = grip_contact + Vector2(-70.0, 15.0)
	var grip_follow: Vector2 = grip_contact + Vector2(55.0, -18.0)
	var puck_exit: Vector2 = Vector2(_puck.x + px * 0.27, _puck.y - py * 0.01)

	_tween = create_tween()

	# Brief black hold
	_tween.tween_interval(0.12)

	# Stick fades in
	_tween.tween_property(self, "_stick_alpha", 1.0, 0.18)

	# Stick slides into frame (wind-up position)
	_tween.tween_property(self, "_grip", grip_windup, 0.48) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Puck appears
	_tween.tween_property(self, "_puck_alpha", 1.0, 0.12)

	# Fast final swing into contact
	_tween.tween_property(self, "_grip", grip_contact, 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "_shaft_angle", _SHAFT_ANGLE_ENTRY - 0.105, 0.11)

	# Impact
	_tween.tween_callback(_fire_contact)

	# Puck shoots across screen, stick follows through
	_tween.tween_property(self, "_puck", puck_exit, 0.20) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "_grip", grip_follow, 0.22)
	_tween.parallel().tween_property(self, "_shaft_angle", _SHAFT_ANGLE_ENTRY - 0.175, 0.22)

	# Everything fades
	_tween.tween_property(self, "_stick_alpha", 0.0, 0.28)
	_tween.parallel().tween_property(self, "_puck_alpha", 0.0, 0.22)
	_tween.parallel().tween_property(self, "_flash_alpha", 0.0, 0.38)

	# Overlay fades, revealing menu underneath
	_tween.tween_interval(0.04)
	_tween.tween_property(self, "_overlay_alpha", 0.0, 0.52) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	_tween.tween_callback(func() -> void:
		_active = false
		intro_finished.emit())

func _fire_contact() -> void:
	_flash_alpha = 1.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i: int in 24:
		var ang: float = rng.randf_range(deg_to_rad(-75.0), deg_to_rad(10.0))
		var spd: float = rng.randf_range(70.0, 260.0)
		_spray.append({
			"pos": Vector2(_puck.x, _puck.y),
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": rng.randf_range(0.18, 0.62),
			"max_life": 0.62,
		})

func _process(delta: float) -> void:
	var i: int = _spray.size() - 1
	while i >= 0:
		_spray[i].life -= delta
		_spray[i].pos += _spray[i].vel * delta
		if _spray[i].life <= 0.0:
			_spray.remove_at(i)
		i -= 1
	if _active or not _spray.is_empty():
		queue_redraw()

func _draw() -> void:
	var sz: Vector2 = get_viewport_rect().size

	if _overlay_alpha > 0.001:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.0, 0.0, _overlay_alpha))

	if _flash_alpha > 0.001:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 1.0, 1.0, _flash_alpha * 0.20))

	for p: Dictionary in _spray:
		var a: float = clampf(p.life / p.max_life, 0.0, 1.0)
		draw_line(p.pos, p.pos - p.vel * 0.07, Color(0.88, 0.93, 1.0, a * 0.9), 2.0)

	if _puck_alpha > 0.001:
		draw_circle(_puck, 18.0, Color(0.12, 0.12, 0.16, _puck_alpha))
		draw_arc(_puck, 18.0, 0.0, TAU, 40, Color(0.38, 0.38, 0.45, _puck_alpha * 0.9), 2.5)

	if _stick_alpha > 0.001:
		_draw_stick()

func _draw_stick() -> void:
	var a: float = _stick_alpha
	var shaft_dir := Vector2(cos(_shaft_angle), sin(_shaft_angle))
	var heel: Vector2 = _grip + shaft_dir * _SHAFT_LEN
	var blade_angle: float = _shaft_angle + _BLADE_OFFSET_RAD
	var blade_dir := Vector2(cos(blade_angle), sin(blade_angle))
	var toe: Vector2 = heel + blade_dir * _BLADE_LEN
	var perp: Vector2 = shaft_dir.orthogonal()

	# Shaft (dark wood / carbon composite)
	draw_line(_grip, heel, Color(0.17, 0.10, 0.05, a), 10.0)
	draw_line(_grip + perp * 2.5, heel + perp * 2.5, Color(0.40, 0.25, 0.12, a * 0.45), 4.5)

	# Grip tape — black tape at top of shaft
	var grip_end: Vector2 = _grip + shaft_dir * 42.0
	draw_line(_grip, grip_end, Color(0.07, 0.07, 0.09, a), 11.5)
	for k: int in 3:
		var t0: Vector2 = _grip + shaft_dir * (8.0 + k * 11.0)
		var t1: Vector2 = t0 + shaft_dir * 5.0
		draw_line(t0, t1, Color(0.20, 0.20, 0.22, a * 0.55), 11.5)

	# Blade (dark composite)
	draw_line(heel, toe, Color(0.13, 0.13, 0.17, a), 13.0)
	# White tape over most of blade
	draw_line(heel.lerp(toe, 0.1), heel.lerp(toe, 0.9), Color(0.88, 0.88, 0.88, a * 0.62), 6.0)
	# Bottom edge highlight
	var blade_perp: Vector2 = blade_dir.orthogonal()
	draw_line(heel + blade_perp * 3.5, toe + blade_perp * 3.5,
		Color(0.50, 0.50, 0.60, a * 0.65), 2.0)

class_name MenuIntro
extends Control

signal intro_finished

var _overlay_alpha: float = 1.0
var _stick_alpha: float = 0.0
var _puck_alpha: float = 0.0
var _puck_radius: float = 72.0
var _flash_alpha: float = 0.0
var _shock_ring_radius: float = 0.0
var _shock_ring_alpha: float = 0.0
var _spray: Array[Dictionary] = []
var _grip: Vector2 = Vector2.ZERO
var _shaft_angle: float = 0.0
var _puck: Vector2 = Vector2.ZERO
var _active: bool = true
var _tween: Tween = null

const _SHAFT_LEN: float = 1120.0
const _BLADE_LEN: float = 272.0
const _PUCK_RADIUS_INIT: float = 72.0
const _SHAFT_ANGLE_ENTRY: float = 1.2217  # 70° — shaft points strongly downward
const _BLADE_OFFSET_RAD: float = -1.2217  # blade lies horizontal when shaft is at 70°

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
	_shock_ring_alpha = 0.0
	_spray.clear()
	queue_redraw()
	intro_finished.emit()

func _run() -> void:
	var sz: Vector2 = get_viewport_rect().size
	var px: float = sz.x
	var py: float = sz.y

	_puck = Vector2(px * 0.48, py * 0.52)
	_puck_radius = _PUCK_RADIUS_INIT
	_shaft_angle = _SHAFT_ANGLE_ENTRY

	var shaft_dir := Vector2(cos(_shaft_angle), sin(_shaft_angle))
	var blade_dir := Vector2(cos(_shaft_angle + _BLADE_OFFSET_RAD), sin(_shaft_angle + _BLADE_OFFSET_RAD))
	var grip_contact: Vector2 = _puck - blade_dir * _BLADE_LEN - shaft_dir * _SHAFT_LEN

	# Puck grows until it covers every corner from its final resting point (screen center)
	var screen_center := Vector2(px * 0.5, py * 0.5)
	var screen_fill_radius := screen_center.length() + 80.0

	# Grip starts well above the screen — blade descends from above onto the puck
	_grip = Vector2(grip_contact.x - 80.0, grip_contact.y - 700.0)
	var grip_windup: Vector2 = grip_contact + Vector2(-80.0, -250.0)
	# Follow-through continues downward, reinforcing the overhead/forward direction
	var grip_follow: Vector2 = grip_contact + Vector2(50.0, 80.0)

	_tween = create_tween()

	# Brief black hold
	_tween.tween_interval(0.12)

	# Stick fades in and slides into frame
	_tween.tween_property(self, "_stick_alpha", 1.0, 0.18)
	_tween.tween_property(self, "_grip", grip_windup, 0.48) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Puck appears
	_tween.tween_property(self, "_puck_alpha", 1.0, 0.12)

	# Fast final swing into contact
	_tween.tween_property(self, "_grip", grip_contact, 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Impact — _fire_contact pops the puck radius and spawns effects
	_tween.tween_callback(_fire_contact)

	# Puck rushes toward camera: expands from the popped radius to fill the screen,
	# center drifts to screen center (perspective — the puck is flying straight at you).
	# Shock ring bursts outward as a leading shockwave. Stick vanishes fast.
	_tween.tween_property(self, "_puck_radius", screen_fill_radius, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "_puck", screen_center, 0.30) \
		.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "_shock_ring_radius", sz.length() * 0.22, 0.28) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "_shock_ring_alpha", 0.0, 0.28)
	_tween.parallel().tween_property(self, "_grip", grip_follow, 0.18)
	_tween.parallel().tween_property(self, "_stick_alpha", 0.0, 0.15)
	_tween.parallel().tween_property(self, "_flash_alpha", 0.0, 0.15)

	# Puck has filled the screen — snap to solid overlay, retire the puck circle
	_tween.tween_callback(func() -> void:
		_overlay_alpha = 1.0
		_puck_alpha = 0.0
		queue_redraw())

	_tween.tween_interval(0.06)

	# Overlay fades out, revealing menu
	_tween.tween_property(self, "_overlay_alpha", 0.0, 0.52) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	_tween.tween_callback(func() -> void:
		_active = false
		intro_finished.emit())

func _fire_contact() -> void:
	_flash_alpha = 1.0
	# Immediate radius pop — establishes the toward-camera direction before the tween kicks in
	_puck_radius = 140.0
	_shock_ring_radius = 140.0
	_shock_ring_alpha = 0.90
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i: int in 28:
		var ang: float = rng.randf_range(deg_to_rad(-80.0), deg_to_rad(15.0))
		var spd: float = rng.randf_range(250.0, 900.0)
		_spray.append({
			"pos": Vector2(_puck.x, _puck.y),
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": rng.randf_range(0.15, 0.50),
			"max_life": 0.50,
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
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 1.0, 1.0, _flash_alpha * 0.30))

	# Shock ring — expands fast ahead of the puck edge, clear radial motion cue
	if _shock_ring_alpha > 0.001:
		draw_arc(_puck, _shock_ring_radius, 0.0, TAU, 80,
			Color(0.88, 0.94, 1.0, _shock_ring_alpha), 7.0)

	# Puck — solid dark disk that grows to fill the screen
	if _puck_alpha > 0.001:
		draw_circle(_puck, _puck_radius, Color(0.10, 0.10, 0.14, _puck_alpha))
		if _puck_radius < 160.0:
			draw_arc(_puck, _puck_radius, 0.0, TAU, 64,
				Color(0.38, 0.38, 0.50, _puck_alpha * 0.85), 10.0)

	# Spray on top of puck — ice sparks visible against the dark expanding surface
	for p: Dictionary in _spray:
		var a: float = clampf(p.life / p.max_life, 0.0, 1.0)
		draw_line(p.pos, p.pos - p.vel * 0.06, Color(0.88, 0.93, 1.0, a * 0.85), 3.0)

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
	var blade_perp: Vector2 = blade_dir.orthogonal()

	const SHAFT_HW: float = 22.0   # shaft half-width
	const BLADE_HW: float = 28.0   # blade half-height (top-down)

	# ── SHAFT BODY ──────────────────────────────────────────────────────────────
	# Solid polygon gives a proper rectangular cross-section
	draw_colored_polygon(PackedVector2Array([
		_grip + perp * SHAFT_HW,
		_grip - perp * SHAFT_HW,
		heel - perp * SHAFT_HW,
		heel + perp * SHAFT_HW,
	]), Color(0.20, 0.12, 0.05, a))

	# Shadow edge (far side from light)
	draw_line(_grip - perp * SHAFT_HW, heel - perp * SHAFT_HW,
		Color(0.07, 0.04, 0.02, a * 0.95), 8.0)

	# Highlight edge (near side)
	draw_line(_grip + perp * SHAFT_HW, heel + perp * SHAFT_HW,
		Color(0.48, 0.31, 0.15, a * 0.75), 9.0)

	# Specular strip near highlight edge — gives the shaft a rounded feel
	draw_line(_grip + perp * (SHAFT_HW - 7.0), heel + perp * (SHAFT_HW - 7.0),
		Color(0.72, 0.54, 0.32, a * 0.30), 4.0)

	# Subtle wood grain lines along the shaft axis
	for k: int in 4:
		var g_off: float = -14.0 + k * 9.0
		draw_line(_grip + perp * g_off + shaft_dir * 50.0,
			heel + perp * g_off,
			Color(0.14, 0.08, 0.03, a * 0.12), 1.5)

	# ── GRIP TAPE ───────────────────────────────────────────────────────────────
	var grip_tape_end: Vector2 = _grip + shaft_dir * 168.0
	draw_colored_polygon(PackedVector2Array([
		_grip + perp * (SHAFT_HW + 3.0),
		_grip - perp * (SHAFT_HW + 3.0),
		grip_tape_end - perp * (SHAFT_HW + 3.0),
		grip_tape_end + perp * (SHAFT_HW + 3.0),
	]), Color(0.07, 0.07, 0.09, a))

	# Tape highlight stripe along the lit edge
	draw_line(_grip + perp * (SHAFT_HW + 2.0), grip_tape_end + perp * (SHAFT_HW + 2.0),
		Color(0.25, 0.25, 0.30, a * 0.55), 6.0)

	# Cross-wrap texture: thin lines perpendicular to shaft axis
	var t_pos: float = 16.0
	while t_pos < 162.0:
		var t0: Vector2 = _grip + shaft_dir * t_pos
		draw_line(t0 + perp * (SHAFT_HW + 3.0), t0 - perp * (SHAFT_HW + 3.0),
			Color(0.14, 0.14, 0.16, a * 0.55), 3.0)
		t_pos += 22.0

	# Butt cap — widened end knob at the grip
	draw_circle(_grip, SHAFT_HW + 9.0, Color(0.10, 0.10, 0.13, a))
	draw_arc(_grip, SHAFT_HW + 9.0, 0.0, TAU, 32,
		Color(0.30, 0.30, 0.38, a * 0.65), 4.0)

	# ── HEEL CONNECTOR ──────────────────────────────────────────────────────────
	draw_circle(heel, SHAFT_HW - 2.0, Color(0.15, 0.10, 0.05, a))

	# ── BLADE BODY ──────────────────────────────────────────────────────────────
	draw_colored_polygon(PackedVector2Array([
		heel + blade_perp * BLADE_HW,
		heel - blade_perp * BLADE_HW,
		toe - blade_perp * BLADE_HW,
		toe + blade_perp * BLADE_HW,
	]), Color(0.11, 0.11, 0.15, a))

	# White tape across the blade face
	var btape_s: Vector2 = heel.lerp(toe, 0.05)
	var btape_e: Vector2 = heel.lerp(toe, 0.96)
	draw_colored_polygon(PackedVector2Array([
		btape_s + blade_perp * (BLADE_HW - 5.0),
		btape_s - blade_perp * (BLADE_HW - 5.0),
		btape_e - blade_perp * (BLADE_HW - 5.0),
		btape_e + blade_perp * (BLADE_HW - 5.0),
	]), Color(0.86, 0.86, 0.86, a * 0.72))

	# Blade shadow edge (bottom/trailing side)
	draw_line(heel - blade_perp * BLADE_HW, toe - blade_perp * BLADE_HW,
		Color(0.30, 0.30, 0.42, a * 0.88), 4.5)

	# Blade highlight edge (top/leading side)
	draw_line(heel + blade_perp * BLADE_HW, toe + blade_perp * BLADE_HW,
		Color(0.55, 0.55, 0.68, a * 0.65), 3.5)

	# Toe cap — rounded end of blade
	draw_circle(toe, BLADE_HW - 4.0, Color(0.11, 0.11, 0.15, a))

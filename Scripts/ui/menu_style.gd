class_name MenuStyle

# ── Palette ───────────────────────────────────────────────────────────────────
# Change these to retheme the entire UI.

# Ice-blue accent family
const ICE         := Color(0.60, 0.82, 1.00, 1.00)   # bright ice (hover border, pressed text)
const ICE_MID     := Color(0.40, 0.62, 0.85, 0.80)   # normal button border
const ICE_DIM     := Color(0.35, 0.55, 0.78, 0.55)   # panel border, subtle accents
const ICE_HOVER   := Color(0.62, 0.84, 1.00, 0.95)   # hover border

# Text
const TEXT_TITLE  := Color(0.88, 0.95, 1.00, 1.00)   # heading / primary label
const TEXT_BODY   := Color(1.00, 1.00, 1.00, 1.00)   # pure white body text
const TEXT_DIM    := Color(0.55, 0.62, 0.72, 1.00)   # secondary / disabled label
const TEXT_SEP    := Color(0.28, 0.32, 0.45, 1.00)   # separator line

# Surfaces
const PANEL_BG    := Color(0.10, 0.10, 0.14, 0.88)   # overlay / popup panel background
const HUD_BG      := Color(0.07, 0.07, 0.09, 0.92)   # in-game scorebug / HUD chrome

# Button fill states
const BTN_FILL    := Color(0.10, 0.14, 0.22, 0.80)
const BTN_HOVER   := Color(0.14, 0.20, 0.34, 0.92)
const BTN_PRESS   := Color(0.07, 0.10, 0.18, 1.00)

# Non-blue accents (keep these for specific in-game uses)
const GOLD        := Color(1.00, 0.85, 0.20, 1.00)   # game-over "GAME OVER" heading


# ── Factories ─────────────────────────────────────────────────────────────────

static func panel(corner: int = 6, margin: int = 32) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.set_corner_radius_all(corner)
	s.set_content_margin_all(margin)
	s.border_color = ICE_DIM
	s.set_border_width_all(1)
	return s

static func apply_button(btn: Button) -> void:
	btn.add_theme_color_override("font_color",          TEXT_TITLE)
	btn.add_theme_color_override("font_hover_color",    TEXT_BODY)
	btn.add_theme_color_override("font_pressed_color",  ICE)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)

	var normal := StyleBoxFlat.new()
	normal.bg_color = BTN_FILL
	normal.set_corner_radius_all(6)
	normal.border_color = ICE_MID
	normal.set_border_width_all(1)
	normal.set_content_margin_all(10)

	var hover := StyleBoxFlat.new()
	hover.bg_color = BTN_HOVER
	hover.set_corner_radius_all(6)
	hover.border_color = ICE_HOVER
	hover.set_border_width_all(2)
	hover.set_content_margin_all(10)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = BTN_PRESS
	pressed.set_corner_radius_all(6)
	pressed.border_color = ICE_MID
	pressed.set_border_width_all(1)
	pressed.set_content_margin_all(10)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(BTN_FILL.r, BTN_FILL.g, BTN_FILL.b, 0.40)
	disabled.set_corner_radius_all(6)
	disabled.border_color = Color(ICE_DIM.r, ICE_DIM.g, ICE_DIM.b, 0.28)
	disabled.set_border_width_all(1)
	disabled.set_content_margin_all(10)

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed)
	btn.add_theme_stylebox_override("focus",    hover)
	btn.add_theme_stylebox_override("disabled", disabled)

static func close_button() -> Button:
	var btn := Button.new()
	btn.text = "×"
	btn.flat = true
	btn.custom_minimum_size = Vector2(30, 30)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color",         TEXT_DIM)
	btn.add_theme_color_override("font_hover_color",   TEXT_BODY)
	btn.add_theme_color_override("font_pressed_color", ICE)
	var empty := StyleBoxEmpty.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(BTN_HOVER.r, BTN_HOVER.g, BTN_HOVER.b, 0.65)
	hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal",  empty)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus",   empty)
	return btn

static func apply_tab_button(btn: Button, active: bool) -> void:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	s.set_content_margin(SIDE_LEFT,  16)
	s.set_content_margin(SIDE_RIGHT, 16)
	s.set_content_margin(SIDE_TOP,   8)
	s.set_content_margin(SIDE_BOTTOM, 8)
	s.bg_color = Color(BTN_HOVER.r, BTN_HOVER.g, BTN_HOVER.b, 1.0) if active \
		else Color(0.0, 0.0, 0.0, 0.0)
	if active:
		s.border_color = ICE_MID
		s.set_border_width_all(0)
		s.border_width_bottom = 2
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color",       TEXT_BODY  if active else TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", TEXT_BODY)

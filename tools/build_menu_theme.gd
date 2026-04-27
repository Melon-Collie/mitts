@tool
extends EditorScript

# Run this script (File → Run, Ctrl+Shift+X) to (re)generate Resources/MenuTheme.tres
# from the MenuStyle palette. After running, set the resource as the project's
# default theme: Project Settings → General → GUI → Theme → Custom.
#
# All styling is derived from MenuStyle constants so the generated theme is
# byte-equivalent to what MenuStyle.apply_* used to produce at runtime.

const _OUT_PATH: String = "res://Resources/MenuTheme.tres"


func _run() -> void:
	var theme: Theme = _build_theme()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Resources"))
	var err: int = ResourceSaver.save(theme, _OUT_PATH)
	if err != OK:
		push_error("Failed to save theme: %d" % err)
		return
	print("Wrote ", _OUT_PATH)
	print("Now set Project Settings → General → GUI → Theme → Custom = ", _OUT_PATH)


func _build_theme() -> Theme:
	var theme := Theme.new()
	_apply_button_type(theme, "Button")
	_apply_button_type(theme, "OptionButton")
	_apply_line_edit(theme)
	_apply_spin_box(theme)
	_apply_h_slider(theme)
	_apply_panel_container(theme)
	_apply_toggle_variation(theme)
	_apply_tab_inactive_variation(theme)
	_apply_tab_active_variation(theme)
	return theme


# ── Type entries ─────────────────────────────────────────────────────────────

func _apply_button_type(theme: Theme, type: String) -> void:
	theme.set_color("font_color",          type, MenuStyle.TEXT_TITLE)
	theme.set_color("font_hover_color",    type, MenuStyle.TEXT_BODY)
	theme.set_color("font_pressed_color",  type, MenuStyle.ICE)
	theme.set_color("font_disabled_color", type, MenuStyle.TEXT_DIM)
	theme.set_stylebox("normal",   type, _btn_box(MenuStyle.BTN_FILL,  MenuStyle.ICE_MID,   1))
	theme.set_stylebox("hover",    type, _btn_box(MenuStyle.BTN_HOVER, MenuStyle.ICE_HOVER, 2))
	theme.set_stylebox("pressed",  type, _btn_box(MenuStyle.BTN_PRESS, MenuStyle.ICE_MID,   1))
	theme.set_stylebox("focus",    type, _btn_box(MenuStyle.BTN_HOVER, MenuStyle.ICE_HOVER, 2))
	theme.set_stylebox("disabled", type, _btn_box(
		Color(MenuStyle.BTN_FILL.r, MenuStyle.BTN_FILL.g, MenuStyle.BTN_FILL.b, 0.40),
		Color(MenuStyle.ICE_DIM.r,  MenuStyle.ICE_DIM.g,  MenuStyle.ICE_DIM.b,  0.28),
		1))


func _apply_line_edit(theme: Theme) -> void:
	const TYPE: String = "LineEdit"
	theme.set_color("font_color",             TYPE, MenuStyle.TEXT_BODY)
	theme.set_color("font_placeholder_color", TYPE, MenuStyle.TEXT_DIM)
	theme.set_color("caret_color",            TYPE, MenuStyle.ICE)
	theme.set_color("selection_color",        TYPE,
		Color(MenuStyle.ICE_MID.r, MenuStyle.ICE_MID.g, MenuStyle.ICE_MID.b, 0.35))
	theme.set_stylebox("normal",    TYPE, _btn_box(MenuStyle.BTN_FILL, MenuStyle.ICE_DIM,   1))
	theme.set_stylebox("focus",     TYPE, _btn_box(MenuStyle.BTN_FILL, MenuStyle.ICE_HOVER, 2))
	theme.set_stylebox("read_only", TYPE, _btn_box(MenuStyle.BTN_FILL, MenuStyle.ICE_DIM,   1))


func _apply_spin_box(theme: Theme) -> void:
	# SpinBox renders as a LineEdit with up/down arrows. Mirror the LineEdit look
	# so spin boxes match the rest of the inputs.
	const TYPE: String = "SpinBox"
	theme.set_color("font_color", TYPE, MenuStyle.TEXT_BODY)


func _apply_h_slider(theme: Theme) -> void:
	const TYPE: String = "HSlider"
	var track := StyleBoxFlat.new()
	track.bg_color = MenuStyle.BTN_FILL
	track.set_corner_radius_all(3)
	track.border_color = MenuStyle.ICE_DIM
	track.set_border_width_all(1)
	track.set_content_margin(SIDE_TOP, 3)
	track.set_content_margin(SIDE_BOTTOM, 3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(MenuStyle.ICE_MID.r, MenuStyle.ICE_MID.g, MenuStyle.ICE_MID.b, 0.65)
	fill.set_corner_radius_all(3)
	fill.set_content_margin(SIDE_TOP, 3)
	fill.set_content_margin(SIDE_BOTTOM, 3)
	theme.set_stylebox("slider",                 TYPE, track)
	theme.set_stylebox("grabber_area",           TYPE, fill)
	theme.set_stylebox("grabber_area_highlight", TYPE, fill)


func _apply_panel_container(theme: Theme) -> void:
	# Default PanelContainer panel — matches MenuStyle.panel() defaults (corner=6, margin=32).
	# PanelContainers that need other dimensions (popups, cards) still call MenuStyle.panel().
	const TYPE: String = "PanelContainer"
	var s := StyleBoxFlat.new()
	s.bg_color = MenuStyle.PANEL_BG
	s.set_corner_radius_all(6)
	s.set_content_margin_all(32)
	s.border_color = MenuStyle.ICE_DIM
	s.set_border_width_all(1)
	theme.set_stylebox("panel", TYPE, s)


# ── Type variations ──────────────────────────────────────────────────────────

func _apply_toggle_variation(theme: Theme) -> void:
	const TYPE: StringName = &"ToggleButton"
	theme.set_type_variation(TYPE, &"Button")
	theme.set_color("font_color",          TYPE, MenuStyle.TEXT_DIM)
	theme.set_color("font_hover_color",    TYPE, MenuStyle.TEXT_BODY)
	theme.set_color("font_pressed_color",  TYPE, MenuStyle.ICE)
	theme.set_color("font_disabled_color", TYPE, MenuStyle.TEXT_DIM)
	var off       := _btn_box(MenuStyle.BTN_FILL,  MenuStyle.ICE_DIM,   1)
	var off_hover := _btn_box(MenuStyle.BTN_HOVER, MenuStyle.ICE_MID,   1)
	var on        := _btn_box(Color(0.10, 0.22, 0.38, 0.90), MenuStyle.ICE,       2)
	var on_hover  := _btn_box(Color(0.14, 0.28, 0.46, 0.95), MenuStyle.ICE_HOVER, 2)
	theme.set_stylebox("normal",        TYPE, off)
	theme.set_stylebox("hover",         TYPE, off_hover)
	theme.set_stylebox("pressed",       TYPE, on)
	theme.set_stylebox("hover_pressed", TYPE, on_hover)
	theme.set_stylebox("focus",         TYPE, off_hover)
	theme.set_stylebox("disabled",      TYPE, off)


func _apply_tab_inactive_variation(theme: Theme) -> void:
	const TYPE: StringName = &"TabButton"
	theme.set_type_variation(TYPE, &"Button")
	theme.set_color("font_color",       TYPE, MenuStyle.TEXT_DIM)
	theme.set_color("font_hover_color", TYPE, MenuStyle.TEXT_BODY)
	var s := _tab_box(false)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		theme.set_stylebox(state, TYPE, s)


func _apply_tab_active_variation(theme: Theme) -> void:
	const TYPE: StringName = &"TabButtonActive"
	theme.set_type_variation(TYPE, &"Button")
	theme.set_color("font_color",       TYPE, MenuStyle.TEXT_BODY)
	theme.set_color("font_hover_color", TYPE, MenuStyle.TEXT_BODY)
	var s := _tab_box(true)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		theme.set_stylebox(state, TYPE, s)


# ── Stylebox factories ───────────────────────────────────────────────────────

func _btn_box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_content_margin_all(10)
	return s


func _tab_box(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(0)
	s.set_content_margin(SIDE_LEFT,   16)
	s.set_content_margin(SIDE_RIGHT,  16)
	s.set_content_margin(SIDE_TOP,    8)
	s.set_content_margin(SIDE_BOTTOM, 8)
	s.bg_color = Color(MenuStyle.BTN_HOVER.r, MenuStyle.BTN_HOVER.g, MenuStyle.BTN_HOVER.b, 1.0) \
		if active else Color(0.0, 0.0, 0.0, 0.0)
	if active:
		s.border_color = MenuStyle.ICE_MID
		s.set_border_width_all(0)
		s.border_width_bottom = 2
	return s

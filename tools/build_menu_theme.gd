@tool
extends EditorScript

# Run this script (File → Run, Ctrl+Shift+X) to (re)generate Resources/MenuTheme.tres
# from the MenuStyle palette. After running, set the resource as the project's
# default theme: Project Settings → General → GUI → Theme → Custom.

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
	_apply_h_slider(theme)
	_apply_check_button(theme)
	_apply_panel_container(theme)
	_apply_popup_menu(theme)
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
	# Circular grabber knob — a procedural ice-blue dot with a darker rim.
	theme.set_icon("grabber",           TYPE, _circle_icon(16, MenuStyle.ICE,       MenuStyle.BTN_PRESS))
	theme.set_icon("grabber_highlight", TYPE, _circle_icon(18, MenuStyle.ICE_HOVER, MenuStyle.BTN_PRESS))
	theme.set_icon("grabber_disabled",  TYPE, _circle_icon(16, MenuStyle.TEXT_DIM,  MenuStyle.BTN_PRESS))


func _apply_check_button(theme: Theme) -> void:
	# CheckButton is a slide-switch — show the native switch icon and label,
	# but don't draw a heavy Button-style box around the whole thing.
	const TYPE: String = "CheckButton"
	theme.set_color("font_color",          TYPE, MenuStyle.TEXT_BODY)
	theme.set_color("font_hover_color",    TYPE, MenuStyle.TEXT_TITLE)
	theme.set_color("font_pressed_color",  TYPE, MenuStyle.ICE)
	theme.set_color("font_disabled_color", TYPE, MenuStyle.TEXT_DIM)
	var empty := StyleBoxEmpty.new()
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		theme.set_stylebox(state, TYPE, empty)


func _apply_panel_container(theme: Theme) -> void:
	const TYPE: String = "PanelContainer"
	var s := StyleBoxFlat.new()
	s.bg_color = MenuStyle.PANEL_BG
	s.set_corner_radius_all(6)
	s.set_content_margin_all(32)
	s.border_color = MenuStyle.ICE_DIM
	s.set_border_width_all(1)
	theme.set_stylebox("panel", TYPE, s)


func _apply_popup_menu(theme: Theme) -> void:
	# Styles the dropdown that appears when an OptionButton is opened.
	const TYPE: String = "PopupMenu"
	theme.set_color("font_color",           TYPE, MenuStyle.TEXT_BODY)
	theme.set_color("font_hover_color",     TYPE, MenuStyle.ICE)
	theme.set_color("font_disabled_color",  TYPE, MenuStyle.TEXT_DIM)
	theme.set_color("font_separator_color", TYPE, MenuStyle.TEXT_SEP)
	theme.set_constant("h_separation", TYPE, 8)
	theme.set_constant("v_separation", TYPE, 4)
	var panel := StyleBoxFlat.new()
	panel.bg_color = MenuStyle.PANEL_BG
	panel.set_corner_radius_all(4)
	panel.border_color = MenuStyle.ICE_DIM
	panel.set_border_width_all(1)
	panel.set_content_margin_all(6)
	theme.set_stylebox("panel", TYPE, panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color = MenuStyle.BTN_HOVER
	hover.set_corner_radius_all(3)
	hover.set_content_margin(SIDE_LEFT,  6)
	hover.set_content_margin(SIDE_RIGHT, 6)
	theme.set_stylebox("hover", TYPE, hover)
	var sep := StyleBoxFlat.new()
	sep.bg_color = MenuStyle.TEXT_SEP
	sep.set_content_margin(SIDE_TOP,    1)
	sep.set_content_margin(SIDE_BOTTOM, 1)
	theme.set_stylebox("separator", TYPE, sep)


# ── Type variations ──────────────────────────────────────────────────────────

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


# ── Stylebox / icon factories ────────────────────────────────────────────────

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


# Antialiased filled circle with a 1-pixel rim — used for slider grabbers.
func _circle_icon(diameter: int, fill: Color, rim: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(diameter * 0.5 - 0.5, diameter * 0.5 - 0.5)
	var outer: float = diameter * 0.5
	var inner: float = outer - 1.5
	for y: int in diameter:
		for x: int in diameter:
			var d: float = Vector2(x, y).distance_to(center)
			if d <= inner - 0.5:
				img.set_pixel(x, y, fill)
			elif d <= inner + 0.5:
				var t: float = clampf(inner + 0.5 - d, 0.0, 1.0)
				img.set_pixel(x, y, fill.lerp(rim, 1.0 - t))
			elif d <= outer - 0.5:
				img.set_pixel(x, y, rim)
			elif d <= outer:
				var t: float = clampf(outer - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(rim.r, rim.g, rim.b, rim.a * t))
	return ImageTexture.create_from_image(img)

class_name PlayerSettingsPopup
extends Control

# The player screen: who you are and everything you skate with, one region at a
# time around a live mannequin — YOU (name, number, hand, seat, team), BODY,
# HEAD, STICK and SKATES. A region's rows are in the order the piece reads, with
# a gold asterisk on each pick that changes play; beside them a stat panel shows
# what the whole build does, with the stats the current region can move lit.
#
# Edits land in a PlayerDraft copy; Apply commits what differs from the draft
# the screen opened with (PlayerDraft.commit), Cancel / Esc / an overlay click
# drop it.

signal name_changed(new_name: String)
signal jersey_number_changed(new_number: int)
signal handedness_changed(is_left: bool)
signal position_changed(position: int)
signal preferred_color_changed(color_slot: int)

enum Region { YOU, BODY, HEAD, STICK, SKATES }

const _REGION_KEYS: Array[StringName] = [&"PLAYER_REGION_YOU", &"PLAYER_REGION_BODY",
		&"PLAYER_REGION_HEAD", &"PLAYER_REGION_STICK", &"PLAYER_REGION_SKATES"]
const _REGION_NOTE_KEYS: Array[StringName] = [&"STAT_NOTE_YOU", &"STAT_NOTE_BODY",
		&"STAT_NOTE_HEAD", &"STAT_NOTE_STICK", &"STAT_NOTE_SKATES"]
# The shot the case cuts to on landing in a region.
const _REGION_FOCUS: Array[int] = [LockerMannequin.Focus.FULL, LockerMannequin.Focus.FULL,
		LockerMannequin.Focus.HELMET, LockerMannequin.Focus.STICK, LockerMannequin.Focus.SKATES]

# Position buttons in rink order (wings around the C) → PlayerRules.POSITION_NAMES
# index, with the badge and full-name keys in lockstep.
const _POSITION_ORDER: Array[int] = [1, 0, 2, 3, 4]
const _POSITION_BADGE_KEYS: Array[StringName] = [
	&"POS_BADGE_LW", &"POS_BADGE_C", &"POS_BADGE_RW", &"POS_BADGE_LD", &"POS_BADGE_RD"]
const _POSITION_KEYS: Array[StringName] = [
	&"POSITION_LW", &"POSITION_C", &"POSITION_RW", &"POSITION_LD", &"POSITION_RD"]

const _PROFILE_KEYS: Array[StringName] = [
	&"GEAR_PROFILE_SHIFTY", &"GEAR_PROFILE_STABILITY", &"GEAR_PROFILE_POWER"]
const _PROFILE_HINTS: Array[StringName] = [
	&"HINT_PROFILE_SHIFTY", &"HINT_PROFILE_STABILITY", &"HINT_PROFILE_POWER"]
const _LENGTH_KEYS: Array[StringName] = [
	&"STICK_LENGTH_SHORT", &"STICK_LENGTH_STANDARD", &"STICK_LENGTH_LONG"]
const _LENGTH_HINTS: Array[StringName] = [
	&"HINT_LENGTH_SHORT", &"HINT_LENGTH_STANDARD", &"HINT_LENGTH_LONG"]
const _CURVE_KEYS: Array[StringName] = [
	&"STICK_CURVE_M88", &"STICK_CURVE_M92", &"STICK_CURVE_M28"]
const _CURVE_HINTS: Array[StringName] = [
	&"HINT_CURVE_M88", &"HINT_CURVE_M92", &"HINT_CURVE_M28"]
const _FLEX_KEYS: Array[StringName] = [
	&"STICK_FLEX_WHIPPY", &"STICK_FLEX_MEDIUM", &"STICK_FLEX_STIFF"]
const _FLEX_HINTS: Array[StringName] = [
	&"HINT_FLEX_WHIPPY", &"HINT_FLEX_MEDIUM", &"HINT_FLEX_STIFF"]
const _FRAME_KEYS: Array[StringName] = [
	&"FRAME_LEAN", &"FRAME_LIGHT", &"FRAME_MEDIUM", &"FRAME_SOLID", &"FRAME_HEAVY"]

const _SPAN_OPTIONS: Array[int] = [
	StickTapeConfig.Span.FULL, StickTapeConfig.Span.HEEL_TO_MID,
	StickTapeConfig.Span.MID_TO_TOE, StickTapeConfig.Span.MID,
	StickTapeConfig.Span.TOE, StickTapeConfig.Span.NONE,
]
const _SPAN_KEYS: Array[StringName] = [
	&"TAPE_SPAN_FULL", &"TAPE_SPAN_HEEL_TO_MID", &"TAPE_SPAN_MID_TO_TOE",
	&"TAPE_SPAN_MID", &"TAPE_SPAN_TOE", &"TAPE_SPAN_NONE",
]
const _STYLE_OPTIONS: Array[int] = [
	StickTapeConfig.KnobStyle.KNOB, StickTapeConfig.KnobStyle.CANDY_CANE,
	StickTapeConfig.KnobStyle.FULL,
]
const _STYLE_KEYS: Array[StringName] = [
	&"TAPE_HANDLE_KNOB", &"TAPE_HANDLE_CANDY", &"TAPE_HANDLE_FULL",
]

# Tall enough for the stick, the longest region, so switching never resizes the
# panel.
const _ROWS_MIN_H: float = 540.0

var _draft: PlayerDraft = PlayerDraft.new()
var _saved: PlayerDraft = PlayerDraft.new()
var _region: int = Region.YOU
var _name_valid: bool = true
var _number_valid: bool = true
# Guards _refresh(): assigning the weight slider's bounds can re-clamp its value
# and emit value_changed (Range.set_min/set_max route through set_value, which
# set_value_no_signal does not silence), and that reentrant handler would
# clobber the pending weight with a band-clamped one.
var _refreshing: bool = false
# The team the model rows' swatches and the tape palettes were last painted
# against — they repaint only when it changes.
var _painted_slot: int = -1

# Chrome.
var _case: PlayerCase = null
var _stats: BuildStatPanel = null
var _pages: Array[VBoxContainer] = []
var _tab_btns: Array[Button] = []
var _tab_stars: Array[Label] = []
var _emphasis: Array[Array] = []
var _pending_label: Label = null
var _apply_btn: Button = null
var _keyboard: ControllerKeyboard = null
# The region being built, so a starred row can star its tab.
var _building: int = Region.YOU
var _tab_gameplay: Array[bool] = [false, false, false, false, false]

# YOU.
var _name_field: LineEdit = null
var _name_warning: Label = null
var _number_field: LineEdit = null
var _number_warning: Label = null
var _shoots_btns: Array[Button] = []
var _position_btns: Array[Button] = []
var _color_dropdown: PaletteDropdown = null
# BODY.
var _height_slider: HSlider = null
var _height_value: Label = null
var _weight_slider: HSlider = null
var _weight_value: Label = null
var _weight_hint: Label = null
var _skin_buttons: Array[Button] = []
var _glove_btn: OptionButton = null
var _tuck_btn: OptionButton = null
# HEAD.
var _hair_btn: OptionButton = null
var _facial_btn: OptionButton = null
var _hair_color_buttons: Array[Button] = []
var _face_btns: Array[Button] = []
# STICK and SKATES — the gear dials are _GearRow records.
var _gear_rows: Array[_GearRow] = []
var _flex_row: _GearRow = null
var _stick_model_btn: OptionButton = null
var _blade_color_dd: SwatchDropdown = null
var _span_btn: OptionButton = null
var _knob_color_dd: SwatchDropdown = null
var _style_btn: OptionButton = null
var _skate_btn: OptionButton = null
var _lace_dd: SwatchDropdown = null


# One three-way gear dial: its buttons, the draft field it sets, and the hint
# naming what each option does.
class _GearRow:
	var field: StringName
	var buttons: Array[Button] = []
	var hint: Label = null
	var hint_keys: Array[StringName] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var focus_theme: Theme = MenuStyle.controller_focus_theme()
	if focus_theme != null:
		theme = focus_theme
	_build()
	_keyboard = ControllerKeyboard.new()
	_keyboard.submitted.connect(_on_keyboard_submitted)
	_keyboard.cancelled.connect(func() -> void: ControllerNav.grab_focus(_name_field))
	add_child(_keyboard)
	visible = false


func open() -> void:
	_saved = PlayerDraft.from_prefs()
	_draft = _saved.copy()
	_painted_slot = -1
	_sync_text_fields()
	_refresh()
	_update_apply_state()
	_show_region(Region.YOU)
	_case.settle(LockerMannequin.Focus.FULL)
	visible = true
	ControllerNav.focus_first(_pages[_region])  # take focus off the side menu behind


# ── Input ────────────────────────────────────────────────────────────────────

# Controller extras, all ahead of the GUI: LB / RB walk the regions; the number
# is a D-pad stepper; the name opens the on-screen keyboard on A. ui_cancel
# stays in _unhandled_input.
func _input(event: InputEvent) -> void:
	if not visible or _keyboard.visible:
		return
	var tab: int = ControllerNav.bumper_tab_delta(event)
	if tab != 0:
		_show_region((_region + tab + Region.size()) % Region.size())
		ControllerNav.focus_first(_pages[_region])
		get_viewport().set_input_as_handled()
		return
	if not ControllerNav.active():
		return
	if _number_field.has_focus():
		if event.is_action_pressed(&"ui_left"):
			_step_number(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"ui_right"):
			_step_number(1)
			get_viewport().set_input_as_handled()
	elif _name_field.has_focus() and event.is_action_pressed(&"ui_accept"):
		# `self` as the background: the key grid covers this form, and focus has
		# to stay on the grid until it's dismissed.
		_keyboard.open(_name_field.text, _name_field.max_length, self)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


func _on_overlay_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_cancel()


func _step_number(delta: int) -> void:
	_number_field.text = str(clampi(_number_field.text.to_int() + delta, 0, 99))
	_on_number_text_changed(_number_field.text)  # a programmatic set doesn't emit


func _on_keyboard_submitted(text: String) -> void:
	_name_field.text = text
	_on_name_text_changed(text)  # a programmatic set doesn't emit
	ControllerNav.grab_focus(_name_field)


# ── Construction ─────────────────────────────────────────────────────────────

func _build() -> void:
	# Setting a slider's bounds fires its handler before the rows below exist.
	_refreshing = true
	var overlay := ColorRect.new()
	overlay.color = MenuStyle.SCRIM
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_clicked)
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(6, 24))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 28)
	vbox.add_child(header)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	vbox.add_child(body)
	# The case first: every row's hover hands it a framing.
	_case = PlayerCase.new()
	_case.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(_case)

	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(0, _ROWS_MIN_H)
	body.add_child(rows)
	for r: int in Region.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 12)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rows.add_child(page)
		_pages.append(page)
		_emphasis.append([])
	_building = Region.YOU
	_build_you(_pages[Region.YOU])
	_building = Region.BODY
	_build_body(_pages[Region.BODY])
	_building = Region.HEAD
	_build_head(_pages[Region.HEAD])
	_building = Region.STICK
	_build_stick(_pages[Region.STICK])
	_building = Region.SKATES
	_build_skates(_pages[Region.SKATES])
	var legend := Label.new()
	legend.text = tr(&"STICK_GAMEPLAY_LEGEND")
	legend.add_theme_color_override("font_color", MenuStyle.GOLD)
	legend.add_theme_font_size_override("font_size", 13)
	rows.add_child(legend)

	_stats = BuildStatPanel.new()
	_stats.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(_stats)

	_build_header(header)
	_build_footer(vbox)
	_emphasis[Region.BODY] = BuildReadout.moved_by(
			[BuildReadout.Dial.HEIGHT, BuildReadout.Dial.WEIGHT])
	_emphasis[Region.STICK] = BuildReadout.moved_by([BuildReadout.Dial.LENGTH,
			BuildReadout.Dial.CURVE, BuildReadout.Dial.FLEX])
	_emphasis[Region.SKATES] = BuildReadout.moved_by([BuildReadout.Dial.PROFILE])
	_refreshing = false


func _build_header(header: HBoxContainer) -> void:
	var title := Label.new()
	title.text = tr(&"PLAYER_TITLE")
	MenuStyle.apply_heading(title)
	header.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	header.add_child(tabs)
	for r: int in Region.size():
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		tabs.add_child(cell)
		var btn := Button.new()
		btn.text = tr(_REGION_KEYS[r])
		btn.custom_minimum_size = Vector2(0, 44)
		btn.add_theme_font_size_override("font_size", 18)
		MenuStyle.apply_focus_ring(btn)
		SoundManager.wire_button(btn)
		btn.pressed.connect(_show_region.bind(r))
		cell.add_child(btn)
		_tab_btns.append(btn)
		var star: Label = PlayerRowKit.star()
		star.visible = false
		cell.add_child(star)
		_tab_stars.append(star)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_btn := MenuStyle.close_button()
	close_btn.pressed.connect(_cancel)
	SoundManager.wire_button(close_btn)
	header.add_child(close_btn)
	for r: int in Region.size():
		_tab_stars[r].visible = _tab_gameplay[r]


func _build_footer(vbox: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	_pending_label = Label.new()
	_pending_label.text = tr(&"EDIT_PENDING_NOTE")
	_pending_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pending_label.add_theme_color_override("font_color", MenuStyle.GOLD)
	_pending_label.add_theme_font_size_override("font_size", 14)
	row.add_child(_pending_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_apply_btn = Button.new()
	_apply_btn.text = tr(&"PLAYER_APPLY")
	MenuStyle.apply_primary_cta(_apply_btn, 18)
	_apply_btn.custom_minimum_size = Vector2(140, 44)
	_apply_btn.pressed.connect(_apply)
	SoundManager.wire_button(_apply_btn)
	row.add_child(_apply_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr(&"EDITOR_CANCEL")
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.add_theme_font_size_override("font_size", 18)
	MenuStyle.apply_focus_ring(cancel_btn)
	cancel_btn.pressed.connect(_cancel)
	SoundManager.wire_button(cancel_btn)
	row.add_child(cancel_btn)


# A row in the region being built. Hovering it, or reaching any control in it,
# frames `focus` in the case.
func _row(page: VBoxContainer, label_key: StringName, gameplay: bool,
		focus: int) -> VBoxContainer:
	if gameplay:
		_tab_gameplay[_building] = true
	return PlayerRowKit.row(page, tr(label_key), gameplay, _case.frame.bind(focus))


func _wire_reach(controls: Array, focus: int) -> void:
	for c: Control in controls:
		var target: Control = c
		if c is SwatchDropdown:
			target = (c as SwatchDropdown).focus_target()
		target.focus_entered.connect(_case.frame.bind(focus))
		target.mouse_entered.connect(_case.frame.bind(focus))


func _build_you(page: VBoxContainer) -> void:
	var full: int = LockerMannequin.Focus.FULL
	var name_col: VBoxContainer = _row(page, &"PLAYER_NAME_LABEL", false, full)
	_name_field = LineEdit.new()
	_name_field.placeholder_text = tr(&"PLAYER_NAME_PLACEHOLDER")
	_name_field.max_length = NameFilter.MAX_LENGTH
	_name_field.custom_minimum_size = Vector2(PlayerRowKit.FIELD_W, PlayerRowKit.CONTROL_H)
	_name_field.add_theme_font_size_override("font_size", 18)
	_name_field.text_changed.connect(_on_name_text_changed)
	name_col.add_child(_name_field)
	_name_warning = _warning(name_col)

	var num_col: VBoxContainer = _row(page, &"PLAYER_NUMBER_LABEL", false, full)
	_number_field = LineEdit.new()
	_number_field.max_length = 2
	_number_field.custom_minimum_size = Vector2(80, PlayerRowKit.CONTROL_H)
	_number_field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_number_field.add_theme_font_size_override("font_size", 18)
	_number_field.text_changed.connect(_on_number_text_changed)
	num_col.add_child(_number_field)
	_number_warning = _warning(num_col)

	_shoots_btns = PlayerRowKit.segmented(_row(page, &"PLAYER_SHOOTS_LABEL", true, full),
			[tr(&"PLAYER_SHOOTS_LEFT"), tr(&"PLAYER_SHOOTS_RIGHT")],
			func(i: int) -> void:
				_draft.is_left_handed = i == 0
				_edited())

	var pos_col: VBoxContainer = _row(page, &"PLAYER_POSITION_LABEL", false, full)
	var badges: Array[String] = []
	for key: StringName in _POSITION_BADGE_KEYS:
		badges.append(tr(key))
	_position_btns = PlayerRowKit.segmented(pos_col, badges, func(i: int) -> void:
		_draft.position = _POSITION_ORDER[i]
		_edited())
	for i: int in _position_btns.size():
		_position_btns[i].tooltip_text = tr(_POSITION_KEYS[i])
	PlayerRowKit.hint(pos_col).text = tr(&"PLAYER_POSITION_HINT")

	var team_col: VBoxContainer = _row(page, &"PLAYER_TEAM_LABEL", false, full)
	_color_dropdown = PaletteDropdown.new(TeamColorRegistry.DEFAULT_HOME_SLOT,
			Vector2(PlayerRowKit.FIELD_W, PlayerRowKit.CONTROL_H))
	_color_dropdown.selected.connect(func(slot: int) -> void:
		_draft.color_slot = slot
		_edited())
	team_col.add_child(_color_dropdown)


func _warning(parent: Container) -> Label:
	var w := Label.new()
	w.add_theme_color_override("font_color", MenuStyle.DANGER)
	w.add_theme_font_size_override("font_size", 13)
	w.visible = false
	parent.add_child(w)
	return w


func _build_body(page: VBoxContainer) -> void:
	var full: int = LockerMannequin.Focus.FULL
	var h_col: VBoxContainer = _row(page, &"PLAYER_HEIGHT_LABEL", true, full)
	var h: Array[Control] = PlayerRowKit.slider(h_col, _on_height_changed)
	_height_slider = h[0] as HSlider
	_height_slider.min_value = PlayerAttributes.HEIGHT_MIN
	_height_slider.max_value = PlayerAttributes.HEIGHT_MAX
	_height_value = h[1] as Label
	PlayerRowKit.hint(h_col).text = tr(&"PLAYER_HEIGHT_HINT")

	var w_col: VBoxContainer = _row(page, &"PLAYER_WEIGHT_LABEL", true, full)
	var w: Array[Control] = PlayerRowKit.slider(w_col, _on_weight_changed)
	_weight_slider = w[0] as HSlider
	_weight_value = w[1] as Label
	_weight_hint = PlayerRowKit.hint(w_col)
	_wire_reach([_height_slider, _weight_slider], full)

	_skin_buttons = PlayerRowKit.swatches(_row(page, &"PLAYER_SKIN_LABEL", false, full),
			SkinToneRegistry.TONES, [], func(i: int) -> void:
				_draft.skin = SkinToneRegistry.clamp_index(i)
				_edited())
	_wire_reach(_skin_buttons, full)

	var gloves: int = LockerMannequin.Focus.GLOVES
	_glove_btn = PlayerRowKit.option_button(_row(page, &"PLAYER_GLOVES_LABEL", false, gloves),
			func(i: int) -> void: _edit_gear(&"glove_model", i))
	_tuck_btn = PlayerRowKit.option_button(_row(page, &"GEAR_TUCK_LABEL", false, full),
			func(i: int) -> void: _edit_gear(&"jersey_tuck", i))
	for i: int in GearModelRegistry.tuck_count():
		_tuck_btn.add_item(tr(GearModelRegistry.TUCK_NAME_KEYS[i]), i)
	_wire_reach([_glove_btn], gloves)
	_wire_reach([_tuck_btn], full)


func _build_head(page: VBoxContainer) -> void:
	var head: int = LockerMannequin.Focus.HELMET
	_hair_btn = PlayerRowKit.option_button(_row(page, &"PLAYER_HAIR_LABEL", false, head),
			func(i: int) -> void: _edit_gear(&"hair_style", _hair_btn.get_item_id(i)))
	for style: int in HairStyleRegistry.pickable_hair():
		_hair_btn.add_item(tr(HairStyleRegistry.HAIR_NAME_KEYS[style]), style)
	_facial_btn = PlayerRowKit.option_button(_row(page, &"PLAYER_BEARD_LABEL", false, head),
			func(i: int) -> void: _edit_gear(&"facial_hair", i))
	for i: int in HairStyleRegistry.facial_count():
		_facial_btn.add_item(tr(HairStyleRegistry.FACIAL_NAME_KEYS[i]), i)
	var color_names: Array[String] = []
	for key: StringName in HairStyleRegistry.COLOR_NAME_KEYS:
		color_names.append(tr(key))
	_hair_color_buttons = PlayerRowKit.swatches(
			_row(page, &"PLAYER_HAIR_COLOR_LABEL", false, head), HairStyleRegistry.COLORS,
			color_names, func(i: int) -> void: _edit_gear(&"hair_color", i))
	var face_names: Array[String] = []
	for key: StringName in GearModelRegistry.FACE_NAME_KEYS:
		face_names.append(tr(key))
	_face_btns = PlayerRowKit.segmented(_row(page, &"PLAYER_HELMET_LABEL", false, head),
			face_names, func(i: int) -> void: _edit_gear(&"helmet_face", i))
	var head_controls: Array = [_hair_btn, _facial_btn]
	head_controls.append_array(_hair_color_buttons)
	head_controls.append_array(_face_btns)
	_wire_reach(head_controls, head)


func _build_stick(page: VBoxContainer) -> void:
	# Each row asks for the shot its pick shows up in: cut and stiffness are the
	# whole stick, the pattern and the tape live on the blade, the knob and the
	# wrap are up at the butt.
	var stick: int = LockerMannequin.Focus.STICK
	var blade: int = LockerMannequin.Focus.BLADE
	var grip: int = LockerMannequin.Focus.GRIP
	_gear_row(page, &"STICK_GEAR_LENGTH", &"length", _LENGTH_KEYS, _LENGTH_HINTS, stick)
	_gear_row(page, &"STICK_GEAR_CURVE", &"curve", _CURVE_KEYS, _CURVE_HINTS, blade)
	_flex_row = _gear_row(page, &"STICK_GEAR_FLEX", &"flex", _FLEX_KEYS, _FLEX_HINTS, stick)

	# Stick colorways are fixed designs with no kit zones, so their items fill once.
	_stick_model_btn = PlayerRowKit.option_button(
			_row(page, &"STICK_MODEL_LABEL", false, stick),
			func(i: int) -> void: _edit_gear(&"stick_model", i))
	for model: int in StickModelRegistry.count():
		_stick_model_btn.add_icon_item(
				PlayerRowKit.swatch_strip(StickModelRegistry.swatch_colors(model)),
				tr(StickModelRegistry.NAME_KEYS[model]), model)
	_blade_color_dd = _swatch_dropdown(_row(page, &"TAPE_BLADE_LABEL", false, blade),
			func(i: int) -> void: _edit_tape(i, -1, -1, -1))
	_span_btn = PlayerRowKit.option_button(_row(page, &"TAPE_COVERAGE_LABEL", false, blade),
			func(i: int) -> void: _edit_tape(-1, _SPAN_OPTIONS[i], -1, -1))
	for i: int in _SPAN_KEYS.size():
		_span_btn.add_item(tr(_SPAN_KEYS[i]), i)
	_knob_color_dd = _swatch_dropdown(_row(page, &"TAPE_KNOB_LABEL", false, grip),
			func(i: int) -> void: _edit_tape(-1, -1, i, -1))
	_style_btn = PlayerRowKit.option_button(_row(page, &"TAPE_HANDLE_LABEL", false, grip),
			func(i: int) -> void: _edit_tape(-1, -1, -1, _STYLE_OPTIONS[i]))
	for i: int in _STYLE_KEYS.size():
		_style_btn.add_item(tr(_STYLE_KEYS[i]), i)
	_wire_reach([_stick_model_btn], stick)
	_wire_reach([_blade_color_dd, _span_btn], blade)
	_wire_reach([_knob_color_dd, _style_btn], grip)


func _build_skates(page: VBoxContainer) -> void:
	var skates: int = LockerMannequin.Focus.SKATES
	_gear_row(page, &"GEAR_PROFILE_LABEL", &"profile", _PROFILE_KEYS, _PROFILE_HINTS, skates)
	# Model items are rebuilt with the team: a model's TEAM zones resolve against
	# the kit the player is about to wear.
	_skate_btn = PlayerRowKit.option_button(_row(page, &"STICK_MODEL_LABEL", false, skates),
			func(i: int) -> void: _edit_gear(&"skate_model", i))
	_lace_dd = _swatch_dropdown(_row(page, &"GEAR_LACES_LABEL", false, skates),
			func(i: int) -> void: _edit_gear(&"lace_color", i))
	_wire_reach([_skate_btn, _lace_dd], skates)


func _gear_row(page: VBoxContainer, label_key: StringName, field: StringName,
		option_keys: Array[StringName], hint_keys: Array[StringName], focus: int) -> _GearRow:
	var col: VBoxContainer = _row(page, label_key, true, focus)
	var labels: Array[String] = []
	for key: StringName in option_keys:
		labels.append(tr(key))
	var r := _GearRow.new()
	r.field = field
	r.hint_keys = hint_keys
	r.buttons = PlayerRowKit.segmented(col, labels, func(i: int) -> void:
		_draft.set(field, i)
		_edited())
	r.hint = PlayerRowKit.hint(col)
	_wire_reach(r.buttons, focus)
	_gear_rows.append(r)
	return r


func _swatch_dropdown(parent: Container, on_pick: Callable) -> SwatchDropdown:
	var dd := SwatchDropdown.new(Vector2(PlayerRowKit.FIELD_W, PlayerRowKit.CONTROL_H))
	dd.selected.connect(on_pick)
	parent.add_child(dd)
	return dd


# ── Editing ──────────────────────────────────────────────────────────────────

func _show_region(r: int) -> void:
	_region = r
	for i: int in Region.size():
		_pages[i].visible = i == r
		MenuStyle.apply_tab_button(_tab_btns[i], i == r)
	_case.frame(_REGION_FOCUS[r])
	var lit: Array[int] = []
	lit.assign(_emphasis[r])
	_stats.emphasize(lit, tr(_REGION_NOTE_KEYS[r]))


func _edited() -> void:
	_refresh()
	_update_apply_state()


func _edit_gear(field: StringName, value: int) -> void:
	var g: GearStyleConfig = _draft.gear()
	g.set(field, value)
	_draft.set_gear(g)
	_edited()


# −1 keeps a field.
func _edit_tape(blade_color: int, span: int, knob_color: int, knob_style: int) -> void:
	var t: StickTapeConfig = _draft.tape()
	_draft.set_tape(StickTapeConfig.new(
			t.blade_color if blade_color < 0 else blade_color,
			t.span if span < 0 else span,
			t.knob_color if knob_color < 0 else knob_color,
			t.knob_style if knob_style < 0 else knob_style))
	_edited()


func _on_height_changed(value: float) -> void:
	if _refreshing:
		return
	_draft.set_height(int(value))
	_edited()


func _on_weight_changed(value: float) -> void:
	if _refreshing:
		return
	_draft.set_weight(int(value))
	_edited()


func _on_name_text_changed(t: String) -> void:
	var trimmed: String = t.strip_edges()
	_name_valid = false
	_name_warning.visible = false
	if trimmed.is_empty():
		pass
	elif not NameFilter.is_alphanumeric(trimmed):
		_name_warning.text = tr(&"PLAYER_NAME_ALNUM")
		_name_warning.visible = true
	elif not NameFilter.is_clean(trimmed):
		_name_warning.text = tr(&"PLAYER_NAME_NOT_ALLOWED")
		_name_warning.visible = true
	else:
		_name_valid = true
		_draft.player_name = trimmed
	_edited()


func _on_number_text_changed(t: String) -> void:
	_number_valid = not t.is_empty() and t.is_valid_int()
	_number_warning.text = tr(&"PLAYER_NUMBER_DIGITS")
	_number_warning.visible = not t.is_empty() and not t.is_valid_int()
	if _number_valid:
		_draft.jersey_number = clampi(t.to_int(), 0, 99)
	_edited()


# ── Showing the draft ────────────────────────────────────────────────────────

func _sync_text_fields() -> void:
	_name_field.text = _draft.player_name
	_number_field.text = str(_draft.jersey_number)
	_name_warning.visible = false
	_number_warning.visible = false
	_name_valid = true
	_number_valid = true


# Every control but the text fields (resetting those mid-edit would throw the
# caret) from the draft, then the figure and the stat panel.
func _refresh() -> void:
	_refreshing = true
	var gear: GearStyleConfig = _draft.gear()
	var tape: StickTapeConfig = _draft.tape()
	PlayerRowKit.select(_shoots_btns, 0 if _draft.is_left_handed else 1)
	PlayerRowKit.select(_position_btns, _POSITION_ORDER.find(_draft.position))
	_color_dropdown.set_selected(_draft.color_slot)

	_height_slider.set_value_no_signal(_draft.height)
	_height_value.text = PlayerAttributes.inches_label(_draft.height)
	# Bounds first, then the value — a value outside the old range would clamp
	# before the new bounds land.
	_weight_slider.min_value = PlayerAttributes.weight_min(_draft.height)
	_weight_slider.max_value = PlayerAttributes.weight_max(_draft.height)
	_weight_slider.set_value_no_signal(_draft.weight)
	_weight_value.text = tr(&"PLAYER_WEIGHT_VALUE") % _draft.weight
	var frame: int = roundi(PlayerAttributes.frame_t_for(_draft.height, _draft.weight) * 4.0)
	_weight_hint.text = tr(&"PLAYER_WEIGHT_HINT") % [tr(_FRAME_KEYS[frame]),
			PlayerAttributes.weight_min(_draft.height), PlayerAttributes.weight_max(_draft.height)]
	PlayerRowKit.select(_skin_buttons, _draft.skin)
	_tuck_btn.select(gear.jersey_tuck)

	_hair_btn.select(_hair_btn.get_item_index(gear.hair_style))
	_facial_btn.select(gear.facial_hair)
	PlayerRowKit.select(_hair_color_buttons, gear.hair_color)
	PlayerRowKit.select(_face_btns, gear.helmet_face)

	for r: _GearRow in _gear_rows:
		var pick: int = int(_draft.get(r.field))
		PlayerRowKit.select(r.buttons, pick)
		r.hint.text = tr(r.hint_keys[pick])
	# The flex buttons carry the real stiffness number, fitted to the weight — so
	# "Stiff" on a light frame can read lower than "Whippy" on a heavy one.
	var flex_labels: Array[String] = []
	for i: int in _FLEX_KEYS.size():
		flex_labels.append(tr(&"STICK_FLEX_ITEM")
				% [tr(_FLEX_KEYS[i]), PlayerAttributes.flex_number_for(_draft.weight, i)])
	PlayerRowKit.relabel(_flex_row.buttons, flex_labels)
	_stick_model_btn.select(clampi(gear.stick_model, 0, StickModelRegistry.count() - 1))
	_span_btn.select(maxi(_SPAN_OPTIONS.find(tape.span), 0))
	_style_btn.select(maxi(_STYLE_OPTIONS.find(tape.knob_style), 0))

	if _painted_slot != _draft.color_slot:
		_painted_slot = _draft.color_slot
		_paint_team_rows()
	_glove_btn.select(gear.glove_model)
	_skate_btn.select(gear.skate_model)
	_blade_color_dd.set_selected(tape.blade_color)
	_knob_color_dd.set_selected(tape.knob_color)
	_lace_dd.set_selected(gear.lace_color)
	_refreshing = false

	var attrs: PlayerAttributes = _draft.attributes()
	_case.set_jersey_info(_draft.player_name, _draft.jersey_number)
	_case.dress(attrs, gear, tape, _draft.team_colors(), _draft.skin, _draft.is_left_handed)
	_stats.show_build(attrs)


# The rows whose swatches resolve against the team: the skate and glove models
# (their TEAM zones) and the tape palettes (the TEAM chip).
func _paint_team_rows() -> void:
	var colors: Dictionary = _draft.team_colors()
	var team: Color = colors.get("primary", Color.WHITE)
	var accent: Color = colors.get("secondary", Color.WHITE)
	var light: Color = colors.get("light", Color.WHITE)
	var glove_kit: Color = colors.get("gloves", Color.BLACK)
	var glove_accent: Color = colors.get("glove_accent", Color.WHITE)

	_skate_btn.clear()
	for model: int in GearModelRegistry.skate_count():
		var zones: Array[Color] = []
		for zone: int in GearModelRegistry.SKATE_ZONE_COUNT:
			zones.append(GearModelRegistry.skate_color(model, zone, team, accent, light))
		_skate_btn.add_icon_item(PlayerRowKit.swatch_strip(zones),
				tr(GearModelRegistry.SKATE_NAME_KEYS[model]), model)
	_glove_btn.clear()
	for model: int in GearModelRegistry.glove_count():
		var zones: Array[Color] = []
		for zone: int in GearModelRegistry.GLOVE_ZONE_COUNT:
			zones.append(GearModelRegistry.glove_color(model, zone,
					glove_kit, glove_accent, light))
		_glove_btn.add_icon_item(PlayerRowKit.swatch_strip(zones),
				tr(GearModelRegistry.GLOVE_NAME_KEYS[model]), model)

	var tape_colors: Array[Color] = []
	var names: Array[String] = []
	var chips: Array[String] = []
	for i: int in TapeColorRegistry.count():
		tape_colors.append(TapeColorRegistry.resolve(i, team))
		names.append(tr(TapeColorRegistry.NAME_KEYS[i]))
		# The TEAM chip says so — it tracks the kit rather than being one more
		# fixed colour.
		chips.append(tr(&"TAPE_COLOR_TEAM_SHORT") if i == TapeColorRegistry.TEAM_INDEX else "")
	for dd: SwatchDropdown in [_blade_color_dd, _knob_color_dd, _lace_dd]:
		dd.set_palette(tape_colors, names, chips)


func _update_apply_state() -> void:
	var changed: bool = _draft.differs(_saved)
	_apply_btn.disabled = not changed or not _name_valid or not _number_valid
	# Fades via modulate rather than `visible`, so the footer never reflows.
	_pending_label.modulate.a = 1.0 if changed else 0.0


# ── Commit ───────────────────────────────────────────────────────────────────

func _apply() -> void:
	if not _name_valid or not _number_valid:
		return
	_draft.commit(_saved)
	if _draft.player_name != _saved.player_name:
		name_changed.emit(_draft.player_name)
	if _draft.jersey_number != _saved.jersey_number:
		jersey_number_changed.emit(_draft.jersey_number)
	if _draft.is_left_handed != _saved.is_left_handed:
		handedness_changed.emit(_draft.is_left_handed)
	if _draft.position != _saved.position:
		position_changed.emit(_draft.position)
	if _draft.color_slot != _saved.color_slot:
		preferred_color_changed.emit(_draft.color_slot)
	visible = false


func _cancel() -> void:
	visible = false

extends GutTest

# The player screen builds its regions and rows in code, so nothing but running
# it proves the rows are wired to the catalogues and the draft, and that a pick
# reaches the figure and the stat panel. Apply writes PlayerPrefs to disk, so it
# is left alone here; what is pinned is everything up to it. The case's own
# geometry and camera are test_player_case.gd's.

const R := PlayerSettingsPopup.Region
const F := LockerMannequin.Focus

var _popup: PlayerSettingsPopup = null
var _saved_gear: int = 0
var _saved_build: Array[int] = []


func before_each() -> void:
	_saved_gear = PlayerPrefs.gear_style_code
	_saved_build = [PlayerPrefs.attr_height, PlayerPrefs.attr_weight, PlayerPrefs.attr_profile,
			PlayerPrefs.attr_curve, PlayerPrefs.attr_flex, PlayerPrefs.attr_length]
	PlayerPrefs.gear_style_code = GearStyleConfig.new(GearModelRegistry.SKATE_RETRO,
			GearModelRegistry.GLOVE_CONTRAST, GearStyleConfig.LACE_DEFAULT_INDEX,
			StickModelRegistry.STICK_SPLIT, GearModelRegistry.FACE_VISOR).to_code()
	PlayerPrefs.set_player_attributes(PlayerAttributes.neutral())
	_popup = PlayerSettingsPopup.new()
	add_child_autofree(_popup)
	_popup.open()


func after_each() -> void:
	PlayerPrefs.gear_style_code = _saved_gear
	PlayerPrefs.set_player_attributes(PlayerAttributes.new(_saved_build[0], _saved_build[1],
			_saved_build[2], _saved_build[3], _saved_build[4], _saved_build[5]))


func _btn(field: String) -> OptionButton:
	return _popup.get(field) as OptionButton


func _buttons(field: String) -> Array:
	return _popup.get(field) as Array


func _draft() -> PlayerDraft:
	return _popup.get("_draft") as PlayerDraft


func _case() -> PlayerCase:
	return _popup.get("_case") as PlayerCase


func _gear_row(field: StringName) -> Object:
	for r: Object in _popup.get("_gear_rows") as Array:
		if r.get("field") == field:
			return r
	return null


func _press(buttons: Array, index: int) -> void:
	(buttons[index] as Button).pressed.emit()


func _picked(buttons: Array) -> int:
	for i: int in buttons.size():
		if (buttons[i] as Button).button_pressed:
			return i
	return -1


func test_every_row_lists_its_catalogue_with_the_saved_picks() -> void:
	assert_eq(_btn("_skate_btn").item_count, GearModelRegistry.skate_count())
	assert_eq(_btn("_glove_btn").item_count, GearModelRegistry.glove_count())
	assert_eq(_btn("_stick_model_btn").item_count, StickModelRegistry.pickable().size(),
			"a retired stick is not offered")
	assert_eq(_btn("_tuck_btn").item_count, GearModelRegistry.tuck_count())
	assert_eq(_btn("_facial_btn").item_count, HairStyleRegistry.facial_count())
	assert_eq(_buttons("_face_btns").size(), GearModelRegistry.face_count())
	assert_eq(_btn("_hair_btn").item_count, HairStyleRegistry.pickable_hair().size())
	assert_eq(_btn("_hair_btn").get_item_index(HairStyleRegistry.HAIR_LONG), -1,
			"a retired style is not offered")
	assert_eq(_buttons("_hair_color_buttons").size(), HairStyleRegistry.color_count())
	assert_eq(_buttons("_skin_buttons").size(), SkinToneRegistry.TONES.size())
	assert_eq(_btn("_skate_btn").selected, GearModelRegistry.SKATE_RETRO)
	assert_eq(_btn("_glove_btn").selected, GearModelRegistry.GLOVE_CONTRAST)
	assert_eq(_btn("_stick_model_btn").get_selected_id(), StickModelRegistry.STICK_SPLIT)
	# The color rows show the saved picks, not the palette's first entry.
	assert_eq((_popup.get("_stick_shaft_dd") as SwatchDropdown).get("_selected_index"),
			GearStyleConfig.STICK_SHAFT_DEFAULT)
	assert_eq((_popup.get("_stick_primary_dd") as SwatchDropdown).get("_selected_index"),
			GearStyleConfig.STICK_PRIMARY_DEFAULT)
	assert_eq((_popup.get("_lace_dd") as SwatchDropdown).get("_selected_index"),
			GearStyleConfig.LACE_DEFAULT_INDEX)
	assert_eq(_picked(_buttons("_face_btns")), GearModelRegistry.FACE_VISOR)


# The model items are rebuilt when the team changes — their TEAM zones resolve
# against the kit — so re-opening and re-picking must re-list, not append.
func test_the_coverage_row_offers_every_span_once() -> void:
	var offered: Array[int] = []
	offered.assign(_popup.get("_SPAN_OPTIONS") as Array)
	assert_eq(_btn("_span_btn").item_count, StickTapeConfig.Span.size())
	for span: int in StickTapeConfig.Span.size():
		assert_eq(offered.count(span), 1, "span %d offered once" % span)


# Each color row is live only while the coverage lays the piece it paints.
func test_a_coverage_pick_lights_the_color_rows_it_uses() -> void:
	var blade_dd: SwatchDropdown = _popup.get("_blade_color_dd") as SwatchDropdown
	var strip_dd: SwatchDropdown = _popup.get("_strip_color_dd") as SwatchDropdown
	var offered: Array = _popup.get("_SPAN_OPTIONS") as Array
	var cases: Dictionary = {
		StickTapeConfig.Span.FULL: [true, false],
		StickTapeConfig.Span.STRIP: [false, true],
		StickTapeConfig.Span.STRIP_AND_TOE: [true, true],
		StickTapeConfig.Span.NONE: [false, false],
	}
	for span: int in cases:
		_btn("_span_btn").item_selected.emit(offered.find(span))
		assert_eq(_draft().tape().span, span, "the pick lands in the draft")
		assert_eq(not blade_dd.get("_disabled"), cases[span][0], "blade row for span %d" % span)
		assert_eq(not strip_dd.get("_disabled"), cases[span][1], "strip row for span %d" % span)
	strip_dd.selected.emit(2)
	assert_eq(_draft().tape().strip_color, 2, "a strip pick lands in the draft")
	assert_eq(_draft().tape().span, StickTapeConfig.Span.NONE, "…and keeps the coverage")


# The stick's colors are the player's; the model only lays out the graphic, so
# its row redraws in them and the second color goes quiet on a graphic that
# never shows it.
func test_stick_color_picks_land_and_redraw_the_models() -> void:
	var model_btn: OptionButton = _btn("_stick_model_btn")
	var secondary_dd: SwatchDropdown = _popup.get("_stick_secondary_dd") as SwatchDropdown
	(_popup.get("_stick_shaft_dd") as SwatchDropdown).selected.emit(TapeColorRegistry.WHITE_INDEX)
	(_popup.get("_stick_primary_dd") as SwatchDropdown).selected.emit(
			TapeColorRegistry.BLACK_INDEX)
	secondary_dd.selected.emit(TapeColorRegistry.TEAM_INDEX)
	var gear: GearStyleConfig = _draft().gear()
	assert_eq(gear.stick_shaft, TapeColorRegistry.WHITE_INDEX)
	assert_eq(gear.stick_primary, TapeColorRegistry.BLACK_INDEX)
	assert_eq(gear.stick_secondary, TapeColorRegistry.TEAM_INDEX)
	assert_eq(model_btn.item_count, StickModelRegistry.pickable().size(), "redrawn, not stacked")
	assert_eq(model_btn.get_selected_id(), StickModelRegistry.STICK_SPLIT, "and still picked")
	assert_false(secondary_dd.get("_disabled"), "Split's seam ring shows the second color")
	model_btn.item_selected.emit(model_btn.get_item_index(StickModelRegistry.STICK_STEALTH))
	assert_eq(_draft().gear().stick_model, StickModelRegistry.STICK_STEALTH)
	assert_true(secondary_dd.get("_disabled"), "Stealth has no second color to paint")


func test_reopening_and_a_team_change_do_not_stack_items() -> void:
	_popup.call("_cancel")
	_popup.open()
	(_popup.get("_color_dropdown") as PaletteDropdown).selected.emit(1)
	assert_eq(_btn("_skate_btn").item_count, GearModelRegistry.skate_count())
	assert_eq(_btn("_glove_btn").item_count, GearModelRegistry.glove_count())
	assert_eq(_btn("_skate_btn").selected, GearModelRegistry.SKATE_RETRO)


func test_a_model_pick_lands_in_the_draft_and_on_the_figure() -> void:
	var mannequin: LockerMannequin = _case().get("_mannequin") as LockerMannequin
	var boot: MeshInstance3D = (mannequin.get("_boots") as Array)[0] as MeshInstance3D
	var before: Color = (boot.get_surface_override_material(SkaterMeshBuilder.BOOT_SURF_SHELL)
			as StandardMaterial3D).albedo_color
	_btn("_skate_btn").item_selected.emit(GearModelRegistry.SKATE_WHITEOUT)
	assert_eq(_draft().gear().skate_model, GearModelRegistry.SKATE_WHITEOUT)
	assert_ne((boot.get_surface_override_material(SkaterMeshBuilder.BOOT_SURF_SHELL)
			as StandardMaterial3D).albedo_color, before, "the figure re-dresses")


# The hair picker skips retired styles, so its rows are not style indices.
func _pick_hair(style: int) -> void:
	var btn: OptionButton = _btn("_hair_btn")
	btn.item_selected.emit(btn.get_item_index(style))


# The hair lives in the packed gear code beside the equipment; a pick must land
# in the pending code without disturbing the equipment fields.
func test_a_hair_pick_lands_in_the_draft_and_nowhere_else() -> void:
	_pick_hair(HairStyleRegistry.HAIR_MULLET)
	_btn("_facial_btn").item_selected.emit(HairStyleRegistry.FACIAL_GOATEE)
	_press(_buttons("_hair_color_buttons"), 5)
	var gear: GearStyleConfig = _draft().gear()
	assert_eq(gear.hair_style, HairStyleRegistry.HAIR_MULLET)
	assert_eq(gear.facial_hair, HairStyleRegistry.FACIAL_GOATEE)
	assert_eq(gear.hair_color, 5)
	assert_eq(gear.skate_model, GearModelRegistry.SKATE_RETRO, "the equipment is untouched")
	assert_eq(gear.helmet_face, GearModelRegistry.FACE_VISOR)
	assert_eq(_picked(_buttons("_hair_color_buttons")), 5, "one swatch is ringed")
	assert_eq(_btn("_hair_btn").get_selected_id(), HairStyleRegistry.HAIR_MULLET)
	assert_false((_popup.get("_apply_btn") as Button).disabled, "Apply wakes up")


func test_cancel_drops_the_edits() -> void:
	_pick_hair(HairStyleRegistry.HAIR_BALD)
	_press((_gear_row(&"curve").get("buttons") as Array), 2)
	_popup.call("_cancel")
	_popup.open()
	assert_eq(_draft().gear().hair_style, HairStyleRegistry.HAIR_SHORT)
	assert_eq(_btn("_hair_btn").get_selected_id(), HairStyleRegistry.HAIR_SHORT)
	assert_eq(_draft().curve, PlayerAttributes.GEAR_BALANCED)
	assert_true((_popup.get("_apply_btn") as Button).disabled, "nothing pending")


func test_a_gear_pick_sets_the_dial_and_says_what_it_does() -> void:
	var profile: Object = _gear_row(&"profile")
	_press(profile.get("buttons") as Array, 2)
	assert_eq(_draft().profile, 2, "Power")
	assert_eq(_picked(profile.get("buttons") as Array), 2)
	assert_eq((profile.get("hint") as Label).text, tr(&"HINT_PROFILE_POWER"))


# A height move keeps the frame: a lean build stays lean as it grows.
func test_a_height_move_keeps_the_frame() -> void:
	var h: int = PlayerAttributes.HEIGHT_MEDIUM
	(_popup.get("_weight_slider") as HSlider).value_changed.emit(PlayerAttributes.weight_min(h))
	var frame: float = PlayerAttributes.frame_t_for(h, _draft().weight)
	(_popup.get("_height_slider") as HSlider).value_changed.emit(PlayerAttributes.HEIGHT_MAX)
	assert_eq(_draft().height, PlayerAttributes.HEIGHT_MAX)
	assert_eq(_draft().weight, PlayerAttributes.weight_for_frame_t(PlayerAttributes.HEIGHT_MAX, frame))
	var slider: HSlider = _popup.get("_weight_slider") as HSlider
	assert_eq(slider.min_value, float(PlayerAttributes.weight_min(PlayerAttributes.HEIGHT_MAX)),
			"the weight slider takes the new height's band")
	assert_eq(int(slider.value), _draft().weight)


# The flex buttons carry the stiffness number fitted to the weight.
func test_the_flex_buttons_follow_the_weight() -> void:
	var buttons: Array = _gear_row(&"flex").get("buttons") as Array
	var h: int = PlayerAttributes.HEIGHT_MEDIUM
	(_popup.get("_weight_slider") as HSlider).value_changed.emit(PlayerAttributes.weight_max(h))
	for i: int in buttons.size():
		assert_true((buttons[i] as Button).text.ends_with(
				str(PlayerAttributes.flex_number_for(_draft().weight, i))),
				"flex %d reads its fitted number" % i)


func test_the_stat_panel_reads_the_draft() -> void:
	var values: Array = (_popup.get("_stats") as BuildStatPanel).get("_values") as Array
	var top: Label = values[BuildReadout.Stat.TOP_SPEED] as Label
	assert_eq(top.text, "—", "neutral reads no change")
	_press(_gear_row(&"profile").get("buttons") as Array, 2)
	assert_true(top.text.begins_with("+"), "power skates read faster")


# Each region shows its own page, frames its own piece, and lights the stats its
# dials can move.
func test_a_region_shows_its_page_frames_its_piece_and_lights_its_stats() -> void:
	var pages: Array = _buttons("_pages")
	var rows: Array = (_popup.get("_stats") as BuildStatPanel).get("_rows") as Array
	_popup.call("_show_region", R.SKATES)
	for i: int in pages.size():
		assert_eq((pages[i] as Control).visible, i == R.SKATES, "page %d" % i)
	assert_eq(_case().get("_focus"), F.SKATES)
	var lit: Array[int] = BuildReadout.moved_by([BuildReadout.Dial.PROFILE])
	for s: int in BuildReadout.STAT_COUNT:
		var a: float = (rows[s] as Control).modulate.a
		if lit.has(s):
			assert_eq(a, 1.0, "%s is lit" % BuildReadout.NAME_KEYS[s])
		else:
			assert_lt(a, 1.0, "%s dims" % BuildReadout.NAME_KEYS[s])
	_popup.call("_show_region", R.HEAD)
	for s: int in BuildReadout.STAT_COUNT:
		assert_eq((rows[s] as Control).modulate.a, 1.0, "nothing to single out on the head")


func test_a_region_with_a_gameplay_row_stars_its_tab() -> void:
	var stars: Array = _buttons("_tab_stars")
	assert_true((stars[R.YOU] as Label).visible, "shoots")
	assert_true((stars[R.BODY] as Label).visible, "height and weight")
	assert_false((stars[R.HEAD] as Label).visible, "nothing on the head plays")
	assert_true((stars[R.STICK] as Label).visible)
	assert_true((stars[R.SKATES] as Label).visible)


# Landing on a row aims the case at the piece that row dresses — by focus (the
# pad) and by hover (the mouse), which lands on the CONTROL, not the row.
func test_a_row_aims_the_case_at_its_own_piece() -> void:
	var rows: Dictionary = {
		_btn("_skate_btn"): F.SKATES,
		_btn("_glove_btn"): F.GLOVES,
		_buttons("_face_btns")[0]: F.HELMET,
		(_gear_row(&"length").get("buttons") as Array)[0]: F.STICK,
		(_gear_row(&"flex").get("buttons") as Array)[0]: F.STICK,
		_btn("_stick_model_btn"): F.STICK,
		(_gear_row(&"curve").get("buttons") as Array)[0]: F.BLADE,
		_btn("_span_btn"): F.BLADE,
		_btn("_style_btn"): F.GRIP,
		(_popup.get("_height_slider") as Control): F.FULL,
	}
	for control: Control in rows:
		_case().frame(F.SKATES if rows[control] != F.SKATES else F.HELMET)
		control.focus_entered.emit()
		assert_eq(_case().get("_focus"), rows[control], "%s aims on focus" % control)
		_case().frame(F.SKATES if rows[control] != F.SKATES else F.HELMET)
		control.mouse_entered.emit()
		assert_eq(_case().get("_focus"), rows[control], "%s aims on hover" % control)


# SwatchDropdown is a FOCUS_NONE wrapper whose inner button takes the focus, so
# watching the wrapper would connect a signal that never fires.
func test_the_swatch_rows_reframe_the_case_too() -> void:
	var rows: Dictionary = {
		"_stick_shaft_dd": F.STICK,
		"_stick_primary_dd": F.STICK,
		"_stick_secondary_dd": F.STICK,
		"_blade_color_dd": F.BLADE,
		"_strip_color_dd": F.BLADE,
		"_knob_color_dd": F.GRIP,
		"_lace_dd": F.SKATES,
	}
	for field: String in rows:
		var dd: SwatchDropdown = _popup.get(field) as SwatchDropdown
		assert_eq(dd.focus_mode, Control.FOCUS_NONE,
				"%s is still a wrapper — if this changed, so did the wiring" % field)
		_case().frame(F.FULL)
		dd.focus_target().focus_entered.emit()
		assert_eq(_case().get("_focus"), rows[field], "%s aims the case" % field)
		_case().frame(F.FULL)
		dd.focus_target().mouse_entered.emit()
		assert_eq(_case().get("_focus"), rows[field], "%s aims it on hover too" % field)


# A control the focus search skips is a pick a controller player cannot make.
func test_every_row_control_is_pad_reachable() -> void:
	var controls: Array[Control] = [_btn("_skate_btn"), _btn("_glove_btn"),
		_btn("_stick_model_btn"), _btn("_span_btn"), _btn("_style_btn"), _btn("_tuck_btn"),
		_btn("_hair_btn"), _btn("_facial_btn"), _popup.get("_height_slider") as Control,
		_popup.get("_weight_slider") as Control, _popup.get("_name_field") as Control,
		_popup.get("_number_field") as Control]
	for field: String in ["_stick_shaft_dd", "_stick_primary_dd", "_stick_secondary_dd",
			"_blade_color_dd", "_strip_color_dd", "_knob_color_dd", "_lace_dd"]:
		controls.append((_popup.get(field) as SwatchDropdown).focus_target())
	for field: String in ["_face_btns", "_hair_color_buttons", "_skin_buttons",
			"_shoots_btns", "_position_btns", "_tab_btns"]:
		for b: Control in _buttons(field):
			controls.append(b)
	for r: Object in _popup.get("_gear_rows") as Array:
		for b: Control in r.get("buttons") as Array:
			controls.append(b)
	for c: Control in controls:
		assert_ne(c.focus_mode, Control.FOCUS_NONE, "%s can be focused" % c)


func test_position_buttons_run_in_rink_order() -> void:
	_press(_buttons("_position_btns"), 0)
	assert_eq(_draft().position, PlayerRules.POSITION_NAMES.find("LW"),
			"the leftmost button is the left wing")
	_press(_buttons("_position_btns"), 1)
	assert_eq(_draft().position, PlayerRules.POSITION_NAMES.find("C"))

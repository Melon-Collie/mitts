extends GutTest

# The hair is picked on the player screen, beside the skin, but it lives in the
# packed gear code whose equipment half the locker edits. What is pinned here:
# a pick lands in the pending code and nowhere else, it never reads as a pending
# LOCKER change, and Cancel throws it away.

var _popup: PlayerSettingsPopup = null
var _saved_gear: int = 0


func before_each() -> void:
	_saved_gear = PlayerPrefs.gear_style_code
	PlayerPrefs.gear_style_code = GearStyleConfig.new(GearModelRegistry.SKATE_RETRO, 0,
			GearStyleConfig.LACE_DEFAULT_INDEX, 0, GearModelRegistry.FACE_VISOR).to_code()
	_popup = PlayerSettingsPopup.new()
	add_child_autofree(_popup)
	_popup.open()


func after_each() -> void:
	PlayerPrefs.gear_style_code = _saved_gear


func _pending() -> GearStyleConfig:
	return GearStyleConfig.from_code(int(_popup.get("_pending_gear")))


func test_the_rows_list_every_style_and_colour() -> void:
	assert_eq((_popup.get("_hair_btn") as OptionButton).item_count,
			HairStyleRegistry.hair_count())
	assert_eq((_popup.get("_facial_btn") as OptionButton).item_count,
			HairStyleRegistry.facial_count())
	assert_eq((_popup.get("_hair_color_buttons") as Array).size(),
			HairStyleRegistry.color_count())


func test_a_pick_lands_in_the_pending_gear_and_nowhere_else() -> void:
	(_popup.get("_hair_btn") as OptionButton).item_selected.emit(HairStyleRegistry.HAIR_LONG)
	(_popup.get("_facial_btn") as OptionButton).item_selected.emit(
			HairStyleRegistry.FACIAL_GOATEE)
	((_popup.get("_hair_color_buttons") as Array)[5] as Button).pressed.emit()
	var gear: GearStyleConfig = _pending()
	assert_eq(gear.hair_style, HairStyleRegistry.HAIR_LONG)
	assert_eq(gear.facial_hair, HairStyleRegistry.FACIAL_GOATEE)
	assert_eq(gear.hair_color, 5)
	assert_eq(gear.skate_model, GearModelRegistry.SKATE_RETRO, "the equipment is untouched")
	assert_eq(gear.helmet_face, GearModelRegistry.FACE_VISOR)
	var swatches: Array = _popup.get("_hair_color_buttons") as Array
	for i: int in swatches.size():
		assert_eq((swatches[i] as Button).button_pressed, i == 5, "one swatch is ringed")
	assert_false((_popup.get("_apply_btn") as Button).disabled, "Apply wakes up")
	assert_false(_popup.call("_is_locker_dirty"),
			"a hair pick is not an unapplied locker change")


func test_cancel_drops_the_pick() -> void:
	(_popup.get("_hair_btn") as OptionButton).item_selected.emit(HairStyleRegistry.HAIR_BALD)
	_popup.call("_cancel")
	_popup.open()
	assert_eq(_pending().hair_style, HairStyleRegistry.HAIR_SHORT)
	assert_eq((_popup.get("_hair_btn") as OptionButton).selected, HairStyleRegistry.HAIR_SHORT)

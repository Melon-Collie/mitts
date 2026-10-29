class_name KitSwatches
extends RefCounted

# The player screen's pickers that resolve against the team the player is
# about to wear: the skate, glove and stick model lists (each item's swatch
# strip shows the design in that kit) and the palette every color row offers.
# Static; the screen owns the controls and calls in whenever the team, or the
# stick colors a stick strip is drawn in, change.


static func fill_skates(btn: OptionButton, colors: Dictionary) -> void:
	btn.clear()
	for model: int in GearModelRegistry.skate_count():
		var zones: Array[Color] = []
		for zone: int in GearModelRegistry.SKATE_ZONE_COUNT:
			zones.append(GearModelRegistry.skate_color(model, zone,
					colors.primary, colors.secondary, colors.light))
		btn.add_icon_item(PlayerRowKit.swatch_strip(zones),
				_tr(GearModelRegistry.SKATE_NAME_KEYS[model]), model)


static func fill_gloves(btn: OptionButton, colors: Dictionary) -> void:
	btn.clear()
	for model: int in GearModelRegistry.glove_count():
		var zones: Array[Color] = []
		for zone: int in GearModelRegistry.GLOVE_ZONE_COUNT:
			zones.append(GearModelRegistry.glove_color(model, zone,
					colors.gloves, colors.glove_accent, colors.light))
		btn.add_icon_item(PlayerRowKit.swatch_strip(zones),
				_tr(GearModelRegistry.GLOVE_NAME_KEYS[model]), model)


# Pickable models only, each item's id its model index.
static func fill_sticks(btn: OptionButton, gear: GearStyleConfig, colors: Dictionary) -> void:
	btn.clear()
	var c: Array[Color] = StickStyle.colors(gear, colors.primary, colors.secondary,
			colors.light)
	for model: int in StickModelRegistry.pickable():
		btn.add_icon_item(PlayerRowKit.swatch_strip(
				StickModelRegistry.swatch_colors(model, c[0], c[1], c[2])),
				_tr(StickModelRegistry.NAME_KEYS[model]), model)


static func paint_palette(dd: SwatchDropdown, colors: Dictionary) -> void:
	var swatches: Array[Color] = []
	var names: Array[String] = []
	var chips: Array[String] = []
	for i: int in TapeColorRegistry.count():
		swatches.append(TapeColorRegistry.resolve(i, colors.primary, colors.secondary,
				colors.light))
		names.append(_tr(TapeColorRegistry.NAME_KEYS[i]))
		var chip: StringName = TapeColorRegistry.CHIP_KEYS[i]
		chips.append("" if chip.is_empty() else _tr(chip))
	dd.set_palette(swatches, names, chips)


static func _tr(key: StringName) -> String:
	return TranslationServer.translate(key)

class_name CosmeticSwatches
extends RefCounted

# Fills a colour slot's swatch picker with what the player may wear
# (CosmeticUnlocks.available), the team entries resolved against the kit and
# labelled so players know those chips follow the team.

const _TEAM_CHIPS: Dictionary[int, StringName] = {
	TapeColorRegistry.TEAM_INDEX: &"TAPE_COLOR_TEAM_SHORT",
	TapeColorRegistry.TEAM_SECOND_INDEX: &"TAPE_COLOR_TEAM_SECOND_SHORT",
}


static func fill(dd: SwatchDropdown, slot: String, primary: Color, secondary: Color,
		raised: Array[String]) -> void:
	var ids: Array[int] = CosmeticUnlocks.available(slot, raised)
	var colors: Array[Color] = []
	var names: Array[String] = []
	var chips: Array[String] = []
	for id: int in ids:
		colors.append(TapeColorRegistry.resolve(id, primary, secondary))
		names.append(TrophyCopy.t(TapeColorRegistry.NAME_KEYS[id]))
		chips.append(TrophyCopy.t(_TEAM_CHIPS[id]) if _TEAM_CHIPS.has(id) else "")
	dd.set_palette(colors, names, chips, ids)

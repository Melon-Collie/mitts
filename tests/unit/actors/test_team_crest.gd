extends GutTest

# The chest crest (TeamCrest over CrestFruits): one per team, drawn only in the
# team's own colors, with a keyline that edges it on both of its jerseys.


func _presets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: int in TeamColorRegistry.get_all_slots():
		out.append(TeamColorRegistry.get_preset(slot))
	return out


func _team_pool(value: Variant, pool: Array[Color]) -> void:
	if value is Color:
		pool.append(value)
	elif value is Dictionary:
		for v: Variant in (value as Dictionary).values():
			_team_pool(v, pool)
	elif value is Array:
		for v: Variant in value:
			_team_pool(v, pool)


func test_every_team_has_a_crest() -> void:
	for preset: Dictionary in _presets():
		assert_ne(TeamCrest.fruit_for(preset), "", "%s has no crest drawing" % preset.name)


func test_a_team_without_a_drawing_gets_a_plain_chest() -> void:
	assert_eq(TeamCrest.fruit_for({"name": "Durian"}), "")
	assert_eq(TeamCrest.fruit_for({}), "")


# The one color a crest may bring in from outside its team.
func test_crest_colors_come_from_the_team() -> void:
	for preset: Dictionary in _presets():
		var pool: Array[Color] = []
		_team_pool(preset, pool)
		var fruit: String = TeamCrest.fruit_for(preset)
		for color: Color in TeamCrest.team_colors(fruit, preset):
			if CrestFruits.keeps(color):
				continue
			var found: bool = false
			for have: Color in pool:
				found = found or have.is_equal_approx(color)
			assert_true(found, "%s's crest uses %s, which is not a team color"
					% [preset.name, color.to_html(false)])


# Of the two keylines, at least one must stand off each jersey's base, or the
# crest has no edge on that sweater.
func test_the_keylines_edge_the_crest_on_both_jerseys() -> void:
	for preset: Dictionary in _presets():
		var light: Color = preset.light
		var dark: Color = TeamCrest.dark_color(preset)
		for kit: Dictionary in [preset.home, preset.away]:
			var base: Color = kit.jersey.base
			var contrast: float = maxf(absf(light.get_luminance() - base.get_luminance()),
					absf(dark.get_luminance() - base.get_luminance()))
			assert_gt(contrast, 0.15, "%s's crest has no edge on its %s jersey"
					% [preset.name, base.to_html(false)])


func test_home_and_away_wear_the_same_crest() -> void:
	for slot: int in TeamColorRegistry.get_all_slots():
		var home: Dictionary = TeamColorRegistry.get_colors(slot, 0).preset
		var away: Dictionary = TeamColorRegistry.get_colors(slot, 1).preset
		assert_eq(TeamCrest.fruit_for(home), TeamCrest.fruit_for(away))
		assert_eq(TeamCrest.team_colors(TeamCrest.fruit_for(home), home),
				TeamCrest.team_colors(TeamCrest.fruit_for(away), away))


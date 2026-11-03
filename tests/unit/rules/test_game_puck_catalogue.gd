extends GutTest

# The Game Puck catalogue and the banners hold together: ids unique, ladders
# ascending, every banner requirement naming a real puck and tier, every puck
# and banner named in the locale catalogue, and every Steam-mirrored id listed
# in steam/ACHIEVEMENTS.md (the Steamworks side, which the code cannot check).

const _CATALOGUE: String = "res://locale/translations.csv"
const _STEAM_DOC: String = "res://steam/ACHIEVEMENTS.md"

# The achievements that shipped before the catalogue, each still mirrored so no
# Steam unlock a player already holds is orphaned.
const _SHIPPED_STEAM_IDS: Array[String] = [
	"ACH_FIRST_GOAL", "ACH_HAT_TRICK", "ACH_PLAYMAKER", "ACH_BIG_NIGHT",
	"ACH_BRICK_WALL", "ACH_ONE_TIMER", "ACH_TIP_IN", "ACH_OVERTIME_HERO",
	"ACH_FACEOFF_BOSS", "ACH_PICKPOCKET", "ACH_SHUTOUT", "ACH_FIRST_WIN",
	"ACH_FREIGHT_TRAIN", "ACH_STUDENT", "ACH_CUSTOM_BUILD", "ACH_PLAY_WITH_BUUKIE",
	"ACH_SNIPER", "ACH_SETUP_ARTIST", "ACH_ENFORCER", "ACH_VETERAN",
]


func test_puck_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for entry: Dictionary in GamePucks.ALL:
		var id: String = entry["id"]
		assert_false(seen.has(id), "duplicate puck id: %s" % id)
		seen[id] = true


func test_banner_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for banner: Dictionary in Banners.ALL:
		var id: String = banner["id"]
		assert_false(seen.has(id), "duplicate banner id: %s" % id)
		seen[id] = true


func test_ladders_ascend_strictly() -> void:
	for entry: Dictionary in GamePucks.ALL:
		if not GamePucks.is_ladder(entry):
			continue
		var tiers: Array[int] = GamePucks.tiers_of(entry)
		assert_false(tiers.is_empty(), "%s has no tiers" % entry["id"])
		for i: int in range(1, tiers.size()):
			assert_gt(tiers[i], tiers[i - 1], "%s tiers must ascend" % entry["id"])
		for target: Variant in (entry.get("steam_tiers", {}) as Dictionary):
			assert_has(tiers, int(target),
					"%s mirrors a tier (%s) it does not have" % [entry["id"], target])


func test_one_game_conditions_read_real_fields() -> void:
	var fields: Dictionary = GamePuckRules.game_dict(PlayerStats.new())
	for entry: Dictionary in GamePucks.ALL:
		if GamePucks.kind_of(entry) == "game":
			var field: String = String((entry["cond"] as Dictionary)["field"])
			assert_true(fields.has(field), "%s reads unknown field %s" % [entry["id"], field])


func test_every_banner_requirement_names_a_real_puck_and_tier() -> void:
	for banner: Dictionary in Banners.ALL:
		var needs: Array[String] = Banners.needs_of(banner)
		assert_false(needs.is_empty(), "%s needs nothing" % banner["id"])
		for req: String in needs:
			var puck: Dictionary = GamePucks.find(Banners.requirement_puck(req))
			assert_false(puck.is_empty(), "%s needs unknown puck %s" % [banner["id"], req])
			if puck.is_empty():
				continue
			var target: int = Banners.requirement_target(req)
			if GamePucks.is_ladder(puck):
				assert_has(GamePucks.tiers_of(puck), target,
						"%s needs %s, which is not one of its tiers" % [banner["id"], req])
			else:
				assert_eq(target, 0, "%s names a tier on a single puck: %s" % [banner["id"], req])


func test_every_banner_title_is_a_title_and_every_title_is_awarded() -> void:
	var awarded: Dictionary = {}
	for banner: Dictionary in Banners.ALL:
		var title: String = Banners.title_of(banner)
		if title.is_empty():
			continue
		assert_true(Titles.is_known(title), "%s awards unknown title %s" % [banner["id"], title])
		awarded[title] = true
	var seen: Dictionary = {}
	for title: String in Titles.ALL:
		assert_false(seen.has(title), "duplicate title %s" % title)
		seen[title] = true
		assert_true(awarded.has(title), "no banner awards the %s title" % title)
		assert_ne(title, "", "\"\" is reserved for no title")


func test_titles_coerce_to_none_when_unknown() -> void:
	assert_eq(Titles.coerce("power_forward"), "power_forward")
	assert_eq(Titles.coerce("grand_poobah"), "")
	assert_eq(Titles.coerce(""), "")


func test_every_puck_and_banner_is_named_in_the_locale_catalogue() -> void:
	var keys: Dictionary = _catalogue_keys()
	var missing: Array[String] = []
	for entry: Dictionary in GamePucks.ALL:
		var id: String = entry["id"]
		for key: StringName in [GamePucks.name_key(id), GamePucks.desc_key(id)]:
			if not keys.has(String(key)):
				missing.append(String(key))
	for banner: Dictionary in Banners.ALL:
		var key: String = String(Banners.name_key(String(banner["id"])))
		if not keys.has(key):
			missing.append(key)
	for title: String in Titles.ALL:
		var key: String = String(Titles.name_key(title))
		if not keys.has(key):
			missing.append(key)
	assert_true(missing.is_empty(), "missing locale rows: " + ", ".join(missing))


func test_every_ladder_tier_has_a_numeral() -> void:
	for entry: Dictionary in GamePucks.ALL:
		if GamePucks.is_ladder(entry):
			assert_lte(GamePucks.tiers_of(entry).size(), TrophyCopy.TIER_KEYS.size(),
					"%s has more tiers than TrophyCopy has numerals" % entry["id"])


func test_steam_ids_are_unique_and_keep_every_shipped_achievement() -> void:
	var ids: Array[String] = GamePucks.all_steam_ids()
	var seen: Dictionary = {}
	for id: String in ids:
		assert_false(seen.has(id), "two pucks mirror %s" % id)
		seen[id] = true
	for id: String in _SHIPPED_STEAM_IDS:
		assert_true(seen.has(id), "%s is no longer mirrored by any puck" % id)


func test_every_mirrored_id_is_listed_for_steamworks() -> void:
	var doc: String = FileAccess.get_file_as_string(_STEAM_DOC)
	assert_false(doc.is_empty(), "could not read " + _STEAM_DOC)
	for id: String in GamePucks.all_steam_ids():
		assert_true(doc.contains("`%s`" % id), "%s is not in steam/ACHIEVEMENTS.md" % id)


func test_event_lookups_resolve_and_fail_closed() -> void:
	assert_eq(GamePucks.event_puck("big_hit"), GamePucks.FREIGHT_TRAIN)
	assert_gt(GamePucks.event_threshold("big_hit"), 0.0)
	assert_eq(GamePucks.event_puck("tutorials_done"), GamePucks.STUDENT)
	assert_eq(GamePucks.event_puck("build_edited"), GamePucks.CUSTOM_BUILD)
	assert_eq(GamePucks.event_puck("nope"), "")
	assert_eq(GamePucks.event_threshold("nope"), -1.0)


func _catalogue_keys() -> Dictionary:
	var out: Dictionary = {}
	var f: FileAccess = FileAccess.open(_CATALOGUE, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() > 0:
			out[row[0]] = true
	return out

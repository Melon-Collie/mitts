extends GutTest

# The Game Puck catalogue and what it unlocks hold together: ids unique, ladders
# ascending, every combo, title and cosmetic reward naming a real puck and tier,
# no combo needing itself, every puck and title named in the locale catalogue
# (a title as its puck is), and every Steam-mirrored id listed in
# steam/ACHIEVEMENTS.md (the Steamworks side, which the code cannot check).

const _CATALOGUE: String = "res://locale/translations.csv"
const _STEAM_DOC: String = "res://steam/ACHIEVEMENTS.md"

# The achievements the Steam apps define, each still mirrored so no Steam unlock
# a player holds is orphaned.
const _SHIPPED_STEAM_IDS: Array[String] = [
	"ACH_FIRST_GOAL", "ACH_HAT_TRICK", "ACH_THREE_HELPERS", "ACH_BIG_NIGHT",
	"ACH_BRICK_WALL", "ACH_ONE_TIMER", "ACH_TIP_IN", "ACH_OVERTIME_HERO",
	"ACH_FACEOFF_BOSS", "ACH_PICKPOCKET", "ACH_SHUTOUT", "ACH_FIRST_WIN",
	"ACH_FREIGHT_TRAIN", "ACH_STUDENT", "ACH_CUSTOM_BUILD", "ACH_PLAY_WITH_BUUKIE",
	"ACH_GOALS_50", "ACH_SETUP_ARTIST", "ACH_ENFORCER", "ACH_VETERAN",
]


func test_puck_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for entry: Dictionary in GamePucks.ALL:
		var id: String = entry["id"]
		assert_false(seen.has(id), "duplicate puck id: %s" % id)
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
			var mins: Dictionary = GamePucks.game_mins(entry)
			assert_false(mins.is_empty(), "%s asks for nothing" % entry["id"])
			for field: Variant in mins:
				assert_true(fields.has(field), "%s reads unknown field %s" % [entry["id"], field])


func test_every_requirement_names_a_real_puck_and_tier() -> void:
	for entry: Dictionary in GamePucks.ALL:
		if GamePucks.is_combo(entry):
			assert_false(GamePucks.needs_of(entry).is_empty(), "%s needs nothing" % entry["id"])
			for req: String in GamePucks.needs_of(entry):
				_assert_requirement(req, String(entry["id"]))
	for row: Dictionary in Titles.ALL:
		_assert_requirement(String(row["puck"]), "title " + String(row["id"]))
	for req: String in CosmeticUnlocks.reward_pucks():
		_assert_requirement(req, "a cosmetic reward")


func test_no_combo_needs_itself() -> void:
	for entry: Dictionary in GamePucks.ALL:
		if GamePucks.is_combo(entry):
			var id: String = entry["id"]
			assert_false(_reaches(id, id, {}), "%s needs itself through its chain" % id)


func test_every_title_is_unlocked_and_named_as_its_puck() -> void:
	var rows: Dictionary = _catalogue_rows()
	var seen: Dictionary = {}
	for row: Dictionary in Titles.ALL:
		var title: String = row["id"]
		assert_ne(title, "", "\"\" is reserved for no title")
		assert_false(seen.has(title), "duplicate title %s" % title)
		seen[title] = true
		var req: String = row["puck"]
		if GamePucks.requirement_target(req) > 0:
			continue
		var title_row: PackedStringArray = rows.get(String(Titles.name_key(title)), [])
		var puck_row: PackedStringArray = rows.get(
				String(GamePucks.name_key(GamePucks.requirement_puck(req))), [])
		assert_eq(title_row.slice(1), puck_row.slice(1),
				"the %s title reads as its puck does, in every language" % title)


func test_every_feat_puck_has_a_rule_and_every_rule_a_puck() -> void:
	var rows: Array[String] = []
	for entry: Dictionary in GamePucks.ALL:
		if GamePucks.kind_of(entry) == "feat":
			rows.append(String(entry["id"]))
	for feat: String in FeatRules.ALL:
		assert_has(rows, feat, "FeatRules detects %s but no puck awards it" % feat)
	for id: String in rows:
		assert_has(FeatRules.ALL, id, "puck %s is a feat nothing detects" % id)


func test_titles_coerce_to_none_when_unknown() -> void:
	assert_eq(Titles.coerce("power_forward"), "power_forward")
	assert_eq(Titles.coerce("grand_poobah"), "")
	assert_eq(Titles.coerce(""), "")


func test_every_puck_and_title_is_named_in_the_locale_catalogue() -> void:
	var keys: Dictionary = _catalogue_rows()
	var missing: Array[String] = []
	for entry: Dictionary in GamePucks.ALL:
		var id: String = entry["id"]
		var needed: Array[StringName] = [GamePucks.name_key(id)]
		if not GamePucks.is_combo(entry):
			needed.append(GamePucks.desc_key(id))
		for key: StringName in needed:
			if not keys.has(String(key)):
				missing.append(String(key))
	for row: Dictionary in Titles.ALL:
		var key: String = String(Titles.name_key(String(row["id"])))
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


# Steam shows the name steam/ACHIEVEMENTS.md gives an achievement; it must read
# as the puck does in game, a ladder tier with its numeral.
func test_every_mirrored_achievement_is_named_as_its_puck() -> void:
	var rows: Dictionary = _catalogue_rows()
	var names: Dictionary = _steam_doc_names()
	for entry: Dictionary in GamePucks.ALL:
		var id: String = entry["id"]
		var base: String = String((rows.get(String(GamePucks.name_key(id)), ["", ""])
				as PackedStringArray)[1])
		if entry.has("steam"):
			assert_eq(names.get(String(entry["steam"]), ""), base, "%s's Steam name" % id)
		var tiers: Array[int] = GamePucks.tiers_of(entry)
		var steam_tiers: Dictionary = entry.get("steam_tiers", {})
		for target: Variant in steam_tiers:
			var numeral: String = String((rows[String(TrophyCopy.TIER_KEYS[
					tiers.find(int(target))])] as PackedStringArray)[1])
			assert_eq(names.get(String(steam_tiers[target]), ""), "%s %s" % [base, numeral],
					"%s@%s's Steam name" % [id, target])


func test_event_lookups_resolve_and_fail_closed() -> void:
	assert_eq(GamePucks.event_puck("big_hit"), GamePucks.FREIGHT_TRAIN)
	assert_gt(GamePucks.event_threshold("big_hit"), 0.0)
	assert_eq(GamePucks.event_puck("tutorials_done"), GamePucks.STUDENT)
	assert_eq(GamePucks.event_puck("build_edited"), GamePucks.CUSTOM_BUILD)
	assert_eq(GamePucks.event_puck("cup_won"), GamePucks.CUP_WINNER)
	assert_eq(GamePucks.event_puck("nope"), "")
	assert_eq(GamePucks.event_threshold("nope"), -1.0)


func _assert_requirement(req: String, who: String) -> void:
	var puck: Dictionary = GamePucks.find(GamePucks.requirement_puck(req))
	assert_false(puck.is_empty(), "%s needs unknown puck %s" % [who, req])
	if puck.is_empty():
		return
	var target: int = GamePucks.requirement_target(req)
	if GamePucks.is_ladder(puck):
		assert_has(GamePucks.tiers_of(puck), target,
				"%s needs %s, which is not one of its tiers" % [who, req])
	else:
		assert_eq(target, 0, "%s names a tier on a single puck: %s" % [who, req])


# Whether `from`'s chain of combos reaches `target`.
func _reaches(from: String, target: String, visited: Dictionary) -> bool:
	for req: String in GamePucks.needs_of(GamePucks.find(from)):
		var next: String = GamePucks.requirement_puck(req)
		if next == target:
			return true
		if visited.has(next):
			continue
		visited[next] = true
		if _reaches(next, target, visited):
			return true
	return false


# The Name column of steam/ACHIEVEMENTS.md's table, by API Name.
func _steam_doc_names() -> Dictionary:
	var out: Dictionary = {}
	for line: String in FileAccess.get_file_as_string(_STEAM_DOC).split("\n"):
		var cells: PackedStringArray = line.split("|")
		if cells.size() > 3 and cells[1].strip_edges().begins_with("`ACH_"):
			out[cells[1].strip_edges().trim_prefix("`").trim_suffix("`")] = cells[2].strip_edges()
	return out


# Every catalogue row by its key.
func _catalogue_rows() -> Dictionary:
	var out: Dictionary = {}
	var f: FileAccess = FileAccess.open(_CATALOGUE, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() > 0:
			out[row[0]] = row
	return out

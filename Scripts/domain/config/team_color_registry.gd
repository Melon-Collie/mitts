class_name TeamColorRegistry

# Loads team color presets on first use.
# Load order: user://team_colors.json (player's editable copy) →
#             res://data/team_colors.json (bundled defaults) →
#             hardcoded fallback (if both are missing or malformed).
#
# Players who want to customize colors place a team_colors.json in their
# game data directory (user://) — no other setup is required.
# Unknown preset IDs return a fallback and log a warning; they never crash.

const DEFAULT_HOME_ID: String = "penguins"
const DEFAULT_AWAY_ID: String  = "leafs"

const _USER_JSON_PATH: String = "user://team_colors.json"
const _RES_JSON_PATH:  String = "res://data/team_colors.json"

static var _presets: Dictionary = {}
static var _preset_ids: Array[String] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# Try the player's editable copy first, then the bundled defaults.
	for path: String in [_USER_JSON_PATH, _RES_JSON_PATH]:
		if _try_load_from(path):
			return
	push_error("TeamColorRegistry: no valid JSON found in user:// or res://")
	_load_hardcoded_fallback()


static func get_preset(id: String) -> Dictionary:
	ensure_loaded()
	if _presets.has(id):
		return _presets[id]
	push_warning("TeamColorRegistry: unknown preset '%s', using default" % id)
	return _presets.get(DEFAULT_HOME_ID, _hardcoded_penguins())


# Returns the color set appropriate for the given team slot.
# team_id == 0 → home (dark jersey), team_id == 1 → away (white jersey).
# Merges top-level primary/secondary with the slot-specific fields.
static func get_colors(id: String, team_id: int) -> Dictionary:
	var preset: Dictionary = get_preset(id)
	var slot: Dictionary = preset.home if team_id == 0 else preset.away
	return {
		"primary":        preset.primary,
		"secondary":      preset.secondary,
		"helmet":         slot.helmet,
		"jersey":         slot.jersey,
		"jersey_stripe":  slot.jersey_stripe,
		"gloves":         slot.gloves,
		"pants":          slot.pants,
		"pants_stripe":   slot.pants_stripe,
		"socks":          slot.socks,
		"socks_stripe":   slot.socks_stripe,
		"goalie_pads":    slot.goalie_pads,
		"text":           slot.text,
		"text_outline":   slot.text_outline,
	}


static func get_all_ids() -> Array[String]:
	ensure_loaded()
	return _preset_ids.duplicate()


static func get_preset_name(id: String) -> String:
	return get_preset(id).get("name", id)


static func _try_load_from(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	if not data is Dictionary or not data.has("presets"):
		push_error("TeamColorRegistry: malformed JSON in %s" % path)
		return false
	var count: int = 0
	for entry: Dictionary in data["presets"]:
		var id: String = entry.get("id", "")
		if id.is_empty():
			continue
		var home: Dictionary = entry.get("home", {})
		var away: Dictionary = entry.get("away", {})
		_presets[id] = {
			"id":        id,
			"name":      entry.get("name", id),
			"primary":   _parse_color(entry.get("primary",   "#FFFFFF")),
			"secondary": _parse_color(entry.get("secondary", "#FFFFFF")),
			"home": {
				"helmet":        _parse_color(home.get("helmet",        "#FFFFFF")),
				"jersey":        _parse_color(home.get("jersey",        "#FFFFFF")),
				"jersey_stripe": _parse_color(home.get("jersey_stripe", "#000000")),
				"gloves":        _parse_color(home.get("gloves",        "#000000")),
				"pants":         _parse_color(home.get("pants",         "#FFFFFF")),
				"pants_stripe":  _parse_color(home.get("pants_stripe",  "#000000")),
				"socks":         _parse_color(home.get("socks",         "#FFFFFF")),
				"socks_stripe":  _parse_color(home.get("socks_stripe",  "#000000")),
				"goalie_pads":   _parse_color(home.get("goalie_pads",   "#FFFFFF")),
				"text":          _parse_color(home.get("text",          "#000000")),
				"text_outline":  _parse_color(home.get("text_outline",  "#FFFFFF")),
			},
			"away": {
				"helmet":        _parse_color(away.get("helmet",        "#FFFFFF")),
				"jersey":        _parse_color(away.get("jersey",        "#FFFFFF")),
				"jersey_stripe": _parse_color(away.get("jersey_stripe", "#000000")),
				"gloves":        _parse_color(away.get("gloves",        "#000000")),
				"pants":         _parse_color(away.get("pants",         "#FFFFFF")),
				"pants_stripe":  _parse_color(away.get("pants_stripe",  "#000000")),
				"socks":         _parse_color(away.get("socks",         "#FFFFFF")),
				"socks_stripe":  _parse_color(away.get("socks_stripe",  "#000000")),
				"goalie_pads":   _parse_color(away.get("goalie_pads",   "#FFFFFF")),
				"text":          _parse_color(away.get("text",          "#000000")),
				"text_outline":  _parse_color(away.get("text_outline",  "#FFFFFF")),
			},
		}
		if not _preset_ids.has(id):
			_preset_ids.append(id)
		count += 1
	if count == 0:
		push_warning("TeamColorRegistry: %s contained no valid presets" % path)
		return false
	return true


static func _parse_color(hex: String) -> Color:
	return Color.from_string(hex, Color.WHITE)


static func _load_hardcoded_fallback() -> void:
	var p: Dictionary = _hardcoded_penguins()
	_presets[p.id] = p
	if not _preset_ids.has(p.id):
		_preset_ids.append(p.id)
	var l: Dictionary = _hardcoded_leafs()
	_presets[l.id] = l
	if not _preset_ids.has(l.id):
		_preset_ids.append(l.id)


static func _hardcoded_penguins() -> Dictionary:
	return {
		"id":        DEFAULT_HOME_ID,
		"name":      "Pittsburgh Penguins",
		"primary":   Color(0.988, 0.710, 0.078),
		"secondary": Color(0.06,  0.06,  0.06),
		"home": {
			"helmet":        Color(0.06,  0.06,  0.06),
			"jersey":        Color(0.988, 0.710, 0.078),
			"jersey_stripe": Color(0.06,  0.06,  0.06),
			"gloves":        Color(0.06,  0.06,  0.06),
			"pants":         Color(0.06,  0.06,  0.06),
			"pants_stripe":  Color(0.988, 0.710, 0.078),
			"socks":         Color(0.988, 0.710, 0.078),
			"socks_stripe":  Color(0.06,  0.06,  0.06),
			"goalie_pads":   Color(1.0,   1.0,   1.0),
			"text":          Color(0.06,  0.06,  0.06),
			"text_outline":  Color(0.988, 0.710, 0.078),
		},
		"away": {
			"helmet":        Color(0.06,  0.06,  0.06),
			"jersey":        Color(1.0,   1.0,   1.0),
			"jersey_stripe": Color(0.988, 0.710, 0.078),
			"gloves":        Color(0.06,  0.06,  0.06),
			"pants":         Color(1.0,   1.0,   1.0),
			"pants_stripe":  Color(0.988, 0.710, 0.078),
			"socks":         Color(1.0,   1.0,   1.0),
			"socks_stripe":  Color(0.988, 0.710, 0.078),
			"goalie_pads":   Color(0.988, 0.710, 0.078),
			"text":          Color(0.06,  0.06,  0.06),
			"text_outline":  Color(0.988, 0.710, 0.078),
		},
	}


static func _hardcoded_leafs() -> Dictionary:
	return {
		"id":        DEFAULT_AWAY_ID,
		"name":      "Toronto Maple Leafs",
		"primary":   Color(0.000, 0.125, 0.357),
		"secondary": Color(1.0,   1.0,   1.0),
		"home": {
			"helmet":        Color(0.000, 0.125, 0.357),
			"jersey":        Color(0.000, 0.125, 0.357),
			"jersey_stripe": Color(1.0,   1.0,   1.0),
			"gloves":        Color(0.000, 0.125, 0.357),
			"pants":         Color(0.000, 0.125, 0.357),
			"pants_stripe":  Color(1.0,   1.0,   1.0),
			"socks":         Color(0.000, 0.125, 0.357),
			"socks_stripe":  Color(1.0,   1.0,   1.0),
			"goalie_pads":   Color(1.0,   1.0,   1.0),
			"text":          Color(1.0,   1.0,   1.0),
			"text_outline":  Color(0.000, 0.125, 0.357),
		},
		"away": {
			"helmet":        Color(0.000, 0.125, 0.357),
			"jersey":        Color(1.0,   1.0,   1.0),
			"jersey_stripe": Color(0.000, 0.125, 0.357),
			"gloves":        Color(0.000, 0.125, 0.357),
			"pants":         Color(1.0,   1.0,   1.0),
			"pants_stripe":  Color(0.000, 0.125, 0.357),
			"socks":         Color(1.0,   1.0,   1.0),
			"socks_stripe":  Color(0.000, 0.125, 0.357),
			"goalie_pads":   Color(1.0,   1.0,   1.0),
			"text":          Color(0.000, 0.125, 0.357),
			"text_outline":  Color(0.000, 0.125, 0.357),
		},
	}

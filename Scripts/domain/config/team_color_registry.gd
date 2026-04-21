class_name TeamColorRegistry

# Loads team color presets from res://data/team_colors.json on first use.
# Pure static class — no scene-tree APIs. FileAccess/JSON are acceptable here.
# If the JSON file is missing or malformed, falls back to hardcoded defaults so
# the game still boots without the data file.

const DEFAULT_HOME_ID: String = "penguins"
const DEFAULT_AWAY_ID: String  = "leafs"

const _JSON_PATH: String = "res://data/team_colors.json"

static var _presets: Dictionary = {}
static var _preset_ids: Array[String] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("TeamColorRegistry: cannot open %s" % _JSON_PATH)
		_load_hardcoded_fallback()
		return
	var text: String = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	if not data is Dictionary or not data.has("presets"):
		push_error("TeamColorRegistry: malformed JSON in %s" % _JSON_PATH)
		_load_hardcoded_fallback()
		return
	for entry: Dictionary in data["presets"]:
		var id: String = entry.get("id", "")
		if id.is_empty():
			continue
		_presets[id] = {
			"id":           id,
			"name":         entry.get("name", id),
			"primary":      _parse_color(entry.get("primary",      "#FFFFFF")),
			"secondary":    _parse_color(entry.get("secondary",    "#FFFFFF")),
			"helmet":       _parse_color(entry.get("helmet",       "#FFFFFF")),
			"jersey":       _parse_color(entry.get("jersey",       "#FFFFFF")),
			"pants":        _parse_color(entry.get("pants",        "#FFFFFF")),
			"goalie_pads":  _parse_color(entry.get("goalie_pads",  "#FFFFFF")),
			"text":         _parse_color(entry.get("text",         "#FFFFFF")),
			"text_outline": _parse_color(entry.get("text_outline", "#000000")),
		}
		_preset_ids.append(id)
	if _preset_ids.is_empty():
		push_warning("TeamColorRegistry: JSON contained no valid presets, using fallback")
		_load_hardcoded_fallback()


static func get_preset(id: String) -> Dictionary:
	ensure_loaded()
	if _presets.has(id):
		return _presets[id]
	push_warning("TeamColorRegistry: unknown preset '%s', using default" % id)
	return _presets.get(DEFAULT_HOME_ID, _hardcoded_penguins())


static func get_all_ids() -> Array[String]:
	ensure_loaded()
	return _preset_ids.duplicate()


static func get_name(id: String) -> String:
	return get_preset(id).get("name", id)


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
		"id":           DEFAULT_HOME_ID,
		"name":         "Pittsburgh Gold",
		"primary":      Color(0.988, 0.710, 0.078),
		"secondary":    Color(0.06,  0.06,  0.06),
		"helmet":       Color(0.06,  0.06,  0.06),
		"jersey":       Color(0.988, 0.710, 0.078),
		"pants":        Color(0.06,  0.06,  0.06),
		"goalie_pads":  Color(1.0,   1.0,   1.0),
		"text":         Color(0.06,  0.06,  0.06),
		"text_outline": Color(0.988, 0.710, 0.078),
	}


static func _hardcoded_leafs() -> Dictionary:
	return {
		"id":           DEFAULT_AWAY_ID,
		"name":         "Toronto Blue",
		"primary":      Color(0.000, 0.125, 0.357),
		"secondary":    Color(1.0,   1.0,   1.0),
		"helmet":       Color(0.000, 0.125, 0.357),
		"jersey":       Color(0.000, 0.125, 0.357),
		"pants":        Color(1.0,   1.0,   1.0),
		"goalie_pads":  Color(1.0,   1.0,   1.0),
		"text":         Color(1.0,   1.0,   1.0),
		"text_outline": Color(0.000, 0.125, 0.357),
	}

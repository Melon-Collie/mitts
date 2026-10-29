class_name TeamColorRegistry

# Loads team color presets on first use.
# Load order: user://team_colors.json (player's editable copy) →
#             res://data/team_colors.json (bundled defaults) →
#             hardcoded fallback (if both are missing or malformed).
#
# Schema: mitts.jersey.v2. Each team has home + away kits with structured
# regions (jersey/arms/pants/socks/shoulders) carrying a base color plus
# an array of {pos, width, color} stripes painted over the region's UV
# range. See data/team_colors.json for the description.
#
# get_colors(slot, team_id) returns a Dictionary that's a hybrid:
#   - Flat legacy keys (primary, secondary, light, helmet, gloves,
#     goalie_pads, goalie_accent, text, text_outline, jersey, jersey_stripe, pants,
#     pants_stripe, socks, socks_stripe) for simple consumers (replay
#     records, goalie/spawn paint) — *_stripe are derived from the first
#     stripe color of the matching region (or the region base if no stripes).
#   - UI palette keys (ui_base, ui_stripe, ui_text) — the canonical 3-color
#     scheme for HUD/lobby surfaces (scorebug header, lobby slot cards). See
#     get_ui_colors() for the home/away rule. UI code should read these, NOT
#     the jersey/* keys (those mirror the 3D uniform mesh and look muddy in
#     flat UI panels).
#   - A nested "uniform" sub-dict carrying the full v2 detail
#     (shoulders, jersey-with-yoke-and-stripes, arms.upper/lower,
#     pants-with-stripes, socks-with-stripes). The skater painter
#     consumes this; UI accent code doesn't need to touch it.
#
# Color identity is an integer slot: the team's index in the loaded array.
# Out-of-range slots return a fallback and log a warning; they never crash.

const DEFAULT_HOME_SLOT: int = 0
const DEFAULT_AWAY_SLOT: int = 1

const USER_JSON_PATH: String = "user://team_colors.json"
const RES_JSON_PATH:  String = "res://data/team_colors.json"
const _SCHEMA_ID: String = "mitts.jersey.v2"

# Fallback "light" (away body) for presets that predate the field or come
# from a malformed file. A faint cool white so the away card still reads as a
# card against the dark lobby/HUD panels.
const _UI_WHITE: Color = Color(0.949, 0.957, 0.969)  # #F2F4F7

static var _presets: Array[Dictionary] = []
static var _loaded: bool = false
# The file the presets came from; empty when the hardcoded fallback is in use.
static var _loaded_path: String = ""


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in [USER_JSON_PATH, RES_JSON_PATH]:
		if _try_load_from(path):
			return
	push_error("TeamColorRegistry: no valid JSON found in user:// or res://")
	_load_hardcoded_fallback()


static func get_preset(slot: int) -> Dictionary:
	ensure_loaded()
	if slot >= 0 and slot < _presets.size():
		return _presets[slot]
	push_warning("TeamColorRegistry: unknown slot '%d', using default" % slot)
	if _presets.size() > DEFAULT_HOME_SLOT:
		return _presets[DEFAULT_HOME_SLOT]
	return _hardcoded_pomegranate()


# Returns the merged color set for a given team slot + side.
# team_id == 0 → home, team_id == 1 → away.
static func get_colors(slot: int, team_id: int) -> Dictionary:
	var preset: Dictionary = get_preset(slot)
	var kit: Dictionary = preset.home if team_id == 0 else preset.away
	var jersey_block: Dictionary = kit.jersey
	var pants_block: Dictionary  = kit.pants
	var socks_block: Dictionary  = kit.socks
	var shoulders: Dictionary    = kit.shoulders
	var ui: Dictionary           = get_ui_colors(slot, team_id)
	return {
		"primary":        preset.primary,
		"secondary":      preset.secondary,
		"light":          preset.get("light", _UI_WHITE),
		"ui_base":        ui.base,
		"ui_stripe":      ui.stripe,
		"ui_text":        ui.text,
		"helmet":         kit.helmet,
		"jersey":         jersey_block.base,
		"jersey_stripe":  _accent_color(jersey_block, shoulders.color),
		"gloves":         kit.gloves,
		# A glove design's SECOND color is whichever team color the glove body
		# is not. Most presets dress their gloves in the secondary, so a design
		# that reached for the secondary again would paint those teams a
		# monochrome glove — this is the only derived color that has to look at
		# what it is contrasting against.
		"glove_accent":   preset.primary if kit.gloves.is_equal_approx(preset.secondary) \
				else preset.secondary,
		"pants":          pants_block.base,
		"pants_stripe":   _accent_color(pants_block, shoulders.color),
		"socks":          socks_block.base,
		"socks_stripe":   _accent_color(socks_block, shoulders.color),
		"goalie_pads":    kit.goalie_pads,
		"goalie_accent":  _goalie_accent(preset, kit.goalie_pads),
		"text":           kit.text.color,
		"text_outline":   kit.text.outline,
		"uniform":        kit,
		# The whole team, both kits: the chest crest takes its colors from all of
		# them, so it is the same crest home and away.
		"preset":         preset,
	}


# Below this contrast ratio against the pads (WCAG's 3:1 for graphics) the
# team's primary is too faint to read as trim on them.
const _GOALIE_ACCENT_MIN_CONTRAST: float = 3.0


# The goalie's trim on his pads, blocker and trapper, which wear the pads'
# colour: the team's primary, unless it is too faint on the pads — a yellow on
# white, or a team that dressed its pads in its primary — and then whichever of
# its two colours stands out more.
static func _goalie_accent(preset: Dictionary, pads: Color) -> Color:
	var primary: Color = preset.primary
	var secondary: Color = preset.secondary
	var p: float = contrast_ratio(primary, pads)
	if p >= _GOALIE_ACCENT_MIN_CONTRAST:
		return primary
	return primary if p >= contrast_ratio(secondary, pads) else secondary


# WCAG contrast ratio between two colours, 1 (identical) to 21 (black on white).
static func contrast_ratio(a: Color, b: Color) -> float:
	var la: float = _relative_luminance(a)
	var lb: float = _relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _relative_luminance(c: Color) -> float:
	var l: Color = c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


# Canonical UI palette for a team's side. The single source of truth for how
# HUD/lobby surfaces color a home/away team — keep all UI panels routed through
# here (directly, or via get_colors' ui_base/ui_stripe/ui_text keys) so the
# scheme stays consistent.
#
#   Home (team_id 0): primary body, secondary stripe, light lettering.
#   Away (team_id 1): light body, primary stripe, primary lettering.
#
# A preset with a `ui_ink` letters both sides in it instead — for a primary
# too light to read against white and too dark for white to read on it.
#
# Returns { base, stripe, text } as Colors.
static func get_ui_colors(slot: int, team_id: int) -> Dictionary:
	var preset: Dictionary = get_preset(slot)
	var light: Color = preset.get("light", _UI_WHITE)
	var ink: Variant = preset.get("ui_ink")
	if team_id == 0:
		return {"base": preset.primary, "stripe": preset.secondary,
				"text": light if ink == null else ink}
	return {"base": light, "stripe": preset.primary,
			"text": preset.primary if ink == null else ink}


# Stripe colors for score surfaces (scorebug + box-score period summary): each
# team always wears its own primary, so a team's color stays fixed no matter
# who it's playing. Returns { home, away } as Colors.
static func get_score_stripe_pair(home_slot: int, away_slot: int) -> Dictionary:
	return {
		"home": get_preset(home_slot).primary,
		"away": get_preset(away_slot).primary,
	}


static func get_all_slots() -> Array[int]:
	ensure_loaded()
	var result: Array[int] = []
	for i: int in _presets.size():
		result.append(i)
	return result


static func get_preset_name(slot: int) -> String:
	return get_preset(slot).get("name", "Slot %d" % slot)


# Pick the "accent" color for legacy *_stripe consumers: first stripe of
# the region, or the shoulder color if the region has no stripes.
static func _accent_color(region: Dictionary, fallback: Color) -> Color:
	var stripes: Array = region.get("stripes", [])
	if stripes.size() > 0:
		return stripes[0].color
	return fallback


static func _try_load_from(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(text)
	if not accepts(data):
		push_error("TeamColorRegistry: %s is not a %s file with teams" % [path, _SCHEMA_ID])
		return false
	var data_dict: Dictionary = data
	_presets.clear()
	for entry: Dictionary in data_dict.teams:
		_presets.append({
			"name":      entry.get("name", "Slot %d" % _presets.size()),
			"primary":   _parse_color(entry.get("primary",   "#FFFFFF")),
			"secondary": _parse_color(entry.get("secondary", "#FFFFFF")),
			"light":     _parse_color(entry.get("light",     "#F2F4F7")),
			"ui_ink":    _parse_optional_color(entry.get("ui_ink", null)),
			"home":      _parse_kit(entry.get("home", {})),
			"away":      _parse_kit(entry.get("away", {})),
		})
	_loaded_path = path
	return true


# Whether parsed JSON is a colors file the loader takes: the schema, and at
# least one team. The Options menu asks this of a player's edited copy.
static func accepts(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var d: Dictionary = data
	return d.get("schema", "") == _SCHEMA_ID and d.get("teams") is Array \
			and not (d.teams as Array).is_empty()


static func loaded_path() -> String:
	ensure_loaded()
	return _loaded_path


static func _parse_kit(raw: Dictionary) -> Dictionary:
	var shoulders_raw: Dictionary = raw.get("shoulders", {})
	var jersey_raw:    Dictionary = raw.get("jersey",    {})
	var arms_raw:      Dictionary = raw.get("arms",      {})
	var arms_upper:    Dictionary = arms_raw.get("upper", {})
	var arms_lower:    Dictionary = arms_raw.get("lower", {})
	var pants_raw:     Dictionary = raw.get("pants",     {})
	var socks_raw:     Dictionary = raw.get("socks",     {})
	var text_raw:      Dictionary = raw.get("text",      {})
	var arms := {
		"elbow": _parse_optional_color(arms_raw.get("elbow", null)),
		"upper": {
			"base":    _parse_color(arms_upper.get("base",    "#FFFFFF")),
			"stripes": _parse_stripes(arms_upper.get("stripes", [])),
		},
		"lower": {
			"base":    _parse_color(arms_lower.get("base",    "#FFFFFF")),
			"stripes": _parse_stripes(arms_lower.get("stripes", [])),
		},
	}
	var shoulder_color: Color = _parse_color(shoulders_raw.get("color", "#FFFFFF"))
	# The sleeve is the kit's arm (SleevePaint); a kit still in the two-segment
	# form is read into one, and a sleeve hands the two-segment form back to the
	# bodies that paint the arm in two.
	var sleeve: Dictionary
	if raw.has("sleeve"):
		var sleeve_raw: Dictionary = raw.sleeve
		sleeve = {
			"base":    _parse_color(sleeve_raw.get("base", "#FFFFFF")),
			"stripes": _parse_stripes(sleeve_raw.get("stripes", []), true),
		}
		arms.upper = SleevePaint.segment(sleeve, true)
		arms.lower = SleevePaint.segment(sleeve, false)
		shoulder_color = SleevePaint.color_at(sleeve,
				SleevePaint.pos_of(SleevePaint.NUMBER_CENTER_M))
	else:
		sleeve = SleevePaint.from_legacy(arms, shoulder_color)
	return {
		"helmet":      _parse_color(raw.get("helmet", "#FFFFFF")),
		"shoulders": {
			"color":   shoulder_color,
			"text":    _parse_color(shoulders_raw.get("text",    "#FFFFFF")),
			"stroke":  _parse_stroke(shoulders_raw.get("stroke", null)),
		},
		"jersey": {
			"base":    _parse_color(jersey_raw.get("base",    "#FFFFFF")),
			"yoke":    _parse_optional_color(jersey_raw.get("yoke", null)),
			"collar":  _parse_optional_color(jersey_raw.get("collar", null)),
			"stripes": _parse_stripes(jersey_raw.get("stripes", []), true),
		},
		"sleeve":      sleeve,
		"arms":        arms,
		"gloves":      _parse_color(raw.get("gloves", "#FFFFFF")),
		"pants": {
			"base":    _parse_color(pants_raw.get("base",    "#FFFFFF")),
			"stripes": _parse_stripes(pants_raw.get("stripes", [])),
		},
		"socks": {
			"base":    _parse_color(socks_raw.get("base",    "#FFFFFF")),
			"stripes": _parse_stripes(socks_raw.get("stripes", [])),
		},
		"goalie_pads": _parse_color(raw.get("goalie_pads", "#FFFFFF")),
		"text": {
			"color":   _parse_color(text_raw.get("color",   "#FFFFFF")),
			"outline": _parse_color(text_raw.get("outline", "#000000")),
			"stroke":  _parse_stroke(text_raw.get("stroke", null)),
		},
	}


# Parses an array of {pos, width, color} stripes into Dictionaries with
# real Color values. Bad entries are skipped with a warning.
# `shaped` reads each stripe's optional `peak` and `fill_below` too
# (StripeOutline); the sleeve and the jersey paint them.
static func _parse_stripes(raw: Variant, shaped: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not raw is Array:
		return out
	for s: Variant in raw:
		if not s is Dictionary:
			continue
		var sd: Dictionary = s
		var stripe := {
			"pos":   float(sd.get("pos",   0.5)),
			"width": float(sd.get("width", 0.0)),
			"color": _parse_color(sd.get("color", "#FFFFFF")),
		}
		var peak: Variant = sd.get("peak")
		if shaped and sd.has("fill_below"):
			stripe.fill_below = _parse_color(sd.fill_below)
		if shaped and peak is Dictionary:
			stripe.peak = {
				"depth": float(peak.get("depth", 0.0)),
				"count": maxi(int(peak.get("count", 1)), 1),
				"u":     float(peak.get("u", 0.5)),
			}
		out.append(stripe)
	return out


static func _parse_color(hex: Variant) -> Color:
	if hex is String:
		return Color.from_string(hex, Color.WHITE)
	return Color.WHITE


# yoke, collar, arms.elbow and ui_ink are optional — null falls back: the collar
# to the yoke, the yoke to the jersey body, the elbow to the sleeve under it,
# the ink to the side's usual lettering.
static func _parse_optional_color(hex: Variant) -> Variant:
	if hex == null:
		return null
	return _parse_color(hex)


# A lettering stroke (text.stroke, shoulders.stroke) is optional too, but
# absent means unbordered, which a transparent Color says to every painter.
static func _parse_stroke(hex: Variant) -> Color:
	if hex == null:
		return Color.TRANSPARENT
	return _parse_color(hex)


static func _load_hardcoded_fallback() -> void:
	_loaded_path = ""
	_presets.clear()
	_presets.append(_hardcoded_pomegranate())
	_presets.append(_hardcoded_blueberry())


static func _hardcoded_pomegranate() -> Dictionary:
	return {
		"name":      "Pomegranate",
		"primary":   _parse_color("#971829"),
		"secondary": _parse_color("#E8445A"),
		"light":     _parse_color("#F5E6D3"),  # mirrors away jersey base
		"home":      _parse_kit({
			"helmet":      "#971829",
			"shoulders":   {"color": "#971829", "text": "#F5E6D3"},
			"jersey":      {"base": "#971829", "stripes": []},
			"arms":        {"upper": {"base": "#971829", "stripes": []},
							"lower": {"base": "#971829", "stripes": []}},
			"gloves":      "#971829",
			"pants":       {"base": "#971829", "stripes": []},
			"socks":       {"base": "#971829", "stripes": []},
			"goalie_pads": "#FFFFFF",
			"text":        {"color": "#F5E6D3", "outline": "#E8445A"},
		}),
		"away":      _parse_kit({
			"helmet":      "#F5E6D3",
			"shoulders":   {"color": "#F5E6D3", "text": "#971829"},
			"jersey":      {"base": "#F5E6D3", "stripes": []},
			"arms":        {"upper": {"base": "#971829", "stripes": []},
							"lower": {"base": "#971829", "stripes": []}},
			"gloves":      "#971829",
			"pants":       {"base": "#971829", "stripes": []},
			"socks":       {"base": "#F5E6D3", "stripes": []},
			"goalie_pads": "#FFFFFF",
			"text":        {"color": "#971829", "outline": "#E8445A"},
		}),
	}


static func _hardcoded_blueberry() -> Dictionary:
	return {
		"name":      "Blueberry",
		"primary":   _parse_color("#3B67C4"),
		"secondary": _parse_color("#6B1E4A"),
		"light":     _parse_color("#FFFFFF"),  # mirrors away jersey base
		"home":      _parse_kit({
			"helmet":      "#6B1E4A",
			"shoulders":   {"color": "#3B67C4", "text": "#FFFFFF"},
			"jersey":      {"base": "#3B67C4", "stripes": []},
			"arms":        {"upper": {"base": "#3B67C4", "stripes": []},
							"lower": {"base": "#3B67C4", "stripes": []}},
			"gloves":      "#6B1E4A",
			"pants":       {"base": "#6B1E4A", "stripes": []},
			"socks":       {"base": "#3B67C4", "stripes": []},
			"goalie_pads": "#FFFFFF",
			"text":        {"color": "#FFFFFF", "outline": "#6B1E4A"},
		}),
		"away":      _parse_kit({
			"helmet":      "#FFFFFF",
			"shoulders":   {"color": "#3B67C4", "text": "#FFFFFF"},
			"jersey":      {"base": "#FFFFFF", "stripes": []},
			"arms":        {"upper": {"base": "#C8D8F0", "stripes": []},
							"lower": {"base": "#C8D8F0", "stripes": []}},
			"gloves":      "#3B67C4",
			"pants":       {"base": "#3B67C4", "stripes": []},
			"socks":       {"base": "#FFFFFF", "stripes": []},
			"goalie_pads": "#FFFFFF",
			"text":        {"color": "#3B67C4", "outline": "#6B1E4A"},
		}),
	}

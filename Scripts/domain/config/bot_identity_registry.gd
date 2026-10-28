class_name BotIdentityRegistry

# Loads the curated list of bot identities used when spawning AI players.
# Load order: user://bot_identities.json (player's editable roster) →
#             res://data/bot_identities.json (bundled roster) →
#             empty list (bots fall back to generic "Bot N" / 80+id / slot-based handedness).
#
# Editable rosters are a feature: a host can craft their own bots — custom
# names, numbers, handedness, and attribute archetypes — by dropping a
# user://bot_identities.json next to their save. Bots are host-authoritative
# online: only the host reads this file (pick_for_slot is gated behind
# NetworkManager.send_bot_slot's is_host check), and the chosen attributes are
# replicated to clients through notify_bot_slot, spawn_remote_skater, and
# sync_existing_players. Clients never consult their own copy, so the host's
# roster is exactly what the whole lobby plays against — no divergence.
#
# Builds are COERCED on load (normalize_entry → the PlayerAttributes
# constructor): v4 axes are all lateral, so there is no legal shape to enforce —
# an out-of-range height/weight/gear value clamps to the nearest legal body
# (weight into the height's BMI band), so a typo neither crashes the game nor
# fields an impossible frame. A super-bot is unrepresentable by construction.
#
# JSON schema (attributes v4, body + gear). Height is inches (67..80 =
# 5'7"..6'8"); weight is lbs inside the height's band (omit for the height's neutral frame);
# gear slots are 0/1/2 with 1 = balanced (profile: 0 agility / 2 power;
# curve: 0 closed / 2 open; flex: 0 whippy / 2 stiff; length: 0 short / 2 long):
#   {
#     "identities": [
#       { "name": "Wayne Gretzky", "number": 99, "is_left_handed": false,
#         "height": 72, "weight": 185, "curve": 2, "position": "C" },
#       ...
#     ]
#   }
#
# Optional cosmetic fields give a card a signature look (all integer indices):
#   tape job — "tape_blade" / "tape_knob" (TapeColorRegistry: 0 team, 1 white,
#     2 black, 3.. the flair colors), "tape_span" (StickTapeConfig.Span),
#     "knob_style" (StickTapeConfig.KnobStyle);
#   gear     — "skate_model" / "glove_model" (GearModelRegistry),
#     "lace_color" (TapeColorRegistry), "stick_model" (StickModelRegistry),
#     "helmet_face" (GearModelRegistry FACE_*: 0 bare / 1 visor / 2 cage /
#     3 fishbowl);
#   hair     — "hair_style" (HairStyleRegistry HAIR_*: 0 short / 1 medium /
#     3 bald / 4 mullet / 5 buzz / 6 shaggy; 2, the retired long, is worn as
#     shaggy), "facial_hair" (FACIAL_*: 0 none / 1 stubble / 2 mustache /
#     3 goatee / 4 full beard / 5 horseshoe / 6 long beard), "hair_color"
#     (COLORS index).
# Pinning ANY field of a group claims the whole group (unpinned fields sit at
# the stock defaults); a card that pins no field of a group draws a stable
# fallback look from its name hash instead (see the fallback tables below), so
# hand-rolled user rosters get variety without authoring. Gear and hair share
# the packed gear code but are separate groups: a card that dresses its bot in
# a visor still gets a rolled haircut.
#
# Fields are optional; missing values default to the neutral build.
#
# A well-formed file with zero entries is valid — the caller treats an empty
# pool as "use the built-in deterministic defaults".

const USER_JSON_PATH: String = "user://bot_identities.json"
const RES_JSON_PATH:  String = "res://data/bot_identities.json"

const _TAPE_KEYS: Array[String] = ["tape_blade", "tape_span", "tape_knob", "knob_style"]
const _GEAR_KEYS: Array[String] = ["skate_model", "glove_model", "lace_color",
		"stick_model", "helmet_face", "jersey_tuck"]
const _HAIR_KEYS: Array[String] = ["hair_style", "facial_hair", "hair_color"]

# TapeColorRegistry indices the fallback tables reach for by name (same local-
# constant convention as GearStyleConfig — these are wire values, not lookups).
const _TAPE_WHITE: int = 1
const _TAPE_BLACK: int = 2
const _LACE_YELLOW: int = 5

# ── Fallback looks for cards that don't pin cosmetics ────────────────────────
# Weighted pick tables, one slice of the name hash per field — the same seam
# spawn_bot uses for an unpinned skin tone — so a bot keeps its look across
# sessions and any roster shows variety without authoring. Weights lean on the
# common real-rink looks (black or white tape, stock boots, the house stick);
# the loud statements (colored tape, a bare blade, the wood stick) are left to
# curated cards so a hash never dresses a bot in a clown suit.
const _FB_BLADE_TAPE: Array[int] = [_TAPE_BLACK, _TAPE_BLACK, _TAPE_BLACK, _TAPE_WHITE,
		_TAPE_WHITE, _TAPE_WHITE, TapeColorRegistry.TEAM_INDEX, _TAPE_BLACK]
const _FB_TAPE_SPAN: Array[int] = [StickTapeConfig.Span.HEEL_TO_MID, StickTapeConfig.Span.FULL,
		StickTapeConfig.Span.MID, StickTapeConfig.Span.HEEL_TO_MID, StickTapeConfig.Span.FULL,
		StickTapeConfig.Span.TOE, StickTapeConfig.Span.MID_TO_TOE, StickTapeConfig.Span.MID]
const _FB_KNOB_TAPE: Array[int] = [_TAPE_WHITE, _TAPE_WHITE, _TAPE_BLACK,
		TapeColorRegistry.TEAM_INDEX, _TAPE_WHITE, _TAPE_BLACK, _TAPE_WHITE,
		TapeColorRegistry.TEAM_INDEX]
const _FB_KNOB_STYLE: Array[int] = [StickTapeConfig.KnobStyle.KNOB, StickTapeConfig.KnobStyle.KNOB,
		StickTapeConfig.KnobStyle.KNOB, StickTapeConfig.KnobStyle.CANDY_CANE,
		StickTapeConfig.KnobStyle.KNOB, StickTapeConfig.KnobStyle.KNOB,
		StickTapeConfig.KnobStyle.FULL, StickTapeConfig.KnobStyle.KNOB]
const _FB_SKATE: Array[int] = [GearModelRegistry.SKATE_BLACKOUT, GearModelRegistry.SKATE_TEAM,
		GearModelRegistry.SKATE_BLACKOUT, GearModelRegistry.SKATE_RETRO,
		GearModelRegistry.SKATE_TEAM, GearModelRegistry.SKATE_TWO_TONE,
		GearModelRegistry.SKATE_PRO, GearModelRegistry.SKATE_BLACKOUT]
const _FB_GLOVE: Array[int] = [GearModelRegistry.GLOVE_TEAM, GearModelRegistry.GLOVE_PRO,
		GearModelRegistry.GLOVE_CONTRAST, GearModelRegistry.GLOVE_TEAM,
		GearModelRegistry.GLOVE_VINTAGE, GearModelRegistry.GLOVE_TWO_TONE,
		GearModelRegistry.GLOVE_TRICOLOR, GearModelRegistry.GLOVE_TEAM]
const _FB_LACES: Array[int] = [_TAPE_WHITE, _TAPE_WHITE, _TAPE_WHITE, _TAPE_BLACK,
		_TAPE_WHITE, _LACE_YELLOW, _TAPE_BLACK, _TAPE_WHITE]
const _FB_STICK: Array[int] = [StickModelRegistry.STICK_STEALTH, StickModelRegistry.STICK_REDLINE,
		StickModelRegistry.STICK_VOLT, StickModelRegistry.STICK_STEALTH,
		StickModelRegistry.STICK_SPLIT, StickModelRegistry.STICK_STEALTH,
		StickModelRegistry.STICK_REDLINE, StickModelRegistry.STICK_STEALTH]
# Visor-heavy like a real pro lineup, with bare heads for the old-school and
# the occasional cage or fishbowl for flavor.
const _FB_FACE: Array[int] = [GearModelRegistry.FACE_VISOR, GearModelRegistry.FACE_VISOR,
		GearModelRegistry.FACE_NONE, GearModelRegistry.FACE_VISOR,
		GearModelRegistry.FACE_CAGE, GearModelRegistry.FACE_VISOR,
		GearModelRegistry.FACE_FISHBOWL, GearModelRegistry.FACE_NONE]
# Short, medium and buzzed cuts dominate, with the odd mullet, shag, flow and
# shaved head. Beards run common, as they do in a dressing room; colours
# lean dark, so a hash rarely lands on a combination that reads as a costume.
const _FB_HAIR: Array[int] = [HairStyleRegistry.HAIR_SHORT, HairStyleRegistry.HAIR_MEDIUM,
		HairStyleRegistry.HAIR_SHORT, HairStyleRegistry.HAIR_SHAGGY,
		HairStyleRegistry.HAIR_MEDIUM, HairStyleRegistry.HAIR_BUZZ,
		HairStyleRegistry.HAIR_FLOW, HairStyleRegistry.HAIR_MULLET,
		HairStyleRegistry.HAIR_BALD, HairStyleRegistry.HAIR_MEDIUM,
		HairStyleRegistry.HAIR_BUZZ, HairStyleRegistry.HAIR_SHAGGY]
const _FB_FACIAL: Array[int] = [HairStyleRegistry.FACIAL_NONE, HairStyleRegistry.FACIAL_STUBBLE,
		HairStyleRegistry.FACIAL_BEARD, HairStyleRegistry.FACIAL_NONE,
		HairStyleRegistry.FACIAL_GOATEE, HairStyleRegistry.FACIAL_STUBBLE,
		HairStyleRegistry.FACIAL_HORSESHOE, HairStyleRegistry.FACIAL_MUSTACHE,
		HairStyleRegistry.FACIAL_NONE, HairStyleRegistry.FACIAL_LONG_BEARD]
# HairStyleRegistry.COLORS indices: dark brown, black, brown, light brown,
# blonde, red. Grey and white are left to curated veterans.
const _FB_HAIR_COLOR: Array[int] = [0, 1, 2, 0, 3, 1, 4, 0, 2, 5, 0, 1]
# Most of a bench wears the sweater loose; the odd skater tucks a front corner,
# the forehand-side tuck a few stars made famous, or the whole tail.
const _FB_TUCK: Array[int] = [GearModelRegistry.TUCK_NONE, GearModelRegistry.TUCK_NONE,
		GearModelRegistry.TUCK_NONE, GearModelRegistry.TUCK_RIGHT,
		GearModelRegistry.TUCK_NONE, GearModelRegistry.TUCK_NONE,
		GearModelRegistry.TUCK_LEFT, GearModelRegistry.TUCK_NONE,
		GearModelRegistry.TUCK_NONE, GearModelRegistry.TUCK_FULL]

static var _identities: Array[Dictionary] = []
static var _loaded: bool = false
# The file the roster came from; empty when neither loaded.
static var _loaded_path: String = ""


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in [USER_JSON_PATH, RES_JSON_PATH]:
		if _try_load_from(path):
			return


static func get_all() -> Array[Dictionary]:
	ensure_loaded()
	return _identities.duplicate()


# Picks an identity for a bot slot at lobby-toggle time. If the configured
# pool has an entry whose name is not in `used_names`, returns one at
# random so successive toggles in the same lobby don't duplicate — preferring
# identities whose `position` matches the slot's position (a defenseman
# archetype fills the LD card), falling back to any unused identity when the
# position pool is exhausted. When the whole pool is spent, returns the
# generic "Bot N" fallback derived from `slot_key` so the lobby card still
# has something concrete to display.
static func pick_for_slot(slot_key: int, used_names: Array[String]) -> Dictionary:
	ensure_loaded()
	var slot_position: String = PlayerRules.position_name(LobbySlotKey.slot(slot_key))
	var available: Array[Dictionary] = []
	var position_matches: Array[Dictionary] = []
	for entry: Dictionary in _identities:
		if used_names.has(entry.name):
			continue
		available.append(entry)
		if not slot_position.is_empty() and entry.get("position", "") == slot_position:
			position_matches.append(entry)
	if not position_matches.is_empty():
		return position_matches.pick_random()
	if not available.is_empty():
		return available.pick_random()
	return fallback_identity(slot_key)


static func fallback_identity(slot_key: int) -> Dictionary:
	return {
		"name":           "Bot %d" % (slot_key + 1),
		"number":         80 + slot_key,
		"is_left_handed": LobbySlotKey.slot(slot_key) % 2 == 1,
		"position":       PlayerRules.position_name(LobbySlotKey.slot(slot_key)),
		"height":         PlayerAttributes.HEIGHT_MEDIUM,
		"weight":         int(PlayerAttributes.NEUTRAL_WEIGHT_LBS),
		"profile":        PlayerAttributes.GEAR_BALANCED,
		"curve":          PlayerAttributes.GEAR_BALANCED,
		"flex":           PlayerAttributes.GEAR_BALANCED,
		"length":         PlayerAttributes.GEAR_BALANCED,
	}


static func _try_load_from(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(text)
	if not accepts(data):
		push_error("BotIdentityRegistry: malformed JSON in %s" % path)
		return false
	for entry: Dictionary in (data as Dictionary)["identities"]:
		if String(entry.get("name", "")).is_empty():
			continue
		_identities.append(normalize_entry(entry))
	_loaded_path = path
	return true


# Whether parsed JSON is a roster the loader takes — an empty one included.
# The Options menu asks this of a player's edited copy.
static func accepts(data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).get("identities") is Array


static func loaded_path() -> String:
	ensure_loaded()
	return _loaded_path


# Turns one raw JSON entry into a canonical identity dict: routes the
# attribute keys through PlayerAttributes.from_dict and takes the COERCED
# values back — out-of-range
# height/weight/gear lands on the nearest legal body rather than being
# rejected. Extracted from _try_load_from so the rule is unit-testable
# without touching the filesystem.
static func normalize_entry(entry: Dictionary) -> Dictionary:
	var attrs := PlayerAttributes.from_dict(entry)
	# Optional casting hint: which lineup slot this identity suits (see
	# PlayerRules.POSITION_NAMES). Unknown/missing → "" (fills any slot).
	var position: String = String(entry.get("position", "")).to_upper()
	if position not in PlayerRules.POSITION_NAMES:
		position = ""
	var out: Dictionary = attrs.to_dict()
	out["name"] = entry.get("name", "")
	out["number"] = int(entry.get("number", 0))
	out["is_left_handed"] = bool(entry.get("is_left_handed", false))
	out["position"] = position
	# Optional identity skin tone (SkinToneRegistry index); omitted → the
	# spawn path derives a stable one from the bot's name.
	if entry.has("skin"):
		out["skin"] = SkinToneRegistry.clamp_index(int(entry.get("skin", 0)))
	# Optional cosmetic pins, packed through the config constructors so an
	# out-of-range pick coerces to a legal look. A group's code is written only
	# when the card pins at least one of its fields — unpinned groups let
	# spawn_bot derive the name-hash fallback look instead.
	if _has_any(entry, _TAPE_KEYS):
		out["tape_code"] = StickTapeConfig.new(
				int(entry.get("tape_blade", TapeColorRegistry.TEAM_INDEX)),
				int(entry.get("tape_span", StickTapeConfig.Span.HEEL_TO_MID)),
				int(entry.get("tape_knob", TapeColorRegistry.TEAM_INDEX)),
				int(entry.get("knob_style", StickTapeConfig.KnobStyle.KNOB))).to_code()
	var pins_gear: bool = _has_any(entry, _GEAR_KEYS)
	var pins_hair: bool = _has_any(entry, _HAIR_KEYS)
	if pins_gear or pins_hair:
		# One code carries both groups, so the one this card leaves unpinned is
		# filled from the same name-hash fallback spawn_bot would have drawn.
		# Through the constructor, which coerces each field on its own — an
		# out-of-range pin must not bleed into its neighbours in the code.
		var gear: GearStyleConfig = GearStyleConfig.from_code(
				fallback_gear_style_code(String(entry.get("name", ""))))
		if pins_gear:
			gear = GearStyleConfig.new(
					int(entry.get("skate_model", 0)),
					int(entry.get("glove_model", 0)),
					int(entry.get("lace_color", GearStyleConfig.LACE_DEFAULT_INDEX)),
					int(entry.get("stick_model", 0)),
					int(entry.get("helmet_face", GearModelRegistry.FACE_NONE)),
					gear.hair_style, gear.facial_hair, gear.hair_color,
					int(entry.get("jersey_tuck", GearModelRegistry.TUCK_NONE)))
		if pins_hair:
			gear = GearStyleConfig.new(gear.skate_model, gear.glove_model, gear.lace_color,
					gear.stick_model, gear.helmet_face,
					int(entry.get("hair_style", HairStyleRegistry.HAIR_SHORT)),
					int(entry.get("facial_hair", HairStyleRegistry.FACIAL_NONE)),
					int(entry.get("hair_color", 0)), gear.jersey_tuck)
		out["gear_style_code"] = gear.to_code()
	return out


static func _has_any(entry: Dictionary, keys: Array[String]) -> bool:
	for key: String in keys:
		if entry.has(key):
			return true
	return false


# A stable tape job for a card without tape pins. Deterministic in the name,
# so the same bot tapes the same way every session; host-resolved and
# replicated, so cross-machine hash agreement is not required.
static func fallback_tape_code(bot_name: String) -> int:
	var h: int = bot_name.hash()
	return StickTapeConfig.new(
			_FB_BLADE_TAPE[(h >> 2) % _FB_BLADE_TAPE.size()],
			_FB_TAPE_SPAN[(h >> 5) % _FB_TAPE_SPAN.size()],
			_FB_KNOB_TAPE[(h >> 8) % _FB_KNOB_TAPE.size()],
			_FB_KNOB_STYLE[(h >> 11) % _FB_KNOB_STYLE.size()]).to_code()


# Gear/stick/hair counterpart of fallback_tape_code; hash slices are disjoint
# from the tape ones so the two looks vary independently. The face, the hair and
# the tuck draw from DERIVED hashes rather than yet-higher slices: String.hash is
# djb2-style, so names sharing a prefix ("Bot 1".."Bot 12") only vary the low
# ~25 bits and a bit-26 slice would deal every generic bot the same face.
static func fallback_gear_style_code(bot_name: String) -> int:
	var h: int = bot_name.hash()
	var hf: int = ("%s/face" % bot_name).hash()
	var hh: int = ("%s/hair" % bot_name).hash()
	var ht: int = ("%s/tuck" % bot_name).hash()
	return GearStyleConfig.new(
			_FB_SKATE[(h >> 14) % _FB_SKATE.size()],
			_FB_GLOVE[(h >> 17) % _FB_GLOVE.size()],
			_FB_LACES[(h >> 20) % _FB_LACES.size()],
			_FB_STICK[(h >> 23) % _FB_STICK.size()],
			_FB_FACE[(hf >> 2) % _FB_FACE.size()],
			_FB_HAIR[(hh >> 2) % _FB_HAIR.size()],
			_FB_FACIAL[(hh >> 6) % _FB_FACIAL.size()],
			_FB_HAIR_COLOR[(hh >> 10) % _FB_HAIR_COLOR.size()],
			_FB_TUCK[(ht >> 2) % _FB_TUCK.size()]).to_code()

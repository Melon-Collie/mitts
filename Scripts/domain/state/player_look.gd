class_name PlayerLook
extends RefCounted

# Everything a player looks like, apart from the team kit: the lettering, the
# hand they shoot, the build, and the cosmetic picks. The lobby carries one per
# seated player so its bench figures are the players; a bot's comes from its
# identity card, the same way its skater's does when it spawns.

var player_name: String = ""
var jersey_number: int = 0
var is_left_handed: bool = false
var attributes: PlayerAttributes = PlayerAttributes.neutral()
var skin_tone: int = SkinToneRegistry.DEFAULT_INDEX
var tape_code: int = StickTapeConfig.DEFAULT_CODE
var gear_style_code: int = GearStyleConfig.DEFAULT_CODE


# A bot's look from its identity card (BotIdentityRegistry.normalize_entry's
# keys). An empty card falls back to "Bot N" in 80+N, alternating hands by slot.
# Unpinned skin, tape and gear derive from the name, so a hand-rolled roster
# still shows variety and each bot keeps its look across sessions; the
# from_code round-trips coerce a forged card onto a legal look.
static func for_bot(identity: Dictionary, bot_id: int, team_slot: int) -> PlayerLook:
	var look := PlayerLook.new()
	look.is_left_handed = identity.get("is_left_handed", team_slot % 2 == 1)
	look.player_name = identity.get("name", "Bot %d" % (bot_id + 1))
	look.jersey_number = identity.get("number", 80 + bot_id)
	look.attributes = PlayerAttributes.neutral() if identity.is_empty() \
			else PlayerAttributes.from_dict(identity)
	look.skin_tone = SkinToneRegistry.clamp_index(int(identity.get("skin",
			look.player_name.hash() % SkinToneRegistry.TONES.size())))
	look.tape_code = StickTapeConfig.from_code(int(identity.get("tape_code",
			BotIdentityRegistry.fallback_tape_code(look.player_name)))).to_code()
	look.gear_style_code = GearStyleConfig.from_code(int(identity.get("gear_style_code",
			BotIdentityRegistry.fallback_gear_style_code(look.player_name)))).to_code()
	return look


# The build and cosmetics, as a lobby roster entry carries them after the
# name, hand and number it already had.
func cosmetics_to_wire() -> Array:
	return [attributes.to_dict(), skin_tone, tape_code, gear_style_code]


# Reads cosmetics_to_wire's fields starting at `at`; anything missing or
# malformed stays at the default look.
func cosmetics_from_wire(entry: Array, at: int) -> void:
	if entry.size() <= at + 3:
		return
	if entry[at] is Dictionary:
		attributes = PlayerAttributes.from_dict(entry[at])
	skin_tone = SkinToneRegistry.clamp_index(int(entry[at + 1]))
	tape_code = StickTapeConfig.from_code(int(entry[at + 2])).to_code()
	gear_style_code = GearStyleConfig.from_code(int(entry[at + 3])).to_code()

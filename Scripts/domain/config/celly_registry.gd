class_name CellyRegistry
extends RefCounted

# The goal celebrations a player picks on the player screen and skates when
# they score (CellyPoseRules poses them). The pick rides GearStyleConfig's
# packed code, so it reaches every machine with the rest of the look. Zero is
# the raised stick, which a code saved before the field existed decodes to.

const RAISED_STICK: int = 0
const SWORD_SHEATH: int = 1
const KNEE_SLIDE: int = 2
const HOT_STICK: int = 3
const BOW_AND_ARROW: int = 4
const CANT_HEAR_YOU: int = 5

const NAME_KEYS: Array[StringName] = [
	&"CELLY_RAISED_STICK",
	&"CELLY_SWORD_SHEATH",
	&"CELLY_KNEE_SLIDE",
	&"CELLY_HOT_STICK",
	&"CELLY_BOW_AND_ARROW",
	&"CELLY_CANT_HEAR_YOU",
]


static func count() -> int:
	return NAME_KEYS.size()


static func is_valid(celly: int) -> bool:
	return celly >= 0 and celly < NAME_KEYS.size()

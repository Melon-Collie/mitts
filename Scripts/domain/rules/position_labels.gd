class_name PositionLabels

# Translation keys for a skater's position badge and the lobby grid's column
# headers. Engine-free like the rest of the domain: this hands back a stable
# key and the display seam localizes it (see Scripts/ui/CLAUDE.md).
#
# A slot is the same position on both teams (PlayerRules.POSITION_NAMES), so
# neither table takes a team. 3v3 is position-free: slots 1/2 are rovers and
# keep the classic single letters. 5v5 has a real forward/defense split, and
# there the wingers spell out LW/RW so they read consistently beside LD/RD.

const _BADGE: Array[StringName] = [
	&"POS_BADGE_C", &"POS_BADGE_L", &"POS_BADGE_R", &"POS_BADGE_LD", &"POS_BADGE_RD",
]
const _BADGE_5V5: Array[StringName] = [
	&"POS_BADGE_C", &"POS_BADGE_LW", &"POS_BADGE_RW", &"POS_BADGE_LD", &"POS_BADGE_RD",
]

# Forward slots only: the headers ride above the 3v3 forward row.
const _HEADER: Array[StringName] = [
	&"POSITION_C", &"POSITION_LW", &"POSITION_RW",
]

# Badge for one roster slot. `slot` is a team_slot; out-of-range slots fall
# back to the centre badge rather than crashing a HUD rebuild.
static func badge_key(slot: int, is_5v5: bool) -> StringName:
	var table: Array[StringName] = _BADGE_5V5 if is_5v5 else _BADGE
	if slot < 0 or slot >= table.size():
		return _BADGE[0]
	return table[slot]

# Header over the lobby column a forward slot sits in.
static func column_header_key(slot: int) -> StringName:
	if slot < 0 or slot >= _HEADER.size():
		return _HEADER[0]
	return _HEADER[slot]

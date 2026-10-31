extends GutTest

# PositionLabels is the single home for the badge and column-header keys the
# box score, the matchup card and the lobby slot grid all draw.

const _CATALOGUE: String = "res://locale/translations.csv"
const _FORWARD_SLOTS: int = 3


func test_a_slot_wears_its_own_position_on_both_teams() -> void:
	# Slot 1 is each team's own left wing (PlayerRules.home_side_x, faceoff
	# alignment); the badge must say so on the away bench too.
	assert_eq(PositionLabels.badge_key(1, false), &"POS_BADGE_L")
	assert_eq(PositionLabels.badge_key(2, false), &"POS_BADGE_R")
	assert_eq(PositionLabels.badge_key(1, true), &"POS_BADGE_LW")
	assert_eq(PositionLabels.badge_key(2, true), &"POS_BADGE_RW")
	assert_eq(PositionLabels.badge_key(3, true), &"POS_BADGE_LD")
	assert_eq(PositionLabels.badge_key(4, true), &"POS_BADGE_RD")
	assert_eq(PositionLabels.column_header_key(1), &"POSITION_LW")
	assert_eq(PositionLabels.column_header_key(2), &"POSITION_RW")


func test_only_the_wingers_change_between_modes() -> void:
	# 3v3 is position-free rovers, so slots 1/2 keep the plain letters; 5v5 has
	# a real forward/defense split and spells the wingers out beside LD/RD.
	for slot: int in [0, 3, 4]:
		assert_eq(PositionLabels.badge_key(slot, false), PositionLabels.badge_key(slot, true),
			"slot %d reads the same in both modes" % slot)
	for slot: int in [1, 2]:
		assert_ne(PositionLabels.badge_key(slot, false), PositionLabels.badge_key(slot, true),
			"slot %d spells the wing out in 5v5" % slot)


func test_out_of_range_indices_fall_back_rather_than_crash() -> void:
	# A HUD rebuild must not die on a slot the roster does not have.
	assert_eq(PositionLabels.badge_key(-1, false), PositionLabels.badge_key(0, false),
		"a negative slot falls back to the centre badge")
	assert_eq(PositionLabels.badge_key(99, true), PositionLabels.badge_key(0, false),
		"a slot past the roster falls back to the centre badge")
	assert_eq(PositionLabels.column_header_key(7), PositionLabels.column_header_key(0),
		"a slot past the forward row falls back to the centre header")


func test_every_key_has_a_catalogue_row() -> void:
	var known: Dictionary[String, bool] = {}
	var rows: PackedStringArray = FileAccess.get_file_as_string(_CATALOGUE).split("\n")
	for i: int in range(1, rows.size()):
		var row: String = rows[i].strip_edges()
		if not row.is_empty():
			known[row.get_slice(",", 0)] = true

	var missing: Array[String] = []
	for is_5v5: bool in [false, true]:
		for slot: int in PlayerRules.MAX_PER_TEAM:
			var badge: String = String(PositionLabels.badge_key(slot, is_5v5))
			if not known.has(badge):
				missing.append(badge)
	for slot: int in _FORWARD_SLOTS:
		var header: String = String(PositionLabels.column_header_key(slot))
		if not known.has(header):
			missing.append(header)
	assert_true(missing.is_empty(),
		"keys with no locale/translations.csv row (they would render raw): "
		+ ", ".join(missing))

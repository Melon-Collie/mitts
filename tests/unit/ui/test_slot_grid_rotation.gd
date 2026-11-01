extends GutTest

# The lobby grid draws the two teams as a faceoff lineup seen from the home
# end: away's rows are home's rotated a half turn, never mirrored, so a card
# sits on the side of the ice its slot plays (PlayerRules.home_side_x).


func test_home_reads_left_to_right() -> void:
	assert_eq(SlotGridPanel.row_order(0, [0, 1, 2] as Array[int]), [1, 0, 2] as Array[int],
		"home forwards: LW / C / RW")
	assert_eq(SlotGridPanel.row_order(0, [3, 4] as Array[int]), [3, 4] as Array[int],
		"home defense: LD / RD")


func test_away_is_home_rotated_a_half_turn() -> void:
	assert_eq(SlotGridPanel.row_order(1, [0, 1, 2] as Array[int]), [2, 0, 1] as Array[int],
		"away forwards: RW / C / LW")
	assert_eq(SlotGridPanel.row_order(1, [3, 4] as Array[int]), [4, 3] as Array[int],
		"away defense: RD / LD")

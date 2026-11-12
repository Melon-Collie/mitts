extends GutTest

# FaceoffFormation — who stands where at a faceoff when a team is short.

const C: int = 0
const LW: int = 1
const RW: int = 2
const LD: int = 3
const RD: int = 4

const SEAT_COUNT: int = PlayerRules.MAX_PER_TEAM


func _mask(seats: Array[int]) -> int:
	var mask: int = 0
	for seat: int in seats:
		mask |= FaceoffFormation.seat_bit(seat)
	return mask


func _seats_of(mask: int) -> Array[int]:
	var seats: Array[int] = []
	for seat: int in SEAT_COUNT:
		if (mask & FaceoffFormation.seat_bit(seat)) != 0:
			seats.append(seat)
	return seats


# ── Full strength ────────────────────────────────────────────────────────────

func test_five_men_stand_in_their_own_spots() -> void:
	assert_eq(Array(FaceoffFormation.cast(_mask([C, LW, RW, LD, RD]))), [C, LW, RW, LD, RD])


func test_three_forwards_stand_in_their_own_spots() -> void:
	var none: int = FaceoffFormation.NO_SPOT
	assert_eq(Array(FaceoffFormation.cast(_mask([C, LW, RW]))), [C, LW, RW, none, none])


# ── Every way a team can be short ────────────────────────────────────────────

func test_every_man_on_the_ice_gets_a_spot_of_his_own() -> void:
	for mask: int in range(1, 1 << SEAT_COUNT):
		var spots: PackedInt32Array = FaceoffFormation.cast(mask)
		var taken: Dictionary = {}
		for seat: int in SEAT_COUNT:
			var on_ice: bool = (mask & FaceoffFormation.seat_bit(seat)) != 0
			if not on_ice:
				assert_eq(spots[seat], FaceoffFormation.NO_SPOT,
						"seat %d is off the ice in %s" % [seat, _seats_of(mask)])
				continue
			assert_ne(spots[seat], FaceoffFormation.NO_SPOT,
					"seat %d has no spot in %s" % [seat, _seats_of(mask)])
			assert_false(taken.has(spots[seat]),
					"two men share spot %d in %s" % [spots[seat], _seats_of(mask)])
			taken[spots[seat]] = true


func test_the_dot_is_always_taken_by_the_lowest_seat() -> void:
	for mask: int in range(1, 1 << SEAT_COUNT):
		var lowest: int = _seats_of(mask)[0]
		assert_eq(FaceoffFormation.draw_taker(mask), lowest)
		assert_eq(FaceoffFormation.cast(mask)[lowest], FaceoffFormation.CENTER_SPOT,
				"in %s" % [_seats_of(mask)])


func test_the_wings_are_filled_before_any_defense_spot() -> void:
	for mask: int in range(1, 1 << SEAT_COUNT):
		var men: int = _seats_of(mask).size()
		var spots: PackedInt32Array = FaceoffFormation.cast(mask)
		var wings: int = int(spots.has(LW)) + int(spots.has(RW))
		assert_eq(wings, mini(men - 1, 2),
				"%d men in %s fill %d wing spots" % [men, _seats_of(mask), wings])


func test_a_winger_not_taking_the_draw_keeps_his_wing() -> void:
	for mask: int in range(1, 1 << SEAT_COUNT):
		var spots: PackedInt32Array = FaceoffFormation.cast(mask)
		for wing: int in [LW, RW]:
			if spots[wing] != FaceoffFormation.NO_SPOT \
					and spots[wing] != FaceoffFormation.CENTER_SPOT:
				assert_eq(spots[wing], wing, "in %s" % [_seats_of(mask)])


func test_no_men_cast_nobody() -> void:
	assert_eq(FaceoffFormation.draw_taker(0), FaceoffFormation.NO_SPOT)
	assert_false(Array(FaceoffFormation.cast(0)).any(
			func(spot: int) -> bool: return spot != FaceoffFormation.NO_SPOT))


# ── The casts that matter ────────────────────────────────────────────────────

func test_with_the_centre_off_a_winger_draws_and_his_defenseman_steps_up() -> void:
	var spots: PackedInt32Array = FaceoffFormation.cast(_mask([LW, RW, LD, RD]))
	assert_eq(spots[LW], FaceoffFormation.CENTER_SPOT, "the left wing takes the draw")
	assert_eq(spots[LD], LW, "the left defenseman fills the wing he left")
	assert_eq(spots[RW], RW)
	assert_eq(spots[RD], RD)


func test_with_a_winger_off_his_own_sides_defenseman_steps_up() -> void:
	var spots: PackedInt32Array = FaceoffFormation.cast(_mask([C, LW, LD, RD]))
	assert_eq(spots[RD], RW)
	assert_eq(spots[LD], LD, "the other defenseman stays back")


func test_with_a_defenseman_off_nobody_moves() -> void:
	assert_eq(Array(FaceoffFormation.cast(_mask([C, LW, RW, RD]))),
			[C, LW, RW, FaceoffFormation.NO_SPOT, RD])


func test_three_men_are_the_draw_and_two_wings() -> void:
	var spots: PackedInt32Array = FaceoffFormation.cast(_mask([C, LD, RD]))
	assert_eq(spots[LD], LW)
	assert_eq(spots[RD], RW)


func test_a_defenseman_crosses_the_ice_only_when_that_sides_own_is_gone() -> void:
	var crossed: PackedInt32Array = FaceoffFormation.cast(_mask([C, RW, RD]))
	assert_eq(crossed[RD], LW, "nobody else can fill the left wing")
	var stayed: PackedInt32Array = FaceoffFormation.cast(_mask([C, RD]))
	assert_eq(stayed[RD], RW, "with both wings open he takes his own side's")

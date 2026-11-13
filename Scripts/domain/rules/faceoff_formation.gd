class_name FaceoffFormation

# Casts the men a team has on the ice into a faceoff's spots. A spot is named
# by the seat whose place it is (PlayerRules.POSITION_NAMES), so a man cast
# into spot `s` lines up at PlayerRules.faceoff_position(team, s, ...).
#
# The dot is filled first and the two wing spots next: a team with a wing
# spot empty loses the draw's scramble to the one that has both, so a
# defenseman steps up into it. Being cast up changes where he stands at the
# drop and nothing else about him.

const NO_SPOT: int = -1
const CENTER_SPOT: int = 0
const _WING_SPOTS: Array[int] = [1, 2]
# A wing's own-side defenseman sits two seats above it (LW 1 / LD 3, RW 2 / RD 4).
const _WING_TO_OWN_DEFENSE: int = 2
const _DEFENSE_SEAT_SUM: int = 7  # LD 3 + RD 4


static func seat_bit(seat: int) -> int:
	return 1 << seat


# The seat that takes the draw: the lowest one on the ice, so the centre, then
# a winger, and a defenseman only with no forward left. NO_SPOT for no men.
static func draw_taker(on_ice: int) -> int:
	for seat: int in PlayerRules.MAX_PER_TEAM:
		if (on_ice & seat_bit(seat)) != 0:
			return seat
	return NO_SPOT


# The spot each seat takes, indexed by seat; NO_SPOT for a seat not on the
# ice. `on_ice` is a bitmask of seats (seat_bit).
static func cast(on_ice: int) -> PackedInt32Array:
	var spots := PackedInt32Array()
	spots.resize(PlayerRules.MAX_PER_TEAM)
	spots.fill(NO_SPOT)
	var drawer: int = draw_taker(on_ice)
	if drawer == NO_SPOT:
		return spots
	spots[drawer] = CENTER_SPOT
	var open_wings: Array[int] = []
	for wing: int in _WING_SPOTS:
		if _is_free(on_ice, spots, wing):
			spots[wing] = wing
		else:
			open_wings.append(wing)
	# His own side's defenseman first, for every open wing, before either
	# crosses the ice: with one of each missing, nobody changes sides.
	for crossing: bool in [false, true]:
		for wing: int in open_wings:
			if spots.has(wing):
				continue
			var own: int = wing + _WING_TO_OWN_DEFENSE
			var defender: int = _DEFENSE_SEAT_SUM - own if crossing else own
			if _is_free(on_ice, spots, defender):
				spots[defender] = wing
	for seat: int in range(PlayerRules.FIRST_DEFENSE_SLOT, PlayerRules.MAX_PER_TEAM):
		if _is_free(on_ice, spots, seat):
			spots[seat] = seat
	return spots


static func _is_free(on_ice: int, spots: PackedInt32Array, seat: int) -> bool:
	return (on_ice & seat_bit(seat)) != 0 and spots[seat] == NO_SPOT

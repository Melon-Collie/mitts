extends GutTest

# The puck-following cues' timeline: who gets the bold ring, when a change of
# possession pulses (and when it does not), and the loose-puck halo.

const DT: float = 1.0 / 60.0
const A: int = 101
const B: int = 202
const C: int = 303
const HOME: int = 0
const AWAY: int = 1
const ALLY: Color = Color(0.2, 0.4, 1.0, 1.0)
const ENEMY: Color = Color(1.0, 0.2, 0.2, 1.0)

var _cues: PuckFollowCues


func before_each() -> void:
	_cues = PuckFollowCues.new()


func _carry(id: int, team: int, color: Color = ALLY, at: Vector2 = Vector2.ZERO,
		seconds: float = DT) -> void:
	var t: float = 0.0
	while t < seconds - 1e-6:
		_cues.step(DT, id, team, at, color, false)
		t += DT


func _loose(seconds: float, on_ice: bool = true) -> void:
	var t: float = 0.0
	while t < seconds - 1e-6:
		_cues.step(DT, PuckFollowCues.NO_CARRIER, PuckFollowCues.NO_TEAM,
				Vector2.ZERO, Color(), on_ice)
		t += DT


func _pulse_end_r_after_full_growth() -> float:
	var max_r: float = 0.0
	while _cues.pulse_active:
		max_r = maxf(max_r, _cues.pulse_outer_r)
		_cues.step(DT, _cues.carrier_id, PuckFollowCues.NO_TEAM, Vector2.ZERO, ALLY, false)
	return max_r


func test_first_pickup_pulses_in_the_carriers_color() -> void:
	_carry(A, HOME, ALLY)
	assert_true(_cues.pulse_active)
	assert_eq(Color(_cues.pulse_color.r, _cues.pulse_color.g, _cues.pulse_color.b), Color(ALLY.r, ALLY.g, ALLY.b))
	assert_eq(_cues.carrier_id, A)


func test_carrier_ring_thickens_over_its_ease_and_drops_when_loose() -> void:
	_carry(A, HOME)
	assert_lt(_cues.carrier_weight, 1.0, "eases in rather than snapping")
	_carry(A, HOME, ALLY, Vector2.ZERO, PuckFollowCues.CARRIER_EASE_IN_S)
	assert_almost_eq(_cues.carrier_weight, 1.0, 1e-6)
	_loose(DT)
	assert_eq(_cues.carrier_id, PuckFollowCues.NO_CARRIER)
	assert_eq(_cues.carrier_weight, 0.0)


func test_carrier_ring_is_thicker_than_the_slot_ring() -> void:
	assert_lt(PuckFollowCues.CARRIER_RING_INNER_R, SkaterHUDCoordinator.RING_INNER_R)
	assert_gt(PuckFollowCues.CARRIER_RING_INNER_R, 0.0)


func test_a_fumble_and_regain_by_the_same_skater_does_not_pulse() -> void:
	_carry(A, HOME, ALLY, Vector2.ZERO, 1.0)
	assert_false(_cues.pulse_active, "the pickup pulse has run out")
	_loose(PuckFollowCues.LAST_CARRIER_MEMORY_S * 0.5)
	_carry(A, HOME)
	assert_false(_cues.pulse_active)


func test_the_same_skater_winning_it_back_after_a_while_pulses() -> void:
	_carry(A, HOME, ALLY, Vector2.ZERO, 1.0)
	_loose(PuckFollowCues.LAST_CARRIER_MEMORY_S + DT)
	_carry(A, HOME)
	assert_true(_cues.pulse_active)


func test_a_pass_to_a_teammate_pulses() -> void:
	_carry(A, HOME, ALLY, Vector2.ZERO, 1.0)
	_loose(0.3)
	_carry(B, HOME)
	assert_true(_cues.pulse_active)
	assert_eq(_cues.carrier_id, B)


func test_a_turnover_pulse_reaches_further_than_a_pass() -> void:
	_carry(A, HOME, ALLY, Vector2.ZERO, 1.0)
	_carry(B, HOME)
	var pass_r: float = _pulse_end_r_after_full_growth()
	_carry(C, AWAY, ENEMY)
	var turnover_r: float = _pulse_end_r_after_full_growth()
	assert_gt(turnover_r, pass_r)


func test_a_turnover_is_read_across_a_long_loose_spell() -> void:
	# A dump-in recovered by the other side seconds later still changed hands.
	_carry(A, HOME, ALLY, Vector2.ZERO, 1.0)
	_loose(3.0)
	_carry(C, AWAY, ENEMY)
	assert_gt(_pulse_end_r_after_full_growth(), PuckFollowCues.PASS_PULSE_END_R + 0.01)


func test_the_pulse_grows_fades_and_ends() -> void:
	_carry(A, HOME)
	var last_r: float = _cues.pulse_outer_r
	var last_a: float = _cues.pulse_color.a
	var frames: int = 0
	while _cues.pulse_active:
		_carry(A, HOME)
		if _cues.pulse_active:
			assert_gt(_cues.pulse_outer_r, last_r)
			assert_lt(_cues.pulse_color.a, last_a)
			assert_lt(_cues.pulse_inner_r, _cues.pulse_outer_r)
			last_r = _cues.pulse_outer_r
			last_a = _cues.pulse_color.a
		frames += 1
	assert_almost_eq(frames * DT, PuckFollowCues.PASS_PULSE_S, DT * 2.0)
	assert_eq(_cues.pulse_color.a, 0.0)


func test_the_pulse_rides_its_carrier_and_stays_put_once_he_loses_it() -> void:
	_carry(A, HOME, ALLY, Vector2(1.0, 2.0))
	_carry(A, HOME, ALLY, Vector2(1.5, 2.5))
	assert_eq(_cues.pulse_center, Vector2(1.5, 2.5))
	_loose(DT)
	_carry(A, HOME, ALLY, Vector2(9.0, 9.0))  # regained inside the memory: no new pulse
	assert_eq(_cues.pulse_center, Vector2(9.0, 9.0), "still his pulse")
	_carry(B, HOME, ALLY, Vector2(-3.0, 0.0))
	assert_eq(_cues.pulse_center, Vector2(-3.0, 0.0), "the new carrier's pulse")


func test_loose_halo_fades_in_and_vanishes_on_pickup() -> void:
	_loose(DT)
	assert_gt(_cues.loose_weight, 0.0)
	assert_lt(_cues.loose_weight, 1.0)
	_loose(PuckFollowCues.LOOSE_FADE_IN_S)
	assert_eq(_cues.loose_weight, 1.0)
	_carry(A, HOME)
	assert_eq(_cues.loose_weight, 0.0)


func test_no_halo_for_a_puck_off_the_ice() -> void:
	_loose(1.0, false)
	assert_eq(_cues.loose_weight, 0.0)


func test_reset_forgets_the_possession_history() -> void:
	_carry(A, HOME, ALLY, Vector2.ZERO, 1.0)
	_cues.reset()
	assert_eq(_cues.carrier_id, PuckFollowCues.NO_CARRIER)
	_carry(A, HOME)
	assert_true(_cues.pulse_active, "the same carrier after a reset is a fresh pickup")

extends GutTest

# AIStandUpRead — a defender meets a carrier about to skate into him with Ctrl
# held, when the contact is a beat away and, committed, it rocks him.

const CFG_REF: float = 1.35
const TRANSFER: float = 0.65


# The carrier skating +x at `speed` into a set defender `gap` metres of ice away
# (body edge to body edge).
func _meets(speed: float, gap: float, me_vel: Vector3 = Vector3.ZERO) -> bool:
	var man_pos := Vector3.ZERO
	var me_pos := Vector3(gap + AIPinThreatRead.TOUCHING_M, 0.0, 0.0)
	return AIStandUpRead.meets(me_pos, me_vel, 1.0, man_pos, Vector3(speed, 0.0, 0.0), 1.0,
			TRANSFER, CFG_REF)


func test_he_meets_a_carrier_a_beat_from_contact() -> void:
	assert_true(_meets(8.0, 8.0 * AIStandUpRead.MEET_S * 0.5))


func test_not_while_the_carrier_can_still_turn_away() -> void:
	assert_false(_meets(8.0, 8.0 * AIStandUpRead.MEET_S * 2.0))


func test_not_for_a_contact_that_would_not_rock_him() -> void:
	var too_slow: float = 0.9 * CFG_REF / SkaterCollisionRules.victim_kick(1.0, 1.0, 1.0, TRANSFER)
	assert_false(_meets(too_slow, 0.01))


func test_not_for_a_carrier_skating_away() -> void:
	assert_false(_meets(-8.0, 0.1))


func test_a_defender_backing_off_slower_than_him_still_meets_him() -> void:
	assert_true(_meets(9.0, 0.2, Vector3(4.0, 0.0, 0.0)), "closing at 5 m/s")

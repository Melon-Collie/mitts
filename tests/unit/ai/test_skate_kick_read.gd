extends GutTest

# AISkateKickRead — a bot holds the brake for the kick when the puck's line in
# its frame meets a skate within the beat before it arrives, misses the blade
# on the way, and the kick would be granted.

const FACING := Vector2(0.0, -1.0)  # facing −Z; right is +X
const REACH: float = 0.5
const HOME: int = 0
const AWAY: int = 1

var _contact := SkateContactRules.Contact.new()


func _boot_x() -> float:
	return SkateContactRules.half_spacing(false)


func _read(puck_pos: Vector3, puck_vel: Vector3, blade: Vector3 = Vector3(0.5, 0.0, -1.0),
		puck_team: int = HOME, stick_free: bool = true, pressured: bool = false) -> bool:
	return AISkateKickRead.should_kick(Vector3.ZERO, Vector3.ZERO, FACING, false, blade, REACH,
			puck_pos, puck_vel, puck_team, HOME, stick_free, pressured, _contact)


func test_a_feed_into_his_skate_from_behind_is_kicked() -> void:
	assert_true(_read(Vector3(_boot_x(), 0.0127, 1.0), Vector3(0.0, 0.0, -6.0)))


func test_a_feed_his_blade_meets_first_is_left_to_the_blade() -> void:
	assert_false(_read(Vector3(_boot_x(), 0.0127, 1.0), Vector3(0.0, 0.0, -6.0),
			Vector3(_boot_x(), 0.0, 0.6)))


func test_a_puck_still_beyond_the_beat_waits() -> void:
	var out_of_beat: float = 6.0 * AISkateKickRead.SET_S + 0.5
	assert_false(_read(Vector3(_boot_x(), 0.0127, out_of_beat), Vector3(0.0, 0.0, -6.0)))


func test_a_puck_through_the_gap_needs_no_kick() -> void:
	assert_false(_read(Vector3(0.0, 0.0127, 1.0), Vector3(0.0, 0.0, -6.0)))


func test_an_opponents_puck_is_not_his_to_kick() -> void:
	assert_false(_read(Vector3(_boot_x(), 0.0127, 1.0), Vector3(0.0, 0.0, -6.0),
			Vector3(0.5, 0.0, -1.0), AWAY))


func test_an_opponent_on_him_takes_the_kick_away() -> void:
	assert_false(_read(Vector3(_boot_x(), 0.0127, 1.0), Vector3(0.0, 0.0, -6.0),
			Vector3(0.5, 0.0, -1.0), HOME, true, true))


func test_a_busy_stick_does_not_brake_for_it() -> void:
	assert_false(_read(Vector3(_boot_x(), 0.0127, 1.0), Vector3(0.0, 0.0, -6.0),
			Vector3(0.5, 0.0, -1.0), HOME, false))


func test_a_feed_too_hard_for_a_boot_is_not_kicked() -> void:
	var v: float = SkateContactRules.KICK_MAX_SPEED_M_S + 1.0
	assert_false(_read(Vector3(_boot_x(), 0.0127, 0.5 + v * 0.05), Vector3(0.0, 0.0, -v)))


func test_a_puck_moving_away_from_his_skates_is_not_kicked() -> void:
	assert_false(_read(Vector3(_boot_x(), 0.0127, 0.15), Vector3(0.0, 0.0, 6.0)))

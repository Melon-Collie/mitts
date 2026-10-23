extends GutTest

# What he reads of the play (KeeperPlayRead): a puck holding its line read
# where it is; a change of direction read going the old way until his read has
# passed, a slower tier's later; and the receivers a pass could reach, through
# a lane no defender's stick reaches, in front of the goal line and inside the
# blue line.

const DT: float = 1.0 / 120.0


func test_a_puck_holding_its_line_is_read_where_it_is() -> void:
	var play := KeeperPlayRead.new()
	var v := Vector2(3.0, 5.0)
	var at := Vector2(-4.0, -12.0)
	for i: int in 60:
		at += v * DT
		play.step(DT, at, v)
	assert_almost_eq(play.puck, at, Vector2.ONE * 1e-4, "where it is")
	assert_almost_eq(play.motion, v, Vector2.ONE * 1e-6, "its motion")


func _flip_seen_after(delay_s: float) -> float:
	var play := KeeperPlayRead.new()
	play.delay_s = delay_s
	var at := Vector2(0.0, -6.0)
	var v := Vector2(4.0, 0.0)
	for i: int in 60:
		at += v * DT
		play.step(DT, at, v)
	v = -v
	var t: float = 0.0
	var ahead: bool = true
	while play.motion.x > 0.0 and t < 1.0:
		at += v * DT
		play.step(DT, at, v)
		t += DT
		if play.motion.x > 0.0:
			ahead = ahead and play.puck.x > at.x
	assert_true(ahead, "read going the old way until then")
	return t


func test_a_change_of_direction_is_read_after_his_read() -> void:
	var hard: float = GoalieSkillProfile.hard().reaction_delay_s
	var easy: float = GoalieSkillProfile.easy().reaction_delay_s
	var hard_t: float = _flip_seen_after(hard)
	# Seen from the first tick it moves the new way, his read later.
	assert_almost_eq(hard_t, DT + hard, DT, "his read's time")
	assert_gt(_flip_seen_after(easy), hard_t, "a slower tier later")


func test_receivers_are_the_ones_a_pass_can_reach() -> void:
	var play := KeeperPlayRead.new()
	for i: int in 30:
		play.step(DT, Vector2(3.0, -6.0), Vector2.ZERO)
	var attackers := PackedVector2Array([Vector2(-3.0, -5.0), Vector2(0.0, -3.0), Vector2(-2.0, 1.0),
			Vector2(1.0, -25.0)])
	play.read_receivers(attackers, PackedVector2Array())
	assert_eq(play.receivers, PackedVector2Array([Vector2(-3.0, -5.0), Vector2(0.0, -3.0)]),
			"in front of the goal line, inside the blue line")
	# A metre off the lane to (-3, -5), three off the one to (0, -3).
	play.read_receivers(attackers, PackedVector2Array([Vector2(-1.0, -6.4)]))
	assert_eq(play.receivers, PackedVector2Array([Vector2(0.0, -3.0)]), "a stick on the lane takes it")
	play.read_receivers(attackers, PackedVector2Array([Vector2(8.0, -15.0)]))
	assert_eq(play.receivers.size(), 2, "one nowhere near takes none")

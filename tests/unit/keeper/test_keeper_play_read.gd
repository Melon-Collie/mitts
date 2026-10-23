extends GutTest

# What he reads of the play (KeeperPlayRead): a puck holding its line read
# where it is; a change of direction read going the old way until his read has
# passed, a slower tier's later; a wind-up seen late by his read and priming
# the save once he has watched it long enough; and the receivers a pass could
# reach, through a lane no defender's stick reaches, in front of the goal line
# and inside the blue line. A stickhandle read where the puck is on average
# about its carrier, the carrier's skating as it is; and a loose puck read to
# the first opposing stick its line reaches before it stops.

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


# A wind-up is seen his read late, and primes the save once watched for
# KeeperPlayRead.PRIME_S; a look broken off starts over.
func test_a_wind_up_watched_long_enough_primes_the_save() -> void:
	var play := KeeperPlayRead.new()
	var at := Vector2(0.0, -6.0)
	for i: int in 60:
		play.step(DT, at, Vector2.ZERO, false)
	var seen_at: float = -1.0
	var primed_at: float = -1.0
	var t: float = 0.0
	while t < 1.0 and primed_at < 0.0:
		play.step(DT, at, Vector2.ZERO, true)
		t += DT
		if play.winding_up and seen_at < 0.0:
			seen_at = t
		if play.primed():
			primed_at = t
	assert_almost_eq(seen_at, DT + play.delay_s, DT, "seen his read late")
	assert_almost_eq(primed_at - seen_at, KeeperPlayRead.PRIME_S, DT, "primed once watched long enough")
	for i: int in 40:
		play.step(DT, at, Vector2.ZERO, false)
	play.step(DT, at, Vector2.ZERO, true)
	assert_false(play.primed(), "a broken look starts over")


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


func test_a_stickhandle_is_read_where_the_puck_is_on_average() -> void:
	var play := KeeperPlayRead.new()
	var body := Vector2(0.0, -6.0)
	var lo: float = INF
	var hi: float = -INF
	for i: int in 360:
		var puck := body + Vector2(0.4 * sin(TAU * 1.5 * i * DT), -0.5)
		play.step(DT, puck, Vector2.ZERO, false, body)
		if i > 180:
			lo = minf(lo, play.puck.x)
			hi = maxf(hi, play.puck.x)
	assert_lt(hi - lo, 0.8 * 0.5, "a stickhandle swings it less than half as far")
	for i: int in 240:
		play.step(DT, body + Vector2(0.5, -0.5), Vector2.ZERO, false, body)
	assert_almost_eq(play.puck, body + Vector2(0.5, -0.5), Vector2.ONE * 0.01, "held to the side, read there")
	var v := Vector2(5.0, 0.0)
	for i: int in 120:
		body += v * DT
		play.step(DT, body + Vector2(0.5, -0.5), v, false, body)
	assert_almost_eq(play.puck, body + Vector2(0.5, -0.5), Vector2.ONE * 1e-3, "the carrier's skating as it is")


func _loose(play: KeeperPlayRead, from: Vector2, v: Vector2, seconds: float) -> Vector2:
	var at: Vector2 = from
	for i: int in roundi(seconds / DT):
		at += v * DT
		play.step(DT, at, v)
	return at


func test_a_pass_is_read_to_the_stick_that_meets_it() -> void:
	var play := KeeperPlayRead.new()
	var receiver := Vector2(-3.0, -6.0)
	var reach: float = KeeperPlayRead.LANE_REACH_M
	var v := Vector2(-15.0, 0.0)
	for i: int in 60:
		play.step(DT, Vector2(3.0, -6.0), Vector2.ZERO)
	var at: Vector2 = _loose(play, Vector2(3.0, -6.0), v, play.delay_s * 0.5)
	play.read_pass(PackedVector2Array([receiver]))
	assert_false(play.meets, "not before his read sees it go")
	at = _loose(play, at, v, play.delay_s)
	play.read_pass(PackedVector2Array([receiver]))
	assert_true(play.meets, "once seen")
	assert_almost_eq(play.meet, receiver + Vector2(reach, 0.0), Vector2.ONE * 1e-3, "where his stick reaches it")
	var t: float = (at.x - play.meet.x) / 15.0
	assert_almost_eq(play.meet_s, t, 0.02, "in the time it takes to get there")
	play.read_pass(PackedVector2Array([Vector2(-3.0, -9.0)]))
	assert_false(play.meets, "a line no stick reaches: none")
	play.read_pass(PackedVector2Array([play.puck + Vector2(0.3, 0.0), receiver]))
	assert_true(play.meets, "the stick it is going away from is no receiver")
	assert_almost_eq(play.meet, receiver + Vector2(reach, 0.0), Vector2.ONE * 1e-3)
	for i: int in roundi(play.delay_s / DT) - 1:
		play.step(DT, at, Vector2.ZERO, false, receiver)
	play.read_pass(PackedVector2Array([receiver]))
	assert_true(play.meets, "caught, until he sees it caught")
	play.step(DT, at, Vector2.ZERO, false, receiver)
	play.step(DT, at, Vector2.ZERO, false, receiver)
	play.read_pass(PackedVector2Array([receiver]))
	assert_false(play.meets, "seen caught: no pass")
	var slow := KeeperPlayRead.new()
	_loose(slow, Vector2(3.0, -6.0), Vector2(-1.5, 0.0), 0.5)
	slow.read_pass(PackedVector2Array([receiver]))
	assert_false(slow.meets, "one that stops short of him: none")

extends GutTest

# What he reads of the play (KeeperPlayRead): a puck holding its line read
# where it is; a change of direction read going the old way until his read has
# passed, a slower tier's later; a wind-up seen late by his read and priming
# the save once he has watched it long enough; and the receivers a pass could
# reach, through a lane no defender's stick reaches, in front of the goal line
# and inside the blue line. A carried puck read his read late, carried on
# along its own motion no further from its carrier than he reaches, and whose
# carrier it is read as late; and a loose puck
# read to the first opposing stick its line reaches before it stops.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


# A carrier of theirs releasing: he reads the puck carried by one of theirs
# until his read has passed, then loose and no one's.
func test_a_release_is_read_late() -> void:
	var play := KeeperPlayRead.new()
	var body := Vector2(0.0, -6.0)
	for i: int in 30:
		play.step(DT, body, Vector2.ZERO, false, body, true)
	assert_true(play.theirs, "carried by one of theirs")
	var ticks_to_see: int = 0
	while play.theirs and ticks_to_see < 60:
		play.step(DT, body, Vector2(0.0, 25.0))
		ticks_to_see += 1
	assert_almost_eq(ticks_to_see * DT, play.delay_s, DT * 1.5, "the release seen his read late")
	assert_true(play.loose, "loose once seen")


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


# The puck held in his eyes on a stick of theirs, wound up or not, primes the
# save once he has held it KeeperPlayRead.PRIME_S, seen his read late; a puck
# swung across his view faster than his eyes follow it (a stickhandle) breaks
# the look and it starts over, as does a pass; a puck of ours never primes him.
func test_a_steady_look_at_the_puck_primes_the_save() -> void:
	var play := KeeperPlayRead.new()
	var body := Vector2(0.0, -6.0)
	var t: float = 0.0
	var primed_at: float = -1.0
	while t < 1.0 and primed_at < 0.0:
		play.step(DT, body + Vector2(0.3, -0.3), Vector2.ZERO, false, body, true)
		t += DT
		if play.primed():
			primed_at = t
	assert_almost_eq(primed_at, play.delay_s + KeeperPlayRead.PRIME_S, 2.0 * DT, "primed once held long enough, no wind-up")
	# A stickhandle: the puck swung a stick's reach across his view and back,
	# for longer than his read takes to see it.
	var swing: float = GameRules.DEFAULT_STICK_LENGTH_M
	for i: int in ceili(play.delay_s / DT) + 12:
		var off: float = swing if i % 6 < 3 else -swing
		play.step(DT, body + Vector2(off, -0.3), Vector2.ZERO, false, body, true)
	assert_false(play.primed(), "a stickhandle breaks the look")
	assert_lt(play.watched_s, KeeperPlayRead.PRIME_S, "and it starts over")
	for i: int in 60:
		play.step(DT, body, Vector2(0.0, 12.0))
	assert_false(play.primed(), "a pass breaks the look")
	var ours := KeeperPlayRead.new()
	for i: int in 90:
		ours.step(DT, body, Vector2.ZERO, false, body, false)
	assert_false(ours.primed(), "a puck of ours never primes him")


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


# A carried puck is read his read late and carried on along its own motion
# over it, as a loose one is, but never further from its carrier, carried on
# along his skating, than he reaches: a stickhandle swung across read where it
# was heading, and one held to the side read there.
func test_a_carried_puck_is_read_on_along_its_own_motion() -> void:
	var play := KeeperPlayRead.new()
	var body := Vector2(0.0, -6.0)
	var lag: int = ceili(play.delay_s / DT - 1e-6)
	var swung: Array[Vector2] = []
	for i: int in 360:
		var puck := body + Vector2(0.4 * sin(TAU * 1.5 * i * DT), -0.5)
		swung.append(puck)
		play.step(DT, puck, Vector2.ZERO, false, body)
	var seen: Vector2 = swung[swung.size() - 1 - lag]
	var own: Vector2 = (seen - swung[swung.size() - 3 - lag]) / (2.0 * DT)
	assert_almost_eq(play.puck, seen + own * lag * DT, Vector2.ONE * 1e-4, "a stickhandle, read on along its motion")
	for i: int in 60:
		play.step(DT, body + Vector2(0.5, -0.5), Vector2.ZERO, false, body)
	assert_almost_eq(play.puck, body + Vector2(0.5, -0.5), Vector2.ONE * 1e-4, "held to the side, read there")
	# A pull across read on past the carrier's reach is read at its edge.
	for i: int in 60:
		play.step(DT, body + Vector2(-1.1 + 2.2 * minf(i * DT / 0.22, 1.0), -0.3), Vector2.ZERO, false, body)
		if i == 12 + lag:
			assert_lte(play.puck.distance_to(body), KeeperPlayRead.CARRIER_REACH_M + 1e-4, "never past his reach")
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

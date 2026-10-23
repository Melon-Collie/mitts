extends GutTest

# Saves (KeeperShotRead, KeeperSave): he reads a shot only once he has watched
# it for his read's delay, its flight under gravity; the save he makes is the
# least committed one his own gear says covers the flight in time — standing
# for a shot at a pad, the glove high on his glove side, the blocker high on
# the other, the blade for one along the ice wide of the paddle — and a hand
# moves no faster than its tier's speed, gets there when the choice said, meets
# the flight, and goes back once it is over. With no time, he still goes and is
# beaten.

const DT: float = 1.0 / 120.0
# On his angle, at the top of the crease, square to a shot from the slot.
const STANDING := Vector2(0.0, -1.3)

var _motor: KeeperMotor = null
var _read: KeeperShotRead = null
var _save: KeeperSave = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_motor = KeeperMotor.new()
	_motor.x = STANDING.x
	_motor.z = STANDING.y
	_read = KeeperShotRead.new()
	_save = KeeperSave.new()


# A shot from `from` (net frame) at `speed` that arrives at the goal line at
# `to` (x across, y height), under gravity; read up to his leg read.
func _shoot(from: Vector3, to: Vector2, speed: float) -> void:
	var at_line := Vector3(to.x, to.y, 0.0)
	var t: float = from.distance_to(at_line) / speed
	var v: Vector3 = (at_line - from) / t
	# Along the ice it slides; lifted, it is thrown high enough to fall there.
	if from.y > KeeperShotRead.ON_ICE_Y or to.y > KeeperShotRead.ON_ICE_Y:
		v.y += 0.5 * GameRules.GRAVITY_M_S2 * t
	_read.step(0.0, from, v)
	_read.start()
	while not _read.legs_read():
		_fly(DT)


func _fly(dt: float) -> void:
	var p: Vector3 = _read.position_in(dt)
	var v: Vector3 = _read.velocity
	if p.y > KeeperShotRead.ON_ICE_Y:
		v.y -= GameRules.GRAVITY_M_S2 * dt
	else:
		v.y = 0.0
	_read.step(dt, p, v)


# The flight in his authored space, now and `dt` on.
func _in_him(p: Vector3) -> Vector3:
	return p - Vector3(_motor.x, 0.0, _motor.z)


func test_he_reads_a_shot_only_after_his_read() -> void:
	_read.step(0.0, Vector3(0.0, 0.1, -8.0), Vector3(0.0, 0.0, 25.0))
	_read.start()
	assert_false(_read.legs_read())
	for i: int in int(_read.leg_delay_s / DT) - 1:
		_read.step(DT, _read.position_in(DT), _read.velocity)
	assert_false(_read.legs_read(), "not before the leg read")
	_read.step(DT * 2.0, _read.position_in(DT * 2.0), _read.velocity)
	assert_true(_read.legs_read())
	assert_false(_read.arms_read(), "the arms read later")


func test_the_flight_falls_and_lands_on_the_net_or_not() -> void:
	_read.step(0.0, Vector3(0.0, 0.5, -10.0), Vector3(0.0, 3.0, 20.0))
	var t: float = 0.4
	assert_almost_eq(_read.position_in(t).y, 0.5 + 3.0 * t - 0.5 * GameRules.GRAVITY_M_S2 * t * t, 1e-5)
	assert_almost_eq(_read.time_to_line(), 0.5, 1e-6)
	assert_true(_read.on_net(), "under the bar")
	_read.step(0.0, Vector3(1.5, 0.1, -10.0), Vector3(0.0, 0.0, 20.0))
	assert_false(_read.on_net(), "wide of the post")
	_read.step(0.0, Vector3(0.0, 0.1, -10.0), Vector3(0.0, 0.0, -20.0))
	assert_eq(_read.time_to_line(), INF, "going away")


func test_a_shot_at_his_pad_is_saved_standing() -> void:
	_shoot(Vector3(0.0, KeeperShotRead.ON_ICE_Y, -9.0), Vector2(0.3, 0.25), 25.0)
	_save.choose(_read, _motor, false)
	assert_true(_save.covers)
	assert_eq(_save.low, KeeperSave.Low.NONE)
	assert_eq(_save.hand, KeeperSave.Hand.NONE, "his pad is already there")
	assert_lte(_save.ready_s, _save.impact_s)


func test_high_on_either_side_his_hand_goes_and_meets_it() -> void:
	for case: Array in [[-0.85, KeeperSave.Hand.GLOVE, KeeperGear.Part.GLOVE],
			[0.85, KeeperSave.Hand.BLOCKER, KeeperGear.Part.BLOCKER]]:
		before_each()
		_shoot(Vector3(0.0, 0.3, -9.0), Vector2(float(case[0]), 1.0), 20.0)
		_save.choose(_read, _motor, false)
		var what: String = KeeperSave.Hand.keys()[case[1]]
		assert_eq(_save.hand, case[1], what)
		assert_true(_save.covers, what)
		assert_lte(_save.ready_s, _save.impact_s, "%s: in time" % what)
		_hand_to_the_puck(case[2], what)


# Runs the hand and the flight on together until the puck reaches his gear:
# the hand never faster than its speed, and there when the choice said.
func _hand_to_the_puck(part: int, what: String) -> void:
	var t: float = 0.0
	var was := Vector3.INF
	var speed: float = _save.glove_speed_m_s if part == KeeperGear.Part.GLOVE else _save.blocker_speed_m_s
	var hit: int = -1
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	while t < _save.impact_s + 0.05 and hit < 0:
		var from: Vector3 = _in_him(_read.at)
		_fly(DT)
		t += DT
		_motor.pose(_pose)
		_save.step(DT, _read.arms_read(), _pose)
		_save.overlay(_pose)
		_skel.pose(_pose)
		var hand_at: Vector3 = KeeperGear.box(_skel, part).origin
		if was != Vector3.INF:
			assert_lte(hand_at.distance_to(was), speed * DT + 0.01, "%s t %.3f: no faster than it moves" % [what, t])
		was = hand_at
		hit = KeeperGear.nearest(_skel, from, _in_him(_read.at), GameRules.PUCK_COLLISION_RADIUS, out, scratch)
	assert_eq(hit, part, "%s: the puck meets it" % what)


func test_along_the_ice_wide_of_the_paddle_the_blade_goes() -> void:
	_shoot(Vector3(0.0, KeeperShotRead.ON_ICE_Y, -9.0), Vector2(-0.6, KeeperShotRead.ON_ICE_Y), 22.0)
	_save.choose(_read, _motor, false)
	assert_true(_save.covers)
	assert_eq(_save.hand, KeeperSave.Hand.STICK)


func test_in_tight_to_a_far_corner_he_goes_and_is_beaten() -> void:
	_motor.z = -0.4
	_shoot(Vector3(0.0, 0.3, -2.5), Vector2(-0.85, 1.05), 30.0)
	_save.choose(_read, _motor, false)
	assert_eq(_save.hand, KeeperSave.Hand.GLOVE, "he still goes for it")
	assert_true(not _save.covers or _save.ready_s > _save.impact_s, "and is beaten")


func test_released_the_hand_goes_back_and_the_save_ends() -> void:
	_shoot(Vector3(0.0, 0.3, -9.0), Vector2(-0.85, 1.0), 20.0)
	_save.choose(_read, _motor, false)
	_motor.pose(_pose)
	for i: int in 40:
		_fly(DT)
		_motor.pose(_pose)
		_save.step(DT, _read.arms_read(), _pose)
	assert_true(_save.active(), "out")
	_save.release()
	var t: float = 0.0
	while _save.active() and t < 1.0:
		_motor.pose(_pose)
		_save.step(DT, true, _pose)
		t += DT
	assert_false(_save.active(), "back")
	assert_eq(_save.hand, KeeperSave.Hand.NONE)


func test_a_right_catcher_catches_with_his_glove_on_his_own_side() -> void:
	_shoot(Vector3(0.0, 0.3, -9.0), Vector2(0.85, 1.0), 20.0)
	_save.choose(_read, _motor, true)
	assert_eq(_save.hand, KeeperSave.Hand.GLOVE, "high to +x is his glove side")

extends GutTest

# Rebound control (KeeperSave's face turns): a stick or blocker save is made
# with the face turned so what comes off it goes toward the near corner.
# Against the same shot unsteered, the save he makes meets and holds it and
# sends it no less toward the corner; straight on from the slot, at his
# blocker or along the ice at his stick, he turns the face and it goes more
# that way. The face turns no faster than the hand's far edge moves at its
# speed, and back once the save is over.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const FROM: Array[Vector3] = [Vector3(0.0, 0.05, -8.0), Vector3(-3.0, 0.05, -7.0), Vector3(3.0, 0.05, -7.0),
		Vector3(-6.0, 0.05, -4.0), Vector3(6.0, 0.05, -4.0)]
# Where at the goal line (across, height): high and mid at his blocker, along
# the ice at his stick.
const BLOCKER_HIGH := Vector2(0.55, 0.8)
const BLOCKER_MID := Vector2(0.6, 0.4)
const ICE: Array[Vector2] = [Vector2(-0.2, 0.0), Vector2(0.0, 0.0), Vector2(0.2, 0.0)]
const SPEED_M_S: float = 25.0


# The same save with the face never turned.
class Unsteered extends KeeperSave:
	func _steer(_l: int, _side: float, _h: int) -> float:
		return 0.0


# A read of a shot from `from` (net frame) arriving at `to` on the goal line,
# up to his leg read.
func _read_of(from: Vector3, to: Vector2) -> KeeperShotRead:
	var read := KeeperShotRead.new()
	var at_line := Vector3(to.x, to.y, 0.0)
	var t: float = from.distance_to(at_line) / SPEED_M_S
	var v: Vector3 = (at_line - from) / t
	if to.y > KeeperShotRead.ON_ICE_Y:
		v.y += 0.5 * GameRules.GRAVITY_M_S2 * t
	read.step(0.0, from, v)
	read.start()
	while not read.legs_read():
		var p: Vector3 = read.position_in(DT)
		var w: Vector3 = read.velocity
		w.y = w.y - GameRules.GRAVITY_M_S2 * DT if p.y > KeeperShotRead.ON_ICE_Y else 0.0
		read.step(DT, p, w)
	return read


# On his angle to `from`, at the top of the crease.
func _set_for(from: Vector3) -> KeeperMotor:
	var motor := KeeperMotor.new()
	var spot: Vector2 = Vector2(from.x, from.z).normalized() * 1.3
	motor.x = spot.x
	motor.z = spot.y
	motor.yaw = KeeperPositioning.facing(spot, Vector2(from.x, from.z))
	return motor


func test_a_steered_save_holds_and_sends_it_no_less_toward_the_corner() -> void:
	for from: Vector3 in FROM:
		for to: Vector2 in [BLOCKER_HIGH, BLOCKER_MID] + ICE:
			var what: String = "from %s to %s" % [Vector2(from.x, from.z), to]
			var motor: KeeperMotor = _set_for(from)
			var steered := KeeperSave.new()
			steered.choose(_read_of(from, to), motor, false)
			var plain := Unsteered.new()
			plain.choose(_read_of(from, to), motor, false)
			assert_eq(steered.covers, plain.covers, what + ": met as unsteered")
			assert_gte(steered.to_corner(), plain.to_corner() - 1e-4, what + ": no less toward the corner")


func test_straight_on_he_turns_the_face_toward_the_corner() -> void:
	var slot: Vector3 = FROM[0]
	for to: Vector2 in [BLOCKER_HIGH, Vector2(0.0, 0.0)]:
		var motor: KeeperMotor = _set_for(slot)
		var steered := KeeperSave.new()
		steered.choose(_read_of(slot, to), motor, false)
		var plain := Unsteered.new()
		plain.choose(_read_of(slot, to), motor, false)
		assert_has([KeeperSave.Hand.STICK, KeeperSave.Hand.BLOCKER], steered.hand, "%s: the stick or the blocker" % to)
		assert_ne(steered.face_turn, 0.0, "%s: the face turned" % to)
		assert_gt(steered.to_corner(), plain.to_corner(), "%s: more toward the corner" % to)


# The face goes out to its turn no faster than its far edge moves at the
# hand's speed, and back once the save is over.
func test_the_face_turns_at_the_hands_pace_and_back() -> void:
	var slot: Vector3 = FROM[0]
	var motor: KeeperMotor = _set_for(slot)
	var save := KeeperSave.new()
	save.choose(_read_of(slot, BLOCKER_HIGH), motor, false)
	assert_eq(save.hand, KeeperSave.Hand.BLOCKER, "the blocker")
	var base := KeeperPose.new()
	motor.pose(base)
	var rate: float = save.blocker_speed_m_s / KeeperAnatomy.BLADE_LENGTH_M
	var was: float = _blocker_turn(save, base)
	for i: int in 30:
		save.step(DT, true, base)
		var now: float = _blocker_turn(save, base)
		assert_lte(absf(now - was), rate * DT + 1e-4, "tick %d: no faster than the hand" % i)
		was = now
	assert_almost_eq(was, save.face_turn, 1e-3, "turned all the way")
	save.release()
	for i: int in 60:
		save.step(DT, true, base)
	assert_almost_eq(_blocker_turn(save, base), 0.0, 1e-3, "and back")


# How far the blocker's board is turned from the stance's, about the vertical.
func _blocker_turn(save: KeeperSave, base: KeeperPose) -> float:
	var p := KeeperPose.new()
	p.copy_from(base)
	save.overlay(p)
	var a := Vector2(base.blocker_face.x, base.blocker_face.z)
	var b := Vector2(p.blocker_face.x, p.blocker_face.z)
	return -a.angle_to(b)

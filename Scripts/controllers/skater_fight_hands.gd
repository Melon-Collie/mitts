class_name SkaterFightHands
extends RefCounted

# A fighter's two fists (docs/fighting-plan.md §3), owned outright: where each
# is and how fast it moves, in UpperBody's frame, and what the holding hand
# holds. The punching fist chases the cursor (FightFistRules); the holding hand
# keeps the guard (FightGuardRules) until the grab button takes the other man's
# sweater or punching arm (FightHoldRules), and then follows the hold. The slap
# button swaps the hands, letting go first. Each fist is laid on its arm's
# marker — the top hand's on TopHand, the bottom hand's on the stick's Blade
# marker, which the stick on the ice frees — so the wire carries both.
#
# Stepped on live ticks only, like SkaterPoseBridge: the fists have momentum the
# wire does not carry, so a reconcile replay lays the fists the live tick left
# (lay_markers) rather than playing them again.

const Grip = FightHoldRules.Grip
const Side = FightHoldRules.Side

var _skater: Skater = null
var _ik: SkaterIKCoordinator = null
var _seeded: bool = false
var _top := Vector3.ZERO
var _top_vel := Vector3.ZERO
var _bottom := Vector3.ZERO
var _bottom_vel := Vector3.ZERO
# A grip let go of by the swap, or torn away, is taken again only after the
# grab button has come up.
var _grab_spent: bool = false


func setup(skater: Skater, ik: SkaterIKCoordinator) -> void:
	_skater = skater
	_ik = ik


# Out of a fight: the hands go back to the stick, and the next fight starts from
# wherever they are then.
func leave() -> void:
	if not _seeded:
		return
	_seeded = false
	_top_vel = Vector3.ZERO
	_bottom_vel = Vector3.ZERO
	_skater.fight_grip = Grip.NONE
	_skater.fight_punch_side = Side.TOP
	_grab_spent = false


# A live tick's fists. `partner` is the man being fought, null for none, his
# body at `partner_pos` this tick (world).
func step(input: InputState, delta: float, partner: Skater, partner_pos: Vector3) -> void:
	if not _seeded:
		_top = _skater.get_top_hand_position()
		_bottom = _skater.bottom_hand.position
		_seeded = true
	if input.slap_pressed:
		_skater.fight_punch_side = Side.BOTTOM if _skater.fight_punch_side == Side.TOP \
				else Side.TOP
		_skater.fight_grip = Grip.NONE
		_grab_spent = true
	var top_punches: bool = _skater.fight_punch_side == Side.TOP
	var reach: float = arm_reach(_skater)
	var punch_shoulder: Vector3 = _shoulder(top_punches)
	var hold_shoulder: Vector3 = _shoulder(not top_punches)
	var at: Vector3 = Vector3.ZERO if partner == null else partner_pos - partner.global_position

	var guard: Vector3 = FightGuardRules.guard_hand(punch_shoulder)
	var chin_y: float = guard.y
	var tied: bool = false
	if partner != null:
		chin_y = _skater.upper_body_to_local(chin_world(partner) + at).y
		tied = FightHoldRules.tied(_skater.fight_punch_side, partner.fight_grip)
	var rattled: float = FightPunchRules.fist_scale(_skater.fight_rattle)
	var speed: float = FightFistRules.MAX_SPEED_M_S * rattled
	var accel: float = FightFistRules.MAX_ACCEL_M_S2 * rattled
	var punch_reach: float = reach
	if tied:
		speed *= FightFistRules.TIED_SPEED_SHARE
		accel *= FightFistRules.TIED_SPEED_SHARE
		punch_reach *= FightFistRules.TIED_REACH_SHARE
	var target: Vector3 = FightFistRules.target(punch_shoulder,
			_skater.upper_body_to_local(input.mouse_world_pos), punch_reach, guard.y, chin_y)

	var hold_target: Vector3 = _hold(input, partner, at, hold_shoulder, reach)
	if top_punches:
		_move_top(target, delta, speed, accel, punch_shoulder, punch_reach)
		_move_bottom(hold_target, delta, FightFistRules.MAX_SPEED_M_S,
				FightFistRules.MAX_ACCEL_M_S2, hold_shoulder, reach + FightHoldRules.GRAB_SLACK_M)
	else:
		_move_bottom(target, delta, speed, accel, punch_shoulder, punch_reach)
		_move_top(hold_target, delta, FightFistRules.MAX_SPEED_M_S,
				FightFistRules.MAX_ACCEL_M_S2, hold_shoulder, reach + FightHoldRules.GRAB_SLACK_M)
	lay_markers()


# The fists where the last live tick left them, on their arms' markers.
func lay_markers() -> void:
	if not _seeded:
		return
	_skater.set_top_hand_position(_top)
	_skater.set_blade_position(_bottom)


# An arm's straight reach off its shoulder: the arm, at the working extension
# the stick's IK reaches to, and the shoulder's own reach.
static func arm_reach(s: Skater) -> float:
	return (s.upper_arm_length + s.forearm_length) * s.arm_working_extension + s.shoulder_reach_m


# A man's chin, world: his guard's height, between his shoulders.
static func chin_world(s: Skater) -> Vector3:
	var mid: Vector3 = (s.shoulder.position + s.bottom_shoulder.position) * 0.5
	mid.y += FightGuardRules.GUARD_UP_M
	return s.upper_body_to_global(mid)


# What the holding hand reaches for this tick, in UpperBody's frame: the guard,
# or the grip, which the grab button takes and keeps while it can.
func _hold(input: InputState, partner: Skater, at: Vector3, shoulder: Vector3,
		reach: float) -> Vector3:
	var guard: Vector3 = FightGuardRules.guard_hand(shoulder)
	if not input.shoot_held:
		_grab_spent = false
	if partner == null or not input.shoot_held:
		_skater.fight_grip = Grip.NONE
		return guard
	var shoulder_world: Vector3 = _skater.upper_body_to_global(shoulder)
	var holding_top: bool = _skater.fight_punch_side == Side.BOTTOM
	var hand_world: Vector3 = _skater.upper_body_to_global(_top if holding_top else _bottom)
	if _skater.fight_grip == Grip.NONE and not _grab_spent:
		var their_arm: int = FightHoldRules.arm_grip_for(partner.fight_punch_side)
		var arm: Vector3 = _grip_point(partner, at, their_arm)
		if not _arm_thrown(partner, their_arm):
			their_arm = Grip.NONE
		_skater.fight_grip = FightHoldRules.choose(hand_world, shoulder_world, reach,
				_grip_point(partner, at, Grip.JERSEY), arm, their_arm)
	if _skater.fight_grip == Grip.NONE:
		return guard
	var point: Vector3 = _grip_point(partner, at, _skater.fight_grip)
	if FightHoldRules.torn(shoulder_world, point, reach):
		_skater.fight_grip = Grip.NONE
		_grab_spent = true
		return guard
	return _skater.upper_body_to_local(point)


# Where on him a grip holds, world.
func _grip_point(partner: Skater, at: Vector3, grip: int) -> Vector3:
	if grip == Grip.JERSEY:
		return FightHoldRules.jersey_point(partner.global_position + at,
				partner.collision_radius(), _skater.global_position,
				partner.upper_body_to_global(partner.shoulder.position).y + at.y)
	var top: bool = grip == Grip.ARM_TOP
	var shoulder: Vector3 = partner.upper_body_to_global(
			partner.shoulder.position if top else partner.bottom_shoulder.position)
	var fist: Vector3 = partner.upper_body_to_global(
			partner.get_top_hand_position() if top else partner.get_blade_position())
	return FightHoldRules.arm_point(shoulder, fist) + at


# Whether his arm `grip` names is out, thrown (FightHoldRules.thrown).
static func _arm_thrown(partner: Skater, grip: int) -> bool:
	var top: bool = grip == Grip.ARM_TOP
	return FightHoldRules.thrown(
			partner.shoulder.position if top else partner.bottom_shoulder.position,
			partner.get_top_hand_position() if top else partner.get_blade_position(),
			arm_reach(partner))


func _shoulder(top: bool) -> Vector3:
	return _ik.arm_shoulder() if top else _skater.bottom_shoulder.position


func _move_top(target: Vector3, delta: float, speed: float, accel: float, shoulder: Vector3,
		reach: float) -> void:
	_top_vel = FightFistRules.step_velocity(_top, _top_vel, target, delta, speed, accel)
	var moved: Vector3 = FightFistRules.held_to_reach(shoulder, _top + _top_vel * delta, reach)
	_top_vel = (moved - _top) / delta if delta > 0.0 else _top_vel
	_top = moved


func _move_bottom(target: Vector3, delta: float, speed: float, accel: float, shoulder: Vector3,
		reach: float) -> void:
	_bottom_vel = FightFistRules.step_velocity(_bottom, _bottom_vel, target, delta, speed, accel)
	var moved: Vector3 = FightFistRules.held_to_reach(shoulder, _bottom + _bottom_vel * delta, reach)
	_bottom_vel = (moved - _bottom) / delta if delta > 0.0 else _bottom_vel
	_bottom = moved

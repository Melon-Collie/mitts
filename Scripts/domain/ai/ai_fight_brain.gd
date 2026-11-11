class_name AIFightBrain
extends RefCounted

# How a bot fights once the gloves are off (docs/fighting-plan.md, phase 5). It
# works the same three controls a human does (SkaterFightHands): the cursor, the
# grab and the swap.
#
# - It holds the guard, the cursor just in front of it, and the sweater, the
#   grab held.
# - It throws on a cadence its tier's check aggression sets: the cursor out
#   through the other man's head, round the side of it his guard leaves open
#   (the side whose fist sits further from his head), then back to the guard.
#   It doesn't throw while he has its punching arm.
# - It reads two things a beat late, by its tier's reaction delay: his punching
#   arm thrown, which it catches (letting the sweater go for a tick so the grab
#   takes again and finds the arm nearer), and its own punching arm held, which
#   it frees by swapping hands. Both need `ties_up_arms`; an Easy bot only
#   guards, holds and throws.
#
# Engine-free: everything it sees comes in through View, in world space.

const Grip = FightHoldRules.Grip

# Where the guard's cursor rests, ahead of the body, m: inside the arm's reach,
# so the fist stays up and bent.
const GUARD_AHEAD_M: float = 0.35
# How far past his head the throw drives the cursor, so the fist arrives at
# full extension and full speed rather than easing onto him.
const THROUGH_M: float = 0.3
# How far round his guard a throw aims, m off the line to his head.
const AROUND_M: float = 0.2
# A throw is out this long before the cursor comes back, and back this long
# before the next can start: a fist's travel and its return.
const THROW_S: float = 0.18
const RECOVER_S: float = 0.25
# The gap between throws at full check aggression, and at none. A feel tunable
# on the pace axis (Scripts/domain/ai/CLAUDE.md).
const GAP_AGGRESSIVE_S: float = 0.6
const GAP_PASSIVE_S: float = 2.0


class View:
	var me := Vector3.ZERO
	var facing := Vector2(0.0, -1.0)
	var head := Vector3.ZERO           # his head, world
	var his_top_fist := Vector3.ZERO
	var his_bottom_fist := Vector3.ZERO
	var his_arm_thrown: bool = false   # his punching arm, out (FightHoldRules.thrown)
	var my_grip: int = Grip.NONE
	var my_arm_held: bool = false      # he has my punching arm (FightHoldRules.tied)


class Decision:
	var aim := Vector3.ZERO
	var grab: bool = true
	var swap: bool = false


var _reaction_s: float = 0.2
var _gap_s: float = 1.2
var _ties_up_arms: bool = true
var _until_next_s: float = 0.0
var _throw_left_s: float = 0.0
var _recover_left_s: float = 0.0
var _arm_seen_s: float = 0.0
var _held_s: float = 0.0
var _let_go: bool = false
var _out := Decision.new()


# `phase_s` staggers bots' cadences so two never throw in step.
func setup(profile: BotSkillProfile, phase_s: float) -> void:
	if profile != null:
		_reaction_s = profile.carrier_reaction_delay_s
		_gap_s = lerpf(GAP_PASSIVE_S, GAP_AGGRESSIVE_S, clampf(profile.check_aggression, 0.0, 1.0))
		_ties_up_arms = profile.ties_up_arms
	_until_next_s = fposmod(phase_s, _gap_s)


# This tick's controls. The returned Decision is this brain's own and is
# overwritten by the next call: read it before calling again.
func decide(v: View, delta: float) -> Decision:
	var forward := Vector3(v.facing.x, 0.0, v.facing.y)
	_out.swap = false
	_out.grab = true
	_out.aim = v.me + forward * GUARD_AHEAD_M

	_held_s = _held_s + delta if v.my_arm_held else 0.0
	if _ties_up_arms and _held_s >= _reaction_s:
		_out.swap = true
		_held_s = 0.0

	_arm_seen_s = _arm_seen_s + delta if v.his_arm_thrown else 0.0
	var holding_arm: bool = v.my_grip == Grip.ARM_TOP or v.my_grip == Grip.ARM_BOTTOM
	if _let_go:
		_let_go = false
	elif _ties_up_arms and not holding_arm and _arm_seen_s >= _reaction_s:
		_out.grab = false   # one tick up, so the grab takes again: his arm, nearer
		_let_go = true

	if _throw_left_s > 0.0:
		_throw_left_s -= delta
		if _throw_left_s <= 0.0:
			_recover_left_s = RECOVER_S
		_out.aim = _through_his_guard(v)
	elif _recover_left_s > 0.0:
		_recover_left_s -= delta
	else:
		_until_next_s -= delta
		if _until_next_s <= 0.0 and not v.my_arm_held:
			_throw_left_s = THROW_S
			_until_next_s = _gap_s
			_out.aim = _through_his_guard(v)
	return _out


# Through his head, round the side his guard leaves open.
func _through_his_guard(v: View) -> Vector3:
	var to := Vector3(v.head.x - v.me.x, 0.0, v.head.z - v.me.z)
	if to.length_squared() < 1e-6:
		return v.head
	to = to.normalized()
	var across := Vector3(-to.z, 0.0, to.x)
	var top_side: float = (v.his_top_fist - v.head).dot(across)
	var bottom_side: float = (v.his_bottom_fist - v.head).dot(across)
	# The open side is away from whichever of his fists covers the line most.
	var covered: float = top_side if absf(top_side) < absf(bottom_side) else bottom_side
	var open_side: float = -signf(covered) if covered != 0.0 else 1.0
	return Vector3(v.head.x, 0.0, v.head.z) + to * THROUGH_M + across * AROUND_M * open_side

class_name AIFightBrain
extends RefCounted

# How a bot fights once the gloves are off (docs/fighting-plan.md, phase 5). It
# works the controls a human does (SkaterFightHands): the stick, the cursor, the
# grab and the swap.
#
# - It skates in until its fist reaches his head, and stands there.
# - It holds the guard, the cursor just in front of it, and the sweater, the
#   grab held.
# - In range, it throws on a cadence its tier's check aggression sets, then
#   comes back to the guard. With none of his arms up in his guard the cursor
#   goes straight out through his head. With one up it is a hook: out beside
#   his head on the side he leaves open (away from the guarding fist furthest
#   off the line to his head), then across through it. It doesn't throw while
#   he has its punching arm.
# - It reads two things a beat late, by its tier's reaction delay: his punching
#   arm thrown, which it catches (letting the sweater go for a tick so the grab
#   takes again and finds the arm nearer), and its own punching arm held, which
#   it frees by swapping hands. Both need `ties_up_arms`; an Easy bot only
#   closes, guards, holds and throws.
# - With a man down it is over: it stands off with its guard up.
#
# Engine-free: everything it sees comes in through View, in world space.

const Grip = FightHoldRules.Grip

# Where the guard's cursor rests, ahead of the body, m: inside the arm's reach,
# so the fist stays up and bent.
const GUARD_AHEAD_M: float = 0.35
# How far past his head the throw drives the cursor, so the fist arrives at
# full extension and full speed rather than easing onto him.
const THROUGH_M: float = 0.3
# A hook winds out to a point this far beside his head, level with it: clear of
# his head's size and a fist's, and behind the guard held in front of his face.
const HOOK_OUT_M: float = 0.3
# The hook's wind-up: a fist's travel out to that point.
const WIND_S: float = 0.1
# A throw is out this long before the cursor comes back, and back this long
# before the next can start: a fist's travel and its return.
const THROW_S: float = 0.18
const RECOVER_S: float = 0.25
# The gap between throws at full check aggression, and at none. A feel tunable
# on the pace axis (Scripts/domain/ai/CLAUDE.md).
const GAP_AGGRESSIVE_S: float = 0.6
const GAP_PASSIVE_S: float = 1.6
# It stands with its centre this far past its arm's reach from his: close
# enough that a fist wound out beside his head gets there.
const STAND_PAST_REACH_M: float = 0.03
# It throws from no further than this past its arm's reach, centre to centre:
# the shoulder ahead of its own centre, and the fist's and his head's size.
const STRIKE_PAST_REACH_M: float = 0.22


class View:
	var me := Vector3.ZERO
	var facing := Vector2(0.0, -1.0)
	var head := Vector3.ZERO           # his head, world
	var his_top_fist := Vector3.ZERO
	var his_bottom_fist := Vector3.ZERO
	var his_arm_thrown: bool = false   # his punching arm, out (FightHoldRules.thrown)
	var his_top_guards: bool = true    # that arm is up in his guard (SkaterFightHands.arm_guards)
	var his_bottom_guards: bool = true
	var my_grip: int = Grip.NONE
	var my_arm_held: bool = false      # he has my punching arm (FightHoldRules.tied)
	var him := Vector3.ZERO            # his body, world
	var reach: float = 0.7             # my arm's (SkaterFightHands.arm_reach)
	var man_down: bool = false         # one of us is on the ice


class Decision:
	var aim := Vector3.ZERO
	var grab: bool = true
	var swap: bool = false
	var move := Vector2.ZERO           # the stick, world XZ
	var brake: bool = true


var _reaction_s: float = 0.2
var _gap_s: float = 1.2
var _ties_up_arms: bool = true
var _until_next_s: float = 0.0
var _throw_left_s: float = 0.0
var _recover_left_s: float = 0.0
var _wind_left_s: float = 0.0
# The side this throw goes round his guard, across the line to his head: ±1, or
# 0 straight through.
var _hook_side: float = 0.0
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
	_out.grab = not v.man_down
	_out.aim = v.me + forward * GUARD_AHEAD_M
	_out.move = Vector2.ZERO
	_out.brake = true
	if v.man_down:
		_wind_left_s = 0.0
		_throw_left_s = 0.0
		_recover_left_s = 0.0
		return _out
	var to_him := Vector2(v.him.x - v.me.x, v.him.z - v.me.z)
	var dist: float = to_him.length()
	# A man who has skated off is let go (FightRules.DISENGAGE_M).
	if dist > v.reach + STAND_PAST_REACH_M and dist < FightRules.DISENGAGE_M:
		_out.move = to_him / dist
		_out.brake = false
	var in_range: bool = dist <= v.reach + STRIKE_PAST_REACH_M

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

	if _wind_left_s > 0.0:
		_wind_left_s -= delta
		_out.aim = _beside_his_head(v)
	elif _throw_left_s > 0.0:
		_throw_left_s -= delta
		if _throw_left_s <= 0.0:
			_recover_left_s = RECOVER_S
		_out.aim = _through_his_head(v)
	elif _recover_left_s > 0.0:
		_recover_left_s -= delta
	else:
		_until_next_s -= delta
		if _until_next_s <= 0.0 and in_range and not v.my_arm_held:
			_hook_side = _open_side(v)
			_wind_left_s = WIND_S if _hook_side != 0.0 else 0.0
			_throw_left_s = THROW_S
			_until_next_s = _gap_s
			_out.aim = _beside_his_head(v) if _hook_side != 0.0 else _through_his_head(v)
	return _out


# Whether a punch is on its way: winding out, or thrown.
func throwing() -> bool:
	return _wind_left_s > 0.0 or _throw_left_s > 0.0


# Which side of his guard is open, across the line to his head: away from the
# guarding fist furthest off that line, or 0 with none of his arms up.
func _open_side(v: View) -> float:
	var across: Vector3 = _across(v)
	var top: float = (v.his_top_fist - v.head).dot(across) if v.his_top_guards else 0.0
	var bottom: float = (v.his_bottom_fist - v.head).dot(across) if v.his_bottom_guards else 0.0
	if not v.his_top_guards and not v.his_bottom_guards:
		return 0.0
	var covered: float = top if absf(top) > absf(bottom) else bottom
	return -1.0 if covered >= 0.0 else 1.0


# The line to his head and across it, flat on the ice.
func _toward(v: View) -> Vector3:
	var to := Vector3(v.head.x - v.me.x, 0.0, v.head.z - v.me.z)
	return to.normalized() if to.length_squared() > 1e-6 else Vector3(v.facing.x, 0.0, v.facing.y)


func _across(v: View) -> Vector3:
	var to: Vector3 = _toward(v)
	return Vector3(-to.z, 0.0, to.x)


# The hook's wind-up: beside his head on the open side.
func _beside_his_head(v: View) -> Vector3:
	return Vector3(v.head.x, 0.0, v.head.z) + _across(v) * HOOK_OUT_M * _hook_side


# The throw: straight out past his head, or across through it from the side the
# hook wound out to.
func _through_his_head(v: View) -> Vector3:
	var head := Vector3(v.head.x, 0.0, v.head.z)
	if _hook_side == 0.0:
		return head + _toward(v) * THROUGH_M
	return head - _across(v) * THROUGH_M * _hook_side

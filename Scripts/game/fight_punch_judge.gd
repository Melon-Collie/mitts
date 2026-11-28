class_name FightPunchJudge
extends RefCounted

# Host-only: whether each fighter's punching fist landed on the man he is
# fighting this tick (FightPunchRules). The fist is swept from where it was last
# tick to where it is now, in the world, against the other man's head, chest
# and the arms he has up in his guard (SkaterFightHands.arm_guards) as they are
# now; the first it meets is the hit, an arm is a block, and too slow a fist
# lands nothing. A landed fist lands nothing more for
# FightPunchRules.HIT_COOLDOWN_S, and nothing lands with either man down.
# GameManager does what a punch does.
#
# Judged on the host's own copy of both bodies and both fists, at the host's
# present, as a body check is.

signal punch_landed(attacker: Skater, victim: Skater, hit: int, speed: float, toward: Vector3)

const Hit = FightPunchRules.Hit

# What a swept fist met first, and that volume's middle (world).
class Contact:
	var hit: int = FightPunchRules.Hit.NONE
	var center := Vector3.ZERO
	var at: float = 2.0


var _partner_of: Callable = Callable()     # (Skater) -> Skater, null for none
var _now_getter: Callable = Callable()     # () -> float, host seconds
var _last_fist: Dictionary = {}            # Skater -> Vector3, world, last tick
var _cool_until: Dictionary = {}           # Skater -> host seconds
var _contact := Contact.new()


func setup(partner_of: Callable, now_getter: Callable) -> void:
	_partner_of = partner_of
	_now_getter = now_getter


func clear() -> void:
	_last_fist.clear()
	_cool_until.clear()


# `fighters`: everyone fighting this tick.
func tick(fighters: Array[Skater], delta: float) -> void:
	if fighters.is_empty():
		if not _last_fist.is_empty():
			clear()
		return
	var now: float = _now_getter.call() if _now_getter.is_valid() else 0.0
	for attacker: Skater in fighters:
		var fist: Vector3 = punching_fist(attacker)
		var from: Vector3 = _last_fist.get(attacker, fist)
		_last_fist[attacker] = fist
		if delta <= 0.0 or attacker.is_knocked_down \
				or now < float(_cool_until.get(attacker, -INF)):
			continue
		var victim: Skater = _partner_of.call(attacker) if _partner_of.is_valid() else null
		if victim == null or not is_instance_valid(victim) or victim.is_knocked_down:
			continue
		contact(from, fist, victim, _contact)
		if _contact.hit == Hit.NONE:
			continue
		var toward: Vector3 = _contact.center - from
		toward = toward.normalized() if toward.length_squared() > 1e-8 else (fist - from).normalized()
		var speed: float = FightPunchRules.closing_speed((fist - from) / delta, victim.velocity, toward)
		if not FightPunchRules.lands(speed):
			continue
		_cool_until[attacker] = now + FightPunchRules.HIT_COOLDOWN_S
		punch_landed.emit(attacker, victim, _contact.hit, speed, toward)


# What a fist swept from `from` to `to` (world) meets first on `victim`, into
# `out`: his head, his chest, or an arm he has up in his guard.
static func contact(from: Vector3, to: Vector3, victim: Skater, out: Contact) -> void:
	out.hit = Hit.NONE
	out.at = 2.0
	var head: Vector3 = head_center(victim)
	_meet(out, Hit.HEAD, head, FightPunchRules.sweep_sphere(from, to, head,
			FightPunchRules.HEAD_RADIUS_M + FightPunchRules.FIST_RADIUS_M))
	var chest: Vector3 = chest_center(victim)
	_meet(out, Hit.BODY, chest, FightPunchRules.sweep_sphere(from, to, chest,
			FightPunchRules.BODY_RADIUS_M + FightPunchRules.FIST_RADIUS_M))
	_meet_arm(out, from, to, victim, true)
	_meet_arm(out, from, to, victim, false)


static func _meet_arm(out: Contact, from: Vector3, to: Vector3, victim: Skater, top: bool) -> void:
	if not SkaterFightHands.arm_guards(victim, top):
		return
	var arm_fist: Vector3 = victim.upper_body_to_global(SkaterFightHands.fist_local(victim, top))
	var shoulder: Vector3 = victim.upper_body_to_global(SkaterFightHands.shoulder_local(victim, top))
	_meet(out, Hit.BLOCKED, arm_fist, FightPunchRules.sweep_capsule(from, to,
			arm_fist.lerp(shoulder, FightPunchRules.GUARD_ARM_SHARE), arm_fist,
			FightPunchRules.ARM_RADIUS_M + FightPunchRules.FIST_RADIUS_M))


static func _meet(out: Contact, hit: int, center: Vector3, t: float) -> void:
	if t >= 0.0 and t < out.at:
		out.hit = hit
		out.at = t
		out.center = center


# The fist a fighter punches with, world: the top arm's on TopHand, the bottom
# arm's on the Blade marker (SkaterFightHands).
static func punching_fist(s: Skater) -> Vector3:
	return s.upper_body_to_global(SkaterFightHands.fist_local(s,
			s.fight_punch_side == FightHoldRules.Side.TOP))


static func head_center(s: Skater) -> Vector3:
	return SkaterFightHands.head_world(s)


static func chest_center(s: Skater) -> Vector3:
	var mid: Vector3 = (s.shoulder.position + s.bottom_shoulder.position) * 0.5
	return s.upper_body_to_global(mid) + Vector3.DOWN * FightPunchRules.BODY_BELOW_SHOULDERS_M

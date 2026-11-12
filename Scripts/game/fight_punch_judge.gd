class_name FightPunchJudge
extends RefCounted

# Host-only: whether each fighter's punching fist landed on the man he is
# fighting this tick (FightPunchRules). The fist is swept from where it was last
# tick to where it is now, in the world, against the other man's head, chest
# and arms as they are now; the first it meets is the hit, an arm is a block,
# and too slow a fist lands nothing. A landed fist lands nothing more for
# FightPunchRules.HIT_COOLDOWN_S. GameManager does what a punch does.
#
# Judged on the host's own copy of both bodies and both fists, at the host's
# present, as a body check is.

signal punch_landed(attacker: Skater, victim: Skater, hit: int, speed: float, toward: Vector3)

const Hit = FightPunchRules.Hit

var _partner_of: Callable = Callable()     # (Skater) -> Skater, null for none
var _now_getter: Callable = Callable()     # () -> float, host seconds
var _last_fist: Dictionary = {}            # Skater -> Vector3, world, last tick
var _cool_until: Dictionary = {}           # Skater -> host seconds


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
		if delta <= 0.0 or now < float(_cool_until.get(attacker, -INF)):
			continue
		var victim: Skater = _partner_of.call(attacker) if _partner_of.is_valid() else null
		if victim == null or not is_instance_valid(victim):
			continue
		var hit: int = Hit.NONE
		var at: float = 2.0
		var center: Vector3 = Vector3.ZERO
		var head: Vector3 = head_center(victim)
		var t: float = FightPunchRules.sweep_sphere(from, fist, head,
				FightPunchRules.HEAD_RADIUS_M + FightPunchRules.FIST_RADIUS_M)
		if t >= 0.0 and t < at:
			hit = Hit.HEAD
			at = t
			center = head
		var chest: Vector3 = chest_center(victim)
		t = FightPunchRules.sweep_sphere(from, fist, chest,
				FightPunchRules.BODY_RADIUS_M + FightPunchRules.FIST_RADIUS_M)
		if t >= 0.0 and t < at:
			hit = Hit.BODY
			at = t
			center = chest
		for top: bool in [true, false]:
			var shoulder: Vector3 = victim.upper_body_to_global(
					victim.shoulder.position if top else victim.bottom_shoulder.position)
			var arm_fist: Vector3 = victim.upper_body_to_global(
					victim.get_top_hand_position() if top else victim.get_blade_position())
			t = FightPunchRules.sweep_capsule(from, fist, shoulder, arm_fist,
					FightPunchRules.ARM_RADIUS_M + FightPunchRules.FIST_RADIUS_M)
			if t >= 0.0 and t < at:
				hit = Hit.BLOCKED
				at = t
				center = arm_fist
		if hit == Hit.NONE:
			continue
		var toward: Vector3 = center - from
		toward = toward.normalized() if toward.length_squared() > 1e-8 else (fist - from).normalized()
		var speed: float = FightPunchRules.closing_speed((fist - from) / delta, victim.velocity, toward)
		if not FightPunchRules.lands(speed):
			continue
		_cool_until[attacker] = now + FightPunchRules.HIT_COOLDOWN_S
		punch_landed.emit(attacker, victim, hit, speed, toward)


# The fist a fighter punches with, world: the top arm's on TopHand, the bottom
# arm's on the Blade marker (SkaterFightHands).
static func punching_fist(s: Skater) -> Vector3:
	return s.upper_body_to_global(s.get_top_hand_position()
			if s.fight_punch_side == FightHoldRules.Side.TOP else s.get_blade_position())


static func head_center(s: Skater) -> Vector3:
	return SkaterFightHands.chin_world(s) + Vector3.UP * FightPunchRules.HEAD_ABOVE_CHIN_M


static func chest_center(s: Skater) -> Vector3:
	var mid: Vector3 = (s.shoulder.position + s.bottom_shoulder.position) * 0.5
	return s.upper_body_to_global(mid) + Vector3.DOWN * FightPunchRules.BODY_BELOW_SHOULDERS_M

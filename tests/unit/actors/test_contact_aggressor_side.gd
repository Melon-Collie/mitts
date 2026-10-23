extends GutTest

# Which body a skater contact lands on (Skater._resolve_player_collisions). The
# pair resolves once, from the body moving toward the other more, but who is
# faster no longer decides who is hit: the transfer is the contact's
# (SkaterCollisionRules.contact_transfer, a committed checker delivering it
# whichever way the bodies are moving), both bodies take their own Δv
# (body_check_received), and the strip and the credit are the committed
# checker's (body_checked_player names the carrier as his victim).
#
# So a set defender standing up a carrier skating into him lands the same hit
# as one stepping into a slower carrier at the same closing speed, and leans
# into his own share of it (BodyBalanceRules.leaned_into).
#
# Real Skater scenes at equal mass, resolved by hand. The carrier skates +x,
# the defender meets him from +x facing back down the ice at him.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const CLOSING_M_S: float = 8.0

var _carrier: Skater = null
var _defender: Skater = null
var _cfg: BodyCheckRules.Config = BodyCheckRules.Config.new()
# Per body: the impulses body_check_received delivered to it.
var _received: Dictionary = {}
# [checker, victim] for every body_checked_player — whom the strip is asked about.
var _checks: Array[Array] = []


func before_each() -> void:
	_carrier = _spawn()
	_defender = _spawn()
	var both: Array = [_carrier, _defender]
	for s: Skater in both:
		s.set_skater_collision_provider(func() -> Array: return both)
		s.is_host_machine = true
		var bucket: Array[Vector3] = []
		_received[s] = bucket
		s.body_check_received.connect(func(i: Vector3, _strength: float) -> void:
			bucket.append(i))
		s.body_checked_player.connect(func(v: Skater, _f: float, _d: Vector3) -> void:
			_checks.append([s, v]))
	_carrier.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	_defender.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_defender.hit_committed = true
	_defender.set_facing(Vector2(-1.0, 0.0))
	_carrier.set_facing(Vector2(1.0, 0.0))
	_checks.clear()


func _spawn() -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.set_physics_process(false)
	s.set_process(false)
	return s


# The pair overlapping, closing at CLOSING_M_S with the carrier at
# `carrier_speed` (+x) and the defender making up the rest toward him (−x).
# Both resolve, as a tick runs them; the aggressor gate lets exactly one through.
func _contact(carrier_speed: float) -> void:
	var y: float = GameRules.FACEOFF_SPAWN_HEIGHT
	_carrier.global_position = Vector3(0.0, y, 0.0)
	_defender.global_position = Vector3(0.6, y, 0.0)
	_carrier.velocity = Vector3(carrier_speed, 0.0, 0.0)
	_defender.velocity = Vector3(carrier_speed - CLOSING_M_S, 0.0, 0.0)
	_carrier._resolve_player_collisions()
	_defender._resolve_player_collisions()


func _largest(s: Skater) -> Vector3:
	var best := Vector3.ZERO
	for i: Vector3 in _received[s]:
		if i.length() > best.length():
			best = i
	return best


func _checked_by_defender() -> bool:
	for pair: Array in _checks:
		if pair[0] == _defender and pair[1] == _carrier:
			return true
	return false


func _carrier_keeps_the_puck() -> bool:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.set_process(false)
	puck._is_server = true
	puck.set_carrier(_carrier)
	if _checked_by_defender():
		puck.on_body_check(_defender, _carrier, _defender.weight * CLOSING_M_S,
				Vector3(-1.0, 0.0, 0.0))
	return puck.carrier == _carrier


# What the defender's own share reads as, leaning into it.
func _defender_feels() -> float:
	var dv: Vector3 = _largest(_defender)
	return BodyBalanceRules.leaned_into(Vector2(dv.x, dv.z), _defender.get_facing(),
			BodyBalanceRules.Config.new()).length()


func test_stepping_into_a_slower_carrier_strips_him() -> void:
	_contact(1.0)
	assert_gt(_largest(_carrier).length(), _cfg.ref_impulse, "a full check")
	assert_true(_checked_by_defender())
	assert_false(_carrier_keeps_the_puck(), "stripped")


# The stand-up: the defender set on his spot, the carrier skating into him.
func test_standing_up_a_faster_carrier_rocks_and_strips_him() -> void:
	_contact(CLOSING_M_S)
	assert_gt(_largest(_carrier).length(), _cfg.ref_impulse, "a full check: rocked")
	assert_true(_checked_by_defender(), "the strip and the credit are the defender's")
	assert_false(_carrier_keeps_the_puck())
	assert_lt(_carrier.velocity.x, CLOSING_M_S - _cfg.ref_impulse,
			"slowed by a full check, not skating on through")


func test_the_set_defender_leans_into_his_share() -> void:
	_contact(CLOSING_M_S)
	assert_gt(_largest(_defender).length(), _cfg.ref_impulse, "the same impulse lands on him")
	assert_lt(_defender_feels(), _cfg.ref_impulse, "leaning into it, he is staggered, not rocked")


func test_stepping_up_slower_than_the_carrier_lands_the_same_hit() -> void:
	_contact(5.0)
	var slower_than_him: float = _largest(_carrier).length()
	before_each()
	_contact(1.0)
	assert_almost_eq(slower_than_him, _largest(_carrier).length(), 1e-4,
			"the closing speed decides it, not who is faster")

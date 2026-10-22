extends GutTest

# Which body a skater contact lands on (Skater._resolve_player_collisions). The
# pair resolves once, from the body moving toward the other more, and only its
# partner takes the outcome: the stagger and knockdown (body_check_received) and
# the strip (body_checked_player names him as the victim). A carrier delivers
# only the passive bump, and a committed defender on the other side of the
# contact counts only as braced.
#
# So the same 8 m/s closing between a committed defender and a carrier lands two
# different hits depending on who is faster along the line: stepping into a
# slower carrier knocks him down and strips him, while standing up a faster one
# barely touches him. docs/hit-outcomes-plan.md Phase 3 changes this; these
# assertions change with it.
#
# Real Skater scenes at equal mass, resolved by hand. The carrier skates +x,
# the defender meets him from +x.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const CLOSING_M_S: float = 8.0

var _carrier: Skater = null
var _defender: Skater = null
var _cfg: BodyCheckRules.Config = BodyCheckRules.Config.new()
# Per body: the impulses body_check_received delivered to it.
var _received: Dictionary = {}
# The victims body_checked_player named — whom the strip is evaluated on.
var _strip_victims: Array[Skater] = []


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
			_strip_victims.append(v))
	_carrier.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	_defender.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_defender.hit_committed = true
	_strip_victims.clear()


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


func _largest(s: Skater) -> float:
	var best: float = 0.0
	for i: Vector3 in _received[s]:
		best = maxf(best, i.length())
	return best


func _carrier_keeps_the_puck() -> bool:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.set_process(false)
	puck._is_server = true
	puck.set_carrier(_carrier)
	if _strip_victims.has(_carrier):
		puck.on_body_check(_defender, _carrier, _defender.weight * CLOSING_M_S,
				Vector3(-1.0, 0.0, 0.0))
	return puck.carrier == _carrier


# The control: the defender is the faster body, so he resolves the contact and
# delivers his full committed transfer.
func test_stepping_into_a_slower_carrier_strips_him() -> void:
	_contact(1.0)
	assert_gt(_largest(_carrier), _cfg.ref_impulse, "a full check")
	assert_true(_strip_victims.has(_carrier))
	assert_false(_carrier_keeps_the_puck(), "stripped")
	assert_lt(_carrier.velocity.x, 1.0, "driven back")


# The stand-up: the defender set on his spot, the carrier skating into him. The
# carrier is the faster body, so he resolves the contact with the passive bump,
# and the defender's commit only braces him.
func test_standing_up_a_faster_carrier_barely_touches_him() -> void:
	_contact(CLOSING_M_S)
	assert_eq((_received[_carrier] as Array).size(), 0,
			"the carrier takes no stagger, no knockdown")
	assert_false(_strip_victims.has(_carrier), "the strip is never asked about him")
	assert_true(_carrier_keeps_the_puck())
	assert_lt(_largest(_defender), _cfg.min_impulse,
			"the hit is a bump below the stagger floor on either body")
	assert_gt(_carrier.velocity.x, 0.9 * CLOSING_M_S, "he skates on through")


# Stepping up does not help while the carrier is still the faster body: the
# same closing speed, the same bump.
func test_stepping_up_slower_than_the_carrier_lands_the_same_bump() -> void:
	_contact(5.0)
	assert_eq((_received[_carrier] as Array).size(), 0)
	assert_false(_strip_victims.has(_carrier))
	assert_lt(_largest(_defender), _cfg.min_impulse)

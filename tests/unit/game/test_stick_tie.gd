extends GutTest

# The stick tie on the host (StickTieTracker) and what it does to the tied stick
# (PuckController's loose-puck loop): a TIE-phase blade on an opponent's shaft
# latches, holds through the hold radius, breaks on separation or release and
# waits out its cooldown — and a tied receiver bobbles a pass he would have caught.
# Real Skater and Puck scenes, never ticked by a controller; phases and positions
# are set by hand, as in test_stick_lift.gd.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const Phase = StickCheckRules.Phase

var _registry: PlayerRegistry = null
var _puck: Puck = null
var _ties: StickTieTracker = null
var _defender: Skater = null
var _receiver: Skater = null
var _now: float = 100.0


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_defender = _spawn_skater(Vector3(0.6, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0))
	_receiver = _spawn_skater(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0))
	_registry = PlayerRegistry.new()
	_registry._skaters_cache = [_defender, _receiver] as Array[Skater]
	_registry.team_id_by_skater = {_defender: 1, _receiver: 0}
	_ties = StickTieTracker.new()
	_ties.setup(_registry, func() -> Skater: return _puck.carrier, func() -> float: return _now)


func _spawn_skater(pos: Vector3) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.global_position = pos
	s.set_physics_process(false)
	s.set_process(false)
	return s


# Puts the defender's blade `off` metres from the midpoint of the receiver's
# hand→blade shaft, square to it, so `off` is the distance the tracker measures.
func _blade_beside_the_shaft(off: float) -> void:
	var hand: Vector3 = _receiver.upper_body_to_global(_receiver.get_top_hand_position())
	var blade: Vector3 = _receiver.get_blade_contact_global()
	var side: Vector3 = (blade - hand).cross(Vector3.UP).normalized()
	var target: Vector3 = hand.lerp(blade, 0.5) + side * off
	var offset: Vector3 = _defender.get_blade_contact_global() - _defender.global_position
	_defender.global_position = target - offset


func test_a_tie_latches_on_a_shaft_in_reach() -> void:
	_defender.stick_check_phase = Phase.TIE
	_blade_beside_the_shaft(0.2)
	_ties.tick(true)
	assert_true(_receiver.stick_tied)
	assert_eq(_ties.victim_of(_defender), _receiver)


func test_only_the_tie_phase_ties() -> void:
	for phase: int in [Phase.IDLE, Phase.HOOK, Phase.DROP]:
		_defender.stick_check_phase = phase
		_blade_beside_the_shaft(0.2)
		_ties.tick(true)
		assert_false(_receiver.stick_tied, "phase %d" % phase)


func test_a_carrier_or_a_teammate_is_never_tied() -> void:
	_defender.stick_check_phase = Phase.TIE
	_blade_beside_the_shaft(0.2)
	_puck.set_carrier(_receiver)
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "a carrier's stick is lifted, not tied")
	_puck.clear_carrier()
	_registry.team_id_by_skater[_defender] = 0
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "a teammate's stick is left alone")


func test_a_tie_holds_wider_than_it_latches_then_breaks() -> void:
	_defender.stick_check_phase = Phase.TIE
	_blade_beside_the_shaft(0.2)
	_ties.tick(true)
	var hold: float = StickCheckRules.tie_hold_radius(Constants.NETWORK_INTERPOLATION_DELAY)
	_blade_beside_the_shaft((StickCheckRules.TIE_ENGAGE_RADIUS_M + hold) * 0.5)
	_ties.tick(true)
	assert_true(_receiver.stick_tied, "past the latch reach but inside the hold, it holds")
	_blade_beside_the_shaft(hold + 0.2)
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "pulled clear of the hold radius, it breaks")


func test_letting_go_breaks_the_tie_and_the_pair_waits_out_its_cooldown() -> void:
	_defender.stick_check_phase = Phase.TIE
	_blade_beside_the_shaft(0.2)
	_ties.tick(true)
	_defender.stick_check_phase = Phase.DROP
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "out of the tie phase, the tie is gone")
	_defender.stick_check_phase = Phase.TIE
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "the same pair cannot re-tie straight away")
	_now += StickCheckRules.TIE_COOLDOWN_S + 0.01
	_ties.tick(true)
	assert_true(_receiver.stick_tied, "after the cooldown it can")


func test_a_stoppage_unties_everyone() -> void:
	_defender.stick_check_phase = Phase.TIE
	_blade_beside_the_shaft(0.2)
	_ties.tick(true)
	_ties.tick(false)
	assert_false(_receiver.stick_tied)


# The receiver's blade hangs unposed above the ice in this rig, so the receiver
# is lowered until it sits at puck height — a grounded puck on a grounded blade.
func _pass_into_the_receivers_blade(speed: float) -> PuckController:
	var drop: float = _receiver.get_blade_contact_global().y - _puck.ice_height
	_receiver.global_position.y -= drop
	var pc := PuckController.new()
	add_child_autofree(pc)
	pc.set_physics_process(false)
	pc.set_process(false)
	pc.setup(_puck, true)
	pc.set_team_id_by_skater({_defender: 1, _receiver: 0})
	pc.set_skater_getter(func() -> Array: return [_receiver])
	pc.set_peer_id_resolver(func(_s: Skater) -> int: return 2)
	var blade: Vector3 = _receiver.get_blade_contact_global()
	var face: Vector3 = _receiver.get_blade_face_normal(Vector3(0.0, 0.0, -speed))
	_puck.global_position = blade
	_puck.linear_velocity = -face * speed
	pc._prev_puck_pos = blade + face * 0.2
	return pc


func test_an_untied_receiver_catches_the_pass() -> void:
	var pc: PuckController = _pass_into_the_receivers_blade(6.0)
	pc._check_interactions()
	assert_eq(_puck.carrier, _receiver, "the control: this pass is caught")


func test_a_tied_receiver_bobbles_the_same_pass() -> void:
	_receiver.stick_tied = true
	var pc: PuckController = _pass_into_the_receivers_blade(6.0)
	pc._check_interactions()
	assert_null(_puck.carrier, "a tied blade catches nothing")
	assert_lt(_puck.linear_velocity.length(), 6.0 * StickCheckRules.TIE_BOBBLE_RETAIN + 0.01,
			"the puck dies off the tied blade")
	assert_eq(_puck.linear_velocity.y, 0.0, "laid flat")

extends GutTest

# The stick tie on the host (StickTieTracker) and what it does to the tied sticks
# (PuckController's loose-puck loop): a TIE-phase stick touching an opponent's
# latches and ties BOTH; it holds while either holds the button and the sticks
# stay within the separation, and a break puts both on the shared cooldown — and a
# tied stick, held off the ice, lets a grounded pass under and bobbles an airborne
# one. Real Skater and Puck scenes, never ticked by a controller; phases, held
# flags and positions are set by hand, as in test_stick_lift.gd.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const Phase = StickCheckRules.Phase

var _registry: PlayerRegistry = null
var _puck: Puck = null
var _ties: StickTieTracker = null
var _defender: Skater = null
var _receiver: Skater = null


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
	_ties.setup(_registry, func() -> Skater: return _puck.carrier)


func _spawn_skater(pos: Vector3) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.global_position = pos
	s.set_physics_process(false)
	s.set_process(false)
	return s


func _gap() -> float:
	return StickCheckRules.stick_gap(
			_defender.upper_body_to_global(_defender.get_top_hand_position()),
			_defender.get_blade_contact_global(),
			_receiver.upper_body_to_global(_receiver.get_top_hand_position()),
			_receiver.get_blade_contact_global())


# Moves the defender so his stick sits `gap` metres (plan view) from the
# receiver's, his blade off the middle of the receiver's stick on the side his
# own hand is on. A few corrective passes land the measured gap on the target.
func _sticks_apart(gap: float) -> void:
	var hand: Vector3 = _receiver.upper_body_to_global(_receiver.get_top_hand_position())
	var blade: Vector3 = _receiver.get_blade_contact_global()
	var side: Vector3 = (blade - hand).cross(Vector3.UP)
	side.y = 0.0
	side = side.normalized()
	var mid: Vector3 = hand.lerp(blade, 0.5)
	var offset: Vector3 = _defender.get_blade_contact_global() - _defender.global_position
	var d_hand_off: Vector3 = _defender.upper_body_to_global(_defender.get_top_hand_position()) \
			- _defender.get_blade_contact_global()
	if d_hand_off.dot(side) < 0.0:
		side = -side
	var off: float = gap
	for _i: int in 6:
		_defender.global_position = mid + side * off - offset
		off += gap - _gap()
	assert_almost_eq(_gap(), gap, 0.01, "the rig placed the sticks %.2f m apart" % gap)


func _latch() -> void:
	_defender.stick_check_phase = Phase.TIE
	_defender.stick_check_held = true
	_sticks_apart(StickCheckRules.TIE_CONTACT_M * 0.5)
	_ties.tick(true)


func test_sticks_touching_tie_both_players() -> void:
	_latch()
	assert_true(_defender.stick_tied, "the initiator's stick is tied too")
	assert_true(_receiver.stick_tied)
	assert_eq(_ties.partner_of(_defender), _receiver)
	assert_eq(_ties.partner_of(_receiver), _defender)


func test_sticks_apart_do_not_tie() -> void:
	_defender.stick_check_phase = Phase.TIE
	_sticks_apart(StickCheckRules.TIE_CONTACT_M + 0.05)
	_ties.tick(true)
	assert_false(_receiver.stick_tied)


func test_only_the_tie_phase_ties() -> void:
	for phase: int in [Phase.IDLE, Phase.HOOK, Phase.DROP]:
		_defender.stick_check_phase = phase
		_sticks_apart(StickCheckRules.TIE_CONTACT_M * 0.5)
		_ties.tick(true)
		assert_false(_receiver.stick_tied, "phase %d" % phase)


func test_a_carrier_or_a_teammate_is_never_tied() -> void:
	_defender.stick_check_phase = Phase.TIE
	_sticks_apart(StickCheckRules.TIE_CONTACT_M * 0.5)
	_puck.set_carrier(_receiver)
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "a carrier's stick is lifted, not tied")
	_puck.clear_carrier()
	_registry.team_id_by_skater[_defender] = 0
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "a teammate's stick is left alone")


func test_a_skater_on_the_shared_cooldown_ties_nothing() -> void:
	_defender.start_stick_check_cooldown()
	_latch()
	assert_false(_receiver.stick_tied, "a landed lift or a broken tie is still cooling")
	assert_false(_ties.try_engage(_defender, _receiver), "the claim path refuses it too")


func test_either_players_hold_keeps_the_tie() -> void:
	_latch()
	_sticks_apart((StickCheckRules.TIE_CONTACT_M + StickCheckRules.TIE_SEPARATION_M) * 0.5)
	_ties.tick(true)
	assert_true(_receiver.stick_tied, "pulled apart but inside the separation, it holds")
	_defender.stick_check_held = false
	_receiver.stick_check_held = true
	_ties.tick(true)
	assert_true(_receiver.stick_tied, "the victim holding on keeps it")
	_receiver.stick_check_held = false
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "nobody holding, it lets go")
	assert_false(_defender.stick_tied)


func test_pulling_past_the_separation_breaks_it_even_held() -> void:
	_latch()
	_receiver.stick_check_held = true
	_sticks_apart(StickCheckRules.TIE_SEPARATION_M + 0.1)
	_ties.tick(true)
	assert_false(_receiver.stick_tied)
	assert_false(_defender.stick_tied)


func test_a_break_puts_both_on_the_shared_cooldown() -> void:
	_latch()
	_defender.stick_check_held = false
	_ties.tick(true)
	assert_true(_defender.is_stick_check_cooling())
	assert_true(_receiver.is_stick_check_cooling())
	_defender.stick_check_held = true
	_sticks_apart(0.0)
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "the same pair cannot re-tie straight away")


func test_nobody_in_a_board_pin_ties_or_is_tied() -> void:
	_defender.pin_role = BoardPinRules.Role.PINNER
	_latch()
	assert_false(_receiver.stick_tied, "a pinner's stick is on the pin")
	_defender.pin_role = BoardPinRules.Role.NONE
	_receiver.pin_role = BoardPinRules.Role.PINNED
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "a pinned man's stick is held")


func test_a_cross_check_breaks_the_shovers_tie() -> void:
	_latch()
	_defender.cross_check_phase = CrossCheckRules.Phase.THROW
	_ties.tick(true)
	assert_false(_receiver.stick_tied, "both hands went to the shaft")
	assert_true(_receiver.is_stick_check_cooling())


func test_a_pin_breaks_a_tie() -> void:
	_latch()
	_receiver.pin_role = BoardPinRules.Role.PINNED
	_ties.tick(true)
	assert_false(_defender.stick_tied)
	assert_false(_receiver.stick_tied)


func test_a_knockdown_breaks_it() -> void:
	_latch()
	_receiver.is_knocked_down = true
	_ties.tick(true)
	assert_false(_defender.stick_tied)


func test_a_stoppage_unties_everyone() -> void:
	_latch()
	_ties.tick(false)
	assert_false(_receiver.stick_tied)
	assert_false(_defender.stick_tied)


# The goal replay stamps its recorded frames onto the live actors, so it can end
# on a tie the tracker has already broken (or never held).
func test_a_stoppage_unties_a_tie_the_tracker_does_not_hold() -> void:
	_defender.stick_tied = true
	_receiver.stick_tied = true
	_ties.tick(false)
	assert_false(_receiver.stick_tied)
	assert_false(_defender.stick_tied)


# Sustained escape is a contest at equal speed: the separation covers the gap a
# pull opens while the other player's answer is in flight both ways.
func test_the_separation_covers_the_network_lag() -> void:
	assert_gte(StickCheckRules.TIE_SEPARATION_M, StickCheckRules.TIE_CONTACT_M
			+ 2.0 * StickCheckRules.TIE_BLADE_SPEED_M_S * StickCheckRules.TIE_LAG_BUDGET_S)
	assert_lt(StickCheckRules.TIE_BLADE_SPEED_M_S, 10.0, "tied sticks are slower than free ones")


# The receiver's blade hangs unposed above the ice in this rig, so the receiver
# is lowered until it sits at the puck's height `above_ice` metres up.
func _pass_into_the_receivers_blade(speed: float, above_ice: float) -> PuckController:
	var drop: float = _receiver.get_blade_contact_global().y - (_puck.ice_height + above_ice)
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
	var pc: PuckController = _pass_into_the_receivers_blade(6.0, 0.0)
	pc._check_interactions()
	assert_eq(_puck.carrier, _receiver, "the control: this pass is caught")


func test_a_grounded_pass_slides_under_a_tied_stick() -> void:
	_receiver.stick_tied = true
	var pc: PuckController = _pass_into_the_receivers_blade(6.0, 0.0)
	var v: Vector3 = _puck.linear_velocity
	pc._check_interactions()
	assert_null(_puck.carrier, "a tied stick is off the ice")
	assert_eq(_puck.linear_velocity, v, "the puck goes on untouched")


func test_an_airborne_pass_dies_off_a_tied_stick() -> void:
	_receiver.stick_tied = true
	var pc: PuckController = _pass_into_the_receivers_blade(
			6.0, GameRules.PUCK_AIRBORNE_HEIGHT_M + 0.1)
	pc._check_interactions()
	assert_null(_puck.carrier, "a tied blade catches nothing")
	assert_lt(_puck.linear_velocity.length(), 6.0 * StickCheckRules.TIE_BOBBLE_RETAIN + 0.01,
			"the puck dies off the tied blade")
	assert_eq(_puck.linear_velocity.y, 0.0, "laid flat")

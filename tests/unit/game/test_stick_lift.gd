extends GutTest

# The stick lift on the host's present-time path (PuckController
# ._check_interactions): only a hooking blade lifts, a stick mid-lift pokes
# nothing, and a landed lift is graded — a clean hook holds the carrier's stick
# up longer — and leaves the lifter free to take the puck while the carrier
# cannot. Same rig as test_block_withdraws_blade.gd: real Skater and Puck
# scenes, never ticked by a controller, with the PuckController driven by hand.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const State = SkaterStateMachine.State
const Phase = StickCheckRules.Phase

var _pc: PuckController = null
var _puck: Puck = null
var _carrier: Skater = null
var _checker: Skater = null


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_carrier = _spawn_skater(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0))
	_checker = _spawn_skater(Vector3(0.6, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0))
	_checker.current_shot_state = State.SKATING_WITHOUT_PUCK
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_pc.set_team_id_by_skater({_carrier: 0, _checker: 1})
	_pc.set_skater_getter(func() -> Array: return [_carrier, _checker])
	_pc.set_peer_id_resolver(func(s: Skater) -> int: return 1 if s == _checker else 2)
	_puck.set_carrier(_carrier)


func _spawn_skater(pos: Vector3) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.global_position = pos
	s.set_physics_process(false)
	s.set_process(false)
	return s


# Puts the checker's blade `below` metres under the midpoint of the carrier's
# hand→blade shaft, and the puck on the carrier's blade.
func _blade_under_the_shaft(below: float) -> void:
	var hand: Vector3 = _carrier.upper_body_to_global(_carrier.get_top_hand_position())
	var target: Vector3 = hand.lerp(_carrier.get_blade_contact_global(), 0.5) \
			- Vector3(0.0, below, 0.0)
	var offset: Vector3 = _checker.get_blade_contact_global() - _checker.global_position
	_checker.global_position = target - offset
	_puck.global_position = _carrier.get_blade_contact_global()
	_pc._prev_puck_pos = _puck.global_position


func _blade_on_the_puck() -> void:
	_puck.global_position = _checker.get_blade_contact_global()
	_pc._prev_puck_pos = _puck.global_position


func test_a_raised_blade_that_is_not_hooking_lifts_nothing() -> void:
	# A deflect raised at an air loft — and a stick an opponent just forced up —
	# both read blade_up. Neither is a lift any more.
	_checker.blade_up = true
	_blade_under_the_shaft(0.1)
	_pc._check_interactions()
	assert_eq(_puck.carrier, _carrier, "only the stick-check hook lifts a stick")


func test_a_forced_up_stick_cannot_lift_back() -> void:
	_checker.force_blade_lift(0.5)
	_checker.blade_up = true
	_blade_under_the_shaft(0.1)
	_pc._check_interactions()
	assert_eq(_puck.carrier, _carrier, "a lifted victim lifts nobody")


func test_a_stick_mid_lift_pokes_nothing() -> void:
	for phase: int in [Phase.RISE, Phase.TIE]:
		_checker.stick_check_phase = phase
		_blade_on_the_puck()
		_pc._check_interactions()
		assert_eq(_puck.carrier, _carrier, "phase %d keeps the stick off the puck" % phase)


func test_the_drop_pokes_like_any_grounded_blade() -> void:
	_checker.stick_check_phase = Phase.DROP
	_blade_on_the_puck()
	_pc._check_interactions()
	assert_null(_puck.carrier, "the dropping blade is back on the puck")


func test_a_landed_lift_leaves_the_puck_to_the_lifter() -> void:
	_checker.stick_check_phase = Phase.HOOK
	_blade_under_the_shaft(0.1)
	_pc._check_interactions()
	assert_null(_puck.carrier, "the hook strips the carrier")
	assert_true(_carrier.is_forced_lift_active(), "the carrier's stick is up")
	var now: float = _puck._now()
	assert_true(_puck.is_on_cooldown_at(_carrier, now), "the carrier cannot re-grab")
	assert_false(_puck.is_on_cooldown_at(_checker, now),
			"the lifter carries no cooldown: their blade dropping onto it is the take")
	assert_true(_puck.is_on_cooldown_at(_carrier,
			now + StickCheckRules.FORCED_LIFT_MIN_S),
			"the carrier's lockout outlasts even the shortest forced lift")


func test_a_cleaner_hook_holds_the_stick_up_longer() -> void:
	_checker.stick_check_phase = Phase.HOOK
	_blade_under_the_shaft(0.02)
	_pc._check_interactions()
	var clean: float = _carrier._forced_lift_timer
	_carrier._forced_lift_timer = 0.0
	_checker._stick_check_cooldown = 0.0
	_puck.set_carrier(_carrier)
	_puck.remove_skater_cooldown(_carrier)
	_blade_under_the_shaft(0.4)
	_pc._check_interactions()
	assert_null(_puck.carrier, "a hook at the rim still lands")
	assert_gt(clean, _carrier._forced_lift_timer, "a hook square under the shaft earns more")


func test_a_landed_lift_puts_the_lifter_on_the_shared_cooldown() -> void:
	_checker.stick_check_phase = Phase.HOOK
	_blade_under_the_shaft(0.1)
	_pc._check_interactions()
	assert_true(_checker.is_stick_check_cooling(),
			"a lift held on into TIE can't tie the stick it just lifted")


func test_a_cooling_hook_lifts_nothing() -> void:
	_checker.start_stick_check_cooldown()
	_checker.stick_check_phase = Phase.HOOK
	_blade_under_the_shaft(0.1)
	_pc._check_interactions()
	assert_eq(_puck.carrier, _carrier, "the host's own detection refuses it")
	_pc.apply_lag_comp_stick_lift(_checker, _carrier, 1.0)
	assert_eq(_puck.carrier, _carrier, "and so does a client's claim")

extends GutTest

# A slow puck that misses the stick and meets a skate, through the host's real
# present-time detection (PuckController._check_interactions): his own team's
# puck on open ice is kicked to his blade and costs the catch a settle; an
# opponent's puck, or his own with an opponent on him, bounces off the boot; a
# puck between the boots goes through.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const HOME: int = 0
const AWAY: int = 1

var _pc: PuckController = null
var _puck: Puck = null
var _receiver: Skater = null
var _opponent: Skater = null


func _skater(team: int, at: Vector3) -> Skater:
	var s := SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.global_position = at
	s.set_physics_process(false)
	s.set_process(false)
	s.set_team_id_resolver(func() -> int: return team)
	s.set_facing(Vector2(0.0, -1.0))
	s.capture_prev_blade_contact()
	return s


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_receiver = _skater(HOME, Vector3(0.0, 0.0, -8.0))
	_opponent = _skater(AWAY, Vector3(10.0, 0.0, -8.0))
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_pc.set_team_id_by_skater({_receiver: HOME, _opponent: AWAY})
	_pc.set_skater_getter(func() -> Array: return [_receiver, _opponent])
	_pc.set_peer_id_resolver(func(s: Skater) -> int: return 2 if s == _receiver else 3)


# Slides the puck at `speed` up the receiver's line from behind him, `across`
# metres to his right of centre, ending just short of his heels.
func _slide_into_feet(speed: float, across: float) -> void:
	var origin: Vector3 = _receiver.global_position
	_pc._prev_puck_pos = origin + Vector3(across, _puck.ice_height, 0.8)
	_puck.set_puck_position(origin + Vector3(across, _puck.ice_height, 0.12))
	_puck.set_puck_velocity(Vector3(0.0, 0.0, -speed))
	_pc._check_interactions()


func _right_boot() -> float:
	return SkateContactRules.half_spacing(false)


func test_his_teams_pass_into_his_skate_is_kicked_to_his_blade() -> void:
	_puck.last_touch_team = HOME
	_slide_into_feet(6.0, _right_boot())
	var v: Vector3 = _puck.get_puck_velocity()
	var blade: Vector3 = _receiver.get_blade_contact_global()
	var to_blade := Vector2(blade.x - _receiver.global_position.x - _right_boot(),
			blade.z - _receiver.global_position.z).normalized()
	assert_gt(Vector2(v.x, v.z).normalized().dot(to_blade), 0.95, "off the skate toward his blade")
	assert_lte(Vector2(v.x, v.z).length(), SkateContactRules.KICK_MAX_PUSH_M_S + 0.001,
			"a touch to the stick, not a pass")
	assert_null(_puck.carrier, "the blade still has to take it")


func test_the_catch_after_a_kick_settles() -> void:
	_puck.last_touch_team = HOME
	_slide_into_feet(6.0, _right_boot())
	watch_signals(_pc)
	_pc.apply_lag_comp_pickup(_receiver, 0.0)
	assert_signal_emitted(_pc, "puck_picked_up_by")
	var args: Array = get_signal_parameters(_pc, "puck_picked_up_by")
	assert_almost_eq(args[1] as float, SkateContactRules.KICK_SETTLE_S, 0.0001,
			"a soft catch off the skate still costs the gather")


func test_a_catch_with_no_kick_is_clean() -> void:
	watch_signals(_pc)
	_pc.apply_lag_comp_pickup(_receiver, 0.0)
	var args: Array = get_signal_parameters(_pc, "puck_picked_up_by")
	assert_eq(args[1] as float, 0.0)


func test_an_opponents_pass_bounces_off_his_skate() -> void:
	_puck.last_touch_team = AWAY
	_slide_into_feet(6.0, _right_boot())
	var v: Vector3 = _puck.get_puck_velocity()
	assert_gt(v.z, 0.0, "back off the heel the way it came")
	assert_lt(v.z, 6.0, "slower than it came")
	assert_eq(_puck.last_touch_team, HOME, "his skate touched it last")


func test_an_opponent_on_him_takes_the_kick_away() -> void:
	_opponent.global_position = _receiver.global_position + Vector3(1.0, 0.0, 0.5)
	_puck.last_touch_team = HOME
	_slide_into_feet(6.0, _right_boot())
	assert_gt(_puck.get_puck_velocity().z, 0.0, "crowded, the boot just bounces it")


func test_a_teammate_beside_him_is_no_pressure() -> void:
	_opponent.set_team_id_resolver(func() -> int: return HOME)
	_opponent.global_position = _receiver.global_position + Vector3(1.0, 0.0, 0.5)
	_puck.last_touch_team = HOME
	_slide_into_feet(6.0, _right_boot())
	assert_lt(_puck.get_puck_velocity().z, 0.0, "kicked on toward the blade")


func test_a_pass_too_hard_for_a_boot_bounces() -> void:
	_puck.last_touch_team = HOME
	_slide_into_feet(SkateContactRules.KICK_MAX_SPEED_M_S + 2.0, _right_boot())
	assert_gt(_puck.get_puck_velocity().z, 0.0)


func test_a_puck_between_his_skates_goes_through() -> void:
	_puck.last_touch_team = AWAY
	_slide_into_feet(6.0, 0.0)
	assert_eq(_puck.get_puck_velocity(), Vector3(0.0, 0.0, -6.0), "the nutmeg gap")


func test_the_skate_touch_is_a_contact_event() -> void:
	_puck.last_touch_team = HOME
	watch_signals(_puck)
	_slide_into_feet(6.0, _right_boot())
	_puck.drain_contact_events()
	assert_signal_emitted_with_parameters(_puck, "puck_skate_touched", [_receiver])


func test_a_reset_puck_is_nobodys() -> void:
	_puck.last_touch_team = HOME
	_puck.reset()
	assert_eq(_puck.last_touch_team, -1)


func test_a_pickup_makes_it_the_carriers_teams() -> void:
	_puck.set_carrier(_opponent)
	assert_eq(_puck.last_touch_team, AWAY)

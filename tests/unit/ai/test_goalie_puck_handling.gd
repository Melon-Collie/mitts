extends GutTest

# The goalie with the puck on his stick (GoaliePuckHandling): he gains it off a
# catch, a loose crease puck or a rim stop, holds it on his blade, and releases
# it the way a skater would — or loses it to a stick. Drives the real controller
# and the real host puck drive (goalie contact included).
#
# The goalie defends the -Z net, so his team is 1 and up ice is +Z.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const OUR_TEAM: int = 1
const THEIR_TEAM: int = 0
const SHOOTERS: Array[Vector3] = [
	Vector3(0.0, 0.0, GOAL_Z + 8.0),
	Vector3(4.0, 0.0, GOAL_Z + 5.0),
	Vector3(-4.0, 0.0, GOAL_Z + 5.0),
]
# Well out of anyone's way: no pressure, nobody to pass to.
const FAR_AWAY := Vector3(0.0, 0.0, 20.0)
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")

var _goalie: Node = null
var _puck: Node = null
var _opp: Skater = null
var _mate: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_opp = SKATER_SCENE.instantiate() as Skater
	_mate = SKATER_SCENE.instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_opp)
	add_child_autofree(_mate)
	add_child_autofree(_ctrl)
	_puck.set_physics_process(false)
	_mate.set_physics_process(false)
	_mate.set_process(false)
	_opp.set_team_id_resolver(func() -> int: return THEIR_TEAM)
	_mate.set_team_id_resolver(func() -> int: return OUR_TEAM)
	_ctrl.team_id = OUR_TEAM
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _opp)
	_ctrl.set_skater_getter(func() -> Array: return [_opp, _mate])
	_puck.set_server_mode(true)
	_puck.set_goalie_provider(func() -> Array: return [_goalie])
	_mate.global_position = FAR_AWAY
	_mate.velocity = Vector3.ZERO


func _tick() -> void:
	_ctrl._physics_process(DT)
	_puck._drive_analytic(DT)
	_puck.drain_contact_events()


func _handling() -> bool:
	return _ctrl._sm.current == GoalieStateMachine.State.HANDLING


# A glove catch from `shooter`, then the hold, ending on his stick. The shooter
# skates off out of the play so the catch is unpressured.
func _catch_to_stick(shooter: Vector3, down: bool) -> void:
	_h.settle_ready(shooter)
	if down:
		_ctrl._enter_butterfly()
		for _i: int in 40:
			_ctrl._physics_process(DT)
	_puck.clear_carrier()
	_puck.global_position = _goalie.get_glove_world_position()
	_puck.linear_velocity = Vector3.ZERO
	_opp.global_position = FAR_AWAY
	_opp.velocity = Vector3.ZERO
	_opp.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_ctrl._on_puck_caught(_goalie)
	for _i: int in 240:
		_tick()
		if _handling():
			return


# Ticks until he no longer has it, up to `seconds`. Returns the release velocity
# (ZERO if he still has it or it was taken).
func _until_released(seconds: float) -> Vector3:
	for _i: int in int(seconds / DT):
		_tick()
		if not _handling():
			return _puck.linear_velocity
	return Vector3.ZERO


# Runs the released puck on and reports whether it ever went into his net.
func _ever_scores(seconds: float) -> bool:
	for _i: int in int(seconds / DT):
		_tick()
		var p: Vector3 = _puck.global_position
		if p.z < GOAL_Z and absf(p.x) < GameRules.NET_HALF_WIDTH:
			return true
	return false


func test_a_catch_ends_on_his_stick() -> void:
	for down: bool in [false, true]:
		_catch_to_stick(SHOOTERS[0], down)
		assert_true(_handling(), "the hold ends with the puck on his stick (down %s)" % down)
		_tick()
		var spot: Vector3 = _ctrl._handled_carry_spot()
		assert_lt(_puck.global_position.distance_to(spot), 0.01,
				"the puck rides his blade's carry point")
		assert_true(_puck.motion_pinned, "the drive is parked while he holds it")
		assert_false(_puck.pickup_locked, "and it is live to every other stick")


func test_he_releases_it_and_never_into_his_own_net() -> void:
	for shooter: Vector3 in SHOOTERS:
		for down: bool in [false, true]:
			_catch_to_stick(shooter, down)
			var label: String = "%s from %s" % ["down" if down else "upright", shooter]
			var vel: Vector3 = _until_released(_ctrl.handling_max_hold_s + 0.5)
			gut.p("%s: released at %s" % [label, vel])
			assert_false(_handling(), "%s: he released it by his max hold" % label)
			assert_gt(vel.length(), 1.0, "%s: it left his stick at pace" % label)
			assert_false(_ever_scores(3.0), "%s: it went into his own net" % label)


func test_an_open_teammate_gets_the_pass() -> void:
	_mate.global_position = Vector3(-9.0, 0.0, GOAL_Z + 12.0)
	_catch_to_stick(SHOOTERS[0], false)
	var vel: Vector3 = _until_released(_ctrl.handling_max_hold_s + 0.5)
	var to_mate: Vector3 = _mate.global_position - _puck.global_position
	var angle: float = rad_to_deg(Vector2(vel.x, vel.z).angle_to(Vector2(to_mate.x, to_mate.z)))
	gut.p("release %s, %.1f deg off the mate" % [vel, angle])
	assert_lt(absf(angle), 15.0, "an uncontested outlet is a pass, not a clear")
	assert_lt(absf(vel.y), 0.01, "a pass goes along the ice")


func test_pressure_forces_the_release_before_the_read_beat() -> void:
	_catch_to_stick(SHOOTERS[0], false)
	var spot: Vector3 = _ctrl._handled_carry_spot()
	_opp.global_position = spot + Vector3(0.0, 0.0, 3.0)
	_opp.velocity = Vector3(0.0, 0.0, -8.0)
	var ticks: int = 0
	while _handling() and ticks < 240:
		_tick()
		ticks += 1
	gut.p("released after %.3f s under a forecheck" % (ticks * DT))
	assert_lt(ticks * DT, _ctrl.handling_read_beat_s,
			"a forechecker on top of him moves the puck now")


func test_with_nobody_to_pass_to_he_waits_then_clears() -> void:
	_catch_to_stick(SHOOTERS[0], false)
	var ticks: int = 0
	while _handling() and ticks < 600:
		_tick()
		ticks += 1
	var vel: Vector3 = _puck.linear_velocity
	gut.p("cleared after %.3f s at %s" % [ticks * DT, vel])
	assert_gt(ticks * DT, _ctrl.handling_max_hold_s - 0.1,
			"no pass worth making: he holds for one to open up")
	assert_gt(vel.z, 0.0, "then clears it up ice")


func test_a_forechecker_takes_it_clean() -> void:
	_catch_to_stick(SHOOTERS[0], false)
	_puck.set_carrier(_opp)
	_tick()
	assert_false(_handling(), "the puck is gone, so is the possession")
	assert_false(_puck.motion_pinned, "he lets go of the pin")
	assert_eq(_puck.get_carrier(), _opp, "the forechecker has it")


func test_a_stick_on_it_knocks_it_off_his() -> void:
	_catch_to_stick(SHOOTERS[0], false)
	_tick()
	_puck.set_puck_velocity(Vector3(3.0, 0.0, 1.0))
	_tick()
	assert_false(_handling(), "somebody else wrote the puck's velocity")
	assert_false(_puck.motion_pinned, "it is a loose puck again")


func test_a_crease_puck_is_his_only_when_his_blade_gets_there() -> void:
	_h.settle_ready(SHOOTERS[0])
	_puck.clear_carrier()
	_opp.global_position = FAR_AWAY
	_opp.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	var g: Vector3 = _goalie.global_position
	# Inside his reach window but a metre past where the stick can go: no force
	# field takes it any more.
	_puck.global_position = Vector3(g.x + 1.2, _puck.ice_height, g.z + 0.5)
	_puck.linear_velocity = Vector3.ZERO
	var start: Vector3 = _puck.global_position
	for _i: int in 120:
		_tick()
	assert_false(_handling(), "a puck the blade cannot reach is not his")
	assert_lt(_puck.global_position.distance_to(start), 0.05,
			"and nothing moves it from across the crease")
	# At the blade: his.
	_puck.global_position = _ctrl._handled_carry_spot() + Vector3(0.2, 0.0, 0.0)
	_puck.linear_velocity = Vector3.ZERO
	for _i: int in 30:
		_tick()
		if _handling():
			break
	assert_true(_handling(), "the blade on a slow loose puck gains it")


func test_after_a_rim_stop_he_plays_it_then_goes_home() -> void:
	_h.settle_ready(SHOOTERS[0])
	_puck.clear_carrier()
	_ctrl._puck_play.begin()
	_ctrl._sm.transition_to(GoalieStateMachine.State.PLAYING_PUCK)
	_ctrl._begin_handling(GoaliePuckHandling.Origin.RIM)
	_until_released(_ctrl.handling_max_hold_s + 0.5)
	assert_eq(_ctrl._sm.current, GoalieStateMachine.State.PLAYING_PUCK,
			"after the release he finishes the trip")
	assert_eq(_ctrl._puck_play.phase, GoaliePuckPlay.PHASE_RETURN, "home")

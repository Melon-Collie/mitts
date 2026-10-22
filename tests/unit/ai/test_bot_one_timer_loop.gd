extends GutTest

# A bot's one-timer, closed loop (docs/slapshot-realism-plan.md, Phase 6): the
# production decision stack drives a real Skater + SkaterController onto a
# scripted feed. Loaded, a skater only glides, shuffles and turns, so whether
# the circle is on the pass's line when it gets there is a question of the
# body, which a dispatch against a frozen snapshot cannot answer.
#
# The puck flies straight at constant pace and is caught the way the host
# catches it: by the slapper circle during a puckless wind-up, by the blade
# otherwise.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SlapState = SkaterStateMachine.State
const DT: float = 1.0 / 120.0
const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const FINISHER_ID := 1
const CARRIER_ID := 2
const OPP_MARK := 11
const OPP_PRESSURE := 12
const PASSER := Vector3(8.0, 0.0, -18.0)
const PASS_SPEED: float = 18.0
const DEBOUNCE_TICKS: int = 6
const CATCH_RADIUS_M: float = 0.5


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _team_map := {FINISHER_ID: 0, CARRIER_ID: 0, OPP_MARK: 1, OPP_PRESSURE: 1}
var _skater: Skater = null
var _puck: Puck = null
var _controller: SkaterController = null
var _agent: SkaterAgent = null
var _brain: TeamBrain = null
var _snap: WorldSnapshot = null
var _shots: Array[Vector3] = []
var _host_t: float = 0.0
# Where the puck left from: the pin once it is carried, the circle otherwise.
var _release_from := Vector3.ZERO


class Outcome:
	var pressed: bool = false
	var caught_in_circle: bool = false
	var fired: bool = false
	var shot := Vector3.ZERO
	# Where the shot crosses the goal line, metres off centre (INF: never).
	var at_goal_x: float = INF
	# Where the locked aim, before the contact, crosses it.
	var aimed_x: float = INF


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, _puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_shots.clear()
	_controller.puck_release_requested.connect(
			func(direction: Vector3, power: float, _slapper: bool) -> void:
				_shots.append(direction * power))
	_controller.one_timer_release_requested.connect(
			func(direction: Vector3, power: float) -> void:
				_shots.append(direction * power))
	_brain = TeamBrain.new(0, _team_map)
	_agent = SkaterAgent.new()
	_agent.setup(FINISHER_ID, 0, _brain, _team_map, _skater.is_left_handed)
	_agent.apply_capabilities(_controller.build_ai_caps())
	_snap = _cycle_snap()
	_host_t = 0.0


func _add_skater(pid: int, pos: Vector3) -> void:
	var st := SkaterNetworkState.new()
	st.position = pos
	st.facing = Vector2(0.0, -1.0)
	_snap.skater_states[pid] = st


# The settled OZONE cycle test_one_timer_chain.gd plays: the carrier on the
# right half-wall, the finisher weak-side, the mark drawn to the puck side.
func _cycle_snap() -> WorldSnapshot:
	_snap = WorldSnapshot.new()
	_add_skater(FINISHER_ID, Vector3.ZERO)
	_add_skater(CARRIER_ID, PASSER)
	_add_skater(OPP_MARK, Vector3(3.0, 0.0, -24.0))
	_add_skater(OPP_PRESSURE, Vector3(7.0, 0.0, -16.5))
	var g := GoalieNetworkState.new()
	g.position_x = 0.8
	g.position_z = -25.3
	g.rotation_y = atan2(0.8, -25.3)
	_snap.goalie_states[1] = g
	_snap.puck_state = PuckNetworkState.new()
	_snap.puck_state.position = PASSER
	_snap.puck_state.carrier_peer_id = CARRIER_ID
	_snap.real_puck_carrier_peer_id = CARRIER_ID
	return _snap


func _step() -> void:
	_controller.fill_network_state(_snap.skater_states[FINISHER_ID])
	_host_t += DT
	var input: InputState = _agent.tick(_snap, DT, _host_t)
	input.move_vector = AIBotMechanics.braked_stick(input.move_vector, input.brake,
			_skater.velocity, input.bot_shuffle)
	_controller._process_input(input, DT)
	_skater._physics_process(DT)


# The finisher stood at `spot`, facing `facing`, camped through the carrier's
# hold until his readiness publishes; then the feed leaves the passer for
# `target` and flies until something takes it.
func _feed(spot: Vector3, facing: Vector2, target: Vector3) -> Outcome:
	var out := Outcome.new()
	_controller.teleport_to(Vector3(spot.x, GameRules.FACEOFF_SPAWN_HEIGHT, spot.z), facing)
	_skater.velocity = Vector3.ZERO
	for i: int in 30:
		_brain.tick(DT, _snap)
		_step()
		_agent.push_one_timer_ready()
	var dir: Vector3 = (target - PASSER).normalized()
	var pos: Vector3 = PASSER
	var caught: bool = false
	for tick: int in 240:
		if not caught:
			pos += dir * PASS_SPEED * DT
			_snap.puck_state.position = pos
			_snap.puck_state.velocity = dir * PASS_SPEED
			_snap.real_puck_carrier_peer_id = -1
			_snap.puck_state.carrier_peer_id = CARRIER_ID if tick < DEBOUNCE_TICKS else -1
			_puck.global_position = pos
			_puck.linear_velocity = dir * PASS_SPEED
			caught = _try_catch(pos, dir * PASS_SPEED, out)
		else:
			_snap.puck_state.position = _skater.get_carry_target_global()
			_snap.puck_state.velocity = _skater.velocity
		if _brain != null and tick % 20 == 0:
			_brain.tick(DT * 20.0, _snap)
		_step()
		if _skater.current_shot_state == SlapState.SLAPPER_CHARGE_WITHOUT_PUCK:
			out.pressed = true
		_release_from = _skater.get_carry_target_global() if caught else pos
		if _skater.current_shot_state != SlapState.SKATING_WITHOUT_PUCK \
				and _skater.current_shot_state != SlapState.SKATING_WITH_PUCK:
			var d: Vector2 = _controller._sm.locked_slapper_dir
			var from: Vector3 = _skater.get_carry_target_global() if caught \
					else _skater.get_slapper_zone_global_position()
			if d.y < -0.01:
				out.aimed_x = from.x + d.x * (GOAL.z - from.z) / d.y
		if not _shots.is_empty():
			break
		if not caught and Vector3(pos.x - _skater.global_position.x, 0.0,
				pos.z - _skater.global_position.z).dot(dir) > 4.0:
			break
	if not _shots.is_empty():
		out.fired = true
		out.shot = _shots[0]
		var from: Vector3 = _release_from
		if out.shot.z < -0.01:
			out.at_goal_x = from.x + out.shot.x * (GOAL.z - from.z) / out.shot.z
	return out


# The host's catch: the circle during a puckless wind-up, the blade otherwise.
func _try_catch(pos: Vector3, vel: Vector3, out: Outcome) -> bool:
	var winding: bool = _skater.current_shot_state == SlapState.SLAPPER_CHARGE_WITHOUT_PUCK \
			or _skater.current_shot_state == SlapState.ONE_TIMER_RETENTION
	var at: Vector3 = _skater.get_slapper_zone_global_position() if winding \
			else _skater.get_blade_contact_global()
	var radius: float = _controller.slapper_zone_radius if winding else CATCH_RADIUS_M
	if Vector2(pos.x - at.x, pos.z - at.z).length() > radius:
		return false
	out.caught_in_circle = winding
	_puck.set_carrier(_skater)
	_snap.real_puck_carrier_peer_id = FINISHER_ID
	_snap.puck_state.carrier_peer_id = FINISHER_ID
	var rel := Vector2(vel.x - _skater.velocity.x, vel.z - _skater.velocity.z)
	_controller.on_puck_picked_up_network(0, rel)
	return true


# Where the finisher's own role puts him on this cycle.
func _argmax_spot() -> Vector3:
	var sm := SkaterAgentStateMachine.new()
	sm.setup(FINISHER_ID, 0, _brain, _team_map, false)
	var probe := Vector3(-4.0, 0.0, -21.65)
	_snap.skater_states[FINISHER_ID].position = probe
	_brain.tick(1.0, _snap)
	var ctx: RoleContext = sm._build_role_context(_snap, probe, _snap.skater_states[FINISHER_ID])
	return AIRoleFinisher.decide(ctx).target_position


func _describe(o: Outcome) -> String:
	return "pressed %s, circle %s, fired %s at %.2f m off centre, aimed %.2f (%.1f m/s)" % [
			o.pressed, o.caught_in_circle, o.fired, o.at_goal_x, o.aimed_x, o.shot.length()]


func _to_net(spot: Vector3) -> Vector2:
	return Vector2(GOAL.x - spot.x, GOAL.z - spot.z).normalized()


# Straight across the pass's line from `spot`, `off` metres.
func _beside(spot: Vector3, off: float) -> Vector3:
	var line: Vector3 = (spot - PASSER).normalized()
	return spot + Vector3(-line.z, 0.0, line.x) * off


func _one_timed(o: Outcome) -> bool:
	return o.pressed and o.caught_in_circle and o.fired


func _on_net(o: Outcome) -> bool:
	return absf(o.at_goal_x) < GameRules.NET_HALF_WIDTH - GameRules.PUCK_COLLISION_RADIUS


func test_a_feed_at_the_body_is_one_timed_on_net() -> void:
	var spot: Vector3 = _argmax_spot()
	var o: Outcome = _feed(spot, _to_net(spot), spot)
	assert_true(_one_timed(o), _describe(o))
	assert_true(_on_net(o), _describe(o))


# The face pulls a one-timer toward the feed's cross speed; the bot leads the
# swing against it, so the shot lands where the same bot puts it with the pull
# turned off. The cross-seam feed here pulls it most of a metre.
func test_the_swing_leads_the_pull_onto_the_hole() -> void:
	var spot: Vector3 = _argmax_spot()
	_controller.one_timer_feed_grip = 0.0
	_agent.apply_capabilities(_controller.build_ai_caps())
	var straight: Outcome = _feed(spot, _to_net(spot), spot)
	before_each()
	var pulled: Outcome = _feed(_argmax_spot(), _to_net(spot), spot)
	assert_true(_one_timed(straight) and _one_timed(pulled), _describe(pulled))
	assert_almost_eq(pulled.at_goal_x, straight.at_goal_x, 0.1,
			"lands on the hole (%s vs %s)" % [_describe(pulled), _describe(straight)])
	assert_gt(absf(pulled.aimed_x - pulled.at_goal_x), 0.3, "led against a real pull")


# Off the body's line, the circle still has to get there: the press waits for
# the glide and a shuffle to be able to put it on the line in time.
func test_a_feed_half_a_metre_off_is_stepped_onto() -> void:
	for off: float in [-0.5, 0.5]:
		before_each()
		var spot: Vector3 = _argmax_spot()
		var o: Outcome = _feed(spot, _to_net(spot), _beside(spot, off))
		assert_true(_one_timed(o), "%.1f m: %s" % [off, _describe(o)])
		assert_true(_on_net(o), "%.1f m: %s" % [off, _describe(o)])


# Wound up, the hips pivot at their own rate, so a body turned away from the
# shot still sets in a feed's flight — where a cone on the facing it pressed
# from would have sent it to a catch.
func test_a_body_turned_away_pivots_into_the_one_timer() -> void:
	var spot: Vector3 = _argmax_spot()
	var o: Outcome = _feed(spot, Vector2(0.0, 1.0), spot)
	assert_true(_one_timed(o), _describe(o))
	assert_true(_on_net(o), _describe(o))


# A feed whose line no glide or shuffle reaches in its flight is caught on the
# blade instead of swung at.
func test_a_feed_out_of_reach_of_the_circle_is_caught() -> void:
	var spot: Vector3 = _argmax_spot()
	var o: Outcome = _feed(spot, _to_net(spot), _beside(spot, 1.0))
	assert_false(o.pressed, _describe(o))
	assert_true(_controller.has_puck or o.fired, "caught: " + _describe(o))

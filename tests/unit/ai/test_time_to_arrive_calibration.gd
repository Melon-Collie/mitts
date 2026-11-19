extends GutTest

# Calibrates AIArrival.time_to_arrive — the universal ETA every race,
# election, lane, and chase read runs on — against ACTUAL arrival times under
# the real skating physics (SkaterMovementRules.apply_movement at the tick)
# driven by the bot's own steering (SkaterAgentSteering: the velocity-matched
# seek, the pivot brake or its stance cut, and the stance carve).
#
# The contract is two-sided: the estimator IS the arrival time, within
# tolerance, cell by cell — not an optimistic lower bound. If the movement
# tuning drifts (thrust, friction, drag, brake, turn authority, the stance's
# grip and scrape, top speed), cells here fail and the model's terms get
# re-measured — never silently absorbed.
#
# One place is a knife edge rather than a cell: a short cut at speed whose
# point the carve only just makes or only just flies past. A few tenths of a
# metre there decide whether the body arrives on its first pass or loops back
# for it, so that edge is held to a factor rather than the band.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# Pass-through tolerance: within one blade's contact of the target counts as
# arrived (ETAs feed contests and races, not parking precision).
const ARRIVE_RADIUS_M: float = 0.5
const TOL_FRAC: float = AIArrival.ERROR_FRAC
const TOL_FLOOR_S: float = AIArrival.ERROR_FLOOR_S
const PEER_ID: int = 1
# Every cell starts here and skates toward -z: open ice, clear of the boards'
# and the creases' repels for the longest cell and the widest loop.
const ORIGIN := Vector3(0.0, 0.0, 12.0)

var _cfg: SkaterMovementRules.MovementConfig
var _steering: SkaterAgentSteering
var _snapshot: WorldSnapshot
var _self_state: SkaterNetworkState
var _input: InputState


func before_each() -> void:
	var ctrl := SkaterController.new()
	_cfg = ctrl.get_movement_config()
	ctrl.free()
	_cfg.puck_carry_speed_multiplier = 1.0
	_steering = SkaterAgentSteering.new()
	_steering.setup(PEER_ID, 0, {PEER_ID: 0})
	_snapshot = WorldSnapshot.new()
	_snapshot.puck_state = PuckNetworkState.new()
	_self_state = SkaterNetworkState.new()
	_snapshot.skater_states[PEER_ID] = _self_state
	_input = InputState.new()


# Measured arrival under the real controller: the bot's steering to a station
# with the velocity match on (the carrier/station steering), its stick dropped
# under a brake as AIController drops it, facing aligned to the thrust (a bot's
# facing tracks its travel in open ice). A lone body on the ice for a clean read.
func _sim_arrival_s(v0: Vector3, target: Vector3) -> float:
	var pos: Vector3 = ORIGIN
	var vel: Vector3 = v0
	var t: float = 0.0
	var upright_lateral_accel: float = GameRules.DEFAULT_SKATER_TURN_ACCEL_M_S2 * _cfg.lateral_grip
	for _i: int in 1800:  # 20 s cap
		var to_t: Vector3 = target - pos
		to_t.y = 0.0
		if to_t.length() <= ARRIVE_RADIUS_M:
			return t
		_self_state.position = pos
		_self_state.velocity = vel
		_steering.steer(_input, _snapshot, pos, target, false,
				GameRules.DEFAULT_SKATER_MAX_SPEED_M_S, Vector3.ZERO, -1, Vector3.ZERO, 0.0,
				Vector3.ZERO, upright_lateral_accel, AIBotMechanics.BLADE_REACH_M)
		var mi: Vector2 = AIBotMechanics.braked_stick(_input.move_vector, _input.brake, vel)
		var facing_y: float = atan2(-mi.x, -mi.y) if mi.length() > 0.001 else 0.0
		vel = SkaterMovementRules.apply_movement(vel, mi, facing_y, false, _input.brake, DT, _cfg,
				SkaterMovementRules.posture_of(_input.stance_held, false))
		pos += vel * DT
		t += DT
	return INF


func _model_s(v0: Vector3, target: Vector3) -> float:
	return AIArrival.time_to_arrive(
			ORIGIN, target, v0,
			GameRules.DEFAULT_SKATER_MAX_SPEED_M_S,
			GameRules.DEFAULT_SKATER_THRUST_M_S2)


func _cell(speed: float, angle_deg: float, dist: float) -> Array:
	var ang: float = deg_to_rad(angle_deg)
	var v0 := Vector3(sin(ang), 0.0, -cos(ang)) * speed
	var target: Vector3 = ORIGIN + Vector3(0.0, 0.0, -dist)
	var real: float = _sim_arrival_s(v0, target)
	var model: float = _model_s(v0, target)
	gut.p("  v=%.1f  %3.0f°  d=%4.1f:  model %.2fs  real %.2fs" % [
			speed, angle_deg, dist, model, real])
	return [model, real]


func _check_cell(speed: float, angle_deg: float, dist: float) -> void:
	var pair: Array = _cell(speed, angle_deg, dist)
	var tol: float = maxf(pair[1] * TOL_FRAC, TOL_FLOOR_S)
	assert_almost_eq(pair[0], pair[1], tol,
			"v0=%.1f m/s at %.0f° over %.1f m: model %.2fs vs real %.2fs"
			% [speed, angle_deg, dist, pair[0], pair[1]])


func test_standing_starts() -> void:
	# The ramp: a standing start genuinely pays ~0.5 s over dist/top_speed.
	for dist: float in [2.0, 4.0, 8.0, 16.0, 25.0]:
		_check_cell(0.0, 0.0, dist)


func test_full_speed_head_on() -> void:
	# No double-credit: a full-speed closer arrives at dist/top_speed.
	for dist: float in [2.0, 4.0, 8.0, 16.0, 25.0]:
		_check_cell(9.0, 0.0, dist)


func test_half_speed_head_on() -> void:
	for dist: float in [4.0, 8.0, 16.0]:
		_check_cell(4.5, 0.0, dist)


func test_perpendicular_cuts() -> void:
	# The 90° family — the wing-curl read: carved round on the stance's edges,
	# the seek's skid tightening the turn as it bleeds the speed.
	for speed: float in [4.5, 9.0]:
		for dist: float in [4.0, 8.0, 16.0, 25.0]:
			_check_cell(speed, 90.0, dist)


func test_curl_back() -> void:
	# 135° — part reversal, part cut.
	for dist: float in [4.0, 8.0, 16.0]:
		_check_cell(9.0, 135.0, dist)
	_check_cell(4.5, 135.0, 4.0)


func test_full_reversal() -> void:
	# 180° — the pivot brake: brake out the retreat (giving back the ground
	# lost while braking), then a standing-start pursuit.
	for speed: float in [4.5, 9.0]:
		for dist: float in [4.0, 8.0, 16.0]:
			_check_cell(speed, 180.0, dist)


func test_long_diagonals() -> void:
	# 45° at range.
	_check_cell(4.5, 45.0, 4.0)
	_check_cell(4.5, 45.0, 8.0)
	_check_cell(4.5, 45.0, 16.0)
	_check_cell(9.0, 45.0, 16.0)
	_check_cell(9.0, 45.0, 25.0)


func test_short_fast_diagonal_cuts() -> void:
	# Short cuts at speed, both sides of the carve's reach: the cells the carve
	# makes on its first pass, and those whose point it flies past and loops
	# back for (9 m/s at 45° inside ~4 m, 10 m/s inside ~5 m).
	for cell: Array in [[9.0, 45.0, 3.0], [9.0, 45.0, 3.5], [9.0, 45.0, 6.0],
			[9.0, 45.0, 8.0], [9.0, 30.0, 4.5], [9.0, 30.0, 6.0], [9.0, 60.0, 3.0],
			[9.0, 60.0, 6.0], [7.5, 45.0, 4.0], [7.5, 60.0, 4.0], [6.0, 45.0, 3.0],
			[10.0, 45.0, 3.5], [10.0, 45.0, 6.0]]:
		_check_cell(cell[0], cell[1], cell[2])


func test_miss_loop_edge_stays_within_a_factor_of_two() -> void:
	# The knife edge between a cut the carve makes and one it loops back for
	# (see header): either side may be read as the other, by no more than the
	# loop costs over the catch.
	for cell: Array in [[9.0, 45.0, 4.0], [9.0, 45.0, 4.5]]:
		var pair: Array = _cell(cell[0], cell[1], cell[2])
		assert_between(pair[0], pair[1] * 0.5, pair[1] * 2.0,
				"v0=%.1f m/s at %.0f° over %.1f m: model %.2fs vs real %.2fs"
				% [cell[0], cell[1], cell[2], pair[0], pair[1]])


func test_a_point_the_carve_flies_past_costs_the_loop() -> void:
	# Not monotone in distance: at speed, a point inside the carve's curl is
	# reached later than one further out on the same bearing.
	var v0 := Vector3(sin(PI / 4.0), 0.0, -cos(PI / 4.0)) * 9.0
	var near: float = _model_s(v0, ORIGIN + Vector3(0.0, 0.0, -3.0))
	var far: float = _model_s(v0, ORIGIN + Vector3(0.0, 0.0, -8.0))
	assert_gt(near, far, "the point flown past is the slower one")


func test_momentum_direction_ordering() -> void:
	# Direction is priced correctly whatever the calibration details.
	var dest: Vector3 = ORIGIN + Vector3(0.0, 0.0, -8.0)
	var aligned: float = _model_s(Vector3(0, 0, -6), dest)
	var rest: float = _model_s(Vector3.ZERO, dest)
	var perp: float = _model_s(Vector3(6, 0, 0), dest)
	var away: float = _model_s(Vector3(0, 0, 6), dest)
	assert_lt(aligned, rest, "momentum toward the target beats rest")
	assert_lt(rest, away, "rest beats momentum pointed away")
	assert_lt(perp, away, "a cut beats a full reversal")


# ── Net-aware routing (breakout plan Phase D iteration 2) ────────────────────
# A route whose straight line crosses a cage prices the real detour; open ice
# is bit-identical to the direct model.

func test_open_ice_route_is_exactly_the_direct_model() -> void:
	var t_pub: float = AIArrival.time_to_arrive(
			Vector3(-5, 0, 3), Vector3(6, 0, -8), Vector3(2, 0, 1))
	var t_dir: float = AIArrival._time_to_arrive_direct(
			Vector3(-5, 0, 3), Vector3(6, 0, -8), Vector3(2, 0, 1))
	assert_eq(t_pub, t_dir, "open ice never pays the net gate")


func test_cross_cage_route_costs_more_than_the_straight_fiction() -> void:
	# Front of the net to behind it, straight through the cage: the honest
	# route rounds a post and must cost strictly more than the fiction.
	var from := Vector3(2.0, 0, GameRules.GOAL_LINE_Z - 2.15)
	var dest := Vector3(-1.5, 0, GameRules.GOAL_LINE_Z + 1.75)
	var t: float = AIArrival.time_to_arrive(from, dest, Vector3.ZERO)
	var fiction: float = AIArrival._time_to_arrive_direct(
			from, dest, Vector3.ZERO)
	assert_gt(t, fiction, "you cannot skate through the cage")
	# ...but by a detour, not a catastrophe (the corner waypoint is near).
	assert_lt(t, fiction + 1.5, "the detour is the post corner, not a lap")


func test_behind_net_traverse_prices_the_alley() -> void:
	# Both endpoints in the behind-net alley: the honest route is the tiny
	# dip through the alley's center, not a trip around a post.
	var from := Vector3(2.0, 0, GameRules.GOAL_LINE_Z + 1.35)
	var dest := Vector3(-2.0, 0, GameRules.GOAL_LINE_Z + 1.35)
	var t: float = AIArrival.time_to_arrive(from, dest, Vector3.ZERO)
	var fiction: float = AIArrival._time_to_arrive_direct(
			from, dest, Vector3.ZERO)
	assert_lt(t, fiction + 0.6,
			"a 4 m behind-net skate routes through the alley, not around the world")


func test_retrieval_race_read_is_now_net_honest() -> void:
	# The harness-caught bug: a defender in FRONT of his net racing an
	# attacker to a puck BEHIND it. Straight-line the defender is much
	# closer; net-aware, his route rounds the cage. The race read must
	# price the real routes (the attacker's line from the side is clean).
	var states: Dictionary = {}
	var d := SkaterNetworkState.new()
	d.position = Vector3(0.0, 0, 24.0)      # net-front, 4.4 m from the puck
	states[1] = d
	var a := SkaterNetworkState.new()
	a.position = Vector3(9.0, 0, 28.2)      # side wall, 7 m, clean line
	a.velocity = Vector3(-6.0, 0, 0)
	states[2] = a
	var puck := Vector3(2.0, 0, 28.3)
	var t_defender: float = AILoosePuckChase.best_intercept_time(
			states, [1], puck, Vector3.ZERO)
	var t_attacker: float = AILoosePuckChase.best_intercept_time(
			states, [2], puck, Vector3.ZERO)
	assert_gt(t_defender, t_attacker,
			"the cage-rounding defender honestly loses this race")


# ── Lateral grip: planning matches the gripped body ──────────────────────────
# The movement core turns on edge grip (MovementConfig.lateral_grip) and the
# ETA's carve reads the same quantity. This pins the match: for a hard 90° redirect
# at speed, the LOW-grip body genuinely arrives later in the real sim, and
# the grip-aware model tracks the gripped sim within the suite's band.

func test_low_grip_redirect_model_tracks_gripped_sim() -> void:
	var v0 := Vector3(8.0, 0.0, 0.0)                          # flying +X
	var target: Vector3 = ORIGIN + Vector3(0.0, 0.0, -14.0)   # hard 90° redirect
	_cfg.lateral_grip = 0.85
	var sim_gripped: float = _sim_arrival_s(v0, target)
	_cfg.lateral_grip = 1.0
	var sim_neutral: float = _sim_arrival_s(v0, target)
	assert_gt(sim_gripped, sim_neutral,
			"the low-grip body really does arrive later on a redirect")
	var model_gripped: float = AIArrival.time_to_arrive(
			ORIGIN, target, v0,
			GameRules.DEFAULT_SKATER_MAX_SPEED_M_S,
			GameRules.DEFAULT_SKATER_THRUST_M_S2, 0.85)
	var model_neutral: float = AIArrival.time_to_arrive(
			ORIGIN, target, v0,
			GameRules.DEFAULT_SKATER_MAX_SPEED_M_S,
			GameRules.DEFAULT_SKATER_THRUST_M_S2, 1.0)
	assert_gt(model_gripped, model_neutral,
			"the model prices the same redirect penalty")
	var tol: float = maxf(sim_gripped * TOL_FRAC, TOL_FLOOR_S)
	assert_almost_eq(model_gripped, sim_gripped, tol,
			"grip-aware model tracks the gripped sim within the band")

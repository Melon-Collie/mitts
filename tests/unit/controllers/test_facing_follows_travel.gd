extends GutTest

# A skating human faces their travel rather than the cursor
# (FacingRules), driven through the live controller.
# Facing starts toward −Z; the skater is held at a set velocity each tick so the
# speed under test is the speed the rule reads.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const AHEAD := Vector3(0.0, 0.0, -1.0)
const LEFT := Vector3(-1.0, 0.0, 0.0)
const BEHIND := Vector3(0.0, 0.0, 1.0)


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	_puck = puck
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))


# Runs `ticks` ticks skating along `travel` at `speed` with the cursor 6 m out
# along `cursor`, holding the velocity so friction doesn't bleed it.
func _skate(travel: Vector3, speed: float, cursor: Vector3, ticks: int,
		move: Vector2 = Vector2.ZERO, stance: bool = false) -> void:
	for _i: int in ticks:
		_skater.velocity = travel * speed
		var input := InputState.new()
		input.move_vector = move
		input.stance_held = stance
		input.mouse_world_pos = _skater.global_position + cursor * 6.0
		input.mouse_world_pos.y = 0.0
		input.delta = DT
		_controller._process_input(input, DT)


func _facing_off(dir: Vector3) -> float:
	return rad_to_deg(absf(_skater.get_facing().angle_to(Vector2(dir.x, dir.z))))


func test_skating_with_the_puck_out_wide_faces_the_travel() -> void:
	_skate(AHEAD, 6.0, LEFT, 120, Vector2(0.0, -1.0))
	assert_lt(_facing_off(AHEAD), 5.0, "hips stay on the line while the cursor sits at 9")


func test_a_coast_keeps_its_line() -> void:
	_skate(AHEAD, 6.0, LEFT, 60, Vector2(0.0, -1.0))
	_skate(AHEAD, 1.3, LEFT, 120)
	assert_lt(_facing_off(AHEAD), 20.0, "a slow coast still faces where it glides")


func test_standing_squares_to_the_cursor() -> void:
	_skate(AHEAD, 0.0, LEFT, 120)
	assert_lt(_facing_off(LEFT), 5.0)


func test_a_cursor_behind_the_travel_turns_the_skater_round() -> void:
	_skate(AHEAD, 6.0, AHEAD, 30, Vector2(0.0, -1.0))
	_skate(AHEAD, 6.0, BEHIND, 120)
	assert_lt(_facing_off(BEHIND), 20.0,
			"looking straight back while skating forward turns to skate backward, not freeze")


func test_a_cursor_flicked_ahead_turns_a_backward_skater_forward() -> void:
	_controller._pose.facing = Vector2(BEHIND.x, BEHIND.z)
	_skater.set_facing(Vector2(BEHIND.x, BEHIND.z))
	_skate(AHEAD, 6.0, BEHIND, 30)
	_skate(AHEAD, 6.0, AHEAD, 120)
	assert_lt(_facing_off(AHEAD), 20.0,
			"a cursor flicked to where a backward skater is going turns them round, not freeze")


func test_a_backward_skater_turns_forward_on_the_cursors_side() -> void:
	# Leaning a touch right of straight back, with the cursor flicked ahead-left:
	# the body comes round through the left, the way the player is looking.
	var lean := Vector2(BEHIND.x, BEHIND.z).rotated(deg_to_rad(-5.0))
	_controller._pose.facing = lean
	_skater.set_facing(lean)
	var ahead_left := AHEAD.rotated(Vector3.UP, deg_to_rad(10.0))
	var widest_right: float = -INF
	var widest_left: float = INF
	for _i: int in 120:
		_skate(AHEAD, 6.0, ahead_left, 1)
		widest_right = maxf(widest_right, _skater.get_facing().x)
		widest_left = minf(widest_left, _skater.get_facing().x)
	assert_lt(_facing_off(AHEAD), 20.0)
	assert_lt(widest_left, -0.9, "the body swept through the left")
	assert_lt(widest_right, 0.2, "and never round the right")


func test_a_slow_backward_skater_turns_forward_on_a_flick() -> void:
	_controller._pose.facing = Vector2(BEHIND.x, BEHIND.z)
	_skater.set_facing(Vector2(BEHIND.x, BEHIND.z))
	_skate(AHEAD, 1.0, BEHIND, 30)
	_skate(AHEAD, 1.0, AHEAD, 120)
	assert_lt(_facing_off(AHEAD), 20.0, "below the engage band the body still comes round")


func test_a_stop_turns_round_to_a_cursor_behind() -> void:
	_skate(AHEAD, 6.0, AHEAD, 30, Vector2(0.0, -1.0))
	for _i: int in 60:
		_skater.velocity = AHEAD * 4.0
		var input := InputState.new()
		input.brake = true
		input.mouse_world_pos = _skater.global_position + BEHIND * 6.0
		input.mouse_world_pos.y = 0.0
		input.delta = DT
		_controller._process_input(input, DT)
	assert_lt(_facing_off(BEHIND), 20.0, "stopping and looking back turns the body to go back")


func test_a_lefty_reaches_round_the_forehand_then_pivots_onto_the_backhand() -> void:
	var edge: float = rad_to_deg(_controller.facing_rules.forehand_edge_rad)
	var inside := AHEAD.rotated(Vector3.UP, deg_to_rad(edge - 7.0))
	_skate(AHEAD, 6.0, AHEAD, 30, Vector2(0.0, -1.0))
	_skate(AHEAD, 6.0, inside, 120)
	assert_lt(_facing_off(AHEAD), 3.0, "the torso and arms reach; the hips stay on the line")
	var past := AHEAD.rotated(Vector3.UP, deg_to_rad(edge + 7.0))
	var widest_left: float = INF
	for _i: int in 120:
		_skate(AHEAD, 6.0, past, 1)
		widest_left = minf(widest_left, _skater.get_facing().x)
	assert_lt(_facing_off(BEHIND), 5.0, "past the edge the hips pivot onto the backward line")
	assert_lt(widest_left, -0.9, "turning toward the cursor, round the forehand side")
	var cursor_side: float = signf(_skater.get_facing().angle_to(Vector2(past.x, past.z)))
	assert_eq(cursor_side, -FacingRules.forehand_sign(true), "and the cursor comes out on the backhand")


# A carrier's blade stops on the backhand at the angle the bottom hand lets go,
# so its hips pivot there; an empty stick reaches on round to the full edge.
func test_a_carrier_pivots_where_its_blade_stops_on_the_backhand() -> void:
	var stop: float = _controller.bh_release_angle_deg
	var past := AHEAD.rotated(Vector3.UP, deg_to_rad(-(stop + 10.0)))
	_skate(AHEAD, 6.0, AHEAD, 30, Vector2(0.0, -1.0))
	_skate(AHEAD, 6.0, past, 120)
	assert_lt(_facing_off(AHEAD), 3.0, "an empty stick reaches; the hips stay on the line")
	_puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	var inside := AHEAD.rotated(Vector3.UP, deg_to_rad(-(stop - 10.0)))
	_skate(AHEAD, 6.0, inside, 120)
	assert_lt(_facing_off(AHEAD), 3.0, "inside the stop the carrier's hips stay on the line")
	_skate(AHEAD, 6.0, past, 120)
	assert_lt(_facing_off(BEHIND), 5.0, "past the stop they pivot onto the backward line")
	var cursor_side: float = signf(_skater.get_facing().angle_to(Vector2(past.x, past.z)))
	assert_eq(cursor_side, FacingRules.forehand_sign(true), "and the puck comes out on the forehand")
	_skate(AHEAD, 6.0, past, 120)
	assert_lt(_facing_off(BEHIND), 5.0, "far inside the forehand edge, it does not flip back")


func test_a_standing_carrier_still_turns_to_its_backhand() -> void:
	_puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	var right := AHEAD.rotated(Vector3.UP, deg_to_rad(-90.0))
	_skate(AHEAD, 0.0, right, 240)
	assert_lt(_facing_off(right), 5.0, "the freeze is the empty stick's wedge, not the carry stop")


func test_skating_backward_keeps_the_hips_on_the_line() -> void:
	_controller._pose.facing = Vector2(BEHIND.x, BEHIND.z)
	_skater.set_facing(Vector2(BEHIND.x, BEHIND.z))
	_skate(AHEAD, 6.0, BEHIND.rotated(Vector3.UP, deg_to_rad(60.0)), 120)
	assert_lt(_facing_off(BEHIND), 3.0, "the torso watches the play; the hips stay on the line")


func test_the_reach_edges_are_the_rigs() -> void:
	var c := _controller
	assert_almost_eq(c.facing_rules.forehand_edge_rad,
			deg_to_rad(c.rom_forehand_angle_max_deg + c.upper_body_max_twist_deg), 0.000001)
	assert_almost_eq(c.facing_rules.backhand_edge_rad,
			deg_to_rad(c.rom_backhand_angle_max_deg + c.upper_body_max_twist_deg), 0.000001)
	assert_almost_eq(c.carry_facing_rules.forehand_edge_rad, c.facing_rules.forehand_edge_rad,
			0.000001)
	assert_almost_eq(c.carry_facing_rules.backhand_edge_rad, deg_to_rad(c.bh_release_angle_deg),
			0.000001, "a carrier's blade stops on the backhand where the bottom hand lets go")
	assert_almost_eq(c.carry_facing_rules.forehand_yield_rad,
			deg_to_rad(c.carry_forehand_yield_deg), 0.000001)
	assert_eq(c.facing_rules.forehand_yield_rad, INF, "an empty stick reaches round to the edge")
	# Only the edges and the yield differ: the native rollout reads the rest off
	# facing_rules.
	for knob: String in ["engage_min_speed", "engage_full_speed", "hold_min_speed",
			"hold_full_speed", "stance_square_max_speed", "pivot_commit_rad"]:
		assert_eq(c.carry_facing_rules.get(knob), c.facing_rules.get(knob), knob)
	# The top hand's shoulder is on the backhand side, so the forehand is the other.
	for lefty: bool in [true, false]:
		_skater.is_left_handed = lefty
		var sh: Vector3 = _skater.shoulder.global_position - _skater.global_position
		var side: float = signf(_skater.get_facing().angle_to(Vector2(sh.x, sh.z)))
		assert_eq(side, -FacingRules.forehand_sign(lefty),
				"a %s shot's shoulder" % ("left" if lefty else "right"))


func test_a_standing_skater_turns_round_to_a_cursor_behind() -> void:
	var behind_left := BEHIND.rotated(Vector3.UP, deg_to_rad(-10.0))
	_skate(AHEAD, 0.0, AHEAD, 30)
	var widest_left: float = INF
	var widest_right: float = -INF
	for _i: int in 240:
		_skate(AHEAD, 0.0, behind_left, 1)
		widest_left = minf(widest_left, _skater.get_facing().x)
		widest_right = maxf(widest_right, _skater.get_facing().x)
	assert_lt(_facing_off(behind_left), 5.0, "the body comes round to it")
	assert_lt(widest_left, -0.9, "round the cursor's side")
	assert_lt(widest_right, 0.2, "and never the other way")


# A cursor held on the carry stop flipped the pivot on float noise, and the hips
# sat between the two lines; a pivot under way now carries through.
func test_a_cursor_held_on_the_stop_puts_the_hips_on_a_line() -> void:
	_puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	var edge: float = _controller.bh_release_angle_deg
	for jitter: float in [0.0, 2.0]:
		_controller._pose.facing = Vector2(0.0, -1.0)
		_skater.set_facing(Vector2(0.0, -1.0))
		_skate(AHEAD, 6.0, AHEAD, 30, Vector2(0.0, -1.0))
		var widest: float = 0.0
		for i: int in 240:
			var cursor := AHEAD.rotated(Vector3.UP, deg_to_rad(-edge + jitter * sin(i * 0.9)))
			_skate(AHEAD, 6.0, cursor, 1, Vector2(0.0, -1.0))
			if i >= 120:
				var off: float = _facing_off(AHEAD)
				widest = maxf(widest, minf(off, 180.0 - off))
		assert_lt(widest, 5.0, "jitter %.0f°: the hips sit on a line, %.1f° off one" % [jitter, widest])


func test_pushing_off_squared_to_the_backhand_skates_forward() -> void:
	_puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	var stop: float = _controller.bh_release_angle_deg
	var cursor := AHEAD.rotated(Vector3.UP, deg_to_rad(-(stop - 6.0)))
	_skate(AHEAD, 0.0, cursor, 120)
	for i: int in 120:
		_skate(AHEAD, minf(i * 0.08, 6.0), cursor, 1, Vector2(0.0, -1.0))
	assert_lt(_facing_off(AHEAD), 5.0, "the hips take the line up, not the pivot")


func test_the_stance_squares_only_when_slow() -> void:
	_skate(AHEAD, 1.5, LEFT, 120, Vector2.ZERO, true)
	assert_lt(_facing_off(LEFT), 10.0, "slow in the stance squares to the cursor")
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))
	_skate(AHEAD, 6.0, LEFT, 120, Vector2(0.0, -1.0), true)
	assert_lt(_facing_off(AHEAD), 5.0, "at speed the stance just crouches")

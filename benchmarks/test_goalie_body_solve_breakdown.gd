extends GutTest

# Splits GoalieController._update_body_parts into its three halves — the input
# gather, the pose build (pure GDScript math on a RefCounted scratch config) and
# apply_body_config (eases and writes the Node3D parts) — and prices the engine
# property accesses apply makes, so the solve's cost can be divided into script
# work and engine work. Report-only; same scene setup as the goalie micro-bench.

const REPS: int = 5000
const SETTLE_TICKS: int = 240
const DELTA: float = 1.0 / 120.0

var _results: Array[Dictionary] = []
var _goalie: Goalie = null
var _puck: Puck = null
var _ctrl: GoalieController = null


func before_all() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate() as Goalie
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child(_goalie)
	add_child(_puck)
	_puck.global_position = Vector3(1.2, 0.0, GameRules.GOAL_LINE_Z - 6.5)
	_ctrl = GoalieController.new()
	add_child(_ctrl)
	_ctrl.setup(_goalie, _puck, GameRules.GOAL_LINE_Z, true)
	for _i: int in SETTLE_TICKS:
		_ctrl._physics_process(DELTA)


func after_all() -> void:
	for n: Node in [_ctrl, _goalie, _puck]:
		if is_instance_valid(n):
			n.free()
	var widest: int = 0
	for r: Dictionary in _results:
		widest = maxi(widest, (r["label"] as String).length())
	gut.p("")
	gut.p("── Goalie body solve breakdown (µs/call, %d reps) ──" % REPS)
	for r: Dictionary in _results:
		gut.p("  %s  %8.3f" % [(r["label"] as String).rpad(widest), r["us"]])
	gut.p("")


func _bench(label: String, fn: Callable) -> float:
	fn.call()
	var t0: int = Time.get_ticks_usec()
	for _i: int in REPS:
		fn.call()
	var us: float = float(Time.get_ticks_usec() - t0) / float(REPS)
	_results.append({"label": label, "us": us})
	return us


# An empty lambda through the same Callable, so its cost can be read off every row.
func _note(label: String, us: float) -> void:
	_results.append({"label": label, "us": us})


func test_body_solve_breakdown() -> void:
	var overhead: float = _bench("(callable overhead)", func() -> void: pass)
	var whole: float = _bench("_update_body_parts (whole)", func() -> void:
		_ctrl._update_body_parts(DELTA))
	var build: float = _bench("  build() (state as played: %s)" % _ctrl._sm.current,
			func() -> void: _ctrl._pose.build(_ctrl._pose_inputs))
	var config: GoalieBodyConfig = _ctrl._pose.build(_ctrl._pose_inputs)
	var lerp_t: float = _ctrl.part_lerp_speed * DELTA
	var apply: float = _bench("  apply_body_config", func() -> void:
		_goalie.apply_body_config(config, lerp_t))
	var seat: float = _bench("    of which _seat_blocker", func() -> void:
		_goalie._seat_blocker())
	_note("  gather + pacing (whole - build - apply)",
			(whole - overhead) - (build - overhead) - (apply - overhead))

	# The build per state: the inputs as gathered, only the branch switched.
	var played: int = _ctrl._pose_inputs.state
	for s: int in [GoalieStateMachine.State.STANDING, GoalieStateMachine.State.BUTTERFLY,
			GoalieStateMachine.State.SLIDING, GoalieStateMachine.State.HALF_BUTTERFLY_LEFT,
			GoalieStateMachine.State.RVH_LEFT, GoalieStateMachine.State.COVERING]:
		_ctrl._pose_inputs.state = s
		_bench("  build() as %s" % GoalieStateMachine.State.keys()[s], func() -> void:
			_ctrl._pose.build(_ctrl._pose_inputs))
	# A shot being answered: the hand-reach path runs on top of the stance.
	_ctrl._pose_inputs.state = GoalieStateMachine.State.READY
	_ctrl._pose_inputs.reacting_to_shot = true
	_ctrl._pose_inputs.hands_answer_shot = true
	_ctrl._pose_inputs.shot_impact_x = 0.45
	_ctrl._pose_inputs.shot_impact_y = 1.1
	_bench("  build() as READY + glove reach", func() -> void:
		_ctrl._pose.build(_ctrl._pose_inputs))
	_ctrl._pose_inputs.reacting_to_shot = false
	_ctrl._pose_inputs.hands_answer_shot = false
	_ctrl._pose_inputs.state = played

	# Engine accesses, on the goalie's own parts so the subtree each write
	# propagates through is the real one. Values alternate so no setter can
	# short-circuit on an unchanged value.
	var body: Node3D = _goalie._body
	var a: Vector3 = body.position
	var b: Vector3 = a + Vector3(0.001, 0.0, 0.0)
	var flip: Array[bool] = [false]
	var get_pos: float = _bench("  engine: Node3D.position read", func() -> void:
		var _p: Vector3 = body.position)
	var set_pos: float = _bench("  engine: Node3D.position write", func() -> void:
		flip[0] = not flip[0]
		body.position = a if flip[0] else b)
	var ra: Vector3 = body.rotation_degrees
	var rb: Vector3 = ra + Vector3(0.1, 0.0, 0.0)
	var get_rot: float = _bench("  engine: rotation_degrees read", func() -> void:
		var _r: Vector3 = body.rotation_degrees)
	var set_rot: float = _bench("  engine: rotation_degrees write", func() -> void:
		flip[0] = not flip[0]
		body.rotation_degrees = ra if flip[0] else rb)
	var blocker: Node3D = _goalie._blocker
	var ta: Transform3D = blocker.transform
	var tb: Transform3D = ta.translated(Vector3(0.001, 0.0, 0.0))
	var set_xf: float = _bench("  engine: transform write", func() -> void:
		flip[0] = not flip[0]
		blocker.transform = ta if flip[0] else tb)
	body.position = a
	body.rotation_degrees = ra
	blocker.transform = ta

	# apply_body_config's accesses, counted off its source: two pads (position +
	# rotation writes each), four _lerp_part (two reads, two writes each) and
	# _seat_blocker (four reads, one transform write; basis/transform reads
	# priced as a position read).
	var engine_est: float = (get_pos - overhead) * 8.0 + (get_rot - overhead) * 4.0 \
			+ (set_pos - overhead) * 6.0 + (set_rot - overhead) * 6.0 \
			+ (set_xf - overhead) * 1.0
	_note("  apply: engine accesses (estimated sum)", engine_est)
	_note("  apply: script math (apply - estimate)", (apply - overhead) - engine_est)
	assert_true(seat > 0.0 and _results.size() > 0, "breakdown produced results")


func test_interaction() -> void:
	var t: float = _ctrl.part_lerp_speed * DELTA
	var a := GoalieBodyConfig.new()
	var b := GoalieBodyConfig.new()
	var src: GoalieBodyConfig = _ctrl._pose.build(_ctrl._pose_inputs)
	for p: Dictionary in src.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = src.get(p["name"])
			a.set(p["name"], v)
			b.set(p["name"], v + Vector3(0.02, 0.01, 0.0) if v is Vector3 else v)
	var flip: Array[bool] = [false]
	_bench("apply, one converged pose", func() -> void: _goalie.apply_body_config(a, t))
	_bench("apply, alternating poses (t = 1)", func() -> void:
		flip[0] = not flip[0]
		_goalie.apply_body_config(a if flip[0] else b, 1.0))
	_bench("apply, alternating poses (t = 1), whole-tree flush", func() -> void:
		flip[0] = not flip[0]
		_goalie.apply_body_config(a if flip[0] else b, 1.0)
		var _g: Vector3 = _goalie._left_pad.global_position)
	_bench("build -> apply", func() -> void:
		_goalie.apply_body_config(_ctrl._pose.build(_ctrl._pose_inputs), t))
	assert_true(_results.size() > 0, "interaction rows produced results")


func test_gather_breakdown() -> void:
	_bench("gather: _suspend_body_solve", func() -> void: _ctrl._suspend_body_solve())
	_bench("gather: _hands_answer_shot", func() -> void: _ctrl._hands_answer_shot())
	_bench("gather: _is_blade_intent_active", func() -> void: _ctrl._is_blade_intent_active())
	_bench("gather: _lunge_progress", func() -> void: _ctrl._lunge_progress())
	_bench("gather: _sweep_anim_progress", func() -> void: _ctrl._sweep_anim_progress())
	_bench("gather: _sweep_windup_progress", func() -> void: _ctrl._sweep_windup_progress())
	_bench("gather: _is_paddle_sweep_active", func() -> void: _ctrl._is_paddle_sweep_active())
	_bench("gather: _is_standing_sweep_active", func() -> void:
		_ctrl._is_standing_sweep_active())
	_bench("gather: _desired_head_yaw_deg", func() -> void: _ctrl._desired_head_yaw_deg())
	_bench("gather: _footwork.advance", func() -> void:
		_ctrl._footwork.advance(DELTA, 0.0, _ctrl._arc_t_push, _ctrl._arc_braking,
				_ctrl.shuffle_speed))
	_bench("gather: _set_pad_toe_out_inputs", func() -> void: _ctrl._set_pad_toe_out_inputs())
	_bench("gather: _set_prelean_inputs", func() -> void: _ctrl._set_prelean_inputs())
	_bench("gather: one Inputs field write", func() -> void:
		_ctrl._pose_inputs.current_x = _ctrl._current_x)
	_bench("engine: goalie.global_position read", func() -> void:
		var _p: Vector3 = _goalie.global_position)
	_bench("engine: puck.global_position read", func() -> void:
		var _p: Vector3 = _puck.global_position)
	_bench("engine: goalie.get_goalie_rotation_y()", func() -> void:
		_goalie.get_goalie_rotation_y())
	_bench("engine: puck.get_carrier()", func() -> void: _puck.get_carrier())
	assert_true(_results.size() > 0, "gather breakdown produced results")

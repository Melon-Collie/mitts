extends GutTest

# Stateful parity: NativeSkaterGait (native/src/) against its GDScript reference.
# Two SkaterSkatingCoordinators share one skater and controller — one wired to
# the port, one with its handle nulled so it runs SkaterLocomotion, the
# alignment and pivot read and GaitPose — and every step both publish into a
# CaptureSkater whose pose writes land in fields instead of bones. The port
# carries ~60 floats of smoothed state, so parity is checked EVERY step: a
# divergence compounds and trips within a few frames of where it happens.
#
# The overlay layers run in GDScript on both sides, shaping the pose each side
# solved, so the overlay scenario checks that the port loads everything a layer
# reads.

const State = SkaterStateMachine.State
const TOLERANCE: float = 0.001
const SEED: int = 0x47414954  # "GAIT"


class CaptureSkater extends Skater:
	var cap := PackedFloat64Array()

	func _init() -> void:
		cap.resize(22)

	func set_leg_swing(left_pitch: float, left_roll: float, left_knee: float,
			right_pitch: float, right_roll: float, right_knee: float,
			left_yaw: float = 0.0, right_yaw: float = 0.0) -> void:
		cap[0] = left_pitch
		cap[1] = left_roll
		cap[2] = left_knee
		cap[3] = right_pitch
		cap[4] = right_roll
		cap[5] = right_knee
		cap[6] = left_yaw
		cap[7] = right_yaw

	func set_ankle_flatten(left: float, right: float, level_l: float = 0.0,
			level_r: float = 0.0, _ice: Basis = Basis.IDENTITY) -> void:
		cap[8] = left
		cap[9] = right
		cap[20] = level_l
		cap[21] = level_r

	func set_edge_loads(left: float, right: float) -> void:
		cap[10] = left
		cap[11] = right

	func set_skating_crouch_drop(drop: float, frame_drop: float = 0.0, plant: float = 1.0) -> void:
		cap[12] = drop
		cap[16] = frame_drop
		cap[17] = plant

	func set_leg_contact(plant_l: float, plant_r: float, _dt: float) -> void:
		cap[18] = plant_l
		cap[19] = plant_r

	func set_trunk_texture(pitch_add: float, roll_add: float) -> void:
		cap[13] = pitch_add
		cap[14] = roll_add

	func set_faceoff_address(blend: float) -> void:
		cap[15] = blend


class StubGameState extends Node:
	var faceoff_prep: bool = false

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func is_faceoff_prep() -> bool:
		return faceoff_prep


const _CAP_NAMES: Array[String] = ["l_pitch", "l_roll", "l_knee", "r_pitch", "r_roll",
		"r_knee", "l_yaw", "r_yaw", "flat_l", "flat_r", "edge_l", "edge_r", "crouch",
		"trunk_pitch", "trunk_roll", "address", "frame_drop", "plant", "plant_l",
		"plant_r", "level_l", "level_r"]

var _rng := RandomNumberGenerator.new()
var _skater: CaptureSkater = null
var _controller: SkaterController = null
var _state: StubGameState = null
var _ref: SkaterSkatingCoordinator = null
var _nat: SkaterSkatingCoordinator = null
var _worst: float = 0.0
var _worst_where: String = ""
var _steps: int = 0
# The heaviest weight each state reached, so a fuzz that never skated a state
# cannot pass as parity on it.
var _seen: Dictionary = {}


func before_each() -> void:
	if not ClassDB.class_exists(&"NativeSkaterGait"):
		return
	_rng.seed = SEED
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var node: Node = load("res://Scenes/Skater.tscn").instantiate()
	node.set_script(CaptureSkater)
	_skater = node as CaptureSkater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(2.0, GameRules.FACEOFF_SPAWN_HEIGHT, 8.0)
	_state = StubGameState.new()
	add_child_autofree(_state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, _state)
	# All stepping is explicit: a live controller would tick its own gait in the
	# frames GUT yields between tests.
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	_ref = SkaterSkatingCoordinator.new()
	_ref.setup(_skater, SkaterStateMachine.new(), _controller)
	_ref._native = null
	_nat = SkaterSkatingCoordinator.new()
	_nat.setup(_skater, SkaterStateMachine.new(), _controller)
	_worst = 0.0
	_worst_where = ""
	_steps = 0
	_seen = {}


func _native_missing() -> bool:
	if ClassDB.class_exists(&"NativeSkaterGait") and _nat != null and _nat._native != null:
		return false
	NativeParityGuard.report_missing(self, "NativeSkaterGait")
	return true


# One render pass on both sides; returns false at the first divergence (and
# fails the test with where it happened).
func _step(delta: float, label: String) -> bool:
	_steps += 1
	_ref.apply(delta)
	var want: PackedFloat64Array = _skater.cap.duplicate()
	var want_pub: PackedFloat64Array = _published(_ref)
	_nat.apply(delta)
	var got: PackedFloat64Array = _skater.cap
	var got_pub: PackedFloat64Array = _published(_nat)
	for i: int in want.size():
		if not _close(want[i], got[i], "%s step %d %s" % [label, _steps, _CAP_NAMES[i]]):
			return false
	var pub_names: Array[String] = ["stop_yaw", "travel_align_yaw", "pivot_hold",
			"faceoff_blend", "shot_hip_yaw", "crouch_drop", "push_l", "push_r", "push_strength", "stop_weight",
			"skid_weight", "turn_load"]
	for i: int in pub_names.size():
		if not _close(want_pub[i], got_pub[i], "%s step %d %s" % [label, _steps, pub_names[i]]):
			return false
	var mix_want: LocomotionRules.Mix = _ref.locomotion_mix()
	var mix_got: LocomotionRules.Mix = _nat.locomotion_mix()
	for field: String in ["glide", "stride", "crossover", "carve", "backward", "shuffle", "skid",
			"tight", "stop", "side"]:
		if not _close(mix_want.get(field), mix_got.get(field),
				"%s step %d mix.%s" % [label, _steps, field]):
			return false
		_seen[field] = maxf(_seen.get(field, 0.0), mix_got.get(field))
	return _close(0.0, angle_difference(_ref.stride_phase, _nat.stride_phase),
			"%s step %d stride_phase" % [label, _steps])


func _published(c: SkaterSkatingCoordinator) -> PackedFloat64Array:
	return PackedFloat64Array([c.stop_yaw_offset, c.travel_align_yaw, c.pivot_hold,
			c.faceoff_blend, c.shot_hip_yaw, c.crouch_drop, c.push_l, c.push_r, c.push_strength, c.stop_weight,
			c.skid_weight, c.turn_load])


func _close(want: float, got: float, where: String) -> bool:
	var err: float = absf(want - got)
	if err > _worst:
		_worst = err
		_worst_where = where
	if err > TOLERANCE:
		fail_test("native gait diverged at %s: GDScript %.6f, native %.6f" % [where, want, got])
		return false
	return true


func _report(label: String) -> void:
	gut.p("%s: %d steps, worst |Δ| %s at %s" % [label, _steps,
			String.num_scientific(_worst), _worst_where])
	assert_lt(_worst, TOLERANCE, "%s stayed within tolerance" % label)


func _random_delta() -> float:
	# Render rates from 40 to 240 fps; the velocity below only steps on some of
	# them, as it does between physics ticks.
	return 1.0 / _rng.randf_range(40.0, 240.0)


func _drive_skating(steps: int, label: String) -> bool:
	var vel := Vector3(_rng.randf_range(-4.0, 4.0), 0.0, _rng.randf_range(-4.0, 4.0))
	var heading: float = _rng.randf_range(-PI, PI)
	var segment: int = 0
	var tilt := Vector2.ZERO
	for _i: int in steps:
		if segment <= 0:
			segment = _rng.randi_range(10, 90)
			var r: float = _rng.randf()
			if r < 0.15:
				_skater.move_intent = Vector2.ZERO
			else:
				_skater.move_intent = Vector2.from_angle(_rng.randf_range(-PI, PI)) \
						* _rng.randf_range(0.3, 1.0)
			_skater.brake_intent = _rng.randf() < 0.15
			_controller.stance_active = _rng.randf() < 0.2
			# The hips lean into the turn and pitch over it; the ice frame the
			# authored states stand the skates on follows both.
			tilt = Vector2(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.35, 0.35))
			_skater.lower_body.rotation = Vector3(_rng.randf_range(-0.3, 0.3),
					_rng.randf_range(-0.8, 0.8), 0.0)
		segment -= 1
		# Velocity steps on roughly two of three passes, toward the intent.
		if _rng.randf() < 0.66:
			var push := Vector3(_skater.move_intent.x, 0.0, _skater.move_intent.y) * 0.12
			if _skater.brake_intent:
				push = -vel * 0.05
			vel = (vel + push + Vector3(_rng.randf_range(-0.05, 0.05), 0.0,
					_rng.randf_range(-0.05, 0.05))).limit_length(9.0)
			if _rng.randf() < 0.01:
				vel = Vector3.ZERO
		_skater.velocity = vel
		_skater.set_balance_tilt(tilt)
		# Facing wanders, with occasional fast swings across the travel line —
		# the pivot's trigger.
		heading += _rng.randf_range(-0.05, 0.05)
		if _rng.randf() < 0.02:
			heading += _rng.randf_range(-2.5, 2.5)
		_skater.set_facing(Vector2(sin(heading), -cos(heading)))
		if not _step(_random_delta(), label):
			return false
	return true


func test_skating_parity() -> void:
	if _native_missing():
		return
	if _drive_skating(4000, "skating"):
		_report("skating")
	_assert_skated(["stride", "backward", "shuffle", "skid", "stop"])


# Held curves, both ways and reversed: the stick ahead of travel drives through
# them in crossovers, across it coasts round on carved edges, and in the stance
# both dig in. The hips lean into the curve.
func test_turn_parity() -> void:
	if _native_missing():
		return
	var heading: float = 0.0
	for turn: Array in [[2.4, PI * 0.25, false], [-2.4, -PI * 0.25, false],
			[2.0, PI * 0.5, false], [-2.0, -PI * 0.5, false], [2.4, PI * 0.3, true],
			[-2.4, -PI * 0.3, true]]:
		var rate: float = turn[0]
		_controller.stance_active = turn[2]
		_skater.set_balance_tilt(Vector2(signf(rate) * 0.25, 0.0))
		for _i: int in 360:
			var delta: float = _random_delta()
			heading += rate * delta
			var travel := Vector2(sin(heading), -cos(heading))
			_skater.velocity = Vector3(travel.x, 0.0, travel.y) * 7.0
			_skater.move_intent = travel.rotated(turn[1])
			_skater.set_facing(travel)
			if not _step(delta, "turn %.1f" % rate):
				return
	_report("turns")
	_assert_skated(["crossover", "carve", "tight"])


func _assert_skated(fields: Array[String]) -> void:
	gut.p("heaviest weights: %s" % _seen)
	for field: String in fields:
		assert_gt(_seen.get(field, 0.0), 0.5, "the fuzz skated %s" % field)


func test_pivot_parity() -> void:
	if _native_missing():
		return
	# Travel held straight, facing swung through the lateral band and back, at
	# several rates — engage, step-around, release, and an aborted swing.
	_skater.velocity = Vector3(0.0, 0.0, -6.0)
	_skater.move_intent = Vector2(0.0, -1.0)
	for rate: float in [2.0, 5.0, 9.0, -6.0]:
		var heading: float = 0.0
		for _i: int in 240:
			heading = clampf(heading + rate / 120.0, -PI, PI)
			_skater.set_facing(Vector2(sin(heading), -cos(heading)))
			if not _step(1.0 / 120.0, "pivot %.0f" % rate):
				return
		for _i: int in 120:
			heading = move_toward(heading, 0.0, 4.0 / 120.0)
			_skater.set_facing(Vector2(sin(heading), -cos(heading)))
			if not _step(1.0 / 120.0, "pivot return %.0f" % rate):
				return
	_report("pivot")


func test_overlay_parity() -> void:
	if _native_missing():
		return
	var shot_states: Array[int] = [State.SKATING_WITH_PUCK, State.SKATING_WITHOUT_PUCK,
			State.WRISTER_AIM, State.SLAPPER_CHARGE_WITH_PUCK, State.ONE_TIMER_RETENTION,
			State.FOLLOW_THROUGH, State.SHOT_BLOCKING]
	var vel := Vector3(1.0, 0.0, -5.0)
	for round_i: int in 60:
		var r: float = _rng.randf()
		_skater.current_shot_state = shot_states[_rng.randi_range(0, shot_states.size() - 1)]
		_skater.shot_charge = _rng.randf()
		_skater.hit_committed = r < 0.15
		_skater.blade_up = _rng.randf() < 0.15
		_skater.is_left_handed = _rng.randf() < 0.5
		_skater.is_faceoff_center = _rng.randf() < 0.5
		_controller.stance_active = _rng.randf() < 0.3
		_state.faceoff_prep = _rng.randf() < 0.12
		if _rng.randf() < 0.15:
			_controller.set("_knockdown_total", 1.2)
			_controller.knockdown_timer = 1.2
		if _rng.randf() < 0.15:
			_controller.stagger_timer = _rng.randf_range(0.2, _controller.stagger_max_seconds)
		if _rng.randf() < 0.1:
			_controller.start_celebration(1.0)
		if _rng.randf() < 0.2:
			var hit := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf_range(-PI, PI))
			var power: float = _rng.randf()
			_ref.start_check_drive(hit, power)
			_nat.start_check_drive(hit, power)
		_skater.move_intent = Vector2.ZERO if r > 0.8 \
				else Vector2.from_angle(_rng.randf_range(-PI, PI))
		_skater.set_balance_tilt(Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3)))
		for _i: int in _rng.randi_range(20, 80):
			var delta: float = _random_delta()
			vel = (vel + Vector3(_skater.move_intent.x, 0.0, _skater.move_intent.y) * 0.1) \
					.limit_length(8.0)
			_skater.velocity = vel
			_controller.knockdown_timer = maxf(_controller.knockdown_timer - delta, 0.0)
			_controller.stagger_timer = maxf(_controller.stagger_timer - delta, 0.0)
			_controller.tick_celebration(delta)
			if not _step(delta, "overlays round %d" % round_i):
				return
	_report("overlays")


func test_reset_settle_and_reconfigure_parity() -> void:
	if _native_missing():
		return
	if not _drive_skating(400, "before reset"):
		return
	# A teleport resets both mid-stride.
	_ref.reset_to_rest()
	_nat.reset_to_rest()
	if not _drive_skating(400, "after reset"):
		return
	# Quiet long enough to settle, then wake.
	_skater.velocity = Vector3.ZERO
	_skater.move_intent = Vector2.ZERO
	_skater.brake_intent = false
	_controller.stance_active = false
	for _i: int in 200:
		if not _step(1.0 / 120.0, "settling"):
			return
	assert_true(_nat._settled and _ref._settled, "both sides settled")
	# Attribute scaling rewrites tunables; the port reloads them.
	_controller.max_speed *= 1.1
	_controller.lateral_grip *= 0.9
	_controller.stride_push_out_m *= 0.9
	_nat.native_reconfigure()
	_ref.leg_scale = 1.07
	_nat.leg_scale = 1.07
	if _drive_skating(800, "reconfigured"):
		_report("reset, settle and reconfigure")

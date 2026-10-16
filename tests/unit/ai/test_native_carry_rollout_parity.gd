extends GutTest

# Parity fuzz: NativeCarryRollout (C++ GDExtension, native/src/) against the
# GDScript reference AICarryRollout — every move rolled from random starts over
# the whole surface (the boards, the corner arcs, round the cages) for random
# bodies and step sizes. Goes pending when the extension isn't built.

const TOLERANCE: float = 0.001
const FUZZ_ITERATIONS: int = 400
const SEED: int = 0x524F4C4C  # "ROLL"

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_rng.seed = SEED


func _native_missing() -> bool:
	if ClassDB.class_exists(&"NativeCarryRollout"):
		return false
	NativeParityGuard.report_missing(self, "NativeCarryRollout")
	return true


func _random_caps() -> AISkaterCaps:
	var caps := AISkaterCaps.new()
	var cfg: SkaterMovementRules.MovementConfig = caps.movement
	cfg.thrust *= _rng.randf_range(0.7, 1.3)
	cfg.max_speed *= _rng.randf_range(0.8, 1.2)
	cfg.turn_accel *= _rng.randf_range(0.7, 1.3)
	cfg.lateral_grip = _rng.randf_range(0.6, 1.3)
	cfg.puck_carry_speed_multiplier = _rng.randf_range(0.8, 1.0)
	caps.facing_drag_speed = _rng.randf_range(3.0, 8.0)
	caps.facing_drag_speed_braking = _rng.randf_range(6.0, 14.0)
	caps.body_radius = _rng.randf_range(0.3, 0.42)
	caps.board_shield_probe = _rng.randf_range(0.8, 1.4)
	caps.board_shield_max_rad = deg_to_rad(_rng.randf_range(30.0, 70.0))
	caps.reach_cone_half_angle = deg_to_rad(_rng.randf_range(130.0, 170.0))
	return caps


func _random_pos() -> Vector3:
	var r: float = _rng.randf()
	var x: float
	var z: float
	if r < 0.3:
		# Hugging a side board.
		x = signf(_rng.randf() - 0.5) * (GameRules.INNER_HALF_WIDTH - _rng.randf_range(0.4, 2.0))
		z = _rng.randf_range(-GameRules.CORNER_CENTER_Z, GameRules.CORNER_CENTER_Z)
	elif r < 0.5:
		# Round a cage.
		x = _rng.randf_range(-3.0, 3.0)
		z = signf(_rng.randf() - 0.5) * (GameRules.GOAL_LINE_Z + _rng.randf_range(-3.0, 3.0))
	elif r < 0.65:
		# In a corner.
		x = signf(_rng.randf() - 0.5) * _rng.randf_range(GameRules.CORNER_CENTER_X,
				GameRules.INNER_HALF_WIDTH - 0.5)
		z = signf(_rng.randf() - 0.5) * _rng.randf_range(GameRules.CORNER_CENTER_Z,
				GameRules.INNER_HALF_LENGTH - 2.5)
	else:
		x = _rng.randf_range(-GameRules.INNER_HALF_WIDTH + 1.0, GameRules.INNER_HALF_WIDTH - 1.0)
		z = _rng.randf_range(-GameRules.GOAL_LINE_Z, GameRules.GOAL_LINE_Z)
	var held: Vector2 = GameRules.push_out_of_net(
			GameRules.clamp_to_rink_inner(Vector2(x, z), 0.4), 0.4)
	return Vector3(held.x, 0.0, held.y)


func _unit(angle: float) -> Vector2:
	return Vector2.from_angle(angle)


func test_every_move_rolls_as_the_gdscript_does() -> void:
	if _native_missing():
		return
	var reference := AICarryRollout.new()
	reference._native = null
	var ported := AICarryRollout.new()
	ported._native = NativeCarryRolloutFactory.make_configured()
	var worst: float = 0.0
	for i: int in FUZZ_ITERATIONS:
		var caps: AISkaterCaps = _random_caps()
		var pos: Vector3 = _random_pos()
		var speed: float = _rng.randf_range(0.0, 10.0) if _rng.randf() < 0.9 else 0.0
		var vel3 := Vector3.ZERO
		var v2: Vector2 = _unit(_rng.randf_range(-PI, PI)) * speed
		vel3 = Vector3(v2.x, 0.0, v2.y)
		var facing: Vector2 = _unit(_rng.randf_range(-PI, PI))
		var toward: Vector2 = _unit(_rng.randf_range(-PI, PI)) * _rng.randf_range(0.5, 30.0)
		var has_puck: bool = _rng.randf() < 0.85
		var steps: Array[int] = [1, 2, 4, 8]
		var st: int = steps[_rng.randi_range(0, steps.size() - 1)]
		reference.step_ticks = st
		ported.step_ticks = st
		reference.roll_all(pos, vel3, facing, toward, caps, has_puck)
		ported.roll_all(pos, vel3, facing, toward, caps, has_puck)
		assert_not_null(ported._native, "the kernel loaded these caps")
		for m: int in AICarryRollout.MOVE_COUNT:
			var label: String = "iter %d, %s from %s, step %d" % [
					i, AICarryRollout.Move.keys()[m], pos, st]
			var dp: float = reference.end_pos[m].distance_to(ported.end_pos[m])
			var dv: float = reference.end_vel[m].distance_to(ported.end_vel[m])
			var df: float = reference.end_facing[m].distance_to(ported.end_facing[m])
			worst = maxf(worst, maxf(dp, maxf(dv, df)))
			assert_lt(dp, TOLERANCE, "%s: end position" % label)
			assert_lt(dv, TOLERANCE, "%s: end velocity" % label)
			assert_lt(df, TOLERANCE, "%s: end facing" % label)
			assert_eq(reference.touched_boundary[m], ported.touched_boundary[m],
					"%s: met the boards" % label)
			for k: int in AICarryRollout.SAMPLES:
				assert_lt(reference.sample(m, k).distance_to(ported.sample(m, k)), TOLERANCE,
						"%s: sample %d" % [label, k])
	gut.p("worst divergence %.7f" % worst)


func test_a_caps_rebuilt_for_a_new_body_is_reloaded() -> void:
	if _native_missing():
		return
	var reference := AICarryRollout.new()
	reference._native = null
	var ported := AICarryRollout.new()
	ported._native = NativeCarryRolloutFactory.make_configured()
	var slow := AISkaterCaps.new()
	var fast := AISkaterCaps.new()
	fast.movement.thrust *= 1.4
	fast.movement.max_speed *= 1.2
	for caps: AISkaterCaps in [slow, fast]:
		reference.roll_all(Vector3.ZERO, Vector3(0, 0, -4), Vector2(0, -1), Vector2(0, -1), caps)
		ported.roll_all(Vector3.ZERO, Vector3(0, 0, -4), Vector2(0, -1), Vector2(0, -1), caps)
		assert_almost_eq(ported.end_pos[0], reference.end_pos[0], Vector3.ONE * TOLERANCE)

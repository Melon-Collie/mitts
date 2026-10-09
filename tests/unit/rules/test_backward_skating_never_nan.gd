extends GutTest

# Probe for a crash skating backwards online.
# 1. Confirms how Godot's Vector2.normalized() behaves on a (near-)zero vector.
# 2. Drives the real SkaterMovementRules.apply_movement loop backward in every
#    posture, round-tripping velocity through the wire quantization (the online
#    reconcile snap) every tick, and asserts velocity/position never go NaN/Inf.

func _is_finite_v3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

# Mirror of WorldStateCodec velocity quantization (encode *50 round, decode /50).
func _quantize_vel(v: Vector3) -> Vector3:
	return Vector3(
		clampi(roundi(v.x * 50.0), -32768, 32767) / 50.0,
		clampi(roundi(v.y * 50.0), -32768, 32767) / 50.0,
		clampi(roundi(v.z * 50.0), -32768, 32767) / 50.0)

func test_zero_vector_normalized_behavior() -> void:
	var n: Vector2 = Vector2.ZERO.normalized()
	gut.p("Vector2.ZERO.normalized() = %s  is_finite=%s" % [n, is_finite(n.x) and is_finite(n.y)])
	# Godot 4 returns Vector2.ZERO for a zero-length normalize (no NaN).
	assert_true(is_finite(n.x) and is_finite(n.y),
		"zero normalize should NOT be NaN in Godot 4")

func _cfg() -> SkaterMovementRules.MovementConfig:
	var cfg := SkaterMovementRules.MovementConfig.new()
	cfg.thrust = 10.5
	cfg.friction = 5.0
	cfg.friction_drag = 0.5
	cfg.max_speed = 8.0
	cfg.move_deadzone = 0.1
	cfg.stop_decel = 20.0
	cfg.reverse_skid_fraction = 0.75
	cfg.turn_accel = 9.0
	cfg.max_turn_rate = 6.0
	cfg.power_knee_speed = 3.0
	cfg.backward_max_speed_multiplier = 0.75
	cfg.puck_carry_speed_multiplier = 0.86
	cfg.backward_thrust_multiplier = 0.55
	cfg.crossover_thrust_multiplier = 0.75
	cfg.stance_grip_mult = 2.0
	cfg.stance_scrape = 1.0 / 3.0
	cfg.stance_stride_mult = 0.6
	cfg.stance_max_speed_mult = 0.85
	cfg.stance_shuffle_mult = 1.2
	cfg.commit_grip_mult = 0.6
	cfg.commit_stride_mult = 0.5
	return cfg

func test_backward_with_quantization_never_nan() -> void:
	var cfg := _cfg()
	var delta: float = 1.0 / 120.0
	# Facing forward (rotation_y = 0 → facing -Z). Backward input is +Z = (0, 1).
	var backward := Vector2(0, 1)
	for posture: SkaterMovementRules.Posture in [SkaterMovementRules.Posture.UPRIGHT,
			SkaterMovementRules.Posture.STANCE, SkaterMovementRules.Posture.COMMIT]:
		for has_puck: bool in [false, true]:
			_drive_backward(cfg, delta, backward, posture, has_puck)


func _drive_backward(cfg: SkaterMovementRules.MovementConfig, delta: float, backward: Vector2,
		posture: SkaterMovementRules.Posture, has_puck: bool) -> void:
	var velocity := Vector3.ZERO
	var position := Vector3.ZERO
	var all_finite: bool = true
	for i in range(2000):
		velocity = SkaterMovementRules.apply_movement(
			velocity, backward, 0.0, has_puck, false, delta, cfg, posture)
		# Every other tick, emulate the online reconcile: snap to the
		# wire-quantized server value (what LocalController.reconcile does).
		if i % 2 == 0:
			velocity = _quantize_vel(velocity)
		position += velocity * delta
		all_finite = all_finite and _is_finite_v3(velocity) and _is_finite_v3(position)
	assert_true(all_finite, "velocity/position stayed finite (posture=%d has_puck=%s)" % [posture, has_puck])
	var spd: float = Vector2(velocity.x, velocity.z).length()
	assert_lte(spd, cfg.max_speed + 0.5,
		"backward speed stays bounded by the cap (posture=%d has_puck=%s)" % [posture, has_puck])

func test_stance_release_over_cap_then_backward_never_nan() -> void:
	# Build forward speed upright, drop into the stance over its cap, then
	# reverse — exercises the "preserve over-max" branch in both directions.
	var cfg := _cfg()
	var delta: float = 1.0 / 120.0
	var velocity := Vector3.ZERO
	# Forward (input (0,-1)) to the upright cap.
	for i in range(600):
		velocity = SkaterMovementRules.apply_movement(
			velocity, Vector2(0, -1), 0.0, false, false, delta, cfg)
		velocity = _quantize_vel(velocity)
	# Now reverse in the stance, quantizing each tick.
	var all_finite: bool = true
	for i in range(600):
		velocity = SkaterMovementRules.apply_movement(
			velocity, Vector2(0, 1), 0.0, false, false, delta, cfg,
			SkaterMovementRules.Posture.STANCE)
		velocity = _quantize_vel(velocity)
		all_finite = all_finite and _is_finite_v3(velocity)
	assert_true(all_finite, "velocity stayed finite through over-cap reverse")

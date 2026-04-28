class_name SkaterMovementRules

# Pure movement math extracted from SkaterController._apply_movement.
# Takes current state + input + tuning config, returns the new velocity.
# The caller (SkaterController) still owns the state machine guard (slapper
# charge windup, etc.); this function just does the physics.

class MovementConfig:
	var thrust: float = 0.0                      # forward thrust magnitude
	var friction: float = 0.0                    # base friction applied each tick
	var max_speed: float = 0.0                   # maximum horizontal speed
	var move_deadzone: float = 0.0               # stick deadzone
	var brake_multiplier: float = 0.0            # friction multiplier when braking
	var puck_carry_speed_multiplier: float = 0.0 # max speed reduction while carrying
	var backward_thrust_multiplier: float = 0.0  # thrust scale when moving against facing
	var crossover_thrust_multiplier: float = 0.0 # thrust scale when moving perpendicular to facing
	var friction_drag: float = 0.0               # velocity-proportional drag coefficient (m/s² per m/s)

static func apply_movement(
		current_velocity: Vector3,
		move_input: Vector2,
		facing_rotation_y: float,
		has_puck: bool,
		brake: bool,
		delta: float,
		cfg: MovementConfig) -> Vector3:
	var velocity: Vector3 = current_velocity

	if not brake and move_input.length() > cfg.move_deadzone:
		# NORMAL: apply thrust in the input direction, scaled by facing alignment.
		var thrust_dir := Vector3(move_input.x, 0.0, move_input.y)
		var facing_dir := Vector2(-sin(facing_rotation_y), -cos(facing_rotation_y))
		var move_dot: float = facing_dir.dot(move_input.normalized())

		var thrust_scale: float
		if move_dot >= 0.0:
			thrust_scale = lerpf(cfg.crossover_thrust_multiplier, 1.0, move_dot)
		else:
			thrust_scale = lerpf(cfg.backward_thrust_multiplier, cfg.crossover_thrust_multiplier, move_dot + 1.0)

		velocity += thrust_dir * cfg.thrust * thrust_scale * delta

		# Speed cap — but preserve over-max speed from external sources (body
		# check boost, etc.) so we don't instantly clamp a legitimate momentum gain.
		var effective_max: float = cfg.max_speed * cfg.puck_carry_speed_multiplier if has_puck else cfg.max_speed
		var horiz := Vector2(velocity.x, velocity.z)
		var speed: float = horiz.length()
		if speed > effective_max:
			var pre_thrust_speed: float = Vector2(
				velocity.x - thrust_dir.x * cfg.thrust * thrust_scale * delta,
				velocity.z - thrust_dir.z * cfg.thrust * thrust_scale * delta
			).length()
			var target_speed: float = maxf(pre_thrust_speed, effective_max)
			if speed > target_speed:
				var limited: Vector2 = horiz.normalized() * target_speed
				velocity.x = limited.x
				velocity.z = limited.y

	# Friction: heavy when braking (regardless of direction input), normal otherwise.
	var horiz_vel := Vector2(velocity.x, velocity.z)
	var base_decel: float = cfg.friction + cfg.friction_drag * horiz_vel.length()
	var effective_friction: float = base_decel * cfg.brake_multiplier if brake else base_decel
	horiz_vel = horiz_vel.move_toward(Vector2.ZERO, effective_friction * delta)
	velocity.x = horiz_vel.x
	velocity.z = horiz_vel.y
	return velocity

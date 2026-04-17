class_name ShotMechanics

# Pure shot-release math. Callers gather world/local positions and pass them in;
# these functions compute direction + power without touching the engine.
#
# Returns a Dictionary with keys:
#   direction: Vector3 — normalized, includes Y if elevated
#   power: float       — final shot power after backhand penalty / charge curve

# Wrister release. Quick shots (very short charge) aim along player→blade —
# the blade tracks the cursor via IK but ROM constraints prevent it going
# behind the player, so this direction is always valid. Full wristers aim
# from the drag direction with power scaling over the charge distance.
# Backhand is detected by comparing blade position to shoulder position in
# local space and penalised by a coefficient.
#
# Config keys (floats):
#   min_wrister_power, max_wrister_power, max_wrister_charge_distance,
#   backhand_power_coefficient, quick_shot_power, quick_shot_threshold,
#   wrister_elevation
static func release_wrister(
		player_pos: Vector3,
		mouse_world_pos: Vector3,
		blade_world_pos: Vector3,
		blade_local_pos: Vector3,
		shoulder_local_pos: Vector3,
		is_left_handed: bool,
		is_elevated: bool,
		charge_distance: float,
		cfg: Dictionary,
		charge_direction: Vector3 = Vector3.ZERO) -> Dictionary:
	var target := Vector3(mouse_world_pos.x, 0.0, mouse_world_pos.z)
	var charge_t: float = clampf(charge_distance / cfg.max_wrister_charge_distance, 0.0, 1.0)

	if charge_t < cfg.quick_shot_threshold:
		# Quick shot — aim player→blade. The blade tracks the cursor via IK so
		# aim is accurate, and ROM constraints mean the blade can never be behind
		# the player, so this direction can't flip backward when the cursor is.
		var player_xz := Vector3(player_pos.x, 0.0, player_pos.z)
		var blade_xz := Vector3(blade_world_pos.x, 0.0, blade_world_pos.z)
		var dir: Vector3 = (blade_xz - player_xz).normalized()
		if dir.length_squared() < 0.0001:
			dir = (target - player_xz).normalized()
		return {
			"direction": Vector3(dir.x, cfg.wrister_elevation if is_elevated else 0.0, dir.z).normalized(),
			"power": cfg.quick_shot_power,
		}

	# Full wrister — shot goes where the blade was dragged, power scales with charge.
	# charge_direction is the world-space direction the blade was sweeping at release;
	# fall back to player→mouse only when no drag direction is available.
	var shot_dir: Vector3
	if charge_direction.length_squared() > 0.0001:
		shot_dir = Vector3(charge_direction.x, 0.0, charge_direction.z).normalized()
	else:
		var player_xz := Vector3(player_pos.x, 0.0, player_pos.z)
		shot_dir = (target - player_xz).normalized()
	var power: float = lerpf(cfg.min_wrister_power, cfg.max_wrister_power, charge_t)

	var hand_sign: float = -1.0 if is_left_handed else 1.0
	var is_backhand: bool = sign(blade_local_pos.x - shoulder_local_pos.x) != sign(hand_sign)
	if is_backhand:
		power *= cfg.backhand_power_coefficient

	var y: float = cfg.wrister_elevation if is_elevated else 0.0
	return {
		"direction": Vector3(shot_dir.x, y, shot_dir.z).normalized(),
		"power": power,
	}

# Slapper release — power scales linearly with charge time.
#
# Config keys: min_slapper_power, max_slapper_power, max_slapper_charge_time,
#              slapper_elevation
#
# shot_direction: when non-zero, used as the shot direction directly (locked
# at press time); falls back to blade→mouse when zero (backwards compat).
static func release_slapper(
		blade_world_pos: Vector3,
		mouse_world_pos: Vector3,
		is_elevated: bool,
		charge_time: float,
		cfg: Dictionary,
		shot_direction: Vector3 = Vector3.ZERO) -> Dictionary:
	var shot_dir: Vector3
	if shot_direction.length_squared() > 0.0001:
		shot_dir = Vector3(shot_direction.x, 0.0, shot_direction.z).normalized()
	else:
		var blade_xz := Vector3(blade_world_pos.x, 0.0, blade_world_pos.z)
		var target := Vector3(mouse_world_pos.x, 0.0, mouse_world_pos.z)
		shot_dir = (target - blade_xz).normalized()
	var charge_t: float = clampf(charge_time / cfg.max_slapper_charge_time, 0.0, 1.0)
	var power: float = lerpf(cfg.min_slapper_power, cfg.max_slapper_power, charge_t)
	var y: float = cfg.slapper_elevation if is_elevated else 0.0
	return {
		"direction": Vector3(shot_dir.x, y, shot_dir.z).normalized(),
		"power": power,
	}

# Should a blade-in-wall squeeze auto-release the puck? Pure threshold check.
static func should_release_on_wall_pin(squeeze: float, threshold: float) -> bool:
	return squeeze > threshold

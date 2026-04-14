class_name ShotMechanics

# Pure shot-release math. Callers gather world/local positions and pass them in;
# these functions compute direction + power without touching the engine.
#
# Returns a Dictionary with keys:
#   direction: Vector3 — normalized, includes Y if elevated
#   power: float       — final shot power after backhand penalty / charge curve

# Wrister release. Quick shots (very short charge) aim from the blade itself at
# reduced power; full wristers aim from the player position with power scaling
# to max over the full charge distance. Backhand is detected by comparing blade
# position to shoulder position in local space and penalised by a coefficient.
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
		cfg: Dictionary) -> Dictionary:
	var target := Vector3(mouse_world_pos.x, 0.0, mouse_world_pos.z)
	var charge_t: float = clampf(charge_distance / cfg.max_wrister_charge_distance, 0.0, 1.0)

	if charge_t < cfg.quick_shot_threshold:
		# Quick shot — aim from the blade, fixed low power.
		var blade_xz := Vector3(blade_world_pos.x, 0.0, blade_world_pos.z)
		var dir: Vector3 = (target - blade_xz).normalized()
		var y: float = cfg.wrister_elevation if is_elevated else 0.0
		return {
			"direction": Vector3(dir.x, y, dir.z).normalized(),
			"power": cfg.quick_shot_power,
		}

	# Full wrister — aim from player, power scales with charge.
	var player_xz := Vector3(player_pos.x, 0.0, player_pos.z)
	var shot_dir: Vector3 = (target - player_xz).normalized()
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
static func release_slapper(
		blade_world_pos: Vector3,
		mouse_world_pos: Vector3,
		is_elevated: bool,
		charge_time: float,
		cfg: Dictionary) -> Dictionary:
	var blade_xz := Vector3(blade_world_pos.x, 0.0, blade_world_pos.z)
	var target := Vector3(mouse_world_pos.x, 0.0, mouse_world_pos.z)
	var shot_dir: Vector3 = (target - blade_xz).normalized()
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

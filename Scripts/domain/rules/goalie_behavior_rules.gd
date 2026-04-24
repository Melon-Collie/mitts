class_name GoalieBehaviorRules

# Pure goalie AI math. Callers pass tracked puck state + geometry; these
# functions return classifications and targets. The Buckley-style depth
# chart and shot detection live here so we can test them without a scene.
#
# direction_sign convention (matches GoalieController: sign(-goal_line_z)):
#   -1  goalie defends the +Z goal (goal_line_z = +GOAL_LINE_Z)
#   +1  goalie defends the -Z goal (goal_line_z = -GOAL_LINE_Z)
# "Behind goal" therefore means:
#   (puck_z - goal_line_z) * direction_sign < 0

class ShotResult:
	var is_shot: bool = false
	var reaction_delay: float = 0.0
	var impact_x: float = 0.0
	var impact_y: float = 0.0
	var is_low: bool = false      # impact_y < low_shot_threshold
	var is_elevated: bool = false # impact_y >= elevated_threshold

class ShotDetectionConfig:
	var shot_speed_threshold: float = 0.0
	var net_half_width: float = 0.0
	var net_margin: float = 0.0
	var reaction_delay: float = 0.0
	var low_shot_threshold: float = 0.0
	var elevated_threshold: float = 0.0

class DefensiveZoneConfig:
	var zone_post_z: float = 0.0
	var rvh_early_angle: float = 0.0  # degrees

class DepthConfig:
	var zone_post_z: float = 0.0
	var zone_aggressive_z: float = 0.0
	var zone_base_z: float = 0.0
	var zone_conservative_z: float = 0.0
	var depth_aggressive: float = 0.0
	var depth_base: float = 0.0
	var depth_conservative: float = 0.0
	var depth_defensive: float = 0.0

class PressureConfig:
	var pressure_butterfly_distance: float = 0.0
	var pressure_velocity_threshold: float = 0.0
	var pressure_lateral_margin: float = 0.0
	var net_half_width: float = 0.0

class ShotIntentConfig:
	var shot_intent_max_distance: float = 18.0
	var shot_intent_commit_close: float = 0.55
	var shot_intent_commit_mid: float = 0.75
	var shot_intent_commit_far: float = 0.90

# Is a released puck on course to hit this goalie's net? Returns a ShotResult.
# is_shot == false means not on net or below fake_threshold.
static func detect_shot(
		puck_position: Vector3,
		puck_velocity: Vector3,
		goal_line_z: float,
		goal_center_x: float,
		cfg: ShotDetectionConfig) -> ShotResult:
	var result := ShotResult.new()
	if puck_velocity.length() < cfg.shot_speed_threshold:
		return result
	if abs(puck_velocity.z) < 0.001:
		return result
	var t_to_goal: float = (goal_line_z - puck_position.z) / puck_velocity.z
	if t_to_goal <= 0.0:
		return result
	var impact_x: float = puck_position.x + puck_velocity.x * t_to_goal
	var impact_y: float = puck_position.y + puck_velocity.y * t_to_goal
	if abs(impact_x - goal_center_x) > cfg.net_half_width + cfg.net_margin:
		return result
	result.is_shot = true
	result.reaction_delay = cfg.reaction_delay
	result.impact_x = impact_x
	result.impact_y = impact_y
	result.is_low = impact_y < cfg.low_shot_threshold
	result.is_elevated = impact_y >= cfg.elevated_threshold
	return result

# Defensive zone — either behind the goal line or within zone_post_z at a
# sharp horizontal angle. Triggers RVH post-hug.
static func is_puck_in_defensive_zone(
		puck_position: Vector3,
		goal_line_z: float,
		goal_center_x: float,
		direction_sign: int,
		cfg: DefensiveZoneConfig) -> bool:
	var behind_goal: bool = (puck_position.z - goal_line_z) * direction_sign < 0.0
	if behind_goal:
		return true
	var puck_z_dist: float = abs(puck_position.z - goal_line_z)
	if puck_z_dist > cfg.zone_post_z:
		return false
	var puck_angle: float = atan2(abs(puck_position.x - goal_center_x), maxf(puck_z_dist, 0.01))
	return puck_angle >= deg_to_rad(cfg.rvh_early_angle)

# Buckley-chart target depth given horizontal distance from the goal line.
# Piecewise-linear interpolation across four zones. Callers smooth toward
# this target with their own lerp speed.
static func target_depth_for_puck_distance(puck_z_dist: float, cfg: DepthConfig) -> float:
	var t: float
	if puck_z_dist <= cfg.zone_post_z:
		t = puck_z_dist / cfg.zone_post_z
		return lerpf(cfg.depth_defensive, cfg.depth_aggressive, t)
	if puck_z_dist <= cfg.zone_aggressive_z:
		return cfg.depth_aggressive
	if puck_z_dist <= cfg.zone_base_z:
		t = (puck_z_dist - cfg.zone_aggressive_z) / (cfg.zone_base_z - cfg.zone_aggressive_z)
		return lerpf(cfg.depth_aggressive, cfg.depth_base, t)
	if puck_z_dist <= cfg.zone_conservative_z:
		t = (puck_z_dist - cfg.zone_base_z) / (cfg.zone_conservative_z - cfg.zone_base_z)
		return lerpf(cfg.depth_base, cfg.depth_conservative, t)
	t = clampf((puck_z_dist - cfg.zone_conservative_z) / cfg.zone_conservative_z, 0.0, 1.0)
	return lerpf(cfg.depth_conservative, cfg.depth_defensive, t)

# Should the goalie drop to butterfly preemptively? True when puck is close to
# the net and approaching with enough forward velocity (catches skaters charging
# in regardless of whether a shot has been released).
static func is_under_pressure(
		puck_position: Vector3,
		puck_approach_velocity: float,
		goal_line_z: float,
		goal_center_x: float,
		cfg: PressureConfig) -> bool:
	if abs(puck_position.z - goal_line_z) > cfg.pressure_butterfly_distance:
		return false
	if abs(puck_position.x - goal_center_x) > cfg.net_half_width + cfg.pressure_lateral_margin:
		return false
	return puck_approach_velocity >= cfg.pressure_velocity_threshold

# Arc-based positioning: returns (x, z) point on a circle of radius current_depth
# centered at the goal center, along the ray from goal center to puck.
# Replaces the angle-bisector depth-plane intersection for STANDING lateral target.
# The goalie's Z now varies with puck angle instead of staying on a flat plane.
static func target_position_on_arc(
		puck_position: Vector3,
		goal_line_z: float,
		goal_center_x: float,
		current_depth: float,
		net_half_width: float,
		direction_sign: int) -> Vector2:
	var gc := Vector2(goal_center_x, goal_line_z)
	var p  := Vector2(puck_position.x, puck_position.z)
	var dir := p - gc
	if dir.length() < 0.001:
		return Vector2(goal_center_x, goal_line_z + direction_sign * current_depth)
	dir = dir.normalized()
	var arc_point := gc + dir * current_depth
	arc_point.x = clampf(arc_point.x, goal_center_x - net_half_width, goal_center_x + net_half_width)
	return arc_point

# Shot intent score: 0.0 (no intent) → 1.0 (imminent shot).
# carrier_stick_load: 0.0–1.0 if available, -1.0 to use velocity fallback.
# Returns 0.0 immediately when intent scoring is disabled or no carrier.
static func compute_shot_intent(
		carrier_position: Vector3,
		carrier_rotation_y: float,
		carrier_velocity: Vector3,
		carrier_stick_load: float,
		puck_position: Vector3,
		goal_line_z: float,
		goal_center_x: float,
		cfg: ShotIntentConfig) -> float:
	var distance_to_net: float = abs(puck_position.z - goal_line_z)
	if distance_to_net > cfg.shot_intent_max_distance:
		return 0.0
	var to_net_v := Vector2(goal_center_x - carrier_position.x, goal_line_z - carrier_position.z)
	if to_net_v.length() < 0.001:
		return 0.0
	var to_net := to_net_v.normalized()
	var facing := Vector2(-sin(carrier_rotation_y), -cos(carrier_rotation_y))
	var facing_dot: float = facing.dot(to_net)
	if facing_dot < 0.3:
		return 0.0
	var facing_score: float = smoothstep(0.3, 0.85, facing_dot)
	var stick_score: float
	if carrier_stick_load >= 0.0:
		stick_score = carrier_stick_load
	else:
		var vel_xz := Vector2(carrier_velocity.x, carrier_velocity.z)
		stick_score = clampf(vel_xz.normalized().dot(to_net) if vel_xz.length() > 0.001 else 0.0, 0.0, 1.0)
	var distance_score: float = 1.0 - smoothstep(6.0, cfg.shot_intent_max_distance, distance_to_net)
	return facing_score * 0.4 + stick_score * 0.4 + distance_score * 0.2

# Commit threshold for butterfly drop given puck distance to net.
static func shot_intent_commit_threshold(puck_z_dist: float, cfg: ShotIntentConfig) -> float:
	if puck_z_dist < 6.0:
		return cfg.shot_intent_commit_close
	if puck_z_dist < 9.0:
		return cfg.shot_intent_commit_mid
	return cfg.shot_intent_commit_far

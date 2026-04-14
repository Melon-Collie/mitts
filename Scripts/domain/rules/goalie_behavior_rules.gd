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

# Is a released puck on course to hit this goalie's net? If so, return the
# reaction_delay to arm a butterfly-drop timer. Returns -1.0 if not a shot.
# Config keys: shot_speed_threshold, net_half_width, net_margin, reaction_delay
static func detect_shot(
		puck_position: Vector3,
		puck_velocity: Vector3,
		goal_line_z: float,
		goal_center_x: float,
		cfg: Dictionary) -> float:
	if puck_velocity.length() < cfg.shot_speed_threshold:
		return -1.0
	if abs(puck_velocity.z) < 0.001:
		return -1.0
	var t_to_goal: float = (goal_line_z - puck_position.z) / puck_velocity.z
	if t_to_goal <= 0.0:
		return -1.0
	var projected_x: float = puck_position.x + puck_velocity.x * t_to_goal
	if abs(projected_x - goal_center_x) > cfg.net_half_width + cfg.net_margin:
		return -1.0
	return cfg.reaction_delay

# Defensive zone — either behind the goal line or within zone_post_z at a
# sharp horizontal angle. Triggers RVH post-hug.
# Config keys: zone_post_z, rvh_early_angle (degrees)
static func is_puck_in_defensive_zone(
		puck_position: Vector3,
		goal_line_z: float,
		goal_center_x: float,
		direction_sign: int,
		cfg: Dictionary) -> bool:
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
# Config keys: zone_post_z, zone_aggressive_z, zone_base_z, zone_conservative_z,
#              depth_aggressive, depth_base, depth_conservative, depth_defensive
static func target_depth_for_puck_distance(puck_z_dist: float, cfg: Dictionary) -> float:
	if puck_z_dist <= cfg.zone_post_z:
		var t: float = puck_z_dist / cfg.zone_post_z
		return lerpf(cfg.depth_defensive, cfg.depth_aggressive, t)
	if puck_z_dist <= cfg.zone_aggressive_z:
		return cfg.depth_aggressive
	if puck_z_dist <= cfg.zone_base_z:
		var t: float = (puck_z_dist - cfg.zone_aggressive_z) / (cfg.zone_base_z - cfg.zone_aggressive_z)
		return lerpf(cfg.depth_aggressive, cfg.depth_base, t)
	if puck_z_dist <= cfg.zone_conservative_z:
		var t: float = (puck_z_dist - cfg.zone_base_z) / (cfg.zone_conservative_z - cfg.zone_base_z)
		return lerpf(cfg.depth_base, cfg.depth_conservative, t)
	var t: float = clampf((puck_z_dist - cfg.zone_conservative_z) / cfg.zone_conservative_z, 0.0, 1.0)
	return lerpf(cfg.depth_conservative, cfg.depth_defensive, t)

# Lateral X target — project the puck onto the goalie's current depth along
# the shot line, clamped to the net width so we never stray past a post.
static func target_lateral_x(
		puck_position: Vector3,
		goal_line_z: float,
		goal_center_x: float,
		current_depth: float,
		net_half_width: float) -> float:
	var puck_z_dist: float = abs(puck_position.z - goal_line_z)
	var target_x: float
	if puck_z_dist > 0.01:
		target_x = goal_center_x + (puck_position.x - goal_center_x) * (current_depth / puck_z_dist)
	else:
		target_x = goal_center_x
	return clampf(target_x, goal_center_x - net_half_width, goal_center_x + net_half_width)

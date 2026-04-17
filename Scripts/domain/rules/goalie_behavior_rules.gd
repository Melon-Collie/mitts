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
	var fake_threshold: float = 0.0
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
	if puck_velocity.length() < cfg.fake_threshold:
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

# Lateral X target using angle bisector: find the line from the puck that
# bisects the shooting angle between the two posts, then intersect it with
# the goalie's depth plane. This maximises net coverage from the goalie's
# position rather than simply projecting the puck's X onto the depth plane.
# direction_sign: sign(-goal_line_z) — determines which side of the goal
# the goalie stands on (same convention as GoalieController._direction_sign).
static func target_lateral_x(
		puck_position: Vector3,
		goal_line_z: float,
		goal_center_x: float,
		current_depth: float,
		net_half_width: float,
		direction_sign: int) -> float:
	var px: float = puck_position.x
	var pz: float = puck_position.z
	var left_x: float  = goal_center_x - net_half_width
	var right_x: float = goal_center_x + net_half_width

	# 2D (XZ) vectors from puck to each post.
	var dlx: float = left_x  - px
	var dlz: float = goal_line_z - pz
	var drx: float = right_x - px
	var drz: float = goal_line_z - pz   # same Z for both posts

	var dl: float = sqrt(dlx * dlx + dlz * dlz)
	var dr: float = sqrt(drx * drx + drz * drz)
	if dl < 0.001 or dr < 0.001:
		return goal_center_x

	# Angle bisector direction (sum of unit vectors to each post).
	var bx: float = dlx / dl + drx / dr
	var bz: float = dlz / dl + drz / dr
	var blen: float = sqrt(bx * bx + bz * bz)
	if blen < 0.001:
		return goal_center_x   # perfectly centred — bisector undefined, stay put

	bx /= blen
	bz /= blen

	# Intersect the bisector ray with the goalie's depth plane.
	if abs(bz) < 0.001:
		return clampf(px, left_x, right_x)
	var goalie_z: float = goal_line_z + direction_sign * current_depth
	var t: float = (goalie_z - pz) / bz
	if t <= 0.0:
		return clampf(px, left_x, right_x)

	return clampf(px + bx * t, left_x, right_x)

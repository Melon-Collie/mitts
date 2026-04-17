extends GutTest

# GoalieBehaviorRules — shot detection, defensive zone, Buckley depth chart,
# lateral X projection.

func _shot_cfg() -> GoalieBehaviorRules.ShotDetectionConfig:
	var cfg := GoalieBehaviorRules.ShotDetectionConfig.new()
	cfg.shot_speed_threshold = 5.0
	cfg.net_half_width = 0.915
	cfg.net_margin = 1.0
	cfg.reaction_delay = 0.10
	cfg.low_shot_threshold = 0.45
	cfg.elevated_threshold = 0.45
	cfg.fake_threshold = 0.0
	return cfg

func _zone_cfg() -> GoalieBehaviorRules.DefensiveZoneConfig:
	var cfg := GoalieBehaviorRules.DefensiveZoneConfig.new()
	cfg.zone_post_z = 2.0
	cfg.rvh_early_angle = 60.0
	return cfg

func _depth_cfg() -> GoalieBehaviorRules.DepthConfig:
	var cfg := GoalieBehaviorRules.DepthConfig.new()
	cfg.zone_post_z = 2.0
	cfg.zone_aggressive_z = 8.0
	cfg.zone_base_z = 12.0
	cfg.zone_conservative_z = 20.0
	cfg.depth_aggressive = 1.2
	cfg.depth_base = 0.6
	cfg.depth_conservative = 0.3
	cfg.depth_defensive = 0.1
	return cfg

# ── detect_shot ──────────────────────────────────────────────────────────────

func test_slow_puck_not_a_shot() -> void:
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
		Vector3(0, 0, 10), Vector3(0, 0, -1),   # below threshold
		26.6, 0.0, _shot_cfg())
	assert_false(result.is_shot)

func test_fast_puck_on_target_is_shot() -> void:
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
		Vector3(0, 0, 10), Vector3(0, 0, 20),   # heading toward +Z goal
		26.6, 0.0, _shot_cfg())
	assert_true(result.is_shot)
	assert_almost_eq(result.reaction_delay, 0.10, 0.001)

func test_fast_puck_moving_away_not_a_shot() -> void:
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
		Vector3(0, 0, 10), Vector3(0, 0, -20),  # away from +Z goal
		26.6, 0.0, _shot_cfg())
	assert_false(result.is_shot)

func test_fast_puck_wide_of_post_not_a_shot() -> void:
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
		Vector3(10, 0, 10), Vector3(10, 0, 5),  # drifting wider as it travels
		26.6, 0.0, _shot_cfg())
	assert_false(result.is_shot)

func test_shot_classifies_low() -> void:
	# Puck at z=10, velocity (0, 0, 20) — no Y component, impact_y ≈ 0
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
		Vector3(0, 0, 10), Vector3(0, 0, 20),
		26.6, 0.0, _shot_cfg())
	assert_true(result.is_shot)
	assert_true(result.is_low)
	assert_false(result.is_elevated)

func test_shot_classifies_elevated() -> void:
	# Puck with upward velocity — impact_y should be > 0.45
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
		Vector3(0, 0.05, 10), Vector3(0, 6.0, 20),
		26.6, 0.0, _shot_cfg())
	assert_true(result.is_shot)
	assert_false(result.is_low)
	assert_true(result.is_elevated)

func test_shot_impact_x_projects_correctly() -> void:
	# Puck at x=0, z=10; velocity (5, 0, 20) — drifting right.
	# t_to_goal = (26.6 - 10) / 20 = 0.83s; impact_x = 0 + 5 * 0.83 = 4.15 → wide, not a shot
	# Use smaller X drift to stay on net:
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
		Vector3(0, 0, 10), Vector3(0.5, 0, 20),
		26.6, 0.0, _shot_cfg())
	assert_true(result.is_shot)
	# impact_x = 0 + 0.5 * (16.6/20) = 0.415
	assert_almost_eq(result.impact_x, 0.415, 0.01)

func test_fake_threshold_suppresses_reaction() -> void:
	var cfg: GoalieBehaviorRules.ShotDetectionConfig = _shot_cfg()
	cfg.fake_threshold = 25.0  # above the shot speed
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
		Vector3(0, 0, 10), Vector3(0, 0, 20),
		26.6, 0.0, cfg)
	assert_false(result.is_shot)

# ── is_puck_in_defensive_zone ────────────────────────────────────────────────
# direction_sign = sign(-goal_line_z), so for goalie at +Z (goal_line=+26.6)
# direction_sign = -1. Puck "behind" the goalie means z > goal_line_z.

func test_puck_behind_goal_in_defensive_zone() -> void:
	# Goalie defends +Z goal, puck past the goal line at z=28
	assert_true(GoalieBehaviorRules.is_puck_in_defensive_zone(
		Vector3(0, 0, 28), 26.6, 0.0, -1, _zone_cfg()))

func test_puck_far_from_goal_not_in_defensive_zone() -> void:
	assert_false(GoalieBehaviorRules.is_puck_in_defensive_zone(
		Vector3(0, 0, 10), 26.6, 0.0, -1, _zone_cfg()))

func test_puck_near_post_sharp_angle_in_defensive_zone() -> void:
	# Close in z (puck_z_dist = 1.1), offset in x (3) → angle ≈ 70° > 60°
	assert_true(GoalieBehaviorRules.is_puck_in_defensive_zone(
		Vector3(3, 0, 25.5), 26.6, 0.0, -1, _zone_cfg()))

func test_puck_near_post_shallow_angle_not_in_defensive_zone() -> void:
	# Close in z (1.1), small X offset (0.3) → angle ≈ 15° < 60°
	assert_false(GoalieBehaviorRules.is_puck_in_defensive_zone(
		Vector3(0.3, 0, 25.5), 26.6, 0.0, -1, _zone_cfg()))

func test_puck_behind_negative_z_goal() -> void:
	# Opposite-side goalie: defends -Z (goal_line=-26.6), direction_sign=+1.
	# Puck "behind" means z < -26.6.
	assert_true(GoalieBehaviorRules.is_puck_in_defensive_zone(
		Vector3(0, 0, -28), -26.6, 0.0, 1, _zone_cfg()))

# ── target_depth_for_puck_distance ───────────────────────────────────────────

func test_depth_at_zone_post_reaches_aggressive() -> void:
	var d: float = GoalieBehaviorRules.target_depth_for_puck_distance(
		_depth_cfg().zone_post_z, _depth_cfg())
	assert_almost_eq(d, _depth_cfg().depth_aggressive, 0.001)

func test_depth_inside_aggressive_zone_stays_aggressive() -> void:
	var d: float = GoalieBehaviorRules.target_depth_for_puck_distance(
		5.0,  # between zone_post_z and zone_aggressive_z
		_depth_cfg())
	assert_almost_eq(d, _depth_cfg().depth_aggressive, 0.001)

func test_depth_far_away_is_defensive() -> void:
	var d: float = GoalieBehaviorRules.target_depth_for_puck_distance(
		100.0, _depth_cfg())
	assert_almost_eq(d, _depth_cfg().depth_defensive, 0.001)

func test_depth_at_origin_is_defensive() -> void:
	# puck_z_dist = 0 → t = 0 → lerp(defensive, aggressive, 0) = defensive
	var d: float = GoalieBehaviorRules.target_depth_for_puck_distance(
		0.0, _depth_cfg())
	assert_almost_eq(d, _depth_cfg().depth_defensive, 0.001)

# ── target_lateral_x ─────────────────────────────────────────────────────────
# Goalie defends +Z goal: direction_sign = sign(-26.6) = -1

func test_lateral_x_clamps_to_net_width() -> void:
	var x: float = GoalieBehaviorRules.target_lateral_x(
		Vector3(100, 0, 10), 26.6, 0.0, 0.5, 0.915, -1)
	assert_true(x <= 0.916, "x=%f should be clamped to net_half_width" % x)

func test_lateral_x_centered_puck_returns_center() -> void:
	# Puck directly in front of goal, centred — bisector is straight ahead, target = 0.
	var x: float = GoalieBehaviorRules.target_lateral_x(
		Vector3(0, 0, 10), 26.6, 0.0, 1.0, 0.915, -1)
	assert_almost_eq(x, 0.0, 0.05)

func test_lateral_x_bisector_closer_to_near_post_on_angle() -> void:
	# Puck far to the right at (4, 0, 16) — bisector should place goalie
	# closer to the right post than simple X-projection would.
	var bisect_x: float = GoalieBehaviorRules.target_lateral_x(
		Vector3(4, 0, 16), 26.6, 0.0, 1.0, 0.915, -1)
	var simple_x: float = 0.0 + (4.0 - 0.0) * (1.0 / absf(16.0 - 26.6))  # old formula
	# Angle bisector pulls goalie further toward the near post than simple projection.
	assert_true(bisect_x > simple_x, "bisect=%f should exceed simple=%f on sharp angle" % [bisect_x, simple_x])
	assert_true(bisect_x <= 0.916)

func test_lateral_x_puck_at_goal_line_clamps_to_post() -> void:
	# Puck sitting at the goal line far to the right — goalie should hug that post.
	var x: float = GoalieBehaviorRules.target_lateral_x(
		Vector3(5, 0, 26.6), 26.6, 0.0, 1.0, 0.915, -1)
	assert_almost_eq(x, 0.915, 0.01)

extends GutTest

# CreaseRules — D-shape geometry for the goalie crease, used by PuckController
# to detect a puck stuck in the crease and shove it outward.

const _GOAL_Z: float = GameRules.GOAL_LINE_Z


# ── is_in_crease ──────────────────────────────────────────────────────────────

func test_center_ice_not_in_crease() -> void:
	assert_false(CreaseRules.is_in_crease(Vector2(0.0, 0.0)))


func test_neutral_zone_not_in_crease() -> void:
	assert_false(CreaseRules.is_in_crease(Vector2(0.0, 5.0)))


func test_inside_crease_team0_zone() -> void:
	# Just inside the crease on the +Z half (team 0 defends here).
	assert_true(CreaseRules.is_in_crease(Vector2(0.0, _GOAL_Z - 0.5)))


func test_inside_crease_team1_zone() -> void:
	assert_true(CreaseRules.is_in_crease(Vector2(0.0, -_GOAL_Z + 0.5)))


func test_inside_crease_offset_within_half_width() -> void:
	# 1.0m laterally — inside HALF_WIDTH (1.22). 0.5m inward — inside ARC_RADIUS.
	assert_true(CreaseRules.is_in_crease(Vector2(1.0, _GOAL_Z - 0.5)))


func test_behind_goal_line_not_in_crease() -> void:
	# Behind the goal line (in the net): outside the crease.
	assert_false(CreaseRules.is_in_crease(Vector2(0.0, _GOAL_Z + 0.5)))
	assert_false(CreaseRules.is_in_crease(Vector2(0.0, -_GOAL_Z - 0.5)))


func test_outside_arc_radius_not_in_crease() -> void:
	# 2.0m inward from goal line is past the 1.83m arc radius.
	assert_false(CreaseRules.is_in_crease(Vector2(0.0, _GOAL_Z - 2.0)))


func test_outside_half_width_not_in_crease() -> void:
	# X = 1.5m exceeds HALF_WIDTH (1.22), even close to the goal line.
	assert_false(CreaseRules.is_in_crease(Vector2(1.5, _GOAL_Z - 0.3)))


func test_corner_case_at_arc_boundary_inside() -> void:
	# At exactly the arc radius the point counts as inside (<=).
	assert_true(CreaseRules.is_in_crease(Vector2(0.0, _GOAL_Z - CreaseRules.ARC_RADIUS)))


# ── outward_direction ─────────────────────────────────────────────────────────

func test_outward_direction_team0_points_toward_center_ice() -> void:
	# Puck on the +Z (team 0) side; outward direction must have negative Z
	# (away from the +Z goal, toward center ice).
	var dir: Vector2 = CreaseRules.outward_direction(Vector2(0.0, _GOAL_Z - 0.5))
	assert_lt(dir.y, 0.0)


func test_outward_direction_team1_points_toward_center_ice() -> void:
	var dir: Vector2 = CreaseRules.outward_direction(Vector2(0.0, -_GOAL_Z + 0.5))
	assert_gt(dir.y, 0.0)


func test_outward_direction_unit_length() -> void:
	var dir: Vector2 = CreaseRules.outward_direction(Vector2(0.4, _GOAL_Z - 0.6))
	assert_almost_eq(dir.length(), 1.0, 0.001)


func test_outward_direction_at_goal_center_falls_back_to_center_ice() -> void:
	# Puck exactly at the goal center on the +Z side: degenerate; must still
	# return a valid unit vector pointing toward center ice.
	var dir: Vector2 = CreaseRules.outward_direction(Vector2(0.0, _GOAL_Z))
	assert_almost_eq(dir.length(), 1.0, 0.001)
	assert_lt(dir.y, 0.0)


func test_outward_direction_lateral_offset_pushes_outward() -> void:
	# Puck offset in +X from goal center: outward direction must have +X
	# component (away from goal center axis) and -Z component (toward center ice).
	var dir: Vector2 = CreaseRules.outward_direction(Vector2(0.8, _GOAL_Z - 0.4))
	assert_gt(dir.x, 0.0)
	assert_lt(dir.y, 0.0)

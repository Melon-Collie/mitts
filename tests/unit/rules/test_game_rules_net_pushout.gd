extends GutTest

# GameRules.push_out_of_net — analytic goal-net exclusion projection. Keeps a
# skater's body disc off the cage footprint, the open mouth included: the whole
# body stays in front of the goal line, and the posts are solid to it.
#
# Geometry under test (near/positive-Z net), every face inset by `radius`:
#   GOAL_LINE_Z          front face (open mouth) at |z| = GOAL_LINE_Z (− radius)
#   NET_DEPTH            back panel at |z| = GOAL_LINE_Z + NET_DEPTH (+ radius)
#   NET_BACK_HALF_WIDTH  side panels at |x| = NET_BACK_HALF_WIDTH (+ radius)
# with the corners rounded by `radius`.
#
# Derived from GameRules rather than restated as literals: test_net_geometry_mirrors
# is what pins those constants, so this file is free to test the projection alone.
# Restating them here meant a constant could move and leave this test asserting the
# old geometry against the new function.

const TOL: float = 0.001
const GOAL_Z: float = GameRules.GOAL_LINE_Z
const BACK_HW: float = GameRules.NET_BACK_HALF_WIDTH
const DEPTH: float = GameRules.NET_DEPTH

# ── Points outside the box are untouched ──────────────────────────────────────

func test_center_ice_unchanged() -> void:
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.0, 0.0))
	assert_almost_eq(r.x, 0.0, TOL, "x")
	assert_almost_eq(r.y, 0.0, TOL, "z")

func test_in_front_of_goal_line_unchanged() -> void:
	# A skater in the crease (in front of the goal line) must not be pushed.
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.0, 26.0))
	assert_almost_eq(r.x, 0.0, TOL, "x")
	assert_almost_eq(r.y, 26.0, TOL, "z unchanged (crease play untouched)")

func test_wide_of_net_unchanged() -> void:
	# A wraparound skater going around the net at |x| beyond the side panel.
	var r: Vector2 = GameRules.push_out_of_net(Vector2(1.5, 27.0))
	assert_almost_eq(r.x, 1.5, TOL, "x unchanged")
	assert_almost_eq(r.y, 27.0, TOL, "z unchanged")

func test_behind_net_unchanged() -> void:
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.0, 28.5))
	assert_almost_eq(r.x, 0.0, TOL, "x")
	assert_almost_eq(r.y, 28.5, TOL, "z unchanged (behind the net)")

# ── Inside the pocket → ejected along the nearest face ────────────────────────

func test_just_past_goal_line_ejected_to_mouth() -> void:
	# The reported case: shoved just across the goal line — front face is nearest,
	# so eject back out toward center ice (the open mouth).
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.0, 26.75))
	assert_almost_eq(r.x, 0.0, TOL, "x held")
	assert_almost_eq(r.y, GOAL_Z, TOL, "z ejected to goal line")

func test_deep_in_pocket_ejected_out_back() -> void:
	# Near the back panel — back face is nearest.
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.0, 27.6))
	assert_almost_eq(r.y, GOAL_Z + DEPTH, TOL, "z ejected to back face (radius 0)")

func test_near_side_panel_ejected_sideways() -> void:
	# Center deep enough that a side face is the nearest exit.
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.95, 27.15))
	assert_almost_eq(r.x, BACK_HW, TOL, "x ejected to +side face")
	assert_almost_eq(r.y, 27.15, TOL, "z held during a sideways eject")

func test_negative_side_ejects_negative() -> void:
	var r: Vector2 = GameRules.push_out_of_net(Vector2(-0.95, 27.15))
	assert_almost_eq(r.x, -BACK_HW, TOL, "x ejected to -side face")

# ── Radius insets every face, the mouth included ─────────────────────────────

func test_radius_insets_every_face() -> void:
	var radius: float = 0.35
	# Front (mouth): a body centred on the goal line is half inside the cage.
	var front: Vector2 = GameRules.push_out_of_net(Vector2(0.0, GOAL_Z), radius)
	assert_almost_eq(front.y, GOAL_Z - radius, TOL, "front face inset — body edge on the line")
	# Back panel inset by radius: the body edge stops at the back face, center at +r.
	var back: Vector2 = GameRules.push_out_of_net(Vector2(0.0, 27.9), radius)
	assert_almost_eq(back.y, GOAL_Z + DEPTH + radius, TOL, "back face inset by radius")
	# Side panel inset by radius.
	var side: Vector2 = GameRules.push_out_of_net(Vector2(1.3, 27.15), radius)
	assert_almost_eq(side.x, BACK_HW + radius, TOL, "side face inset by radius")


func test_crease_body_clear_of_the_line_is_untouched() -> void:
	var radius: float = 0.35
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.4, GOAL_Z - radius - 0.01), radius)
	assert_almost_eq(r.y, GOAL_Z - radius - 0.01, TOL, "edge short of the line — free")


func test_skating_along_the_goal_line_cannot_pass_through_the_posts() -> void:
	# The reported case: a body just in front of the line slid sideways from beside
	# the net, across the mouth and out the other side, through both posts. Every
	# sample along that line must come out with the body edge off the cage.
	var radius: float = 0.35
	for i: int in 41:
		var x: float = -2.0 + 0.1 * float(i)
		var p: Vector2 = GameRules.push_out_of_net(Vector2(x, GOAL_Z - 0.01), radius)
		var near := Vector2(clampf(p.x, -BACK_HW, BACK_HW), clampf(p.y, GOAL_Z, GOAL_Z + DEPTH))
		assert_gte(p.distance_to(near), radius - TOL,
				"body at x=%.1f overlaps the cage after the push" % x)


func test_corner_is_rounded() -> void:
	# Diagonally off the front corner, inside the inflated box but outside the
	# rounded one: untouched. Pushed in closer: out radially from the corner.
	var radius: float = 0.35
	var corner := Vector2(BACK_HW, GOAL_Z)
	var clear: Vector2 = corner + Vector2(0.3, -0.3)
	assert_eq(GameRules.push_out_of_net(clear, radius), clear,
			"0.42 m off the corner — clear of a 0.35 m body")
	var touching: Vector2 = corner + Vector2(0.2, -0.2)
	var out: Vector2 = GameRules.push_out_of_net(touching, radius)
	assert_almost_eq(out.distance_to(corner), radius, TOL, "pushed to the body radius off the corner")
	assert_almost_eq((out - corner).angle(), Vector2(1.0, -1.0).angle(), TOL, "radially")


# ── The far (negative-Z) net mirrors the near net ─────────────────────────────

func test_far_net_ejects_with_sign_preserved() -> void:
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.0, -26.75))
	assert_almost_eq(r.y, -GOAL_Z, TOL, "far net front eject keeps the -Z sign")

func test_far_net_front_untouched() -> void:
	var r: Vector2 = GameRules.push_out_of_net(Vector2(0.0, -26.0))
	assert_almost_eq(r.y, -26.0, TOL, "far crease untouched")

# ── net_proximity ─────────────────────────────────────────────────────────────
# The board_proximity analog for the net footprint: away-from-net normal scaled
# by closeness (0 at `probe` away → 1 against a panel), Euclidean closest-point,
# open mouth reports nothing.

func test_proximity_zero_far_from_net() -> void:
	assert_eq(GameRules.net_proximity(Vector2(0.0, 0.0), 2.0), Vector2.ZERO,
			"center ice — no net within probe")

func test_proximity_zero_in_front_of_the_mouth() -> void:
	assert_eq(GameRules.net_proximity(Vector2(0.0, 26.0), 2.0), Vector2.ZERO,
			"the mouth is open — a crease skater gets no report at any range")

func test_proximity_beside_the_net_points_away_laterally() -> void:
	# 1.0 m off the +x side panel with a 2.0 m probe → closeness 0.5, pure +x.
	var p: Vector2 = GameRules.net_proximity(Vector2(BACK_HW + 1.0, 27.0), 2.0)
	assert_almost_eq(p.x, 0.5, TOL, "half-probe from the side panel → closeness 0.5, +x")
	assert_almost_eq(p.y, 0.0, TOL, "pure lateral — no z component beside the panel")

func test_proximity_behind_the_net_points_out_back() -> void:
	# 0.5 m behind the back panel with a 2.0 m probe → closeness 0.75, +z.
	var p: Vector2 = GameRules.net_proximity(Vector2(0.0, GOAL_Z + DEPTH + 0.5), 2.0)
	assert_almost_eq(p.x, 0.0, TOL, "no lateral component dead behind the net")
	assert_almost_eq(p.y, 0.75, TOL, "quarter-probe gap → closeness 0.75, away out back")

func test_proximity_corner_is_euclidean() -> void:
	# Diagonally off the back corner: 0.6 right of the side, 0.8 past the back →
	# 1.0 m Euclidean. A face-distance box would report each axis separately.
	var p: Vector2 = GameRules.net_proximity(
			Vector2(BACK_HW + 0.6, GOAL_Z + DEPTH + 0.8), 2.0)
	assert_almost_eq(p.length(), 0.5, TOL, "1.0 m Euclidean on a 2.0 m probe → closeness 0.5")
	assert_almost_eq(p.angle(), Vector2(0.6, 0.8).angle(), TOL,
			"direction is the true corner diagonal")

func test_proximity_far_net_mirrors_sign() -> void:
	var p: Vector2 = GameRules.net_proximity(Vector2(0.0, -(GOAL_Z + DEPTH + 0.5)), 2.0)
	assert_almost_eq(p.y, -0.75, TOL, "far-net report points away in -z")

func test_proximity_zero_probe_is_silent() -> void:
	assert_eq(GameRules.net_proximity(Vector2(0.0, 28.0), 0.0), Vector2.ZERO,
			"zero probe never reports")

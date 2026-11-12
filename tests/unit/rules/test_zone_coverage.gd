extends GutTest

# AIZoneCoverage — the 5v5 D-zone geometry (plan §3/§5). Team 0 defends +Z
# (own_goal_z = GOAL_LINE_Z); depths are metres off that goal line into the zone.

const NET_Z: float = GameRules.GOAL_LINE_Z


func _pt(x: float, depth: float) -> Vector3:
	# World point at lateral x and depth off the defended (+Z) goal line.
	return Vector3(x, 0.0, NET_Z - depth)


# ── depth_of ─────────────────────────────────────────────────────────────────

func test_depth_measures_off_the_defended_goal_line() -> void:
	assert_almost_eq(AIZoneCoverage.depth_of(NET_Z, _pt(0.0, 0.0)), 0.0, 0.001)
	assert_almost_eq(AIZoneCoverage.depth_of(NET_Z, _pt(0.0, 10.0)), 10.0, 0.001)
	# Behind the goal line reads negative.
	assert_lt(AIZoneCoverage.depth_of(NET_Z, Vector3(0, 0, NET_Z + 2.0)), 0.0)
	# Mirrored net: same answer for team 1's zone.
	assert_almost_eq(AIZoneCoverage.depth_of(-NET_Z, Vector3(0, 0, -NET_Z + 5.0)),
			5.0, 0.001)


# ── pressure ownership: exactly one owner everywhere ─────────────────────────

func test_pressure_owner_by_region() -> void:
	var s: float = 1.0  # strong side = +X
	# Corner battle (strong side low) → strong D.
	assert_eq(AIZoneCoverage.pressure_owner(s, NET_Z, _pt(9.0, 3.0)),
			AIRoleSlots.Slot.ZONE_D_STRONG)
	# Behind the net → strong D (the low perimeter is his battle).
	assert_eq(AIZoneCoverage.pressure_owner(s, NET_Z, _pt(0.0, -1.5)),
			AIRoleSlots.Slot.ZONE_D_STRONG)
	# WEAK-side corner also belongs to the battle D (the strong sign flips
	# with the brain's hysteresis as the puck crosses).
	assert_eq(AIZoneCoverage.pressure_owner(s, NET_Z, _pt(-9.0, 3.0)),
			AIRoleSlots.Slot.ZONE_D_STRONG)
	# Net-front jam → the net-front box D.
	assert_eq(AIZoneCoverage.pressure_owner(s, NET_Z, _pt(0.5, 2.0)),
			AIRoleSlots.Slot.ZONE_D_WEAK)
	# Mid slot → the center.
	assert_eq(AIZoneCoverage.pressure_owner(s, NET_Z, _pt(1.0, 8.5)),
			AIRoleSlots.Slot.ZONE_C)
	# Strong point → strong winger.
	assert_eq(AIZoneCoverage.pressure_owner(s, NET_Z, _pt(7.0, 16.0)),
			AIRoleSlots.Slot.ZONE_W_STRONG)
	# Weak point → weak winger.
	assert_eq(AIZoneCoverage.pressure_owner(s, NET_Z, _pt(-7.0, 16.0)),
			AIRoleSlots.Slot.ZONE_W_WEAK)


func test_pressure_owner_is_unique_across_a_zone_sweep() -> void:
	# Every point in the zone maps to exactly one owner (a total function —
	# the match can't return two, so this asserts it's one of the five
	# and never crashes across the sweep).
	var zone_roles: Array[int] = [
		AIRoleSlots.Slot.ZONE_D_STRONG, AIRoleSlots.Slot.ZONE_D_WEAK,
		AIRoleSlots.Slot.ZONE_C, AIRoleSlots.Slot.ZONE_W_STRONG,
		AIRoleSlots.Slot.ZONE_W_WEAK]
	for xi: int in range(-12, 13, 3):
		for di: int in range(-3, 19, 2):
			var owner_id: int = AIZoneCoverage.pressure_owner(
					1.0, NET_Z, _pt(float(xi), float(di)))
			assert_has(zone_roles, owner_id,
					"x=%d depth=%d has no owner" % [xi, di])


func test_every_house_point_is_inside_some_area() -> void:
	# The house (posts → dots → circle tops) must always be someone's
	# responsibility — no dead seam a net-front man can hide in.
	var zone_roles: Array[int] = [
		AIRoleSlots.Slot.ZONE_D_STRONG, AIRoleSlots.Slot.ZONE_D_WEAK,
		AIRoleSlots.Slot.ZONE_C, AIRoleSlots.Slot.ZONE_W_STRONG,
		AIRoleSlots.Slot.ZONE_W_WEAK]
	for xi: int in range(-6, 7, 2):
		for di: int in range(0, 11, 2):
			var p: Vector3 = _pt(float(xi), float(di))
			var covered: bool = false
			for role: int in zone_roles:
				if AIZoneCoverage.in_area(role, 1.0, NET_Z, p):
					covered = true
					break
			assert_true(covered, "house point x=%d depth=%d uncovered" % [xi, di])


# ── Breathing anchors ────────────────────────────────────────────────────────

func test_wingers_collapse_when_the_puck_goes_below_the_goal_line() -> void:
	var puck_low: Vector3 = _pt(8.0, -1.0)     # corner, behind the goal line
	var puck_point: Vector3 = _pt(6.0, 16.0)   # at the point
	var sink: Vector3 = AIZoneCoverage.anchor_of(
			AIRoleSlots.Slot.ZONE_W_STRONG, 1.0, NET_Z, puck_low)
	var extend: Vector3 = AIZoneCoverage.anchor_of(
			AIRoleSlots.Slot.ZONE_W_STRONG, 1.0, NET_Z, puck_point)
	# Collapsed: at the circle top. Extended (point threat): stepped up
	# toward the puck — much further from our net.
	assert_almost_eq(AIZoneCoverage.depth_of(NET_Z, sink),
			AIZoneCoverage.W_STRONG_SINK_DEPTH_M, 0.5)
	assert_gt(AIZoneCoverage.depth_of(NET_Z, extend), 12.0,
			"point threat pulls the strong winger up the lane")


func test_point_threat_anchor_blocks_the_shot_lane() -> void:
	# Puck at the strong point: the winger's anchor must sit ON the
	# puck→net line, SHOT_LANE_STEP_M from the puck.
	var puck: Vector3 = _pt(6.0, 16.0)
	var a: Vector3 = AIZoneCoverage.anchor_of(
			AIRoleSlots.Slot.ZONE_W_STRONG, 1.0, NET_Z, puck)
	var to_net: Vector3 = Vector3(0, 0, NET_Z) - puck
	var expected: Vector3 = puck + to_net.normalized() * AIZoneCoverage.SHOT_LANE_STEP_M
	assert_lt(a.distance_to(expected), 0.1)


func test_weak_winger_sags_into_the_high_slot_when_puck_is_low() -> void:
	var a: Vector3 = AIZoneCoverage.anchor_of(
			AIRoleSlots.Slot.ZONE_W_WEAK, 1.0, NET_Z, _pt(9.0, 1.0))
	# Weak side of center, high-slot depth band.
	assert_lt(a.x, 0.0)
	assert_between(AIZoneCoverage.depth_of(NET_Z, a), 7.5, 10.0)


func test_anchors_mirror_with_strong_side_and_net() -> void:
	# Strong side −X, team 1's net: the geometry mirrors cleanly.
	var a: Vector3 = AIZoneCoverage.anchor_of(
			AIRoleSlots.Slot.ZONE_D_STRONG, -1.0, -NET_Z, Vector3(-8, 0, -20))
	assert_lt(a.x, 0.0, "strong-side anchor follows the strong sign")
	assert_lt(a.z, 0.0, "anchor is in team 1's zone")

# WHICH man a zone defender covers moved to TeamBrain's matching (one partition
# across all five areas, so two defenders can never take the same body); the
# per-area argmax that used to live here is gone with it. What stays here is the
# GEOMETRY that matching consumes as eligibility — see test_team_brain.gd for the
# partition itself.

func test_the_release_margin_holds_a_man_just_past_the_edge() -> void:
	# A man half a metre outside the net-front box. A fresh read excludes him,
	# but the incumbent margin keeps him eligible so a man skating the seam is
	# not handed back and forth between two defenders every tick.
	var edge_pos: Vector3 = _pt(NET_FRONT_EDGE_X + 0.5, 2.0)
	assert_false(AIZoneCoverage.in_area(
			AIRoleSlots.Slot.ZONE_D_WEAK, 1.0, NET_Z, edge_pos),
			"a fresh read does not reach past the box edge")
	assert_true(AIZoneCoverage.in_area(
			AIRoleSlots.Slot.ZONE_D_WEAK, 1.0, NET_Z, edge_pos,
			AIZoneCoverage.AREA_RELEASE_MARGIN_M),
			"the incumbent margin holds him")


func test_a_man_who_leaves_the_box_is_the_neighbours() -> void:
	# Out past the box AND past the margin: the net-front D can no longer be
	# given him at all, and the slot's area has him instead.
	var gone: Vector3 = _pt(0.0, 8.0)
	assert_false(AIZoneCoverage.in_area(
			AIRoleSlots.Slot.ZONE_D_WEAK, 1.0, NET_Z, gone,
			AIZoneCoverage.AREA_RELEASE_MARGIN_M),
			"never chase him out of the box")
	assert_true(AIZoneCoverage.in_area(
			AIRoleSlots.Slot.ZONE_C, 1.0, NET_Z, gone),
			"the ice he entered owns him")


const NET_FRONT_EDGE_X: float = 2.6  # AIZoneCoverage.NET_FRONT_HALF_WIDTH_M


# ── Defensive-responsibility anchor ──────────────────────────────────────────

func test_defensive_anchor_geometry() -> void:
	var ld: Vector3 = AIZoneCoverage.defensive_anchor(true, -1.0, NET_Z)
	assert_lt(ld.x, 0.0, "LD's post is on the left")
	assert_almost_eq(ld.z, GameRules.BLUE_LINE_Z, 0.001)
	var fwd: Vector3 = AIZoneCoverage.defensive_anchor(false, 0.0, NET_Z)
	assert_lt(fwd.z, ld.z, "a forward's post is up-ice of the D's")


# ── A man down: the wedge and one ────────────────────────────────────────────

const BASE_STRONG: int = AIRoleSlots.Slot.ZONE_D_STRONG
const BASE_WEAK: int = AIRoleSlots.Slot.ZONE_D_WEAK
const TIP: int = AIRoleSlots.Slot.ZONE_C
const THE_ONE: int = AIRoleSlots.Slot.ZONE_W_STRONG
const WEDGE: Array[int] = [BASE_STRONG, BASE_WEAK, TIP]


func _wedge_owner(x: float, depth: float) -> int:
	return AIZoneCoverage.pressure_owner(1.0, NET_Z, _pt(x, depth), true)


func _in_the_house(p: Vector3) -> bool:
	var depth: float = AIZoneCoverage.depth_of(NET_Z, p)
	return depth >= 0.0 and depth < AIZoneCoverage.SLOT_TOP_DEPTH_M \
			and absf(p.x) <= AIZoneCoverage.SLOT_HALF_WIDTH_M


func test_the_whole_perimeter_is_the_ones_to_pressure() -> void:
	assert_eq(_wedge_owner(9.0, 3.0), THE_ONE, "the strong corner")
	assert_eq(_wedge_owner(-9.0, 3.0), THE_ONE, "the weak corner")
	assert_eq(_wedge_owner(0.0, -1.5), THE_ONE, "behind the net")
	assert_eq(_wedge_owner(10.0, 9.0), THE_ONE, "the half wall")
	assert_eq(_wedge_owner(6.0, 16.0), THE_ONE, "the strong point")
	assert_eq(_wedge_owner(-6.0, 16.0), THE_ONE, "the weak point")


func test_a_puck_in_the_house_is_the_wedge_man_whose_third_it_is_in() -> void:
	assert_eq(_wedge_owner(1.5, 2.0), BASE_STRONG)
	assert_eq(_wedge_owner(-1.5, 2.0), BASE_WEAK)
	assert_eq(_wedge_owner(0.5, 7.0), TIP)


func test_every_puck_has_one_owner_and_sits_in_his_area() -> void:
	for xi: int in range(-12, 13):
		for di: int in range(-3, 19):
			var p: Vector3 = _pt(float(xi), float(di))
			var owner_id: int = AIZoneCoverage.pressure_owner(1.0, NET_Z, p, true)
			assert_true(AIZoneCoverage.in_area(owner_id, 1.0, NET_Z, p, 0.0, true),
					"x=%d depth=%d is not in its owner's area" % [xi, di])


func test_no_wedge_man_is_handed_a_man_outside_the_house() -> void:
	for xi: int in range(-12, 13):
		for di: int in range(-3, 19):
			var p: Vector3 = _pt(float(xi), float(di))
			if _in_the_house(p):
				continue
			for role: int in WEDGE:
				assert_false(AIZoneCoverage.in_area(role, 1.0, NET_Z, p, 0.0, true),
						"wedge role %d would leave the house for x=%d depth=%d"
						% [role, xi, di])


func test_the_wedge_stands_inside_the_house_wherever_the_puck_is() -> void:
	for puck: Vector3 in [_pt(9.0, 3.0), _pt(0.0, -1.5), _pt(10.0, 9.0), _pt(6.0, 16.0),
			_pt(-6.0, 16.0)]:
		for role: int in WEDGE:
			assert_true(_in_the_house(AIZoneCoverage.anchor_of(role, 1.0, NET_Z, puck, true)),
					"wedge role %d with the puck at %v" % [role, puck])


func test_the_wedge_is_a_triangle_with_its_base_across_the_crease() -> void:
	var puck: Vector3 = _pt(6.0, 16.0)
	var strong: Vector3 = AIZoneCoverage.anchor_of(BASE_STRONG, 1.0, NET_Z, puck, true)
	var weak: Vector3 = AIZoneCoverage.anchor_of(BASE_WEAK, 1.0, NET_Z, puck, true)
	var tip: Vector3 = AIZoneCoverage.anchor_of(TIP, 1.0, NET_Z, puck, true)
	assert_almost_eq(strong.x, -weak.x, 0.001, "the base is centred on the net")
	assert_gt(strong.x, 0.0, "its strong man is on the puck's side")
	assert_almost_eq(strong.z, weak.z, 0.001, "and level")
	assert_gt(AIZoneCoverage.depth_of(NET_Z, tip), AIZoneCoverage.depth_of(NET_Z, strong),
			"the tip is above the base")
	assert_lt(absf(tip.x), strong.x, "and between its men")


func test_the_tip_rises_as_the_puck_goes_to_the_point() -> void:
	var low: Vector3 = AIZoneCoverage.anchor_of(TIP, 1.0, NET_Z, _pt(9.0, -1.0), true)
	var high: Vector3 = AIZoneCoverage.anchor_of(TIP, 1.0, NET_Z, _pt(6.0, 16.0), true)
	assert_gt(AIZoneCoverage.depth_of(NET_Z, high), AIZoneCoverage.depth_of(NET_Z, low))


func test_the_wedge_mirrors_with_the_strong_side() -> void:
	var puck: Vector3 = _pt(-6.0, 16.0)
	var strong: Vector3 = AIZoneCoverage.anchor_of(BASE_STRONG, -1.0, NET_Z, puck, true)
	assert_lt(strong.x, 0.0, "the strong base man follows the puck across")
	assert_eq(AIZoneCoverage.pressure_owner(-1.0, NET_Z, _pt(-1.5, 2.0), true), BASE_STRONG)


func test_at_even_strength_the_coverage_is_unchanged() -> void:
	assert_eq(AIZoneCoverage.pressure_owner(1.0, NET_Z, _pt(9.0, 3.0)),
			AIRoleSlots.Slot.ZONE_D_STRONG, "the corner is still the battle D's")

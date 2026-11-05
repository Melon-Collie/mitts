extends GutTest

# AIPossessionFloor — the continuation: a floor by position up the ice plus a
# slot bonus for the net a spot sees from their zone. Properties only; the values
# are feel tunables (docs/possession-floor-plan.md §2.1).

const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)   # attacking -Z
const G: float = GameRules.GOAL_LINE_Z
const B: float = GameRules.BLUE_LINE_Z


# The spot `a` metres toward the attacking goal, `x` across.
func _at(a: float, x: float = 0.0) -> Vector3:
	return Vector3(x, 0.0, -a)


func test_the_floor_sits_on_its_anchors() -> void:
	assert_almost_eq(AIPossessionFloor.floor_at(_at(-G), GOAL),
			AIPossessionFloor.FLOOR_OWN_GOAL_LINE, 1e-6, "our goal line")
	assert_almost_eq(AIPossessionFloor.floor_at(_at(-B), GOAL),
			AIPossessionFloor.FLOOR_OWN_BLUE_LINE, 1e-6, "our blue line")
	assert_almost_eq(AIPossessionFloor.floor_at(_at(B), GOAL),
			AIPossessionFloor.FLOOR_THEIR_BLUE_LINE, 1e-6, "their blue line")
	assert_almost_eq(AIPossessionFloor.floor_at(_at(G), GOAL),
			AIPossessionFloor.FLOOR_THEIR_GOAL_LINE, 1e-6, "their goal line")


func test_the_floor_is_linear_between_anchors_and_flat_past_the_goal_lines() -> void:
	var anchors: Array[float] = [-G, -B, B, G]
	for i: int in anchors.size() - 1:
		var lo: float = anchors[i]
		var hi: float = anchors[i + 1]
		var f_lo: float = AIPossessionFloor.floor_at(_at(lo), GOAL)
		var f_hi: float = AIPossessionFloor.floor_at(_at(hi), GOAL)
		for s: float in [0.25, 0.5, 0.75]:
			assert_almost_eq(AIPossessionFloor.floor_at(_at(lerpf(lo, hi, s)), GOAL),
					lerpf(f_lo, f_hi, s), 1e-6, "%.0f%% from %.2f to %.2f" % [s * 100.0, lo, hi])
	assert_almost_eq(AIPossessionFloor.floor_at(_at(-G - 2.0), GOAL),
			AIPossessionFloor.FLOOR_OWN_GOAL_LINE, 1e-6, "behind our net")
	assert_almost_eq(AIPossessionFloor.floor_at(_at(G + 2.0), GOAL),
			AIPossessionFloor.FLOOR_THEIR_GOAL_LINE, 1e-6, "behind their net")


func test_the_floor_reads_no_lateral_term() -> void:
	for a: float in [-20.0, 0.0, 15.0]:
		assert_almost_eq(AIPossessionFloor.floor_at(_at(a, 11.0), GOAL),
				AIPossessionFloor.floor_at(_at(a), GOAL), 1e-6, "a %.0f" % a)


func test_the_bonus_is_their_zone_only() -> void:
	for a: float in [-20.0, 0.0, B - 0.01, B]:
		assert_eq(AIPossessionFloor.slot_bonus(_at(a), GOAL), 0.0, "a %.2f" % a)
	assert_gt(AIPossessionFloor.slot_bonus(_at(B + 0.01), GOAL), 0.0, "just inside")


# The leaf keeps its own copy of the line test; it must be the zone's.
func test_the_bonus_zone_is_the_offensive_zone() -> void:
	for a: float in [B - 0.5, B - 0.001, B, B + 0.001, B + 0.5]:
		for x: float in [0.0, -9.0]:
			var p: Vector3 = _at(a, x)
			assert_eq(AIPossessionFloor.slot_bonus(p, GOAL) > 0.0,
					AIActionScoring.in_offensive_zone(p, GOAL), "a %.3f x %.0f" % [a, x])


func test_no_bonus_on_or_behind_the_goal_line() -> void:
	for x: float in [0.0, 0.5, -3.0, 8.0]:
		assert_eq(AIPossessionFloor.slot_bonus(_at(G, x), GOAL), 0.0, "on it, x %.1f" % x)
		assert_eq(AIPossessionFloor.slot_bonus(_at(G + 1.5, x), GOAL), 0.0,
				"behind it, x %.1f" % x)


func test_the_bonus_plateaus_inside_the_reference_distance() -> void:
	for out: float in [AIPossessionFloor.SLOT_REF_M, 4.0, 2.0, 0.5]:
		assert_almost_eq(AIPossessionFloor.slot_bonus(_at(G - out), GOAL),
				AIPossessionFloor.SLOT_BONUS, 1e-6, "%.1f m out" % out)
	assert_lt(AIPossessionFloor.slot_bonus(_at(G - AIPossessionFloor.SLOT_REF_M - 0.5), GOAL),
			AIPossessionFloor.SLOT_BONUS, "past the reference it falls")


func test_the_bonus_falls_with_distance_and_with_angle() -> void:
	var prev: float = INF
	for out: float in [7.0, 10.0, 14.0, 19.0]:
		var b: float = AIPossessionFloor.slot_bonus(_at(G - out), GOAL)
		assert_lt(b, prev, "straight out, %.0f m" % out)
		prev = b
	prev = INF
	for x: float in [0.0, 3.0, 6.0, 10.0]:
		var b: float = AIPossessionFloor.slot_bonus(_at(G - 12.0, x), GOAL)
		assert_lt(b, prev, "12 m out, %.0f m across" % x)
		prev = b


func test_left_and_right_read_alike() -> void:
	for p: Vector3 in [_at(G - 8.0, 3.0), _at(G - 2.0, 9.0), _at(B + 1.0, 12.0)]:
		var mirrored := Vector3(-p.x, 0.0, p.z)
		assert_almost_eq(AIPossessionFloor.continuation(mirrored, GOAL),
				AIPossessionFloor.continuation(p, GOAL), 1e-6, "%s" % p)


func test_the_other_end_reads_the_same_spot_mirrored() -> void:
	for p: Vector3 in [_at(G - 5.0, 1.0), _at(0.0, 4.0), _at(-G + 3.0, -6.0), _at(B + 2.0, 10.0)]:
		var flipped := Vector3(-p.x, 0.0, -p.z)
		assert_almost_eq(AIPossessionFloor.continuation(flipped, -GOAL),
				AIPossessionFloor.continuation(p, GOAL), 1e-6, "%s" % p)


func test_the_mouth_is_the_angle_between_the_posts() -> void:
	# Straight out, the half-angle's tangent is the half-width over the distance.
	var out: float = 7.0
	assert_almost_eq(AIPossessionFloor.mouth_angle(_at(G - out), GOAL),
			2.0 * atan(GameRules.NET_HALF_WIDTH / out), 1e-6)
	# From the side, the angle between the two rays to the posts.
	var x: float = 5.0
	var y: float = 4.0
	var to_l := Vector2(-GameRules.NET_HALF_WIDTH - x, -y)
	var to_r := Vector2(GameRules.NET_HALF_WIDTH - x, -y)
	assert_almost_eq(AIPossessionFloor.mouth_angle(_at(G - y, x), GOAL),
			acos(to_l.dot(to_r) / (to_l.length() * to_r.length())), 1e-6)


func test_no_spot_reads_above_the_most_continuation() -> void:
	var most: float = AIPossessionFloor.MOST_CONTINUATION
	for v: float in [AIPossessionFloor.FLOOR_OWN_GOAL_LINE, AIPossessionFloor.FLOOR_OWN_BLUE_LINE,
			AIPossessionFloor.FLOOR_THEIR_BLUE_LINE, AIPossessionFloor.FLOOR_THEIR_GOAL_LINE]:
		assert_lte(v + AIPossessionFloor.SLOT_BONUS, most + 1e-9, "an anchor plus the bonus")
	for zi: int in 61:
		for xi: int in 13:
			var p := Vector3(-12.0 + 2.0 * xi, 0.0, -30.0 + 1.0 * zi)
			assert_lte(AIPossessionFloor.continuation(p, GOAL), most + 1e-9, "%s" % p)
			assert_gte(AIPossessionFloor.continuation(p, GOAL),
					AIPossessionFloor.FLOOR_OWN_GOAL_LINE - 1e-9, "%s" % p)

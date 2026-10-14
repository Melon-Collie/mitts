extends GutTest

# BladeRoute — the path a carried puck takes between two spots off the body.
# Body-relative XZ; facing "ahead" is −Z.

const AHEAD := Vector2(0.0, -1.0)
const RIGHT := Vector2(0.9, 0.0)
const LEFT := Vector2(-0.9, 0.0)


func _samples(from: Vector2, to: Vector2, facing: Vector2, n: int = 40) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var total: float = BladeRoute.length(from, to, facing)
	for i: int in n + 1:
		out.append(BladeRoute.point_along(from, to, facing, total * float(i) / n))
	return out


func test_a_line_clear_of_the_body_is_straight() -> void:
	var to := Vector2(0.0, -0.9)
	assert_false(BladeRoute.crosses_body(RIGHT, to))
	assert_almost_eq(BladeRoute.length(RIGHT, to, AHEAD), RIGHT.distance_to(to), 1e-6)
	assert_eq(BladeRoute.point_along(RIGHT, to, AHEAD, 0.3), RIGHT.move_toward(to, 0.3))


func test_across_the_body_it_goes_round_the_front_and_never_through() -> void:
	assert_true(BladeRoute.crosses_body(RIGHT, LEFT))
	var pts: Array[Vector2] = _samples(RIGHT, LEFT, AHEAD)
	for p: Vector2 in pts:
		assert_gte(p.length(), BladeRoute.CLEAR_M - 0.001)
	assert_gt(pts[pts.size() / 2].dot(AHEAD), 0.0, "halfway it is in front of him")


func test_the_side_follows_the_facing() -> void:
	var behind := -AHEAD
	var mid: Vector2 = BladeRoute.point_along(RIGHT, LEFT, behind,
			BladeRoute.length(RIGHT, LEFT, behind) * 0.5)
	assert_gt(mid.dot(behind), 0.0, "faced the other way, it passes the other side")


func test_the_route_runs_from_one_spot_to_the_other_at_its_length() -> void:
	var to := Vector2(-0.8, -0.3)
	var total: float = BladeRoute.length(RIGHT, to, AHEAD)
	assert_eq(BladeRoute.point_along(RIGHT, to, AHEAD, 0.0), RIGHT)
	assert_almost_eq(BladeRoute.point_along(RIGHT, to, AHEAD, total).distance_to(to), 0.0, 1e-5)
	var walked: float = 0.0
	var pts: Array[Vector2] = _samples(RIGHT, to, AHEAD, 200)
	for i: int in range(1, pts.size()):
		walked += pts[i].distance_to(pts[i - 1])
	assert_almost_eq(walked, total, total * 0.005, "the length is the path walked")
	assert_gt(total, RIGHT.distance_to(to), "longer than the line through him")


func test_re_read_partway_round_it_keeps_going_the_same_way() -> void:
	var total: float = BladeRoute.length(RIGHT, LEFT, AHEAD)
	var part: Vector2 = BladeRoute.point_along(RIGHT, LEFT, AHEAD, total * 0.6)
	assert_almost_eq(BladeRoute.length(part, LEFT, AHEAD), total * 0.4, total * 0.01,
			"what is left of the route is the rest of the same route")


func test_a_puck_inside_the_circle_heading_out_goes_straight() -> void:
	assert_false(BladeRoute.crosses_body(Vector2.ZERO, RIGHT))
	assert_false(BladeRoute.crosses_body(Vector2(0.2, 0.0), RIGHT))


func test_a_tucked_puck_comes_out_before_crossing() -> void:
	var tucked := Vector2(0.1, 0.0)
	assert_true(BladeRoute.crosses_body(tucked, LEFT))
	var pts: Array[Vector2] = _samples(tucked, LEFT, AHEAD)
	var out: bool = false
	for p: Vector2 in pts:
		if p.length() >= BladeRoute.CLEAR_M - 0.001:
			out = true
		elif out:
			fail_test("back inside the body after coming out at %s" % str(p))
	assert_true(out)


func test_the_body_radius_is_the_skater_s() -> void:
	var sk := Skater.new()
	assert_eq(BladeRoute.BODY_RADIUS_M, sk.body_collision_radius)
	sk.free()

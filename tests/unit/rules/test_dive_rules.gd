extends GutTest

# DiveRules and the downed slide (SkaterMovementRules.slide_forward): when a dive
# starts, which way the body lays out, where its low block meets a puck's path,
# and the friction-only slide every downed snapshot is forward-predicted with.


func test_a_dive_starts_from_puckless_skating_with_both_buttons() -> void:
	assert_true(DiveRules.starts(true, true, true, false))
	assert_false(DiveRules.starts(false, true, true, false), "C alone is the standing block")
	assert_false(DiveRules.starts(true, false, true, false), "Shift alone is the stance")
	assert_false(DiveRules.starts(true, true, false, false), "not from carrying or another state")
	assert_false(DiveRules.starts(true, true, true, true), "not while already down")


func test_the_body_lays_out_toward_the_cursor() -> void:
	var body := Vector3(1.0, 0.0, 1.0)
	assert_eq(DiveRules.layout_dir(body, Vector3(4.0, 0.0, 1.0), Vector2(0, -1)), Vector2(1, 0))
	assert_eq(DiveRules.layout_dir(body, body, Vector2(0, 3)), Vector2(0, 1),
			"a cursor on the body falls back to the travel")


func test_the_block_point_is_where_the_puck_path_meets_the_body() -> void:
	var a := Vector2(0.0, 0.0)
	var b := Vector2(0.0, 1.7)
	var p: Vector2 = DiveRules.block_point(Vector3(-1.0, 0.0, 0.8), Vector3(1.0, 0.0, 0.8), a, b)
	assert_almost_eq(p.y, 0.8, 1e-5, "crossing the body: the crossing point")
	assert_almost_eq(p.x, 0.0, 1e-5)
	var near: Vector2 = DiveRules.block_point(Vector3(0.3, 0.0, 3.0), Vector3(0.3, 0.0, 2.5), a, b)
	assert_eq(near, b, "a puck short of the body: the body's end nearest it")


func test_a_downed_body_slides_without_thrust() -> void:
	var r := SkaterMovementRules.ForwardResult.new()
	SkaterMovementRules.slide_forward(r, Vector3.ZERO, Vector3(0.0, 0.0, -6.0), 8.0, 1.0, 0.25)
	assert_almost_eq(r.velocity.z, -(6.0 - 8.0 * 0.25), 1e-5, "it sheds speed at the friction")
	assert_almost_eq(r.position.z, -(6.0 * 0.25 - 0.5 * 8.0 * 0.25 * 0.25), 1e-5)
	assert_almost_eq(r.velocity.x, 0.0, 1e-6, "straight on, the way it was going")
	SkaterMovementRules.slide_forward(r, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 8.0, 1.0, 0.5)
	assert_eq(r.velocity, Vector3.ZERO, "a slow slide stops")
	assert_almost_eq(r.position.z, -(1.0 / (2.0 * 8.0)), 1e-5, "where it stops")

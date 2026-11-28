extends GutTest

# BoardCheckRules — which checks drive their victim into the boards, and where.

const HW: float = GameRules.INNER_HALF_WIDTH
const HL: float = GameRules.INNER_HALF_LENGTH


func _into(pos: Vector3, dir: Vector3) -> bool:
	return BoardCheckRules.contact(pos, dir) != BoardCheckRules.NONE


func test_a_check_square_into_the_side_boards_lands_on_them() -> void:
	var c: Vector3 = BoardCheckRules.contact(Vector3(HW - 0.6, 0.0, 5.0), Vector3(1.0, 0.0, 0.0))
	assert_almost_eq(c.x, HW, 1e-4)
	assert_almost_eq(c.z, 5.0, 1e-4)
	assert_almost_eq(c.y, BoardCheckRules.CONTACT_HEIGHT_M, 1e-4)


func test_the_end_boards_and_both_sides_of_the_rink() -> void:
	assert_true(_into(Vector3(-(HW - 0.5), 0.0, -3.0), Vector3(-1.0, 0.0, 0.2)))
	assert_true(_into(Vector3(0.0, 0.0, HL - 0.5), Vector3(0.0, 0.0, 1.0)))
	assert_true(_into(Vector3(1.0, 0.0, -(HL - 0.5)), Vector3(0.1, 0.0, -1.0)))


func test_open_ice_is_not_the_boards() -> void:
	assert_false(_into(Vector3(HW - BoardCheckRules.REACH_M - 0.2, 0.0, 5.0), Vector3(1.0, 0.0, 0.0)))
	assert_false(_into(Vector3.ZERO, Vector3(1.0, 0.0, 0.0)))


func test_along_the_wall_or_away_from_it_is_not_into_it() -> void:
	var by_the_boards := Vector3(HW - 0.5, 0.0, 5.0)
	assert_false(_into(by_the_boards, Vector3(0.0, 0.0, 1.0)), "along the wall")
	assert_false(_into(by_the_boards, Vector3(-1.0, 0.0, 0.0)), "off the wall")
	assert_false(_into(by_the_boards, Vector3.ZERO), "no push")


# In a corner the contact is on the arc, square to it, and the push must head
# out through the arc rather than along either wall it joins.
func test_a_corner_check_lands_on_the_arc() -> void:
	var centre := Vector2(GameRules.CORNER_CENTER_X, GameRules.CORNER_CENTER_Z)
	var out := Vector2(1.0, 1.0).normalized()
	var at: Vector2 = centre + out * (GameRules.INNER_CORNER_RADIUS - 0.5)
	var c: Vector3 = BoardCheckRules.contact(Vector3(at.x, 0.0, at.y), Vector3(out.x, 0.0, out.y))
	assert_ne(c, BoardCheckRules.NONE)
	assert_almost_eq(Vector2(c.x, c.z).distance_to(centre), GameRules.INNER_CORNER_RADIUS, 1e-3)
	assert_almost_eq(GameRules.distance_to_rink_inner(Vector2(c.x, c.z)), 0.0, 1e-3)


func test_every_contact_is_on_the_boards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var landed: int = 0
	for i: int in 400:
		var pos := Vector3(rng.randf_range(-HW, HW), 0.0, rng.randf_range(-HL, HL))
		if GameRules.distance_to_rink_inner(Vector2(pos.x, pos.z)) < 0.0:
			continue
		var out: Vector2 = BoardCheckRules.outward_at(Vector2(pos.x, pos.z))
		var c: Vector3 = BoardCheckRules.contact(pos, Vector3(out.x, 0.0, out.y))
		if c == BoardCheckRules.NONE:
			continue
		landed += 1
		assert_almost_eq(GameRules.distance_to_rink_inner(Vector2(c.x, c.z)), 0.0, 1e-3,
				"contact for %s" % pos)
	assert_gt(landed, 10)

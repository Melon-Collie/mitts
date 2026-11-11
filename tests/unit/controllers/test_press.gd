extends GutTest

# The press on the live rig (PressHarness): two real controllers in contact, the
# attacker driving into the man. Properties only; the calibration table is the
# slow tier's snapshot (tests/slow/controllers/test_press_table.gd).

const PRESS_S: float = 0.75
# Moved less than this, he held.
const HELD_M: float = 0.01


func _spec(man_lbs: int, attacker_lbs: int, man: String, attacker: String = "skate commit",
		side: String = "behind") -> PressHarness.Spec:
	var s := PressHarness.Spec.new()
	s.man_lbs = man_lbs
	s.attacker_lbs = attacker_lbs
	s.side = side
	s.man_does(man)
	s.attacker = attacker
	return s


func _run(spec: PressHarness.Spec) -> PressHarness.Result:
	return PressHarness.new(self).run(spec, PRESS_S)


func _gave(man: String, attacker: String = "skate commit", side: String = "behind") -> float:
	return _run(_spec(201, 201, man, attacker, side)).gave


func test_an_engaged_man_who_has_set_holds_an_equal_drive() -> void:
	assert_lt(_gave("commit brake"), HELD_M)
	assert_lt(_gave("commit brake", "skate commit", "beside"), HELD_M, "from any side")


func test_a_man_who_is_not_engaged_is_moved_whatever_else_he_holds() -> void:
	var passive: float = _gave("nothing")
	assert_gt(passive, HELD_M)
	assert_gt(_gave("brake"), 0.5 * passive, "a stop is not a stand")
	assert_gt(_gave("back"), HELD_M, "nor is skating back into him")


func test_the_stance_is_nothing_in_a_press() -> void:
	assert_almost_eq(_gave("stance"), _gave("nothing"), 1e-4)
	assert_almost_eq(_gave("brake stance"), _gave("brake"), 1e-4)
	assert_almost_eq(_gave("commit brake stance"), _gave("commit brake"), 1e-4)


func test_two_engaged_men_pushing_chest_to_chest_stall() -> void:
	assert_lt(absf(_gave("commit back facing")), HELD_M)


func test_pushing_back_with_his_back_to_him_only_slows_it() -> void:
	var back_turned: float = _gave("commit back")
	assert_gt(back_turned, HELD_M)
	assert_lt(back_turned, _gave("commit"))


func test_weight_decides_at_the_margin() -> void:
	assert_gt(_run(_spec(170, 235, "commit brake")).gave, HELD_M, "heavy creeps a set light man")
	assert_lt(_run(_spec(235, 170, "commit brake")).gave, HELD_M, "light never moves a set heavy man")
	assert_gt(_run(_spec(170, 235, "commit back facing")).gave, HELD_M, "and out-pushes him")


func test_a_press_moves_a_man_at_a_walk() -> void:
	var r: PressHarness.Result = PressHarness.new(self).run(_spec(201, 201, "nothing"), 2.0)
	assert_lte(r.man_speed, PressRules.MAX_SPEED_M_S + 0.05)
	assert_gt(r.man_speed, 0.5 * PressRules.MAX_SPEED_M_S)


func test_a_press_alone_staggers_nobody() -> void:
	var r: PressHarness.Result = _run(_spec(201, 201, "nothing"))
	assert_eq(r.peak_stagger, 0.0)
	assert_false(r.knocked)


func test_a_shove_breaks_a_set_man_loose() -> void:
	var shoved: PressHarness.Result = _run(_spec(201, 201, "commit brake", "skate commit shove"))
	assert_gt(shoved.peak_stagger, 0.0, "a fresh press on a man he leans on is a shove")
	assert_false(shoved.knocked)
	assert_gt(shoved.gave, 10.0 * HELD_M, "and the push after it moves him")


func test_a_staggered_man_loses_the_press() -> void:
	var spec: PressHarness.Spec = _spec(201, 201, "commit brake")
	spec.man_stagger_s = BodyCheckRules.Config.new().max_stagger_seconds
	assert_gt(_run(spec).gave, HELD_M)


func test_chest_on_pushes_harder_than_side_on() -> void:
	var square: float = _gave("nothing")
	var side_on: float = _gave("nothing", "skate commit side-on")
	assert_gt(side_on, HELD_M)
	assert_lt(side_on, 0.7 * square)


# ── On the boards ────────────────────────────────────────────────────────────
# The man against the boards, the attacker square on his open-ice side
# (BoardWallRules' squeeze).

const BOARDS_S: float = 1.0
# Slid less than this along the wall, he was held there.
const BOARDS_HELD_M: float = 0.05
const PUSHING_BACK: String = "commit back along facing"


func _on_the_boards(man: String, attacker: String = "skate commit", man_lbs: int = 201,
		attacker_lbs: int = 201, at_boards: bool = true) -> PressHarness.Result:
	var s: PressHarness.Spec = _spec(man_lbs, attacker_lbs, man, attacker, "beside")
	s.at_boards = at_boards
	return PressHarness.new(self).run(s, BOARDS_S)


func test_an_engaged_man_square_on_him_holds_an_equal_against_the_boards() -> void:
	assert_lt(_on_the_boards("along").slid, BOARDS_HELD_M, "he cannot skate off along the glass")
	assert_gt(_on_the_boards("along", "skate commit", 201, 201, false).slid, BOARDS_HELD_M,
			"as he does in open ice")


func test_a_man_who_only_skates_into_him_holds_nobody_there() -> void:
	assert_gt(_on_the_boards("along", "skate").slid, BOARDS_HELD_M)


func test_a_shove_gets_a_held_man_off_the_wall() -> void:
	var shoved: PressHarness.Result = _on_the_boards(PUSHING_BACK + " shove")
	assert_gt(shoved.slid, _on_the_boards(PUSHING_BACK).slid)
	assert_gt(shoved.slid, BOARDS_HELD_M)
	assert_lt(shoved.gave, -BoardWallRules.SQUEEZE_MARGIN_M, "and off the boards")


func test_weight_decides_who_is_held_there() -> void:
	var equal: float = _on_the_boards(PUSHING_BACK).slid
	assert_gt(_on_the_boards(PUSHING_BACK, "skate commit", 235, 170).slid,
			maxf(equal, BOARDS_HELD_M), "a heavy man pushes a light one off him")
	assert_lt(_on_the_boards(PUSHING_BACK, "skate commit", 170, 235).slid, BOARDS_HELD_M,
			"a light man does not")

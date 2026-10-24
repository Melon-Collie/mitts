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
	s.man_stance = man.contains("stance")
	s.man_brake = man.contains("brake")
	s.man_back = man.contains("back")
	s.attacker = attacker
	return s


func _run(spec: PressHarness.Spec) -> PressHarness.Result:
	return PressHarness.new(self).run(spec, PRESS_S)


func test_an_anchored_man_holds_an_equal_drive() -> void:
	assert_lt(_run(_spec(201, 201, "brake stance")).gave, HELD_M, "braking in the stance")


func test_braking_upright_he_gives_ground_slowly() -> void:
	var braking: PressHarness.Result = _run(_spec(201, 201, "brake"))
	var passive: PressHarness.Result = _run(_spec(201, 201, "nothing"))
	assert_gt(braking.gave, HELD_M, "the stop alone gives")
	assert_lt(braking.gave, passive.gave * 0.5, "but far less than a man who does nothing")
	assert_eq(passive.peak_stagger, 0.0, "a press staggers nobody")
	assert_false(passive.knocked)


func test_weight_decides_at_the_margin() -> void:
	assert_gt(_run(_spec(170, 235, "brake stance")).gave, HELD_M, "heavy creeps an anchored light man")
	assert_lt(_run(_spec(235, 170, "brake stance")).gave, HELD_M, "light never moves an anchored heavy man")


func test_a_staggered_man_loses_the_press() -> void:
	var spec: PressHarness.Spec = _spec(201, 201, "brake stance")
	spec.man_stagger_s = BodyCheckRules.Config.new().max_stagger_seconds
	assert_gt(_run(spec).gave, HELD_M)


func test_across_his_blades_holds_more_than_along_them() -> void:
	var side: PressHarness.Result = _run(_spec(201, 201, "nothing", "skate commit", "beside"))
	var behind: PressHarness.Result = _run(_spec(201, 201, "nothing"))
	assert_lt(side.gave, behind.gave * 0.25)

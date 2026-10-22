extends GutTest

# What a sustained press moves: two real controllers in contact at a standstill
# (PressHarness), the attacker driving into the man in front of him for two
# seconds. Prints how far the man gives ground and how far the attacker gets,
# against what the cross-check buys from the same spot. Read by
# docs/net-front-battles-plan.md; asserts nothing.

const PRESS_S: float = 2.0


func _spec(man_lbs: int, attacker_lbs: int, side: String, man: String,
		attacker: String) -> PressHarness.Spec:
	var s := PressHarness.Spec.new()
	s.man_lbs = man_lbs
	s.attacker_lbs = attacker_lbs
	s.side = side
	s.man_stance = man.contains("stance")
	s.man_back = man.contains("back")
	s.man_brake = man.contains("brake")
	s.attacker = attacker
	return s


func test_print_the_press_table() -> void:
	var rows: Array[String] = [
		"| case | man / attacker lb | side | man | attacker | gave 1 s (m) | gave 2 s (m) | attacker went (m) | gap at end (m) | man speed at end (m/s) | peak stagger (s) | down |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|",
	]
	# label, man lb, attacker lb, side, man, attacker
	var cases: Array = [
		["skate in", 201, 201, "behind", "nothing", "skate"],
		["skate in, committed", 201, 201, "behind", "nothing", "skate commit"],
		["skate in, stance", 201, 201, "behind", "nothing", "skate stance"],
		["man in stance", 201, 201, "behind", "stance", "skate commit"],
		["man backs in", 201, 201, "behind", "back", "skate commit"],
		["man backs in, uncommitted attacker", 201, 201, "behind", "back", "skate"],
		["man brakes", 201, 201, "behind", "brake", "skate commit"],
		["man brakes, stance", 201, 201, "behind", "brake stance", "skate commit"],
		["man brakes, from the side", 201, 201, "beside", "brake", "skate commit"],
		["man brakes, heavy uncommitted attacker", 170, 235, "behind", "brake", "skate"],
		["heavy on light, anchored", 170, 235, "behind", "brake stance", "skate commit"],
		["light on heavy, anchored", 235, 170, "behind", "brake stance", "skate commit"],
		["heavy on light", 170, 235, "behind", "nothing", "skate commit"],
		["light on heavy", 235, 170, "behind", "nothing", "skate commit"],
		["from the side", 201, 201, "beside", "nothing", "skate commit"],
		["from the side, stance", 201, 201, "beside", "stance", "skate commit"],
		["cross-check", 201, 201, "behind", "nothing", "shove"],
		["cross-check, man brakes", 201, 201, "behind", "brake", "shove"],
		["cross-check, side", 201, 201, "beside", "nothing", "shove"],
	]
	for c: Array in cases:
		var r: PressHarness.Result = PressHarness.new(self).run(
				_spec(c[1], c[2], c[3], c[4], c[5]), PRESS_S)
		rows.append("| %s | %d / %d | %s | %s | %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %s |" % [
				c[0], c[1], c[2], c[3], c[4], c[5], r.gave_1s, r.gave, r.went, r.gap_end,
				r.man_speed, r.peak_stagger, "yes" if r.knocked else "no"])
	gut.p("\n" + "\n".join(rows))
	assert_true(true)

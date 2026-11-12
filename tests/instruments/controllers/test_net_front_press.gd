extends GutTest

# What a sustained press moves: two real controllers in contact at a standstill
# (PressHarness), the attacker driving into the man in front of him for two
# seconds. Prints how far the man gives ground and how far the attacker gets.
# Read by
# docs/net-front-battles-plan.md; asserts nothing.

const PRESS_S: float = 2.0


func _spec(man_lbs: int, attacker_lbs: int, side: String, man: String,
		attacker: String) -> PressHarness.Spec:
	var s := PressHarness.Spec.new()
	s.man_lbs = man_lbs
	s.attacker_lbs = attacker_lbs
	s.side = side
	s.man_does(man)
	s.attacker = attacker
	return s


func test_print_the_press_table() -> void:
	var rows: Array[String] = [
		"| case | man / attacker lb | side | man | attacker | gave 1 s (m) | gave 2 s (m) | attacker went (m) | gap at end (m) | man speed at end (m/s) | peak stagger (s) | down |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|",
	]
	# label, man lb, attacker lb, side, man, attacker
	var cases: Array = [
		["not engaged, skated into", 201, 201, "behind", "nothing", "skate"],
		["not engaged, pushed", 201, 201, "behind", "nothing", "skate commit"],
		["not engaged, pushed side-on", 201, 201, "behind", "nothing", "skate commit side-on"],
		["not engaged, in the stance", 201, 201, "behind", "stance", "skate commit"],
		["not engaged, skating back in", 201, 201, "behind", "back", "skate commit"],
		["not engaged, braking", 201, 201, "behind", "brake", "skate commit"],
		["engaged, doing nothing", 201, 201, "behind", "commit", "skate commit"],
		["engaged, pushing back, his back to him", 201, 201, "behind", "commit back", "skate commit"],
		["engaged, pushing back, chest to chest", 201, 201, "behind", "commit back facing", "skate commit"],
		["engaged and set", 201, 201, "behind", "commit brake", "skate commit"],
		["engaged and set, shoved first", 201, 201, "behind", "commit brake", "skate commit shove"],
		["engaged and set, from the side", 201, 201, "beside", "commit brake", "skate commit"],
		["heavy on a set light man", 170, 235, "behind", "commit brake", "skate commit"],
		["light on a set heavy man", 235, 170, "behind", "commit brake", "skate commit"],
		["heavy out-pushing light, chest to chest", 170, 235, "behind", "commit back facing", "skate commit"],
		["heavy on light, not engaged", 170, 235, "behind", "nothing", "skate commit"],
	]
	for c: Array in cases:
		var r: PressHarness.Result = PressHarness.new(self).run(
				_spec(c[1], c[2], c[3], c[4], c[5]), PRESS_S)
		rows.append("| %s | %d / %d | %s | %s | %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %s |" % [
				c[0], c[1], c[2], c[3], c[4], c[5], r.gave_1s, r.gave, r.went, r.gap_end,
				r.man_speed, r.peak_stagger, "yes" if r.knocked else "no"])
	gut.p("\n" + "\n".join(rows))
	assert_true(true)

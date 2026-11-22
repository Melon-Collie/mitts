extends GutTest

# AICarrySpace.carry_strip_point names WHERE a carry is stripped and
# carry_safety HOW LIKELY: the two read the same three samples (the crossing,
# the mid-route pursuit, the arrival lunge) and must agree on which of them is
# covered, or a carry is charged a strip at a point its own safety read calls
# open. Neither exposes its sample windows, so this holds them together through
# what each answers: over a seeded sweep of carries past one to three
# defenders, every verdict the strip point gives is one the safety read prices.
#
# Run on the GDScript references; test_native_carry_space_parity.gd holds the
# native kernels to them.

const TRIALS: int = 4000
const SEED: int = 775


func _carries() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out: Array[Dictionary] = []
	for _i: int in TRIALS:
		var from := Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
		var stand: bool = rng.randf() < 0.15
		var heading: float = rng.randf() * TAU
		var dist: float = 0.0 if stand else rng.randf_range(1.0, 9.0)
		var to: Vector3 = from + Vector3(sin(heading), 0.0, cos(heading)) * dist
		var pace: float = rng.randf_range(2.0, 9.0)
		var arrival: float = rng.randf_range(0.3, 1.5) if stand else dist / pace
		var opponents: Array[Vector3] = []
		var vels: Array[Vector3] = []
		for _k: int in rng.randi_range(1, 3):
			# Somewhere about the path, skating any way at up to a sprint.
			var along: Vector3 = from.lerp(to, rng.randf())
			opponents.append(along + Vector3(rng.randf_range(-4.0, 4.0), 0.0,
					rng.randf_range(-4.0, 4.0)))
			var dir: float = rng.randf() * TAU
			vels.append(Vector3(sin(dir), 0.0, cos(dir)) * rng.randf_range(0.0, 8.0))
		out.append({
			"from": from, "to": to, "t": arrival, "opps": opponents, "vels": vels,
			"escape": rng.randf() < 0.5, "stand": stand,
		})
	return out


func _safety(c: Dictionary) -> float:
	var opps: Array[Vector3] = c.opps
	var vels: Array[Vector3] = c.vels
	return AICarrySpace.carry_safety_reference(c.from, c.to, c.t, opps, vels, [], c.escape)


func _strip(c: Dictionary) -> Vector3:
	var opps: Array[Vector3] = c.opps
	var vels: Array[Vector3] = c.vels
	return AICarrySpace.carry_strip_point_reference(c.from, c.to, c.t, opps, vels, [],
			c.escape, true)


func test_the_strip_point_and_the_safety_read_agree_on_what_is_covered() -> void:
	# A mid sample the strip point reads covered (clearance below zero) is one
	# the safety read's transit map prices under its zero-clearance value; a
	# crossing it strips at is one the crossing band keeps nothing of; and a carry
	# the safety read calls fully safe has nothing covered on it at all.
	var mid_transit_cap: float = AICarrySpace.transit_clearance_to_safety(0.0)
	var stripped_mid: int = 0
	var stripped_crossing: int = 0
	var fully_safe: int = 0
	var disagreements: int = 0
	var first: String = ""
	for c: Dictionary in _carries():
		var safety: float = _safety(c)
		var at: Vector3 = _strip(c)
		var to: Vector3 = c.to
		var mid: Vector3 = (c.from as Vector3).lerp(to, 0.5)
		var agrees: bool = true
		var verdict: String = ""
		if safety >= 1.0:
			fully_safe += 1
			agrees = at == to
			verdict = "fully safe, stripped short of the destination"
		elif c.stand or at.is_equal_approx(to):
			continue
		elif at.is_equal_approx(mid):
			stripped_mid += 1
			agrees = safety < mid_transit_cap
			verdict = "stripped at the mid sample, its transit read uncovered"
		else:
			stripped_crossing += 1
			agrees = safety == 0.0
			verdict = "stripped at a crossing the band keeps something of"
		if not agrees:
			disagreements += 1
			if first.is_empty():
				first = "%s (safety %.3f, strip %s): %s" % [verdict, safety, at, c]
	assert_eq(disagreements, 0, first)
	# The sweep has to reach every verdict or it asserts nothing.
	assert_gt(stripped_mid, 20, "carries stripped at the mid sample")
	assert_gt(stripped_crossing, 20, "carries stripped at a crossing")
	assert_gt(fully_safe, 20, "carries the safety read calls fully safe")

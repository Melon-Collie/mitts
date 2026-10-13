extends GutTest

const OMEGA: float = TAU * 2.0
const ZETA: float = 0.35


func test_the_hem_swings_away_from_the_acceleration() -> void:
	var swing: Vector2 = ClothSwayRules.rest_swing(Vector2(0.0, -0.2), 0.35, 0.1)
	assert_gt(swing.y, 0.0, "a forward lean throws the hem back")
	assert_almost_eq(swing.x, 0.0, 1e-6)
	assert_lt(swing.length(), 0.1, "eased under its cap")
	assert_eq(ClothSwayRules.rest_swing(Vector2.ZERO, 0.35, 0.1), Vector2.ZERO)


func test_the_step_does_not_depend_on_how_time_is_chopped() -> void:
	var one: Vector4 = ClothSwayRules.step(Vector2(0.05, 0.0), Vector2.ZERO, Vector2.ZERO,
			OMEGA, ZETA, 0.1)
	var x := Vector2(0.05, 0.0)
	var v := Vector2.ZERO
	for i: int in 10:
		var s: Vector4 = ClothSwayRules.step(x, v, Vector2.ZERO, OMEGA, ZETA, 0.01)
		x = Vector2(s.x, s.y)
		v = Vector2(s.z, s.w)
	assert_almost_eq(Vector2(one.x, one.y), x, Vector2.ONE * 1e-6)
	assert_almost_eq(Vector2(one.z, one.w), v, Vector2.ONE * 1e-5)


# Cloth overshoots its rest and settles, which is what tells it from the lean.
func test_it_overshoots_then_settles() -> void:
	var x := Vector2.ZERO
	var v := Vector2.ZERO
	var target := Vector2(0.0, 0.08)
	var peak: float = 0.0
	for i: int in 240:
		var s: Vector4 = ClothSwayRules.step(x, v, target, OMEGA, ZETA, 1.0 / 120.0)
		x = Vector2(s.x, s.y)
		v = Vector2(s.z, s.w)
		peak = maxf(peak, x.y)
	assert_gt(peak, target.y * 1.05, "it swings past its rest")
	assert_almost_eq(x.y, target.y, 0.002, "and settles there within two seconds")

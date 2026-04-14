extends GutTest

# PuckCollisionRules — pure physics math for puck interactions.

# ── can_poke_check ───────────────────────────────────────────────────────────

func test_same_team_cannot_poke() -> void:
	assert_false(PuckCollisionRules.can_poke_check(0, 0))
	assert_false(PuckCollisionRules.can_poke_check(1, 1))

func test_opponents_can_poke() -> void:
	assert_true(PuckCollisionRules.can_poke_check(0, 1))
	assert_true(PuckCollisionRules.can_poke_check(1, 0))

# ── deflect_velocity ─────────────────────────────────────────────────────────

func test_full_blend_reflects_velocity() -> void:
	# Puck moving +X, contact normal -X (blade face toward -X, puck bounces back)
	var velocity := Vector3(10, 0, 0)
	var normal := Vector3(-1, 0, 0)
	var result: Vector3 = PuckCollisionRules.deflect_velocity(velocity, normal, 1.0, 1.0)
	assert_lt(result.x, 0.0, "deflected velocity X should flip sign")
	assert_almost_eq(result.length(), 10.0, 0.01)

func test_zero_blend_preserves_direction() -> void:
	# With deflect_blend=0 the result is along the incoming direction
	var velocity := Vector3(10, 0, 0)
	var normal := Vector3(-1, 0, 0)
	var result: Vector3 = PuckCollisionRules.deflect_velocity(velocity, normal, 0.0, 1.0)
	assert_gt(result.x, 0.0, "zero blend should keep moving in incoming direction")

func test_speed_retain_scales_magnitude() -> void:
	var velocity := Vector3(10, 0, 0)
	var normal := Vector3(-1, 0, 0)
	var result: Vector3 = PuckCollisionRules.deflect_velocity(velocity, normal, 1.0, 0.5)
	assert_almost_eq(result.length(), 5.0, 0.01)

# ── apply_deflection_elevation ───────────────────────────────────────────────

func test_elevation_adds_y_component() -> void:
	var horiz := Vector3(1, 0, 0)
	var elevated: Vector3 = PuckCollisionRules.apply_deflection_elevation(horiz, 35.0)
	assert_gt(elevated.y, 0.0)
	assert_almost_eq(elevated.length(), 1.0, 0.01, "result should still be unit length")

func test_zero_elevation_no_y_component() -> void:
	var horiz := Vector3(1, 0, 0)
	var flat: Vector3 = PuckCollisionRules.apply_deflection_elevation(horiz, 0.0)
	assert_almost_eq(flat.y, 0.0, 0.01)

# ── body_block_velocity ──────────────────────────────────────────────────────

func test_body_block_reflects_and_dampens() -> void:
	var velocity := Vector3(10, 0, 0)
	var normal := Vector3(-1, 0, 0)
	var result: Vector3 = PuckCollisionRules.body_block_velocity(velocity, normal, 0.5)
	assert_lt(result.x, 0.0, "reflected X should flip")
	assert_almost_eq(result.length(), 5.0, 0.01, "dampen halves speed")

func test_body_block_falls_back_to_normal_when_reflection_zero() -> void:
	# Zero velocity → reflected is also zero → fallback to contact normal
	var velocity := Vector3.ZERO
	var normal := Vector3(0, 0, 1)
	var result: Vector3 = PuckCollisionRules.body_block_velocity(velocity, normal, 1.0)
	# result.length() is horiz_vel.length() * dampen = 0 — but direction is normal
	assert_almost_eq(result.length(), 0.0, 0.01,
		"no input energy means no output energy; fallback only sets direction")

# ── body_check_strip_velocity ────────────────────────────────────────────────

func test_body_check_strip_scales_direction() -> void:
	var dir := Vector3(1, 0, 0)
	var result: Vector3 = PuckCollisionRules.body_check_strip_velocity(dir, 5.0)
	assert_eq(result, Vector3(5, 0, 0))

# ── poke_strip_velocity ──────────────────────────────────────────────────────

func test_poke_blends_checker_and_carrier_momentum() -> void:
	# Checker moving fast in +X, carrier moving slightly in +Z
	var result: Vector3 = PuckCollisionRules.poke_strip_velocity(
		Vector3(2, 0, 0),          # checker_blade_vel
		Vector3(0, 0, 1),          # carrier_blade_vel
		Vector3.ZERO,              # carrier_pos (unused when checker vel dominates)
		Vector3.ZERO,              # checker_pos
		0.5,                       # blend
		6.0,                       # strip_speed
		Vector3(1, 0, 0))          # fallback unused
	assert_almost_eq(result.length(), 6.0, 0.01)
	assert_gt(result.x, 0.0, "should move along checker's +X")
	assert_gt(result.z, 0.0, "should pick up some of carrier's +Z")

func test_poke_uses_position_delta_when_checker_still() -> void:
	# Checker blade not moving — strip direction is carrier_pos - checker_pos
	var result: Vector3 = PuckCollisionRules.poke_strip_velocity(
		Vector3.ZERO,              # checker not moving
		Vector3.ZERO,              # carrier not moving
		Vector3(3, 0, 0),          # carrier at +X
		Vector3(0, 0, 0),          # checker at origin
		0.5,
		6.0,
		Vector3(1, 0, 0))
	assert_almost_eq(result.length(), 6.0, 0.01)
	assert_gt(result.x, 0.0, "push puck away from checker (+X)")

func test_poke_uses_fallback_when_everything_is_zero() -> void:
	# Nothing moving, same positions — fall back to provided direction
	var fallback := Vector3(0, 0, 1)
	var result: Vector3 = PuckCollisionRules.poke_strip_velocity(
		Vector3.ZERO, Vector3.ZERO,
		Vector3.ZERO, Vector3.ZERO,
		0.5, 6.0, fallback)
	assert_almost_eq(result.length(), 6.0, 0.01)
	assert_gt(result.z, 0.0, "should use fallback direction (+Z)")

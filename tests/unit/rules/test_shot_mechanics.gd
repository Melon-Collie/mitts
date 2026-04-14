extends GutTest

# ShotMechanics — wrister + slapper power/direction + wall-pin release.

func _wrister_cfg() -> Dictionary:
	return {
		"min_wrister_power": 8.0,
		"max_wrister_power": 25.0,
		"max_wrister_charge_distance": 3.0,
		"backhand_power_coefficient": 0.75,
		"quick_shot_power": 12.0,
		"quick_shot_threshold": 0.1,
		"wrister_elevation": 0.3,
	}

func _slapper_cfg() -> Dictionary:
	return {
		"min_slapper_power": 20.0,
		"max_slapper_power": 40.0,
		"max_slapper_charge_time": 1.0,
		"slapper_elevation": 0.15,
	}

# ── Wrister: quick shot branch ───────────────────────────────────────────────

func test_wrister_very_short_charge_uses_quick_shot_power() -> void:
	var result: Dictionary = ShotMechanics.release_wrister(
		Vector3.ZERO,                   # player_pos
		Vector3(10, 0, 0),              # mouse at (10, 0, 0)
		Vector3(0.5, 0, 0),             # blade world pos
		Vector3(0.5, 0, 0),             # blade local pos
		Vector3(0.35, 0, 0),            # shoulder local pos
		false, false,
		0.01,                           # charge below threshold
		_wrister_cfg())
	assert_almost_eq(result.power, 12.0, 0.01, "quick shot uses fixed quick_shot_power")

func test_wrister_quick_shot_direction_from_blade() -> void:
	# Quick shot aims from the blade, not the player
	var result: Dictionary = ShotMechanics.release_wrister(
		Vector3(0, 0, 0),
		Vector3(10, 0, 0),
		Vector3(0.5, 0, 0),
		Vector3(0.5, 0, 0),
		Vector3(0.35, 0, 0),
		false, false,
		0.01,
		_wrister_cfg())
	assert_gt(result.direction.x, 0.0, "direction toward the target (+X)")

# ── Wrister: full charge branch ──────────────────────────────────────────────

func test_wrister_full_charge_maxes_power() -> void:
	var result: Dictionary = ShotMechanics.release_wrister(
		Vector3.ZERO,
		Vector3(10, 0, 0),
		Vector3(0.5, 0, 0),
		Vector3(0.5, 0, 0),
		Vector3(0.35, 0, 0),
		false, false,
		5.0,                            # over max_wrister_charge_distance
		_wrister_cfg())
	assert_almost_eq(result.power, 25.0, 0.01, "over-full charge clamps to max_wrister_power")

func test_wrister_backhand_penalty() -> void:
	var cfg := _wrister_cfg()
	# Right-handed forehand: blade on +X side of shoulder → sign matches hand_sign (+1)
	var forehand: Dictionary = ShotMechanics.release_wrister(
		Vector3.ZERO, Vector3(10, 0, 0),
		Vector3(0.5, 0, 0),          # blade_world
		Vector3(0.5, 0, 0),          # blade_local
		Vector3(0.35, 0, 0),         # shoulder_local
		false, false,                # left-handed, elevated
		3.0,                         # full charge
		cfg)
	# Right-handed backhand: blade on -X side of shoulder → sign mismatches hand_sign
	var backhand: Dictionary = ShotMechanics.release_wrister(
		Vector3.ZERO, Vector3(10, 0, 0),
		Vector3(-0.5, 0, 0),
		Vector3(-0.5, 0, 0),
		Vector3(0.35, 0, 0),
		false, false,
		3.0,
		cfg)
	assert_lt(backhand.power, forehand.power, "backhand penalised by backhand_power_coefficient")

func test_wrister_elevation_adds_y_component() -> void:
	var cfg := _wrister_cfg()
	var flat: Dictionary = ShotMechanics.release_wrister(
		Vector3.ZERO, Vector3(10, 0, 0),
		Vector3(0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.35, 0, 0),
		false, false, 3.0, cfg)
	var elevated: Dictionary = ShotMechanics.release_wrister(
		Vector3.ZERO, Vector3(10, 0, 0),
		Vector3(0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.35, 0, 0),
		false, true, 3.0, cfg)
	assert_almost_eq(flat.direction.y, 0.0, 0.01)
	assert_gt(elevated.direction.y, 0.0)

# ── Slapper ──────────────────────────────────────────────────────────────────

func test_slapper_power_scales_with_charge_time() -> void:
	var cfg := _slapper_cfg()
	var short_result: Dictionary = ShotMechanics.release_slapper(
		Vector3.ZERO, Vector3(10, 0, 0), false, 0.1, cfg)
	var long_result: Dictionary = ShotMechanics.release_slapper(
		Vector3.ZERO, Vector3(10, 0, 0), false, 1.0, cfg)
	assert_gt(long_result.power, short_result.power)
	assert_almost_eq(long_result.power, cfg.max_slapper_power, 0.01)

func test_slapper_elevation() -> void:
	var cfg := _slapper_cfg()
	var flat: Dictionary = ShotMechanics.release_slapper(
		Vector3.ZERO, Vector3(10, 0, 0), false, 1.0, cfg)
	var elevated: Dictionary = ShotMechanics.release_slapper(
		Vector3.ZERO, Vector3(10, 0, 0), true, 1.0, cfg)
	assert_almost_eq(flat.direction.y, 0.0, 0.01)
	assert_gt(elevated.direction.y, 0.0)

# ── Wall-pin release ─────────────────────────────────────────────────────────

func test_wall_pin_fires_above_threshold() -> void:
	assert_true(ShotMechanics.should_release_on_wall_pin(0.5, 0.3))

func test_wall_pin_ignored_below_threshold() -> void:
	assert_false(ShotMechanics.should_release_on_wall_pin(0.2, 0.3))

func test_wall_pin_ignored_at_threshold() -> void:
	assert_false(ShotMechanics.should_release_on_wall_pin(0.3, 0.3), "equal is not above")

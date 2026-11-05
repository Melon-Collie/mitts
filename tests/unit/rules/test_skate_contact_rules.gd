extends GutTest

# SkateContactRules — the two boots a loose puck meets on the ice, the gap
# between them, and what the boot does with it: a kick to the stick or a bounce.

const FORWARD := Vector2(0.0, -1.0)  # facing −Z; right is +X


func _contact() -> SkateContactRules.Contact:
	return SkateContactRules.Contact.new()


# ── The boots stand where the legs put them ──────────────────────────────────

func test_rest_spacing_is_the_hip_the_gait_stands_the_skate_under() -> void:
	assert_eq(SkateContactRules.REST_HALF_SPACING_M, GaitPose.HIP_HALF_WIDTH)


func test_stance_spacing_is_the_width_the_gait_sets_the_skates_out() -> void:
	var controller := SkaterController.new()
	assert_eq(SkateContactRules.STANCE_EXTRA_SPACING_M, controller.stance_width_m)
	controller.free()


func test_stance_sets_the_boots_wider() -> void:
	assert_gt(SkateContactRules.half_spacing(true), SkateContactRules.half_spacing(false))


# ── Contact ───────────────────────────────────────────────────────────────────

func test_puck_across_a_boot_meets_it() -> void:
	var spacing: float = SkateContactRules.half_spacing(false)
	var c := _contact()
	# From the right, across the line of the right boot.
	assert_true(SkateContactRules.find_contact(
			Vector2(1.0, 0.0), Vector2(spacing, 0.0), FORWARD, spacing, c))
	assert_almost_eq(c.normal.x, 1.0, 0.01, "it meets the boot's outside face")


func test_puck_up_the_middle_goes_through_the_gap() -> void:
	var spacing: float = SkateContactRules.half_spacing(false)
	var c := _contact()
	# Straight up between the skates, heel to toe and on.
	assert_false(SkateContactRules.find_contact(
			Vector2(0.0, 1.0), Vector2(0.0, -1.0), FORWARD, spacing, c))


func test_the_gap_is_open_for_the_puck() -> void:
	var gap: float = 2.0 * (SkateContactRules.REST_HALF_SPACING_M - SkateContactRules.reach())
	assert_gt(gap, 0.0, "a puck fits between the boots at rest")


func test_puck_beside_the_skater_passes_wide_of_the_boots() -> void:
	var spacing: float = SkateContactRules.half_spacing(false)
	var c := _contact()
	var wide: float = spacing + SkateContactRules.reach() + 0.01
	assert_false(SkateContactRules.find_contact(
			Vector2(wide, 1.0), Vector2(wide, -1.0), FORWARD, spacing, c))


func test_a_fast_puck_cannot_tunnel_through_a_boot() -> void:
	var spacing: float = SkateContactRules.half_spacing(false)
	var c := _contact()
	# 38 m/s over one 90 Hz tick, ending past the far side of the right boot.
	var step: float = 38.0 / 90.0
	assert_true(SkateContactRules.find_contact(
			Vector2(spacing + step * 0.5, 0.0), Vector2(spacing - step * 0.5, 0.0),
			FORWARD, spacing, c))
	assert_gt(c.normal.x, 0.0, "it struck the side it came from")


func test_the_boots_turn_with_the_facing() -> void:
	var spacing: float = SkateContactRules.half_spacing(false)
	var c := _contact()
	var east := Vector2(1.0, 0.0)  # right is then +Z
	assert_true(SkateContactRules.find_contact(
			Vector2(0.0, 1.0), Vector2(0.0, spacing), east, spacing, c))
	assert_false(SkateContactRules.find_contact(
			Vector2(1.0, 0.0), Vector2(-1.0, 0.0), east, spacing, c),
			"the line between the boots now runs along x")


func test_only_a_puck_moving_into_the_boot_is_approaching() -> void:
	assert_true(SkateContactRules.approaching(Vector2(-3.0, 0.0), Vector2(1.0, 0.0)))
	assert_false(SkateContactRules.approaching(Vector2(3.0, 0.0), Vector2(1.0, 0.0)))


func test_a_puck_above_the_boot_clears_it() -> void:
	assert_true(SkateContactRules.puck_below_boot_top(GameRules.PUCK_COLLISION_HALF_HEIGHT))
	assert_false(SkateContactRules.puck_below_boot_top(
			SkateContactRules.BOOT_HEIGHT_M + GameRules.PUCK_COLLISION_HALF_HEIGHT + 0.01))


# ── Who kicks ─────────────────────────────────────────────────────────────────

func test_own_teams_slow_puck_is_kicked() -> void:
	assert_true(SkateContactRules.can_kick(5.0, 0, 0, true, false))


func test_nobodys_puck_is_kicked() -> void:
	assert_true(SkateContactRules.can_kick(5.0, -1, 1, true, false))


func test_an_opponents_puck_is_not_kicked() -> void:
	assert_false(SkateContactRules.can_kick(5.0, 1, 0, true, false))


func test_a_puck_too_fast_for_a_boot_is_not_kicked() -> void:
	assert_false(SkateContactRules.can_kick(
			SkateContactRules.KICK_MAX_SPEED_M_S + 0.5, 0, 0, true, false))


func test_a_busy_stick_takes_no_kick() -> void:
	assert_false(SkateContactRules.can_kick(5.0, 0, 0, false, false))


func test_an_opponent_on_him_takes_the_kick_away() -> void:
	assert_false(SkateContactRules.can_kick(5.0, 0, 0, true, true))


func test_pressure_is_an_opponent_within_reach() -> void:
	var r: float = SkateContactRules.PRESSURE_RADIUS_M
	assert_true(SkateContactRules.pressures(Vector3.ZERO, Vector3(r - 0.1, 0.0, 0.0)))
	assert_false(SkateContactRules.pressures(Vector3.ZERO, Vector3(r + 0.1, 0.0, 0.0)))


# ── The kick ──────────────────────────────────────────────────────────────────

func test_the_kick_sends_the_puck_at_the_blade() -> void:
	var v: Vector3 = SkateContactRules.kick_velocity(
			Vector3.ZERO, Vector2(0.13, 0.0), Vector2(0.5, -0.8), FORWARD)
	var dir := Vector2(v.x, v.z).normalized()
	var want := (Vector2(0.5, -0.8) - Vector2(0.13, 0.0)).normalized()
	assert_almost_eq(dir.dot(want), 1.0, 0.001)
	assert_eq(v.y, 0.0, "the kick stays on the ice")


func test_the_kick_is_a_touch_in_the_skaters_frame() -> void:
	var skating := Vector3(0.0, 0.0, -6.0)
	var v: Vector3 = SkateContactRules.kick_velocity(
			skating, Vector2(0.13, 0.0), Vector2(0.4, -1.2), FORWARD)
	var push: float = (v - skating).length()
	assert_between(push, SkateContactRules.KICK_MIN_PUSH_M_S, SkateContactRules.KICK_MAX_PUSH_M_S)
	assert_lt(push, 22.0 * 0.5, "a soft catch for the blade it reaches")


func test_a_blade_over_the_contact_sends_it_ahead() -> void:
	var v: Vector3 = SkateContactRules.kick_velocity(
			Vector3.ZERO, Vector2(0.13, 0.0), Vector2(0.13, 0.0), FORWARD)
	assert_almost_eq(Vector2(v.x, v.z).normalized().dot(FORWARD), 1.0, 0.001)


# ── The bounce ────────────────────────────────────────────────────────────────

func test_a_bounce_comes_off_the_boot_slower() -> void:
	var v: Vector3 = SkateContactRules.bounce_velocity(
			Vector3(-6.0, 0.0, 0.0), Vector3.ZERO, Vector2(1.0, 0.0))
	assert_gt(v.x, 0.0, "back the way it came")
	assert_lt(v.x, 6.0, "the boot keeps some of it")


func test_a_skater_skating_onto_a_still_puck_pushes_it_ahead() -> void:
	# The puck is still; the skater comes on at 4 m/s along −Z and meets it on
	# the boot's toe, whose normal faces ahead.
	var v: Vector3 = SkateContactRules.bounce_velocity(
			Vector3.ZERO, Vector3(0.0, 0.0, -4.0), FORWARD)
	assert_lt(v.z, -4.0, "it leaves ahead of him")

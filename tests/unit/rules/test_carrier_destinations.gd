extends GutTest

# AICarrierDestinations: which places a carry can be for, from where, on whose
# left, and the hysteresis that keeps the plan. Team 0 defends +Z and attacks −Z,
# so the carrier's left is −X.

const K := AICarrierDestinations.Kind


func _ctx(self_pos: Vector3, team_size: int = 3) -> RoleContext:
	var ctx := RoleContext.new()
	ctx.self_pos = self_pos
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_size = team_size
	return ctx


func _menu(self_pos: Vector3, team_size: int = 3) -> AICarrierDestinations:
	var d := AICarrierDestinations.new()
	d.fill(_ctx(self_pos, team_size))
	return d


func _spot(d: AICarrierDestinations, kind: int) -> Vector3:
	return d.spots[d.kinds.find(kind)]


func test_the_neutral_zone_offers_the_slot_the_wide_entries_and_regroup() -> void:
	var d := _menu(Vector3(1.0, 0.0, 0.0))
	assert_eq(d.kinds, [K.SLOT, K.WIDE_LEFT, K.WIDE_RIGHT, K.REGROUP] as Array[int])
	assert_lt(_spot(d, K.WIDE_LEFT).x, 0.0, "his left, attacking −Z, is −X")
	assert_lt(_spot(d, K.WIDE_LEFT).z, -GameRules.BLUE_LINE_Z, "the entry is past the line")
	var regroup: Vector3 = _spot(d, K.REGROUP)
	assert_between(regroup.z, 0.0, GameRules.BLUE_LINE_Z, "regroup stays out of our zone")


func test_the_attacking_zone_offers_the_slot_and_the_half_walls() -> void:
	var d := _menu(Vector3(0.0, 0.0, -14.0))
	assert_eq(d.kinds, [K.SLOT, K.WIDE_LEFT, K.WIDE_RIGHT] as Array[int])
	assert_almost_eq(_spot(d, K.WIDE_RIGHT).z, -GameRules.ICING_FACEOFF_DOT_Z, 0.001)


func test_our_zone_offers_the_slot_and_the_exits() -> void:
	var d := _menu(Vector3(3.0, 0.0, 15.0))
	assert_eq(d.kinds, [K.SLOT, K.EXIT_LEFT, K.EXIT_RIGHT] as Array[int])
	assert_lt(_spot(d, K.EXIT_LEFT).z, GameRules.BLUE_LINE_Z, "the exit is past our line")


func test_behind_our_net_in_5v5_the_wheel_appears_only_round_the_cage() -> void:
	var behind := Vector3(2.0, 0.0, GameRules.GOAL_LINE_Z + 1.5)
	var five := _menu(behind, 5)
	assert_true(five.kinds.has(K.WALKOUT_LEFT) and five.kinds.has(K.WALKOUT_RIGHT))
	assert_true(five.kinds.has(K.WHEEL_LEFT), "the far wall is round the cage")
	assert_false(five.kinds.has(K.WHEEL_RIGHT), "the near wall is straight up the boards")
	assert_false(_menu(behind, 3).kinds.has(K.WHEEL_LEFT), "3v3 has no wheel")


func test_a_destination_he_is_already_at_is_not_on_the_menu() -> void:
	var d := _menu(Vector3(1.0, 0.0, 0.0))
	var at := _menu(_spot(d, K.REGROUP) + Vector3(0.0, 0.0, -1.0))
	assert_false(at.kinds.has(K.REGROUP))
	var on_slot := _menu(AICarrierField.slot_anchor(1.0))
	assert_true(on_slot.kinds.has(K.SLOT), "except the slot: the drive at the net is still on")


func test_the_incumbent_keeps_the_plan_inside_the_margin() -> void:
	var d := _menu(Vector3(1.0, 0.0, 0.0))
	var totals: Array[float] = [0.30, 0.20, 0.10, 0.05]
	d.choose(totals)
	assert_eq(d.chosen_kind, K.SLOT)
	var near: float = 0.30 * (1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC) - 0.01
	totals = [0.30, near, 0.10, 0.05]
	d.choose(totals)
	assert_eq(d.chosen_kind, K.SLOT, "a challenger inside the margin does not take it")
	assert_eq(d.chosen_total, 0.30, "and the honest total is what competes")
	totals = [0.30, near + 0.02, 0.10, 0.05]
	d.choose(totals)
	assert_eq(d.chosen_kind, K.WIDE_LEFT, "past it, it does")


func test_nothing_reachable_chooses_nothing() -> void:
	var d := _menu(Vector3(1.0, 0.0, 0.0))
	var none: Array[float] = [-INF, -INF, -INF, -INF]
	d.choose(none)
	assert_eq(d.chosen_kind, -1)

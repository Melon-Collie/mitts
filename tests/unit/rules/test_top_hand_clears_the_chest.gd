extends GutTest

# TopHandIK.clear_of_chest: the top hand is held out of the trunk. Pulled in
# tight, the solve raises the hand over the shoulder, up inside the chest; the
# keep-out brings it out in front as it rises, without moving the blade.

const STICK_LENGTH: float = 1.30
const BLADE_Y: float = -0.97
const SHOULDER := Vector3(0.22, 0.40, 0.0)
# The chest's section, from the hand's rest height (0.50 under the shoulder) to
# its ceiling (0.10 under it).
const KEEP_OUT := Vector4(0.30, 0.26, 0.50, 0.10)
const SIDE: float = -1.0  # lefty: the blade lives on −X, the top shoulder on +X


func _cfg(keep_out: Vector4 = KEEP_OUT) -> TopHandIK.Config:
	var cfg := TopHandIK.Config.new()
	cfg.stick_length = STICK_LENGTH
	cfg.blade_y = BLADE_Y
	cfg.hand_rest_y = -0.10
	cfg.hand_y_max = 0.30
	cfg.rom_forehand_angle_max = PI * 0.5
	cfg.rom_backhand_angle_max = PI * 0.5
	cfg.rom_forward_reach_max = 0.55
	cfg.rom_forehand_reach_max = 0.25
	cfg.rom_backhand_reach_max = 0.45
	cfg.chest_keep_out = keep_out
	return cfg


func _inside(hand: Vector3) -> float:
	var e := Vector2(hand.x / KEEP_OUT.x, (hand.z - SHOULDER.z) / KEEP_OUT.y)
	return 1.0 - e.length()


# Targets from the skates out past the rim, all round the front of the body.
func _targets() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in 13:
		var bearing: float = lerpf(-PI * 0.5, PI * 0.5, float(i) / 12.0)
		for r: float in [0.2, 0.35, 0.5, 0.7, 0.9, 1.1, 1.4, 1.8]:
			out.append(Vector2(SHOULDER.x + sin(bearing) * r, -cos(bearing) * r))
	return out


func test_blade_in_tight_holds_the_hand_in_front_of_the_chest() -> void:
	var ik := TopHandIK.solve(SHOULDER, Vector2(0.15, -0.35), SIDE, _cfg())
	assert_lt(_inside(ik.hand), 0.01, "the hand sits on or outside the trunk")
	assert_lt(ik.hand.z, SHOULDER.z - 0.1, "it is held out in front, not over the shoulder")
	var bare := TopHandIK.solve(SHOULDER, Vector2(0.15, -0.35), SIDE, _cfg(Vector4.ZERO))
	assert_almost_eq(bare.hand.z, SHOULDER.z, 0.001, "without a trunk it sits over the shoulder")


func test_the_blade_never_moves_for_the_trunk() -> void:
	for t: Vector2 in _targets():
		var held := TopHandIK.solve(SHOULDER, t, SIDE, _cfg())
		var bare := TopHandIK.solve(SHOULDER, t, SIDE, _cfg(Vector4.ZERO))
		assert_almost_eq(held.blade, bare.blade, Vector3.ONE * 0.0001, "blade for %s" % t)


# The hand comes out as it rises: none of the way at its rest height, all of
# it at its ceiling.
func test_a_hand_raised_to_its_ceiling_is_left_in_no_chest() -> void:
	var raised: int = 0
	for t: Vector2 in _targets():
		var ik := TopHandIK.solve(SHOULDER, t, SIDE, _cfg())
		if ik.hand.y >= 0.30 - 0.001:
			raised += 1
			assert_lt(_inside(ik.hand), 0.01, "hand for %s" % t)
	assert_gt(raised, 0, "some targets raise the hand to its ceiling")


func test_a_hand_at_rest_height_is_the_models_own() -> void:
	var cfg := _cfg()
	var hand := Vector3(SHOULDER.x, cfg.hand_rest_y, SHOULDER.z)
	assert_eq(TopHandIK.clear_of_chest(hand, Vector3(0.2, BLADE_Y, -1.0), SHOULDER,
			STICK_LENGTH, cfg.hand_y_max, KEEP_OUT), hand)


func test_the_stick_never_stretches() -> void:
	for t: Vector2 in _targets():
		var ik := TopHandIK.solve(SHOULDER, t, SIDE, _cfg())
		assert_lt(ik.hand.distance_to(ik.blade), STICK_LENGTH + 0.0005, "stick for %s" % t)
		assert_lt(ik.hand.y, 0.30 + 0.0005, "the hand stays under its ceiling for %s" % t)


func test_a_hand_already_clear_is_untouched() -> void:
	var t := Vector2(0.4, -1.6)
	var held := TopHandIK.solve(SHOULDER, t, SIDE, _cfg())
	var bare := TopHandIK.solve(SHOULDER, t, SIDE, _cfg(Vector4.ZERO))
	assert_lt(_inside(bare.hand), 0.0, "the reach carries the hand clear by itself")
	assert_eq(held.hand, bare.hand)


# The hand's path as the blade is pulled in from the rim to the skates has no
# jump where the trunk starts to bite.
func test_pulling_the_blade_in_moves_the_hand_smoothly() -> void:
	var cfg := _cfg()
	for bearing: float in [-0.6, 0.0, 0.6]:
		var prev := Vector3.INF
		for i: int in 200:
			var r: float = lerpf(1.8, 0.25, float(i) / 199.0)
			var t := Vector2(SHOULDER.x + sin(bearing) * r, -cos(bearing) * r)
			var hand: Vector3 = TopHandIK.solve(SHOULDER, t, SIDE, cfg).hand
			if prev != Vector3.INF:
				assert_lt(hand.distance_to(prev), 0.03, "bearing %.1f at %.2f m" % [bearing, r])
			prev = hand


func test_the_clamped_blade_inverse_still_inverts_the_solve() -> void:
	var cfg := _cfg()
	for t: Vector2 in _targets():
		var ik := TopHandIK.solve(SHOULDER, t, SIDE, cfg)
		var hand: Vector3 = TopHandIK.hand_for_clamped_blade(
				SHOULDER, Vector2(ik.blade.x, ik.blade.z), ik.blade.y, SIDE, cfg)
		assert_almost_eq(hand, ik.hand, Vector3.ONE * 0.001, "inverse for %s" % t)

extends GutTest

# The executable spec for the tables in player_attributes.gd: two body dials
# (HEIGHT in inches, WEIGHT in lbs inside the height's band) plus four lateral
# gear slots, neutral at 6'1" / 201 lbs / all-balanced where every multiplier
# is 1.0. Scripts/domain/state/CLAUDE.md has the model.

const H_MIN: int = PlayerAttributes.HEIGHT_MIN     # 5'7" (67")
const H_MED: int = PlayerAttributes.HEIGHT_MEDIUM  # 6'1" (73")
const H_MAX: int = PlayerAttributes.HEIGHT_MAX     # 6'8" (80")

const BASE_MAX_SPEED: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
const MS_TO_MPH: float = 2.23694


func _body(h: int, w: int) -> PlayerAttributes:
	return PlayerAttributes.new(h, w)


# ── Neutral identity ──────────────────────────────────────────────────────────
func test_neutral_is_all_ones() -> void:
	var a := PlayerAttributes.neutral()
	assert_eq(a.height, H_MED)
	assert_eq(a.weight, 201)
	assert_eq(a.profile, PlayerAttributes.GEAR_BALANCED)
	# 6'1"/201/balanced must equal the controller's defaults everywhere.
	assert_almost_eq(a.speed_mult(), 1.0, 0.0001, "speed")
	assert_almost_eq(a.top_speed_mult(), 1.0, 0.0001, "top speed")
	assert_almost_eq(a.accel_mult(), 1.0, 0.0001, "accel")
	assert_almost_eq(a.agility_mult(), 1.0, 0.0001, "agility")
	assert_almost_eq(a.shot_power_mult(), 1.0, 0.0001, "shot")
	assert_almost_eq(a.mass_mult(), 1.0, 0.0001, "mass")
	assert_almost_eq(a.girth_mult(), 1.0, 0.0001, "girth")


func test_neutral_derived_levers() -> void:
	var a := PlayerAttributes.neutral()
	assert_almost_eq(a.glide_drag_mult(), 1.0, 0.0001, "glide")
	assert_almost_eq(a.shot_charge_mult(), 1.0, 0.0001, "charge")
	assert_almost_eq(a.carry_speed_mult(), 0.9576, 0.001, "carry at neutral")


# ── Weight band (BMI interval + absolute playable-mass floor) ─────────────────
func test_weight_band_pounds_table() -> void:
	# Spot-check the authored table: lbs = BMI·in²/703, floored at 160.
	assert_eq(PlayerAttributes.weight_min(68), 162)       # ratio floor 151 → absolute
	assert_eq(PlayerAttributes.weight_max(68), 191)
	assert_eq(PlayerAttributes.weight_neutral(70), 185)
	assert_eq(PlayerAttributes.weight_min(73), 174)
	assert_eq(PlayerAttributes.weight_neutral(73), 201)  # the NHL-average build
	assert_eq(PlayerAttributes.weight_max(73), 220)
	assert_eq(PlayerAttributes.weight_max(76), 238)
	assert_eq(PlayerAttributes.weight_min(79), 204)
	assert_eq(PlayerAttributes.weight_max(79), 257)


func test_weight_band_covers_real_tall_lean_bodies() -> void:
	# A single flat lean ratio set by short players would forbid real tall-lean
	# NHL bodies. These are listed cards, not invented bodies.
	assert_true(PlayerAttributes.weight_min(76) <= 194,
			"6'4 floor (%d lb) must reach Rinzel/Dobson" % PlayerAttributes.weight_min(76))
	for card: Array in [[76, 195], [76, 194], [78, 207], [69, 162], [70, 165], [72, 175],
			[74, 185], [72, 170], [72, 172], [68, 165]]:
		var h: int = card[0]
		var w: int = card[1]
		assert_eq(_body(h, w).weight, w,
				"%d\"/%d lb is a real NHL body and must survive coercion" % [h, w])
	# …while the absolute floor still forbids a body no NHL player has ever had.
	assert_eq(_body(68, 140).weight, PlayerAttributes.MIN_PLAYABLE_LBS)


func test_band_edges_are_fitted_to_their_tails() -> void:
	# The lean side reaches every sampled body (see the card list above); the
	# heavy side accepts two exclusions, the league's two most extreme BMIs.
	assert_lt(_body(75, 238).weight, 238, "Ovechkin — accepted heavy exclusion")
	assert_lt(_body(78, 255).weight, 255, "Zadorov — accepted heavy exclusion")
	# The absolute floor IS the lightest player in the NHL — Hutson, 5'9"/162.
	assert_eq(PlayerAttributes.MIN_PLAYABLE_LBS, 162)
	assert_eq(_body(69, 162).weight, 162, "the lightest real body is buildable")
	assert_gt(_body(69, 155).weight, 155, "…and nothing under it is")
	# Neither floor may reopen the bodies that are past the tail everywhere:
	# no 6'4" player has ever been 185 lb, nor a 5'10" player 160.
	assert_gt(PlayerAttributes.weight_min(76), 185)
	assert_gt(PlayerAttributes.weight_min(70), 160)


func test_frame_t_pins_all_three_anchors_at_every_height() -> void:
	# The band is asymmetric about MEDIUM, so frame_t is piecewise. The
	# invariant that buys: min/neutral/max land on exactly 0/0.5/1 everywhere,
	# so a neutral build keeps its 1.0 multipliers at any height.
	for h: int in range(PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX + 1):
		assert_almost_eq(_body(h, PlayerAttributes.weight_min(h)).frame_t(),
				0.0, 0.0001, "lean edge at %d\"" % h)
		assert_almost_eq(_body(h, PlayerAttributes.weight_neutral(h)).frame_t(),
				0.5, 0.0001, "neutral at %d\"" % h)
		assert_almost_eq(_body(h, PlayerAttributes.weight_max(h)).frame_t(),
				1.0, 0.0001, "heavy edge at %d\"" % h)


func test_weight_for_frame_t_round_trips() -> void:
	# The picker's actual guarantee: drag the height slider away and back and
	# you land on the SAME pound. That is the pounds round-trip w → t → w, and
	# it must be exact at every height and every legal weight.
	#
	# Note this is the right way to state it — a frame-t round-trip (t → w → t)
	# cannot be exact, because weight is quantized to integer pounds. At 5'7"
	# the lean half of the band is only 9 lb wide (the absolute playable-mass
	# floor at 160 sits just under the 169 neutral), so one pound is 0.056 of
	# frame-t and half-pound rounding alone costs 0.028. Asserting pounds
	# instead of frame-t tests the invariant that matters and stays honest at
	# the squeezed heights.
	var misses: Array[String] = []
	for h: int in range(PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX + 1):
		for w: int in range(PlayerAttributes.weight_min(h), PlayerAttributes.weight_max(h) + 1):
			var back: int = PlayerAttributes.weight_for_frame_t(
					h, PlayerAttributes.frame_t_for(h, w))
			if back != w:
				misses.append("%d\"/%d lb → %d lb" % [h, w, back])
	assert_eq(misses.size(), 0, "pounds must round-trip exactly: %s" % ", ".join(misses))
	# And the frame anchors still land on the band's named rows, to the pound.
	for h: int in [67, 68, 70, 73, 76, 79, 80]:
		assert_eq(PlayerAttributes.weight_for_frame_t(h, 0.0), PlayerAttributes.weight_min(h))
		assert_eq(PlayerAttributes.weight_for_frame_t(h, 0.5), PlayerAttributes.weight_neutral(h))
		assert_eq(PlayerAttributes.weight_for_frame_t(h, 1.0), PlayerAttributes.weight_max(h))


func test_implausible_bodies_unrepresentable() -> void:
	# 6'6"/160 (BMI ~18.5) coerces up to the band floor — by construction, not rule.
	var beanpole := _body(78, 160)
	assert_true(beanpole.weight >= PlayerAttributes.weight_min(78),
			"underweight clamps to band floor (%d)" % beanpole.weight)
	# 5'8"/240 clamps down to the band ceiling.
	assert_eq(_body(68, 240).weight, 191)


func test_zero_weight_coerces_to_neutral_frame() -> void:
	# A defaulted wire arg or roster card (weight 0) lands on the height's
	# neutral frame.
	assert_eq(_body(H_MIN, 0).weight, 169)   # 5'7"
	assert_eq(_body(H_MED, 0).weight, 201)
	assert_eq(_body(H_MAX, 0).weight, 241)   # 6'8"


func test_frame_t_spans_band() -> void:
	assert_almost_eq(_body(H_MED, 174).frame_t(), 0.0, 0.01, "lean edge")
	assert_almost_eq(_body(H_MED, 201).frame_t(), 0.5, 0.01, "neutral mid")
	assert_almost_eq(_body(H_MED, 220).frame_t(), 1.0, 0.01, "heavy edge")


# ── Height: no speed, agility and burst slopes, shot baseline ──────────────────
func test_top_speed_is_body_free() -> void:
	# Size never buys speed: if it did, every build would be the tallest one.
	for h: int in [H_MIN, 70, H_MED, 76, H_MAX]:
		for w: int in [PlayerAttributes.weight_min(h), PlayerAttributes.weight_max(h)]:
			assert_almost_eq(_body(h, w).top_speed_mult(), 1.0, 1e-6,
					"top speed at %d\"/%d" % [h, w])


func test_agility_small_favored() -> void:
	# Neutral-frame builds. The piecewise frame_t pins every height's neutral to
	# exactly 0.5, so the frame term is exactly 1.0 and these are pure height.
	assert_almost_eq(_body(H_MIN, 0).agility_mult(), 1.065, 0.0001)
	assert_almost_eq(_body(H_MAX, 0).agility_mult(), 0.920, 0.0001)
	# The old end heights kept their values when the anchors moved out.
	assert_almost_eq(_body(68, 0).agility_mult(), 1.050, 0.0001, "5'8\" unchanged")
	assert_almost_eq(_body(79, 0).agility_mult(), 0.930, 0.0001, "6'7\" unchanged")
	assert_true(_body(H_MIN, 0).agility_mult() > _body(H_MED, 0).agility_mult())


func test_shot_big_favored_and_nhl_anchored() -> void:
	assert_true(_body(H_MAX, 0).shot_power_mult() > _body(H_MIN, 0).shot_power_mult())
	# League average = neutral (~89.5 mph slapper on the 40 m/s base).
	assert_almost_eq(40.0 * _body(H_MED, 0).shot_power_mult() * MS_TO_MPH, 89.5, 1.0)
	# Body-only ceiling ≈ 98.7 mph at 6'8" (the flex gear slot re-widens it further).
	assert_between(40.0 * _body(H_MAX, 0).shot_power_mult() * MS_TO_MPH, 97.5, 100.0)


func test_continuous_height_interpolates_between_anchors() -> void:
	# Uses a height-only lever (shot) so nothing on the frame axis can wobble the
	# pure-height interpolation being pinned.
	var lo := _body(70, 0).shot_power_mult()
	var hi := _body(73, 0).shot_power_mult()
	var mid := _body(71, 0).shot_power_mult()
	assert_true(mid > lo and mid < hi, "71\" shot falls between the 70\" and 73\" rows")
	assert_almost_eq(mid, lerpf(lo, hi, 1.0 / 3.0), 0.0001, "linear between anchors")


func test_extended_range_preserves_the_old_heights() -> void:
	# The end anchors moved out (5'8"→5'7", 6'7"→6'8") rather than gaining rows.
	# Every height that was playable before must keep the values it had.
	assert_eq(PlayerAttributes.HEIGHT_MIN, 67)
	assert_eq(PlayerAttributes.HEIGHT_MAX, 80)
	var expected_shot: Dictionary = {68: 0.900, 70: 0.940, 73: 1.000, 76: 1.050, 79: 1.090}
	for h: int in expected_shot:
		assert_almost_eq(_body(h, 0).shot_power_mult(), float(expected_shot[h]), 0.0005,
				"%d\" shot power unchanged" % h)
	# …and the new ends genuinely extend each curve rather than copying a neighbour.
	assert_lt(_body(67, 0).shot_power_mult(), _body(68, 0).shot_power_mult())
	assert_gt(_body(80, 0).shot_power_mult(), _body(79, 0).shot_power_mult())
	assert_gt(_body(67, 0).agility_mult(), _body(68, 0).agility_mult())
	assert_lt(_body(80, 0).agility_mult(), _body(79, 0).agility_mult())
	# The new heights' weight bands, and that they cover the bodies they exist for.
	assert_eq(PlayerAttributes.weight_max(67), 185)   # Caufield 5'7"/174 fits
	assert_eq(_body(67, 174).weight, 174)
	assert_eq(PlayerAttributes.weight_max(80), 264)   # Rempe 6'8"/261 fits
	assert_eq(_body(80, 261).weight, 261)


# ── Weight: accel fork, linear mass ───────────────────────
func test_accel_small_favored() -> void:
	# Burst rides height too: the shorter leg cycles its stride faster.
	assert_gt(_body(H_MIN, 0).accel_mult(), _body(H_MED, 0).accel_mult())
	assert_lt(_body(H_MAX, 0).accel_mult(), _body(H_MED, 0).accel_mult())
	assert_almost_eq(_body(H_MED, 0).accel_mult(), 1.0, 0.0001)


func test_accel_lean_favored() -> void:
	var lean := _body(H_MED, 174)
	var heavy := _body(H_MED, 220)
	assert_true(lean.accel_mult() > heavy.accel_mult(), "lean gets the first step")
	assert_almost_eq(lean.accel_mult(), 1.08, 0.001)
	assert_almost_eq(heavy.accel_mult(), 0.97, 0.001)


func test_mass_linear_in_displayed_weight() -> void:
	assert_almost_eq(_body(H_MED, 201).mass_mult(), 1.0, 0.0001)
	# Same pounds = same mass regardless of height — mass IS the displayed weight.
	assert_almost_eq(_body(73, 210).mass_mult(), _body(76, 210).mass_mult(), 0.0001)
	# Full spread ≈ 1.61× — mass carries the physical game.
	var ratio: float = _body(H_MAX, PlayerAttributes.weight_max(H_MAX)).mass_mult() \
			/ _body(H_MIN, PlayerAttributes.weight_min(H_MIN)).mass_mult()
	assert_between(ratio, 1.55, 1.70)


func test_frame_interpolates_between_anchors() -> void:
	# A weight between two frame anchors lerps the frame tables continuously.
	var lo := _body(H_MED, 174).accel_mult()   # LEAN anchor (frame-t 0.0)
	var hi := _body(H_MED, 188).accel_mult()   # LIGHT anchor (frame-t 0.25)
	var mid := _body(H_MED, 181).accel_mult()
	assert_true(mid < lo and mid > hi, "181 lbs falls between the LEAN and LIGHT rows")


# ── The constitution: no fidelity scaling, checking is mass-emergent ──────────
func test_mass_carries_the_physical_edge() -> void:
	var tank := _body(H_MAX, 257)
	var waterbug := _body(H_MIN, PlayerAttributes.weight_min(H_MIN))
	assert_true(tank.mass_mult() > waterbug.mass_mult(),
			"the physical edge lives entirely in mass")


func test_agility_bites_with_weight() -> void:
	# F = mv²/r: heavy turns wide and stops long. Frame term multiplies the
	# height baseline.
	var lean := _body(H_MED, 174)
	var heavy := _body(H_MED, 220)
	assert_almost_eq(lean.agility_mult(), 1.03, 0.001, "lean agility bonus")
	assert_almost_eq(heavy.agility_mult(), 0.96, 0.001, "heavy agility tax")
	# Corner budget, re-pinned at the extended range: the worst body corner
	# (6'8"/264) sits ~0.88 and the best (5'7"/160) ~1.10 — one inch further out
	# at each end than the old 0.89/1.08, leaving the profile gear room to lean.
	assert_between(_body(H_MAX, PlayerAttributes.weight_max(H_MAX)).agility_mult(),
			0.875, 0.89, "worst corner")
	assert_between(_body(H_MIN, PlayerAttributes.weight_min(H_MIN)).agility_mult(),
			1.09, 1.11, "best corner")


func test_glide_follows_mass() -> void:
	# Drag over mass: a heavy-for-his-height body coasts, a tall lean one scrubs.
	var lean := _body(H_MED, 174)
	var heavy := _body(H_MED, 220)
	assert_lt(heavy.glide_drag_mult(), lean.glide_drag_mult(), "the tank coasts")
	assert_almost_eq(_body(H_MED, 201).glide_drag_mult(), 1.0, 0.0001, "neutral glide")
	assert_almost_eq(heavy.glide_drag_mult(), 1.0 / heavy.girth_mult(), 1e-6,
			"drag/mass with area ∝ sqrt(mass·height) is 1 / girth")


func test_girth_widens_with_frame() -> void:
	# Hitbox and silhouette both wear girth: same height, heavier = wider.
	assert_true(_body(H_MED, 220).girth_mult() > _body(H_MED, 174).girth_mult())
	assert_almost_eq(_body(H_MED, 201).girth_mult(), 1.0, 0.0001, "neutral girth")


# ── Derived (coupled) levers ──────────────────────────────────────────────────
func test_wind_up_goes_with_shot_power() -> void:
	# The long lever loads a harder shot and takes longer to: big shoots harder,
	# small gets the quicker release.
	var small := _body(H_MIN, 0)
	var big := _body(H_MAX, 0)
	assert_almost_eq(small.shot_charge_mult(), small.shot_power_mult(), 0.0001)
	assert_lt(small.shot_charge_mult(), 1.0, "small winds up quicker")
	assert_gt(big.shot_charge_mult(), 1.0, "big winds up slower")


# ── Top speed ─────────────────────────────────────────────────────────────────
func test_top_speed_band_is_the_skates() -> void:
	# Every body skates the neutral top speed; only the skate profile moves it.
	for h: int in [H_MIN, H_MED, H_MAX]:
		var top_mph: float = BASE_MAX_SPEED * _body(h, 0).top_speed_mult() * MS_TO_MPH
		assert_almost_eq(top_mph, BASE_MAX_SPEED * MS_TO_MPH, 0.001,
				"body-only top speed at %d\"" % h)


# ── Gear slots: stored and coerced ────────────────────────────────────────────
func test_gear_defaults_balanced_and_clamps() -> void:
	var a := PlayerAttributes.new(H_MED, 201, -3, 99, 2, 0)
	assert_eq(a.profile, 0, "out-of-range gear clamps low")
	assert_eq(a.curve, 2, "out-of-range gear clamps high")
	assert_eq(a.flex, PlayerAttributes.FLEX_HIGH)
	assert_eq(a.length, PlayerAttributes.LENGTH_SHORT)
	assert_eq(PlayerAttributes.neutral().curve, PlayerAttributes.GEAR_BALANCED)


func test_equals_includes_gear() -> void:
	var a := PlayerAttributes.new(H_MED, 201, 1, 1, 1, 1)
	var b := PlayerAttributes.new(H_MED, 201, 1, 1, 1, 2)
	assert_false(a.equals(b), "length differs")
	assert_true(a.equals(PlayerAttributes.new(H_MED, 201)))


# ── Serialization ─────────────────────────────────────────────────────────────
func test_dict_round_trip() -> void:
	var a := PlayerAttributes.new(76, 228, 2, 0, 1, 2)
	var b := PlayerAttributes.from_dict(a.to_dict())
	assert_true(a.equals(b))
	assert_eq(b.weight, 228)
	assert_eq(b.profile, 2)


func test_from_dict_name_only_is_neutral() -> void:
	# No attribute keys at all → the height's neutral frame.
	var a := PlayerAttributes.from_dict({"name": "Bot 1"})
	assert_true(a.equals(PlayerAttributes.neutral()))
	var tall := PlayerAttributes.from_dict({"height": 79})
	assert_eq(tall.weight, 235)
	assert_eq(tall.profile, PlayerAttributes.GEAR_BALANCED)


# ── Visual tells ──────────────────────────────────────────────────────────────
func test_girth_reads_height_too() -> void:
	# At a fixed frame a taller body is absolutely broader.
	assert_true(_body(H_MAX, 235).girth_mult() > _body(H_MIN, 174).girth_mult())


func test_labels() -> void:
	assert_eq(PlayerAttributes.inches_label(73), "6'1\"")


# ── Stick length ──────────────────────────────────────────────────────────────
func test_stick_length_lean() -> void:
	# A lean on the height's cut (never an absolute pick): ±4% around the
	# height band center, so max-height + LONG can't stack absolute reach
	# beyond the tuned corner.
	var std := PlayerAttributes.neutral()
	var short := PlayerAttributes.new(73, 201, 1, 1, 1, PlayerAttributes.LENGTH_SHORT)
	var long := PlayerAttributes.new(73, 201, 1, 1, 1, PlayerAttributes.LENGTH_LONG)
	assert_almost_eq(std.stick_len_mult(), 1.028, 0.0001, "STANDARD = the height's cut")
	assert_almost_eq(short.stick_len_mult(), 1.028 * 0.96, 0.0001)
	assert_almost_eq(long.stick_len_mult(), 1.028 * 1.04, 0.0001)
	# All four slots are live — a balanced loadout is the only zero-lean one.
	assert_true(PlayerAttributes.new(73, 201).equals(PlayerAttributes.neutral()))


# ── Skate profile: shifty / stability / power ───────────────────────────────────────────
func test_stability_is_the_base_skate() -> void:
	# Stability is the default and the league base: every profile lean is 1.0.
	var a := PlayerAttributes.neutral()
	assert_eq(a.profile, PlayerAttributes.PROFILE_STABILITY)
	for lean: float in [a.speed_mult(), a.crossover_mult(), a.backward_mult(),
			a.stance_grip_mult(), a.sidestep_mult()]:
		assert_almost_eq(lean, 1.0, 1e-6)


func test_each_profile_wins_one_ice_and_pays_another() -> void:
	var shifty := PlayerAttributes.new(73, 201, PlayerAttributes.PROFILE_SHIFTY, 1, 1, 1)
	var stable := PlayerAttributes.neutral()
	var power := PlayerAttributes.new(73, 201, PlayerAttributes.PROFILE_POWER, 1, 1, 1)
	# Shifty owns tight space.
	for other: PlayerAttributes in [stable, power]:
		assert_gt(shifty.agility_mult(), other.agility_mult(), "shifty owns the corner")
		assert_gt(shifty.accel_mult(), other.accel_mult(), "shifty owns the first step")
		assert_gt(shifty.stance_grip_mult(), other.stance_grip_mult(), "shifty owns the stance")
		assert_gt(shifty.sidestep_mult(), other.sidestep_mult(), "shifty owns the side-step")
	# Stability owns skating backward.
	for other: PlayerAttributes in [shifty, power]:
		assert_gt(stable.backward_mult(), other.backward_mult(), "stability owns backward")
	# Power owns open ice.
	for other: PlayerAttributes in [shifty, stable]:
		assert_gt(power.top_speed_mult(), other.top_speed_mult(), "power owns the top end")
		assert_lt(power.glide_drag_mult(), other.glide_drag_mult(), "power owns the coast")
		assert_gt(power.crossover_mult(), other.crossover_mult(), "power owns the crossover")
	# …and each pays where another wins.
	assert_lt(shifty.top_speed_mult(), stable.top_speed_mult(), "shifty pays the top end")
	assert_lt(stable.crossover_mult(), shifty.crossover_mult(), "stability pays the crossover")
	assert_lt(power.agility_mult(), stable.agility_mult(), "power pays the corner")
	assert_lt(power.backward_mult(), shifty.backward_mult(), "power pays backward")


func test_stacked_agility_corners_budgeted() -> void:
	# Body × gear extremes: the involuntary body corners are ~0.88/~1.10, and the
	# self-chosen extremes (heavy tank on power skates / small build on shifty
	# ones) push one gear lean outside them.
	var worst := PlayerAttributes.new(80, 264, PlayerAttributes.PROFILE_POWER, 1, 1, 1)
	var best := PlayerAttributes.new(67, 160, PlayerAttributes.PROFILE_SHIFTY, 1, 1, 1)
	assert_between(worst.agility_mult(), 0.82, 0.84, "worst stacked corner")
	assert_between(best.agility_mult(), 1.15, 1.17, "best stacked corner")


# ── Flex + curve: the shot gear slots ────────────────────────────────────────
func test_flex_is_slapper_stick_vs_wrister_stick() -> void:
	# Stiff: a bigger slapper that needs a longer wind-up (the charge lean goes
	# WITH the power lean, unlike the height coupling). Whippy: more of a
	# wrister without body load. The wrister ceiling is flex-free.
	var whippy := PlayerAttributes.new(73, 201, 1, 1, PlayerAttributes.FLEX_LOW, 1)
	var stiff := PlayerAttributes.new(73, 201, 1, 1, PlayerAttributes.FLEX_HIGH, 1)
	assert_lt(whippy.slapper_power_mult(), stiff.slapper_power_mult(), "stiff slaps harder")
	assert_lt(whippy.shot_charge_mult(), stiff.shot_charge_mult(), "stiff loads slower")
	assert_almost_eq(whippy.shot_power_mult(), stiff.shot_power_mult(), 0.0001,
			"same wrister ceiling")
	assert_gt(whippy.wrister_unloaded_mult(), stiff.wrister_unloaded_mult(),
			"whippy carries more of an unloaded wrister")
	assert_almost_eq(0.6 * whippy.wrister_unloaded_mult(), 0.70, 0.0001)
	assert_almost_eq(0.6 * stiff.wrister_unloaded_mult(), 0.50, 0.0001)
	# So whippy never loses a wrister: ahead on a partial load, level on a full one.
	for stance_load: float in [0.0, 0.5, 1.0]:
		var w: float = WristerLoad.power_share(stance_load, false, 0.6 * whippy.wrister_unloaded_mult(), 1.0)
		var s: float = WristerLoad.power_share(stance_load, false, 0.6 * stiff.wrister_unloaded_mult(), 1.0)
		assert_gte(w, s, "whippy wrister at load %.1f" % stance_load)
	assert_gt(whippy.stick_bend_mult(), stiff.stick_bend_mult(), "whippy visibly bows more")
	# Height trades the same way underneath.
	var tall := PlayerAttributes.new(79, 235)
	assert_gt(tall.shot_charge_mult(), 1.0, "the big frame winds up slower at medium flex")


func test_flex_number_is_fitted_to_the_body() -> void:
	# The DISPLAYED stiffness is a real retail number fitted to weight: the
	# neutral 201 lb build's medium is the most-shipped 85, and the gear pick
	# shifts one rung either way.
	assert_eq(PlayerAttributes.neutral().flex_number(), 85, "neutral shoots an 85")
	assert_eq(PlayerAttributes.new(73, 201, 1, 1, PlayerAttributes.FLEX_LOW, 1).flex_number(), 75)
	assert_eq(PlayerAttributes.new(73, 201, 1, 1, PlayerAttributes.FLEX_HIGH, 1).flex_number(), 100)
	# Both ends of the ladder are reachable, and only by an extreme body on the
	# matching pick.
	assert_eq(PlayerAttributes.new(67, 162, 1, 1, PlayerAttributes.FLEX_LOW, 1).flex_number(),
			PlayerAttributes.FLEX_LADDER[0], "lightest body, whippiest pick")
	assert_eq(PlayerAttributes.new(80, 264, 1, 1, PlayerAttributes.FLEX_HIGH, 1).flex_number(),
			PlayerAttributes.FLEX_LADDER[-1], "heaviest body, stiffest pick")
	# Numbers OVERLAP across bodies — an 85 is the light winger's plank and the
	# heavy defenseman's noodle. That overlap is the whole reason the number
	# stays a display quantity: the gameplay leans read the relative pick.
	assert_eq(PlayerAttributes.new(68, 162, 1, 1, PlayerAttributes.FLEX_HIGH, 1).flex_number(),
			PlayerAttributes.new(77, 240, 1, 1, PlayerAttributes.FLEX_LOW, 1).flex_number(),
			"stiff on a light frame == whippy on a heavy one")


func test_flex_number_is_a_real_rung_for_every_build() -> void:
	# Every playable body × pick lands on a shipping flex, monotone in the pick.
	for inches: int in range(PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX + 1):
		for lbs: int in [PlayerAttributes.weight_min(inches),
				PlayerAttributes.weight_neutral(inches),
				PlayerAttributes.weight_max(inches)]:
			var prev: int = 0
			for pick: int in 3:
				var n: int = PlayerAttributes.new(inches, lbs, 1, 1, pick, 1).flex_number()
				assert_true(PlayerAttributes.FLEX_LADDER.has(n),
						"%d\" %d lb pick %d → %d is a shipping flex" % [inches, lbs, pick, n])
				assert_gt(n, prev, "a stiffer pick reads a higher number")
				prev = n


func test_flex_number_never_reaches_the_gameplay_leans() -> void:
	# Two builds on the same nominal 85 flex still shoot differently: the leans
	# ride the RELATIVE pick, so weight stays out of the shot-power axis. (A
	# two-rung spread needs two very different bodies — the per-height weight
	# band is far too narrow to span it — so each build is measured against its
	# OWN medium-flex twin, which cancels the height term.)
	var light_stiff := PlayerAttributes.new(68, 168, 1, 1, PlayerAttributes.FLEX_HIGH, 1)
	var heavy_whippy := PlayerAttributes.new(78, 245, 1, 1, PlayerAttributes.FLEX_LOW, 1)
	assert_eq(light_stiff.flex_number(), heavy_whippy.flex_number(), "same nominal stick")
	assert_gt(light_stiff.slapper_power_mult(), PlayerAttributes.new(68, 168).slapper_power_mult(),
			"the stiff pick slaps harder than its own medium")
	assert_lt(heavy_whippy.slapper_power_mult(), PlayerAttributes.new(78, 245).slapper_power_mult(),
			"the whippy pick slaps softer than its own — same 85 on the sticker")


func test_curve_trades_loft_ladder_for_backhand() -> void:
	var m88 := PlayerAttributes.new(73, 201, 1, PlayerAttributes.CURVE_CLOSED, 1, 1)
	var m92 := PlayerAttributes.neutral()
	var m28 := PlayerAttributes.new(73, 201, 1, PlayerAttributes.CURVE_OPEN, 1, 1)
	# The angle ladder is the elevation lever: every rung steeper on the M28,
	# flatter on the M88, all rungs under the universal launch-angle guard.
	assert_lt(m88.curve_loft_tan_high(), m92.curve_loft_tan_high(),
			"M88's toe gives the least")
	assert_lt(m92.curve_loft_tan_high(), m28.curve_loft_tan_high())
	assert_lt(m88.curve_loft_tan_low(), m92.curve_loft_tan_low())
	assert_lt(m92.curve_loft_tan_low(), m28.curve_loft_tan_low())
	assert_lt(m88.curve_loft_tan_mid(), m28.curve_loft_tan_mid())
	assert_lt(m28.curve_loft_tan_high(), ShotMechanics.MAX_LOFT_RATIO,
			"the whole ladder sits under the universal guard")
	assert_gt(m88.curve_backhand_mult(), m28.curve_backhand_mult())
	# Backhand relief approaches but never reaches forehand parity: the
	# controller's 0.75 base coefficient stays below 1.0 under the M88.
	assert_lt(0.75 * m88.curve_backhand_mult(), 1.0, "no full-parity backhand")


# GameRules' league-default loft tangents are the M92 rungs written as tan();
# a retune of either side has to move the other.
func test_league_default_loft_is_the_neutral_curve_ladder() -> void:
	var m92 := PlayerAttributes.neutral()
	assert_almost_eq(GameRules.DEFAULT_LOFT_TAN_LOW, m92.curve_loft_tan_low(), 1e-4)
	assert_almost_eq(GameRules.DEFAULT_LOFT_TAN_MID, m92.curve_loft_tan_mid(), 1e-4)
	assert_almost_eq(GameRules.DEFAULT_LOFT_TAN_HIGH, m92.curve_loft_tan_high(), 1e-4)


func test_curve_slap_and_reception_lean_with_the_pattern() -> void:
	# The other half of the M88↔M28 seesaw: the flatter pattern sweeps a
	# squarer slapper contact and cradles a harder feed; the toe hook pays
	# both. M92 is the neutral row on every axis.
	var m88 := PlayerAttributes.new(73, 201, 1, PlayerAttributes.CURVE_CLOSED, 1, 1)
	var m92 := PlayerAttributes.neutral()
	var m28 := PlayerAttributes.new(73, 201, 1, PlayerAttributes.CURVE_OPEN, 1, 1)
	assert_gt(m88.slapper_power_mult(), 1.0, "M88 is the slapper blade")
	assert_almost_eq(m92.slapper_power_mult(), 1.0, 0.0001, "M92 slap-neutral")
	assert_lt(m28.slapper_power_mult(), 1.0, "the toe hook pays the point shot")
	assert_gt(m88.reception_ceiling_mult(), 1.0, "M88 catches the hardest feeds")
	assert_almost_eq(m92.reception_ceiling_mult(), 1.0, 0.0001, "M92 reception-neutral")
	assert_lt(m28.reception_ceiling_mult(), 1.0, "hard feeds bounce off the toe hook")
	# The leans stay leans, not identities: even the M28 receiver still soaks
	# most of the league ceiling (soft/medium passes are unaffected entirely —
	# pickup_max_speed never scales with curve).
	assert_gt(m28.reception_ceiling_mult(), 0.85, "reception lean stays gentle")

extends GutTest

# The shot cue scales with release speed, and live play, the remote broadcast,
# and replay playback all read it from ShotSound — so the curve's shape is the
# only thing left to hold.

const _WRISTER_POWERS: Array[float] = [0.0, 10.0, 14.0, 20.0, 33.0, 40.0]
const _SLAPPER_POWERS: Array[float] = [0.0, 20.0, 30.0, 40.0, 48.0]


func test_louder_and_sharper_with_power() -> void:
	for pair: Array in [[_WRISTER_POWERS, false], [_SLAPPER_POWERS, true]]:
		var powers: Array[float] = pair[0]
		var is_slapper: bool = pair[1]
		for i: int in powers.size() - 1:
			assert_true(ShotSound.volume_db(powers[i + 1], is_slapper)
					>= ShotSound.volume_db(powers[i], is_slapper),
					"volume must not fall from %.0f to %.0f m/s" % [powers[i], powers[i + 1]])
			assert_true(ShotSound.pitch_scale(powers[i + 1], is_slapper)
					>= ShotSound.pitch_scale(powers[i], is_slapper),
					"pitch must not fall from %.0f to %.0f m/s" % [powers[i], powers[i + 1]])


# Past the league band an attribute-boosted shot holds the top of the curve
# rather than running off into clipping.
func test_clamps_outside_the_league_band() -> void:
	assert_almost_eq(ShotSound.intensity(0.0, false), 0.0, 1e-6)
	assert_almost_eq(ShotSound.intensity(100.0, false), 1.0, 1e-6)
	assert_almost_eq(ShotSound.intensity(0.0, true), 0.0, 1e-6)
	assert_almost_eq(ShotSound.intensity(100.0, true), 1.0, 1e-6)


func test_a_quick_pass_is_quieter_than_a_ripped_wrister() -> void:
	var pass_db: float = ShotSound.volume_db(GameRules.DEFAULT_QUICK_PASS_POWER_M_S, false)
	var rip_db: float = ShotSound.volume_db(GameRules.DEFAULT_WRISTER_POWER_MAX_M_S, false)
	assert_lt(pass_db, rip_db - 5.0, "a pass should read as a touch, not a shot")


func test_a_full_slapper_outranks_a_full_wrister() -> void:
	assert_gt(ShotSound.volume_db(GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S, true),
			ShotSound.volume_db(GameRules.DEFAULT_WRISTER_POWER_MAX_M_S, false))

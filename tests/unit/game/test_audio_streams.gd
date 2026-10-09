extends GutTest

# Import flags and level curves that no player ever reports wrongly: a bed that
# stops looping just goes quiet, and a shot at the wrong level just sounds flat.


func test_the_skate_loop_loops() -> void:
	var stream := load("res://Sounds/skate_loop.ogg") as AudioStreamOggVorbis
	assert_not_null(stream)
	assert_true(stream.loop, "skate_loop.ogg.import must set loop=true")


func test_the_crowd_bed_loops() -> void:
	var stream := load("res://Sounds/crowd_ambient.wav") as AudioStreamWAV
	assert_not_null(stream)
	assert_ne(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED,
			"crowd_ambient.wav.import must set a loop mode")


func test_a_full_power_shot_plays_at_the_samples_level() -> void:
	assert_almost_eq(SoundManager.shot_volume_db(GameRules.DEFAULT_WRISTER_POWER_MAX_M_S, false), 0.0, 1e-4)
	assert_almost_eq(SoundManager.shot_volume_db(GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S, true), 0.0, 1e-4)


func test_shot_level_tracks_launch_speed() -> void:
	# Half the launch speed is half the amplitude.
	var half: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S * 0.5
	assert_almost_eq(SoundManager.shot_volume_db(half, false), -6.02, 0.01)
	var last: float = -INF
	for power: float in [1.0, 5.0, 10.0, 14.0, 20.0, 33.0]:
		var db: float = SoundManager.shot_volume_db(power, false)
		assert_gte(db, last, "no quieter at %.0f m/s than below it" % power)
		last = db


func test_shot_level_is_bounded() -> void:
	assert_eq(SoundManager.shot_volume_db(0.0, false), SoundManager._SHOT_VOLUME_FLOOR_DB, "a dead release sits on the floor")
	assert_eq(SoundManager.shot_volume_db(60.0, true), 0.0, "one-timer bonus power never boosts past the sample")

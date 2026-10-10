extends GutTest

# Import flags and level curves that no player ever reports wrongly: a bed that
# stops looping just goes quiet, and a cue at the wrong level just sounds flat.


func test_the_skate_loop_loops() -> void:
	var stream := load("res://Sounds/skate_loop.ogg") as AudioStreamOggVorbis
	assert_not_null(stream)
	assert_true(stream.loop, "skate_loop.ogg.import must set loop=true")


func test_the_crowd_bed_loops() -> void:
	var stream := load("res://Sounds/crowd_ambient.wav") as AudioStreamWAV
	assert_not_null(stream)
	assert_ne(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED,
			"crowd_ambient.wav.import must set a loop mode")


func test_the_hardest_shot_in_the_league_plays_at_full() -> void:
	assert_almost_eq(SoundManager.shot_volume_db(GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S), 0.0, 1e-4)


func test_shot_level_tracks_launch_speed() -> void:
	# Half the launch speed is half the amplitude.
	var half: float = GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S * 0.5
	assert_almost_eq(SoundManager.shot_volume_db(half), -6.02, 0.01)
	var last: float = -INF
	for power: float in [1.0, 5.0, 10.0, 14.0, 20.0, 33.0, 40.0]:
		var db: float = SoundManager.shot_volume_db(power)
		assert_gte(db, last, "no quieter at %.0f m/s than below it" % power)
		last = db
	assert_lt(SoundManager.shot_volume_db(GameRules.DEFAULT_WRISTER_POWER_MAX_M_S), 0.0,
			"a full wrister leaves the puck slower than a full slapper, so it plays under it")


func test_shot_level_is_bounded() -> void:
	assert_eq(SoundManager.shot_volume_db(0.0), SoundManager._SHOT_VOLUME_FLOOR_DB, "a dead release sits on the floor")
	assert_eq(SoundManager.shot_volume_db(60.0), 0.0, "one-timer bonus power never boosts past full")


func test_cues_sharing_a_file_share_its_make_up_gain() -> void:
	# The shortfall is a property of the file, so two cues playing it need the
	# same entry or one of them plays off its mix level.
	var paths: Dictionary = SoundManager._SOUND_PATHS
	var under: Dictionary = SoundManager._UNDER_REFERENCE_DB
	for a: int in paths:
		for b: int in paths:
			if a < b and paths[a] == paths[b]:
				assert_eq(under.get(a, 0.0), under.get(b, 0.0), "%s and %s share %s" % [
						SoundManager.Sound.keys()[a], SoundManager.Sound.keys()[b], paths[a]])


func test_every_cue_has_a_mix_level() -> void:
	for sound: int in SoundManager.Sound.values():
		assert_true(SoundManager._MIX_DB.has(sound),
				"%s needs a deliberate level in _MIX_DB" % SoundManager.Sound.keys()[sound])


# The agreed loudness order. Only cues that share a distance treatment are
# compared: arena cues play flat, world cues fall off with distance.
func test_the_mix_keeps_its_order() -> void:
	var mix: Dictionary = SoundManager._MIX_DB
	var S := SoundManager.Sound
	assert_gt(mix[S.GOAL_HORN], mix[S.PERIOD_BUZZER], "the horn is the biggest moment")
	assert_gt(mix[S.PERIOD_BUZZER], mix[S.FACEOFF_WHISTLE], "the whistle sits under the buzzer")
	var contacts: Array = [S.PUCK_BOARDS, S.PUCK_GLASS, S.PUCK_GOALIE, S.PUCK_POST, S.PUCK_GOAL_BODY,
			S.PUCK_DEFLECTION, S.PUCK_BODY_BLOCK, S.PUCK_STRIP, S.STICK_LIFT, S.BODY_CHECK]
	for contact: int in contacts:
		for shot: int in [S.SHOT_SLAPPER, S.SHOT_WRISTER]:
			assert_gt(mix[shot], mix[contact], "shots over puck contacts")
		for quiet: int in [S.PUCK_PICKUP, S.SKATE_BRAKE, S.STICK_TAP, S.GOALIE_PAD_DROP, S.GOALIE_PAD_SLIDE]:
			assert_gt(mix[contact], mix[quiet], "puck contacts over the quieter body and stick sounds")
	for sound: int in S.values():
		if sound != S.UI_HOVER and sound != S.UI_CLICK:
			assert_gt(mix[sound], mix[S.UI_CLICK], "menus sit under everything in play")
	assert_gt(mix[S.UI_CLICK], mix[S.UI_HOVER], "hover under click")


func test_a_board_contact_above_the_cap_rail_is_glass() -> void:
	var top: float = GameRules.BOARD_TOP_HEIGHT
	assert_eq(SoundManager.board_contact_sound(Vector3(29.0, 0.02, 3.0)), SoundManager.Sound.PUCK_BOARDS, "rimmed along the ice")
	assert_eq(SoundManager.board_contact_sound(Vector3(29.0, top - 0.05, 3.0)), SoundManager.Sound.PUCK_BOARDS, "just under the rail")
	assert_eq(SoundManager.board_contact_sound(Vector3(29.0, top + 0.05, 3.0)), SoundManager.Sound.PUCK_GLASS, "just over the rail")


func test_every_take_of_a_multi_take_cue_exists() -> void:
	for sound: int in SoundManager._TAKE_COUNTS:
		var pattern: String = SoundManager._SOUND_PATHS[sound]
		for i: int in SoundManager._TAKE_COUNTS[sound]:
			assert_true(ResourceLoader.exists(pattern % (i + 1)), pattern % (i + 1))


func test_a_multi_take_cue_never_repeats_a_take_back_to_back() -> void:
	var last: AudioStream = null
	for i: int in 200:
		var take: AudioStream = SoundManager._stream_for(SoundManager.Sound.STICK_TAP)
		assert_not_null(take)
		assert_ne(take, last, "draw %d repeated the previous take" % i)
		last = take


func test_a_tap_follows_the_stroke_that_caused_it() -> void:
	var full: float = 3.0
	assert_almost_eq(SkaterSoundController.tap_volume_db(full, full), 0.0, 1e-4)
	assert_almost_eq(SkaterSoundController.tap_volume_db(full * 0.5, full), -6.02, 0.01)
	assert_eq(SkaterSoundController.tap_volume_db(0.0, full), SkaterSoundController._TAP_FLOOR_DB)
	assert_eq(SkaterSoundController.tap_volume_db(full * 3.0, full), 0.0, "a wild stroke never boosts past full")


# The pad count and the wire's down-test each list the down stances; they must
# agree, or the drop sound and the bots' read of a down goalie part ways.
func test_both_pads_are_down_exactly_when_the_wire_says_down() -> void:
	var wire := GoalieNetworkState.new()
	for state: int in GoalieStateMachine.State.values():
		wire.state_enum = state
		var pads: int = GoalieStateMachine.pads_on_ice(state as GoalieStateMachine.State)
		assert_eq(pads == 2, wire.is_down(), GoalieStateMachine.State.keys()[state])
	assert_eq(GoalieStateMachine.pads_on_ice(GoalieStateMachine.State.HALF_BUTTERFLY_LEFT), 1)
	assert_eq(GoalieStateMachine.pads_on_ice(GoalieStateMachine.State.RECOVERING), 0, "rising legs are off the ice")

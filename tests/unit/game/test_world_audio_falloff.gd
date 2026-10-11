extends GutTest

# How far away a world sound can be heard, and on which slider it sits.
#
# Two places build a 3D emitter — SoundManager's shared pool and each skater's own
# stride / brake players — and neither disagreeing is load-bearing: a mismatch is
# not a crash, it is one class of sound fading out at a different distance from
# the rest, which is exactly what "the sounds are inconsistent" reports as.

func _skater_emitter() -> AudioStreamPlayer3D:
	var controller := SkaterSoundController.new()
	autofree(controller)
	return controller._make_player("res://Sounds/skate_brake.wav")


func test_the_sfx_bus_exists_before_anything_asks_for_it() -> void:
	# Godot silently reroutes a player to Master when the named bus is missing, so
	# an emitter built before SoundManager._ensure_buses would sit off the SFX
	# slider with no error raised anywhere. Autoload order is what guarantees this.
	assert_gt(AudioServer.get_bus_index("SFX"), -1, "SoundManager created the SFX bus")


func test_the_master_bus_is_limited() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	var limited: bool = false
	for i: int in AudioServer.get_bus_effect_count(master):
		limited = limited or AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter
	assert_true(limited, "make-up gain on under-reference cues relies on the Master limiter")


func test_a_skater_emitter_matches_the_shared_world_pool() -> void:
	var pool: Array[AudioStreamPlayer3D] = SoundManager._pool_3d
	assert_gt(pool.size(), 0, "the shared world pool is built")
	var mine: AudioStreamPlayer3D = _skater_emitter()
	assert_eq(mine.bus, "SFX", "a stride is a gameplay sound, so the SFX slider governs it")
	for p: AudioStreamPlayer3D in pool:
		assert_eq(p.bus, mine.bus, "same bus")
		assert_eq(p.unit_size, mine.unit_size, "same falloff anchor")
		assert_eq(p.max_distance, mine.max_distance, "same (absent) cutoff")
		assert_eq(p.attenuation_model, mine.attenuation_model, "same attenuation model")


func test_a_skater_emitter_sounds_from_the_skater() -> void:
	# A 3D player under a non-Node3D parent keeps its own world transform, so the
	# controller between skater and emitter has to pass the transform through or
	# every stride sounds from the origin.
	var skater_stand_in := Node3D.new()
	add_child_autofree(skater_stand_in)
	skater_stand_in.global_position = Vector3(12.0, 0.0, -7.0)
	var controller := SkaterSoundController.new()
	skater_stand_in.add_child(controller)
	var mine: AudioStreamPlayer3D = controller._make_player("res://Sounds/skate_brake.wav")
	assert_eq(mine.global_position, skater_stand_in.global_position, "emitter sits on the skater")
	skater_stand_in.global_position = Vector3(-20.0, 0.0, 4.0)
	assert_eq(mine.global_position, skater_stand_in.global_position, "and follows it")


func test_no_world_emitter_is_cut_off_by_distance() -> void:
	# Godot reads 0.0 as unlimited. Any positive value here puts the silence cliff
	# back: past it a sound stops entirely rather than getting quieter, which makes
	# audibility a step function of how far the camera has pulled back.
	var mine: AudioStreamPlayer3D = _skater_emitter()
	assert_eq(mine.max_distance, 0.0, "skater emitters have no cutoff")
	for p: AudioStreamPlayer3D in SoundManager._pool_3d:
		assert_eq(p.max_distance, 0.0, "the world pool has no cutoff")

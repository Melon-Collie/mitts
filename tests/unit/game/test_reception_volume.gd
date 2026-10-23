extends GutTest

const SoundManagerScript := preload("res://Scripts/game/sound_manager.gd")

# SoundManager.reception_volume_db — the pickup sound's situational gain from the
# puck's arrival speed in the receiver's frame.


func test_full_level_at_the_any_angle_catch_ceiling() -> void:
	var puck := Puck.new()
	assert_eq(SoundManager.RECEPTION_FULL_SPEED_M_S, puck.deflect_min_speed,
			"the loudest catch is the hardest a poorly angled blade holds")
	puck.free()
	assert_almost_eq(SoundManagerScript.reception_volume_db(SoundManager.RECEPTION_FULL_SPEED_M_S),
			0.0, 0.0001)
	assert_eq(SoundManagerScript.reception_volume_db(30.0), 0.0, "never above the cue's mix level")


func test_louder_the_harder_the_catch() -> void:
	var prev: float = SoundManagerScript.reception_volume_db(0.0)
	for speed: float in [4.0, 8.0, 12.0, 16.0, 20.0]:
		var db: float = SoundManagerScript.reception_volume_db(speed)
		assert_gt(db, prev, "%.0f m/s" % speed)
		prev = db


func test_a_still_pickup_is_still_heard() -> void:
	var floor_db: float = SoundManagerScript.reception_volume_db(0.0)
	assert_true(is_finite(floor_db))
	assert_gt(floor_db, -24.0)
	assert_eq(SoundManagerScript.reception_volume_db(-3.0), floor_db)

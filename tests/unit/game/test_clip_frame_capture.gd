extends GutTest

# ClipFrameCapture — the GIF buffer holds a whole goal cinematic.


# Wall-clock seconds of the longest goal cinematic segment: the incoming wipe,
# the full clip with the slow motion at its largest, and the outro hold.
func _longest_cinematic_s() -> float:
	var goal_ts: float = 0.0
	var end_ts: float = goal_ts + GoalReplayRules.POST_GOAL_TAIL
	var slowmo_start: float = goal_ts - GoalReplayRules.SLOWMO_MAX_SPAN
	var clock: float = end_ts - GoalReplayDriver.CLIP_DURATION
	var dt: float = 1.0 / 240.0
	var wall: float = 0.0
	while clock < end_ts:
		clock += dt * GoalReplayRules.playback_speed(clock, slowmo_start)
		wall += dt
	return ReplayStinger.COVER_TIME + wall + GoalReplayDriver.OUTRO_HOLD


func test_the_buffer_holds_the_longest_goal_cinematic() -> void:
	var needed: int = ceili(_longest_cinematic_s() * ClipFrameCapture.CAPTURE_FPS)
	assert_gte(ClipFrameCapture.MAX_FRAMES, needed,
			"a capped segment loses the goal at its end")

extends GutTest

# CrowdAudioController through a goal replay: the replay fades the live goal's
# cheer, so its own goal frame has to cheer again, once.


func _playing_cheers(crowd: CrowdAudioController) -> int:
	var n: int = 0
	for p: AudioStreamPlayer in crowd._cheer_pool:
		if p.playing:
			n += 1
	return n


func _replay_frame(crowd: CrowdAudioController, phase: int) -> void:
	crowd._on_goal_replay_frame({"phase": phase}, -1)


func _replaying_crowd() -> CrowdAudioController:
	var crowd := CrowdAudioController.new()
	add_child_autofree(crowd)
	crowd._on_goal_replay_started()
	return crowd


func test_the_play_before_the_goal_does_not_cheer() -> void:
	var crowd: CrowdAudioController = _replaying_crowd()
	_replay_frame(crowd, GamePhase.Phase.PLAYING)
	_replay_frame(crowd, GamePhase.Phase.PLAYING)
	assert_eq(_playing_cheers(crowd), 0)


func test_the_replayed_goal_cheers_once() -> void:
	var crowd: CrowdAudioController = _replaying_crowd()
	_replay_frame(crowd, GamePhase.Phase.PLAYING)
	_replay_frame(crowd, GamePhase.Phase.GOAL_CELEBRATION)
	assert_eq(_playing_cheers(crowd), 1)
	_replay_frame(crowd, GamePhase.Phase.GOAL_CELEBRATION)
	assert_eq(_playing_cheers(crowd), 1, "the post-goal tail is the same goal")

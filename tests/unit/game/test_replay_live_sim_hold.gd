extends GutTest

# ReplayLiveSimHold — a replay draws its actors exactly as posed, and hands
# each back with the interpolation mode it had.


func _skater(mode: Node.PhysicsInterpolationMode) -> Skater:
	var skater: Skater = autofree(Skater.new())
	skater.physics_interpolation_mode = mode
	return skater


func _hold(skaters: Array[Skater]) -> ReplayLiveSimHold:
	var hold := ReplayLiveSimHold.new()
	var no_goalies: Array[GoalieController] = []
	hold.grab(null, no_goalies, skaters)
	return hold


func test_posed_skaters_do_not_interpolate_during_the_replay() -> void:
	var skaters: Array[Skater] = [
		_skater(Node.PHYSICS_INTERPOLATION_MODE_INHERIT),
		_skater(Node.PHYSICS_INTERPOLATION_MODE_ON),
	]
	_hold(skaters)
	for skater: Skater in skaters:
		assert_eq(skater.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)


func test_release_restores_each_skaters_own_mode() -> void:
	var inherit: Skater = _skater(Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
	var on: Skater = _skater(Node.PHYSICS_INTERPOLATION_MODE_ON)
	var skaters: Array[Skater] = [inherit, on]
	_hold(skaters).release()
	assert_eq(inherit.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
	assert_eq(on.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_ON)


func test_a_skater_freed_mid_replay_is_skipped_on_release() -> void:
	var leaver := Skater.new()
	var stayer: Skater = _skater(Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
	var skaters: Array[Skater] = [leaver, stayer]
	var hold: ReplayLiveSimHold = _hold(skaters)
	leaver.free()
	hold.release()
	assert_eq(stayer.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_INHERIT)


# A clip hides a skater where it has him in the box and shows him where it does
# not; when it ends each is drawn as the live game has him.
func test_release_draws_each_skater_as_the_live_game_has_him() -> void:
	var out_since: Skater = _skater(Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
	var boxed_now: Skater = _skater(Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
	boxed_now.in_box = true
	var skaters: Array[Skater] = [out_since, boxed_now]
	var hold: ReplayLiveSimHold = _hold(skaters)
	out_since.visible = false   # the clip had him in the box
	boxed_now.visible = true    # the clip is from before his penalty
	hold.release()
	assert_true(out_since.visible)
	assert_false(boxed_now.visible)

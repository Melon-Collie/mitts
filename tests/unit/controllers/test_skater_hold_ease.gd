extends GutTest

# SkaterHoldEase: the hold's fold and grip land on their targets when first
# read, ease toward a moved target, and take back the state a tick left.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION

var _target := Vector2(0.4, 0.0)


func _targets() -> Vector2:
	return _target


func test_it_lands_on_its_targets_when_first_read() -> void:
	var hold := SkaterHoldEase.new(_targets)
	assert_almost_eq(hold.fold(), 0.4, 0.000001)
	assert_eq(hold.grip(), 0.0)


func test_it_eases_to_a_moved_target_without_passing_it() -> void:
	var hold := SkaterHoldEase.new(_targets)
	hold.advance(DT)
	_target = Vector2(0.6, 1.0)
	hold.advance(DT)
	assert_between(hold.grip(), 0.0001, 0.2, "a tick in, the grip has barely begun")
	var most := Vector2.ZERO
	for _t: int in 90:
		hold.advance(DT)
		most = Vector2(maxf(most.x, hold.fold()), maxf(most.y, hold.grip()))
	assert_almost_eq(hold.grip(), 1.0, 0.01, "a second on, it is there")
	assert_almost_eq(hold.fold(), 0.6, 0.01)
	assert_lte(most.x, 0.6)
	assert_lte(most.y, 1.0)
	_target = Vector2(0.4, 0.0)


func test_a_replay_plays_back_what_a_tick_left() -> void:
	var hold := SkaterHoldEase.new(_targets)
	hold.adopt(Vector2(0.1, 0.7))
	assert_almost_eq(hold.state(), Vector2(0.1, 0.7), Vector2(0.000001, 0.000001))
	assert_almost_eq(hold.fold(), 0.1, 0.000001, "adopted, it does not land afresh")
	hold.unseed()
	assert_almost_eq(hold.state(), Vector2(0.1, 0.7), Vector2(0.000001, 0.000001),
			"unseeded, the state is still what was left")
	assert_eq(hold.grip(), 0.0, "and the next read lands")

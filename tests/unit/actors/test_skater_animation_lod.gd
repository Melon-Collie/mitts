extends GutTest

# SkaterAnimationLod — how often a skater's mesh is re-posed, by camera distance
# and the player's Animation Detail setting.

const FRAME_60: float = 1.0 / 60.0

var _saved_detail: int


func before_each() -> void:
	_saved_detail = SkaterAnimationLod.detail


func after_each() -> void:
	SkaterAnimationLod.detail = _saved_detail


func _due_count(lod: SkaterAnimationLod, frames: int, distance: float, full: bool) -> int:
	var n: int = 0
	for _f: int in frames:
		if lod.due(FRAME_60, distance, full):
			n += 1
			lod.consumed()
	return n


func test_full_detail_poses_every_frame_at_any_distance() -> void:
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	assert_eq(_due_count(SkaterAnimationLod.new(), 60, 80.0, false), 60)


func test_low_detail_thins_the_far_skater_to_its_rate() -> void:
	# 20 Hz at the far tier: a second at 60 fps re-poses him ~20 times.
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_LOW
	var n: int = _due_count(SkaterAnimationLod.new(), 60, SkaterAnimationLod.FAR_M + 5.0, false)
	assert_between(n, 19, 21, "~20 passes in a second (got %d)" % n)


func test_balanced_never_thins_a_near_skater_on_a_60_hz_frame() -> void:
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_BALANCED
	assert_eq(_due_count(SkaterAnimationLod.new(), 60, 5.0, false), 60)


func test_a_rate_equal_to_the_frame_rate_poses_every_frame() -> void:
	# Balanced's mid tier is 60 Hz. Frame times never sum to it exactly and the
	# table is float32, so without slack a steady 60 fps skipped every other frame.
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_BALANCED
	var mid: float = (SkaterAnimationLod.NEAR_M + SkaterAnimationLod.FAR_M) * 0.5
	assert_eq(_due_count(SkaterAnimationLod.new(0.37), 600, mid, false), 600)


func test_the_local_player_and_a_cameraless_frame_are_never_thinned() -> void:
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_LOW
	assert_eq(_due_count(SkaterAnimationLod.new(), 60, 80.0, true), 60, "local player")
	assert_eq(_due_count(SkaterAnimationLod.new(), 60, -1.0, false), 60, "no camera")


func test_span_covers_every_frame_since_the_last_pass() -> void:
	# The plant's ease is rate-limited by the time the pass covers, so a thinned
	# skater's feet catch up by the frames he skipped, not by one frame.
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_LOW
	var lod := SkaterAnimationLod.new()
	var frames: int = 0
	while not lod.due(FRAME_60, 80.0, false):
		frames += 1
	assert_almost_eq(lod.span, FRAME_60 * float(frames + 1), 1e-6)
	lod.consumed()
	assert_eq(lod.span, 0.0)


func test_phases_spread_skaters_across_frames() -> void:
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_LOW
	var a := SkaterAnimationLod.new(0.0)
	var b := SkaterAnimationLod.new(0.5)
	var same: int = 0
	for _f: int in 60:
		var da: bool = a.due(FRAME_60, 80.0, false)
		var db: bool = b.due(FRAME_60, 80.0, false)
		if da and db:
			same += 1
		a.consumed()
		b.consumed()
	assert_lt(same, 10, "two phases land on different frames (%d shared)" % same)

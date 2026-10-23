extends GutTest

# The keeper into and out of the RVH on a post (KeeperPost): from his feet by
# the drop-in at the post and back up by the rise, from the butterfly after a
# slide to the post and back down into it. Each lands where it should in its
# time, sealed with the post pad's end on the post; and every tick keeps his
# gear out of the ice, his arms on the stick and nothing on him jumping, the
# off skate on the ice through the drop-in and the rise.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 0.1
const GOAL_LINE_Z: float = 0.35
const B := KeeperSkeleton.Bone
const S := KeeperPost.State

var _post: KeeperPost = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_post = KeeperPost.new()


func _iron(post_side: float) -> Vector2:
	return Vector2(post_side * GameRules.NET_HALF_WIDTH, GOAL_LINE_Z)


func _place(at: Vector2, turn: float = 0.0) -> void:
	_post.x = at.x
	_post.z = at.y
	_post.yaw = turn


func _world(v: Vector3) -> Vector3:
	return Basis(Vector3.UP, _post.yaw) * v + Vector3(_post.x, 0.0, _post.z)


func _solve() -> void:
	_post.pose(_pose)
	_skel.pose(_pose)


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# Steps until `state`, at most `limit` seconds; the time it took.
func _until(state: int, limit: float = 2.0) -> float:
	var t: float = 0.0
	while _post.state != state and t < limit:
		_post.step(DT)
		t += DT
	return t


# Where his edge on the post's side touches, in the world, against the post.
func _gap_to(post_side: float) -> float:
	_solve()
	var edge: Vector3 = _world(KeeperGear.post_contact(_skel, post_side))
	return Vector2(edge.x, edge.z).distance_to(_iron(post_side)) - GameRules.NET_POST_RADIUS


func _same_bones(p: KeeperPose, what: String) -> void:
	var skel := KeeperSkeleton.new()
	skel.pose(p)
	_solve()
	for b: int in KeeperSkeleton.BONE_COUNT:
		assert_almost_eq(_skel.xf[b].origin, skel.xf[b].origin, Vector3.ONE * 1e-4, "%s bone %d" % [what, b])


func test_he_drops_in_at_the_post_and_rises_back_out() -> void:
	for post_side: float in [1.0, -1.0]:
		_post = KeeperPost.new()
		var post: Vector2 = _iron(post_side)
		var overlap: Vector2 = _post.overlap_spot(post, post_side)
		_place(overlap)
		assert_almost_eq(_gap_to(post_side), 0.0, 0.01, "%+.0f: standing, his edge on the post" % post_side)
		_post.drop_in(post, post_side)
		assert_almost_eq(_until(S.SEALED), _post.drop_s, DT, "%+.0f: down in the drop's time" % post_side)
		assert_almost_eq(Vector2(_post.x, _post.z), _post.seal_spot(post, post_side), Vector2.ONE * 1e-6)
		assert_almost_eq(_gap_to(post_side), 0.0, 0.01, "%+.0f: sealed, the pad's end on the post" % post_side)
		var rvh := KeeperPose.new()
		KeeperPoses.rvh(rvh, post_side)
		_same_bones(rvh, "%+.0f in the RVH" % post_side)
		_post.rise_out()
		assert_almost_eq(_until(S.STANDING), _post.rise_s, DT, "%+.0f: up in the rise's time" % post_side)
		assert_almost_eq(Vector2(_post.x, _post.z), overlap, Vector2.ONE * 1e-5, "%+.0f: back on the overlap" % post_side)
		var ready_pose := KeeperPose.new()
		KeeperPoses.ready(ready_pose)
		_same_bones(ready_pose, "%+.0f standing" % post_side)


func test_from_a_slide_to_the_post_he_comes_up_into_it_and_folds_back() -> void:
	for post_side: float in [1.0, -1.0]:
		var post: Vector2 = _iron(post_side)
		var slide := KeeperSlide.new()
		var start := Vector2(-post_side * 0.6, -0.4)
		slide.x = start.x
		slide.z = start.y
		slide.slide_to(slide.post_spot(post, start))
		while slide.phase != KeeperSlide.Phase.DOWN or slide.speed > 0.0:
			slide.step(DT)
			if slide.phase == KeeperSlide.Phase.DOWN:
				break
		_post = KeeperPost.new()
		_place(Vector2(slide.x, slide.z), slide.yaw)
		_post.state = S.BUTTERFLY
		_post.slide_in(post, post_side)
		assert_almost_eq(_until(S.SEALED), KeeperPost.IN_FROM_BUTTERFLY_S, DT, "%+.0f: in" % post_side)
		assert_almost_eq(_post.yaw, 0.0, 1e-6, "%+.0f: square to the line" % post_side)
		assert_almost_eq(_gap_to(post_side), 0.0, 0.01, "%+.0f: sealed, the pad's end on the post" % post_side)
		_post.fold_out()
		assert_almost_eq(_until(S.BUTTERFLY), KeeperPost.OUT_TO_BUTTERFLY_S, DT, "%+.0f: out" % post_side)
		var fly := KeeperPose.new()
		KeeperPoses.butterfly(fly)
		_same_bones(fly, "%+.0f down" % post_side)


func test_every_tick_keeps_his_gear_out_of_the_ice_his_arms_on_the_stick_and_nothing_jumping() -> void:
	for post_side: float in [1.0, -1.0]:
		var post: Vector2 = _iron(post_side)
		_post = KeeperPost.new()
		_place(_post.overlap_spot(post, post_side))
		_post.drop_in(post, post_side)
		_watch("%+.0f drop in" % post_side, S.SEALED, post_side)
		_post.rise_out()
		_watch("%+.0f rise out" % post_side, S.STANDING, post_side)
		_post = KeeperPost.new()
		_place(_post.seal_spot(post, post_side) - Vector2(post_side * 0.15, 0.1), -post_side * 0.3)
		_post.state = S.BUTTERFLY
		_post.slide_in(post, post_side)
		_watch("%+.0f in from the butterfly" % post_side, S.SEALED, post_side)
		_post.fold_out()
		_watch("%+.0f out to the butterfly" % post_side, S.BUTTERFLY, post_side)


func _watch(what: String, until: int, post_side: float) -> void:
	_solve()
	var was: Array[Vector3] = _bones()
	var off: int = KeeperGear.Part.SKATE_B if post_side < 0.0 else KeeperGear.Part.SKATE_G
	var feet: bool = _post.state == S.DROPPING_IN or _post.state == S.RISING_OUT
	while _post.state != until:
		_post.step(DT)
		_solve()
		var when: String = "%s %.3f" % [what, _post.x]
		for part: int in KeeperGear.PART_COUNT:
			var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
			assert_gte(_lowest(part), -(PAD_GIVE_M if soft else HARD_GIVE_M),
					"%s %s" % [when, KeeperGear.Part.keys()[part]])
		if feet:
			assert_almost_eq(_lowest(off), 0.0, 0.005, "%s: the off skate on the ice" % when)
		var glove_wrist: Vector3 = _skel.xf[B.FOREARM_G] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
		var blocker_wrist: Vector3 = _skel.xf[B.FOREARM_B] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
		assert_almost_eq(glove_wrist.distance_to(_skel.xf[B.HAND_G].origin), 0.0, 0.002,
				"%s: the glove arm reaches its hand" % when)
		assert_almost_eq(blocker_wrist.distance_to(_skel.xf[B.HAND_B] * KeeperAnatomy.BLOCKER_WRIST),
				0.0, 0.002, "%s: the blocker arm reaches the stick" % when)
		var at: Array[Vector3] = _bones()
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "%s bone %d" % [when, b])
		was = at


func _bones() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(_world(_skel.xf[b].origin))
	return out

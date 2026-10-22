extends GutTest

# The keeper's butterfly drop and rise (KeeperDrop): down in the drop's time
# and up in the rise's; the first frame of the drop is the ready stance and the
# last the butterfly; the drop is a fall, landing at speed; a rise mid-drop or a
# drop mid-rise goes from where he is; and at every tick his gear stays out of
# the ice, his arms reach the stick and nothing on him jumps.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
# A bone's travel in a tick, past which it has jumped: the knees land at about
# 4 m/s.
const MAX_BONE_STEP_M: float = 0.1
const B := KeeperSkeleton.Bone

var _drop: KeeperDrop = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_drop = KeeperDrop.new()


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# Steps until `state`, at most `limit` seconds; the time it took.
func _until(state: int, limit: float = 2.0) -> float:
	var t: float = 0.0
	while _drop.state != state and t < limit:
		_drop.step(DT)
		t += DT
	return t


func _bones(p: KeeperPose) -> Array[Vector3]:
	var skel := KeeperSkeleton.new()
	skel.pose(p)
	var out: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(skel.xf[b].origin)
	return out


func test_he_is_down_in_the_drop_time_and_up_in_the_rise_time() -> void:
	_drop.drop()
	assert_almost_eq(_until(KeeperDrop.State.DOWN), _drop.drop_s, DT, "down")
	assert_eq(_drop.down, 1.0)
	_drop.rise()
	assert_almost_eq(_until(KeeperDrop.State.UP), _drop.rise_s, DT, "up")
	assert_eq(_drop.down, 0.0)


func test_the_drop_runs_from_the_ready_stance_to_the_butterfly() -> void:
	var ready := KeeperPose.new()
	KeeperPoses.ready(ready)
	var fly := KeeperPose.new()
	KeeperPoses.butterfly(fly)
	_drop.drop()
	_drop.step(1e-6)
	_drop.pose(_pose)
	var at: Array[Vector3] = _bones(_pose)
	var want: Array[Vector3] = _bones(ready)
	for b: int in KeeperSkeleton.BONE_COUNT:
		assert_almost_eq(at[b], want[b], Vector3.ONE * 1e-3, "bone %d starts at the stance" % b)
	_until(KeeperDrop.State.DOWN)
	_drop.pose(_pose)
	at = _bones(_pose)
	want = _bones(fly)
	for b: int in KeeperSkeleton.BONE_COUNT:
		assert_almost_eq(at[b], want[b], Vector3.ONE * 1e-6, "bone %d ends in the butterfly" % b)


# A fall from rest: slow off the mark, fastest as the knees land.
func test_the_drop_is_a_fall() -> void:
	_drop.drop()
	_drop.step(DT)
	var first: float = _drop.down
	var was: float = first
	var fastest: float = 0.0
	var fastest_at: float = 0.0
	while _drop.state == KeeperDrop.State.DROPPING:
		_drop.step(DT)
		if _drop.down - was > fastest:
			fastest = _drop.down - was
			fastest_at = _drop.down
		was = _drop.down
	assert_gt(fastest, 3.0 * first, "landing faster than leaving")
	assert_gt(fastest_at, 0.9, "fastest as the knees land")


func test_a_change_of_mind_goes_from_where_he_is() -> void:
	_drop.drop()
	for i: int in 10:
		_drop.step(DT)
	var halfway: float = _drop.down
	_drop.rise()
	_drop.step(DT)
	assert_almost_eq(_drop.down, halfway, 0.05, "a rise mid-drop starts where the drop got to")
	assert_lt(_drop.down, halfway, "and goes up")
	assert_lt(_until(KeeperDrop.State.UP), _drop.rise_s, "up sooner than from the ice")
	_drop.drop()
	_until(KeeperDrop.State.DOWN)
	_drop.rise()
	for i: int in 10:
		_drop.step(DT)
	var rising: float = _drop.down
	_drop.drop()
	_drop.step(DT)
	assert_almost_eq(_drop.down, rising, 0.05, "a drop mid-rise starts where the rise got to")
	assert_gt(_drop.down, rising - 1e-6, "and goes down")


func test_every_tick_keeps_his_gear_out_of_the_ice_and_his_arms_on_the_stick() -> void:
	_drop.drop()
	var rising: bool = false
	while true:
		_drop.step(DT)
		_drop.pose(_pose)
		_skel.pose(_pose)
		var when: String = "%s %.2f" % [KeeperDrop.State.keys()[_drop.state], _drop.down]
		for part: int in KeeperGear.PART_COUNT:
			var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
			assert_gte(_lowest(part), -(PAD_GIVE_M if soft else HARD_GIVE_M),
					"%s %s" % [when, KeeperGear.Part.keys()[part]])
		var glove_wrist: Vector3 = _skel.xf[B.FOREARM_G] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
		var blocker_wrist: Vector3 = _skel.xf[B.FOREARM_B] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)
		assert_almost_eq(glove_wrist.distance_to(_skel.xf[B.HAND_G].origin), 0.0, 0.002,
				"%s: the glove arm reaches its hand" % when)
		assert_almost_eq(blocker_wrist.distance_to(_skel.xf[B.HAND_B] * KeeperAnatomy.BLOCKER_WRIST),
				0.0, 0.002, "%s: the blocker arm reaches the stick" % when)
		if _drop.state == KeeperDrop.State.DOWN:
			_drop.rise()
			rising = true
		if rising and _drop.state == KeeperDrop.State.UP:
			break


func test_nothing_on_him_jumps_between_ticks() -> void:
	_drop.pose(_pose)
	var was: Array[Vector3] = _bones(_pose)
	_drop.drop()
	var rising: bool = false
	while not (rising and _drop.state == KeeperDrop.State.UP):
		_drop.step(DT)
		_drop.pose(_pose)
		var at: Array[Vector3] = _bones(_pose)
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M,
					"%s %.2f bone %d" % [KeeperDrop.State.keys()[_drop.state], _drop.down, b])
		was = at
		if _drop.state == KeeperDrop.State.DOWN:
			_drop.rise()
			rising = true

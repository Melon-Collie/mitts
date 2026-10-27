extends GutTest

# The keeper's butterfly drop, rise and recovery (KeeperDrop): down in the drop's time
# and up in the rise's; the first frame of the drop is the ready stance and the
# last the butterfly; the drop is a fall, landing at speed; a rise mid-drop or a
# drop mid-rise goes from where he is; and at every tick his gear stays out of
# the ice, his arms reach the stick and nothing on him jumps.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
# A bone's travel in a tick, past which it has jumped: the knees land at about
# 4 m/s.
const MAX_BONE_STEP_M: float = 12.0 * DT  # nothing on him moves 12 m/s
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
	var ready_pose := KeeperPose.new()
	KeeperPoses.ready(ready_pose)
	var fly := KeeperPose.new()
	KeeperPoses.butterfly(fly)
	_drop.drop()
	_drop.step(1e-6)
	_drop.pose(_pose)
	var at: Array[Vector3] = _bones(_pose)
	var want: Array[Vector3] = _bones(ready_pose)
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


# The recovery: up in the rise's time, into the ready stance where he got up;
# the leg away from the way he goes comes up first and its skate holds its
# place on the ice while the other comes up; and every tick keeps his gear out
# of the ice, his arms on the stick and nothing jumping.
func test_the_recovery_stands_him_up_on_the_far_leg_first() -> void:
	var ready_pose := KeeperPose.new()
	KeeperPoses.ready(ready_pose)
	var want: Array[Vector3] = _bones(ready_pose)
	for toward: float in [1.0, -1.0]:
		_drop = KeeperDrop.new()
		_drop.drop()
		_until(KeeperDrop.State.DOWN)
		_drop.recover(toward)
		var what: String = "%+.0f" % toward
		var t: float = 0.0
		while t < KeeperDrop.PUSH_LOAD_S:
			_drop.step(DT)
			t += DT
		_drop.pose(_pose)
		_skel.pose(_pose)
		var far: int = 0 if toward > 0.0 else 1
		assert_almost_eq(_lowest(KeeperGear.Part.SKATE_G + far), 0.0, 0.005, "%s: the far skate up first" % what)
		assert_lt(_lowest(KeeperGear.Part.PAD_G + (1 - far)), 0.01, "%s: the near pad still down" % what)
		assert_almost_eq(t + _until(KeeperDrop.State.UP), _drop.rise_s, 1.5 * DT, "%s: up in the rise's time" % what)
		_drop.pose(_pose)
		var at: Array[Vector3] = _bones(_pose)
		for b: int in KeeperSkeleton.BONE_COUNT:
			assert_almost_eq(at[b], want[b], Vector3.ONE * 1e-4, "%s: bone %d in the stance" % [what, b])


func test_the_recovery_push_skate_holds_its_place() -> void:
	for toward: float in [1.0, -1.0]:
		_drop = KeeperDrop.new()
		_drop.state = KeeperDrop.State.DOWN
		_drop.down = 1.0
		_drop.recover(toward)
		var push: int = 0 if toward > 0.0 else 1
		var planted := Vector3.INF
		var held: int = 0
		var t: float = 0.0
		while _drop.state == KeeperDrop.State.RECOVERING:
			_drop.step(DT)
			t += DT
			if _drop.state != KeeperDrop.State.RECOVERING:
				break
			if t <= KeeperDrop.PUSH_LOAD_S:
				continue
			_drop.pose(_pose)
			_skel.pose(_pose)
			var skate: Vector3 = _skel.xf[KeeperSkeleton.FOOT[push]].origin
			assert_almost_eq(_lowest(KeeperGear.Part.SKATE_G + push), 0.0, 0.005,
					"%+.0f: the push skate is on the ice" % toward)
			if planted == Vector3.INF:
				planted = skate
			assert_almost_eq(skate, planted, Vector3.ONE * 0.001, "%+.0f: the push skate holds" % toward)
			held += 1
		assert_gt(held, roundi(0.167 / DT), "%+.0f: it drives him up off one place" % toward)


func test_every_tick_of_the_recovery_is_out_of_the_ice_on_the_stick_and_smooth() -> void:
	for toward: float in [1.0, -1.0]:
		_drop = KeeperDrop.new()
		_drop.state = KeeperDrop.State.DOWN
		_drop.down = 1.0
		_drop.pose(_pose)
		var was: Array[Vector3] = _world_bones()
		_drop.recover(toward)
		while _drop.state == KeeperDrop.State.RECOVERING:
			_drop.step(DT)
			_drop.pose(_pose)
			_skel.pose(_pose)
			var when: String = "%+.0f at %.2f" % [toward, _drop.down]
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
			var at: Array[Vector3] = _world_bones()
			for b: int in KeeperSkeleton.BONE_COUNT:
				assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "%s bone %d" % [when, b])
			was = at


func _world_bones() -> Array[Vector3]:
	_skel.pose(_pose)
	var out: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(_skel.xf[b].origin)
	return out

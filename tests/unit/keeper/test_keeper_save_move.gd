extends GutTest

# A low save's body (KeeperSaveMove through KeeperMotor.save): every low save,
# to either side, from standing set or cut into a push under way, runs every
# tick unbroken from the pose it cut in from, his gear out of the ice; it is
# in its stance in the drop's time and holds it until released; then it
# gathers him into the stance he rests in — up after a kick, down after the
# rest — and the speed it caught him at carries him on and dies.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 0.1
const L := KeeperSaveMove.Low
const R := KeeperRoute.Rest

var _motor: KeeperMotor = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_motor = KeeperMotor.new()


func _bones() -> Array[Vector3]:
	_motor.pose(_pose)
	_skel.pose(_pose)
	var out: Array[Vector3] = []
	var at := Basis(Vector3.UP, _motor.yaw)
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(at * _skel.xf[b].origin + Vector3(_motor.x, 0.0, _motor.z))
	return out


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# Steps `seconds`, every tick unbroken and out of the ice: the worst of each
# asserted once.
func _run(what: String, seconds: float, was: Array[Vector3]) -> Array[Vector3]:
	var t: float = 0.0
	var worst_step: float = 0.0
	var step_at: String = ""
	var worst_sink: float = 0.0
	var sink_at: String = ""
	while t < seconds:
		_motor.step(DT)
		t += DT
		var at: Array[Vector3] = _bones()
		for b: int in KeeperSkeleton.BONE_COUNT:
			var moved: float = at[b].distance_to(was[b])
			if moved > worst_step:
				worst_step = moved
				step_at = "t %.3f bone %d" % [t, b]
		was = at
		for part: int in KeeperGear.PART_COUNT:
			var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
			var sink: float = -_lowest(part) - (PAD_GIVE_M if soft else HARD_GIVE_M)
			if sink > worst_sink:
				worst_sink = sink
				sink_at = "t %.3f %s" % [t, KeeperGear.Part.keys()[part]]
	assert_lt(worst_step, MAX_BONE_STEP_M, "%s: unbroken (%s)" % [what, step_at])
	assert_lte(worst_sink, 0.0, "%s: out of the ice (%s)" % [what, sink_at])
	return was


func test_every_low_save_from_standing_lands_holds_and_gathers() -> void:
	for low: int in [L.BUTTERFLY, L.HALF, L.KICK, L.EXTENSION]:
		for side: float in [-1.0, 1.0]:
			before_each()
			var what: String = "%s %+d" % [L.keys()[low], side]
			assert_true(_motor.can_save(false), what)
			var was: Array[Vector3] = _bones()
			_motor.save(low, side)
			assert_almost_eq(_bones()[KeeperSkeleton.Bone.HEAD], was[KeeperSkeleton.Bone.HEAD],
					Vector3.ONE * 1e-4, "%s: it starts from where he stood" % what)
			was = _run(what, _motor.save_move.drop_s + DT, was)
			assert_true(_motor.save_move.is_set(), "%s: in its stance in the drop's time" % what)
			was = _run(what, 0.3, was)
			assert_true(_motor.save_move.is_set(), "%s: held" % what)
			_motor.end_save()
			was = _run(what, KeeperSaveMove.GATHER_S + DT, was)
			assert_true(_motor.is_idle() or _motor.rest != R.FEET or low == L.KICK, what)
			assert_eq(_motor.rest, R.FEET if low == L.KICK else R.DOWN, "%s: resting" % what)


func test_cut_into_a_push_it_starts_from_there_and_slides_on() -> void:
	for low: int in [L.BUTTERFLY, L.KICK]:
		before_each()
		_motor.push_to(Vector2(1.2, 0.0))
		var was: Array[Vector3] = _run("push", 0.2, _bones())
		var speed: float = _motor._velocity.x
		assert_gt(speed, 1.0, "under way")
		assert_true(_motor.can_save(false))
		var cut_at: float = _motor.x
		_motor.save(low, 1.0)
		var what: String = "%s cut in" % L.keys()[low]
		assert_almost_eq(_bones()[KeeperSkeleton.Bone.HEAD], was[KeeperSkeleton.Bone.HEAD],
				Vector3.ONE * 1e-4, "%s: from the pose it cut" % what)
		was = _run(what, 0.05, was)
		assert_gt(_motor.x, cut_at, "%s: carried on" % what)
		was = _run(what, 1.5, was)
		_motor.end_save()
		_run(what, 1.0, was)
		assert_almost_eq(_motor.save_move.velocity, Vector2.ZERO, Vector2.ONE * 1e-6, "%s: stopped" % what)
		assert_eq(_motor.rest, R.FEET if low == L.KICK else R.DOWN, what)


func test_down_he_can_still_extend_but_not_mid_slide() -> void:
	_motor.drop_down()
	var was: Array[Vector3] = _run("drop", 0.6, _bones())
	assert_eq(_motor.rest, R.DOWN)
	assert_false(_motor.can_save(false), "no drop from down")
	assert_true(_motor.can_save(true), "the extension from down")
	_motor.save(L.EXTENSION, -1.0)
	was = _run("extension from down", 0.5, was)
	_motor.end_save()
	_run("extension from down", 0.3, was)
	assert_eq(_motor.rest, R.DOWN)
	_motor.slide_to(Vector2(0.8, 0.0))
	_motor.step(DT)
	assert_false(_motor.can_save(true), "not mid-slide")


func test_cut_into_a_rise_it_falls_back_from_as_far_down_as_he_is() -> void:
	_motor.drop_down()
	var was: Array[Vector3] = _run("drop", 0.6, _bones())
	_motor.rise()
	was = _run("rise", 0.15, was)
	assert_eq(_motor._mover, KeeperMotor.Mover.DROP, "on his way up")
	assert_true(_motor.can_save(false), "a low save cuts into the rise")
	var fall: float = _motor.fall
	assert_lt(fall, 1.0, "less of a fall than from his feet")
	assert_gte(fall, KeeperLowReady.fall_share_at(1.0), "no less than the low ready's")
	_motor.save(L.BUTTERFLY, 1.0)
	was = _run("butterfly cut into a rise", _motor.save_move.drop_s * fall + DT, was)
	assert_true(_motor.save_move.is_set(), "in its stance in the fall he had left")
	_motor.end_save()
	_run("butterfly cut into a rise", KeeperSaveMove.GATHER_S + DT, was)
	assert_eq(_motor.rest, R.DOWN)


func test_gathering_after_a_save_he_can_save_again() -> void:
	for low: int in [L.BUTTERFLY, L.KICK]:
		before_each()
		var what: String = L.keys()[low]
		_motor.save(low, -1.0)
		var was: Array[Vector3] = _run(what, _motor.save_move.drop_s + DT, _bones())
		_motor.end_save()
		was = _run(what, DT, was)
		assert_eq(_motor.save_move.state, KeeperSaveMove.State.GATHERING, what)
		var down: bool = low != L.KICK
		assert_eq(_motor.can_save(true), down, "%s: the extension from the gather down" % what)
		assert_eq(_motor.can_save(false), not down, "%s: any low from the gather up" % what)
		_motor.save(L.EXTENSION if down else L.BUTTERFLY, 1.0)
		was = _run(what + " again", _motor.save_move.drop_s + DT, was)
		assert_true(_motor.save_move.is_set(), "%s: the second save made" % what)

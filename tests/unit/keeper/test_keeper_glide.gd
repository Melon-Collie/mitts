extends GutTest

# Skating to a spot that moves (KeeperGlide through KeeperMotor.go_to): a spot
# moving across him is caught and then skated with, never stopped for, his
# legs gliding once matched rather than stroking; a still one he stops on, no
# further, in the push's own time; and one that turns back on him is followed
# every tick unbroken, his gear out of the ice.

const DT: float = 1.0 / 120.0
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 0.1

var _motor: KeeperMotor = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()
var _was: Array[Vector3] = []
var _worst_step: float = 0.0
var _worst_sink: float = 0.0


func before_each() -> void:
	_motor = KeeperMotor.new()
	_motor.z = -1.0
	_was = []
	_worst_step = 0.0
	_worst_sink = 0.0


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# One tick toward `spot` moving at `v`, the body checked.
func _tick(spot: Vector2, v: Vector2) -> void:
	_motor.go_to(spot, 0.0, KeeperRoute.Rest.FEET, v)
	_motor.step(DT)
	_motor.pose(_pose)
	_skel.pose(_pose)
	var at := Basis(Vector3.UP, _motor.yaw)
	for b: int in KeeperSkeleton.BONE_COUNT:
		var p: Vector3 = at * _skel.xf[b].origin + Vector3(_motor.x, 0.0, _motor.z)
		if _was.size() > b:
			_worst_step = maxf(_worst_step, p.distance_to(_was[b]))
			_was[b] = p
		else:
			_was.append(p)
	for part: int in KeeperGear.PART_COUNT:
		var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
		_worst_sink = maxf(_worst_sink, -_lowest(part) - (PAD_GIVE_M if soft else HARD_GIVE_M))


func _checked(what: String) -> void:
	assert_lt(_worst_step, MAX_BONE_STEP_M, "%s: unbroken" % what)
	assert_lte(_worst_sink, 0.0, "%s: out of the ice" % what)


func test_a_moving_spot_is_caught_and_skated_with() -> void:
	var v := Vector2(1.8, 0.0)
	var spot := Vector2(-0.6, -1.0)
	var off: float = 0.0
	var stopped: int = 0
	var stroking_matched: int = 0
	for i: int in int(0.9 / DT):
		spot += v * DT
		_tick(spot, v)
		if i * DT > 0.4:
			off = maxf(off, Vector2(_motor.x, _motor.z).distance_to(spot))
			if _motor.glide.velocity.length() < 0.5:
				stopped += 1
			if _motor.glide._drive > 0.5:
				stroking_matched += 1
	assert_lt(off, 0.02, "caught and held on it")
	assert_eq(stopped, 0, "never stopped for it")
	assert_eq(stroking_matched, 0, "gliding, matched, not stroking")
	_checked("a moving spot")


func test_a_still_spot_is_stopped_on_in_the_push_s_time() -> void:
	var spot := Vector2(0.7, -1.0)
	var past: float = 0.0
	var t: float = 0.0
	while not _motor.is_idle() or t == 0.0:
		_tick(spot, Vector2.ZERO)
		t += DT
		past = maxf(past, _motor.x - spot.x)
		if t > 2.0:
			break
	assert_almost_eq(Vector2(_motor.x, _motor.z), spot, Vector2.ONE * 1e-4, "on it")
	assert_lt(past, 1e-4, "no further")
	var push: float = GoaliePushRules.time_to_set(0.7, _motor.footwork.t_push_speed, _motor.footwork.accel)
	assert_almost_eq(t, push, 3.0 * DT, "in the push's time")
	_checked("a still spot")


func test_a_spot_that_turns_back_on_him_is_followed_unbroken() -> void:
	var spot := Vector2(0.0, -1.0)
	var v := Vector2(2.4, 0.4)
	for i: int in int(1.6 / DT):
		if i == int(0.45 / DT):
			v = Vector2(-2.6, -0.3)
		if i == int(0.9 / DT):
			v = Vector2(0.5, 1.2)
		spot += v * DT
		_tick(spot, v)
	assert_lt(Vector2(_motor.x, _motor.z).distance_to(spot), 0.3, "with it")
	_checked("turning back")

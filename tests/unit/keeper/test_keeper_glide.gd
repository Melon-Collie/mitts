extends GutTest

# Skating to a spot that moves (KeeperGlide through KeeperMotor.go_to): a spot
# moving across him is caught and then skated with, never stopped for, his
# legs gliding once matched rather than stroking; a still one he strokes for,
# glides on and stops on, no further, in the glide's own time; and one that
# turns back on him is followed every tick unbroken, his gear out of the ice.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
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


# One tick toward `spot` moving at `v`, given where it is as the tick starts,
# the body checked.
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
		_tick(spot, v)
		spot += v * DT
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


func test_a_still_spot_is_glided_to_and_stopped_on_in_time() -> void:
	var spot := Vector2(0.7, -1.0)
	var past: float = 0.0
	var t: float = 0.0
	var gliding: float = 0.0
	while not _motor.is_idle() or t == 0.0:
		var was: Vector2 = _motor.glide.velocity
		_tick(spot, Vector2.ZERO)
		t += DT
		past = maxf(past, _motor.x - spot.x)
		if was.length() > 0.5 and _motor.glide.velocity.is_equal_approx(was):
			gliding += DT
		if t > 2.0:
			break
	assert_gt(gliding, 0.1, "the stroke glided on before the stop")
	assert_almost_eq(Vector2(_motor.x, _motor.z), spot, Vector2.ONE * 1e-4, "on it")
	assert_lt(past, 1e-4, "no further")
	var skated: float = KeeperFootwork.push_time(0.7, _motor.footwork.t_push_speed, _motor.footwork.accel)
	assert_almost_eq(t, skated, 3.0 * DT, "in the glide's time")
	_checked("a still spot")


func test_a_spot_that_turns_back_on_him_is_followed_unbroken() -> void:
	var spot := Vector2(0.0, -1.0)
	var v := Vector2(2.4, 0.4)
	for i: int in int(1.6 / DT):
		if i == int(0.45 / DT):
			v = Vector2(-2.6, -0.3)
		if i == int(0.9 / DT):
			v = Vector2(0.5, 1.2)
		_tick(spot, v)
		spot += v * DT
	assert_lt(Vector2(_motor.x, _motor.z).distance_to(spot), 0.3, "with it")
	_checked("turning back")


# In depth his strokes are C-cuts: skating in or out he goes no faster than
# they take him, even after a spot that goes faster, and a still spot in depth
# is reached in the glide's time at that speed.
func test_in_depth_he_skates_no_faster_than_his_c_cuts() -> void:
	var cap: float = _motor.footwork.c_cut_speed
	var spot := Vector2(0.0, -1.8)
	var v := Vector2(0.0, 4.0)
	var fastest: float = 0.0
	for i: int in int(0.3 / DT):
		_tick(spot, v)
		spot += v * DT
		fastest = maxf(fastest, absf(_motor.glide.velocity.y))
	assert_lte(fastest, cap + 1e-4, "backing in after a spot at 4 m/s")
	before_each()
	spot = Vector2(0.0, -1.9)
	var t: float = 0.0
	fastest = 0.0
	while not _motor.is_idle() or t == 0.0:
		_tick(spot, Vector2.ZERO)
		t += DT
		fastest = maxf(fastest, absf(_motor.glide.velocity.y))
		if t > 2.0:
			break
	assert_lte(fastest, cap + 1e-4, "out to a still spot")
	assert_almost_eq(Vector2(_motor.x, _motor.z), spot, Vector2.ONE * 1e-4, "on it")
	assert_almost_eq(t, KeeperFootwork.push_time(0.9, cap, _motor.footwork.accel), 3.0 * DT,
			"in the glide's time at the C-cuts' speed")
	_checked("in depth")

extends GutTest

# Covering (KeeperCover, through KeeperMotor and KeeperSave's glove): a puck
# at his feet he can cover, from his feet once his drop lands and sooner when
# down; one out of his reach, one going too fast for the glove to stop, or one
# in the air, he cannot; a puck slowing on the ice is covered where it will be. Played out, he
# goes down, leans on over his pads after the glove and lays it on the puck,
# every tick unbroken, his gear out of the ice and his arms on their gear.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const PAD_GIVE_M: float = 0.025
const HARD_GIVE_M: float = 0.005
const MAX_BONE_STEP_M: float = 12.0 * DT  # nothing on him moves 12 m/s
const B := KeeperSkeleton.Bone
const R := KeeperMotor.Rest

var _motor: KeeperMotor = null
var _cover: KeeperCover = null
var _save: KeeperSave = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func before_each() -> void:
	_motor = KeeperMotor.new()
	_cover = KeeperCover.new()
	_save = KeeperSave.new()


func _on_ice(x: float, z: float) -> Vector3:
	return Vector3(x, KeeperShotRead.ON_ICE_Y, z)


func test_a_puck_at_his_feet_he_can_cover_and_one_out_of_reach_not() -> void:
	assert_true(_cover.plan(_on_ice(-0.2, -0.6), Vector3.ZERO, _motor, false), "at his feet")
	assert_almost_eq(Vector2(_cover.glove_at.x, _cover.glove_at.z), Vector2(-0.2, -0.6), Vector2.ONE * 1e-4,
			"the glove on it")
	var from_feet: float = _cover.land_s
	assert_gte(from_feet, _motor.save_move.drop_s * _motor.low_ready.fall_share() - 1e-6, "once his drop lands")
	_motor.rest = R.DOWN
	assert_true(_cover.plan(_on_ice(-0.2, -0.6), Vector3.ZERO, _motor, false), "down")
	assert_lt(_cover.land_s, from_feet, "down, sooner")
	assert_false(_cover.plan(_on_ice(0.0, -1.6), Vector3.ZERO, _motor, false), "out past his reach")
	assert_false(_cover.plan(_on_ice(1.2, -0.3), Vector3.ZERO, _motor, false), "wide of it")


# A puck in the air at his feet, dropping onto him or popped up off him, he
# leaves until it lands; one on the ice there he covers.
func test_a_puck_in_the_air_he_waits_out_until_it_lands() -> void:
	var at: Vector3 = _on_ice(-0.2, -0.6)
	assert_true(_cover.plan(at, Vector3.ZERO, _motor, false), "on the ice")
	assert_false(_cover.plan(at + Vector3.UP * 0.3, Vector3.ZERO, _motor, false), "above it")
	assert_false(_cover.plan(at + Vector3.UP * 0.3, Vector3(0.0, -2.0, 0.0), _motor, false), "dropping onto it")
	assert_false(_cover.plan(at, Vector3(0.0, 1.5, 0.0), _motor, false), "popped up off it")
	assert_true(KeeperCover.on_ice(at, Vector3(0.0, -0.5, 0.0)), "landing")


func test_a_sliding_puck_is_covered_where_it_will_be_if_it_slows_enough() -> void:
	_motor.rest = R.DOWN
	# Coming at him slowly, it will lie at his feet.
	var at := _on_ice(-0.2, -0.9)
	var v := Vector3(0.0, 0.0, 0.8)
	assert_true(_cover.plan(at, v, _motor, false), "dying at his feet")
	var there: Vector3 = KeeperCover.slid(at, v, _cover.land_s)
	assert_almost_eq(Vector2(_cover.glove_at.x, _cover.glove_at.z), Vector2(there.x, there.z), Vector2.ONE * 1e-4,
			"covered where it will be")
	assert_false(_cover.plan(_on_ice(-1.5, -0.6), Vector3(12.0, 0.0, 0.0), _motor, false), "a pass across: no")


func test_a_puck_slides_to_a_stop_on_the_ice_friction() -> void:
	var v := Vector3(2.0, 0.0, 0.0)
	var stop: float = 2.0 * 2.0 * 0.5 / GameRules.PUCK_ICE_DECEL_M_S2
	assert_almost_eq(KeeperCover.slid(Vector3.ZERO, v, 100.0).x, stop, 1e-5, "where friction stops it")
	assert_almost_eq(KeeperCover.slid(Vector3.ZERO, v, 0.1).x,
			2.0 * 0.1 - 0.5 * GameRules.PUCK_ICE_DECEL_M_S2 * 0.01, 1e-5, "slowing on the way")


func _bones() -> Array[Vector3]:
	_motor.pose(_pose)
	_save.overlay(_pose)
	_skel.pose(_pose)
	var out: Array[Vector3] = []
	for b: int in KeeperSkeleton.BONE_COUNT:
		out.append(_skel.xf[b].origin)
	return out


func _lowest(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# From his feet: down over a puck at his feet, the glove laid on it, every
# tick unbroken; only a breach is asserted.
func test_covering_from_his_feet_goes_down_and_lays_the_glove_on_it() -> void:
	var puck := _on_ice(-0.25, -0.65)
	assert_true(_cover.plan(puck, Vector3.ZERO, _motor, false))
	_motor.save(KeeperSaveMove.Low.BUTTERFLY, signf(_cover.target.x))
	var was: Array[Vector3] = _bones()
	var t: float = 0.0
	while not _save.hand_there() and t < 1.0:
		assert_true(_cover.plan(puck, Vector3.ZERO, _motor, false), "t %.3f: still his" % t)
		_save.cover(_cover.target, _cover.lean)
		_motor.step(DT)
		_motor.pose(_pose)
		_save.step(DT, false, _pose)
		t += DT
		var at: Array[Vector3] = _bones()
		for b: int in KeeperSkeleton.BONE_COUNT:
			if at[b].distance_to(was[b]) >= MAX_BONE_STEP_M:
				assert_lt(at[b].distance_to(was[b]), MAX_BONE_STEP_M, "t %.3f bone %d" % [t, b])
		was = at
		for part: int in KeeperGear.PART_COUNT:
			var soft: bool = KeeperGear.save_part(part) == GoalieSaveRules.SavePart.PAD
			var floor_y: float = -(PAD_GIVE_M if soft else HARD_GIVE_M)
			if _lowest(part) < floor_y:
				assert_gte(_lowest(part), floor_y, "t %.3f %s" % [t, KeeperGear.Part.keys()[part]])
		var gap: float = (_skel.xf[B.FOREARM_G] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0)) \
				.distance_to(_skel.xf[B.HAND_G].origin)
		if gap > 0.002:
			assert_almost_eq(gap, 0.0, 0.002, "t %.3f: the glove arm reaches its hand" % t)
	assert_true(_save.hand_there(), "the glove gets there")
	assert_lte(t, _cover.land_s + 2.0 * DT, "when the plan said")
	for i: int in 30:
		_motor.step(DT)
		_motor.pose(_pose)
		_save.step(DT, false, _pose)
	_bones()
	var glove: Vector3 = KeeperGear.box(_skel, KeeperGear.Part.GLOVE).origin
	assert_lte(Vector2(glove.x - puck.x, glove.z - puck.z).length(), KeeperCover.PIN_M, "on the puck")
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.GLOVE)
	assert_lte(glove.y - puck.y, h.length(), "down on it")
	assert_eq(_motor.save_move.state, KeeperSaveMove.State.HELD, "down")

extends GutTest

# The jersey's tail (KeeperJerseyTail), cloth on his body rig: standing ready
# and still it hangs exactly as built; through his moves it stays out of the
# pants and the thigh guards it drapes over, every vertex as skinned; a push
# throws the hem back against his acceleration, and it settles. And the
# colliders' test: a point is moved exactly when it lies inside the piece's
# surface stood off by the margin along its own direction from the piece's
# axis, onto that stood-off surface.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SAMPLES: int = 4000
const AT_REST_M: float = 0.001
const SINK_M: float = 0.004

var _keeper: Keeper = null
var _motor: KeeperMotor = null
var _pose := KeeperPose.new()
var _velocity := Vector2.ZERO


func before_each() -> void:
	_keeper = Keeper.new()
	add_child_autofree(_keeper)
	_motor = KeeperMotor.new()
	_velocity = Vector2.ZERO


# One tick of him: the motor stepped, his acceleration measured off it into
# his own space, posed, drawn and the cloth stepped.
func _tick() -> void:
	var was := Vector2(_motor.x, _motor.z)
	_motor.step(DT)
	var velocity: Vector2 = (Vector2(_motor.x, _motor.z) - was) / DT
	var a: Vector2 = (velocity - _velocity) / DT
	_velocity = velocity
	_keeper.acceleration = Basis(Vector3.UP, -_motor.yaw) * Vector3(a.x, 0.0, a.y)
	_motor.pose(_pose)
	_keeper.apply_pose(_pose)
	_keeper._process(DT)


func _tail() -> KeeperJerseyTail:
	return _keeper.find_child("JerseyTail", true, false) as KeeperJerseyTail


func _rig() -> Skeleton3D:
	return _keeper.find_child("BodyRig", true, false) as Skeleton3D


# Every vertex where its bones put it, his space; with `cloth_only`, only
# those below the top row, which is the protector's own hem on its bone.
func _skinned(cloth_only: bool = false) -> PackedVector3Array:
	var tail: KeeperJerseyTail = _tail()
	var arrays: Array = tail.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var out := PackedVector3Array()
	for v: int in verts.size():
		if cloth_only and bones[v * 4] == 0:
			continue
		var p := Vector3.ZERO
		for j: int in 4:
			var w: float = weights[v * 4 + j]
			if w > 0.0:
				p += _rig().get_bone_global_pose(tail.skin.get_bind_bone(bones[v * 4 + j])) * verts[v] * w
		out.append(p)
	return out


# The deepest any vertex of the cloth is inside the pants or a thigh guard.
func _sunk() -> float:
	var colliders := KeeperTailColliders.new()
	colliders.update(_rig())
	var worst: float = 0.0
	for p: Vector3 in _skinned(true):
		worst = maxf(worst, p.distance_to(colliders.push_out(p, 0.0)))
	return worst


# The hem's points' mean place against where its rest drape hangs them now.
func _hem_off_rest() -> Vector3:
	var tail: KeeperJerseyTail = _tail()
	var chest: Transform3D = _rig().get_bone_global_pose(KeeperGear.Part.CHEST)
	var points: PackedVector3Array = tail.flaps.hem_points()
	var sum := Vector3.ZERO
	for k: int in tail.flaps.columns:
		var rest: Vector3 = chest * tail.flaps.rest[HemFlaps.HEM][k]
		sum += points[k * HemFlaps.POINTS_PER_COLUMN + 1] - rest
	return sum / float(tail.flaps.columns)


func test_standing_ready_and_still_it_hangs_as_built() -> void:
	for i: int in 120:
		_tick()
	var tail: KeeperJerseyTail = _tail()
	var arrays: Array = tail.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var chest: Transform3D = _rig().get_bone_global_pose(KeeperGear.Part.CHEST)
	var at: PackedVector3Array = _skinned()
	var worst: float = 0.0
	for v: int in at.size():
		worst = maxf(worst, at[v].distance_to(chest * rest[v]))
	assert_lt(worst, AT_REST_M, "every vertex on its rest drape")
	assert_lt(_sunk(), SINK_M, "out of the pants and the thigh guards")


func test_through_his_moves_it_stays_out_of_what_it_drapes_over() -> void:
	var moves: Array[Callable] = [
		func() -> void: _motor.push_to(Vector2(1.0, -0.2)),
		func() -> void: _motor.drop_down(),
		func() -> void: _motor.slide_to(Vector2(-0.6, -0.4)),
		func() -> void: _motor.recover(1.0),
		func() -> void: _motor.push_to(Vector2(-0.8, -0.6)),
	]
	var worst: float = 0.0
	var ticks: int = 0
	for move: Callable in moves:
		move.call()
		var t: float = 0.0
		while not _motor.is_idle() and t < 3.0:
			_tick()
			t += DT
			ticks += 1
			if ticks % 6 == 0:
				worst = maxf(worst, _sunk())
	assert_lt(worst, SINK_M, "out of the pants and the thigh guards")
	assert_eq(_motor.refused, 0)


func test_a_push_throws_the_hem_back_and_it_settles() -> void:
	for i: int in 60:
		_tick()
	_motor.push_to(Vector2(1.2, 0.0))
	var back: float = 0.0
	var t: float = 0.0
	while t < 0.25:
		_tick()
		t += DT
		back = minf(back, _hem_off_rest().x)
	assert_lt(back, -0.01, "the hem swings back from the push")
	while not _motor.is_idle():
		_tick()
	for i: int in 120:
		_tick()
	assert_almost_eq(_hem_off_rest(), Vector3.ZERO, Vector3.ONE * AT_REST_M, "and comes back to rest")


func test_a_point_is_moved_exactly_when_inside_the_stood_off_surface() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xf := Transform3D(Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.4), Vector3(0.1, 0.6, -0.05))
	var margin: float = KeeperJerseyTail.CLOTH_M
	var pieces: Array = [
		[KeeperGearMeshes.PANTS_SECTIONS, KeeperGear.half_extents(KeeperGear.Part.PANTS)],
		[KeeperGearMeshes.THIGH_SECTIONS, KeeperGear.half_extents(KeeperGear.Part.THIGH_G)],
	]
	for piece: Array in pieces:
		var sections: Array[Vector4] = piece[0]
		var h: Vector3 = piece[1]
		var moved: int = 0
		for i: int in SAMPLES:
			var local := Vector3(rng.randf_range(-1.3, 1.3) * h.x, rng.randf_range(-0.98, 0.98) * h.y,
					rng.randf_range(-1.3, 1.3) * h.z)
			var flat := Vector2(local.x, local.z)
			var sec: Vector3 = KeeperGearMeshes.section_at(sections, h, local.y)
			var surface: Vector3 = KeeperTailColliders.on_section(sec, local.y, flat.normalized(), margin)
			var inside: bool = flat.length() < Vector2(surface.x, surface.z).length()
			var got: Vector3 = KeeperTailColliders.push_out_of(xf * local, xf, xf.affine_inverse(), sections, h,
					margin)
			var want: Vector3 = xf * surface if inside else xf * local
			assert_almost_eq(got, want, Vector3.ONE * 1e-5, "%s" % local)
			if inside:
				moved += 1
		assert_between(moved, SAMPLES / 10, SAMPLES * 9 / 10, "both sides of the surface sampled")

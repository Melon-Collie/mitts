extends GutTest

# PuckSpinRig: the drawn puck's spin, wobble and tumble, read off its motion.

const DT: float = 1.0 / 120.0
const LOOSE: Vector3 = Vector3.INF
const R: float = PuckSpinRig.RADIUS

var _rig: PuckSpinRig
var _mesh: MeshInstance3D
var _pos: Vector3


func before_each() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = PuckMeshBuilder._build_puck()
	_rig = PuckSpinRig.new(_mesh)
	_pos = Vector3(0.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, 0.0)


func after_each() -> void:
	_mesh.free()


func _reset() -> void:
	after_each()
	before_each()


func _step(vel: Vector3, airborne: bool = false, carrier: Vector3 = LOOSE) -> void:
	_pos += vel * DT
	_rig.step(DT, _pos, airborne, _pos.y - GameRules.PUCK_COLLISION_HALF_HEIGHT, carrier)


func _slide(vel: Vector3, seconds: float, airborne: bool = false) -> Vector3:
	var v: Vector3 = vel
	for i: int in int(round(seconds / DT)):
		if not airborne:
			v = v.move_toward(Vector3.ZERO, GameRules.PUCK_ICE_DECEL_M_S2 * DT)
		else:
			v.y -= GameRules.GRAVITY_M_S2 * DT
		_step(v, airborne)
	return v


func _hold(seconds: float) -> void:
	_slide(Vector3.ZERO, seconds)


func test_a_straight_slide_stays_flat() -> void:
	_slide(Vector3(20.0, 0.0, 0.0), 2.0)
	assert_true(_rig.is_flat(), "friction alone is no hit")
	assert_eq(_rig.spin, 0.0)


func test_a_board_glance_spins_against_the_slide() -> void:
	_slide(Vector3(10.0, 0.0, 3.0), 0.1)
	_slide(Vector3(8.0, 0.0, -1.0), DT)
	var spin: float = _rig.spin
	# Sliding +x into a wall on +z, the rim drags back along the wall: clockwise
	# from above.
	assert_lt(spin, 0.0, "the glance spins the disc against its slide")
	# Friction can at most stop the rim's slip — a third of it for a disc.
	assert_lte(absf(spin) * R, 10.5 * 2.0 / 3.0, "spin is bounded by the slip it stops")

	_reset()
	_slide(Vector3(10.0, 0.0, -3.0), 0.1)
	_slide(Vector3(8.0, 0.0, 1.0), DT)
	assert_almost_eq(_rig.spin, -spin, 0.01, "the mirrored glance spins the other way")


func test_a_hit_wobbles_then_settles_flat() -> void:
	_slide(Vector3(10.0, 0.0, 0.0), 0.1)
	_slide(Vector3(-4.0, 0.0, 0.0), DT)
	assert_gt(_rig.tilt, 0.0, "a hit rocks the disc")
	_slide(Vector3(-4.0, 0.0, 0.0), 1.5)
	assert_true(_rig.is_flat(), "and the ice lays it flat again")


func test_the_wobble_circles_faster_as_it_flattens() -> void:
	_rig.tilt_settle_rate = 0.0
	_hold(DT)
	_rig.tilt = 0.4
	var a0: float = _rig.tilt_azimuth
	_hold(DT)
	var steep: float = absf(angle_difference(a0, _rig.tilt_azimuth))
	_rig.tilt = 0.05
	a0 = _rig.tilt_azimuth
	_hold(DT)
	var shallow: float = absf(angle_difference(a0, _rig.tilt_azimuth))
	assert_gt(shallow, steep, "Euler's disk: the lean circles faster as it flattens")


func test_spin_slows_the_settle() -> void:
	_hold(DT)
	_rig.tilt = 0.3
	_hold(0.3)
	var still: float = _rig.tilt
	_reset()
	_hold(DT)
	_rig.tilt = 0.3
	_rig.spin = 60.0
	_hold(0.3)
	assert_gt(_rig.tilt, still, "a spinning disc holds its lean longer")


func test_a_puck_spinning_in_place_stops_on_the_face_friction_clock() -> void:
	_hold(DT)
	_rig.spin = 30.0
	var ticks: int = 0
	while _rig.spin != 0.0 and ticks < 1000:
		_hold(DT)
		ticks += 1
	assert_almost_eq(ticks * DT, 30.0 / PuckSpinRig.SPIN_DECEL_AT_REST, 2.0 * DT,
			"(2/3)·μ·m·g·R of face friction over ½·m·R²")


func test_a_sliding_puck_keeps_its_spin_longer() -> void:
	_hold(DT)
	_rig.spin = 30.0
	_hold(0.5)
	var still: float = _rig.spin
	_reset()
	_slide(Vector3(10.0, 0.0, 0.0), DT)
	_rig.spin = 30.0
	_slide(Vector3(10.0, 0.0, 0.0), 0.5)
	assert_gt(_rig.spin, still, "a slide turns the friction away from the spin")


func test_a_clean_release_flies_flat_and_spinning() -> void:
	for i: int in 20:
		_step(Vector3(5.0, 0.0, 0.0), false, _pos + Vector3(-0.3, 0.0, -1.0))
	_slide(Vector3(20.0, 4.0, 0.0), 0.4, true)
	assert_eq(_rig.tumble_rate, 0.0, "a puck off the blade does not tumble")
	assert_almost_eq(_rig.axis().y, 1.0, 1e-4, "it flies flat")
	assert_almost_eq(absf(_rig.spin), _rig.release_roll_share * Vector3(20.0, 4.0, 0.0).length() / R,
			3.0, "rolled off the blade heel to toe")


func test_spin_keeps_a_deflected_puck_flying_truer() -> void:
	var rates: Array[float] = []
	for spin: float in [0.0, 100.0]:
		_reset()
		_pos.y = 1.0
		_slide(Vector3(20.0, 0.0, 0.0), 0.05, true)
		_rig.spin = spin
		_slide(Vector3(18.0, 2.0, 5.0), DT, true)
		rates.append(_rig.tumble_rate)
	assert_gt(rates[0], 0.0, "a deflection tumbles the puck")
	assert_gt(rates[0], rates[1], "and spin resists it")


func test_a_tumbling_puck_lands_into_a_wobble() -> void:
	_pos.y = 1.0
	_slide(Vector3(15.0, 0.0, 0.0), 0.05, true)
	_slide(Vector3(12.0, 1.0, 4.0), 0.2, true)
	assert_gt(_rig.tumble_rate, 0.0)
	_pos.y = GameRules.PUCK_COLLISION_HALF_HEIGHT
	_slide(Vector3(12.0, 0.0, 4.0), DT)
	assert_eq(_rig.tumble_rate, 0.0, "the ice ends the tumble")
	assert_lte(_rig.tilt, _rig.max_tilt_on_ice)
	_slide(Vector3(12.0, 0.0, 4.0), 2.0)
	assert_true(_rig.is_flat(), "and the wobble it lands in settles")


func test_a_carried_puck_never_wobbles() -> void:
	for i: int in 120:
		var dangle := Vector3(0.0, 0.0, 6.0 if i % 10 < 5 else -6.0)
		_step(dangle, false, _pos + Vector3(-1.0, 0.0, 0.0))
	assert_true(_rig.is_flat(), "the blade, not a hit, moves a carried puck")


func test_a_restage_is_not_a_hit() -> void:
	_slide(Vector3(10.0, 0.0, 0.0), 0.2)
	_pos = Vector3(30.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, 5.0)
	_hold(0.1)
	assert_true(_rig.is_flat())
	assert_eq(_rig.spin, 0.0)


# The drawn disc, tilted any way, rests its low rim on the ice and never in it.
func test_the_tilted_disc_rests_on_the_ice() -> void:
	_rig.tilt_settle_rate = 0.0
	var verts: PackedVector3Array = _mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var ice_y: float = -GameRules.PUCK_COLLISION_HALF_HEIGHT
	for tilt: float in [0.05, 0.2, 0.5]:
		for az: float in [0.0, 1.0, 2.5, 4.0]:
			_rig.tilt = tilt
			_rig.tilt_azimuth = az
			_rig.spin = 10.0
			_hold(DT)
			var low: float = INF
			for v: Vector3 in verts:
				low = minf(low, (_mesh.transform * v).y)
			assert_gte(low, ice_y - 1e-5, "tilt %.2f az %.1f sinks into the ice" % [tilt, az])
			assert_lt(low, ice_y + 0.0005, "tilt %.2f az %.1f floats off the ice" % [tilt, az])


func test_only_the_puck_drives_the_rig() -> void:
	var users: Array[String] = []
	_scan("res://Scripts", users)
	assert_eq(users, ["res://Scripts/actors/puck.gd"] as Array[String],
			"the spin is cosmetic: nothing but the puck may hold it")


func _scan(dir: String, users: Array[String]) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(sub), users)
	for f: String in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd") or f == "puck_spin_rig.gd":
			continue
		var path: String = dir.path_join(f)
		if FileAccess.get_file_as_string(path).contains("PuckSpinRig"):
			users.append(path)

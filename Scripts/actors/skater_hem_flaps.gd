class_name SkaterHemFlaps
extends RefCounted

# The jersey's tail below the belt as a ring of two-segment flaps, one per torso
# facet column: belt → bend → hem, each segment a root bone posed in skeleton
# space (SkaterBodySkeleton.column_bone) that its column's vertices ride rigidly
# (SkaterJerseyHem.append_torso).
#
# A column hangs from its point on the belt ring, which is where the torso
# surface's own weights put it — carried by the chest and the hips in the share
# the azimuth and the tuck give it — so the jersey is one surface across the
# belt. Its two free points (the bend, the hem) are verlet particles in the
# skeleton's frame, sprung to the rest drape (how stiff the fabric is) and
# driven by gravity less the skater's own acceleration — less the gravity the
# drape is authored hanging under, so it hangs as built at rest and swings only
# when the pull on it moves off the body's own axis: a start throws the hem
# back, a stop forward. Then, a few times a step, they are held to their
# segment lengths, to their neighbours' spacing round the ring (what makes a
# ring of flaps one sweater), and on the last iterations pushed out of the
# thighs and the pants (SkaterHemColliders) — the segments' midpoints and the
# faces' between columns too, so neither a thigh nor a corner of the pants'
# own facets can pass between two points. A tucked column is held at its tucked
# rest.
#
# The rest drape is the lathe's own rings, tucked as the skater's tuck drapes
# them, torso-local: `rest[station][column]` for the four tail stations from the
# belt down (SkaterMeshBuilder.TORSO_BELT_STATION and on).
#
# It runs in C++ where the extension is built (NativeHemFlaps), which reads the
# same bones, steps the same solver and writes the same bones. Change step(),
# _relax(), _write_bones() or the colliders and the port changes with them, or
# test_native_hem_flaps_parity.gd fails.

const FIRST_STATION: int = SkaterMeshBuilder.TORSO_BELT_STATION
const STATIONS: int = SkaterMeshBuilder.TORSO_HEM_STATION - SkaterMeshBuilder.TORSO_BELT_STATION + 1
const BEND: int = SkaterMeshBuilder.TORSO_BEND_STATION - SkaterMeshBuilder.TORSO_BELT_STATION
const HEM: int = STATIONS - 1
# hem_points' samples per column: the bend, the hem, the midpoints of its two
# segments, and the midpoints toward the next column of the bend and the hem.
const POINTS_PER_COLUMN: int = 6

var gravity_m_s2: float = 9.8
# The fabric's spring back to its drape, as a natural frequency, and the share
# of a particle's speed it loses per second — together an underdamped swing that
# settles in about half a second.
var shape_hz: float = 1.6
var damping_per_s: float = 7.0
var ring_stiffness: float = 0.35
var iterations: int = 3
# Iterations, from the last, that also collide: the earlier ones only settle the
# lengths and spacing the collisions then correct.
var colliding_iterations: int = 2
var margin_m: float = 0.012
var max_step_s: float = 1.0 / 30.0

var columns: int = SkaterMeshBuilder.TORSO_SIDES
var rest: Array[PackedVector3Array] = []
# Per column: how much of the belt point the hips carry, and how tucked it is.
var hips_share := PackedFloat32Array()
var tuck_share := PackedFloat32Array()
# Set false to run the GDScript reference where the port is built.
var native_enabled: bool = true

var _skater: Skater = null
var _skeleton: Skeleton3D = null
var _colliders := SkaterHemColliders.new()
var _native: RefCounted = null
var _bend := PackedVector3Array()
var _hem := PackedVector3Array()
var _bend_prev := PackedVector3Array()
var _hem_prev := PackedVector3Array()
var _anchor := PackedVector3Array()
var _last_dt: float = 0.0
var _started: bool = false


func setup(skater: Skater, skeleton: Skeleton3D, tuck: int) -> void:
	_skater = skater
	_skeleton = skeleton
	if ClassDB.class_exists(&"NativeHemFlaps"):
		_native = ClassDB.instantiate(&"NativeHemFlaps") as RefCounted
		var legs: int = SkaterBodySkeleton.LEG_BONE_OFFSET
		_native.call("bind", skeleton, PackedInt32Array([SkaterMeshBuilder.UpperBone.TORSO,
				SkaterBodySkeleton.TAIL_BONE, SkaterMeshBuilder.UpperBone.PELVIS,
				legs + SkaterMeshBuilder.LegBone.LEG_L, legs + SkaterMeshBuilder.LegBone.LEG_R,
				legs + SkaterMeshBuilder.LegBone.THIGH_L, legs + SkaterMeshBuilder.LegBone.THIGH_R,
				SkaterBodySkeleton.COLUMN_BONE_BASE]))
	set_tuck(tuck)


func set_tuck(tuck: int) -> void:
	rest.clear()
	for station: int in STATIONS:
		rest.append(SkaterMeshBuilder.torso_ring(FIRST_STATION + station, tuck))
	hips_share.resize(columns)
	tuck_share.resize(columns)
	var phase: float = TAU * SkaterMeshBuilder.TORSO_U_PHASE
	for k: int in columns:
		var azimuth: float = TAU * float(k) / float(columns) + phase
		tuck_share[k] = SkaterJerseyHem.tuck_share(tuck, azimuth)
		hips_share[k] = lerpf(SkaterJerseyHem.carry(azimuth), 1.0, tuck_share[k])
	_started = false
	configure_native()


# Hands the port the drape and the tunables (and restarts it); re-run after
# changing either.
func configure_native() -> void:
	if _native == null:
		return
	var drape := PackedVector3Array()
	for station: int in STATIONS:
		drape.append_array(rest[station].slice(0, columns))
	_native.call("configure", drape, hips_share, tuck_share, SkaterMeshBuilder.pelvis_stations(),
			PackedFloat64Array([gravity_m_s2, shape_hz, ring_stiffness, damping_per_s,
					margin_m, max_step_s, SkaterMeshBuilder.THIGH_CAPSULE_LENGTH_M,
					SkaterMeshBuilder.THIGH_CAPSULE_RADIUS_M,
					SkaterMeshBuilder.PELVIS_XZ_SCALE.x, SkaterMeshBuilder.PELVIS_XZ_SCALE.y]),
			PackedInt32Array([iterations, colliding_iterations]))


# One frame: gravity less the skater's acceleration, then the step. Bones are
# written only when drawn; the swing keeps time off camera too.
func update(delta: float, on_camera: bool) -> void:
	var g: Vector3 = _skeleton.global_basis.orthonormalized().inverse() \
			* Vector3(0.0, -gravity_m_s2, 0.0) - _acceleration()
	step(delta, g, on_camera)


# Advances the drape by `delta` under the effective gravity `g` (skeleton
# space: gravity less the skater's acceleration) against this frame's bones,
# and writes the flap bones if `write`.
func step(delta: float, g: Vector3, write: bool) -> void:
	if _native != null and native_enabled:
		_native.call("step", delta, g, write)
		return
	var dt: float = minf(delta, max_step_s)
	if dt <= 0.0:
		return
	var torso: Transform3D = _skeleton.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TORSO)
	var tail: Transform3D = _skeleton.get_bone_global_pose(SkaterBodySkeleton.TAIL_BONE)
	_colliders.update(_skeleton)
	_anchor.resize(columns)
	for k: int in columns:
		_anchor[k] = (torso * rest[0][k]).lerp(tail * rest[0][k], hips_share[k])
	var drape: Basis = tail.basis
	if not _started:
		_start(drape)
	var drive: Vector3 = (g + drape.y.normalized() * gravity_m_s2) * dt * dt
	var carry: float = exp(-damping_per_s * dt) * (dt / _last_dt if _last_dt > 0.0 else 1.0)
	var pull: float = minf(pow(TAU * shape_hz * dt, 2.0), 1.0)
	for k: int in columns:
		var b: Vector3 = _bend[k]
		_bend[k] += (b - _bend_prev[k]) * carry + drive
		_bend[k] += (_rest_bend(k, drape) - _bend[k]) * pull
		_bend_prev[k] = b
		var h: Vector3 = _hem[k]
		_hem[k] += (h - _hem_prev[k]) * carry + drive
		_hem[k] += (_rest_hem(k, drape) - _hem[k]) * pull
		_hem_prev[k] = h
	_last_dt = dt
	for it: int in iterations:
		_relax(drape, it >= iterations - colliding_iterations)
	for k: int in columns:
		var t: float = tuck_share[k]
		if t > 0.0:
			_bend[k] = _bend[k].lerp(_rest_bend(k, drape), t)
			_hem[k] = _hem[k].lerp(_rest_hem(k, drape), t)
	if write:
		_write_bones(drape)


# Where the tail is drawn, skeleton space: POINTS_PER_COLUMN samples a column.
func hem_points() -> PackedVector3Array:
	if _native != null and native_enabled:
		return _native.call("get_points")
	var out := PackedVector3Array()
	for k: int in _bend.size():
		var n: int = (k + 1) % _bend.size()
		out.append(_bend[k])
		out.append(_hem[k])
		out.append((_anchor[k] + _bend[k]) * 0.5)
		out.append((_bend[k] + _hem[k]) * 0.5)
		out.append((_bend[k] + _bend[n]) * 0.5)
		out.append((_hem[k] + _hem[n]) * 0.5)
	return out


func colliders() -> SkaterHemColliders:
	return _colliders


# The solver's state as (bend, hem, bend_prev, hem_prev) packed end to end, and
# the last step's dt; the parity test seeds both sides from one.
func get_state() -> PackedVector3Array:
	if _native != null and native_enabled:
		return _native.call("get_state")
	var out := PackedVector3Array(_bend)
	out.append_array(_hem)
	out.append_array(_bend_prev)
	out.append_array(_hem_prev)
	return out


func set_state(state: PackedVector3Array, last_dt: float) -> void:
	if _native != null and native_enabled:
		_native.call("set_state", state, last_dt)
		return
	_bend = state.slice(0, columns)
	_hem = state.slice(columns, 2 * columns)
	_bend_prev = state.slice(2 * columns, 3 * columns)
	_hem_prev = state.slice(3 * columns, 4 * columns)
	_last_dt = last_dt
	_started = true


# Steps a still figure's drape is settled for: long past its swing's settling.
const SETTLE_STEPS: int = 90


# The torso as a figure that is not a skinned rig wears it (FigureKit — the
# locker's mannequin, the lobby's bench): the tail settled hanging over the
# figure's own pants and legs, and baked into the torso's own frame. `torso`,
# `pelvis` and each leg's frame at its hip (as SkaterBodySkeleton's LEG bone
# carries it, scaled by the leg's bulk) are the figure's parts in one upright
# space.
static func baked_torso(tuck: int, torso: Transform3D, pelvis: Transform3D,
		legs: Array[Transform3D]) -> ArrayMesh:
	var skeleton: Skeleton3D = SkaterBodySkeleton.new_body_skeleton()
	var leg_bones: Array[int] = [SkaterMeshBuilder.LegBone.LEG_L, SkaterMeshBuilder.LegBone.LEG_R]
	skeleton.set_bone_pose(SkaterMeshBuilder.UpperBone.TORSO, torso)
	skeleton.set_bone_pose(SkaterBodySkeleton.TAIL_BONE, torso)
	skeleton.set_bone_pose(SkaterMeshBuilder.UpperBone.PELVIS, pelvis)
	for i: int in 2:
		skeleton.set_bone_pose(SkaterBodySkeleton.LEG_BONE_OFFSET + leg_bones[i], legs[i])
	var flaps := SkaterHemFlaps.new()
	flaps.setup(null, skeleton, tuck)
	for i: int in SETTLE_STEPS:
		flaps.step(1.0 / 60.0, Vector3(0.0, -flaps.gravity_m_s2, 0.0), i == SETTLE_STEPS - 1)
	var arrays: Array = SkaterMeshBuilder.shared_torso(tuck).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = SkaterMeshBuilder.shared_upper_skin_mesh(tuck) \
			.surface_get_arrays(SkaterMeshBuilder.UpperSurface.TORSO)[Mesh.ARRAY_BONES]
	var to_torso: Transform3D = torso.affine_inverse()
	for v: int in verts.size():
		var bind: int = bones[v * 4] - SkaterMeshBuilder.UPPER_COLUMN_BIND_BASE
		if bind < 0:
			continue
		var moved: Transform3D = to_torso * skeleton.get_bone_pose(
				SkaterBodySkeleton.COLUMN_BONE_BASE + bind)
		verts[v] = moved * verts[v]
		normals[v] = (moved.basis * normals[v]).normalized()
	skeleton.free()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# The skater's acceleration, skeleton space: what the balance lean leans toward
# (BalanceRules — atan(|a| / g)), so it is read back off the lean.
func _acceleration() -> Vector3:
	var tilt: Vector2 = _skater.balance_tilt()
	var angle: float = tilt.length()
	if angle < 1e-5:
		return Vector3.ZERO
	var world := Vector3(tilt.x, 0.0, tilt.y) / angle * gravity_m_s2 * tan(angle)
	return _skeleton.global_basis.orthonormalized().inverse() * world


func _start(drape: Basis) -> void:
	_bend.resize(columns)
	_hem.resize(columns)
	for k: int in columns:
		_bend[k] = _rest_bend(k, drape)
		_hem[k] = _rest_hem(k, drape)
	_bend_prev = _bend.duplicate()
	_hem_prev = _hem.duplicate()
	_last_dt = 0.0
	_started = true


func _rest_bend(k: int, drape: Basis) -> Vector3:
	return _anchor[k] + drape * (rest[BEND][k] - rest[0][k])


func _rest_hem(k: int, drape: Basis) -> Vector3:
	return _anchor[k] + drape * (rest[HEM][k] - rest[0][k])


func _relax(drape: Basis, collide: bool) -> void:
	for k: int in columns:
		var a: Vector3 = _anchor[k]
		# The upper segment hangs from a fixed point; the lower shares its pull.
		var upper: float = (drape * (rest[BEND][k] - rest[0][k])).length()
		_bend[k] = a + (_bend[k] - a).normalized() * upper
		var lower: float = (drape * (rest[HEM][k] - rest[BEND][k])).length()
		var d: Vector3 = _hem[k] - _bend[k]
		var fix: Vector3 = d * (1.0 - lower / maxf(d.length(), 1e-6)) * 0.5
		_bend[k] += fix
		_hem[k] -= fix
	for k: int in columns:
		var n: int = (k + 1) % columns
		var fix_bend: Vector3 = _spacing(_bend[k], _bend[n],
				(drape * (rest[BEND][n] - rest[BEND][k])).length())
		_bend[k] += fix_bend
		_bend[n] -= fix_bend
		var fix_hem: Vector3 = _spacing(_hem[k], _hem[n],
				(drape * (rest[HEM][n] - rest[HEM][k])).length())
		_hem[k] += fix_hem
		_hem[n] -= fix_hem
	if not collide:
		return
	for k: int in columns:
		var a: Vector3 = _anchor[k]
		_bend[k] = _colliders.push_out(_bend[k], margin_m)
		_hem[k] = _colliders.push_out(_hem[k], margin_m)
		var m: Vector3 = (a + _bend[k]) * 0.5
		_bend[k] += (_colliders.push_out(m, margin_m) - m) * 2.0
		m = (_bend[k] + _hem[k]) * 0.5
		var push: Vector3 = _colliders.push_out(m, margin_m) - m
		_bend[k] += push
		_hem[k] += push
	for k: int in columns:
		var n: int = (k + 1) % columns
		var m: Vector3 = (_bend[k] + _bend[n]) * 0.5
		var push: Vector3 = _colliders.push_out(m, margin_m) - m
		_bend[k] += push
		_bend[n] += push
		m = (_hem[k] + _hem[n]) * 0.5
		push = _colliders.push_out(m, margin_m) - m
		_hem[k] += push
		_hem[n] += push


# The move toward `b` that `a` takes (and `b` the opposite) to close part of
# their gap's departure from `rest_len`.
func _spacing(a: Vector3, b: Vector3, rest_len: float) -> Vector3:
	var d: Vector3 = b - a
	return d * (1.0 - rest_len / maxf(d.length(), 1e-6)) * 0.5 * ring_stiffness


func _write_bones(drape: Basis) -> void:
	for k: int in columns:
		_write_segment(k, 0, _anchor[k], _bend[k], rest[0][k], rest[BEND][k], drape)
		_write_segment(k, 1, _bend[k], _hem[k], rest[BEND][k], rest[HEM][k], drape)


# A segment's bone: the rest drape turned about its top so its rest direction
# points along the simulated one, with its top moved to the simulated top.
func _write_segment(k: int, joint: int, top: Vector3, bottom: Vector3, rest_top: Vector3,
		rest_bottom: Vector3, drape: Basis) -> void:
	var from: Vector3 = (drape * (rest_bottom - rest_top)).normalized()
	var to: Vector3 = (bottom - top).normalized()
	var turn := Basis.IDENTITY
	if from.dot(to) < 0.99999:
		turn = Basis(Quaternion(from, to))
	var basis: Basis = turn * drape
	_skeleton.set_bone_pose(SkaterBodySkeleton.column_bone(k, joint),
			Transform3D(basis, top - basis * rest_top))

class_name SkaterHemFlaps
extends SkaterHemSim

# The tail below the belt as a ring of two-segment flaps, one per torso facet
# column: belt → bend → hem, each segment a root bone posed in skeleton space
# that its column's vertices ride rigidly (SkaterJerseyHem TAIL_COLUMNS).
#
# The two free points of each column (the bend, the hem) are verlet particles in
# the skeleton's frame, pulled by gravity less the skater's own acceleration —
# so a start throws the hem back and a stop forward — and then, a few times a
# step: held to their segment lengths, eased toward the rest drape (how stiff
# the fabric is), held to their neighbours' spacing round the ring (what makes a
# ring of flaps one sweater), and pushed out of the thighs and the pants
# (SkaterHemColliders), the segments' midpoints too, so a thigh cannot pass
# between two points. A tucked column is held at its tucked rest.

var gravity_m_s2: float = 9.8
# Share of the gap to the rest drape closed per iteration.
var shape_stiffness: float = 0.06
var ring_stiffness: float = 0.35
# Share of a particle's velocity lost per step.
var damping: float = 0.08
var iterations: int = 3
# Iterations, from the last, that also collide: the earlier ones only settle the
# lengths and spacing the collisions then correct.
var colliding_iterations: int = 2
var margin_m: float = 0.012
var max_step_s: float = 1.0 / 30.0

var _bend := PackedVector3Array()
var _hem := PackedVector3Array()
var _bend_prev := PackedVector3Array()
var _hem_prev := PackedVector3Array()
var _anchor := PackedVector3Array()
var _last_dt: float = 0.0
var _started: bool = false


func _rested() -> void:
	_started = false


func update(delta: float, on_camera: bool) -> void:
	var dt: float = minf(delta, max_step_s)
	if dt <= 0.0:
		return
	var torso: Transform3D = _torso()
	var tail: Transform3D = _tail()
	_colliders.update(_skeleton)
	_anchor = anchors(torso, tail)
	var drape: Basis = tail.basis
	if not _started:
		_start(drape)
	var g: Vector3 = _skeleton.global_basis.orthonormalized().inverse() \
			* Vector3(0.0, -gravity_m_s2, 0.0) - _acceleration()
	var carry: float = (1.0 - damping) * (dt / _last_dt if _last_dt > 0.0 else 1.0)
	for k: int in columns:
		var b: Vector3 = _bend[k]
		_bend[k] += (b - _bend_prev[k]) * carry + g * dt * dt
		_bend_prev[k] = b
		var h: Vector3 = _hem[k]
		_hem[k] += (h - _hem_prev[k]) * carry + g * dt * dt
		_hem_prev[k] = h
	_last_dt = dt
	for it: int in iterations:
		_relax(drape, it >= iterations - colliding_iterations)
	for k: int in columns:
		var t: float = tuck_share[k]
		if t > 0.0:
			_bend[k] = _bend[k].lerp(_rest_bend(k, drape), t)
			_hem[k] = _hem[k].lerp(_rest_hem(k, drape), t)
	if on_camera:
		_write_bones(drape)


func hem_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for k: int in columns:
		out.append(_bend[k])
		out.append(_hem[k])
		out.append((_anchor[k] + _bend[k]) * 0.5)
		out.append((_bend[k] + _hem[k]) * 0.5)
	return out


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
		_bend[k] += (_rest_bend(k, drape) - _bend[k]) * shape_stiffness
		_hem[k] += (_rest_hem(k, drape) - _hem[k]) * shape_stiffness
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
	_skeleton.set_bone_pose(SkaterBodySkeleton.column_bone(HemSimMode.FLAPS, k, joint),
			Transform3D(basis, top - basis * rest_top))

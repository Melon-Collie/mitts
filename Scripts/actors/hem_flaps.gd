class_name HemFlaps
extends RefCounted

# A garment's tail as a ring of two-segment cloth flaps: from its point on the
# edge it hangs from → bend → hem, each segment a root bone posed in skeleton
# space that the cloth's vertices ride. The skater's jersey below the belt
# (SkaterHemFlaps) and the keeper's below his chest protector
# (KeeperJerseyTail) both hang this way.
#
# A column hangs from its anchor: its rest point carried by the `top` bone, or
# by the `drape` bone in the share `hips_share` gives it. Its two free points
# (the bend, the hem) are verlet particles in the skeleton's frame, sprung to
# the rest drape turned with the `drape` bone (how stiff the fabric is) and
# driven by gravity less the figure's own acceleration — less the gravity the
# drape is authored hanging under (`authored_up`, turned with the drape), so it
# hangs as built at rest and swings only
# when the pull on it moves off the body's own axis: a start throws the hem
# back, a stop forward. Then, a few times a step, they are held to their
# segment lengths, to their neighbours' spacing round the ring (what makes a
# ring of flaps one garment), and on the last iterations pushed out of what
# they hang over (HemColliders) — the segments' midpoints and the faces'
# between columns too, so nothing can pass between two points. A tucked column
# is held at its tucked rest.
#
# `rest[station][column]` is the drape at rest in the frame of the bones'
# rest: station 0 the anchor ring, BEND and HEM the free points (the stations
# between ride the segments and are not simulated).
#
# It runs in C++ where the extension is built (NativeHemFlaps), which reads the
# same bones, steps the same solver and writes the same bones. Change step(),
# _relax(), _write_bones() or a collider and the port changes with them, or
# test_native_hem_flaps_parity.gd fails.

const STATIONS: int = 4
const BEND: int = 2
const HEM: int = 3
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

var columns: int = 0
var rest: Array[PackedVector3Array] = []
# Up, in the rest drape's frame, as it was hung: the rest drape hangs under
# gravity along −`authored_up`.
var authored_up := Vector3.UP
# Per column: how much of the anchor the `drape` bone carries, and whether it
# is tucked in (held at its rest; a lifted column hangs free).
var hips_share := PackedFloat32Array()
var tuck_share := PackedFloat32Array()
# Set false to run the GDScript reference where the port is built.
var native_enabled: bool = true

var _skeleton: Skeleton3D = null
var _top_bone: int = -1
var _drape_bone: int = -1
var _first_column_bone: int = -1
var _colliders: HemColliders = null
var _native: RefCounted = null
var _bend := PackedVector3Array()
var _hem := PackedVector3Array()
var _bend_prev := PackedVector3Array()
var _hem_prev := PackedVector3Array()
var _anchor := PackedVector3Array()
var _last_dt: float = 0.0
var _started: bool = false


# The skeleton it hangs in: the bone that carries the anchors, the one its rest
# drape turns with, and the first of its flap bones (column k's segments are
# that one + 2k and + 2k + 1); and what it drapes over.
func bind(skeleton: Skeleton3D, top_bone: int, drape_bone: int, first_column_bone: int,
		over: HemColliders) -> void:
	_skeleton = skeleton
	_top_bone = top_bone
	_drape_bone = drape_bone
	_first_column_bone = first_column_bone
	_colliders = over
	_native = null
	if ClassDB.class_exists(&"NativeHemFlaps"):
		_native = ClassDB.instantiate(&"NativeHemFlaps") as RefCounted
		_native.call("bind", skeleton, PackedInt32Array([top_bone, drape_bone, first_column_bone]))


# Hands the port the drape, the tunables and the colliders (and restarts it);
# re-run after changing any of them.
func configure_native() -> void:
	if _native == null:
		return
	var drape := PackedVector3Array()
	for station: int in STATIONS:
		drape.append_array(rest[station].slice(0, columns))
	_native.call("configure", drape, hips_share, tuck_share,
			PackedFloat64Array([gravity_m_s2, shape_hz, ring_stiffness, damping_per_s, margin_m, max_step_s,
					authored_up.x, authored_up.y, authored_up.z]),
			PackedInt32Array([iterations, colliding_iterations]))
	_colliders.configure_native(_native)


# Advances the drape by `delta` under the effective gravity `g` (skeleton
# space: gravity less the figure's acceleration) against this frame's bones,
# and writes the flap bones if `write`.
func step(delta: float, g: Vector3, write: bool) -> void:
	if _native != null and native_enabled:
		_native.call("step", delta, g, write)
		return
	var dt: float = minf(delta, max_step_s)
	if dt <= 0.0:
		return
	var top: Transform3D = _skeleton.get_bone_global_pose(_top_bone)
	var tail: Transform3D = _skeleton.get_bone_global_pose(_drape_bone)
	_colliders.update(_skeleton)
	_anchor.resize(columns)
	for k: int in columns:
		_anchor[k] = (top * rest[0][k]).lerp(tail * rest[0][k], hips_share[k])
	var drape: Basis = tail.basis
	if not _started:
		_start(drape)
	var drive: Vector3 = (g + (drape * authored_up).normalized() * gravity_m_s2) * dt * dt
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


func colliders() -> HemColliders:
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


# Starts it over from its rest drape on the next step.
func restart() -> void:
	_started = false
	configure_native()


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
	_skeleton.set_bone_pose(_first_column_bone + k * 2 + joint, Transform3D(basis, top - basis * rest_top))

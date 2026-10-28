class_name HairHelmetFit
extends RefCounted

# Keeps a scalp shell (SkaterHairMesh) under the helmet: inside the shell and the
# face gear wherever they cover it, hung and kicked out below the rim, and with
# no face of it cutting through the shell between corners that are each inside.
# Every point is helmet-local, `shell` is SkaterMeshBuilder.helmet_shell_triangles.

# How far inside the helmet shell and the face gear the scalp keeps.
const _GAP_M: float = 0.002
# Between these azimuths from dead back (degrees) the hang gives way: in front
# of the ear hair lies on the cheek.
const _HANG_FADE_DEG := Vector2(80.0, 100.0)
# Hair coming out from under the helmet rim kicks out no faster than this (m out
# per m below the rim), so the kick grows from the rim instead of starting there.
const _RIM_SPRING: float = 1.5
# How far each pass draws a crossing edge's ends back toward the surface under
# them (the share they keep), and how many passes it may take.
const _CLEAR_STEP: float = 0.8
const _CLEAR_PASSES: int = 16
# How far round from a column (degrees) the faces it is checked against reach:
# past its neighbour columns, and past a shell face's width.
const _CLEAR_REACH_DEG: float = 40.0


# How far `at` may stand off along `dir` and stay inside the helmet shell and the
# face gear; INF where neither is over it.
static func room(shell: PackedVector3Array, at: Vector3, dir: Vector3) -> float:
	return minf(_shell_room(shell, at, dir), SkaterMeshBuilder.face_gear_room(at, dir)) - _GAP_M


# One column of a scalp, crown down, hung and then kicked out. Each point is
# held out from the head's axis to no less than the point above it less `hang`
# per metre fallen, then pushed further out by `kick(y)` — the kick is the
# hair's own, so it is measured from where the hair hangs, not from the skin —
# as far as the rim has let it. Neither carries it past the shell or the face
# gear.
static func drape(strip: PackedVector3Array, hang: float, kick: Callable,
		shell: PackedVector3Array) -> PackedVector3Array:
	var centre := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var last: Vector3 = strip[strip.size() - 1] - centre
	var held: float = smoothstep(_HANG_FADE_DEG.y, _HANG_FADE_DEG.x,
			rad_to_deg(absf(atan2(last.x, last.z))))
	if hang > 0.0 and held > 0.0:
		var rate: float = hang / held
		for i: int in range(1, strip.size()):
			var above: Vector3 = strip[i - 1] - centre
			var p: Vector3 = strip[i] - centre
			var floor_m: float = Vector2(above.x, above.z).length() - rate * (above.y - p.y)
			strip[i] = _held_out(strip[i], floor_m - Vector2(p.x, p.z).length(), shell)
	for i: int in strip.size():
		var p: Vector3 = strip[i]
		var below_rim: float = SkaterMeshBuilder.helmet_rim_y(atan2(p.x, p.z)) - p.y
		strip[i] = _held_out(p, minf(kick.call(p.y), below_rim * _RIM_SPRING), shell)
	return strip


# Every corner inside the shell does not keep a face inside it: one tucked under
# the rim and the next flipped out below it span the shell's lowest band. Each
# grid edge a triangle is drawn along (down a column, across a row, and the
# quad's diagonal) that crosses a face of the shell has both its ends drawn
# back toward the surface under them (`bare`) until none does. A column is
# checked only against the faces near its azimuth, and an edge only if an end
# of it is outside one of their planes: two ends inside them all bound an edge
# that is.
static func clear(grid: Array[PackedVector3Array], bare: Array[PackedVector3Array],
		shell: PackedVector3Array) -> void:
	var near: Array[PackedInt32Array] = []
	var outside: Array[PackedByteArray] = []
	for k: int in grid.size():
		var column: PackedVector3Array = bare[k]
		var foot: Vector3 = column[column.size() - 1]
		near.append(_faces_near(shell, atan2(foot.x, foot.z)))
		var flags := PackedByteArray()
		for p: Vector3 in grid[k]:
			flags.append(1 if _outside_any(shell, near[k], p) else 0)
		outside.append(flags)
	for _pass: int in _CLEAR_PASSES:
		var moved: bool = false
		for k: int in grid.size():
			for i: int in grid[k].size():
				var down: bool = i + 1 < grid[k].size()
				var across: bool = k + 1 < grid.size()
				if down:
					moved = _clear_edge(grid, bare, shell, near, outside, k, i, k, i + 1) or moved
				if across:
					moved = _clear_edge(grid, bare, shell, near, outside, k, i, k + 1, i) or moved
				if down and across:
					moved = _clear_edge(grid, bare, shell, near, outside, k, i, k + 1, i + 1) \
							or moved
		if not moved:
			return


static func _clear_edge(grid: Array[PackedVector3Array], bare: Array[PackedVector3Array],
		shell: PackedVector3Array, near: Array[PackedInt32Array],
		outside: Array[PackedByteArray], ka: int, ia: int, kb: int, ib: int) -> bool:
	if outside[ka][ia] == 0 and outside[kb][ib] == 0:
		return false
	var a: Vector3 = grid[ka][ia]
	var b: Vector3 = grid[kb][ib]
	var crosses: bool = false
	for t: int in near[ka]:
		if Geometry3D.segment_intersects_triangle(a, b, shell[t], shell[t + 1],
				shell[t + 2]) != null:
			crosses = true
			break
	if not crosses:
		return false
	for end: Vector2i in [Vector2i(ka, ia), Vector2i(kb, ib)]:
		var column: PackedVector3Array = grid[end.x]
		column[end.y] = bare[end.x][end.y].lerp(column[end.y], _CLEAR_STEP)
		grid[end.x] = column
		var flags: PackedByteArray = outside[end.x]
		flags[end.y] = 1 if _outside_any(shell, near[end.x], column[end.y]) else 0
		outside[end.x] = flags
	return true


# The shell's faces (as the index of each's first corner) with a corner within
# _CLEAR_REACH_DEG of azimuth `theta` about the helmet's axis.
static func _faces_near(shell: PackedVector3Array, theta: float) -> PackedInt32Array:
	var reach: float = deg_to_rad(_CLEAR_REACH_DEG)
	var out := PackedInt32Array()
	for t: int in range(0, shell.size(), 3):
		for c: int in 3:
			var p: Vector3 = shell[t + c]
			if Vector2(p.x, p.z).length_squared() > 1e-8 \
					and absf(wrapf(atan2(p.x, p.z) - theta, -PI, PI)) < reach:
				out.append(t)
				break
	return out


# Whether `p` is on the outer side of the plane of any of the `faces`.
static func _outside_any(shell: PackedVector3Array, faces: PackedInt32Array, p: Vector3) -> bool:
	for t: int in faces:
		var n: Vector3 = (shell[t + 1] - shell[t]).cross(shell[t + 2] - shell[t])
		if n.dot(shell[t]) < 0.0:
			n = -n
		if n.dot(p - shell[t]) > 0.0:
			return true
	return false


# `p` moved `by` metres straight out from the head's axis, no further than the
# shell and the face gear allow; unmoved for `by` <= 0.
static func _held_out(p: Vector3, by: float, shell: PackedVector3Array) -> Vector3:
	var across := Vector3(p.x, 0.0, p.z + SkaterMeshBuilder.HEAD_FORWARD_M)
	if by <= 0.0 or across.length_squared() < 1e-12:
		return p
	var out: Vector3 = across.normalized()
	return p + out * clampf(by, 0.0, room(shell, p, out))


# Distance along `dir` from `at` to the helmet shell, INF where it misses.
static func _shell_room(shell: PackedVector3Array, at: Vector3, dir: Vector3) -> float:
	var best: float = INF
	for i: int in range(0, shell.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(at, dir,
				shell[i], shell[i + 1], shell[i + 2])
		if hit != null:
			best = minf(best, ((hit as Vector3) - at).length())
	return best

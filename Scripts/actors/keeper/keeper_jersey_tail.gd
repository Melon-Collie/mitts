class_name KeeperJerseyTail
extends MeshInstance3D

# The jersey's tail, untucked: a front panel and a back panel of cloth below the
# chest protector, open at the sides, each hanging from the protector's hem
# and resting on what is under it. The top of a panel is the protector's hem
# wherever the trunk put it; the panel hangs from there row by row, each row
# its length of cloth below the last and lifted out of the pants and the thigh
# guards to a cloth's thickness off them, so it runs down over the belly, the
# seat and, in a deep stance, the tops of the thighs rather than cutting
# through them. Drawn only: the pants under it are the save.

# How much cloth each panel hangs below the protector: an untucked goalie
# jersey covers most of his pants, to the crotch in front and the lower seat
# behind.
const FRONT_LENGTH_M: float = 0.18
const BACK_LENGTH_M: float = 0.20
# Each panel's half arc round him, from straight ahead or straight behind.
const PANEL_HALF_ARC_RAD: float = deg_to_rad(68.0)
# How far the cloth stands off what it lies on.
const CLOTH_M: float = 0.012
const _COLUMNS: int = 8
const _ROWS: int = 5
# The rounded-box sections the cloth is kept outside: a superellipse of this
# order sits on an octagon's flats and just over its cut corners.
const _ROUND: float = 4.0

var _top: PackedVector3Array
var _top_from_collar_m: float
var _mesh := ImmediateMesh.new()
var _material: Material = null
var _pants_h: Vector3
var _thigh_h: Vector3
# Per update: the boxes the cloth drapes over, and the panel being built.
var _pants_xf: Transform3D
var _thigh_xf: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _rows: Array[PackedVector3Array] = []


func _init(material: Material) -> void:
	_material = material
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	_top = KeeperGearMeshes.jersey_hem_ring(h)
	_top_from_collar_m = 2.0 * h.y
	_pants_h = KeeperGear.half_extents(KeeperGear.Part.PANTS)
	_thigh_h = KeeperGear.half_extents(KeeperGear.Part.THIGH_G)
	for r: int in _ROWS:
		var row := PackedVector3Array()
		row.resize(_COLUMNS + 1)
		_rows.append(row)
	mesh = _mesh
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


# How far the hem hangs below the protector, between the front's and the
# back's: the jersey's length is the protector's and this.
static func length_m() -> float:
	return (FRONT_LENGTH_M + BACK_LENGTH_M) * 0.5


func update(skel: KeeperSkeleton) -> void:
	var chest_box: Transform3D = KeeperGear.box(skel, KeeperGear.Part.CHEST)
	_pants_xf = KeeperGear.box(skel, KeeperGear.Part.PANTS)
	_thigh_xf[0] = KeeperGear.box(skel, KeeperGear.Part.THIGH_G)
	_thigh_xf[1] = KeeperGear.box(skel, KeeperGear.Part.THIGH_B)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for panel: int in 2:
		var facing: float = 0.0 if panel == 0 else PI
		var seg: float = (FRONT_LENGTH_M if panel == 0 else BACK_LENGTH_M) / float(_ROWS - 1)
		for c: int in _COLUMNS + 1:
			var angle: float = facing + PANEL_HALF_ARC_RAD * (2.0 * float(c) / float(_COLUMNS) - 1.0)
			var dir := Vector2(sin(angle), -cos(angle))
			# The top rests on what is under it too: with the hips pitched under
			# a leaning trunk the protector's hem can sit inside the pants' front.
			_rows[0][c] = _clear(chest_box * _ring_point(_top, dir))
			for r: int in range(1, _ROWS):
				_rows[r][c] = _hang(_rows[r - 1][c], seg)
		var below: float = length_m()
		_panel(_top_from_collar_m, _top_from_collar_m + below)
	_mesh.surface_end()


# The point where a ray from the ring's centre along `dir` (x, z) leaves the
# convex ring (in its own frame, all at one height).
static func _ring_point(ring: PackedVector3Array, dir: Vector2) -> Vector3:
	var c := Vector3.ZERO
	for p: Vector3 in ring:
		c += p
	c /= float(ring.size())
	var best: float = INF
	for i: int in ring.size():
		var a: Vector3 = ring[i] - c
		var b: Vector3 = ring[(i + 1) % ring.size()] - c
		var e := Vector2(b.x - a.x, b.z - a.z)
		var den: float = dir.x * e.y - dir.y * e.x
		if absf(den) < 1e-9:
			continue
		var t: float = (a.x * e.y - a.z * e.x) / den
		var s: float = (a.x * dir.y - a.z * dir.x) / den
		if t > 0.0 and s >= 0.0 and s <= 1.0:
			best = minf(best, t)
	return c + Vector3(dir.x, 0.0, dir.y) * best


# The point on a piece's section at height `y` (its box frame) along `dir`,
# `off` metres out from its surface.
static func _on_section(sections: Array[Vector3], h: Vector3, y: float, dir: Vector2,
		off: float) -> Vector3:
	var half: Vector2 = KeeperGearMeshes.section_at(sections, h, clampf(y, -h.y, h.y))
	var r: float = pow(pow(absf(dir.x) / half.x, _ROUND) + pow(absf(dir.y) / half.y, _ROUND),
			-1.0 / _ROUND)
	return Vector3(dir.x, y, dir.y) * Vector3(r + off, 1.0, r + off)


# The next row of cloth below `prev`, `seg` of cloth further on: hung straight
# down, rested on what is under it and drawn back to its length, so the cloth
# runs on down over the seat instead of spending its length going round it.
func _hang(prev: Vector3, seg: float) -> Vector3:
	var p: Vector3 = prev + Vector3(0.0, -seg, 0.0)
	for i: int in 3:
		p = _clear(p)
		var d: Vector3 = p - prev
		if d.length() > seg:
			p = prev + d.normalized() * seg
	return _clear(p)


# `p` (keeper space) moved out of the pants and both thigh guards, if it is in
# one, to a cloth's thickness off its surface.
func _clear(p: Vector3) -> Vector3:
	p = _clear_of(p, _pants_xf, KeeperGearMeshes.PANTS_SECTIONS, _pants_h)
	for xf: Transform3D in _thigh_xf:
		p = _clear_of(p, xf, KeeperGearMeshes.THIGH_SECTIONS, _thigh_h)
	return p


static func _clear_of(p: Vector3, xf: Transform3D, sections: Array[Vector3],
		h: Vector3) -> Vector3:
	var local: Vector3 = xf.affine_inverse() * p
	if absf(local.y) > h.y:
		return p
	var flat := Vector2(local.x, local.z)
	if flat.length_squared() < 1e-10:
		return p
	var dir: Vector2 = flat.normalized()
	var surface: Vector3 = _on_section(sections, h, local.y, dir, CLOTH_M)
	if flat.length() >= Vector2(surface.x, surface.z).length():
		return p
	return xf * surface


# The panel between its rows, both faces, each vertex carrying its depth below
# the collar in UV.y, which is what the jersey paint bands it by.
func _panel(top_y: float, hem_y: float) -> void:
	for r: int in _ROWS - 1:
		var a: PackedVector3Array = _rows[r]
		var b: PackedVector3Array = _rows[r + 1]
		var y0: float = lerpf(top_y, hem_y, float(r) / float(_ROWS - 1))
		var y1: float = lerpf(top_y, hem_y, float(r + 1) / float(_ROWS - 1))
		for c: int in _COLUMNS:
			_quad(a[c], a[c + 1], b[c + 1], b[c], y0, y1)


func _quad(p: Vector3, q: Vector3, r: Vector3, s: Vector3, y0: float, y1: float) -> void:
	var n: Vector3 = (q - p).cross(s - p)
	if n.length_squared() < 1e-14:
		n = (r - q).cross(p - q)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	# Godot's front faces wind clockwise seen from outside, against the
	# right-hand cross `n` was taken from.
	for side: float in [1.0, -1.0]:
		var face: Vector3 = n * side
		var tri: Array = [[p, y0], [r, y1], [q, y0], [p, y0], [s, y1], [r, y1]]
		if side < 0.0:
			tri = [[p, y0], [q, y0], [r, y1], [p, y0], [r, y1], [s, y1]]
		for v: Array in tri:
			_mesh.surface_set_normal(face)
			_mesh.surface_set_uv(Vector2(0.0, v[1]))
			_mesh.surface_add_vertex(v[0])

class_name KeeperJerseyTail
extends MeshInstance3D

# The jersey's tail, untucked: the cloth below the chest protector, all the way
# round him, hanging from the protector's hem and resting on what is under it.
# Its top is the protector's hem wherever the trunk put it; it hangs from there
# row by row, each row its length of cloth below the last and lifted out of the
# pants and the thigh guards to a cloth's thickness off them, so it runs down
# over the belly, the hips, the seat and, in a deep stance, the tops of the
# thighs rather than cutting through them. Drawn only: the pants under it are
# the save.

# How much cloth hangs below the protector in front and behind, eased between
# round the sides: an untucked goalie jersey covers most of his pants, to the
# crotch in front and the lower seat behind.
const FRONT_LENGTH_M: float = 0.18
const BACK_LENGTH_M: float = 0.20
# How far the cloth stands off what it lies on.
const CLOTH_M: float = 0.012
# Columns along each of the hem's eight edges.
const _PER_EDGE: int = 6
const _EDGES: int = 8
const _COLUMNS: int = _PER_EDGE * _EDGES
const _ROWS: int = 5
# A quad's two triangles, its corners taken in order round it: wound to face
# along the cross of its first two edges, or against it.
const _WIND_FLAT: PackedInt32Array = [0, 2, 1, 0, 3, 2]
const _WIND_BACK: PackedInt32Array = [0, 1, 2, 0, 2, 3]

# The hem in the chest box's frame, its edges divided into columns, so the tail
# starts on the protector's own edge; and each edge's facet normal above it.
var _top := PackedVector3Array()
var _facet := PackedVector3Array()
var _seg := PackedFloat32Array()
var _top_from_collar_m: float
var _mesh := ImmediateMesh.new()
var _material: Material = null
var _pants_h: Vector3
var _thigh_h: Vector3
# Per update: the boxes the cloth drapes over and their inverses, and the
# cloth being built (the last column repeats the first, closing it round him)
# with its normals.
var _chest_xf: Transform3D
var _pants_xf: Transform3D
var _pants_inv: Transform3D
var _thigh_xf: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _thigh_inv: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _rows: Array[PackedVector3Array] = []
var _normals: Array[PackedVector3Array] = []
var _facet_now := PackedVector3Array()
# One quad of it as it is emitted: corners, normals, depths below the collar.
var _qp := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _qn := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _qd := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _init(material: Material) -> void:
	_material = material
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	var hem: PackedVector3Array = KeeperGearMeshes.jersey_section(h, 0)
	var above: PackedVector3Array = KeeperGearMeshes.jersey_section(h, 1)
	for e: int in _EDGES:
		var a: Vector3 = hem[e]
		var b: Vector3 = hem[(e + 1) % _EDGES]
		var n: Vector3 = (b - a).cross(above[e] - a).normalized()
		var mid: Vector3 = (a + b) * 0.5
		if n.dot(Vector3(mid.x, 0.0, mid.z)) < 0.0:
			n = -n
		_facet.append(n)
		for k: int in _PER_EDGE:
			var p: Vector3 = a.lerp(b, float(k) / float(_PER_EDGE))
			_top.append(p)
			# Front (−Z) to back, eased round the sides.
			var back: float = 0.5 - 0.5 * cos(atan2(p.x, -p.z))
			_seg.append(lerpf(FRONT_LENGTH_M, BACK_LENGTH_M, back) / float(_ROWS - 1))
	_top_from_collar_m = 2.0 * h.y
	_pants_h = KeeperGear.half_extents(KeeperGear.Part.PANTS)
	_thigh_h = KeeperGear.half_extents(KeeperGear.Part.THIGH_G)
	for r: int in _ROWS:
		var row := PackedVector3Array()
		row.resize(_COLUMNS + 1)
		_rows.append(row)
		_normals.append(row.duplicate())
	_facet_now.resize(_EDGES)
	mesh = _mesh
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


# How far the hem hangs below the protector, between the front's and the
# back's: the jersey's length is the protector's and this. The kit's bands are
# laid at the same share of the way down all round, so they follow the hem.
static func length_m() -> float:
	return (FRONT_LENGTH_M + BACK_LENGTH_M) * 0.5


func update(skel: KeeperSkeleton) -> void:
	var chest_box: Transform3D = KeeperGear.box(skel, KeeperGear.Part.CHEST)
	var pants: Transform3D = KeeperGear.box(skel, KeeperGear.Part.PANTS)
	var thigh_g: Transform3D = KeeperGear.box(skel, KeeperGear.Part.THIGH_G)
	var thigh_b: Transform3D = KeeperGear.box(skel, KeeperGear.Part.THIGH_B)
	# Hung on what it hangs from as it already is: nothing to redo.
	if chest_box == _chest_xf and pants == _pants_xf and thigh_g == _thigh_xf[0] and thigh_b == _thigh_xf[1] \
			and _mesh.get_surface_count() > 0:
		return
	_chest_xf = chest_box
	_pants_xf = pants
	_thigh_xf[0] = thigh_g
	_thigh_xf[1] = thigh_b
	_pants_inv = _pants_xf.affine_inverse()
	for i: int in 2:
		_thigh_inv[i] = _thigh_xf[i].affine_inverse()
	for e: int in _EDGES:
		_facet_now[e] = (chest_box.basis * _facet[e]).normalized()
	for c: int in _COLUMNS:
		# The top is the protector's hem itself, so nothing shows where they
		# meet; the rows below rest on what is under them.
		_rows[0][c] = chest_box * _top[c]
		for r: int in range(1, _ROWS):
			_rows[r][c] = _hang(_rows[r - 1][c], _seg[c])
	for r: int in _ROWS:
		_rows[r][_COLUMNS] = _rows[r][0]
	_smooth_normals(chest_box)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	_cloth(_top_from_collar_m, _top_from_collar_m + length_m())
	_mesh.surface_end()


# The cloth is shaded smooth, from its neighbours, away from the trunk's axis.
func _smooth_normals(chest_box: Transform3D) -> void:
	var axis: Vector3 = chest_box.basis.y.normalized()
	for r: int in _ROWS:
		var above: PackedVector3Array = _rows[maxi(r - 1, 0)]
		var below: PackedVector3Array = _rows[mini(r + 1, _ROWS - 1)]
		for c: int in _COLUMNS:
			var p: Vector3 = _rows[r][c]
			var round_dir: Vector3 = _rows[r][c + 1] - _rows[r][(c + _COLUMNS - 1) % _COLUMNS]
			var n: Vector3 = round_dir.cross(below[c] - above[c])
			var out: Vector3 = p - chest_box.origin
			out -= axis * out.dot(axis)
			if n.dot(out) < 0.0:
				n = -n
			_normals[r][c] = n.normalized()
		_normals[r][_COLUMNS] = _normals[r][0]


# The point on a section (half width, front depth, back depth) at height `y`
# of its box frame, along `dir`, `off` metres out from its surface.
static func _on_section(sec: Vector3, y: float, dir: Vector2, off: float) -> Vector3:
	var depth: float = sec.y if dir.y < 0.0 else sec.z
	var order: float = KeeperGearMeshes.PANTS_ROUNDNESS
	var r: float = pow(pow(absf(dir.x) / sec.x, order) + pow(absf(dir.y) / depth, order),
			-1.0 / order)
	return Vector3(dir.x, y, dir.y) * Vector3(r + off, 1.0, r + off)


# The next row of cloth below `prev`, `seg` of cloth further on: hung straight
# down, rested on what is under it and drawn back to its length, so the cloth
# runs on down over the seat instead of spending its length going round it.
func _hang(prev: Vector3, seg: float) -> Vector3:
	var p: Vector3 = prev + Vector3(0.0, -seg, 0.0)
	for i: int in 3:
		var cleared: Vector3 = _clear(p)
		# Already clear, and within its length: every pass after is this one.
		if cleared == p:
			return p
		p = cleared
		var d: Vector3 = p - prev
		if d.length() > seg:
			p = prev + d.normalized() * seg
	return _clear(p)


# `p` (keeper space) moved out of the pants and both thigh guards, if it is in
# one, to a cloth's thickness off its surface.
func _clear(p: Vector3) -> Vector3:
	p = _clear_of(p, _pants_xf, _pants_inv, KeeperGearMeshes.PANTS_SECTIONS, _pants_h)
	for i: int in 2:
		p = _clear_of(p, _thigh_xf[i], _thigh_inv[i], KeeperGearMeshes.THIGH_SECTIONS, _thigh_h)
	return p


static func _clear_of(p: Vector3, xf: Transform3D, inv: Transform3D, sections: Array[Vector4],
		h: Vector3) -> Vector3:
	var local: Vector3 = inv * p
	# Outside the box with a cloth's room round it is outside every section in it.
	if absf(local.y) > h.y or absf(local.x) > h.x + CLOTH_M or absf(local.z) > h.z + CLOTH_M:
		return p
	var length: float = Vector2(local.x, local.z).length()
	if length < 1e-5:
		return p
	var sec: Vector3 = KeeperGearMeshes.section_at(sections, h, local.y)
	# Clear of the surface stood off by a cloth's thickness exactly when the
	# point drawn in by that thickness is outside the section, which asks no
	# root of the section's order (its cube, PANTS_ROUNDNESS).
	var share: float = maxf(length - CLOTH_M, 0.0) / length
	var across: float = absf(local.x) * share / sec.x
	var deep: float = absf(local.z) * share / (sec.y if local.z < 0.0 else sec.z)
	if across * across * across + deep * deep * deep >= 1.0:
		return p
	return xf * _on_section(sec, local.y, Vector2(local.x, local.z) / length, CLOTH_M)


# The cloth between its rows, both faces, each vertex carrying its depth below
# the collar in UV.y, which is what the jersey paint bands it by. Along its top
# it takes the protector's facet normals, so the light runs on across the hem.
func _cloth(top_y: float, hem_y: float) -> void:
	for r: int in _ROWS - 1:
		var y0: float = lerpf(top_y, hem_y, float(r) / float(_ROWS - 1))
		var y1: float = lerpf(top_y, hem_y, float(r + 1) / float(_ROWS - 1))
		_qd[0] = y0
		_qd[1] = y0
		_qd[2] = y1
		_qd[3] = y1
		for c: int in _COLUMNS:
			_qp[0] = _rows[r][c]
			_qp[1] = _rows[r][c + 1]
			_qp[2] = _rows[r + 1][c + 1]
			_qp[3] = _rows[r + 1][c]
			_qn[0] = _normals[r][c] if r > 0 else _facet_now[floori(float(c) / _PER_EDGE)]
			_qn[1] = _normals[r][c + 1] if r > 0 else _qn[0]
			_qn[2] = _normals[r + 1][c + 1]
			_qn[3] = _normals[r + 1][c]
			_quad()


func _quad() -> void:
	var flat: Vector3 = (_qp[1] - _qp[0]).cross(_qp[3] - _qp[0])
	if flat.length_squared() < 1e-14:
		flat = (_qp[2] - _qp[1]).cross(_qp[0] - _qp[1])
	if flat.length_squared() < 1e-14:
		return
	# Godot's front faces wind clockwise seen from outside, against the
	# right-hand cross `flat` was taken from. Both faces are drawn, the inner
	# one with the normals turned in.
	var flat_out: bool = flat.dot(_qn[0] + _qn[1] + _qn[2] + _qn[3]) > 0.0
	for side: int in 2:
		var turn: float = 1.0 if side == 0 else -1.0
		var order: PackedInt32Array = _WIND_FLAT if (side == 0) == flat_out else _WIND_BACK
		for i: int in order:
			_mesh.surface_set_normal(_qn[i] * turn)
			_mesh.surface_set_uv(Vector2(0.0, _qd[i]))
			_mesh.surface_add_vertex(_qp[i])

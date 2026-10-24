class_name KeeperJerseyTail
extends MeshInstance3D

# The jersey's tail, untucked: the cloth below the chest protector, all the way
# round him, hanging from the protector's hem over the pants and the thigh
# guards. It is cloth (HemFlaps, as the skater's tail is): a flap down each
# column of the hem, two segments, swung by gravity less his acceleration and
# pushed out of the pants and thigh guards (KeeperTailColliders). The mesh is
# skinned once onto his body rig (KeeperBodyRig): its top row on the chest
# protector's own bone, so it starts on the protector's hem, and each column
# below on its own flap's segments. A column blended between two flaps would
# be a chord between two cloths the solver keeps clear, which a thigh or the
# seat pushes straight through. Drawn only: the pants under it are the save.
#
# Its rest is how it settles on him in the ready stance, from a drape hung from
# the hem row by row, each row its length of cloth below the last and lifted
# out of the pants and the thigh guards to a cloth's thickness off them, so it
# runs down over the belly, the hips and the seat rather than cutting through
# them. That rest is held in the protector's frame, the frame the flaps turn
# with.

# How much cloth hangs below the protector in front and behind, eased between
# round the sides: an untucked goalie jersey covers most of his pants, to the
# crotch in front and the lower seat behind.
const FRONT_LENGTH_M: float = 0.18
const BACK_LENGTH_M: float = 0.20
# How far the cloth stands off what it lies on.
const CLOTH_M: float = 0.012
# Columns along each of the hem's eight edges, a flap each.
const _PER_EDGE: int = 6
const _EDGES: int = 8
const FLAPS: int = _PER_EDGE * _EDGES
# The rows from the hem down: the top, the upper segment's middle, the bend,
# the lower segment's middle, the hem.
const _ROWS: int = 5
const _BEND_ROW: int = 2
# A quad's two triangles, its corners taken in order round it: wound to face
# along the cross of its first two edges, or against it.
const _WIND_FLAT: PackedInt32Array = [0, 2, 1, 0, 3, 2]
const _WIND_BACK: PackedInt32Array = [0, 1, 2, 0, 2, 3]
# Steps the cloth is settled over to find its rest: long past its swing's.
const SETTLE_STEPS: int = 90
# Round him in any stance: the skinned mesh is culled by this, not by its rest.
const _BOUNDS := AABB(Vector3(-1.6, -0.1, -1.6), Vector3(3.2, 2.4, 3.2))

var flaps := HemFlaps.new()

# The hem in the chest box's frame, its edges divided into columns, so the tail
# starts on the protector's own edge; and each edge's facet normal above it.
var _top := PackedVector3Array()
var _facet := PackedVector3Array()
var _seg := PackedFloat32Array()
var _top_from_collar_m: float
var _material: Material = null
var _colliders := KeeperTailColliders.new()
# The rest drape, chest frame (the last column repeats the first, closing it
# round him), and its normals.
var _rows: Array[PackedVector3Array] = []
var _normals: Array[PackedVector3Array] = []


func _init(material: Material) -> void:
	name = "JerseyTail"
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
	for r: int in _ROWS:
		var row := PackedVector3Array()
		row.resize(FLAPS + 1)
		_rows.append(row)
		_normals.append(row.duplicate())
	flaps.columns = FLAPS
	flaps.margin_m = CLOTH_M
	flaps.hips_share.resize(FLAPS)
	flaps.tuck_share.resize(FLAPS)
	custom_aabb = _BOUNDS


# How far the hem hangs below the protector, between the front's and the
# back's: the jersey's length is the protector's and this. The kit's bands are
# laid at the same share of the way down all round, so they follow the hem.
static func length_m() -> float:
	return (FRONT_LENGTH_M + BACK_LENGTH_M) * 0.5


# The first of the flaps' bones in his body rig: after a bone per gear piece.
static func first_flap_bone() -> int:
	return KeeperGear.PART_COUNT


# Hangs it on `rig` (its child) as a left- or right-catcher wears it: the flap
# bones added if the rig has none yet, the rest drape hung and settled, the
# mesh skinned, and the cloth started over from its rest.
func build(rig: KeeperBodyRig, mirrored: bool) -> void:
	if rig.get_bone_count() == first_flap_bone():
		for k: int in FLAPS:
			for joint: int in 2:
				rig.add_bone("TAIL_%d_%d" % [k, joint])
	var chest: Transform3D = _hang_at_ready(mirrored, rig)
	flaps.bind(rig, KeeperGear.Part.CHEST, KeeperGear.Part.CHEST, first_flap_bone(), _colliders)
	_settle(rig, chest)
	_smooth_normals()
	_build_mesh()
	skeleton = NodePath("..")


# One frame of the cloth: `down` is gravity's way and `acceleration` his own,
# both in his skeleton's space; its bones are written if `write`.
func step(delta: float, down: Vector3, acceleration: Vector3, write: bool) -> void:
	flaps.step(delta, down * flaps.gravity_m_s2 - acceleration, write)


# The drape on him standing ready, hung row by row, in the protector's frame;
# `rig`'s gear bones set on him standing so. His protector's box, so.
func _hang_at_ready(mirrored: bool, rig: KeeperBodyRig) -> Transform3D:
	var skel := KeeperSkeleton.new()
	skel.mirrored = mirrored
	var ready_pose := KeeperPose.new()
	KeeperPoses.ready(ready_pose)
	skel.pose(ready_pose)
	rig.update(skel)
	for i: int in KeeperTailColliders.PARTS.size():
		_colliders.place(i, KeeperGear.box(skel, KeeperTailColliders.PARTS[i]))
	var chest: Transform3D = KeeperGear.box(skel, KeeperGear.Part.CHEST)
	var to_chest: Transform3D = chest.affine_inverse()
	flaps.authored_up = (to_chest.basis * Vector3.UP).normalized()
	for c: int in FLAPS:
		var p: Vector3 = chest * _top[c]
		_rows[0][c] = _top[c]
		for r: int in range(1, _ROWS):
			p = _hang(p, _seg[c])
			_rows[r][c] = to_chest * p
	for r: int in _ROWS:
		_rows[r][FLAPS] = _rows[r][0]
	return chest


# The cloth let settle on him standing still from the hung drape, and that
# made its rest: the flaps keep their segments' chords clear of what they lie
# on, which the drape hung row by row over the seat does not, so only a
# settled drape is one the cloth rests in. Every row below the top is carried
# to where the settled bones put it, as the mesh will be.
func _settle(rig: KeeperBodyRig, chest: Transform3D) -> void:
	_take_flap_rest()
	flaps.restart()
	var down: Vector3 = Vector3.DOWN * flaps.gravity_m_s2
	for i: int in SETTLE_STEPS:
		flaps.step(1.0 / 60.0, down, i == SETTLE_STEPS - 1)
	var to_chest: Transform3D = chest.affine_inverse()
	for r: int in range(1, _ROWS):
		for c: int in FLAPS:
			var bone: Transform3D = rig.get_bone_global_pose(first_flap_bone() + 2 * c + segment_of(r))
			_rows[r][c] = to_chest * (bone * _rows[r][c])
		_rows[r][FLAPS] = _rows[r][0]
	_take_flap_rest()
	flaps.restart()


func _take_flap_rest() -> void:
	flaps.rest.clear()
	for row: int in [0, 1, _BEND_ROW, _ROWS - 1]:
		var station := PackedVector3Array()
		for k: int in FLAPS:
			station.append(_rows[row][k])
		flaps.rest.append(station)


# Which of a flap's segments a row rides.
static func segment_of(row: int) -> int:
	return 0 if row < _BEND_ROW else 1


# The next row of cloth below `prev`, `seg` of cloth further on: hung straight
# down, rested on what is under it and drawn back to its length, so the cloth
# runs on down over the seat instead of spending its length going round it.
func _hang(prev: Vector3, seg: float) -> Vector3:
	var p: Vector3 = prev + Vector3(0.0, -seg, 0.0)
	for i: int in 3:
		p = _colliders.push_out(p, CLOTH_M)
		var d: Vector3 = p - prev
		if d.length() > seg:
			p = prev + d.normalized() * seg
	return _colliders.push_out(p, CLOTH_M)


# The cloth is shaded smooth, from its neighbours, away from the trunk's axis.
func _smooth_normals() -> void:
	for r: int in _ROWS:
		var above: PackedVector3Array = _rows[maxi(r - 1, 0)]
		var below: PackedVector3Array = _rows[mini(r + 1, _ROWS - 1)]
		for c: int in FLAPS:
			var p: Vector3 = _rows[r][c]
			var round_dir: Vector3 = _rows[r][c + 1] - _rows[r][(c + FLAPS - 1) % FLAPS]
			var n: Vector3 = round_dir.cross(below[c] - above[c])
			if n.dot(Vector3(p.x, 0.0, p.z)) < 0.0:
				n = -n
			_normals[r][c] = n.normalized()
		_normals[r][FLAPS] = _normals[r][0]


# The cloth between its rows, both faces, each vertex carrying its depth below
# the collar in UV.y, which is what the jersey paint bands it by, and its rest
# place and normal in CUSTOM0 and CUSTOM1, which is what it paints by
# otherwise. Along its top it takes the protector's facet normals, so the light
# runs on across the hem.
func _build_mesh() -> void:
	var b := _Built.new()
	var hem_y: float = _top_from_collar_m + length_m()
	for r: int in _ROWS - 1:
		var y0: float = lerpf(_top_from_collar_m, hem_y, float(r) / float(_ROWS - 1))
		var y1: float = lerpf(_top_from_collar_m, hem_y, float(r + 1) / float(_ROWS - 1))
		for c: int in FLAPS:
			var corners: Array[Vector2i] = [Vector2i(c, r), Vector2i(c + 1, r), Vector2i(c + 1, r + 1),
					Vector2i(c, r + 1)]
			var depths: Array[float] = [y0, y0, y1, y1]
			var facet: Vector3 = _facet[floori(float(c) / _PER_EDGE)]
			var qp: Array[Vector3] = []
			var qn: Array[Vector3] = []
			for corner: Vector2i in corners:
				qp.append(_rows[corner.y][corner.x])
				qn.append(facet if corner.y == 0 else _normals[corner.y][corner.x])
			var flat: Vector3 = (qp[1] - qp[0]).cross(qp[3] - qp[0])
			if flat.length_squared() < 1e-14:
				flat = (qp[2] - qp[1]).cross(qp[0] - qp[1])
			if flat.length_squared() < 1e-14:
				continue
			# Godot's front faces wind clockwise seen from outside, against the
			# right-hand cross `flat` was taken from. Both faces are drawn, the
			# inner one with the normals turned in.
			var flat_out: bool = flat.dot(qn[0] + qn[1] + qn[2] + qn[3]) > 0.0
			for side: int in 2:
				var turn: float = 1.0 if side == 0 else -1.0
				var order: PackedInt32Array = _WIND_FLAT if (side == 0) == flat_out else _WIND_BACK
				for i: int in order:
					b.add(qp[i], qn[i] * turn, depths[i], corners[i])
	mesh = b.commit()
	mesh.surface_set_material(0, _material)
	var s := Skin.new()
	s.add_bind(KeeperGear.Part.CHEST, Transform3D.IDENTITY)
	for bone: int in 2 * FLAPS:
		s.add_bind(first_flap_bone() + bone, Transform3D.IDENTITY)
	skin = s


# The tail's vertices as they are skinned: the top row on the chest
# protector's bind (0), the rows below on their column's flap segment (bind
# 1 + 2·column + segment).
class _Built:
	extends RefCounted

	var _verts := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _uvs := PackedVector2Array()
	var _bones := PackedInt32Array()
	var _weights := PackedFloat32Array()
	var _place := PackedFloat32Array()
	var _facing := PackedFloat32Array()

	func add(p: Vector3, n: Vector3, depth: float, at: Vector2i) -> void:
		_verts.append(p)
		_normals.append(n)
		_uvs.append(Vector2(0.0, depth))
		_place.append_array([p.x, p.y, p.z])
		_facing.append_array([n.x, n.y, n.z])
		if at.y == 0:
			_bones.append_array([0, 0, 0, 0])
			_weights.append_array([1.0, 0.0, 0.0, 0.0])
			return
		_bones.append_array([1 + 2 * (at.x % FLAPS) + KeeperJerseyTail.segment_of(at.y), 0, 0, 0])
		_weights.append_array([1.0, 0.0, 0.0, 0.0])

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_BONES] = _bones
		arrays[Mesh.ARRAY_WEIGHTS] = _weights
		arrays[Mesh.ARRAY_CUSTOM0] = _place
		arrays[Mesh.ARRAY_CUSTOM1] = _facing
		var format: int = (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
		return out

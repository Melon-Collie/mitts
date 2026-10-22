class_name KeeperJerseyTail
extends MeshInstance3D

# The jersey's tail, untucked: the cloth below the chest protector, hanging
# from the jersey's hem ring on the chest down over the pants to a loose hem
# round his hips. It is lofted between the two wherever the pose put them, the
# way the skater's tail blends from the chest onto the hips: the front hangs
# wholly from the hips, where the thighs push it, and the back carries only
# BACK_ON_HIPS of them, riding up with the chest over the seat. Drawn only: the
# pants under it are the save.

# The hem round the hips: its height over the pelvis origin, its half width
# and depth (looser than the pants it hangs over) and its centre's depth.
const HEM_ABOVE_PELVIS_M: float = 0.05
const HEM_HALF := Vector2(0.27, 0.185)
const HEM_CENTER_Z: float = 0.01
const BACK_ON_HIPS: float = 0.4
# Where the protector ends and the tail starts, on the chest bone.
const _CHEST_ABOVE_PELVIS_M: float = KeeperAnatomy.LUMBAR_ABOVE_PELVIS_M \
		+ KeeperAnatomy.CHEST_ABOVE_LUMBAR_M
# The middle section stands out from the straight loft, so the cloth bells over
# the pants' seat rather than cutting through it.
const _BELL: float = 1.04

var _top: PackedVector3Array
var _hem_on_hips: PackedVector3Array
var _hem_on_chest: PackedVector3Array
var _hips_share: PackedFloat32Array
var _top_from_collar_m: float
var _mesh := ImmediateMesh.new()
var _material: Material = null


func _init(material: Material) -> void:
	_material = material
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	_top = KeeperGearMeshes.jersey_hem_ring(h)
	_top_from_collar_m = 2.0 * h.y
	_hem_on_hips = KeeperMeshKit.octagon(HEM_ABOVE_PELVIS_M, HEM_HALF.x, HEM_HALF.y,
			HEM_HALF.x * 0.22, 1.0, 0.0, HEM_CENTER_Z)
	_hem_on_chest = PackedVector3Array()
	_hips_share = PackedFloat32Array()
	for p: Vector3 in _hem_on_hips:
		_hem_on_chest.append(p - Vector3(0.0, _CHEST_ABOVE_PELVIS_M, 0.0))
		var back: float = clampf((p.z - HEM_CENTER_Z) / HEM_HALF.y * 0.5 + 0.5, 0.0, 1.0)
		_hips_share.append(lerpf(1.0, BACK_ON_HIPS, back))
	mesh = _mesh
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


# How far the tail's hem hangs below the collar at rest: its length, with the
# chest's, is the jersey's.
static func length_m() -> float:
	return _CHEST_ABOVE_PELVIS_M + KeeperGear.CHEST_BOTTOM_M - HEM_ABOVE_PELVIS_M


func update(skel: KeeperSkeleton) -> void:
	var chest_box: Transform3D = KeeperGear.box(skel, KeeperGear.Part.CHEST)
	var chest: Transform3D = skel.xf[KeeperSkeleton.Bone.CHEST]
	var pelvis: Transform3D = skel.xf[KeeperSkeleton.Bone.PELVIS]
	var n: int = _top.size()
	var a := PackedVector3Array()
	var c := PackedVector3Array()
	a.resize(n)
	c.resize(n)
	var ca := Vector3.ZERO
	var cc := Vector3.ZERO
	for i: int in n:
		a[i] = chest_box * _top[i]
		c[i] = (chest * _hem_on_chest[i]).lerp(pelvis * _hem_on_hips[i], _hips_share[i])
		ca += a[i]
		cc += c[i]
	ca /= float(n)
	cc /= float(n)
	var mid_centre: Vector3 = (ca + cc) * 0.5
	var b := PackedVector3Array()
	b.resize(n)
	for i: int in n:
		b[i] = mid_centre + ((a[i] + c[i]) * 0.5 - mid_centre) * _BELL
	var tail: float = length_m()
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	_band(a, b, _top_from_collar_m, _top_from_collar_m + tail * 0.5, ca)
	_band(b, c, _top_from_collar_m + tail * 0.5, _top_from_collar_m + tail, cc)
	_mesh.surface_end()


# The loft between two rings, each vertex carrying its depth below the collar
# in UV.y, which is what the jersey paint bands it by.
func _band(a: PackedVector3Array, b: PackedVector3Array, ya: float, yb: float,
		inside: Vector3) -> void:
	for i: int in a.size():
		var j: int = (i + 1) % a.size()
		_tri(a[i], ya, a[j], ya, b[j], yb, inside)
		_tri(a[i], ya, b[j], yb, b[i], yb, inside)


func _tri(p: Vector3, py: float, q: Vector3, qy: float, r: Vector3, ry: float,
		inside: Vector3) -> void:
	var nrm: Vector3 = (q - p).cross(r - p)
	if nrm.length_squared() < 1e-14:
		return
	nrm = nrm.normalized()
	if nrm.dot((p + q + r) / 3.0 - inside) < 0.0:
		nrm = -nrm
		var t: Vector3 = q
		q = r
		r = t
		var ty: float = qy
		qy = ry
		ry = ty
	for v: Array in [[p, py], [r, ry], [q, qy]]:
		_mesh.surface_set_normal(nrm)
		_mesh.surface_set_uv(Vector2(0.0, v[1]))
		_mesh.surface_add_vertex(v[0])

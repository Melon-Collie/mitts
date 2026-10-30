class_name SkaterRigidParts
extends RefCounted

# The skater's rigid parts, beside the skin (SkaterConnectedMesh): the head, the
# gloves, the cuffs and the skates, as two meshes the body joins to the skin
# (SkaterBodyMesh). Every part is one zone of its mesh (BodyZoneMesh), zone = UPPER_ZONE_BASE +
# SkaterMeshBuilder.UpperSurface or SkaterMeshBuilder.LegSurface, rigid to its
# bone. The helmet's shell is drawn with a hockey helmet's ridge down its crown
# and a rib either side of it; the hair and face gear fitted under the plain
# shell still fit, as the crest only ever raises it and stops above the brow
# the face gear hangs from.

const _UpperSurface = SkaterMeshBuilder.UpperSurface
const _UpperBone = SkaterMeshBuilder.UpperBone
const _LegSurface = SkaterMeshBuilder.LegSurface
const _LegBone = SkaterMeshBuilder.LegBone
const _HELMET_LON: int = 24
const _HELMET_LAT: int = 8
# A hockey helmet's shape on the shell, every term only raising it (m proud):
# a ridge down the crown's centre line and a rib either side of it (half
# widths, and the ribs' place, as fractions of the radius off the centre
# plane), running out down the back toward the nape and at the front just
# above the brow; a brow ledge flaring the front rim, which the visor tucks
# under; the step across the back where the rear shell laps the front one;
# and the whole shell drawn out front to back, as a helmet is longer than wide.
const _RIDGE_M: float = 0.010
const _RIDGE_HALF_WIDTH: float = 0.22
const _RIB_M: float = 0.007
const _RIB_ACROSS: float = 0.55
const _RIB_HALF_WIDTH: float = 0.08
const _CREST_BACK_FADE := Vector2(-0.35, 0.1)
const _CREST_FRONT_FADE := Vector2(0.35, 0.55)
const _BROW_M: float = 0.007
const _BROW_FADE := Vector2(0.5, 0.31)   # height on the shell: none, full (the rim)
const _STEP_M: float = 0.008
const _STEP_HEIGHT: float = 0.05
const _STEP_HALF_HEIGHT: float = 0.09
const _LENGTH: float = 1.07

static var _cache: Dictionary = {}


static func upper_body_mesh() -> ArrayMesh:
	return _shared("upper", func() -> ArrayMesh:
		var b := BodyZoneMesh.new()
		var fist: ArrayMesh = SkaterMeshBuilder.shared_glove_fist()
		var cuff: ArrayMesh = SkaterMeshBuilder.shared_cuff()
		for top: bool in [true, false]:
			var hand: int = _UpperBone.TOP_HAND if top else _UpperBone.BOTTOM_HAND
			_add(b, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_BACK),
					_UpperSurface.TOP_HAND if top else _UpperSurface.BOTTOM_HAND, hand)
			_add(b, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_FINGERS),
					_UpperSurface.TOP_FINGERS if top else _UpperSurface.BOTTOM_FINGERS, hand)
			_add(b, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_THUMB),
					_UpperSurface.TOP_HAND if top else _UpperSurface.BOTTOM_HAND, hand)
			_add(b, cuff.surface_get_arrays(0),
					_UpperSurface.TOP_CUFF if top else _UpperSurface.BOTTOM_CUFF,
					_UpperBone.TOP_CUFF if top else _UpperBone.BOTTOM_CUFF)
		_add(b, SkaterMeshBuilder.shared_helmet_assembly().surface_get_arrays(
				SkaterMeshBuilder.HELMET_SURF_SKIN), _UpperSurface.HELMET_SKIN, _UpperBone.HELMET)
		_add(b, _crested(SkaterMeshBuilder.shared_helmet_shell(_HELMET_LON, _HELMET_LAT)),
				_UpperSurface.HELMET_SHELL, _UpperBone.HELMET)
		return b.commit())


static func leg_body_mesh() -> ArrayMesh:
	return _shared("legs", func() -> ArrayMesh:
		var b := BodyZoneMesh.new()
		var skate: ArrayMesh = SkaterMeshBuilder.shared_skate_assembly()
		var boot: ArrayMesh = SkaterMeshBuilder.shared_boot_assembly()
		for side: int in 2:
			var first: int = _LegSurface.SKATE_L_COLLAR if side == 0 else _LegSurface.SKATE_R_COLLAR
			var shin: int = _LegBone.SHIN_L if side == 0 else _LegBone.SHIN_R
			# The collar and its stripe ride the SKATE bone, the boot's five
			# parts the FOOT bone, in LegSurface order from the collar on.
			for s: int in 2:
				b.add(skate.surface_get_arrays(s), first + s, shin + 2)
			for s: int in 5:
				b.add(boot.surface_get_arrays(s), first + 2 + s, shin + 3)
		return b.commit())


# The zones whose parts ship a default finish (the skin, the steel runners, the
# laces, the skate's stripe), seeded into a body's paint before any kit lands.
static func seed_paint(paint: BodyZonePaint) -> void:
	var skin: Material = SkaterMeshBuilder.shared_helmet_assembly().surface_get_material(
			SkaterMeshBuilder.HELMET_SURF_SKIN)
	paint.seed_zone(SkaterMeshBuilder.UPPER_ZONE_BASE + _UpperSurface.HELMET_SKIN, skin)
	var skate: ArrayMesh = SkaterMeshBuilder.shared_skate_assembly()
	var boot: ArrayMesh = SkaterMeshBuilder.shared_boot_assembly()
	for side: int in 2:
		var first: int = _LegSurface.SKATE_L_COLLAR if side == 0 else _LegSurface.SKATE_R_COLLAR
		paint.seed_zone(first + SkaterMeshBuilder.SKATE_SURF_STRIPE,
				skate.surface_get_material(SkaterMeshBuilder.SKATE_SURF_STRIPE))
		for s: int in [SkaterMeshBuilder.BOOT_SURF_RUNNER, SkaterMeshBuilder.BOOT_SURF_LACES]:
			paint.seed_zone(first + 2 + s, boot.surface_get_material(s))


static func _add(b: BodyZoneMesh, arrays: Array, surface: int, bone: int) -> void:
	b.add(arrays, SkaterMeshBuilder.UPPER_ZONE_BASE + surface, bone)


static func _shared(key: String, builder: Callable) -> ArrayMesh:
	var built: ArrayMesh = _cache.get(key)
	if built == null:
		built = builder.call()
		_cache[key] = built
	return built


# The shell's arrays with its ridge and ribs raised, each face's normal its
# own facing again.
static func _crested(shell: ArrayMesh) -> Array:
	var arrays: Array = shell.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in verts.size():
		var d: Vector3 = verts[i].normalized()
		var front: float = smoothstep(-0.2, 0.2, -d.z)
		var fade: float = lerpf(smoothstep(_CREST_BACK_FADE.x, _CREST_BACK_FADE.y, d.y),
				smoothstep(_CREST_FRONT_FADE.x, _CREST_FRONT_FADE.y, d.y), front)
		var raise: float = (_RIDGE_M * exp(-(d.x / _RIDGE_HALF_WIDTH) ** 2) \
				+ _RIB_M * exp(-((absf(d.x) - _RIB_ACROSS) / _RIB_HALF_WIDTH) ** 2)) * fade
		raise += _BROW_M * front * smoothstep(_BROW_FADE.x, _BROW_FADE.y, d.y)
		raise += _STEP_M * smoothstep(0.2, 0.5, d.z) \
				* exp(-((d.y - _STEP_HEIGHT) / _STEP_HALF_HEIGHT) ** 2)
		var p: Vector3 = verts[i] + d * raise
		p.z *= _LENGTH
		verts[i] = p
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i: int in verts.size():
			indices.append(i)
	for t: int in range(0, indices.size(), 3):
		var a: Vector3 = verts[indices[t]]
		var n: Vector3 = (verts[indices[t + 2]] - a).cross(verts[indices[t + 1]] - a).normalized()
		for c: int in 3:
			normals[indices[t + c]] = n
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	return arrays

class_name SkaterConnectedRigMeshes
extends RefCounted

# PROTOTYPE: the rig's two meshes as they are drawn beside the connected body
# (SkaterConnectedMesh) — the head, the gloves, the cuffs and the skates, less
# every surface it replaces. Zones keep their numbers, so the paint is the same.
# The helmet's shell is redrawn at a finer facet grid than the rig's, with a
# hockey helmet's ridge down its crown and a rib either side of it. The hair and
# face gear fitted under the rig's still fit: every point of the finer shell
# lies on the same sphere outside the coarser one's chords, and the ridge and
# ribs only ever raise it, and stop above the brow the face gear hangs from.

const _UpperSurface = SkaterMeshBuilder.UpperSurface
const _LegSurface = SkaterMeshBuilder.LegSurface
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

# The replaced surfaces and the shell, which is redrawn finer.
const _REDRAWN_UPPER: Array[int] = [
	_UpperSurface.TOP_UPPER_ARM, _UpperSurface.TOP_FOREARM,
	_UpperSurface.BOTTOM_UPPER_ARM, _UpperSurface.BOTTOM_FOREARM,
	_UpperSurface.TOP_ELBOW, _UpperSurface.BOTTOM_ELBOW,
	_UpperSurface.TORSO, _UpperSurface.SHOULDER_L, _UpperSurface.SHOULDER_R,
	_UpperSurface.PELVIS, _UpperSurface.HELMET_SHELL,
]
const _REPLACED_LEG: Array[int] = [
	_LegSurface.THIGH_L, _LegSurface.KNEE_L, _LegSurface.SOCK_L,
	_LegSurface.THIGH_R, _LegSurface.KNEE_R, _LegSurface.SOCK_R,
]


static func reduced_upper_body_mesh(tuck: int) -> ArrayMesh:
	if not GearModelRegistry.is_valid_tuck(tuck):
		tuck = GearModelRegistry.TUCK_NONE
	return _shared("upper_%d" % tuck, func() -> ArrayMesh:
		var b := _without(SkaterMeshBuilder.shared_upper_skin_mesh(tuck),
				SkaterMeshBuilder.UPPER_ZONE_BASE, _REDRAWN_UPPER)
		b.add(_crested(SkaterMeshBuilder.shared_helmet_shell(_HELMET_LON, _HELMET_LAT)),
				SkaterMeshBuilder.UPPER_ZONE_BASE + _UpperSurface.HELMET_SHELL,
				SkaterMeshBuilder.UpperBone.HELMET)
		return b.commit())


static func reduced_leg_body_mesh() -> ArrayMesh:
	return _shared("legs", func() -> ArrayMesh:
		return _without(SkaterMeshBuilder.shared_leg_skin_mesh(), 0, _REPLACED_LEG).commit())


static func _without(src: ArrayMesh, first_zone: int, dropped: Array[int]) -> BodyZoneMesh:
	var b := BodyZoneMesh.new()
	for s: int in src.get_surface_count():
		if not dropped.has(s):
			b.add(src.surface_get_arrays(s), first_zone + s)
	return b


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

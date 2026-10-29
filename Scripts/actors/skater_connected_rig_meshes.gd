class_name SkaterConnectedRigMeshes
extends RefCounted

# PROTOTYPE: the rig's two meshes as they are drawn beside the connected body
# (SkaterConnectedMesh) — the head, the gloves, the cuffs and the skates, less
# every surface it replaces. Zones keep their numbers, so the paint is the same.
# The helmet's shell is redrawn at a finer facet grid than the rig's; the hair
# and face gear fitted under the rig's still fit, every point of the finer shell
# lying on the same sphere outside the coarser one's chords.

const _UpperSurface = SkaterMeshBuilder.UpperSurface
const _LegSurface = SkaterMeshBuilder.LegSurface
const _HELMET_LON: int = 24
const _HELMET_LAT: int = 8

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
		b.add(SkaterMeshBuilder.shared_helmet_shell(_HELMET_LON, _HELMET_LAT).surface_get_arrays(0),
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

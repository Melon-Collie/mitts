class_name SkaterRigidParts
extends RefCounted

# The skater's rigid parts, beside the skin (SkaterConnectedMesh): the head, the
# gloves, the cuffs and the skates, as two meshes the body joins to the skin
# (SkaterBodyMesh). Every part is one zone of its mesh (BodyZoneMesh), zone =
# UPPER_ZONE_BASE + SkaterMeshBuilder.UpperSurface or SkaterMeshBuilder.LegSurface,
# rigid to its bone but for the skate's upper (SkateUpperMesh), which bends
# across the ankle, and the neck, which bends between the collar and the head
# (neck_foot_share). The helmet's shell is drawn with a hockey helmet's ridge down
# its crown and a rib either side of it; the hair and face gear fitted under the plain
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
# the shell squared off toward a rounded box above the ears; and the whole
# shell drawn out front to back, as a helmet is longer than wide.
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
# The shell squared off toward a rounded box: each point pushed out to a
# superellipsoid of this exponent (an axis stays put, a diagonal goes out),
# by this share, from the ear line up (fading in between these heights of its
# direction), so its sides flatten and its upper corners fill.
const _BOX_EXPONENT: float = 4.0
const _BOX_SHARE: float = 0.5
const _BOX_FADE := Vector2(-0.25, 0.15)

static var _cache: Dictionary = {}

# A bare fist (the gloves off for a fight) is the glove's fist without its
# padding: its shape at this share of the glove's size, in the skin's zone, on
# the end of the sleeve. No wrist: the sleeve runs to where the cuff began.
const BARE_FIST_SCALE: float = 0.72


# `top_right`: the top hand is his right, as a left shot's is. `bare`: the
# gloves are off (FightRules.Role.FIGHTING), the hands drawn as bare fists.
static func upper_body_mesh(top_right: bool = true, bare: bool = false) -> ArrayMesh:
	var key: String = ("upper_r" if top_right else "upper_l") + ("_bare" if bare else "")
	return _shared(key, func() -> ArrayMesh:
		var b := BodyZoneMesh.new()
		var cuff: ArrayMesh = SkaterMeshBuilder.shared_cuff()
		var skin: int = SkaterMeshBuilder.UPPER_ZONE_BASE + _UpperSurface.HELMET_SKIN
		var fist_xform := Transform3D(Basis.from_scale(Vector3.ONE * BARE_FIST_SCALE),
				Vector3.ZERO)
		for top: bool in [true, false]:
			var fist: ArrayMesh = SkaterMeshBuilder.shared_glove_fist(top == top_right)
			var hand: int = _UpperBone.TOP_HAND if top else _UpperBone.BOTTOM_HAND
			var cuff_bone: int = _UpperBone.TOP_CUFF if top else _UpperBone.BOTTOM_CUFF
			if bare:
				for part: int in [SkaterMeshBuilder.FIST_PART_BACK,
						SkaterMeshBuilder.FIST_PART_FINGERS, SkaterMeshBuilder.FIST_PART_THUMB]:
					b.add(fist.surface_get_arrays(part), skin, hand, fist_xform)
				continue
			_add(b, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_BACK),
					_UpperSurface.TOP_HAND if top else _UpperSurface.BOTTOM_HAND, hand)
			_add(b, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_FINGERS),
					_UpperSurface.TOP_FINGERS if top else _UpperSurface.BOTTOM_FINGERS, hand)
			_add(b, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_THUMB),
					_UpperSurface.TOP_HAND if top else _UpperSurface.BOTTOM_HAND, hand)
			_add(b, cuff.surface_get_arrays(0),
					_UpperSurface.TOP_CUFF if top else _UpperSurface.BOTTOM_CUFF, cuff_bone)
		b.add(_neck_weighted(SkaterMeshBuilder.shared_helmet_assembly().surface_get_arrays(
				SkaterMeshBuilder.HELMET_SURF_SKIN)),
				SkaterMeshBuilder.UPPER_ZONE_BASE + _UpperSurface.HELMET_SKIN)
		_add(b, _crested(SkaterMeshBuilder.shared_helmet_shell(_HELMET_LON, _HELMET_LAT)),
				_UpperSurface.HELMET_SHELL, _UpperBone.HELMET)
		var hardware: ArrayMesh = SkaterMeshBuilder.shared_helmet_hardware()
		_add(b, hardware.surface_get_arrays(SkaterMeshBuilder.HELMET_HARDWARE_STRAP),
				_UpperSurface.HELMET_STRAP, _UpperBone.HELMET)
		return b.commit())


# One glove, unskinned, in its bones' frames, for a glove dropped on the ice
# (SkaterDroppedGear): surface 0 the fist in the hand bone's, surface 1 the cuff
# in the cuff bone's, both in the zones the body paints them in, so the body's
# material draws them. `top`: the top hand's glove; `top_right`: as for
# upper_body_mesh.
static func glove_mesh(top: bool, top_right: bool) -> ArrayMesh:
	var key: String = "glove_%s_%s" % ["top" if top else "bottom", "r" if top_right else "l"]
	return _shared(key, func() -> ArrayMesh:
		var fist: ArrayMesh = SkaterMeshBuilder.shared_glove_fist(top == top_right)
		var hand := BodyZoneMesh.new()
		_add(hand, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_BACK),
				_UpperSurface.TOP_HAND if top else _UpperSurface.BOTTOM_HAND, -1)
		_add(hand, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_FINGERS),
				_UpperSurface.TOP_FINGERS if top else _UpperSurface.BOTTOM_FINGERS, -1)
		_add(hand, fist.surface_get_arrays(SkaterMeshBuilder.FIST_PART_THUMB),
				_UpperSurface.TOP_HAND if top else _UpperSurface.BOTTOM_HAND, -1)
		var cuff := BodyZoneMesh.new()
		_add(cuff, SkaterMeshBuilder.shared_cuff().surface_get_arrays(0),
				_UpperSurface.TOP_CUFF if top else _UpperSurface.BOTTOM_CUFF, -1)
		var out := ArrayMesh.new()
		for part: BodyZoneMesh in [hand, cuff]:
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
					part.commit().surface_get_arrays(0), [], {}, ConnectedSkinBuilder.FACET_FORMAT)
		return out)


# Where the scene places the helmet in the trunk's frame (Scenes/Skater.tscn:
# Helmet): the helmet's frame as the torso carries it is the neck's foot.
const HELMET_REST := Transform3D(Basis(Vector3(0.75, 0.0, 0.0), Vector3(0.0, 0.75, 0.0),
		Vector3(0.0, 0.0, 0.75)), Vector3(0.0, 0.7, 0.0))
# The bind past the legs' and the skate uppers' feet (SkaterBodyMesh.shared_skin):
# the neck's foot (SkaterConnectedMesh.Deform.NECK_FOOT).
const NECK_FOOT_BIND: int = SkaterMeshBuilder.UPPER_BONE_COUNT \
		+ SkaterMeshBuilder.LEG_BONE_COUNT + 2


# How far the neck at helmet-local height `y` rides its foot rather than the
# head: wholly from its collar station down, so it stands in the collar
# wherever the head is carried, and less on up to its top inside the head.
static func neck_foot_share(y: float) -> float:
	var profile: Array[Vector2] = SkaterMeshBuilder.NECK_PROFILE
	return clampf(inverse_lerp(profile[0].x,
			profile[SkaterMeshBuilder.NECK_COLLAR_STATION].x, y), 0.0, 1.0)


# The helmet assembly's skin with its neck weighted from the head onto its
# foot (neck_foot_share); the head itself is rigid to the helmet.
static func _neck_weighted(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var neck_start: int = SkaterMeshBuilder.helmet_skin_neck_start()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i: int in verts.size():
		var foot: float = neck_foot_share(verts[i].y) if i >= neck_start else 0.0
		bones.append_array([_UpperBone.HELMET, NECK_FOOT_BIND, 0, 0])
		weights.append_array([1.0 - foot, foot, 0.0, 0.0])
	var out: Array = arrays.duplicate()
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	return out


# The skate upper's zones, in SkateUpperMesh.Surface order, from a side's
# collar zone on (the tongue is painted as the collar); and the blade's two
# after them.
const _UPPER_ZONE_OFFSETS: Array[int] = [0, 1, 2, 3, 6, 0]
const _BLADE_ZONE_OFFSETS: Array[int] = [4, 5]
# The binds past the leg bones' own (SkaterBodyMesh.shared_skin): per side, the
# FOOT bone reading the skate upper from the SKATE bone's frame.
const SKATE_UPPER_FOOT_BIND: int = SkaterMeshBuilder.LEG_BONE_COUNT


# One per GearModelRegistry TONGUE_* option (SkateUpperMesh.shared).
static func leg_body_mesh(tongue: int = GearModelRegistry.TONGUE_TUCKED) -> ArrayMesh:
	if not GearModelRegistry.is_valid_tongue(tongue):
		tongue = GearModelRegistry.TONGUE_TUCKED
	return _shared("legs_%d" % tongue, func() -> ArrayMesh:
		var b := BodyZoneMesh.new()
		var upper: ArrayMesh = SkateUpperMesh.shared(tongue)
		var blade: ArrayMesh = SkaterMeshBuilder.shared_skate_blade()
		for side: int in 2:
			var first: int = _LegSurface.SKATE_L_COLLAR if side == 0 else _LegSurface.SKATE_R_COLLAR
			var skate: int = _LegBone.SKATE_L if side == 0 else _LegBone.SKATE_R
			var foot: int = _LegBone.FOOT_L if side == 0 else _LegBone.FOOT_R
			for s: int in upper.get_surface_count():
				b.add(_ankle_weighted(upper.surface_get_arrays(s), skate,
						SKATE_UPPER_FOOT_BIND + side), first + _UPPER_ZONE_OFFSETS[s])
			for s: int in blade.get_surface_count():
				b.add(blade.surface_get_arrays(s), first + _BLADE_ZONE_OFFSETS[s], foot)
		return b.commit())


# The zones whose parts ship a default finish (the skin, the helmet's strap, the
# steel runners, the laces, the skate's stripe), seeded into a body's paint
# before any kit lands.
static func seed_paint(paint: BodyZonePaint) -> void:
	var skin: Material = SkaterMeshBuilder.shared_helmet_assembly().surface_get_material(
			SkaterMeshBuilder.HELMET_SURF_SKIN)
	paint.seed_zone(SkaterMeshBuilder.UPPER_ZONE_BASE + _UpperSurface.HELMET_SKIN, skin)
	var hardware: ArrayMesh = SkaterMeshBuilder.shared_helmet_hardware()
	paint.seed_zone(SkaterMeshBuilder.UPPER_ZONE_BASE + _UpperSurface.HELMET_STRAP,
			hardware.surface_get_material(SkaterMeshBuilder.HELMET_HARDWARE_STRAP))
	var upper: ArrayMesh = SkateUpperMesh.shared()
	var blade: ArrayMesh = SkaterMeshBuilder.shared_skate_blade()
	for side: int in 2:
		var first: int = _LegSurface.SKATE_L_COLLAR if side == 0 else _LegSurface.SKATE_R_COLLAR
		for s: int in [SkateUpperMesh.Surface.STRIPE, SkateUpperMesh.Surface.LACES]:
			paint.seed_zone(first + _UPPER_ZONE_OFFSETS[s], upper.surface_get_material(s))
		paint.seed_zone(first + _BLADE_ZONE_OFFSETS[SkaterMeshBuilder.BLADE_PART_RUNNER],
				blade.surface_get_material(SkaterMeshBuilder.BLADE_PART_RUNNER))


# The upper's arrays weighted across the ankle (SkateUpperMesh.foot_share):
# the SKATE bone at identity, the foot through its own bind.
static func _ankle_weighted(arrays: Array, skate: int, foot_bind: int) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for p: Vector3 in verts:
		var foot: float = SkateUpperMesh.foot_share(p)
		bones.append_array([skate, foot_bind, 0, 0])
		weights.append_array([1.0 - foot, foot, 0.0, 0.0])
	var out: Array = arrays.duplicate()
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	return out


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
# How far out (a share of the radius) the boxed shell lies along unit `d`
# beyond the sphere.
static func _boxed(d: Vector3) -> float:
	var norm: float = pow(pow(absf(d.x), _BOX_EXPONENT) + pow(absf(d.y), _BOX_EXPONENT)
			+ pow(absf(d.z), _BOX_EXPONENT), 1.0 / _BOX_EXPONENT)
	return (1.0 / norm - 1.0) * _BOX_SHARE * smoothstep(_BOX_FADE.x, _BOX_FADE.y, d.y)


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
		raise += verts[i].length() * _boxed(d)
		var p: Vector3 = verts[i] + d * raise
		p.z *= _LENGTH
		verts[i] = p
	# Laid on the helmet's paint from straight ahead, the number on the front.
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	for i: int in verts.size():
		uvs[i] = HelmetDecal.shell_uv(verts[i])
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i: int in verts.size():
			indices.append(i)
		# Unindexed, each face has its own corners, so its seam unwraps alone.
		for t: int in range(0, verts.size(), 3):
			HelmetDecal.unwrap_face(uvs, t)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	for t: int in range(0, indices.size(), 3):
		var a: Vector3 = verts[indices[t]]
		var n: Vector3 = (verts[indices[t + 2]] - a).cross(verts[indices[t + 1]] - a).normalized()
		for c: int in 3:
			normals[indices[t + c]] = n
	# The shell's grid is laid a quad at a time ahead of its liner, and the
	# ridge and ribs bend those quads: each is lit as one facet, as the jersey's.
	if arrays[Mesh.ARRAY_INDEX] == null:
		arrays[Mesh.ARRAY_CUSTOM0] = ConnectedSkinBuilder.facet_pairs(verts, normals,
				_HELMET_LON * _HELMET_LAT)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	return arrays

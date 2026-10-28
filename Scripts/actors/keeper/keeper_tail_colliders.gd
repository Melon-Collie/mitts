class_name KeeperTailColliders
extends HemColliders

# What the keeper's jersey tail drapes over: his pants and both thigh guards,
# each a stack of rounded sections of order PANTS_ROUNDNESS
# (KeeperGearMeshes.PANTS_SECTIONS, THIGH_SECTIONS) in its gear box, as the
# boxes stand this frame. In his body rig the boxes are the part bones
# (KeeperBodyRig), so a part's bone index is its KeeperGear.Part.

const PARTS: Array[int] = [KeeperGear.Part.PANTS, KeeperGear.Part.THIGH_G, KeeperGear.Part.THIGH_B]

var _xf: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY]
var _inv: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY]
var _h: Array[Vector3] = []
var _sections: Array = []


func _init() -> void:
	for part: int in PARTS:
		_h.append(KeeperGear.half_extents(part))
		_sections.append(KeeperGearMeshes.PANTS_SECTIONS if part == KeeperGear.Part.PANTS
				else KeeperGearMeshes.THIGH_SECTIONS)


func update(skeleton: Skeleton3D) -> void:
	for i: int in PARTS.size():
		place(i, skeleton.get_bone_global_pose(PARTS[i]))


# The `i`th of PARTS where its box stands.
func place(i: int, box: Transform3D) -> void:
	_xf[i] = box
	_inv[i] = box.affine_inverse()


func push_out(p: Vector3, margin: float) -> Vector3:
	for i: int in PARTS.size():
		p = push_out_of(p, _xf[i], _inv[i], _sections[i], _h[i], margin)
	return p


func configure_native(native: RefCounted) -> void:
	var sections := PackedFloat64Array()
	var counts := PackedInt32Array()
	for i: int in PARTS.size():
		var stack: Array[Vector4] = _sections[i]
		counts.append(stack.size())
		for st: Vector4 in stack:
			sections.append_array([st.x, st.y, st.z, st.w])
	native.call("collide_sections", PackedInt32Array(PARTS), PackedVector3Array(_h), sections, counts,
			KeeperGearMeshes.PANTS_ROUNDNESS)


# `p` moved out of one piece (its box `xf`, `inv` its inverse; `sections` and
# half extents `h`), if it is inside, to `margin` off its surface.
static func push_out_of(p: Vector3, xf: Transform3D, inv: Transform3D, sections: Array[Vector4],
		h: Vector3, margin: float) -> Vector3:
	var local: Vector3 = inv * p
	# Outside the box with the margin round it is outside every section in it.
	if absf(local.y) > h.y or absf(local.x) > h.x + margin or absf(local.z) > h.z + margin:
		return p
	var length: float = Vector2(local.x, local.z).length()
	if length < 1e-5:
		return p
	var sec: Vector3 = KeeperGearMeshes.section_at(sections, h, local.y)
	# Clear of the surface stood off by the margin exactly when the point drawn
	# in by it is outside the section, which asks no root of the section's
	# order (its cube, PANTS_ROUNDNESS).
	var share: float = maxf(length - margin, 0.0) / length
	var across: float = absf(local.x) * share / sec.x
	var deep: float = absf(local.z) * share / (sec.y if local.z < 0.0 else sec.z)
	if across * across * across + deep * deep * deep >= 1.0:
		return p
	return xf * on_section(sec, local.y, Vector2(local.x, local.z) / length, margin)


# The point on a section (half width, front depth, back depth) at height `y`
# of its box frame, along `dir`, `off` metres out from its surface.
static func on_section(sec: Vector3, y: float, dir: Vector2, off: float) -> Vector3:
	var depth: float = sec.y if dir.y < 0.0 else sec.z
	var order: float = KeeperGearMeshes.PANTS_ROUNDNESS
	var r: float = pow(pow(absf(dir.x) / sec.x, order) + pow(absf(dir.y) / depth, order),
			-1.0 / order)
	return Vector3(dir.x, y, dir.y) * Vector3(r + off, 1.0, r + off)

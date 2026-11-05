extends GutTest

# The helmet's number (HelmetDecal) is on the front of the shell and nowhere
# else: the shell's middle above the brow samples the number's middle, and no
# face of the shell off the front reaches the number at any point across it,
# the seam behind the head included.

# Off the front: behind this (helmet-local z, the face toward -Z).
const FRONT_Z_M: float = -0.05


# The number's box in the texture, a little over where two digits' glyphs can
# fall (each about 0.55 em wide, 0.7 em high).
func _number_box() -> Rect2:
	var span: float = HelmetDecal.TOP_Y_M - HelmetDecal.BOTTOM_Y_M
	var centre_v: float = (HelmetDecal.TOP_Y_M - HelmetDecal.NUMBER_CENTER_Y_M) / span
	var half_u: float = 0.7 * HelmetDecal.NUMBER_EM_M / (TAU * HelmetDecal.GIRTH_RADIUS_M)
	var half_v: float = 0.45 * HelmetDecal.NUMBER_EM_M / span
	return Rect2(0.5 - half_u, centre_v - half_v, 2.0 * half_u, 2.0 * half_v)


func test_the_front_samples_the_number() -> void:
	var uv: Vector2 = HelmetDecal.shell_uv(Vector3(0.0, HelmetDecal.NUMBER_CENTER_Y_M, -0.16))
	assert_almost_eq(uv, _number_box().get_center(), Vector2.ONE * 1e-4,
			"straight ahead above the brow, the number's middle")


func test_no_face_off_the_front_carries_the_number() -> void:
	var arrays: Array = SkaterRigidParts._crested(SkaterMeshBuilder.shared_helmet_shell(
			SkaterRigidParts._HELMET_LON, SkaterRigidParts._HELMET_LAT))
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var box: Rect2 = _number_box()
	var through: int = 0
	var off_front: int = 0
	for t: int in range(0, verts.size(), 3):
		var behind: bool = false
		for c: int in 3:
			behind = behind or verts[t + c].z > FRONT_Z_M
		if not behind:
			continue
		off_front += 1
		for i: int in 5:
			for j: int in 5 - i:
				var uv: Vector2 = uvs[t] + (uvs[t + 1] - uvs[t]) * (i / 4.0) \
						+ (uvs[t + 2] - uvs[t]) * (j / 4.0)
				# The texture repeats across, as the shader samples it.
				if box.has_point(Vector2(fposmod(uv.x, 1.0), uv.y)):
					through += 1
	assert_gt(off_front, 0, "the shell has faces off the front")
	assert_eq(through, 0, "no face off the front samples the number")

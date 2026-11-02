extends GutTest

# The helmet as the body wears it (HelmetShellMesh) and the number painted on it
# (HelmetDecal). The hair and face gear are fitted under the plain shell, so the
# shape may only raise it; the numbers must land on clear shell, above the
# lip; and every kit's number must stand out on its own helmet.

const _MIN_NUMBER_CONTRAST: float = 3.0


func test_the_shape_only_raises_the_plain_shell() -> void:
	var plain: PackedVector3Array = SkaterMeshBuilder.shared_helmet_shell(
			HelmetShellMesh.LON, HelmetShellMesh.LAT).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sunk: int = 0
	for p: Vector3 in plain:
		if HelmetShellMesh.shape(p).length() < p.length() - 1e-6:
			sunk += 1
	assert_eq(sunk, 0, "plain shell points the shape draws in")


func test_the_brim_stands_out_from_the_brow_further_than_the_edge_elsewhere() -> void:
	var verts: PackedVector3Array = HelmetShellMesh.shared()[Mesh.ARRAY_VERTEX]
	var front: float = -INF
	var side: float = -INF
	for v: Vector3 in verts:
		if absf(v.x) < 0.01 and v.z < 0.0:
			front = maxf(front, -v.z)
		if absf(v.z) < 0.01 and v.x > 0.0:
			side = maxf(side, v.x)
	var brow: float = -HelmetShellMesh.lip_top(PI).z
	assert_gt(front - brow, 0.01, "the brim stands a centimetre proud of the brow")
	assert_gt(front, side, "the helmet is longer than it is wide")


func test_no_face_wraps_the_texture_seam() -> void:
	var uvs: PackedVector2Array = HelmetShellMesh.shared()[Mesh.ARRAY_TEX_UV]
	var wrapped: int = 0
	for t: int in range(0, uvs.size(), 3):
		var lo: float = minf(uvs[t].x, minf(uvs[t + 1].x, uvs[t + 2].x))
		var hi: float = maxf(uvs[t].x, maxf(uvs[t + 1].x, uvs[t + 2].x))
		if hi - lo > 0.2:
			wrapped += 1
	assert_eq(wrapped, 0, "faces whose U runs most of the way round")


# Each number's digits, cap height tall, sit wholly above where the lip leaves
# the shell under them, and below the crown.
func test_the_numbers_sit_on_clear_shell() -> void:
	for site: Vector3 in HelmetDecal.NUMBERS:
		var cap_m: float = site.z * HelmetDecal.CAP_EM
		var half_width_rad: float = site.z / HelmetShellMesh.metres_per_uv(site.x, site.y).x * TAU
		for off: float in [-half_width_rad, 0.0, half_width_rad]:
			var lip: float = HelmetShellMesh.lip_top(site.x + off).y
			assert_gt(site.y - cap_m * 0.5, lip,
					"number at θ %.2f clears the lip at %+.2f rad" % [site.x, off])
		assert_lt(site.y + cap_m * 0.5, HelmetShellMesh.UV_TOP_Y_M)


func test_every_kit_numbers_its_helmet_legibly() -> void:
	for slot: int in TeamColorRegistry.get_all_slots():
		for team_id: int in 2:
			var colors: Dictionary = TeamColorRegistry.get_colors(slot, team_id)
			var kit: Dictionary = colors.uniform
			var ink: Color = HelmetDecal.number_color_for(colors)
			assert_gte(TeamColorRegistry.contrast_ratio(ink, kit.helmet), _MIN_NUMBER_CONTRAST,
					"%s %s: %s on %s" % [TeamColorRegistry.get_preset_name(slot),
					"away" if team_id == 1 else "home", ink.to_html(false),
					(kit.helmet as Color).to_html(false)])

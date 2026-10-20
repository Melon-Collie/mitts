extends GutTest

# The Arena Ads video option reaches a rink that is already built, mid-match, so
# it must hide the board panels and the in-ice logos without a rebuild — and a
# rebuild that happens later must keep them hidden.


# Half-size, so the ice albedo paints in a fraction of the full rink's time.
func _make_rink() -> HockeyRink:
	var rink := HockeyRink.new()
	rink.rink_length = 30.0
	rink.rink_width = 13.0
	rink.corner_radius = 4.0
	add_child_autofree(rink)
	return rink


func _board_ads(rink: HockeyRink) -> MeshInstance3D:
	return rink.find_child("BoardAds", false, false) as MeshInstance3D


func _ice_material(rink: HockeyRink) -> ShaderMaterial:
	for child: Node in rink.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh is PlaneMesh:
			return mi.material_override as ShaderMaterial
	return null


func test_ads_show_by_default() -> void:
	var rink: HockeyRink = _make_rink()
	assert_not_null(_board_ads(rink), "the rink builds its board ads")
	assert_true(_board_ads(rink).visible)
	assert_true(_ice_material(rink).get_shader_parameter("ads_enabled"))


func test_hiding_ads_clears_boards_and_ice_without_a_rebuild() -> void:
	var rink: HockeyRink = _make_rink()
	var boards: MeshInstance3D = _board_ads(rink)
	rink.set_ads_shown(false)
	assert_same(_board_ads(rink), boards, "the switch must not rebuild the rink")
	assert_false(boards.visible, "board panels hidden")
	assert_false(_ice_material(rink).get_shader_parameter("ads_enabled"), "ice logos hidden")
	rink.set_ads_shown(true)
	assert_true(boards.visible)
	assert_true(_ice_material(rink).get_shader_parameter("ads_enabled"))


func test_a_later_rebuild_keeps_ads_hidden() -> void:
	var rink: HockeyRink = _make_rink()
	var band: Mesh = _board_ads(rink).mesh
	rink.set_ads_shown(false)
	rink.wall_color = Color(0.9, 0.9, 0.9)
	# Rebuilt in the same frame, so the new panel is renamed around the old one
	# still queued for deletion; the band mesh is the build cache's, and shared.
	var boards: MeshInstance3D = null
	for child: Node in rink.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh == band and not mi.is_queued_for_deletion():
			boards = mi
	assert_not_null(boards, "the rebuild builds its board ads again")
	assert_false(boards.visible)

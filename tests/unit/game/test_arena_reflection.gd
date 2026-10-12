extends GutTest

# The bowl's reflection probe captures once and keeps that cube, so what it may
# draw is the contract: the building, never an actor, and never at the cost of
# changing what any camera sees.


func _mesh(layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.layers = layers
	return mi


func test_tagging_adds_the_probe_layer_on_top_of_the_default() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var board: MeshInstance3D = _mesh(RenderLayers.DEFAULT)
	root.add_child(board)
	var nested: MeshInstance3D = _mesh(RenderLayers.DEFAULT)
	board.add_child(nested)
	var light := OmniLight3D.new()
	root.add_child(light)
	ArenaReflection.tag_static(root)
	for visual: VisualInstance3D in [board, nested, light]:
		assert_eq(visual.layers, RenderLayers.DEFAULT | RenderLayers.REFLECTED_STATIC,
				"%s must keep layer 1 and gain the probe's" % visual.get_class())


func test_tagging_leaves_overhead_dressing_off_the_play_cameras() -> void:
	# GameCamera masks only OVERHEAD_DRESSING; any other bit on a fixture or the
	# scoreboard would put it back in the top-down shot.
	var root := Node3D.new()
	add_child_autofree(root)
	var fixture: MeshInstance3D = _mesh(RenderLayers.OVERHEAD_DRESSING)
	root.add_child(fixture)
	ArenaReflection.tag_static(root)
	assert_eq(fixture.layers, RenderLayers.OVERHEAD_DRESSING,
			"overhead dressing must stay on its own layer only")


func test_tagging_skips_particles_and_viewport_contents() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var burst := GPUParticles3D.new()
	root.add_child(burst)
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var painted: MeshInstance3D = _mesh(RenderLayers.DEFAULT)
	viewport.add_child(painted)
	ArenaReflection.tag_static(root)
	assert_eq(burst.layers, RenderLayers.DEFAULT, "a capture mid-burst would freeze it")
	assert_eq(painted.layers, RenderLayers.DEFAULT, "a SubViewport is another world")


func test_the_probe_never_draws_the_default_layer() -> void:
	# Actors render on layer 1 alone, so this is what keeps a skater standing at
	# a faceoff dot at load out of the cube for the rest of the game.
	var probe := ArenaReflection.new()
	add_child_autofree(probe)
	probe.setup(self)
	assert_eq(probe.cull_mask & RenderLayers.DEFAULT, 0, "the probe must not see layer 1")
	assert_ne(probe.cull_mask & RenderLayers.REFLECTED_STATIC, 0, "the probe draws the building")
	assert_eq(probe.update_mode, ReflectionProbe.UPDATE_ONCE, "captured once, not per frame")
	assert_true(probe.box_projection, "an arena is a room: box projection")


func test_fit_shoots_from_near_the_ice() -> void:
	var probe := ArenaReflection.new()
	add_child_autofree(probe)
	probe.setup(self)
	var box := AABB(Vector3(-50.0, -1.5, -60.0), Vector3(100.0, 25.0, 120.0))
	probe.fit(box)
	assert_eq(probe.size, box.size, "the probe box is the bowl")
	var capture_y: float = box.get_center().y + probe.origin_offset.y
	assert_almost_eq(capture_y, ArenaReflection.CAPTURE_HEIGHT, 0.001,
			"capture point sits CAPTURE_HEIGHT over the ice")


func test_a_dim_capture_is_retaken_at_full_house() -> void:
	var probe := ArenaReflection.new()
	add_child_autofree(probe)
	probe.setup(self)
	probe.fit(AABB(Vector3(-10.0, -1.0, -10.0), Vector3(20.0, 10.0, 20.0)))
	probe.set_house_level(ArenaHouseLights.HOUSE_LOW)
	await wait_process_frames(1)
	var dim_y: float = probe.position.y
	assert_almost_eq(probe.intensity, ArenaHouseLights.HOUSE_LOW, 0.001,
			"the cube dims with the lights")
	probe.set_house_level(1.0)
	await wait_process_frames(1)
	assert_ne(probe.position.y, dim_y, "back at full house, the probe must re-shoot")
	assert_almost_eq(probe.intensity, 1.0, 0.001, "and its intensity is restored")


func test_house_lights_drive_the_attached_probe() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var spot := SpotLight3D.new()
	spot.name = "SpotLight3D"
	root.add_child(spot)
	var lights := ArenaHouseLights.new()
	root.add_child(lights)
	lights.setup(root)
	var probe := ArenaReflection.new()
	root.add_child(probe)
	probe.setup(root)
	lights.attach_reflection(probe)
	lights.play_intro(4.0)
	await wait_seconds(ArenaHouseLights.FALL_TIME + 0.1)
	assert_lt(probe.intensity, 0.5, "the blackout takes the reflection down with it")
	lights.restore()
	assert_almost_eq(probe.intensity, 1.0, 0.001, "restore brings it back")

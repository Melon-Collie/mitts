extends Node

# The body of tools/uniform_study.gd — see that file for what it is for.
#
# The skater is a real Skater driven by a real SkaterController for a held
# pose, so the hands hold the stick and the arms hang where play puts them
# rather than in the bare rig's akimbo rest.

const DT: float = 1.0 / 120.0
const TILE: int = 512
const BACKGROUND: Color = Color(0.10, 0.11, 0.14)
const BUILD_HEIGHT_IN: int = 73
const BUILD_WEIGHT_LB: int = 201

# [team slot, side (0 home, 1 away)] per row: a yoke kit, a contrast-sleeve kit,
# a white sweater with white caps, a striped-hem kit. UNIFORM_STUDY_KITS
# overrides it ("0:0,6:1" — slot:side).
const KITS: Array = [[6, 0], [7, 0], [4, 1], [0, 0], [2, 1]]

# Held arm poses, as [ticks, {aim (relative to the skater), shoot, slap}]
# segments — the arm-swinging subset of pose_capture_runner.gd's set. Every kit
# is shot in every pose named by UNIFORM_STUDY_POSES (default: rest).
const POSES: Dictionary = {
	"rest": [[60, {"aim": Vector3(0.4, 0.0, -2.5)}]],
	"cross_body": [[20, {"aim": Vector3(0.4, 0.0, -2.0)}], [50, {"aim": Vector3(-2.6, 0.0, -0.4)}]],
	"forehand_wide": [[20, {"aim": Vector3(0.4, 0.0, -2.0)}], [50, {"aim": Vector3(2.6, 0.0, -0.2)}]],
	"wrister_follow": [[10, {"aim": Vector3(0.4, 0.0, -2.0)}],
			[45, {"aim": Vector3(1.4, 0.0, -3.0), "shoot": true}], [14, {"aim": Vector3(1.4, 0.0, -3.0)}]],
	"slap_coil": [[10, {"aim": Vector3(0.4, 0.0, -2.0)}],
			[58, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}]],
	"slap_follow": [[10, {"aim": Vector3(0.4, 0.0, -2.0)}],
			[58, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}], [16, {"aim": Vector3(0.8, 0.0, -3.2)}]],
}

# Camera offset and aim, relative to the skater's origin (hip height). The
# skater faces −Z.
const SHOTS: Array = [
	{"name": "front", "cam": Vector3(0.0, 0.5, -2.6), "aim": Vector3(0.0, 0.25, 0.0)},
	{"name": "three_quarter", "cam": Vector3(1.85, 0.6, -1.85), "aim": Vector3(0.0, 0.25, 0.0)},
	{"name": "side", "cam": Vector3(2.6, 0.5, 0.0), "aim": Vector3(0.0, 0.25, 0.0)},
	{"name": "back", "cam": Vector3(0.0, 0.5, 2.6), "aim": Vector3(0.0, 0.25, 0.0)},
	{"name": "high_back", "cam": Vector3(0.8, 1.9, 2.0), "aim": Vector3(0.0, 0.2, 0.0)},
	{"name": "game", "game_cam": true},
	# Close-ups for lettering (only when named in UNIFORM_STUDY_SHOTS).
	{"name": "back_close", "cam": Vector3(0.0, 0.42, 1.25), "aim": Vector3(0.0, 0.32, 0.0)},
	{"name": "shoulder_close", "cam": Vector3(1.2, 0.5, 0.25), "aim": Vector3(0.18, 0.38, 0.0)},
]
const _CLOSE_SHOTS: Array[String] = ["back_close", "shoulder_close"]
const _GAME_ZOOM: float = 3.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func is_faceoff_prep() -> bool:
		return false


var _camera: Camera3D = null
var _state: StubGameState = null


func begin() -> void:
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	SkaterCameraCull.enabled = false
	CosmeticFreeze.vfx = true
	CosmeticFreeze.hud = true
	_state = StubGameState.new()
	add_child(_state)
	_build_stage()
	_run.call_deferred()


func _run() -> void:
	var skater_scene: PackedScene = load("res://Scenes/Skater.tscn")
	var puck_scene: PackedScene = load("res://Scenes/Puck.tscn")
	var tiles: Array[Image] = []
	var rows: Array[Array] = []
	for kit: Array in _kits():
		for pose: String in _pose_names():
			rows.append([kit, pose])
	for row: Array in rows:
		var kit: Array = row[0]
		var puck: Puck = puck_scene.instantiate() as Puck
		add_child(puck)
		puck.visible = false
		puck.set_physics_process(false)
		puck.set_process(false)
		var skater: Skater = skater_scene.instantiate() as Skater
		skater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(skater)
		skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		skater.set_process(false)
		skater.set_physics_process(false)
		var attrs := PlayerAttributes.new(BUILD_HEIGHT_IN, BUILD_WEIGHT_LB, 1, 1, 1, 1)
		skater.set_uniform(TeamColorRegistry.get_colors(int(kit[0]), int(kit[1])))
		skater.set_jersey_info("Player", 19)
		skater.apply_appearance(attrs)
		skater.set_world_hud_hidden(true)
		var controller := SkaterController.new()
		add_child(controller)
		controller.setup(skater, puck, _state)
		controller.apply_attributes(attrs)

		controller._pose.facing = Vector2(0.0, -1.0)
		skater.set_facing(controller._pose.facing)
		puck.set_carrier(skater)
		controller.on_puck_picked_up_network()
		var input := InputState.new()
		for step: Array in POSES[row[1]]:
			var spec: Dictionary = step[1]
			for t: int in int(step[0]):
				input.delta = DT
				input.mouse_world_pos = skater.global_position + (spec.aim as Vector3)
				input.shoot_held = spec.get("shoot", false)
				input.shoot_pressed = input.shoot_held and t == 0
				input.slap_held = spec.get("slap", false)
				input.slap_pressed = input.slap_held and t == 0
				controller._process_input(input, DT)
				skater._physics_process(DT)
				skater._process(DT)
		print("[uniform_study] %s %s, %s" % [TeamColorRegistry.get_preset_name(int(kit[0])),
				"home" if int(kit[1]) == 0 else "away", row[1]])

		for shot: Dictionary in _shots():
			if bool(shot.get("game_cam", false)):
				_frame_as_the_game_does(skater)
			else:
				_camera.fov = 40.0
				_camera.global_position = skater.global_position + (shot.cam as Vector3)
				_camera.look_at(skater.global_position + (shot.aim as Vector3), Vector3.UP)
			skater._process(DT)
			await get_tree().process_frame
			await get_tree().process_frame
			tiles.append(get_viewport().get_texture().get_image())

		controller.queue_free()
		skater.queue_free()
		puck.queue_free()
		await get_tree().process_frame
	_save_sheet(tiles, rows.size())
	get_tree().quit()


# SHOTS, or the ones UNIFORM_STUDY_SHOTS names; the close-ups only when named.
func _shots() -> Array:
	var requested: PackedStringArray = OS.get_environment("UNIFORM_STUDY_SHOTS").split(",", false)
	var out: Array = []
	for shot: Dictionary in SHOTS:
		var shot_name: String = shot.name
		if requested.is_empty() and not _CLOSE_SHOTS.has(shot_name) or requested.has(shot_name):
			out.append(shot)
	return out


func _kits() -> Array:
	var requested: String = OS.get_environment("UNIFORM_STUDY_KITS")
	if requested.is_empty():
		return KITS
	var out: Array = []
	for token: String in requested.split(",", false):
		var parts: PackedStringArray = token.split(":")
		out.append([int(parts[0]), int(parts[1]) if parts.size() > 1 else 0])
	return out


func _pose_names() -> Array[String]:
	var out: Array[String] = []
	for pose: String in OS.get_environment("UNIFORM_STUDY_POSES").split(",", false):
		if POSES.has(pose.strip_edges()):
			out.append(pose.strip_edges())
		else:
			push_warning("[uniform_study] unknown pose '%s'" % pose)
	if out.is_empty():
		out.append("rest")
	return out


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND
	env.environment = e
	add_child(env)

	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	key.light_energy = 1.3
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -140.0, 0.0)
	fill.light_energy = 0.5
	add_child(fill)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.60, 0.66)
	floor_mesh.material_override = fm
	add_child(floor_mesh)


# The game camera's height and tilt, with the FOV narrowed so the tile is a
# crop of the middle of the player's frame (pose_capture_runner.gd's *_game
# framing), magnified _GAME_ZOOM times so the kit is readable.
func _frame_as_the_game_does(skater: Skater) -> void:
	var probe := GameCamera.new()
	var height: float = probe.min_height * PlayerPrefs.camera_distance
	probe.free()
	var tilt: float = PlayerPrefs.camera_tilt_deg
	var frame_px: float = float(ProjectSettings.get_setting(
			"display/window/size/viewport_height", TILE))
	_camera.fov = rad_to_deg(2.0 * atan(
			tan(deg_to_rad(PlayerPrefs.fov) * 0.5) * float(TILE) / maxf(frame_px, 1.0)
			/ _GAME_ZOOM))
	_camera.global_position = skater.global_position + Vector3(
			0.0, height, height * tan(deg_to_rad(90.0 - tilt)))
	_camera.rotation_degrees = Vector3(-tilt, 0.0, 0.0)


func _save_sheet(tiles: Array[Image], rows: int) -> void:
	var out_dir: String = OS.get_environment("UNIFORM_STUDY_OUT")
	if out_dir.is_empty():
		out_dir = "user://uniform_study"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cols: int = _shots().size()
	var sheet := Image.create_empty(cols * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKGROUND)
	for i: int in tiles.size():
		var src: Image = tiles[i]
		src.convert(Image.FORMAT_RGBA8)
		@warning_ignore("integer_division")
		var row: int = i / cols
		sheet.blit_rect(src, Rect2i(0, 0, TILE, TILE), Vector2i((i % cols) * TILE, row * TILE))
	var path: String = "%s/sheet.png" % out_dir
	sheet.save_png(path)
	print("[uniform_study] sheet -> %s" % ProjectSettings.globalize_path(path))

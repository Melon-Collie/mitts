extends "res://tools/pose_capture_runner.gd"

# The body of tools/body_preview.gd. Reuses pose_capture's stage, actor and
# scripted poses; what it changes is the loop: each pose is built and run once
# per body (the rig's current one, then the connected prototype — the flag is
# read as the skater is built), then shot from four sides of the skater.

const PREVIEW_TILE: int = 448
const PREVIEW_FOV: float = 30.0
const PREVIEW_DIR: String = "res://.preview/body"
# Skater-local camera offsets (he faces −Z): front three-quarter, side, back
# three-quarter, straight behind.
const ANGLES: Array[Vector3] = [
	Vector3(-2.0, 0.55, -3.0),
	Vector3(3.6, 0.35, -0.3),
	Vector3(2.0, 0.65, 3.0),
	Vector3(0.0, 0.5, 3.6),
]
const PREVIEW_POSES: Array[String] = [
	"rest", "carry", "stride_away", "stride_lateral", "stance_rest", "cross_body_reach",
	"wrister_loaded", "slapper_coil", "one_timer_loaded", "hit_commit_deep", "shot_block",
	"jersey_tuck_full", "celebrate", "knockdown_lying_side",
]

enum Step { BUILD, POSE, GRAB }

var _step: Step = Step.BUILD
var _variant: int = 0
var _first_variant: int = 0
var _angle: int = 0
var _tiles: Array[Image] = []


func begin_preview(only: String, new_only: bool) -> void:
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	SkaterCameraCull.enabled = false
	CosmeticFreeze.vfx = true
	CosmeticFreeze.hud = true
	_first_variant = 1 if new_only else 0
	_variant = _first_variant
	for spec: Dictionary in POSES:
		var pose_name: String = spec["name"]
		var wanted: bool = PREVIEW_POSES.has(pose_name)
		if only != "":
			wanted = false
			for part: String in only.split(","):
				wanted = wanted or pose_name.contains(part)
		if wanted:
			_poses.append(spec)
	_pose_index = 0
	_skater_scene = load("res://Scenes/Skater.tscn")
	_puck_scene = load("res://Scenes/Puck.tscn")
	_state = StubGameState.new()
	add_child(_state)
	_build_stage()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))


func _process(_delta: float) -> void:
	if _poses.is_empty():
		return
	match _step:
		Step.BUILD:
			if _pose_index >= _poses.size():
				print("body preview: %d sheets in %s" % [_poses.size(),
						ProjectSettings.globalize_path(PREVIEW_DIR)])
				get_tree().quit()
				return
			SkaterConnectedMesh.enabled = _variant == 1
			_build_actor()
			_step = Step.POSE
		Step.POSE:
			_run_pose()
			_angle = 0
			_place_camera()
			_step = Step.GRAB
		Step.GRAB:
			_tiles.append(get_viewport().get_texture().get_image())
			_angle += 1
			if _angle < ANGLES.size():
				_place_camera()
				return
			_teardown()
			_variant += 1
			if _variant > 1:
				_save_pose_sheet()
				_variant = _first_variant
				_pose_index += 1
			_step = Step.BUILD


func _place_camera() -> void:
	_camera.fov = PREVIEW_FOV
	var basis: Basis = _skater.global_transform.basis.orthonormalized()
	var aim: Vector3 = _skater.global_position + Vector3(0.0, -0.1, 0.0)
	_camera.global_position = aim + basis * ANGLES[_angle]
	_camera.look_at(aim, Vector3.UP)


func _save_pose_sheet() -> void:
	var rows: int = 2 - _first_variant
	var sheet := Image.create_empty(ANGLES.size() * PREVIEW_TILE, rows * PREVIEW_TILE, false,
			Image.FORMAT_RGBA8)
	sheet.fill(BACKGROUND)
	for i: int in _tiles.size():
		var src: Image = _tiles[i]
		src.convert(Image.FORMAT_RGBA8)
		@warning_ignore("integer_division")
		var row: int = i / ANGLES.size()
		sheet.blit_rect(src, Rect2i(0, 0, PREVIEW_TILE, PREVIEW_TILE),
				Vector2i((i % ANGLES.size()) * PREVIEW_TILE, row * PREVIEW_TILE))
	var path: String = "%s/%s.png" % [PREVIEW_DIR, String(_poses[_pose_index]["name"])]
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("  ", ProjectSettings.globalize_path(path))
	_tiles.clear()

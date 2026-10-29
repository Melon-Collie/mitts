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

# --pants: the connected pants alone, nothing above the belt, framed on them.
const PANTS_POSES: Array[String] = [
	"rest", "stride_away", "stride_lateral", "stance_rest", "hit_commit_deep", "shot_block",
	"jersey_tuck_full",
]
const PANTS_FOV: float = 22.0
# --head: framed on the helmet.
const HEAD_FOV: float = 7.0
const PANTS_AIM_Y: float = -0.4

enum Step { BUILD, POSE, GRAB }

var _step: Step = Step.BUILD
var _variant: int = 0
var _first_variant: int = 0
var _angle: int = 0
var _tiles: Array[Image] = []
var _pants: bool = false
var _audit: bool = false
var _head: bool = false


func begin_preview(only: String, new_only: bool, pants: bool = false,
		audit: bool = false, head: bool = false) -> void:
	_pants = pants
	_audit = audit
	_head = head
	SkaterConnectedMesh.preview_pants_only = pants
	new_only = new_only or pants
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	SkaterCameraCull.enabled = false
	CosmeticFreeze.vfx = true
	CosmeticFreeze.hud = true
	_first_variant = 1 if new_only else 0
	_variant = _first_variant
	for spec: Dictionary in POSES:
		var pose_name: String = spec["name"]
		var wanted: bool = (PANTS_POSES if pants else PREVIEW_POSES).has(pose_name)
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
			if _audit and SkaterConnectedMesh.enabled:
				_audit_folds()
			if _pants:
				_hide_all_but_the_pants()
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


func _hide_all_but_the_pants() -> void:
	var keep: Array[String] = ["ConnectedBody", "LegMesh"]
	for node: Node in _skater.find_children("*", "GeometryInstance3D", true, false):
		if not keep.has(String(node.name)):
			(node as GeometryInstance3D).visible = false


func _place_camera() -> void:
	_camera.fov = PANTS_FOV if _pants else PREVIEW_FOV
	var basis: Basis = _skater.global_transform.basis.orthonormalized()
	var aim: Vector3 = _skater.global_position + Vector3(0.0, PANTS_AIM_Y if _pants else -0.1, 0.0)
	if _head:
		var body: Skeleton3D = _skater._arms._skeleton
		_camera.fov = HEAD_FOV
		aim = body.global_transform * body.get_bone_global_pose(
				SkaterMeshBuilder.UpperBone.HELMET).origin
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
	var path: String = "%s/%s%s.png" % [PREVIEW_DIR,
			"pants_" if _pants else ("head_" if _head else ""),
			String(_poses[_pose_index]["name"])]
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("  ", ProjectSettings.globalize_path(path))
	_tiles.clear()


# Skins the connected body on the CPU as the pose holds it and counts the faces
# turned inside out against their bind facing, by paint zone: a fold that has
# gone over shows as a hole (its back is culled), and this says where.
func _audit_folds() -> void:
	var body: Skeleton3D = _skater._arms._skeleton
	var mesh: ArrayMesh = SkaterConnectedMesh.shared_mesh(_skater.gear_style.jersey_tuck)
	var a: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var zones: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var skin: Skin = SkaterConnectedMesh.shared_skin()
	var xforms: Array[Transform3D] = []
	for i: int in skin.get_bind_count():
		xforms.append(body.get_bone_global_pose(skin.get_bind_bone(i)) * skin.get_bind_pose(i))
	var flipped: Dictionary = {}
	var worst: Dictionary = {}
	for t: int in range(0, verts.size(), 3):
		var p: Array[Vector3] = []
		var turn := Basis()
		var heaviest: float = -1.0
		for c: int in 3:
			var v: int = t + c
			var out := Vector3.ZERO
			for i: int in 4:
				var w: float = weights[v * 4 + i]
				if w > 0.0:
					out += xforms[bones[v * 4 + i]] * verts[v] * w
					if w > heaviest:
						heaviest = w
						turn = xforms[bones[v * 4 + i]].basis
			p.append(out)
		var n: Vector3 = (p[2] - p[0]).cross(p[1] - p[0])
		if n.length_squared() < 1e-12:
			continue
		var expected: Vector3 = (turn * normals[t]).normalized()
		if n.normalized().dot(expected) < 0.0:
			var zone: int = int(round(zones[t].x))
			flipped[zone] = int(flipped.get(zone, 0)) + 1
			worst[zone] = (p[0] + p[1] + p[2]) / 3.0
	print("    folds in %s: %s (a face in each: %s)" % [
			String(_poses[_pose_index]["name"]), flipped, worst])

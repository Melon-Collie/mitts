extends SceneTree

# Renders the new keeper offscreen in every taught stance, from the front, the
# side and three-quarter, so his body can be SEEN without a game: each stance
# solved by KeeperSkeleton from KeeperPoses and drawn by the Keeper actor, with
# the save boxes overlaid (KEEPER_CAPTURE_BOXES=0 hides them). One contact sheet
# per stance, plus one of every stance from the front.
#
# Needs a real (software) renderer: run it through .claude/hooks/render-keeper.sh,
# which wraps xvfb-run and the Compatibility backend. Writes .preview/keeper/.
#
# The keeper stands at the origin facing −Z, toward the camera's "front".

const TILE := Vector2i(360, 450)
const OUT_DIR: String = "res://.preview/keeper"

var _camera: Camera3D = null
var _keeper: Keeper = null
var _pose := KeeperPose.new()
var _frames: int = 0
var _views: Array = []
var _stances: Array = []


func _init() -> void:
	DisplayServer.window_set_size(TILE)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment = e
	root.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	light.shadow_enabled = true
	root.add_child(light)
	var ice := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	var ice_mat := StandardMaterial3D.new()
	ice_mat.albedo_color = Color(0.86, 0.90, 0.96)
	plane.material = ice_mat
	ice.mesh = plane
	root.add_child(ice)
	# The goal line and the posts, for scale.
	for x: float in [-GameRules.NET_HALF_WIDTH, GameRules.NET_HALF_WIDTH]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = GameRules.NET_POST_RADIUS
		cyl.bottom_radius = GameRules.NET_POST_RADIUS
		cyl.height = GameRules.NET_HEIGHT
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.8, 0.1, 0.1)
		cyl.material = red
		post.mesh = cyl
		post.position = Vector3(x, GameRules.NET_HEIGHT * 0.5, 0.35)
		root.add_child(post)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	_keeper = Keeper.new()
	_keeper.show_boxes = OS.get_environment("KEEPER_CAPTURE_BOXES") != "0"
	root.add_child(_keeper)
	_views = [
		["front", Vector3(0.0, 1.0, -4.2)],
		["side", Vector3(-4.2, 1.0, 0.0)],
		["34", Vector3(-2.9, 1.3, -3.0)],
	]
	_stances = [
		["upright", func(p: KeeperPose) -> void: KeeperPoses.upright(p)],
		["ready", func(p: KeeperPose) -> void: KeeperPoses.ready(p)],
		["butterfly", func(p: KeeperPose) -> void: KeeperPoses.butterfly(p)],
		["half_butterfly", func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, -1.0)],
		["extension", func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, -1.0)],
		["kick", func(p: KeeperPose) -> void: KeeperPoses.kick(p, 1.0)],
		["rvh", func(p: KeeperPose) -> void: KeeperPoses.rvh(p, -1.0)],
		["vh", func(p: KeeperPose) -> void: KeeperPoses.vh(p, -1.0)],
		["overlap", func(p: KeeperPose) -> void: KeeperPoses.overlap(p, -1.0)],
	]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))


var _shots: Array[Image] = []
var _fronts: Array[Image] = []
var _stance_i: int = 0
var _view_i: int = 0


func _process(_delta: float) -> bool:
	_frames += 1
	# Two frames to draw each shot: one to place, one to render.
	if _frames % 3 == 1:
		if _stance_i >= _stances.size():
			_save_sheet(_fronts, "all_front")
			return true
		var s: Array = _stances[_stance_i]
		(s[1] as Callable).call(_pose)
		_keeper.apply_pose(_pose)
		var v: Array = _views[_view_i]
		_camera.position = v[1]
		_camera.look_at(Vector3(0.0, 0.7, 0.0), Vector3.UP)
	elif _frames % 3 == 0:
		var img: Image = root.get_viewport().get_texture().get_image()
		_shots.append(img)
		if _view_i == 0:
			_fronts.append(img)
		_view_i += 1
		if _view_i >= _views.size():
			_save_sheet(_shots, String(_stances[_stance_i][0]))
			_shots = []
			_view_i = 0
			_stance_i += 1
	return false


func _save_sheet(imgs: Array[Image], name: String) -> void:
	if imgs.is_empty():
		return
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var cols: int = mini(imgs.size(), 5)
	var rows: int = ceili(float(imgs.size()) / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, imgs[0].get_format())
	for i: int in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	var path: String = ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	sheet.save_png(path)
	print("[keeper_capture] ", path)

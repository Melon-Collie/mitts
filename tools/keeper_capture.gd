extends SceneTree

# Renders the new keeper offscreen in every taught stance, from the front, the
# side and three-quarter, so his body can be SEEN without a game: each stance
# solved by KeeperSkeleton from KeeperPoses and drawn by the Keeper actor, with
# the save boxes overlaid (KEEPER_CAPTURE_BOXES=0 hides them). One contact sheet
# per stance — front, side, three-quarter, the shooter's view from the dot line,
# his back and the mouth as a shot straight on sees it (KeeperSeams: his body
# grey, where a puck cannot fit pale, its seams red) — plus one of every stance
# from the front. KEEPER_CAPTURE_STANCES names a
# comma-separated subset; KEEPER_CAPTURE_SCALE enlarges the tiles;
# KEEPER_CAPTURE_FOCUS names a KeeperGear part (MASK, BLOCKER...) to look at up
# close from the same directions; KEEPER_CAPTURE_TEAM picks the team slot whose kit
# he wears (KEEPER_CAPTURE_AWAY for its away kit).
#
# Needs a real (software) renderer: run it through .claude/hooks/render-keeper.sh,
# which wraps xvfb-run and the Compatibility backend. Writes .preview/keeper/.
#
# The keeper stands at the origin facing −Z, toward the camera's "front".

const BASE_TILE := Vector2i(360, 450)
const OUT_DIR: String = "res://.preview/keeper"
# From the dot line, 20 ft out: both posts and the crossbar in a portrait tile.
const SHOOTER_FOV_DEG: float = 28.0
# The goal line, behind the keeper's origin.
const POST_Z: float = 0.35
# A focused part fills about a third of the tile.
const FOCUS_DIST_PER_HALF: float = 6.0

var _camera: Camera3D = null
var _keeper: Keeper = null
var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()
var _frames: int = 0
var _views: Array = []
var _stances: Array = []
var _focus: int = KeeperGear.Part.keys().find(OS.get_environment("KEEPER_CAPTURE_FOCUS"))


func _init() -> void:
	var scale: float = maxf(OS.get_environment("KEEPER_CAPTURE_SCALE").to_float(), 1.0)
	DisplayServer.window_set_size(Vector2i(Vector2(BASE_TILE) * scale))
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
	plane.size = Vector2(20.0, 20.0)
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
		post.position = Vector3(x, GameRules.NET_HEIGHT * 0.5, POST_Z)
		root.add_child(post)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	# The camera jumps between views: interpolated, it is drawn partway along
	# the jump while its fov has already changed.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(_camera)
	_keeper = Keeper.new()
	_keeper.show_boxes = OS.get_environment("KEEPER_CAPTURE_BOXES") != "0"
	root.add_child(_keeper)
	var team: int = OS.get_environment("KEEPER_CAPTURE_TEAM").to_int()
	_keeper.apply_uniform(TeamColorRegistry.get_colors(team, 1 if OS.has_environment("KEEPER_CAPTURE_AWAY") else 0))
	_keeper.apply_jersey_info("Mitts", 31)
	_views = [
		["front", Vector3(0.0, 1.0, -4.2)],
		["side", Vector3(-4.2, 1.0, 0.0)],
		["34", Vector3(-2.9, 1.3, -3.0)],
		["shooter", Vector3(0.0, 1.4, -(GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z))],
		["back", Vector3(0.0, 1.0, 4.2)],
	]
	_stances = [
		["upright", func(p: KeeperPose) -> void: KeeperPoses.upright(p)],
		["ready", func(p: KeeperPose) -> void: KeeperPoses.ready(p)],
		["butterfly", func(p: KeeperPose) -> void: KeeperPoses.butterfly(p)],
	]
	# The one-sided stances, each named by the side its action is on.
	for side: float in [-1.0, 1.0]:
		var tag: String = "_glove" if side < 0.0 else "_blocker"
		_stances.append(["half_butterfly" + tag,
				func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, side)])
		_stances.append(["extension" + tag,
				func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, side)])
		_stances.append(["kick" + tag, func(p: KeeperPose) -> void: KeeperPoses.kick(p, side)])
		# The RVH is drawn on its post, as the brain will place it.
		_stances.append(["rvh" + tag, func(p: KeeperPose) -> void: KeeperPoses.rvh(p, side),
				side])
	var only: String = OS.get_environment("KEEPER_CAPTURE_STANCES")
	if not only.is_empty():
		var keep: PackedStringArray = only.split(",")
		_stances = _stances.filter(func(st: Array) -> bool: return String(st[0]) in keep)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))


var _shots: Array[Image] = []
var _fronts: Array[Image] = []
var _stance_i: int = 0
var _view_i: int = 0


func _process(_delta: float) -> bool:
	_frames += 1
	# Four frames a shot: one to place the camera, two to draw it (a changed fov
	# can land a frame late), one to read it back.
	if _frames % 4 == 1:
		if _stance_i >= _stances.size():
			_save_sheet(_fronts, "all_front")
			return true
		var s: Array = _stances[_stance_i]
		(s[1] as Callable).call(_pose)
		_keeper.apply_pose(_pose)
		var post: float = _post_side(s)
		_keeper.position = _on_post(post)
		_keeper.reset_physics_interpolation()
		var v: Array = _stance_views(post)[_view_i]
		var at: Vector3 = v[2] if v.size() > 2 else Vector3(0.0, 0.62, 0.0)
		_camera.position = v[1]
		_camera.fov = SHOOTER_FOV_DEG if v[0] == "shooter" else 40.0
		if _focus >= 0:
			_skel.pose(_pose)
			var part: Vector3 = _keeper.position + KeeperGear.box(_skel, _focus).origin
			var h: Vector3 = KeeperGear.half_extents(_focus)
			_camera.position = part + (v[1] - at).normalized() \
					* FOCUS_DIST_PER_HALF * maxf(h.x, maxf(h.y, h.z))
			_camera.fov = 40.0
			at = part
		_camera.look_at(at, Vector3.UP)
	elif _frames % 4 == 0:
		var img: Image = root.get_viewport().get_texture().get_image()
		_shots.append(img)
		if _view_i == 0:
			_fronts.append(img)
		_view_i += 1
		if _view_i >= _stance_views(_post_side(_stances[_stance_i])).size():
			if _focus < 0:
				_shots.append(_mouth_tile(img.get_width(), img.get_height(), img.get_format()))
			_save_sheet(_shots, String(_stances[_stance_i][0]))
			_shots = []
			_view_i = 0
			_stance_i += 1
	return false


static func _post_side(stance: Array) -> float:
	return float(stance[2]) if stance.size() > 2 else 0.0


# Where the keeper stands for a stance on `post`: KeeperGear.post_contact on the
# post's inner face, on the goal line; the origin off the post.
func _on_post(post: float) -> Vector3:
	if post == 0.0:
		return Vector3.ZERO
	_skel.pose(_pose)
	var c: Vector3 = KeeperGear.post_contact(_skel, post)
	return Vector3(post * (GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS) - c.x, 0.0,
			POST_Z - c.z)


# On a post, one more view: a shooter at a sharp angle from that side, 15° off
# the goal line, the shot the stance is for.
func _stance_views(post: float) -> Array:
	if _focus >= 0 or post == 0.0:
		return _views
	var at := Vector3(_keeper.position.x, 0.5, _keeper.position.z + 0.2)
	return _views + [["sharp", Vector3(post * 4.5, 0.9, POST_Z - 4.5 * tan(deg_to_rad(15.0))), at]]


const _MOUTH_COLORS: Array[Color] = [
	Color(0.97, 0.97, 0.98), Color(0.32, 0.34, 0.40), Color(0.78, 0.80, 0.84), Color(0.90, 0.12, 0.12),
]


# The mouth as a shot straight on sees him, cell by cell, fitted to a tile.
func _mouth_tile(w: int, h: int, format: Image.Format) -> Image:
	_skel.pose(_pose)
	var step: float = KeeperSeams.STEP_M
	var cells: PackedByteArray = KeeperSeams.classify(_skel, step)
	var nx: int = KeeperSeams.columns(step)
	var ny: int = KeeperSeams.rows(step)
	var mouth := Image.create(nx, ny, false, format)
	# Drawn from the shooter's side, as the front view is: his +X on the left.
	for j: int in ny:
		for i: int in nx:
			mouth.set_pixel(nx - 1 - i, ny - 1 - j, _MOUTH_COLORS[cells[j * nx + i]])
	var scale: float = minf(float(w) / float(nx), float(h) / float(ny))
	mouth.resize(int(nx * scale), int(ny * scale), Image.INTERPOLATE_NEAREST)
	var tile := Image.create(w, h, false, format)
	tile.fill(Color(0.10, 0.11, 0.14))
	tile.blit_rect(mouth, Rect2i(Vector2i.ZERO, mouth.get_size()),
			Vector2i((w - mouth.get_width()) / 2, (h - mouth.get_height()) / 2))
	return tile


func _save_sheet(imgs: Array[Image], name: String) -> void:
	if imgs.is_empty():
		return
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var cols: int = mini(imgs.size(), 7)
	var rows: int = ceili(float(imgs.size()) / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, imgs[0].get_format())
	for i: int in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	var path: String = ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	sheet.save_png(path)
	print("[keeper_capture] ", path)

extends SceneTree

# Renders the new keeper's moves as frame strips, so a move can be SEEN a tick
# at a time: KeeperFootwork stepped through a scripted move (or KeeperDrop
# down and back up, or a KeeperSlide) and drawn by the Keeper actor every few ticks, from the shooter's side, from
# behind and from high off his glove side in front. One sheet per scenario, a
# row per view, the frames left to right; a bar over each frame is its phase
# (PUSH green, GLIDE blue, STOP red, SET grey), and every frame's phase, place
# and speed are printed.
# KEEPER_STRIP_SCENARIOS names a comma-separated subset.
#
# Needs a real (software) renderer: run it through
# .claude/hooks/render-keeper-strip.sh. Writes .preview/keeper/strip_<name>.png.
#
# The keeper's line runs along X, he faces −Z, +X is his blocker side, +Z
# is back toward his net. A move in depth, or down, is seen from his glove side
# in place of behind.

const DT: float = 1.0 / 120.0
const FRAME_EVERY: int = 6
const TILE := Vector2i(220, 280)
const OUT_DIR: String = "res://.preview/keeper"
# The stop settling out of him, after he is set.
const SETTLE_FRAMES: int = 3
# name, the spot he moves to from 0, the move.
const SCENARIOS: Array = [
	["t_push", 1.0, KeeperFootwork.Move.T_PUSH],
	["t_push_far", 1.8, KeeperFootwork.Move.T_PUSH],
	["t_push_glove", -1.0, KeeperFootwork.Move.T_PUSH],
	["shuffle", 0.3, KeeperFootwork.Move.SHUFFLE],
	["shuffle_far", 1.0, KeeperFootwork.Move.SHUFFLE],
	["c_cut_back", 1.2, KeeperFootwork.Move.C_CUT],
	["c_cut_forward", -1.2, KeeperFootwork.Move.C_CUT],
	["drop_and_rise", 0.0, DROP_AND_RISE],
	["slide", 1.0, SLIDE],
	["slide_glove_far", -1.6, SLIDE],
]
# Not a footwork move: KeeperDrop down into the butterfly, held, and back up,
# a frame every DROP_FRAME_EVERY ticks since the whole drop is 24.
const DROP_AND_RISE: int = -1
# Not a footwork move either: KeeperSlide from the butterfly to the spot.
const SLIDE: int = -2
const DROP_FRAME_EVERY: int = 3
const DROP_HOLD_TICKS: int = 12
const _PHASE_COLORS: Array[Color] = [
	Color(0.55, 0.55, 0.58), Color(0.2, 0.8, 0.3), Color(0.25, 0.5, 0.95), Color(0.9, 0.2, 0.2),
]

var _camera: Camera3D = null
var _keeper: Keeper = null
var _views: Array = []
var _scenarios: Array = []
var _frames: Array = []
var _shots: Array[Image] = []
var _ticks: int = 0
var _scenario_i: int = -1
var _shot_i: int = 0


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
	plane.size = Vector2(20.0, 20.0)
	var ice_mat := StandardMaterial3D.new()
	ice_mat.albedo_color = Color(0.86, 0.90, 0.96)
	plane.material = ice_mat
	ice.mesh = plane
	root.add_child(ice)
	# A mark every half metre along his line, so his travel reads.
	for i: int in range(-4, 5):
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.02, 0.002, 0.3)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.1, 0.1) if i == 0 else Color(0.2, 0.3, 0.6)
		box.material = mat
		mark.mesh = box
		mark.position = Vector3(i * 0.5, 0.001, -0.6)
		root.add_child(mark)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(_camera)
	_keeper = Keeper.new()
	_keeper.show_boxes = false
	root.add_child(_keeper)
	_keeper.apply_uniform(TeamColorRegistry.get_colors(0, 0))
	_keeper.apply_jersey_info("Mitts", 31)
	_scenarios = SCENARIOS
	var only: String = OS.get_environment("KEEPER_STRIP_SCENARIOS")
	if not only.is_empty():
		var keep: PackedStringArray = only.split(",")
		_scenarios = _scenarios.filter(func(sc: Array) -> bool: return String(sc[0]) in keep)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))


# Each frame of a move: [pose, where, phase, speed, t].
func _record(target: float, kind: int) -> Array:
	if kind == DROP_AND_RISE:
		return _record_drop()
	if kind == SLIDE:
		return _record_slide(target)
	var fw := KeeperFootwork.new()
	match kind:
		KeeperFootwork.Move.T_PUSH:
			fw.push_to(target)
		KeeperFootwork.Move.SHUFFLE:
			fw.shuffle_to(target)
		KeeperFootwork.Move.C_CUT:
			fw.c_cut_to(target)
	var out: Array = []
	var tick: int = 0
	var settled: int = -1
	while settled < SETTLE_FRAMES * FRAME_EVERY:
		if tick % FRAME_EVERY == 0:
			var p := KeeperPose.new()
			fw.pose(p)
			out.append([p, Vector3(fw.x, 0.0, fw.z), fw.phase, fw.speed, tick * DT])
		fw.step(DT)
		tick += 1
		if fw.phase == KeeperFootwork.Phase.SET:
			settled += 1
	return out


# The drop's frames, as _record's, the phase column standing in for it: PUSH
# while he drops, GLIDE while he is down, STOP while he rises, SET up.
func _record_drop() -> Array:
	var drop := KeeperDrop.new()
	drop.drop()
	var out: Array = []
	var tick: int = 0
	var held: int = 0
	var up_frames: int = 0
	while up_frames < 2:
		if tick % DROP_FRAME_EVERY == 0:
			var p := KeeperPose.new()
			drop.pose(p)
			var phase: int = [KeeperFootwork.Phase.SET, KeeperFootwork.Phase.PUSH,
					KeeperFootwork.Phase.GLIDE, KeeperFootwork.Phase.STOP][drop.state]
			out.append([p, Vector3.ZERO, phase, drop.down, tick * DT])
			if drop.state == KeeperDrop.State.UP and tick > 0:
				up_frames += 1
		drop.step(DT)
		tick += 1
		if drop.state == KeeperDrop.State.DOWN:
			held += 1
			if held >= DROP_HOLD_TICKS:
				drop.rise()
	return out


# The slide's frames, as _record's: PUSH while the leg loads and drives, GLIDE
# while he slides, SET down on the spot.
func _record_slide(target: float) -> Array:
	var slide := KeeperSlide.new()
	slide.slide_to(target)
	var out: Array = []
	var tick: int = 0
	var settled: int = -1
	while settled < SETTLE_FRAMES * FRAME_EVERY:
		if tick % FRAME_EVERY == 0:
			var p := KeeperPose.new()
			slide.pose(p)
			var phase: int = [KeeperFootwork.Phase.SET, KeeperFootwork.Phase.PUSH,
					KeeperFootwork.Phase.PUSH, KeeperFootwork.Phase.GLIDE][slide.phase]
			out.append([p, Vector3(slide.x, 0.0, 0.0), phase, slide.speed, tick * DT])
		slide.step(DT)
		tick += 1
		if slide.phase == KeeperSlide.Phase.DOWN:
			settled += 1
	return out


# view name, camera offset from the middle of the move, look-at offset.
func _views_for(span: float, depth: bool) -> Array:
	var back: float = 2.6 + maxf(span, 1.0) * 0.9
	return [
		["shooter", Vector3(0.0, 1.0, -back), Vector3(0.0, 0.55, 0.0)],
		["side", Vector3(-back, 1.0, 0.0), Vector3(0.0, 0.55, 0.0)] if depth
				else ["behind", Vector3(0.0, 1.0, back), Vector3(0.0, 0.55, 0.0)],
		# High off his glove side in front: the skates' turn and the legs' depth.
		["high", Vector3(-1.6, 2.2, -back), Vector3(0.0, 0.5, 0.0)],
	]


func _process(_delta: float) -> bool:
	_ticks += 1
	if _scenario_i < 0 or _shot_i >= _frames.size() * _views.size():
		if _scenario_i >= 0:
			_save_sheet(String(_scenarios[_scenario_i][0]))
		_scenario_i += 1
		if _scenario_i >= _scenarios.size():
			return true
		var target: float = float(_scenarios[_scenario_i][1])
		var kind: int = int(_scenarios[_scenario_i][2])
		_frames = _record(target, kind)
		_views = _views_for(absf(target), kind != KeeperFootwork.Move.T_PUSH
				and kind != KeeperFootwork.Move.SHUFFLE)
		_shots = []
		_shot_i = 0
		_ticks = 0
		print("[keeper_strip] %s:" % _scenarios[_scenario_i][0])
		for f: Array in _frames:
			var at: Vector3 = f[1]
			print("  t %.3f  %-5s  x %+.3f  z %+.3f  v %.2f" % [f[4], KeeperFootwork.Phase.keys()[f[2]],
					at.x, at.z, f[3]])
		return false
	# Four frames a shot: place, two to draw, one to read back.
	var mid: Vector3 = (_frames[0][1] as Vector3).lerp(_frames[_frames.size() - 1][1] as Vector3, 0.5)
	var frame: Array = _frames[_shot_i % _frames.size()]
	var view: Array = _views[_shot_i / _frames.size()]
	if _ticks % 4 == 1:
		_keeper.apply_pose(frame[0] as KeeperPose)
		_keeper.position = frame[1] as Vector3
		_keeper.reset_physics_interpolation()
		_camera.position = mid + (view[1] as Vector3)
		_camera.look_at(mid + (view[2] as Vector3), Vector3.UP)
	elif _ticks % 4 == 0:
		var img: Image = root.get_viewport().get_texture().get_image()
		img.fill_rect(Rect2i(0, 0, img.get_width(), 6), _PHASE_COLORS[int(frame[2])])
		_shots.append(img)
		_shot_i += 1
	return false


func _save_sheet(name: String) -> void:
	if _shots.is_empty():
		return
	var w: int = _shots[0].get_width()
	var h: int = _shots[0].get_height()
	var cols: int = _frames.size()
	var sheet := Image.create(w * cols, h * _views.size(), false, _shots[0].get_format())
	for i: int in _shots.size():
		sheet.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	var path: String = ProjectSettings.globalize_path("%s/strip_%s.png" % [OUT_DIR, name])
	sheet.save_png(path)
	print("[keeper_strip] ", path)

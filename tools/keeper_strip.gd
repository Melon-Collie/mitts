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
# name, the spot he moves to from 0 (a T-push's may be a Vector2 off his
# line), the move.
const SCENARIOS: Array = [
	["t_push", 1.0, KeeperFootwork.Move.T_PUSH],
	["t_push_far", 1.8, KeeperFootwork.Move.T_PUSH],
	["t_push_glove", -1.0, KeeperFootwork.Move.T_PUSH],
	["t_push_diagonal_forward", Vector2(1.0, -0.7), KeeperFootwork.Move.T_PUSH],
	["t_push_diagonal_back_glove", Vector2(-1.0, 0.7), KeeperFootwork.Move.T_PUSH],
	["shuffle", 0.3, KeeperFootwork.Move.SHUFFLE],
	["shuffle_far", 1.0, KeeperFootwork.Move.SHUFFLE],
	["c_cut_back", 1.2, KeeperFootwork.Move.C_CUT],
	["c_cut_forward", -1.2, KeeperFootwork.Move.C_CUT],
	["drop_and_rise", 0.0, DROP_AND_RISE],
	["recover_blocker", 1.0, RECOVER],
	["recover_glove", -1.0, RECOVER],
	["slide", 1.0, SLIDE],
	["slide_glove_far", -1.6, SLIDE],
	["slide_from_feet", 1.0, SLIDE_FROM_FEET],
	["slide_from_feet_glove", -1.0, SLIDE_FROM_FEET],
	["slide_to_post", 1.0, SLIDE_TO_POST],
	["slide_to_post_glove", -1.0, SLIDE_TO_POST],
	["rvh_drop_in", 1.0, RVH_DROP_IN],
	["rvh_drop_in_glove", -1.0, RVH_DROP_IN],
	["rvh_from_slide", 1.0, RVH_FROM_SLIDE],
	["sequence", 0.0, SEQUENCE],
	["goals", 0.0, GOALS],
	["stick_reach", 0.0, STICK_REACH],
]
# Not a footwork move: KeeperDrop down into the butterfly, held, and back up,
# a frame every DROP_FRAME_EVERY ticks since the whole drop is 24.
const DROP_AND_RISE: int = -1
# The same drop, held, and the recovery toward the target's side instead of the
# rise.
const RECOVER: int = -7
# Not a footwork move either: KeeperSlide from the butterfly to the spot.
const SLIDE: int = -2
# KeeperSlide from his feet, by the half butterfly, a frame every
# DROP_FRAME_EVERY ticks for the drop's sake.
const SLIDE_FROM_FEET: int = -3
# KeeperSlide from the butterfly to the post on the target's side
# (KeeperSlide.post_spot), from the far side of the crease, with the posts
# drawn on the goal line behind him.
const SLIDE_TO_POST: int = -4
const POST_SLIDE_START := Vector2(0.6, -0.4)
# KeeperPost on the post on the target's side: dropped into the RVH from his
# feet on the overlap, held, and risen back out; or come up into it at the end
# of a slide there, held, and folded back into the butterfly. A frame every
# DROP_FRAME_EVERY ticks.
const RVH_DROP_IN: int = -5
const RVH_FROM_SLIDE: int = -6
const RVH_HOLD_TICKS: int = 18
# KeeperMotor through a whole sequence across the crease and back (turned to
# the puck, a T-push, down, a slide to the post, the RVH, back down, a recovery,
# a shuffle and a C-cut), a frame every SEQUENCE_FRAME_EVERY ticks from the
# shooter's side and high in front, the frames wrapped SHEET_WRAP to a row; the
# bar is his rest: on his feet green, down blue, on the post red.
const SEQUENCE: int = -8
# KeeperMotor given goals one after another (on his feet across and turned, a
# spot steeper than a diagonal, down across, sealed on the glove post, back on
# his feet in the middle), each given once he is at the last, making whatever
# moves KeeperRoute picks; drawn as SEQUENCE is.
const GOALS: int = -9
# The ready stance with its blade swept out past the blocker arm's reach (out
# in front, round to his blocker side and behind him), so the stick is seen
# brought to the hand: pivoting on its heel, sliding through the grip.
const STICK_REACH: int = -10
const STICK_SWEEP: Array[Vector3] = [
	KeeperPoses.READY_BLADE, Vector3(-0.2, 0.0, -1.3), Vector3(1.2, 0.0, -0.6), Vector3(0.6, 0.0, 0.6),
	KeeperPoses.READY_BLADE,
]
const STICK_SWEEP_FRAMES: int = 6
const SEQUENCE_FRAME_EVERY: int = 12
const SHEET_WRAP: int = 12
const GOAL_LINE_Z: float = 0.35
const DROP_FRAME_EVERY: int = 3
const DROP_HOLD_TICKS: int = 12
const _PHASE_COLORS: Array[Color] = [
	Color(0.55, 0.55, 0.58), Color(0.2, 0.8, 0.3), Color(0.25, 0.5, 0.95), Color(0.9, 0.2, 0.2),
]

var _camera: Camera3D = null
var _posts: Array[Node3D] = []
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
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = GameRules.NET_POST_RADIUS
		cyl.bottom_radius = GameRules.NET_POST_RADIUS
		cyl.height = GameRules.NET_HEIGHT
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.8, 0.1, 0.1)
		cyl.material = red
		post.mesh = cyl
		post.position = Vector3(side * GameRules.NET_HALF_WIDTH, GameRules.NET_HEIGHT * 0.5, GOAL_LINE_Z)
		post.visible = false
		root.add_child(post)
		_posts.append(post)
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


# Each frame of a move: [pose, where, phase, speed, t], and his turn if he
# turns.
func _record(spot: Vector2, kind: int) -> Array:
	var target: float = spot.x
	if kind == DROP_AND_RISE or kind == RECOVER:
		return _record_drop(target if kind == RECOVER else 0.0)
	if kind == SEQUENCE:
		return _record_sequence()
	if kind == GOALS:
		return _record_goals()
	if kind == STICK_REACH:
		return _record_stick_reach()
	if kind == RVH_DROP_IN or kind == RVH_FROM_SLIDE:
		return _record_post(target, kind == RVH_FROM_SLIDE)
	if kind == SLIDE or kind == SLIDE_FROM_FEET or kind == SLIDE_TO_POST:
		return _record_slide(target, kind == SLIDE_FROM_FEET, kind == SLIDE_TO_POST)
	var fw := KeeperFootwork.new()
	match kind:
		KeeperFootwork.Move.T_PUSH:
			fw.push_to(spot)
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
func _record_drop(toward: float) -> Array:
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
					KeeperFootwork.Phase.GLIDE, KeeperFootwork.Phase.STOP,
					KeeperFootwork.Phase.STOP][drop.state]
			out.append([p, Vector3.ZERO, phase, drop.down, tick * DT])
			if drop.state == KeeperDrop.State.UP and tick > 0:
				up_frames += 1
		drop.step(DT)
		tick += 1
		if drop.state == KeeperDrop.State.DOWN:
			held += 1
			if held >= DROP_HOLD_TICKS:
				if toward == 0.0:
					drop.rise()
				else:
					drop.recover(toward)
	return out


# The slide's frames, as _record's: PUSH while he drops or loads and drives,
# GLIDE while he slides, STOP while the lead edge stops him, SET down on the
# spot.
func _record_slide(target: float, from_feet: bool, to_post: bool) -> Array:
	var slide := KeeperSlide.new()
	var every: int = DROP_FRAME_EVERY if from_feet else FRAME_EVERY
	var spot := Vector2(target, 0.0)
	if to_post:
		var start := Vector2(-target * POST_SLIDE_START.x, POST_SLIDE_START.y)
		slide.x = start.x
		slide.z = start.y
		spot = slide.post_spot(Vector2(target * GameRules.NET_HALF_WIDTH, GOAL_LINE_Z), start)
	if from_feet:
		slide.slide_from_feet(spot)
	else:
		slide.slide_to(spot)
	var out: Array = []
	var tick: int = 0
	var settled: int = -1
	while settled < SETTLE_FRAMES * every:
		if tick % every == 0:
			var p := KeeperPose.new()
			slide.pose(p)
			var phase: int = [KeeperFootwork.Phase.SET, KeeperFootwork.Phase.PUSH,
					KeeperFootwork.Phase.PUSH, KeeperFootwork.Phase.PUSH, KeeperFootwork.Phase.GLIDE,
					KeeperFootwork.Phase.STOP][slide.phase]
			out.append([p, Vector3(slide.x, 0.0, slide.z), phase, slide.speed, tick * DT, slide.yaw])
		slide.step(DT)
		tick += 1
		if slide.phase == KeeperSlide.Phase.DOWN:
			settled += 1
	return out


func _record_sequence() -> Array:
	var motor := KeeperMotor.new()
	var iron := Vector2(GameRules.NET_HALF_WIDTH, GOAL_LINE_Z)
	motor.x = -0.3
	motor.z = -0.6
	motor.face(-0.25)
	motor.push_to(Vector2(-0.8, -0.6))
	motor.drop_down()
	motor.slide_to(motor.slide.post_spot(iron, Vector2(-0.8, -0.6)))
	motor.rvh_slide_in(iron, 1.0)
	motor.rvh_fold_out()
	motor.recover(-1.0)
	motor.face(0.0)
	motor.shuffle_to(Vector2(0.0, 0.0))
	motor.c_cut_to(Vector2(0.0, -0.6))
	var out: Array = []
	var tick: int = 0
	var idle: int = 0
	while idle < SETTLE_FRAMES * SEQUENCE_FRAME_EVERY:
		if tick % SEQUENCE_FRAME_EVERY == 0:
			var p := KeeperPose.new()
			motor.pose(p)
			var phase: int = [KeeperFootwork.Phase.PUSH, KeeperFootwork.Phase.GLIDE,
					KeeperFootwork.Phase.STOP][motor.rest]
			out.append([p, Vector3(motor.x, 0.0, motor.z), phase, 0.0, tick * DT, motor.yaw])
		motor.step(DT)
		tick += 1
		if motor.is_idle():
			idle += 1
	return out


func _record_stick_reach() -> Array:
	var out: Array = []
	for leg: int in STICK_SWEEP.size() - 1:
		for f: int in STICK_SWEEP_FRAMES:
			var p := KeeperPose.new()
			KeeperPoses.ready(p)
			p.blade_center = STICK_SWEEP[leg].lerp(STICK_SWEEP[leg + 1], float(f) / STICK_SWEEP_FRAMES)
			out.append([p, Vector3.ZERO, KeeperFootwork.Phase.SET, 0.0, out.size() * DT])
	return out


func _record_goals() -> Array:
	var motor := KeeperMotor.new()
	motor.z = -0.6
	var goals: Array = [
		[Vector2(-0.8, -0.5), -0.3, KeeperRoute.Rest.FEET], [Vector2(-0.4, -1.3), 0.0, KeeperRoute.Rest.FEET],
		[Vector2(0.7, -0.5), 0.0, KeeperRoute.Rest.DOWN], [Vector2(-GameRules.NET_HALF_WIDTH, GOAL_LINE_Z), -1.0, -1],
		[Vector2(0.0, -0.6), 0.0, KeeperRoute.Rest.FEET],
	]
	var out: Array = []
	var tick: int = 0
	var idle: int = 0
	var next: int = 0
	while next < goals.size() or idle < SETTLE_FRAMES * SEQUENCE_FRAME_EVERY:
		if motor.is_idle() and next < goals.size():
			var goal: Array = goals[next]
			if int(goal[2]) < 0:
				motor.seal(goal[0], goal[1])
			else:
				motor.go_to(goal[0], goal[1], goal[2])
			print("[keeper_strip] goal %d at t %.3f, planned %.3f s" % [next, tick * DT, motor.time_to_goal()])
			next += 1
			idle = 0
		if tick % SEQUENCE_FRAME_EVERY == 0:
			var p := KeeperPose.new()
			motor.pose(p)
			var phase: int = [KeeperFootwork.Phase.PUSH, KeeperFootwork.Phase.GLIDE,
					KeeperFootwork.Phase.STOP][motor.rest]
			out.append([p, Vector3(motor.x, 0.0, motor.z), phase, 0.0, tick * DT, motor.yaw])
		motor.step(DT)
		tick += 1
		if motor.is_idle():
			idle += 1
	return out


# The RVH's frames, as _record's: PUSH on the way in (and through the slide
# before it), GLIDE sealed, STOP on the way out, SET at rest.
func _record_post(post_side: float, from_slide: bool) -> Array:
	var post := Vector2(post_side * GameRules.NET_HALF_WIDTH, GOAL_LINE_Z)
	var out: Array = []
	var tick: int = 0
	var keeper := KeeperPost.new()
	if from_slide:
		var slide := KeeperSlide.new()
		var start := Vector2(-post_side * POST_SLIDE_START.x, POST_SLIDE_START.y)
		slide.x = start.x
		slide.z = start.y
		slide.slide_to(slide.post_spot(post, start))
		while slide.phase != KeeperSlide.Phase.DOWN or tick == 0:
			if tick % FRAME_EVERY == 0:
				var p := KeeperPose.new()
				slide.pose(p)
				out.append([p, Vector3(slide.x, 0.0, slide.z), KeeperFootwork.Phase.PUSH, slide.speed,
						tick * DT, slide.yaw])
			slide.step(DT)
			tick += 1
		keeper.x = slide.x
		keeper.z = slide.z
		keeper.yaw = slide.yaw
		keeper.state = KeeperPost.State.BUTTERFLY
		keeper.slide_in(post, post_side)
	else:
		var at: Vector2 = keeper.overlap_spot(post, post_side)
		keeper.x = at.x
		keeper.z = at.y
		keeper.drop_in(post, post_side)
	var held: int = 0
	var settled: int = 0
	var leaving: bool = false
	while settled < SETTLE_FRAMES * DROP_FRAME_EVERY:
		if tick % DROP_FRAME_EVERY == 0:
			var p := KeeperPose.new()
			keeper.pose(p)
			var phase: int = KeeperFootwork.Phase.GLIDE if keeper.state == KeeperPost.State.SEALED \
					else (KeeperFootwork.Phase.STOP if leaving else KeeperFootwork.Phase.PUSH)
			if leaving and (keeper.state == KeeperPost.State.STANDING or keeper.state == KeeperPost.State.BUTTERFLY):
				phase = KeeperFootwork.Phase.SET
			out.append([p, Vector3(keeper.x, 0.0, keeper.z), phase, 0.0, tick * DT, keeper.yaw])
		keeper.step(DT)
		tick += 1
		if keeper.state == KeeperPost.State.SEALED:
			held += 1
			if held >= RVH_HOLD_TICKS:
				leaving = true
				if from_slide:
					keeper.fold_out()
				else:
					keeper.rise_out()
		elif leaving and (keeper.state == KeeperPost.State.STANDING or keeper.state == KeeperPost.State.BUTTERFLY):
			settled += 1
	return out


# view name, camera offset from the middle of the move, look-at offset.
func _views_for(span: float, depth: bool) -> Array:
	var back: float = 2.6 + maxf(span, 1.0) * 1.3
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
		var to: Variant = _scenarios[_scenario_i][1]
		var spot: Vector2 = to if to is Vector2 else Vector2(float(to), 0.0)
		var target: float = spot.x
		var kind: int = int(_scenarios[_scenario_i][2])
		for post: Node3D in _posts:
			post.visible = kind == SLIDE_TO_POST or kind == RVH_DROP_IN or kind == RVH_FROM_SLIDE \
					or kind == SEQUENCE or kind == GOALS
		_frames = _record(spot, kind)
		_views = _views_for(absf(target), kind == KeeperFootwork.Move.C_CUT or kind == DROP_AND_RISE)
		if kind == SEQUENCE or kind == GOALS:
			_views = [_views[0], _views[2]]
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
		_keeper.rotation.y = float(frame[5]) if frame.size() > 5 else 0.0
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
	# A long move wraps: each view's frames run SHEET_WRAP to a row, the views'
	# blocks one under the other.
	var frames: int = _frames.size()
	var cols: int = mini(frames, SHEET_WRAP) if frames > 2 * SHEET_WRAP else frames
	var rows: int = ceili(float(frames) / float(cols))
	var sheet := Image.create(w * cols, h * rows * _views.size(), false, _shots[0].get_format())
	for i: int in _shots.size():
		var f: int = i % frames
		var row: int = (i / frames) * rows + f / cols
		sheet.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i((f % cols) * w, row * h))
	var path: String = ProjectSettings.globalize_path("%s/strip_%s.png" % [OUT_DIR, name])
	sheet.save_png(path)
	print("[keeper_strip] ", path)

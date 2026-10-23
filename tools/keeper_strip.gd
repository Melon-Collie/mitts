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
	["low_ready", 0.0, LOW_READY],
	["goals", 0.0, GOALS],
	["stick_reach", 0.0, STICK_REACH],
	["track", 0.0, TRACK],
	["save_glove", Vector2(-0.75, 0.95), SAVE],
	["save_blocker", Vector2(0.75, 0.95), SAVE],
	["save_low_glove", Vector2(-0.75, 0.15), SAVE],
	["save_ice_blocker", Vector2(0.65, 0.0), SAVE],
	["save_five_hole", Vector2(-0.05, 0.0), SAVE],
	["save_five_hole_far", Vector2(-0.05, 0.0), SAVE_FAR],
	["cover", 0.0, COVER],
	["save_tight_low", Vector2(0.2, 0.0), SAVE_TIGHT],
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
# KeeperMotor set and sinking into the low ready (KeeperLowReady), out of it
# into a T-push, sinking again where it sets him, and dropping from it; a frame
# every LOW_READY_FRAME_EVERY ticks, the bar green on the move, blue sunk past
# halfway, red down, grey standing.
const LOW_READY: int = -14
const LOW_READY_FRAME_EVERY: int = 4
const LOW_READY_HOLD_S: float = 0.4
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
# KeeperPositioning deciding at the planner's rate from a puck carried round
# the zone by one of theirs (TRACK_PATH, in the net's frame at TRACK_SPEED),
# KeeperMotor moving him there; the puck drawn, the bar his rest as
# SEQUENCE's, the printed column how far he has sunk into the low ready.
const TRACK: int = -11
const TRACK_PATH: Array[Vector2] = [
	Vector2(-3.0, -22.0), Vector2(0.0, -9.0), Vector2(8.0, -6.0), Vector2(6.0, -1.5), Vector2(3.0, 1.5),
	Vector2(-0.3, 1.8), Vector2(-4.0, 1.2), Vector2(-5.0, -3.0), Vector2(-2.0, -8.0),
]
const TRACK_SPEED: float = 4.0
# A shot at him set at the top of the crease, read and saved as in a match
# (KeeperShotRead, KeeperSave, the motor's low save): from the slot, or (TIGHT)
# from the top of the circles' hash marks in, faster, where the drops win; to
# where it would cross the goal line (x across, height; 0 along the ice).
const SAVE: int = -12
const SAVE_TIGHT: int = -13
# From the high slot, where he has the time to drop for a low shot.
const SAVE_FAR: int = -15
const SAVE_FAR_FROM_Z: float = -14.0
# A puck dribbling in to die at his feet, covered (KeeperCover, the motor's
# drop and the save's glove): from COVER_FROM_M ahead of him at COVER_M_S. The
# bar PUSH while he goes for it, STOP once the glove is on it.
const COVER: int = -16
const COVER_FROM_M: float = 1.1
const COVER_M_S: float = 0.9
const SAVE_FROM_Z: float = -9.0
const SAVE_TIGHT_FROM_Z: float = -4.5
const SAVE_SPEED: float = 22.0
const SAVE_TIGHT_SPEED: float = 26.0
const SAVE_KEEPER_Z: float = -1.3
const SAVE_FRAME_EVERY: int = 3
const SAVE_HOLD_S: float = 0.25
const PLANNER_EVERY: int = 4
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
var _puck: MeshInstance3D = null
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
	_puck = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = GameRules.PUCK_COLLISION_RADIUS
	disc.bottom_radius = disc.top_radius
	disc.height = 0.025
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.02, 0.02, 0.02)
	disc.material = black
	_puck.mesh = disc
	_puck.visible = false
	root.add_child(_puck)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(_camera)
	_keeper = Keeper.new()
	_keeper.show_boxes = false
	root.add_child(_keeper)
	_keeper.set_process(false)
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
	if kind == COVER:
		return _record_cover()
	if kind == LOW_READY:
		return _record_low_ready()
	if kind == GOALS:
		return _record_goals()
	if kind == STICK_REACH:
		return _record_stick_reach()
	if kind == TRACK:
		return _record_track()
	if kind == SAVE or kind == SAVE_TIGHT or kind == SAVE_FAR:
		var from_z: float = SAVE_TIGHT_FROM_Z if kind == SAVE_TIGHT else (SAVE_FAR_FROM_Z if kind == SAVE_FAR else SAVE_FROM_Z)
		return _record_save(spot, from_z, SAVE_TIGHT_SPEED if kind == SAVE_TIGHT else SAVE_SPEED)
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


func _record_low_ready() -> Array:
	var motor := KeeperMotor.new()
	motor.low_ready.asked = true
	var out: Array = []
	var tick: int = 0
	var set_s: float = 0.0
	var pushed: bool = false
	var down_s: float = -1.0
	while down_s < LOW_READY_HOLD_S * 0.5:
		if tick % LOW_READY_FRAME_EVERY == 0:
			var p := KeeperPose.new()
			motor.pose(p)
			var phase: int = KeeperFootwork.Phase.SET
			if motor.rest == KeeperRoute.Rest.DOWN:
				phase = KeeperFootwork.Phase.STOP
			elif not motor.is_idle():
				phase = KeeperFootwork.Phase.PUSH
			elif motor.low_ready.share > 0.5:
				phase = KeeperFootwork.Phase.GLIDE
			out.append([p, Vector3(motor.x, 0.0, motor.z), phase, motor.low_ready.share, tick * DT, motor.yaw])
		motor.step(DT)
		tick += 1
		if down_s >= 0.0:
			down_s += DT
		elif motor.rest == KeeperRoute.Rest.DOWN:
			down_s = 0.0
		elif motor.is_idle():
			set_s += DT
			if set_s >= LOW_READY_HOLD_S:
				set_s = 0.0
				if pushed:
					motor.drop_down()
				else:
					motor.push_to(Vector2(1.0, 0.0))
					pushed = true
	return out


func _record_track() -> Array:
	var motor := KeeperMotor.new()
	var brain := KeeperPositioning.new()
	# Carried by one of theirs: set close enough in, he sinks into the low ready.
	brain.play = KeeperPlayRead.new()
	brain.play.theirs = true
	var out: Array = []
	var tick: int = 0
	var leg: int = 0
	var puck: Vector2 = TRACK_PATH[0]
	var still: int = 0
	var zone: int = -1
	while still < SETTLE_FRAMES * SEQUENCE_FRAME_EVERY:
		var velocity := Vector2.ZERO
		if leg < TRACK_PATH.size() - 1:
			var to: Vector2 = TRACK_PATH[leg + 1]
			velocity = (to - puck).normalized() * TRACK_SPEED
			puck = puck.move_toward(to, TRACK_SPEED * DT)
			if puck == to:
				leg += 1
		elif motor.is_idle():
			still += 1
		if tick % PLANNER_EVERY == 0:
			brain.decide(puck, velocity, motor)
			if brain.zone != zone:
				zone = brain.zone
				print("[keeper_strip] t %.2f zone %s" % [tick * DT, KeeperPositioning.Zone.keys()[zone]])
		if tick % SEQUENCE_FRAME_EVERY == 0:
			var p := KeeperPose.new()
			motor.pose(p)
			var phase: int = [KeeperFootwork.Phase.PUSH, KeeperFootwork.Phase.GLIDE,
					KeeperFootwork.Phase.STOP][motor.rest]
			out.append([p, Vector3(motor.x, 0.0, motor.z + GOAL_LINE_Z), phase, motor.low_ready.share, tick * DT,
					motor.yaw, Vector3(puck.x, 0.0, puck.y + GOAL_LINE_Z)])
		motor.step(DT)
		tick += 1
	print("[keeper_strip] refused %d" % motor.refused)
	return out


# The shot's frames: his pose and place, the puck where it is (by its centre,
# less the lift the playback adds); the phase bar PUSH once he has chosen his
# save, STOP once it is over.
func _record_save(to: Vector2, from_z: float, speed: float) -> Array:
	var motor := KeeperMotor.new()
	motor.z = SAVE_KEEPER_Z
	var read := KeeperShotRead.new()
	var save := KeeperSave.new()
	var on_ice: bool = to.y <= 0.0
	var at_line := Vector3(to.x, KeeperShotRead.ON_ICE_Y if on_ice else to.y, 0.0)
	var puck := Vector3(0.0, KeeperShotRead.ON_ICE_Y if on_ice else 0.3, from_z)
	var flight: float = puck.distance_to(at_line) / speed
	var v: Vector3 = (at_line - puck) / flight
	if not on_ice:
		v.y += 0.5 * GameRules.GRAVITY_M_S2 * flight
	read.step(0.0, puck, v)
	read.start()
	var out: Array = []
	var tick: int = 0
	var chosen: bool = false
	var over_at: float = INF
	var p := KeeperPose.new()
	while tick * DT < flight + SAVE_HOLD_S + 0.5:
		var t: float = tick * DT
		if t < flight:
			puck += v * DT
			if not on_ice:
				v.y -= GameRules.GRAVITY_M_S2 * DT
			read.step(DT, puck, v)
		if not chosen and read.legs_read():
			chosen = true
			save.choose(read, motor, false)
			print("[keeper_strip] save %s low %s hand %s covers %s ready %.3f impact %.3f" % [to,
					KeeperSaveMove.Low.keys()[save.low], KeeperSave.Hand.keys()[save.hand], save.covers,
					save.ready_s, save.impact_s])
			if save.low != KeeperSaveMove.Low.NONE:
				motor.save(save.low, save.low_side)
		if over_at == INF and t >= flight + SAVE_HOLD_S:
			over_at = t
			save.release()
			motor.end_save()
		motor.step(DT)
		motor.pose(p)
		save.step(DT, read.arms_read(), p)
		if tick % SAVE_FRAME_EVERY == 0:
			var framed := KeeperPose.new()
			framed.copy_from(p)
			save.overlay(framed)
			var phase: int = KeeperFootwork.Phase.SET
			if t >= over_at:
				phase = KeeperFootwork.Phase.STOP
			elif chosen:
				phase = KeeperFootwork.Phase.PUSH
			out.append([framed, Vector3(motor.x, 0.0, motor.z + GOAL_LINE_Z), phase, 0.0, t, motor.yaw,
					Vector3(puck.x, puck.y - KeeperShotRead.ON_ICE_Y, puck.z + GOAL_LINE_Z)])
		tick += 1
	return out


func _record_cover() -> Array:
	var motor := KeeperMotor.new()
	motor.z = SAVE_KEEPER_Z
	var cover := KeeperCover.new()
	var save := KeeperSave.new()
	var puck := Vector3(-0.25, KeeperShotRead.ON_ICE_Y, SAVE_KEEPER_Z - COVER_FROM_M)
	var v := Vector3(0.0, 0.0, COVER_M_S)
	var covering: bool = false
	var secured: bool = false
	var out: Array = []
	var p := KeeperPose.new()
	var tick: int = 0
	while tick * DT < 1.6:
		var t: float = tick * DT
		if not secured:
			puck = KeeperCover.slid(puck, v, DT)
			v = v.normalized() * maxf(v.length() - GameRules.PUCK_ICE_DECEL_M_S2 * DT, 0.0)
			if cover.plan(puck, v, motor, false):
				if not covering:
					covering = true
					motor.save(KeeperSaveMove.Low.BUTTERFLY, signf(cover.target.x))
				save.cover(cover.target, cover.lean)
		motor.step(DT)
		motor.pose(p)
		save.step(DT, false, p)
		var in_him := Vector3(puck.x - motor.x, puck.y, puck.z - motor.z)
		if covering and not secured and save.hand_there() \
				and Vector2(cover.target.x - in_him.x, cover.target.z - in_him.z).length() <= KeeperCover.PIN_M:
			secured = true
			print("[keeper_strip] cover secured at t %.3f" % t)
		if tick % SAVE_FRAME_EVERY == 0:
			var framed := KeeperPose.new()
			framed.copy_from(p)
			save.overlay(framed)
			var phase: int = KeeperFootwork.Phase.SET
			if secured:
				phase = KeeperFootwork.Phase.STOP
			elif covering:
				phase = KeeperFootwork.Phase.PUSH
			out.append([framed, Vector3(motor.x, 0.0, motor.z + GOAL_LINE_Z), phase, v.length(), t, motor.yaw,
					Vector3(puck.x, puck.y - KeeperShotRead.ON_ICE_Y, puck.z + GOAL_LINE_Z)])
		tick += 1
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
					or kind == SEQUENCE or kind == GOALS or kind == TRACK or kind == SAVE or kind == SAVE_TIGHT \
					or kind == SAVE_FAR or kind == COVER
		_frames = _record(spot, kind)
		_views = _views_for(absf(target), kind == KeeperFootwork.Move.C_CUT or kind == DROP_AND_RISE)
		if kind == SEQUENCE or kind == GOALS or kind == TRACK or kind == SAVE or kind == SAVE_TIGHT or kind == SAVE_FAR \
				or kind == COVER:
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
		_keeper.draw_now()
		_swing_cloth(_shot_i % _frames.size())
		_keeper.position = frame[1] as Vector3
		_keeper.rotation.y = float(frame[5]) if frame.size() > 5 else 0.0
		_puck.visible = frame.size() > 6
		if _puck.visible:
			_puck.position = (frame[6] as Vector3) + Vector3(0.0, 0.0125, 0.0)
		_keeper.reset_physics_interpolation()
		_camera.position = mid + (view[1] as Vector3)
		_camera.look_at(mid + (view[2] as Vector3), Vector3.UP)
	elif _ticks % 4 == 0:
		var img: Image = root.get_viewport().get_texture().get_image()
		img.fill_rect(Rect2i(0, 0, img.get_width(), 6), _PHASE_COLORS[int(frame[2])])
		_shots.append(img)
		_shot_i += 1
	return false


# The jersey's tail on frame `i`: settled on the first, then a frame's time on
# from the last, against his acceleration over the recorded places.
func _swing_cloth(i: int) -> void:
	if i == 0:
		_keeper.acceleration = Vector3.ZERO
		for k: int in KeeperJerseyTail.SETTLE_STEPS:
			_keeper.step_cloth(1.0 / 60.0, k == KeeperJerseyTail.SETTLE_STEPS - 1)
		return
	var frame_dt: float = FRAME_EVERY * DT
	var a := Vector3.ZERO
	if i >= 2:
		var p0: Vector3 = _frames[i - 2][1]
		var p1: Vector3 = _frames[i - 1][1]
		var p2: Vector3 = _frames[i][1]
		var turn: float = float(_frames[i][5]) if _frames[i].size() > 5 else 0.0
		a = Basis(Vector3.UP, -turn) * ((p2 - 2.0 * p1 + p0) / (frame_dt * frame_dt))
	_keeper.acceleration = a
	# Two steps a frame: one would pass the cloth's longest step.
	_keeper.step_cloth(frame_dt * 0.5, false)
	_keeper.step_cloth(frame_dt * 0.5, true)


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

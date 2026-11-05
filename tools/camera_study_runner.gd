extends Node

# The work behind tools/camera_study.gd.
#
# Every study setup frames the same instant around the puck carrier, with
# the carrier's attack direction up the screen. A setup names a pitch (degrees
# below horizontal), a vertical FOV, and a scale: the carrier's ice scale in
# pixels per lateral metre, as a multiple of the live GameCamera's at that
# instant. Equal scale means equal stickhandling resolution at the puck, so the
# grid isolates what angle and FOV change; `carrier_y` is where on screen (0 top,
# 1 bottom) the carrier sits, which sets how much ice shows ahead.

const _SETUPS: Array[Dictionary] = [
	{"name": "p75_f50", "pitch": 75.0, "fov": 50.0, "scale": 1.0},
	{"name": "p65_f50", "pitch": 65.0, "fov": 50.0, "scale": 1.0},
	{"name": "p55_f50", "pitch": 55.0, "fov": 50.0, "scale": 1.0},
	{"name": "p45_f50", "pitch": 45.0, "fov": 50.0, "scale": 1.0},
	{"name": "p35_f50", "pitch": 35.0, "fov": 50.0, "scale": 1.0},
	{"name": "p65_f65", "pitch": 65.0, "fov": 65.0, "scale": 1.0},
	{"name": "p55_f65", "pitch": 55.0, "fov": 65.0, "scale": 1.0},
	{"name": "p45_f65", "pitch": 45.0, "fov": 65.0, "scale": 1.0},
	{"name": "p35_f65", "pitch": 35.0, "fov": 65.0, "scale": 1.0},
	{"name": "p55_f80", "pitch": 55.0, "fov": 80.0, "scale": 1.0},
	{"name": "p45_f80", "pitch": 45.0, "fov": 80.0, "scale": 1.0},
	{"name": "p35_f80", "pitch": 35.0, "fov": 80.0, "scale": 1.0},
	{"name": "close_p65_f60", "pitch": 65.0, "fov": 60.0, "scale": 1.5},
	{"name": "close_p55_f60", "pitch": 55.0, "fov": 60.0, "scale": 1.5},
	{"name": "close_p45_f60", "pitch": 45.0, "fov": 60.0, "scale": 1.5},
	{"name": "close_p35_f60", "pitch": 35.0, "fov": 60.0, "scale": 1.5},
	{"name": "chase", "chase": true, "fov": 50.0},
]

const _CARRIER_Y: float = 0.68
# ChaseCamera's spectator follow, for reference.
const _CHASE_BEHIND: float = 5.5
const _CHASE_HEIGHT: float = 2.5
const _CHASE_LOOK_AHEAD: float = 3.0
const _CHASE_LOOK_HEIGHT: float = 1.0

# The sim runs without drawing until the moment is found, as fast as it will go.
const _STEPS_PER_FRAME: int = 60
const _WARMUP_TIME_SCALE: float = 8.0
const _UNDRAWN_MAX_FPS: int = 240
const _HUNT_TIME_SCALE: float = 2.0
# Frames the study viewports draw before the capture, so the first draw's
# shader compiles are behind them.
const _DRAW_FRAMES: int = 2
const _CATCH_UP_FRAMES: int = 6
const _MOMENT_ATTEMPTS: int = 8
const _START_TIMEOUT_FRAMES: int = 2400
const _WARMUP_SEC: float = 4.0
const _HUNT_TIMEOUT_SEC: float = 90.0
# A carry worth framing: moving with the puck, up-ice, out of the end zones.
const _MIN_CARRY_SPEED: float = 4.0
const _MAX_CARRY_ABS_Z: float = 9.0
const _MAX_CARRY_ABS_X: float = 9.0
const _LIVE_SETTLE_STEPS: int = 80
const _LIVE_SETTLE_DT: float = 0.1
const _RING_RADII: Array[float] = [1.0, 2.0]
const _RING_SEGMENTS: int = 64

var _out_dir: String = ""
var _metrics: Array[Dictionary] = []


func begin(only: String, out_dir: String, list_only: bool) -> void:
	if list_only:
		for s: Dictionary in _SETUPS:
			print(s.name)
		get_tree().quit()
		return
	_out_dir = out_dir
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var setups: Array[Dictionary] = []
	for s: Dictionary in _SETUPS:
		if only.is_empty() or only.split(",").has(s.name):
			setups.append(s)
	# The study cameras frame skaters the live camera may not; with culling off
	# every skater is posed every frame (SkaterAnimationLod reads distance -1).
	SkaterCameraCull.enabled = false
	PlayerPrefs.attack_up = true
	PlayerPrefs.camera_mode = PlayerPrefs.CAMERA_MODE_DYNAMIC
	if not await _start_match():
		get_tree().quit(1)
		return
	var carrier: Skater = await _find_moment()
	if carrier == null:
		push_error("[camera-study] nobody carried the puck through open ice")
		get_tree().quit(1)
		return
	var live: GameCamera = _find(get_tree().current_scene, GameCamera) as GameCamera
	var team_id: int = _team_of(carrier)
	live.skater = carrier
	live.set_local_team_id(team_id)
	for i: int in _LIVE_SETTLE_STEPS:
		live.call("_process", _LIVE_SETTLE_DT)
	var attack_dir: int = live.call("_get_attacking_direction")
	if attack_dir == 0:
		attack_dir = 1 if team_id == 1 else -1
	var carrier_pos: Vector3 = carrier.global_position
	carrier_pos.y = 0.0
	_add_rings(carrier_pos)
	var ref_scale: float = _lateral_px_per_m(live, carrier_pos)

	# One SubViewport a setup, all sharing the match's world and drawn in the
	# same frame, so every shot is the same instant with the match running at
	# normal speed (the rigs pose on render-rate deltas; a frozen clock starves
	# them). No HUD: that lives on the main viewport's canvas.
	var size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	var live_setup: Dictionary = {"name": "live", "pitch": -live.rotation_degrees.x,
			"fov": live.fov, "scale": 1.0}
	var all: Array[Dictionary] = [live_setup]
	all.append_array(setups)
	var views: Array[SubViewport] = []
	var cams: Array[Camera3D] = []
	for s: Dictionary in all:
		var vp := SubViewport.new()
		vp.size = size
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.cull_mask = live.cull_mask
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		cam.fov = s.fov
		vp.add_child(cam)
		add_child(vp)
		if s.name == "live":
			cam.global_transform = live.global_transform
		elif s.get("chase", false):
			_place_chase(cam, carrier)
		else:
			_place_study(cam, carrier_pos, attack_dir, s.pitch, s.fov, s.scale * ref_scale)
		cam.make_current()
		views.append(vp)
		cams.append(cam)
	for i: int in _DRAW_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_diagnose()
	for i: int in all.size():
		_save(all[i], views[i], cams[i], carrier_pos, attack_dir)
		views[i].render_target_update_mode = SubViewport.UPDATE_DISABLED

	var f := FileAccess.open(_out_dir.path_join("metrics.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"carrier_speed": Vector2(carrier.velocity.x,
			carrier.velocity.z).length(), "carrier_pos": [carrier_pos.x, carrier_pos.z],
			"attack_dir": attack_dir, "ref_px_per_m": ref_scale,
			"viewport": [get_viewport().get_visible_rect().size.x,
					get_viewport().get_visible_rect().size.y],
			"shots": _metrics}, "  "))
	f.close()
	get_tree().quit(0)


func _start_match() -> bool:
	var tree: SceneTree = get_tree()
	NetworkManager.start_offline()
	tree.change_scene_to_file(Constants.SCENE_LOBBY)
	while tree.current_scene == null \
			or tree.current_scene.scene_file_path != Constants.SCENE_LOBBY:
		await tree.process_frame
	await tree.process_frame
	var lobby: LobbyManager = _find(tree.current_scene, LobbyManager) as LobbyManager
	lobby.call("_fill_open_slots_with_bots")
	lobby.call("_on_start_pressed")
	RenderingServer.render_loop_enabled = false
	# Undrawn frames otherwise run at thousands of fps, and a near-zero
	# render-rate delta leaves NaN in the bots' skeleton poses.
	Engine.max_fps = _UNDRAWN_MAX_FPS
	Engine.max_physics_steps_per_frame = _STEPS_PER_FRAME
	Engine.time_scale = _WARMUP_TIME_SCALE
	var waited: int = 0
	while tree.current_scene == null \
			or tree.current_scene.scene_file_path != Constants.SCENE_HOCKEY \
			or GameManager.is_movement_locked():
		await tree.process_frame
		waited += 1
		if waited > _START_TIMEOUT_FRAMES:
			push_error("[camera-study] the match never left the opening faceoff")
			return false
	var target: int = Engine.get_physics_frames() \
			+ int(_WARMUP_SEC * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < target:
		await tree.process_frame
	return true


# A carry that survives the catch-up: a few drawn ticks, because with the render
# loop off the interpolated transforms and the render-rate rigs never caught up
# with the sim, and a carry that ends in them is no carry to frame.
func _find_moment() -> Skater:
	for attempt: int in _MOMENT_ATTEMPTS:
		var carrier: Skater = await _hunt_carry()
		if carrier == null:
			return null
		RenderingServer.render_loop_enabled = true
		Engine.time_scale = 1.0
		Engine.max_physics_steps_per_frame = 1
		for i: int in _CATCH_UP_FRAMES:
			await get_tree().process_frame
		if GameManager.puck.carrier == carrier:
			return carrier
		print("[camera-study] the carry ended during catch-up; hunting again")
	return null


func _hunt_carry() -> Skater:
	var tree: SceneTree = get_tree()
	var deadline: int = Engine.get_physics_frames() \
			+ int(_HUNT_TIMEOUT_SEC * Engine.physics_ticks_per_second)
	var live: GameCamera = _find(tree.current_scene, GameCamera) as GameCamera
	RenderingServer.render_loop_enabled = false
	Engine.max_physics_steps_per_frame = 4
	Engine.time_scale = _HUNT_TIME_SCALE
	while Engine.get_physics_frames() < deadline:
		await tree.process_frame
		var puck: Puck = GameManager.puck
		if puck == null or puck.carrier == null or GameManager.is_movement_locked():
			continue
		var c: Skater = puck.carrier
		var v: Vector2 = Vector2(c.velocity.x, c.velocity.z)
		var dir: int = live.call("_get_attacking_direction")
		if v.length() >= _MIN_CARRY_SPEED and absf(c.global_position.z) <= _MAX_CARRY_ABS_Z \
				and absf(c.global_position.x) <= _MAX_CARRY_ABS_X \
				and c.velocity.z * float(dir) > 0.5 * v.length():
			print("[camera-study] carrier at (%.1f, %.1f) %.1f m/s" % [
					c.global_position.x, c.global_position.z, v.length()])
			return c
	return null


func _team_of(skater: Skater) -> int:
	var registry: PlayerRegistry = GameManager.get("_registry") as PlayerRegistry
	var team: Team = registry.resolve_team(skater)
	return team.team_id if team != null else 0


# The carrier at screen height _CARRIER_Y and camera-space depth chosen so a
# lateral metre at the carrier spans `px_per_m` pixels.
func _place_study(cam: Camera3D, carrier: Vector3, attack_dir: int, pitch_deg: float,
		fov_deg: float, px_per_m: float) -> void:
	var half_h: float = get_viewport().get_visible_rect().size.y * 0.5
	var tan_half: float = tan(deg_to_rad(fov_deg) * 0.5)
	var depth: float = half_h / (tan_half * px_per_m)
	var below_axis: float = atan((_CARRIER_Y - 0.5) * 2.0 * tan_half)
	var ray_down: float = deg_to_rad(pitch_deg) + below_axis
	var ray_len: float = depth / cos(below_axis)
	var fwd: Vector3 = Vector3(0.0, 0.0, float(attack_dir))
	cam.global_position = carrier - fwd * cos(ray_down) * ray_len \
			+ Vector3.UP * sin(ray_down) * ray_len
	var pitch: float = deg_to_rad(pitch_deg)
	var look: Vector3 = fwd * cos(pitch) - Vector3.UP * sin(pitch)
	cam.look_at(cam.global_position + look, fwd if pitch_deg > 89.0 else Vector3.UP)


func _place_chase(cam: Camera3D, carrier: Skater) -> void:
	var f2: Vector2 = carrier.get_facing().normalized()
	var facing: Vector3 = Vector3(f2.x, 0.0, f2.y)
	var base: Vector3 = Vector3(carrier.global_position.x, 0.0, carrier.global_position.z)
	cam.global_position = base - facing * _CHASE_BEHIND + Vector3.UP * _CHASE_HEIGHT
	cam.look_at(base + facing * _CHASE_LOOK_AHEAD + Vector3.UP * _CHASE_LOOK_HEIGHT, Vector3.UP)


func _save(setup: Dictionary, vp: SubViewport, cam: Camera3D, carrier: Vector3,
		attack_dir: int) -> void:
	var path: String = _out_dir.path_join(String(setup.name) + ".png")
	vp.get_texture().get_image().save_png(path)
	var m: Dictionary = _measure(cam, carrier, attack_dir)
	m["name"] = setup.name
	m["pitch"] = setup.get("pitch", -1.0)
	m["fov"] = setup.fov
	m["scale"] = setup.get("scale", -1.0)
	_metrics.append(m)
	print("[camera-study] %s -> %s  %s" % [setup.name, ProjectSettings.globalize_path(path),
			JSON.stringify(m)])


func _lateral_px_per_m(cam: Camera3D, p: Vector3) -> float:
	var right: Vector3 = cam.global_basis.x
	right.y = 0.0
	right = right.normalized() * 0.5
	return cam.unproject_position(p + right).distance_to(cam.unproject_position(p - right))


# What the setup does to stickhandling and to vision, measured off the camera:
# - lateral / depth px per metre at the carrier (their ratio is the
#   foreshortening: how much more ice a vertical mouse inch covers);
# - depth px per metre a reach in front of vs behind the carrier (how unevenly
#   the stickhandling circle is drawn);
# - how far up-ice the top of the screen reaches, or where the horizon sits.
func _measure(cam: Camera3D, carrier: Vector3, attack_dir: int) -> Dictionary:
	var size: Vector2 = Vector2(cam.get_viewport().get_visible_rect().size)
	var fwd: Vector3 = Vector3(0.0, 0.0, float(attack_dir))
	var lat: float = _lateral_px_per_m(cam, carrier)
	var depth_at: Callable = func(p: Vector3) -> float:
		return cam.unproject_position(p + fwd * 0.5).distance_to(
				cam.unproject_position(p - fwd * 0.5))
	var dep: float = depth_at.call(carrier)
	var reach: float = 1.5
	var far_d: float = depth_at.call(carrier + fwd * reach)
	var near_d: float = depth_at.call(carrier - fwd * reach)
	var ahead: float = -1.0
	var top_dir: Vector3 = cam.project_ray_normal(Vector2(size.x * 0.5, 0.0))
	var top_org: Vector3 = cam.project_ray_origin(Vector2(size.x * 0.5, 0.0))
	if top_dir.y < -0.001:
		var hit: Vector3 = top_org + top_dir * (-top_org.y / top_dir.y)
		ahead = (hit - carrier).dot(fwd)
	var horizon_y: float = -1.0
	var horizon_pt: Vector3 = cam.global_position + fwd * 10000.0
	horizon_pt.y = cam.global_position.y
	if not cam.is_position_behind(horizon_pt):
		var hy: float = cam.unproject_position(horizon_pt).y
		if hy >= 0.0 and hy <= size.y:
			horizon_y = hy / size.y
	var left_org: Vector3 = cam.project_ray_origin(Vector2(0.0, cam.unproject_position(carrier).y))
	var left_dir: Vector3 = cam.project_ray_normal(Vector2(0.0, cam.unproject_position(carrier).y))
	var left_hit: Vector3 = left_org + left_dir * (-left_org.y / minf(left_dir.y, -0.001))
	var behind: float = (carrier - Vector3(cam.global_position.x, 0.0, cam.global_position.z)).dot(fwd)
	return {
		"cam_height": snappedf(cam.global_position.y, 0.01),
		"cam_behind": snappedf(behind, 0.01),
		"lat_px_per_m": snappedf(lat, 0.1),
		"depth_px_per_m": snappedf(dep, 0.1),
		"foreshortening": snappedf(lat / maxf(dep, 0.001), 0.01),
		"reach_far_over_near": snappedf(far_d / maxf(near_d, 0.001), 0.01),
		"ice_ahead_m": snappedf(ahead, 0.1),
		"horizon_y": snappedf(horizon_y, 0.01),
		"width_at_carrier_m": snappedf(2.0 * absf((left_hit - carrier).dot(cam.global_basis.x)), 0.1),
		"carrier_screen_y": snappedf(cam.unproject_position(carrier).y / size.y, 0.01),
	}


func _add_rings(center: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	for r: float in _RING_RADII:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for i: int in _RING_SEGMENTS + 1:
			var a: float = TAU * float(i) / float(_RING_SEGMENTS)
			mesh.surface_add_vertex(center + Vector3(cos(a) * r, 0.03, sin(a) * r))
		mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().current_scene.add_child(mi)


func _diagnose() -> void:
	var registry: PlayerRegistry = GameManager.get("_registry") as PlayerRegistry
	for sk: Skater in registry.skaters():
		var skel: Skeleton3D = _first_skeleton(sk)
		var nan_bones: int = 0
		var far_bones: int = 0
		if skel != null:
			for b: int in skel.get_bone_count():
				var o: Vector3 = skel.get_bone_global_pose(b).origin
				if is_nan(o.x) or is_nan(o.y) or is_nan(o.z):
					nan_bones += 1
				elif o.length() > 5.0:
					far_bones += 1
		var meshes: PackedStringArray = []
		_collect_meshes(sk, meshes)
		print("[diag] %s local=%s skel=%s bones=%d nan=%d far=%d scale=%s meshes=%s" % [sk.name,
				sk.is_local_skater, skel != null, skel.get_bone_count() if skel else 0, nan_bones,
				far_bones, str(skel.global_basis.get_scale()) if skel else "", ",".join(meshes)])


func _first_skeleton(n: Node) -> Skeleton3D:
	for c: Node in n.get_children():
		if c is Skeleton3D:
			return c as Skeleton3D
		var hit: Skeleton3D = _first_skeleton(c)
		if hit != null:
			return hit
	return null


func _collect_meshes(n: Node, out: PackedStringArray) -> void:
	for c: Node in n.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			out.append("%s:%s%s" % [mi.name, "V" if mi.is_visible_in_tree() else "h",
					"" if mi.mesh != null else "(nomesh)"])
		_collect_meshes(c, out)


func _find(node: Node, cls: Script) -> Node:
	if node == null:
		return null
	if is_instance_of(node, cls):
		return node
	for child: Node in node.get_children():
		var hit: Node = _find(child, cls)
		if hit != null:
			return hit
	return null

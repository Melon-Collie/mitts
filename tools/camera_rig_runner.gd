extends "res://tools/ui_preview_runner.gd"

# The work behind tools/camera_rig_preview.gd: every rig in camera_rigs.gd,
# measured for how the aim cursor lands on the ice, then shot over a live 3v3
# frozen at a few moments. Reuses the UI preview's match staging.
#
# The cursor reaches the ice the way LocalInputGatherer._screen_to_world takes
# it — a ray through the rendering camera onto y = 0 — so a rig's distortion of
# that map is what stickhandling under it would feel. The table measures it with
# no renderer at all; only the stills need one.

const CameraRigs = preload("res://tools/camera_rigs.gd")

const _VIEW: Vector2i = Vector2i(1920, 1080)
# Moments shot per run, and the game time played between them.
const _MOMENTS: int = 3
const _MOMENT_GAP_SEC: float = 2.5
# Blade sample annulus (m from the skater's centre, every bearing): a hand's
# width off the skates out to near the arm's full reach with the stick.
const _BLADE_RADII: Array[float] = [0.4, 0.8, 1.2, 1.6]
const _BLADE_BEARINGS: int = 12
# Half-width (px) of the central difference that reads metres per pixel.
const _STEP_PX: float = 4.0
# The far aim point: the ice under the centre column this far down from the top
# edge, the longest shot or pass the cursor can point at on screen.
const _FAR_AIM_ROW_FRACTION: float = 0.05
# The framed skater as an occluder: a standing skater's shoulder half-width and
# height, a column that over-hides a crouched carry, so the same for every rig.
const _BODY_RADIUS_M: float = 0.3
const _BODY_HEIGHT_M: float = 1.85
# How far up-ice (m) a puck on the skater's centre line is searched for first
# being seen past that column, and the search's step.
const _CLEAR_SEARCH_M: float = 8.0
const _CLEAR_STEP_M: float = 0.05


func begin(only: String, out_dir: String, measure_only: bool) -> void:
	var rigs: Array[Dictionary] = _pick(only)
	if rigs.is_empty():
		get_tree().quit(1)
		return
	_out_dir = out_dir
	DirAccess.make_dir_recursive_absolute(_out_dir)
	await _write_table(rigs)
	if measure_only:
		get_tree().quit(0)
		return
	await _enter_stage(_STAGE_MATCH)
	for moment: int in _MOMENTS:
		if moment > 0:
			await _play(_MOMENT_GAP_SEC)
		await _shoot_moment(moment, rigs)
	get_tree().quit(1 if _failed else 0)


func _pick(only: String) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	if only.is_empty():
		picked.assign(CameraRigs.RIGS)
		return picked
	var tokens: PackedStringArray = only.split(",", false)
	for rig: Dictionary in CameraRigs.RIGS:
		if tokens.has(rig["name"]):
			picked.append(rig)
	if picked.size() != tokens.size():
		var names: PackedStringArray = []
		for rig: Dictionary in CameraRigs.RIGS:
			names.append(rig["name"])
		push_error("[camera-rigs] unknown rig in '%s'; rigs: %s" % [only, ", ".join(names)])
		picked.clear()
	return picked


func _play(seconds: float) -> void:
	var default_steps: int = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = _MATCH_STEPS_PER_FRAME
	var target: int = Engine.get_physics_frames() + int(seconds * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < target:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = default_steps


# Freezes game time and re-places the gameplay camera for each rig, so every rig
# shows the identical instant. The framed skater is whoever is nearest the puck —
# the play — and up-ice is the gameplay camera's own, so the attack-up flip holds.
func _shoot_moment(moment: int, rigs: Array[Dictionary]) -> void:
	var cam: GameCamera = _find(get_tree().current_scene, GameCamera) as GameCamera
	if cam == null or cam.puck == null:
		_fail("the match has no GameCamera with a puck")
		return
	var subject: Skater = _nearest_skater(cam.puck.global_position)
	if subject == null:
		_fail("the match has no skaters")
		return
	print("[camera-rigs] moment %d framed on %s" % [moment, subject.name])
	var up_ice: Vector3 = -cam.global_basis.z
	var saved_xform: Transform3D = cam.global_transform
	var saved_fov: float = cam.fov
	var saved_mask: int = cam.cull_mask
	Engine.time_scale = 0.0
	cam.set_process(false)
	for rig: Dictionary in rigs:
		cam.global_transform = CameraRigs.transform_for(rig, subject.global_position, up_ice)
		cam.fov = rig["fov"]
		# A lower camera sees under the overhead dressing GameCamera hides, so the
		# shoulder stills show it: whether it intrudes is part of the question.
		cam.cull_mask = saved_mask if CameraRigs.is_current_framing(rig) \
				else saved_mask | RenderLayers.OVERHEAD_DRESSING
		await _settle(2, 0.0)
		await _snap("m%d_%s" % [moment, rig["name"]])
	cam.global_transform = saved_xform
	cam.fov = saved_fov
	cam.cull_mask = saved_mask
	cam.set_process(true)
	Engine.time_scale = 1.0


func _nearest_skater(at: Vector3) -> Skater:
	var skaters: Array[Skater] = []
	_collect_skaters(get_tree().current_scene, skaters)
	var best: Skater = null
	var best_d: float = INF
	for s: Skater in skaters:
		var d: float = s.global_position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = s
	return best


func _collect_skaters(node: Node, into: Array[Skater]) -> void:
	if node is Skater:
		into.append(node as Skater)
	for child: Node in node.get_children():
		_collect_skaters(child, into)


# --- Projection table -------------------------------------------------------

func _write_table(rigs: Array[Dictionary]) -> void:
	var vp := SubViewport.new()
	vp.size = _VIEW
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var lines: PackedStringArray = [
		"# Camera rig projection, %dx%d" % [_VIEW.x, _VIEW.y],
		"",
		"Blade columns sample the reach annulus (%.1f–%.1f m, every %d°) around a skater"
				% [_BLADE_RADII[0], _BLADE_RADII[-1], roundi(360.0 / _BLADE_BEARINGS)]
				+ " at the origin facing up-ice. mm/px is ice per pixel of cursor travel"
				+ " (smaller = finer); spread is the largest over the smallest across the"
				+ " reach; aniso is the worst up-screen ÷ across-screen at one spot (1 = the"
				+ " cursor maps the same in every direction). Far aim is the farthest ice"
				+ " the cursor reaches up the centre of the screen, with its bearing and"
				+ " range per pixel there. Ice ahead/behind is the frame's top/bottom edge"
				+ " on the centre line. Puck seen is how far ahead a puck on the skater's"
				+ " line first shows past a standing body. Framing is fixed on the skater:"
				+ " GameCamera's dynamic zoom and zone lean, which push the now_* view up-ice,"
				+ " are not modelled.",
		"",
		"| rig | pitch | fov | across mm/px | up mm/px | spread | aniso | far aim m | far °/px | far cm/px | ice ahead m | ice behind m | sky % | puck seen m |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
	]
	for rig: Dictionary in rigs:
		cam.fov = rig["fov"]
		var placed: Transform3D = CameraRigs.transform_for(rig, Vector3.ZERO, Vector3.FORWARD)
		cam.global_transform = placed
		# Camera3D projects through a view cached on the transform notification,
		# which lands whenever the tree next flushes them.
		while not cam.get_camera_transform().is_equal_approx(placed):
			await get_tree().process_frame
		lines.append(_row(cam, rig))
	vp.queue_free()
	var text: String = "\n".join(lines) + "\n"
	print(text)
	var path: String = _out_dir.path_join("projection.md")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("could not write %s" % path)
		return
	f.store_string(text)
	print("[camera-rigs] table -> %s" % ProjectSettings.globalize_path(path))


func _row(cam: Camera3D, rig: Dictionary) -> String:
	var across: Array[float] = []
	var up: Array[float] = []
	var aniso: float = 0.0
	var offscreen: int = 0
	for r: float in _BLADE_RADII:
		for k: int in _BLADE_BEARINGS:
			var bearing: float = TAU * float(k) / float(_BLADE_BEARINGS)
			var p := Vector3(sin(bearing) * r, 0.0, -cos(bearing) * r)
			var g: Vector2 = _metres_per_px(cam, p)
			if g.x <= 0.0 or g.y <= 0.0:
				offscreen += 1
				continue
			across.append(g.x)
			up.append(g.y)
			aniso = maxf(aniso, g.y / g.x)
	if across.is_empty():
		return "| %s | the reach is off screen |" % rig["name"]
	var all_gains: Array[float] = across.duplicate()
	all_gains.append_array(up)
	var spread: float = all_gains.max() / all_gains.min()
	var far_aim: Vector3 = _ice_at(cam, Vector2(_VIEW.x * 0.5, _VIEW.y * _FAR_AIM_ROW_FRACTION))
	var far_m: float = INF
	var far_deg: float = INF
	var far_cm: float = INF
	if far_aim != Vector3.INF:
		var g: Vector2 = _metres_per_px(cam, far_aim)
		far_m = -far_aim.z
		far_deg = rad_to_deg(g.x / far_m)
		far_cm = g.y * 100.0
	var seen_text: String = _fmt(_puck_seen_from(cam.global_position), "%.2f")
	if offscreen > 0:
		seen_text += " (%d reach samples off screen)" % offscreen
	return "| %s | %d° | %d° | %.1f | %.1f | %.2f | %.2f | %s | %s | %s | %s | %s | %d | %s |" % [
		rig["name"], int(rig["pitch"]), int(rig["fov"]),
		_median(across) * 1000.0, _median(up) * 1000.0, spread, aniso,
		_fmt(far_m, "%.1f"), _fmt(far_deg, "%.3f"), _fmt(far_cm, "%.1f"),
		_fmt(_edge_reach(cam, 0.0), "%.1f"), _fmt(_edge_reach(cam, float(_VIEW.y - 1)), "%.1f"),
		int(round(_sky_fraction(cam) * 100.0)), seen_text,
	]


# Ice metres per screen pixel at p, across (x) and up the screen (y); a
# component is 0 when p or a neighbour has no ice under it.
func _metres_per_px(cam: Camera3D, p: Vector3) -> Vector2:
	if cam.is_position_behind(p):
		return Vector2.ZERO
	var s: Vector2 = cam.unproject_position(p)
	if not Rect2(Vector2.ZERO, Vector2(_VIEW)).has_point(s):
		return Vector2.ZERO
	var dx := Vector2(_STEP_PX, 0.0)
	var dy := Vector2(0.0, _STEP_PX)
	return Vector2(_span(cam, s - dx, s + dx), _span(cam, s - dy, s + dy)) / (2.0 * _STEP_PX)


func _span(cam: Camera3D, a: Vector2, b: Vector2) -> float:
	var ia: Vector3 = _ice_at(cam, a)
	var ib: Vector3 = _ice_at(cam, b)
	if ia == Vector3.INF or ib == Vector3.INF:
		return 0.0
	return ia.distance_to(ib)


func _ice_at(cam: Camera3D, screen: Vector2) -> Vector3:
	var o: Vector3 = cam.project_ray_origin(screen)
	var d: Vector3 = cam.project_ray_normal(screen)
	if d.y > -1e-4:
		return Vector3.INF
	return o + d * (-o.y / d.y)


# Up-ice distance (m, signed: negative is behind the skater) of the ice under the
# centre column at screen row y, or INF above the horizon.
func _edge_reach(cam: Camera3D, y: float) -> float:
	var hit: Vector3 = _ice_at(cam, Vector2(_VIEW.x * 0.5, y))
	return INF if hit == Vector3.INF else -hit.z


# Share of the centre column above the horizon, where the cursor finds no ice.
func _sky_fraction(cam: Camera3D) -> float:
	for row: int in _VIEW.y:
		if _ice_at(cam, Vector2(_VIEW.x * 0.5, row)) != Vector3.INF:
			return float(row) / float(_VIEW.y)
	return 1.0


# Metres ahead on the skater's line where a puck first shows past the body, or
# INF if it never does within the search.
func _puck_seen_from(eye: Vector3) -> float:
	var z: float = _BODY_RADIUS_M
	while z <= _CLEAR_SEARCH_M:
		if not _body_hides(eye, Vector3(0.0, 0.0, -z)):
			return z
		z += _CLEAR_STEP_M
	return INF


func _body_hides(eye: Vector3, spot: Vector3) -> bool:
	const SAMPLES: int = 200
	for i: int in SAMPLES:
		var q: Vector3 = spot.lerp(eye, float(i) / float(SAMPLES))
		if q.y > _BODY_HEIGHT_M:
			return false
		if Vector2(q.x, q.z).length() < _BODY_RADIUS_M:
			return true
	return false


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() >> 1]


func _fmt(v: float, pattern: String) -> String:
	return "—" if is_inf(v) else pattern % v

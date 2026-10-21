extends Node

# The work behind tools/graphics_cost.gd. Starts a 5v5 against bots, lets play
# settle, then measures every condition — the shipped defaults with ONE Video
# setting changed — through the same PlayerPrefs.apply_video() the menu calls.
#
# A 5v5 frame varies by more than most settings cost (docs/performance-findings.md
# → *How to measure something new*), and a goal replay's cameras see twice the
# arena play does. So frames are sampled only in live play, and every condition
# is measured between two measurements of the defaults: its cost is its
# difference from their mean, which cancels the scene drifting under it. Each
# rotation visits every condition once; the table reports the median difference
# and its range, and a range that straddles zero is a setting this machine
# cannot tell from noise.
#
# Draw calls and triangles are properties of the scene and hold on any GPU. The
# times are this machine's: on software Vulkan they rank passes by their work,
# not by what a graphics card would spend.

# label → the PlayerPrefs fields it changes from the defaults.
const CONDITIONS: Array = [
	["defaults", {}],
	["shadows: medium", {"shadow_quality": PlayerPrefs.SHADOW_QUALITY_MEDIUM}],
	["shadows: low", {"shadow_quality": PlayerPrefs.SHADOW_QUALITY_LOW}],
	["render scale: 75%", {"render_scale": 0.75}],
	["render scale: 50%", {"render_scale": 0.5}],
	["upscaling: FSR at 75%", {"render_scale": 0.75, "scaling_3d_mode": PlayerPrefs.SCALING_3D_FSR}],
	["upscaling: FSR2 at 75%", {"render_scale": 0.75, "scaling_3d_mode": PlayerPrefs.SCALING_3D_FSR2}],
	["anti-aliasing: off", {"anti_aliasing_mode": PlayerPrefs.AA_OFF}],
	["anti-aliasing: FXAA", {"anti_aliasing_mode": PlayerPrefs.AA_FXAA}],
	["anti-aliasing: MSAA 4x", {"anti_aliasing_mode": PlayerPrefs.AA_MSAA_4X}],
	["anti-aliasing: MSAA 8x", {"anti_aliasing_mode": PlayerPrefs.AA_MSAA_8X}],
	["anti-aliasing: TAA", {"anti_aliasing_mode": PlayerPrefs.AA_TAA}],
	["global illumination: SDFGI", {"gi_mode": PlayerPrefs.GI_MODE_SDFGI}],
	["crowd: low", {"crowd_density": PlayerPrefs.CROWD_DENSITY_LOW}],
	["crowd: off", {"crowd_density": PlayerPrefs.CROWD_DENSITY_OFF}],
	["volumetric fog: on", {"volumetric_fog_enabled": true}],
	["reflections: off", {"reflections_enabled": false}],
	["ambient occlusion: off", {"ambient_occlusion_enabled": false}],
	["player shadows: off", {"player_shadows_enabled": false}],
	["puck shadow: off", {"puck_shadow_enabled": false}],
	["ice scratches: off", {"ice_scratches_enabled": false}],
	["arena ads: off", {"arena_ads_enabled": false}],
	["animation detail: low", {"animation_detail": SkaterAnimationLod.DETAIL_LOW}],
	["animation detail: full", {"animation_detail": SkaterAnimationLod.DETAIL_FULL}],
	["color grade: none", {"color_grade_preset": 0}],
]

# Tunable from the environment: a software renderer draws a frame a second, a
# graphics card a few hundred.
var _rotations: int = int(OS.get_environment("GRAPHICS_COST_ROTATIONS")) if \
		OS.has_environment("GRAPHICS_COST_ROTATIONS") else 5
var _settle_frames: int = int(OS.get_environment("GRAPHICS_COST_SETTLE")) if \
		OS.has_environment("GRAPHICS_COST_SETTLE") else 30
var _sample_frames: int = int(OS.get_environment("GRAPHICS_COST_SAMPLES")) if \
		OS.has_environment("GRAPHICS_COST_SAMPLES") else 60

const _PLAY_SEC: float = 4.0
const _START_TIMEOUT_FRAMES: int = 3000
# Long enough that no period ends inside a run.
const _PERIOD_SEC: float = 3600.0

var _defaults: Dictionary = {}


func begin(only: String, out_path: String, list_only: bool) -> void:
	if list_only:
		for c: Array in CONDITIONS:
			print(c[0])
		get_tree().quit()
		return
	var picked: Array = _select(only)
	await _start_match()
	_free_run()
	for c: Array in CONDITIONS:
		for field: String in (c[1] as Dictionary):
			_defaults[field] = PlayerPrefs.get(field)
	var vp: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	# rows[label] = per rotation {gpu, frame, draws, tris} and, but for the
	# defaults, the same keys prefixed "d_" for the difference from them.
	var rows: Dictionary = {}
	for c: Array in picked:
		rows[c[0]] = []
	for r: int in _rotations:
		var before: Dictionary = await _measure({})
		(rows["defaults"] as Array).append(before)
		for c: Array in picked:
			if c[0] == "defaults":
				continue
			var m: Dictionary = await _measure(c[1] as Dictionary)
			var after: Dictionary = await _measure({})
			(rows["defaults"] as Array).append(after)
			for key: String in ["gpu", "frame"]:
				m["d_" + key] = m[key] - (before[key] + after[key]) * 0.5
			(rows[c[0]] as Array).append(m)
			print("[graphics-cost] rotation %d/%d  %-28s gpu %+8.2f ms  frame %+8.2f ms  draws %5d" % [
					r + 1, _rotations, c[0], m.d_gpu, m.d_frame, int(m.draws)])
			before = after
	_apply({})
	var table: String = _table(picked, rows)
	print(table)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(table)
		print("[graphics-cost] wrote %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()


func _select(only: String) -> Array:
	var out: Array = [CONDITIONS[0]]
	if only.is_empty():
		return CONDITIONS.duplicate()
	for token: String in only.split(",", false):
		for c: Array in CONDITIONS:
			if (c[0] as String).begins_with(token) and not out.has(c):
				out.append(c)
	return out


# From the offline lobby, a 5v5 with every open slot a bot, played until the
# opening faceoff is behind it.
func _start_match() -> void:
	var tree: SceneTree = get_tree()
	PlayerPrefs.preferred_team_size = 5
	NetworkManager.start_offline()
	tree.change_scene_to_file(Constants.SCENE_LOBBY)
	while tree.current_scene == null or tree.current_scene.scene_file_path != Constants.SCENE_LOBBY:
		await tree.process_frame
	await tree.process_frame
	var lobby: LobbyManager = _find_lobby(tree.current_scene)
	lobby.set("_period_duration", _PERIOD_SEC)
	lobby.call("_fill_open_slots_with_bots")
	lobby.call("_on_start_pressed")
	var waited: int = 0
	while tree.current_scene == null \
			or tree.current_scene.scene_file_path != Constants.SCENE_HOCKEY \
			or GameManager.is_movement_locked():
		await tree.process_frame
		waited += 1
		if waited > _START_TIMEOUT_FRAMES:
			push_error("[graphics-cost] the match never left the opening faceoff")
			break
	var target: int = Engine.get_physics_frames() + int(_PLAY_SEC * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < target:
		await tree.process_frame


func _find_lobby(n: Node) -> LobbyManager:
	if n is LobbyManager:
		return n as LobbyManager
	for c: Node in n.get_children():
		var found: LobbyManager = _find_lobby(c)
		if found != null:
			return found
	return null


# No vsync, no cap: a frame that is waited on measures the wait.
func _free_run() -> void:
	PlayerPrefs.vsync_mode = PlayerPrefs.VSYNC_DISABLED
	PlayerPrefs.fps_cap_index = PlayerPrefs.FPS_CAP_VALUES.find(0)
	PlayerPrefs.apply_video()


func _apply(changes: Dictionary) -> void:
	for field: String in _defaults:
		PlayerPrefs.set(field, changes.get(field, _defaults[field]))
	PlayerPrefs.apply_video()


func _measure(changes: Dictionary) -> Dictionary:
	_apply(changes)
	await _live_frames(_settle_frames)
	return await _sample(get_viewport().get_viewport_rid())


# Play running, no replay cinematic: the scene a setting is judged in.
static func _live() -> bool:
	return not GameManager.is_movement_locked() and not NetworkManager.is_replay_mode()


func _live_frames(n: int) -> void:
	var seen: int = 0
	while seen < n:
		await RenderingServer.frame_post_draw
		if _live():
			seen += 1


func _sample(vp: RID) -> Dictionary:
	var gpu := PackedFloat64Array()
	var frame := PackedFloat64Array()
	var draws := PackedFloat64Array()
	var tris := PackedFloat64Array()
	var t_prev: int = Time.get_ticks_usec()
	while gpu.size() < _sample_frames:
		await RenderingServer.frame_post_draw
		var t: int = Time.get_ticks_usec()
		var dt: float = float(t - t_prev) / 1000.0
		t_prev = t
		if not _live():
			continue
		frame.append(dt)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		tris.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	return {"gpu": _median(gpu), "frame": _median(frame), "draws": _median(draws),
			"tris": _median(tris)}


static func _median(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return 0.0
	var s: PackedFloat64Array = v.duplicate()
	s.sort()
	var mid: int = s.size() / 2
	return s[mid] if s.size() % 2 == 1 else (s[mid - 1] + s[mid]) * 0.5


func _table(picked: Array, rows: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Measured on %s, %s, %d rotations of %d live-play frames, at %s." % [
			RenderingServer.get_video_adapter_name(), OS.get_name(), _rotations,
			_sample_frames, str(get_viewport().get_visible_rect().size)])
	lines.append("")
	lines.append("| setting | GPU ms (Δ, range) | frame ms (Δ, range) | draw calls | triangles |")
	lines.append("|---|---|---|---|---|")
	for c: Array in picked:
		var label: String = c[0]
		var runs: Array = rows[label]
		if label == "defaults":
			lines.append("| **defaults** | %.2f | %.2f | %d | %s |" % [
					_median_of(runs, "gpu"), _median_of(runs, "frame"),
					int(_median_of(runs, "draws")), _mega(_median_of(runs, "tris"))])
			continue
		lines.append("| %s | %s | %s | %d | %s |" % [label,
				_delta(runs, "gpu"), _delta(runs, "frame"),
				int(_median_of(runs, "draws")), _mega(_median_of(runs, "tris"))])
	return "\n".join(lines) + "\n"


static func _median_of(runs: Array, key: String) -> float:
	var v := PackedFloat64Array()
	for m: Dictionary in runs:
		v.append(m[key])
	return _median(v)


# The condition's difference from the defaults around it, over the rotations:
# "+1.20 (+0.9..+1.6)".
static func _delta(runs: Array, key: String) -> String:
	var d := PackedFloat64Array()
	for m: Dictionary in runs:
		d.append(m["d_" + key])
	var s: PackedFloat64Array = d.duplicate()
	s.sort()
	return "%+.2f (%+.2f..%+.2f)" % [_median(d), s[0], s[s.size() - 1]]


static func _mega(n: float) -> String:
	return "%.2f M" % (n / 1000000.0)

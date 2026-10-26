extends Node

# The work behind tools/frame_cost.gd. Starts a 5v5 lobby, fills all but the
# open slots with bots, plays past the opening faceoff, then times live-play
# frames: the process step (every _process) and each physics tick, apart.
#
# The two are reported apart because they scale differently with frame rate. A
# frame pays the process step once and the tick 120 / fps times, so "the frame at
# 90 fps" is composed from both rather than read off a headless run, whose frame
# rate is whatever the CPU allows.
#
# Headless draws nothing: render-side CPU (culling, draw calls, skinning) is not
# in these numbers, and neither is anything a GPU would cost. Run with a display
# (the hook's FRAME_COST_RENDER=1: xvfb and software Vulkan) and each frame also
# records the engine's CPU render time and the draw calls, both properties of the
# CPU work and the scene rather than of the GPU; the GPU time is not reported,
# because on a software rasteriser it is the CPU too.

# Bracket nodes at the far ends of every ordering the tree has. Thread-group
# order outranks priority (docs/parallel-render-pass-plan.md), so a bracket is
# its own main-thread group, first or last, as well as first or last by priority.
const _FAR_ORDER: int = 1_000_000
const _FAR_PRIORITY: int = 1_000_000_000

const _START_TIMEOUT_FRAMES: int = 6000
const _SETTLE_SEC: float = 3.0
const _PERIOD_SEC: float = 3600.0


class Bracket extends Node:
	var opens: bool = true
	var phys_t0: int = 0
	var proc_t0: int = 0
	var phys_us: int = 0
	var proc_us: int = 0
	var partner: Bracket = null

	func _physics_process(_delta: float) -> void:
		if opens:
			phys_t0 = Time.get_ticks_usec()
		else:
			partner.phys_us += Time.get_ticks_usec() - partner.phys_t0

	func _process(_delta: float) -> void:
		if opens:
			proc_t0 = Time.get_ticks_usec()
		else:
			partner.proc_us += Time.get_ticks_usec() - partner.proc_t0


var _head: Bracket = null


func begin(skaters: int, frames: int, parallel: bool = false) -> void:
	Skater.parallel_render = parallel
	await _start_match(clampi(skaters, 2, 10))
	_install_brackets()
	await _play_for(_SETTLE_SEC)
	var row: Dictionary = await _sample(frames)
	print("[frame-cost] %s" % JSON.stringify(row))
	get_tree().quit()


func _install_brackets() -> void:
	var head := Bracket.new()
	var tail := Bracket.new()
	tail.opens = false
	tail.partner = head
	for b: Array in [[head, -1], [tail, 1]]:
		var n: Bracket = b[0]
		var side: int = b[1]
		n.process_thread_group = Node.PROCESS_THREAD_GROUP_MAIN_THREAD
		n.process_thread_group_order = side * _FAR_ORDER
		n.process_priority = side * _FAR_PRIORITY
		n.process_physics_priority = side * _FAR_PRIORITY
		get_tree().root.add_child(n)
	_head = head


func _start_match(skaters: int) -> void:
	var tree: SceneTree = get_tree()
	PlayerPrefs.preferred_team_size = 5
	PlayerPrefs.vsync_mode = PlayerPrefs.VSYNC_DISABLED
	PlayerPrefs.fps_cap_index = PlayerPrefs.FPS_CAP_VALUES.find(0)
	PlayerPrefs.apply_video()
	NetworkManager.start_offline()
	tree.change_scene_to_file(Constants.SCENE_LOBBY)
	while tree.current_scene == null or tree.current_scene.scene_file_path != Constants.SCENE_LOBBY:
		await tree.process_frame
	await tree.process_frame
	var lobby: LobbyManager = _find_lobby(tree.current_scene)
	lobby.set("_period_duration", _PERIOD_SEC)
	_fill_bots(lobby, skaters - 1)
	await tree.process_frame
	lobby.call("_on_start_pressed")
	var waited: int = 0
	while tree.current_scene == null \
			or tree.current_scene.scene_file_path != Constants.SCENE_HOCKEY \
			or GameManager.is_movement_locked():
		await tree.process_frame
		waited += 1
		if waited > _START_TIMEOUT_FRAMES:
			push_error("[frame-cost] the match never left the opening faceoff")
			break


# The open slots, alternating teams so the sides stay level, until `bots` are in.
func _fill_bots(lobby: LobbyManager, bots: int) -> void:
	var taken: Dictionary = lobby.get("_lobby_slots")
	var placed: int = 0
	for s: int in 5:
		for team_id: int in 2:
			var key: int = LobbySlotKey.encode(team_id, s)
			if placed >= bots or taken.has(key):
				continue
			NetworkManager.send_bot_slot(key, true)
			placed += 1


func _find_lobby(n: Node) -> LobbyManager:
	if n is LobbyManager:
		return n as LobbyManager
	for c: Node in n.get_children():
		var found: LobbyManager = _find_lobby(c)
		if found != null:
			return found
	return null


func _play_for(seconds: float) -> void:
	var target: int = Engine.get_physics_frames() + int(seconds * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < target:
		await get_tree().process_frame


static func _live() -> bool:
	return not GameManager.is_movement_locked() and not NetworkManager.is_replay_mode()


func _sample(frames: int) -> Dictionary:
	var proc := PackedFloat64Array()
	var wall := PackedFloat64Array()
	var render := PackedFloat64Array()
	var draws := PackedFloat64Array()
	var drawn: bool = DisplayServer.get_name() != "headless"
	var vp: RID = get_viewport().get_viewport_rid()
	if drawn:
		RenderingServer.viewport_set_measure_render_time(vp, true)
	var phys_us: int = 0
	var ticks: int = 0
	var t_prev: int = Time.get_ticks_usec()
	var tick_prev: int = Engine.get_physics_frames()
	_head.proc_us = 0
	_head.phys_us = 0
	_probe_sums.resize(HostCostProbe.SECTION_COUNT)
	_probe_sums.fill(0.0)
	_probe_windows = 0
	var window_seen: int = HostCostProbe.windows
	var window_live: bool = false
	while proc.size() < frames:
		await get_tree().process_frame
		var t: int = Time.get_ticks_usec()
		var tick: int = Engine.get_physics_frames()
		var live: bool = _live()
		if HostCostProbe.windows != window_seen:
			_take_probe_window(window_live and HostCostProbe.windows == window_seen + 1)
			window_seen = HostCostProbe.windows
			window_live = true
		window_live = window_live and live
		if live:
			wall.append(float(t - t_prev) / 1000.0)
			proc.append(float(_head.proc_us) / 1000.0)
			phys_us += _head.phys_us
			ticks += tick - tick_prev
			if drawn:
				render.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_head.proc_us = 0
		_head.phys_us = 0
		t_prev = t
		tick_prev = tick
	var tick_ms: float = float(phys_us) / 1000.0 / maxf(float(ticks), 1.0)
	var proc_ms: float = _mean(proc)
	return {
		"skaters": get_tree().get_nodes_in_group("skaters").size(),
		"frames": proc.size(),
		"ticks": ticks,
		"wall_ms": _mean(wall),
		"process_ms": proc_ms,
		"process_p95_ms": _percentile(proc, 0.95),
		"tick_ms": tick_ms,
		"at_90fps_ms": proc_ms + tick_ms * float(Engine.physics_ticks_per_second) / 90.0,
		"native": NativeKernels.summary(),
		"parallel": Skater.parallel_render,
		"cpu_render_ms": _mean(render) if drawn else -1.0,
		"draw_calls": _mean(draws) if drawn else -1.0,
		"probe_us": _probe_sections(),
	}


# HostCostProbe's windows, per section: where the tick's time went. A window
# counts only if it was wholly live play and began after sampling did; a single
# window can land on a faceoff or a goal replay, where no bot steps at all.
var _probe_sums := PackedFloat64Array()
var _probe_windows: int = 0


func _take_probe_window(counts: bool) -> void:
	if not counts:
		return
	for s: int in HostCostProbe.SECTION_COUNT:
		_probe_sums[s] += HostCostProbe.mean_us(s)
	_probe_windows += 1


func _probe_sections() -> Dictionary:
	var out: Dictionary = {}
	if _probe_windows == 0:
		return out
	var total: float = 0.0
	for s: int in HostCostProbe.SECTION_COUNT:
		var mean: float = _probe_sums[s] / float(_probe_windows)
		out[HostCostProbe.SECTION_NAMES[s].strip_edges()] = snappedf(mean, 0.1)
		if s in HostCostProbe.MAIN_THREAD_SECTIONS:
			total += mean
	out["tick total"] = snappedf(total, 0.1)
	out["windows"] = _probe_windows
	return out


static func _mean(v: PackedFloat64Array) -> float:
	var s: float = 0.0
	for x: float in v:
		s += x
	return s / maxf(float(v.size()), 1.0)


static func _percentile(v: PackedFloat64Array, q: float) -> float:
	if v.is_empty():
		return 0.0
	var s: PackedFloat64Array = v.duplicate()
	s.sort()
	return s[clampi(int(q * float(s.size() - 1)), 0, s.size() - 1)]

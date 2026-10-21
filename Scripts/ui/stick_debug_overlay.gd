class_name StickDebugOverlay
extends CanvasLayer

# F9 stickhandling debug overlay: why the local carrier's blade changes face.
# Every face change is logged with its cause (CarryStrokeState.Cause) and what
# the player was doing as it fired — skating speed, turn rate, and how far the
# mouse had moved — so "the blade hops though I'm barely moving the mouse" can
# be read as a cause rather than guessed at. F10 copies the log.
#
# Reading it: RETURN is a slow stroke's puck coming back at the blade (the plain
# flip), REPUSH a second push the way a release sent it, RELEASE a hard stroke
# let go mid-sweep. A face change with a still mouse means the puck moved under
# a still cursor: the camera framing or the body moving round it.
#
# Debug surface like NetworkDebugOverlay: strings are deliberately not routed
# through tr(), and it is built in code with no .tscn. Listens only while open,
# so a match nobody inspects pays nothing.

const COL_HEAD := "8fb3d9"
const COL_DIM := "8a93a0"
const COL_VAL := "ececec"
const COL_FLAG := "e6cf52"

const REFRESH_SECONDS: float = 0.1
const LOG_SIZE: int = 12
const COUNT_WINDOW_S: float = 5.0
# How far back the mouse's travel is summed for each face change: about a
# stroke's length, so a deliberate stroke shows and a still hand reads ~0.
const MOUSE_WINDOW_S: float = 0.3
const _MOUSE_RING: int = 256
const _CAUSE_NAMES: Array[String] = ["-", "RETURN", "REPUSH", "RELEASE", "TOLD"]

var _rt: RichTextLabel
var _panel: PanelContainer
var _showing: bool = false
var _refresh_timer: float = 0.0
var _skater: Skater = null
var _status: String = ""

var _clock: float = 0.0
var _mouse_pos := PackedVector2Array()
var _mouse_t := PackedFloat64Array()
var _mouse_head: int = 0
var _facing_prev: float = INF
var _turn_rate: float = 0.0
# Newest last: [time, cause, speed, travel_m, skating, turning, mouse_px].
var _log: Array[PackedFloat64Array] = []


func _ready() -> void:
	layer = 98   # under the network and shape overlays
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.80)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", style)
	_rt = RichTextLabel.new()
	_rt.bbcode_enabled = true
	_rt.fit_content = true
	_rt.scroll_active = false
	_rt.custom_minimum_size = Vector2(600, 0)
	_rt.add_theme_font_size_override("normal_font_size", 13)
	_rt.add_theme_font_size_override("bold_font_size", 13)
	_panel.add_child(_rt)
	add_child(_panel)
	_panel.hide()
	_mouse_pos.resize(_MOUSE_RING)
	_mouse_t.resize(_MOUSE_RING)
	_mouse_t.fill(-INF)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F9:
		_showing = not _showing
		_panel.visible = _showing
		if not _showing:
			_watch(null)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F10 and _showing:
		var text: String = log_text()
		DisplayServer.clipboard_set(text)
		print("[stick debug]\n", text)
		_status = "log copied to the clipboard and printed to the console"
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _showing:
		return
	_clock += delta
	_watch(_find_local_skater())
	_mouse_head = (_mouse_head + 1) % _MOUSE_RING
	_mouse_pos[_mouse_head] = get_viewport().get_mouse_position()
	_mouse_t[_mouse_head] = _clock
	if _skater != null and delta > 0.0:
		var facing: Vector2 = _skater.get_facing()
		var angle: float = atan2(facing.x, facing.y)
		if _facing_prev != INF:
			var rate: float = absf(rad_to_deg(wrapf(angle - _facing_prev, -PI, PI))) / delta
			_turn_rate = lerpf(_turn_rate, rate, 1.0 - exp(-delta / 0.1))
		_facing_prev = angle
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_SECONDS
		_rt.text = _render()


# Records a face change; public so a test can feed one.
func record(cause: int, speed: float, travel_m: float, skating: float, turning: float,
		mouse_px: float) -> void:
	_log.append(PackedFloat64Array([_clock, cause, speed, travel_m, skating, turning, mouse_px]))
	if _log.size() > LOG_SIZE:
		_log.pop_front()


func log_text() -> String:
	var lines: PackedStringArray = ["ago_s\tcause\tpuck_mps\tcame_cm\tskating_mps\tturning_dps\tmouse_px"]
	for e: PackedFloat64Array in _log:
		lines.append("%.1f\t%s\t%.2f\t%.0f\t%.1f\t%.0f\t%.0f" % [_clock - e[0],
				_CAUSE_NAMES[int(e[1])], e[2], e[3] * 100.0, e[4], e[5], e[6]])
	return "\n".join(lines)


func _on_face_changed(cause: int, speed: float, travel_m: float) -> void:
	var v := Vector2(_skater.velocity.x, _skater.velocity.z)
	record(cause, speed, travel_m, v.length(), _turn_rate, _mouse_travel(MOUSE_WINDOW_S))


func _watch(skater: Skater) -> void:
	if skater == _skater:
		return
	if _skater != null and is_instance_valid(_skater) \
			and _skater.carry_face_changed.is_connected(_on_face_changed):
		_skater.carry_face_changed.disconnect(_on_face_changed)
	_skater = skater
	_facing_prev = INF
	if _skater != null:
		_skater.carry_face_changed.connect(_on_face_changed)


func _find_local_skater() -> Skater:
	if _skater != null and is_instance_valid(_skater):
		return _skater
	for node: Node in get_tree().get_nodes_in_group("skaters"):
		var candidate: Skater = node as Skater
		if candidate != null and candidate.is_local_skater:
			return candidate
	return null


# Screen pixels the mouse travelled over the last `window_s`.
func _mouse_travel(window_s: float) -> float:
	var total: float = 0.0
	var i: int = _mouse_head
	for _n: int in _MOUSE_RING - 1:
		var prev: int = (i - 1 + _MOUSE_RING) % _MOUSE_RING
		if _mouse_t[prev] < _clock - window_s:
			break
		total += _mouse_pos[i].distance_to(_mouse_pos[prev])
		i = prev
	return total


func _render() -> String:
	var t: String = "[b][color=#%s]Stickhandling[/color][/b]  [color=#%s]F9 close · F10 copy log[/color]\n" % [COL_HEAD, COL_DIM]
	if _skater == null:
		return t + "[color=#%s]no local skater[/color]" % COL_DIM
	var carrying: bool = SkaterStateMachine.state_has_puck(_skater.current_shot_state)
	var v := Vector2(_skater.velocity.x, _skater.velocity.z)
	t += "[color=#%s]%s[/color]  skating [color=#%s]%.1f m/s[/color]  turning [color=#%s]%.0f°/s[/color]  mouse [color=#%s]%.0f px[/color] in %.1f s\n" % [
			COL_VAL, "CARRYING" if carrying else "no puck", COL_VAL, v.length(),
			COL_VAL, _turn_rate, COL_VAL, _mouse_travel(MOUSE_WINDOW_S), MOUSE_WINDOW_S]
	if carrying:
		t += "face [color=#%s]%+.2f[/color] (+1 forehand)  puck at the face [color=#%s]%+.2f m/s[/color]  hop [color=#%s]%.0f%%[/color]  toe drag [color=#%s]%.2f[/color]\n" % [
				COL_VAL, _skater.get_carry_forehand_factor(), COL_VAL,
				_skater.carry_stroke_toward_blade(), COL_VAL,
				_skater.get_carry_transit_factor() * 100.0, COL_VAL, _skater.get_toe_drag_factor()]
	var counts: PackedInt32Array = [0, 0, 0, 0, 0]
	for e: PackedFloat64Array in _log:
		if _clock - e[0] <= COUNT_WINDOW_S:
			counts[int(e[1])] += 1
	t += "last %.0f s: [color=#%s]%d RETURN · %d REPUSH · %d RELEASE[/color]\n" % [
			COUNT_WINDOW_S, COL_VAL, counts[1], counts[2], counts[3]]
	t += "[table=7][cell][color=#%s]ago[/color][/cell][cell][color=#%s]cause[/color][/cell][cell][color=#%s]puck m/s[/color][/cell][cell][color=#%s]came cm[/color][/cell][cell][color=#%s]skating[/color][/cell][cell][color=#%s]turning °/s[/color][/cell][cell][color=#%s]mouse px[/color][/cell]" % [
			COL_DIM, COL_DIM, COL_DIM, COL_DIM, COL_DIM, COL_DIM, COL_DIM]
	for k: int in range(_log.size() - 1, -1, -1):
		var e: PackedFloat64Array = _log[k]
		var still: bool = e[6] < 10.0
		t += "[cell]%.1f s  [/cell][cell]%s  [/cell][cell]%.2f  [/cell][cell]%.0f  [/cell][cell]%.1f  [/cell][cell]%.0f  [/cell][cell][color=#%s]%.0f%s[/color][/cell]" % [
				_clock - e[0], _CAUSE_NAMES[int(e[1])], e[2], e[3] * 100.0, e[4], e[5],
				COL_FLAG if still else COL_VAL, e[6], " still" if still else ""]
	t += "[/table]"
	if _status != "":
		t += "\n[color=#%s]%s[/color]" % [COL_DIM, _status]
	return t

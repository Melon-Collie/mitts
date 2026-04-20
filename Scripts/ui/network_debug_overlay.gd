class_name NetworkDebugOverlay
extends CanvasLayer

var _label: Label
var _showing: bool = false

func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	panel.add_child(_label)
	add_child(panel)
	hide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo:
		_showing = not _showing
		visible = _showing

func _process(_delta: float) -> void:
	if not _showing or NetworkTelemetry.instance == null:
		return
	var t: NetworkTelemetry = NetworkTelemetry.instance
	_label.text = (
		"── Net Debug (F3 to close) ──────\n"
		+ "RTT:           — (Phase 4)\n"
		+ "WS recv:       %.1f Hz\n" % t.world_state_hz
		+ "Input send:    %.1f Hz\n" % t.input_hz
		+ "Reconcile:     %.1f/s   avg %.3f m\n" % [t.reconcile_per_sec, t.reconcile_magnitude_avg]
		+ "Extrapolation: %.1f/s\n" % t.extrapolation_per_sec
		+ "Buf depth:     skater=%d  puck=%d  goalie=%d" % [t.buffer_depth_skater, t.buffer_depth_puck, t.buffer_depth_goalie]
	)

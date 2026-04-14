class_name HUD
extends CanvasLayer

@export var score_font_size: int = 32
@export var phase_font_size: int = 20
@export var panel_position: Vector2 = Vector2(16.0, 16.0)
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.65)

var _score_label: Label
var _phase_label: Label
var _period_label: Label
var _clock_label: Label
var _elevation_panel: PanelContainer
var _local_skater: Skater = null

func _ready() -> void:
	_build_scorebug()
	_build_elevation_indicator()
	if NetworkManager.is_host:
		_build_reset_button()
	_score_label.text = "0 \u2013 0"
	_phase_label.visible = false
	_period_label.text = "PERIOD 1"
	_clock_label.text = _format_clock(GameRules.PERIOD_DURATION)
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.period_changed.connect(_on_period_changed)
	GameManager.clock_updated.connect(_on_clock_updated)
	GameManager.game_over.connect(_on_game_over)

func _process(_delta: float) -> void:
	if _local_skater == null:
		var record: PlayerRecord = GameManager.get_local_player()
		if record:
			_local_skater = record.skater
	if _local_skater != null:
		_elevation_panel.visible = _local_skater.is_elevated

func _build_scorebug() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.position = panel_position
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", score_font_size)
	_score_label.add_theme_color_override("font_color", Color.WHITE)
	_score_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_score_label.add_theme_constant_override("shadow_offset_x", 1)
	_score_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(_score_label)

	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", phase_font_size)
	_phase_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	vbox.add_child(_phase_label)

	_period_label = Label.new()
	_period_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_period_label.add_theme_font_size_override("font_size", phase_font_size)
	_period_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_period_label)

	_clock_label = Label.new()
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", score_font_size)
	_clock_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	vbox.add_child(_clock_label)

func _build_elevation_indicator() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)

	_elevation_panel = PanelContainer.new()
	_elevation_panel.add_theme_stylebox_override("panel", style)
	_elevation_panel.anchor_left = 0.5
	_elevation_panel.anchor_right = 0.5
	_elevation_panel.anchor_top = 1.0
	_elevation_panel.anchor_bottom = 1.0
	_elevation_panel.offset_left = -60.0
	_elevation_panel.offset_right = 60.0
	_elevation_panel.offset_top = -48.0
	_elevation_panel.offset_bottom = -16.0
	_elevation_panel.visible = false
	add_child(_elevation_panel)

	var label := Label.new()
	label.text = "\u2191 ELEVATED"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0, 1.0))
	_elevation_panel.add_child(label)

func _build_reset_button() -> void:
	var btn := Button.new()
	btn.text = "Reset"
	btn.add_theme_font_size_override("font_size", 14)
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 0.0
	btn.anchor_bottom = 0.0
	btn.offset_left = -88.0
	btn.offset_right = -16.0
	btn.offset_top = 16.0
	btn.offset_bottom = 48.0
	btn.pressed.connect(GameManager.reset_game)
	add_child(btn)

func _on_score_changed(score_0: int, score_1: int) -> void:
	_score_label.text = "%d \u2013 %d" % [score_0, score_1]

func _on_phase_changed(new_phase: int) -> void:
	match new_phase:
		GamePhase.Phase.PLAYING:
			_phase_label.visible = false
			_phase_label.text = ""
		GamePhase.Phase.GOAL_SCORED:
			_phase_label.text = "GOAL!"
			_phase_label.visible = true
		GamePhase.Phase.END_OF_PERIOD:
			_phase_label.text = "END OF PERIOD"
			_phase_label.visible = true
		GamePhase.Phase.GAME_OVER:
			_phase_label.text = "GAME OVER"
			_phase_label.visible = true
		_:
			_phase_label.text = "FACEOFF"
			_phase_label.visible = true

func _on_period_changed(new_period: int) -> void:
	_period_label.text = "PERIOD %d" % new_period

func _on_clock_updated(t: float) -> void:
	_clock_label.text = _format_clock(t)

func _on_game_over() -> void:
	_phase_label.text = "GAME OVER"
	_phase_label.visible = true

func _format_clock(t: float) -> String:
	var secs: int = int(ceil(t))
	return "%d:%02d" % [secs / 60, secs % 60]

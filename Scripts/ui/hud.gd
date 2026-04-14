class_name HUD
extends CanvasLayer

@export var score_font_size: int = 32
@export var phase_font_size: int = 20
@export var panel_position: Vector2 = Vector2(16.0, 16.0)
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.65)

var _score_label: Label
var _phase_label: Label
var _elevation_panel: PanelContainer
var _local_skater: Skater = null

func _ready() -> void:
	_build_scorebug()
	_build_elevation_indicator()
	if NetworkManager.is_host:
		_build_reset_button()
	_score_label.text = "0 \u2013 0"
	_phase_label.visible = false
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.phase_changed.connect(_on_phase_changed)

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
	if new_phase == GamePhase.Phase.PLAYING:
		_phase_label.visible = false
		_phase_label.text = ""
	elif new_phase == GamePhase.Phase.GOAL_SCORED:
		_phase_label.text = "GOAL!"
		_phase_label.visible = true
	else:
		_phase_label.text = "FACEOFF"
		_phase_label.visible = true

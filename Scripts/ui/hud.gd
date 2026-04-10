class_name HUD
extends CanvasLayer

@export var score_font_size: int = 32
@export var phase_font_size: int = 20
@export var panel_position: Vector2 = Vector2(16.0, 16.0)
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.65)

var _score_label: Label
var _phase_label: Label

func _ready() -> void:
	_build_scorebug()
	_score_label.text = "0 \u2013 0"
	_phase_label.visible = false
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.phase_changed.connect(_on_phase_changed)

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

func _on_score_changed(_team: Team) -> void:
	_score_label.text = "%d \u2013 %d" % [GameManager.teams[0].score, GameManager.teams[1].score]

func _on_phase_changed(new_phase: int) -> void:
	if new_phase == GameManager.GamePhase.PLAYING:
		_phase_label.visible = false
		_phase_label.text = ""
	elif new_phase == GameManager.GamePhase.GOAL_SCORED:
		_phase_label.text = "GOAL!"
		_phase_label.visible = true
	else:
		_phase_label.text = "FACEOFF"
		_phase_label.visible = true

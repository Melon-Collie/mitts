class_name HudIcingRace
extends Node

# NHL hybrid icing as every peer sees it — the linesman's raised arm. A banner
# while the host judges a race to the end-zone dots, telling the local player
# which side of it they are on, then a brief washout if it is waved off. A race
# that ends in icing hands over to the whistle's own toast.

const _WASHOUT_S: float = 1.5

var _root: Control = null
var _title_label: Label = null
var _instr_label: Label = null
var _icing_team_id: int = -1
var _washout_left: float = 0.0
var _pulse_t: float = 0.0


func build(scale_root: Control) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Under the infraction banner's band, so a tag-up and a race can show at once.
	root.offset_top = 224.0
	root.offset_bottom = 330.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = root
	scale_root.add_child(root)

	var centering := CenterContainer.new()
	centering.set_anchors_preset(Control.PRESET_FULL_RECT)
	centering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centering)

	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.BROADCAST_BG
	style.set_corner_radius_all(4)
	style.anti_aliasing = false
	style.set_content_margin(SIDE_LEFT, 24)
	style.set_content_margin(SIDE_RIGHT, 24)
	style.set_content_margin(SIDE_TOP, 8)
	style.set_content_margin(SIDE_BOTTOM, 8)
	style.set_border_width_all(2)
	style.border_color = MenuStyle.GOLD

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	centering.add_child(MenuStyle.wrap_drop_shadow(panel, Vector2(4, 4)))

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	_title_label = HudChrome.lbl("", 26, MenuStyle.GOLD)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_instr_label = HudChrome.lbl("", 15, MenuStyle.BROADCAST_CREAM)
	_instr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_instr_label)

	root.visible = false


# GameManager.icing_race_changed: a race opened (icing_team_id), or ended (-1).
func on_icing_race_changed(icing_team_id: int, waved_off: bool) -> void:
	_icing_team_id = icing_team_id
	_washout_left = 0.0
	if icing_team_id != -1:
		_show(tr(&"ICING_RACE_TITLE"), tr(_race_instruction_key()))
	elif waved_off:
		_washout_left = _WASHOUT_S
		_show(tr(&"ICING_WAVED_OFF"), "")
	else:
		_root.visible = false


func is_showing() -> bool:
	return _root != null and _root.visible


func title_text() -> String:
	return _title_label.text if _title_label != null else ""


func _process(delta: float) -> void:
	if not is_showing():
		return
	if _icing_team_id != -1:
		_pulse_t += delta * 4.0
		_root.modulate.a = 0.75 + 0.25 * sin(_pulse_t)
		return
	_washout_left -= delta
	if _washout_left <= 0.0:
		_root.visible = false


func _race_instruction_key() -> StringName:
	var record: PlayerRecord = GameManager.get_local_player()
	if record == null or record.team == null:
		return &"ICING_RACE_WATCH"
	return &"ICING_RACE_ATTACK" if record.team.team_id == _icing_team_id \
			else &"ICING_RACE_DEFEND"


func _show(title: String, instruction: String) -> void:
	_title_label.text = title
	_instr_label.text = instruction
	_instr_label.visible = not instruction.is_empty()
	_root.modulate.a = 1.0
	_root.visible = true

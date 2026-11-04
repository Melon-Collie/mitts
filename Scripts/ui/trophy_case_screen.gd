class_name TrophyCaseScreen extends Control

# The Trophy Case (docs/game-pucks-plan.md): the banners and how close each is,
# the career ladders with their tiers, and the single Game Pucks. Read-only — it
# shows what TrophyService and the Steam counters already hold, rebuilt on open.

const _CARD_WIDTH: float = 300.0
const _PUCK_CARD_WIDTH: float = 250.0
const _SCROLL_STEP_PX: int = 90
const _EARNED := MenuStyle.GOLD
const _CHECK: String = "✓"
const _OPEN: String = "○"

var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _summary: Label = null
var _close_btn: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.024, 0.039, 0.071, 0.96)
	add_child(overlay)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vbox.add_child(head)
	head.add_child(_label(tr(&"TROPHY_CASE_TITLE"), 30, MenuStyle.BROADCAST_CREAM, true))
	_summary = _label("", 13, MenuStyle.TEXT_MUTED, false)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_summary)
	_close_btn = MenuStyle.close_button()
	_close_btn.pressed.connect(hide)
	SoundManager.wire_button(_close_btn)
	head.add_child(_close_btn)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)

	hide()


func open() -> void:
	var ledger: TrophyLedger = PlayerPrefs.trophy_ledger
	if TrophyService.import_steam_unlocks(ledger):
		PlayerPrefs.save()
	_rebuild(SteamStatRecorder.new().totals(), ledger)
	_scroll.scroll_vertical = 0
	show()
	if ControllerNav.active():
		_close_btn.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down", true):
		_scroll.scroll_vertical += _SCROLL_STEP_PX
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up", true):
		_scroll.scroll_vertical -= _SCROLL_STEP_PX
		get_viewport().set_input_as_handled()


func _rebuild(totals: Dictionary, ledger: TrophyLedger) -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if not SteamManager.is_available:
		var note := _label(tr(&"TROPHY_NEEDS_STEAM"), 13, MenuStyle.TEXT_DIM, false)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(note)

	_body.add_child(_section_label(tr(&"TROPHY_BANNERS")))
	var banners := HFlowContainer.new()
	banners.add_theme_constant_override("h_separation", 12)
	banners.add_theme_constant_override("v_separation", 12)
	_body.add_child(banners)
	var raised: int = 0
	for banner: Dictionary in Banners.ALL:
		if GamePuckRules.is_raised(banner, totals, ledger):
			raised += 1
		banners.add_child(_banner_card(banner, totals, ledger))

	_body.add_child(_section_label(tr(&"TROPHY_LADDERS")))
	var ladders := HFlowContainer.new()
	ladders.add_theme_constant_override("h_separation", 12)
	ladders.add_theme_constant_override("v_separation", 12)
	_body.add_child(ladders)
	_body.add_child(_section_label(tr(&"TROPHY_GAME_PUCKS")))
	var singles := HFlowContainer.new()
	singles.add_theme_constant_override("h_separation", 12)
	singles.add_theme_constant_override("v_separation", 12)
	_body.add_child(singles)

	var earned: int = 0
	var total: int = 0
	for entry: Dictionary in GamePucks.ALL:
		var id: String = entry["id"]
		if GamePucks.is_ladder(entry):
			var reached: int = GamePuckRules.tiers_reached(entry, totals)
			earned += reached
			total += GamePucks.tiers_of(entry).size()
			ladders.add_child(_ladder_card(entry, totals, reached))
		else:
			total += 1
			if ledger.has(id):
				earned += 1
			singles.add_child(_puck_card(entry, ledger))
	_summary.text = tr(&"TROPHY_SUMMARY") % [earned, total, raised, Banners.ALL.size()]


func _banner_card(banner: Dictionary, totals: Dictionary, ledger: TrophyLedger) -> Control:
	var is_up: bool = GamePuckRules.is_raised(banner, totals, ledger)
	var col := _card(_CARD_WIDTH, is_up)
	var id: String = banner["id"]
	col.add_child(_label(TrophyCopy.banner_name(id).to_upper(), 22,
			_EARNED if is_up else MenuStyle.BROADCAST_CREAM, true))
	var needs: Array[String] = Banners.needs_of(banner)
	var status: String = tr(&"TROPHY_RAISED") if is_up else tr(&"TROPHY_PROGRESS") % [
		GamePuckRules.banner_progress(banner, totals, ledger), needs.size()]
	col.add_child(_label(status, 12, _EARNED if is_up else MenuStyle.TEXT_MUTED, false))
	var title: String = Banners.title_of(banner)
	if not title.is_empty():
		col.add_child(_label(tr(&"TROPHY_BANNER_TITLE") % TrophyCopy.title_name(title), 13,
				_EARNED if is_up else MenuStyle.TEXT_DIM, false))
	for reward: Dictionary in CosmeticUnlocks.rewards_of(id):
		if String(reward["slot"]) == CosmeticUnlocks.TAPE_SPAN:
			col.add_child(_label(tr(&"TROPHY_BANNER_TAPE") % tr(
					StickTapeConfig.SPAN_NAME_KEYS[int(reward["option"])]), 13,
					_EARNED if is_up else MenuStyle.TEXT_DIM, false))
	for req: String in needs:
		var met: bool = GamePuckRules.requirement_met(req, totals, ledger)
		var puck: String = Banners.requirement_puck(req)
		var target: int = Banners.requirement_target(req)
		var line: String = "%s %s" % [_CHECK if met else _OPEN, TrophyCopy.puck_name(puck, target)]
		if target > 0 and not met:
			var field: String = String((GamePucks.find(puck)["cond"] as Dictionary)["field"])
			line = tr(&"TROPHY_REQUIREMENT_PROGRESS") % [
				line, GamePuckRules.counter(totals, field), target]
		col.add_child(_label(line, 14, MenuStyle.TEXT_BODY if met else MenuStyle.TEXT_DIM, false))
	return col.get_parent() as Control


func _ladder_card(entry: Dictionary, totals: Dictionary, reached: int) -> Control:
	var tiers: Array[int] = GamePucks.tiers_of(entry)
	var done: bool = reached == tiers.size()
	var col := _card(_CARD_WIDTH, done)
	var id: String = entry["id"]
	var field: String = String((entry["cond"] as Dictionary)["field"])
	var value: int = GamePuckRules.counter(totals, field)
	var head := HBoxContainer.new()
	head.add_child(_label(TrophyCopy.puck_name(id).to_upper(), 18, MenuStyle.BROADCAST_CREAM, true))
	var count := _label(str(value), 22, _EARNED if reached > 0 else MenuStyle.TEXT_DIM, true)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(count)
	col.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for i: int in tiers.size():
		row.add_child(_tier_mark(tiers[i], i < reached))
	col.add_child(row)
	var next: String = tr(&"TROPHY_LADDER_DONE") if done \
			else TrophyCopy.puck_desc(id, tiers[reached])
	col.add_child(_label(next, 13, _EARNED if done else MenuStyle.TEXT_DIM, false))
	return col.get_parent() as Control


func _puck_card(entry: Dictionary, ledger: TrophyLedger) -> Control:
	var id: String = entry["id"]
	var has_it: bool = ledger.has(id)
	var col := _card(_PUCK_CARD_WIDTH, has_it)
	var secret: bool = bool(entry.get("hidden", false)) and not has_it
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_PuckMark.new(has_it))
	head.add_child(_label(tr(&"TROPHY_HIDDEN") if secret else TrophyCopy.puck_name(id),
			16, _EARNED if has_it else MenuStyle.BROADCAST_CREAM, true))
	col.add_child(head)
	var desc := _label(tr(&"TROPHY_HIDDEN_DESC") if secret else TrophyCopy.puck_desc(id),
			13, MenuStyle.TEXT_DIM, false)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	var when: String = tr(&"TROPHY_NOT_YET")
	if has_it:
		var at: int = ledger.earned_at(id)
		when = tr(&"TROPHY_EARNED_ON") % Time.get_date_string_from_unix_time(at) \
				if at > 0 else tr(&"TROPHY_EARNED")
	col.add_child(_label(when, 12, _EARNED if has_it else MenuStyle.TEXT_MUTED, false))
	return col.get_parent() as Control


# A tier: its puck, filled when reached, over its target.
func _tier_mark(target: int, reached: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var mark := _PuckMark.new(reached)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(mark)
	var num := _label(str(target), 11, _EARNED if reached else MenuStyle.TEXT_MUTED, false)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(num)
	return col


# A broadcast panel of `width` holding a column; returns the column; the panel is
# its parent.
func _card(width: float, lit: bool) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.BROADCAST_BG
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = _EARNED if lit else MenuStyle.BROADCAST_SEP
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	return col


func _section_label(text: String) -> Label:
	return _label(text.to_upper(), 13, MenuStyle.BROADCAST_DIM, false)


func _label(text: String, font_size: int, color: Color, display: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuStyle.DISPLAY_FONT if display else MenuStyle.UI_FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


# A puck seen from above: a filled disc when earned, a ring when not.
class _PuckMark extends Control:
	const RADIUS: float = 9.0
	var _earned: bool = false

	func _init(earned: bool) -> void:
		_earned = earned
		custom_minimum_size = Vector2(RADIUS * 2.0 + 2.0, RADIUS * 2.0 + 2.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		if _earned:
			draw_circle(c, RADIUS, MenuStyle.GOLD)
			draw_arc(c, RADIUS * 0.62, 0.0, TAU, 24, Color(0, 0, 0, 0.25), 1.5, true)
		else:
			draw_arc(c, RADIUS, 0.0, TAU, 32, MenuStyle.TEXT_MUTED, 1.5, true)

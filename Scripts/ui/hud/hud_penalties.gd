class_name HudPenalties
extends Node

# Penalties as every peer sees them: a strip under the scorebug with the
# manpower and the minor nearest its end, and a banner for the moments a
# player has to read — the referee's arm going up, his own time in the box,
# and a penalty shot being taken.

var _strip_wrap: Control = null
var _strip_label: Label = null
var _banner_root: Control = null
var _title_label: Label = null
var _detail_label: Label = null

var _ledger: PenaltyLedger = null
var _team_size: int = GameRules.DEFAULT_TEAM_SIZE
var _local_peer_id: int = -1
var _local_team_id: int = -1
var _shooter_name: String = ""
# The clock second on screen, so the text is rebuilt once a second, not a frame.
var _shown_second: int = -1


func build(scale_root: Control) -> void:
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = MenuStyle.BROADCAST_BG
	strip_style.set_corner_radius_all(4)
	strip_style.set_content_margin(SIDE_LEFT, 10)
	strip_style.set_content_margin(SIDE_RIGHT, 10)
	strip_style.set_content_margin(SIDE_TOP, 3)
	strip_style.set_content_margin(SIDE_BOTTOM, 3)
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", strip_style)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_label = HudChrome.lbl("", 15, MenuStyle.GOLD)
	strip.add_child(_strip_label)
	_strip_wrap = MenuStyle.wrap_drop_shadow(strip, Vector2(4, 4))
	_strip_wrap.visible = false
	scale_root.add_child(_strip_wrap)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Under the icing race's band, so a race and a delayed call can show at once.
	root.offset_top = 336.0
	root.offset_bottom = 430.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_root = root
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
	_detail_label = HudChrome.lbl("", 15, MenuStyle.BROADCAST_CREAM)
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_detail_label)
	root.visible = false


# GameManager.penalties_changed. `strip_top_left` is where the strip sits, just
# under the scorebug. `local_team_id` is -1 for a spectator; `shooter_name` is
# who is taking the penalty shot on, if one is.
func show_ledger(ledger: PenaltyLedger, team_size: int, local_peer_id: int,
		local_team_id: int, strip_top_left: Vector2, shooter_name: String = "") -> void:
	_ledger = ledger
	_team_size = team_size
	_local_peer_id = local_peer_id
	_local_team_id = local_team_id
	_shooter_name = shooter_name
	_strip_wrap.position = strip_top_left
	_shown_second = -1
	_refresh()


# The banner's title, "" while it is down.
func banner_title() -> String:
	return _title_label.text if _banner_root.visible else ""


# The strip's text, "" while it is down.
func strip_text() -> String:
	return _strip_label.text if _strip_wrap.visible else ""


func _process(_delta: float) -> void:
	if _ledger == null or _ledger.is_empty():
		return
	if _clock_second() != _shown_second:
		_refresh()


# The second the soonest-ending clock on screen reads; -1 with none running.
func _clock_second() -> int:
	var soonest: float = _soonest_remaining()
	return int(ceil(soonest)) if soonest >= 0.0 else -1


func _soonest_remaining() -> float:
	var home: float = _ledger.soonest_remaining(0)
	var away: float = _ledger.soonest_remaining(1)
	if home < 0.0:
		return away
	if away < 0.0:
		return home
	return minf(home, away)


func _refresh() -> void:
	_shown_second = _clock_second() if _ledger != null else -1
	_refresh_strip()
	_refresh_banner()


func _refresh_strip() -> void:
	var soonest: float = _soonest_remaining() if _ledger != null else -1.0
	_strip_wrap.visible = soonest >= 0.0
	if soonest < 0.0:
		return
	var home: int = _ledger.strength(0, _team_size)
	var away: int = _ledger.strength(1, _team_size)
	_strip_label.text = "%s   %s" % [
			tr(&"PENALTY_STRENGTH") % [maxi(home, away), mini(home, away)],
			HudChrome.format_clock(soonest)]
	# The clock belongs to the team with the extra man; gold at even strength.
	_strip_label.add_theme_color_override("font_color", MenuStyle.GOLD if home == away
			else HudChrome.team_ink(0 if home > away else 1))


func _refresh_banner() -> void:
	if _ledger != null and _ledger.shooter_peer_id() != -1:
		_title_label.text = tr(&"PENALTY_SHOT_TITLE")
		_detail_label.text = _shooter_name
		_banner_root.visible = true
	elif _ledger != null and _ledger.is_boxed(_local_peer_id):
		_title_label.text = tr(&"PENALTY_BOX_TITLE")
		var remaining: float = _ledger.remaining_for(_local_peer_id)
		var foul: String = tr(PenaltyRules.name_key(_ledger.foul_of(_local_peer_id)))
		_detail_label.text = tr(&"PENALTY_BOX_LINE") % [foul, HudChrome.format_clock(remaining)]
		_banner_root.visible = true
	elif _ledger != null and _ledger.has_pending():
		_title_label.text = tr(&"PENALTY_DELAYED_TITLE")
		if _local_team_id == -1:
			_detail_label.text = ""
		elif _ledger.has_pending_against(_local_team_id):
			_detail_label.text = tr(&"PENALTY_DELAYED_OFFENDING")
		else:
			_detail_label.text = tr(&"PENALTY_DELAYED_FOULED")
		_banner_root.visible = true
	else:
		_banner_root.visible = false

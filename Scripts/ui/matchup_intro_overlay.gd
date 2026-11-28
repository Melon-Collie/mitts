class_name MatchupIntroOverlay
extends CanvasLayer

# Opening-faceoff matchup card, the broadcast's starting lineups: two team
# panels on the scorebug's dark surface, away on the left as the scorebug lists
# it, a VS disc between them and the title in a pill above. Each panel is headed
# by its club's badge at hero scale (TeamBadge: the crest cropped at the
# panel's outer edge, the club's name), with the lineup below. The camera
# sweep and the skate-on stay visible round it through a medium dim wash.
#
# Deliberately no build readout: the attribute system is all-lateral (two body
# dials and gear leans, no build is "better"), so any summary would imply a
# power ranking; the bodies on the ice during the sweep are the honest preview.
#
# Owned by HUD, which passes the slot-sorted PlayerRecords per team and the two
# clubs. Pure presentation, no buttons: shown for the front of the
# PREGAME_INTRO_DURATION hold and dismissed before the faceoff countdown.

const _WHITE := MenuStyle.BROADCAST_CREAM
const _DIM := MenuStyle.BROADCAST_DIM

# Between the intermission reel's light wash (0.32) and the modal scrim
# (0.55): the sweep behind is mood, not content, but should still read.
const _INTRO_SCRIM := Color(0.024, 0.039, 0.071, 0.40)
const _PANEL_BG := Color(MenuStyle.BROADCAST_BG, 0.94)

const _PANEL_WIDTH: float = 500.0
const _PANEL_RADIUS: int = 6
const _TEAM_STRIPE: int = 5
# The panel's head: the club's badge, the crest about twice its height.
const _HEAD_HEIGHT: float = 78.0
const _HEAD_CREST_PX: float = 156.0
const _HEAD_NAME_SIZE: int = 30
const _HEAD_NAME_INSET: float = 64.0
const _ROW_MARGIN: int = 26
const _VS_DISC: float = 68.0
# Entry: the panels settle in from a touch small, the VS lands after them.
const _ENTER_SCALE: float = 0.96
const _ENTER_TIME: float = 0.40
const _VS_DELAY: float = 0.25

var _scrim: ColorRect = null
var _content: VBoxContainer = null
var _title_label: Label = null
var _away: Dictionary = {}
var _home: Dictionary = {}
var _vs: Control = null
var _present_tween: Tween = null


func _ready() -> void:
	layer = 4  # same shelf as the intermission overlay; the two never coexist
	_build_ui()
	visible = false


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_scrim = ColorRect.new()
	_scrim.color = _INTRO_SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_scrim)

	var centering := CenterContainer.new()
	centering.set_anchors_preset(Control.PRESET_FULL_RECT)
	centering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centering)

	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 18)
	centering.add_child(_content)

	var title_pill := PanelContainer.new()
	title_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = _PANEL_BG
	pill_style.set_corner_radius_all(4)
	pill_style.set_content_margin(SIDE_LEFT, 16)
	pill_style.set_content_margin(SIDE_RIGHT, 16)
	pill_style.set_content_margin(SIDE_TOP, 6)
	pill_style.set_content_margin(SIDE_BOTTOM, 6)
	title_pill.add_theme_stylebox_override("panel", pill_style)
	_title_label = _lbl(tr(&"MATCHUP_TITLE"), 16, _WHITE)
	_title_label.add_theme_font_override("font", MenuStyle.display_font_spaced())
	title_pill.add_child(_title_label)
	_content.add_child(title_pill)

	var panels := HBoxContainer.new()
	panels.alignment = BoxContainer.ALIGNMENT_CENTER
	panels.add_theme_constant_override("separation", 20)
	_content.add_child(panels)
	_away = _build_team_panel(false)
	panels.add_child(_away.panel)
	_vs = _build_vs()
	panels.add_child(_vs)
	_home = _build_team_panel(true)
	panels.add_child(_home.panel)


# One team's panel: the top stripe in its colour, its badge, its lineup. The
# pieces present() fills ride in the returned Dictionary. `mirrored` is the
# right-hand panel, its crest cropped at the right edge.
func _build_team_panel(mirrored: bool) -> Dictionary:
	var style := StyleBoxFlat.new()
	style.bg_color = _PANEL_BG
	style.set_corner_radius_all(_PANEL_RADIUS)
	style.border_width_top = _TEAM_STRIPE
	style.set_content_margin(SIDE_BOTTOM, 18)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(_PANEL_WIDTH, 0)
	# Crops the badge's crest to the panel's rounded corners.
	panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var badge := TeamBadge.new(_PANEL_WIDTH, _HEAD_CREST_PX, _HEAD_NAME_SIZE, _HEAD_NAME_INSET,
			HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT, mirrored)
	badge.custom_minimum_size.y = _HEAD_HEIGHT
	col.add_child(badge)

	var rule := ColorRect.new()
	rule.color = MenuStyle.BROADCAST_SEP
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)

	var rows_margin := MarginContainer.new()
	rows_margin.add_theme_constant_override("margin_left", _ROW_MARGIN)
	rows_margin.add_theme_constant_override("margin_right", _ROW_MARGIN)
	col.add_child(rows_margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows_margin.add_child(rows)
	return {"panel": panel, "style": style, "badge": badge, "rows": rows}


func _build_vs() -> Control:
	var disc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _PANEL_BG
	style.set_corner_radius_all(int(_VS_DISC * 0.5))
	style.border_color = MenuStyle.BROADCAST_BORDER_T
	style.set_border_width_all(2)
	disc.add_theme_stylebox_override("panel", style)
	disc.custom_minimum_size = Vector2(_VS_DISC, _VS_DISC)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vs := _lbl(tr(&"MATCHUP_VS"), 24, _WHITE)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(vs)
	return disc


# `title` and the two names replace "TONIGHT'S MATCHUP" and the clubs' own names
# when given: a tournament game names its round and seeds its clubs.
func present(home_records: Array[PlayerRecord], away_records: Array[PlayerRecord],
		home_club: int, away_club: int, title: String = "",
		home_name: String = "", away_name: String = "") -> void:
	_title_label.text = tr(&"MATCHUP_TITLE") if title.is_empty() else title
	var stripes: Dictionary = TeamColorRegistry.get_score_stripe_pair(home_club, away_club)
	var inks: Dictionary = TeamColorRegistry.get_score_ink_pair(home_club, away_club,
			MenuStyle.BROADCAST_BG)
	_fill_panel(_home, home_records, home_club, stripes.home, inks.home,
			home_name if not home_name.is_empty() else _club_name(home_club, &"TEAM_HOME"))
	_fill_panel(_away, away_records, away_club, stripes.away, inks.away,
			away_name if not away_name.is_empty() else _club_name(away_club, &"TEAM_AWAY"))

	visible = true
	if _present_tween != null and _present_tween.is_running():
		_present_tween.kill()
	_scrim.modulate.a = 0.0
	_content.modulate.a = 0.0
	_vs.modulate.a = 0.0
	for panel: Control in [_away.panel, _home.panel]:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2.ONE * _ENTER_SCALE
	_present_tween = create_tween()
	_present_tween.tween_property(_scrim, "modulate:a", 1.0, 0.30)
	_present_tween.parallel().tween_property(_content, "modulate:a", 1.0, _ENTER_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for panel: Control in [_away.panel, _home.panel]:
		_present_tween.parallel().tween_property(panel, "scale", Vector2.ONE, _ENTER_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_present_tween.parallel().tween_property(_vs, "modulate:a", 1.0, 0.20) \
		.set_delay(_VS_DELAY)


func hide_overlay() -> void:
	if _present_tween != null and _present_tween.is_running():
		_present_tween.kill()
	if not visible:
		return
	# Fade out rather than blink — the sweep continues underneath and the
	# banner countdown picks up the thread.
	_present_tween = create_tween()
	_present_tween.tween_property(_scrim, "modulate:a", 0.0, 0.25)
	_present_tween.parallel().tween_property(_content, "modulate:a", 0.0, 0.25)
	_present_tween.tween_callback(func() -> void: visible = false)


func _club_name(club: int, fallback_key: StringName) -> String:
	return TeamColorRegistry.get_preset_name(club).to_upper() if club >= 0 else tr(fallback_key)


func _fill_panel(side: Dictionary, records: Array[PlayerRecord], club: int,
		stripe: Color, ink: Color, team_name: String) -> void:
	(side.style as StyleBoxFlat).border_color = stripe
	(side.badge as TeamBadge).set_team(club, team_name)
	_fill_rows(side.rows, records, ink)


# Roster rebuilt per present(): once per match, a handful of rows. Each row: a
# position badge, the jersey number in the team's ink, the name. Records arrive
# slot-sorted (see hud.gd._show_matchup_overlay), so in 5v5 the forward group
# (C/LW/RW) always precedes defense (LD/RD) — "FORWARDS" / "DEFENSE" dividers
# label both groups (3v3 is position-free rovers, so it gets none).
func _fill_rows(rows: VBoxContainer, records: Array[PlayerRecord], ink: Color) -> void:
	for child: Node in rows.get_children():
		child.queue_free()
	var is_5v5: bool = records.size() >= 5
	var open_group: int = -1  # -1 = none yet, 0 = forwards, 1 = defense
	for record: PlayerRecord in records:
		var group: int = 1 if PlayerRules.is_defense_slot(record.team_slot) else 0
		if is_5v5 and group != open_group:
			_add_group_header(rows,
					tr(&"MATCHUP_GROUP_DEFENSE") if group == 1 else tr(&"MATCHUP_GROUP_FORWARDS"),
					open_group != -1)
			open_group = group
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var pos := _lbl(tr(PositionLabels.badge_key(record.team_slot, is_5v5)), 15, _DIM)
		pos.custom_minimum_size = Vector2(30, 0)
		pos.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pos)
		# Right-aligned so 7 lines up with 71.
		var num := _lbl("%d" % record.jersey_number, 20, ink)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.custom_minimum_size = Vector2(32, 0)
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(num)
		var name_label := _lbl(record.display_name(), 23, _WHITE)
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_label)
		rows.add_child(row)


# A group divider over the rows that follow it, on the position badges' rail.
# `lead_gap` opens a little air above a group that follows another one.
func _add_group_header(rows: VBoxContainer, text: String, lead_gap: bool) -> void:
	if lead_gap:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 4)
		rows.add_child(spacer)
	var head := _lbl(text, 12, _DIM)
	head.add_theme_font_override("font", MenuStyle.display_font_spaced())
	rows.add_child(head)


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuStyle.DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

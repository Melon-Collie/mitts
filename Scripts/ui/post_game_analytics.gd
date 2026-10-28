class_name PostGameAnalytics
extends CanvasLayer

# Post-game analytics screen (analytics plan §7.1) — the views, all reading the
# SAME per-game data the sim recorded, so a number and its dot on the map can
# never disagree:
#   1. Team shot map — every attempt plotted at its release point, dot size = xG,
#      goals ringed. Position + team colour is the differential read.
#   2. Tale of the tape — head-to-head bars for the broadcast box: goals, shots,
#      faceoffs, hits, blocks, takeaways, giveaways.
#   3. Advanced — the same bars for Corsi, Fenwick and xG.
#
# Data is entirely LOCAL: GameManager.get_shot_events() (the host's buffer, or a
# client's pushed copy) plus the broadcast PlayerStats counters. No Supabase, no
# online gate — so this works in offline / Play-vs-Bots exactly as it does online,
# which is where it gets playtested.
#
# Rendered on its own layer above GameOverPopup (which stays the "moment" screen:
# score, stars, what-next). Opened from its Analytics button; Escape closes.

signal closed

const _CREAM := MenuStyle.BROADCAST_CREAM
const _DIM := MenuStyle.BROADCAST_DIM
const _SEP := MenuStyle.BROADCAST_SEP
const _MUTED := MenuStyle.TEXT_MUTED
const _GOLD := MenuStyle.GOLD

# Rink geometry (GameRules mirrors) for the map's coordinate transform.
const _HALF_LEN: float = GameRules.RINK_HALF_LENGTH
const _HALF_WID: float = GameRules.RINK_HALF_WIDTH
const _GOAL_LINE: float = GameRules.GOAL_LINE_Z
const _BLUE_LINE: float = GameRules.BLUE_LINE_Z

var _root: Control = null
var _map: RinkMap = null
var _tape: GridContainer = null
var _advanced: VBoxContainer = null
var _subtitle: Label = null
var _close_btn: Button = null
# Controller focus scope: the screen underneath (game-over popup / career
# screen), walled off while this is up. Set by the opener via set_focus_scope.
var _focus_background: Control = null
var _focus_restore: Control = null
var _team_colors: Array[Color] = [Color(0.85, 0.35, 0.15), Color(0.22, 0.53, 0.90)]


func _ready() -> void:
	# Above the whole menu stack, not just the game-over screen: this opens from
	# the career screen too, which is reached through the side menu / pause menu
	# (both layer 20) and can sit under ConfirmDialog (22) and DisplayRevert (23).
	# Below ControllerKeyboard (40) and LoadingScreen (100), which must never be
	# occluded. Escape still closes this first — it consumes ui_cancel in
	# _unhandled_input, so the pause menu doesn't open behind it.
	layer = 24
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = Color(0.024, 0.039, 0.071, 0.93)  # near-opaque: this is a reading screen
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_map_panel())
	col.add_child(_build_lower_row())
	col.add_child(_build_footer())


func _build_header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var title := _lbl("GAME ANALYTICS", 26, _CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_subtitle = _lbl("", 13, _MUTED)
	_subtitle.add_theme_font_override("font", MenuStyle.UI_FONT)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_subtitle)
	return box


func _build_map_panel() -> Control:
	var panel := _panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_section_title("SHOT MAP", "dot size = expected goals"))

	_map = RinkMap.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.custom_minimum_size = Vector2(0, 240)
	col.add_child(_map)

	col.add_child(_build_map_legend())
	return panel


# Outcome is carried by dot STYLE (filled / hollow / faded / ringed), team by
# colour — so neither channel has to do both jobs.
func _build_map_legend() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	for spec: Array in [
			["Goal", RinkMap.LEGEND_GOAL], ["On goal", RinkMap.LEGEND_ON_NET],
			["Missed", RinkMap.LEGEND_MISSED], ["Blocked", RinkMap.LEGEND_BLOCKED]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		var swatch := LegendDot.new()
		swatch.kind = int(spec[1])
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(swatch)
		var text := _lbl(String(spec[0]), 12, _DIM)
		text.add_theme_font_override("font", MenuStyle.UI_FONT)
		item.add_child(text)
		row.add_child(item)
	return row


# The broadcast box two rows abreast, the advanced rows beside it in a panel of
# their own.
func _build_lower_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var tape_col := _lower_panel(row, tr(&"TAPE_TITLE"), _CREAM, 2.0)
	_tape = GridContainer.new()
	_tape.columns = 2
	_tape.add_theme_constant_override("h_separation", 28)
	_tape.add_theme_constant_override("v_separation", 10)
	tape_col.add_child(_tape)

	# Gold: these are the rows no broadcast carries.
	var adv_col := _lower_panel(row, tr(&"TAPE_ADVANCED"), _GOLD, 1.0)
	_advanced = VBoxContainer.new()
	_advanced.add_theme_constant_override("separation", 10)
	adv_col.add_child(_advanced)
	return row


func _lower_panel(row: HBoxContainer, title: String, title_color: Color,
		stretch: float) -> VBoxContainer:
	var panel := _panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(_section_title(title.to_upper(), "", title_color))
	row.add_child(panel)
	return col


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(150, 38)
	close_btn.add_theme_font_size_override("font_size", 16)
	MenuStyle.wire_hover_scale(close_btn)
	SoundManager.wire_button(close_btn)
	MenuStyle.apply_focus_ring(close_btn)
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	_close_btn = close_btn  # the screen's only control — the pad's focus target
	return row


# ── Presentation ─────────────────────────────────────────────────────────────

func present() -> void:
	_refresh()
	_show()


# `background` is the screen this covers (the game-over popup's content root, or
# the career screen); focus is walled off there while this is up and handed back
# to whatever held it when this opened.
func set_focus_background(background: Control) -> void:
	_focus_background = background


# Reveal only — the data is already in place. Kept separate from present() so
# present_history() can inject its own render without the live path clobbering it.
func _show() -> void:
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.18)
	# Close is the only control here, so without this the pad has nothing focused
	# on a near-opaque full-screen reader.
	_focus_restore = ControllerNav.focus_owner(self)
	ControllerNav.open_modal(_focus_background, self, _close_btn)


func close() -> void:
	visible = false
	ControllerNav.close_modal(_focus_background, _focus_restore)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Live match just played: everything comes from GameManager.
func _refresh() -> void:
	_render(GameManager.get_shot_events(), _team_totals(), _resolve_team_colors(), "")


# A PAST game, from stored shot events (Supabase rows or a .mreplay footer).
# Nothing about the old match is in memory, so the tape is derived from the
# events themselves — which is self-consistent, since the map reads the same
# list — except the score, which comes from the authoritative record.
# `home_goals`/`away_goals` may be -1 when unknown, in which case goals are
# counted from the events too. `box_score` is the .mreplay footer's per-player
# list; without one the rows only a box score can fill are left off.
func present_history(events: Array[ShotEvent], home_goals: int, away_goals: int,
		label: String, colors: Array[Color] = [], box_score: Array = []) -> void:
	var totals: Array[Dictionary] = history_totals(events, box_score)
	if home_goals >= 0:
		totals[0]["goals"] = home_goals
	if away_goals >= 0:
		totals[1]["goals"] = away_goals
	# The match's real palette when the caller could recover it (the .mreplay
	# header records both colour slots); the neutral defaults otherwise — never
	# the CURRENT session's colours, which would paint an old game in a palette
	# it was never played in.
	_render(events, totals, colors if colors.size() == 2 else _team_colors, label)
	_show()


func _render(events: Array[ShotEvent], totals: Array[Dictionary],
		colors: Array[Color], label: String) -> void:
	_team_colors = colors
	_map.configure(events, _team_colors)
	_build_tape_rows(totals)

	var attempts: int = int(totals[0]["corsi"]) + int(totals[1]["corsi"])
	var suffix: String = label if not label.is_empty() \
			else "every coordinate recorded by the sim"
	_subtitle.text = "%d shot attempts · %s" % [attempts, suffix]


# One team's tape aggregates, zeroed. `box` marks the counters only a box score
# carries (hits, faceoffs, takeaways, giveaways); a past game without one leaves
# it false and those rows off.
static func _empty_totals() -> Dictionary:
	return {"goals": 0, "sog": 0, "corsi": 0, "fenwick": 0, "xg": 0.0, "blocks": 0,
			"box": false, "hits": 0, "faceoff_wins": 0, "takeaways": 0, "giveaways": 0}


# Per-team aggregates for a past game: the shot list's, plus the box score's
# counters when there is one. Same conventions as the live counters: Corsi counts
# every attempt, Fenwick excludes blocks, xG accrues only on unblocked shots, and
# a blocked attempt is a block for the team that DEFENDED it.
static func history_totals(events: Array[ShotEvent], box_score: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = [_empty_totals(), _empty_totals()]
	for e: ShotEvent in events:
		var t: int = clampi(e.team_id, 0, 1)
		out[t]["corsi"] = int(out[t]["corsi"]) + 1
		if e.outcome == ShotEvent.Outcome.BLOCKED:
			out[1 - t]["blocks"] = int(out[1 - t]["blocks"]) + 1
			continue
		out[t]["fenwick"] = int(out[t]["fenwick"]) + 1
		out[t]["xg"] = float(out[t]["xg"]) + e.xg
		if e.outcome == ShotEvent.Outcome.GOAL:
			out[t]["goals"] = int(out[t]["goals"]) + 1
		if e.outcome == ShotEvent.Outcome.GOAL or e.outcome == ShotEvent.Outcome.SAVED:
			out[t]["sog"] = int(out[t]["sog"]) + 1
	for entry: Variant in box_score:
		if not entry is Dictionary:
			continue
		var p: Dictionary = entry as Dictionary
		var t: int = clampi(int(p.get("team_id", 0)), 0, 1)
		out[t]["box"] = true
		out[t]["hits"] = int(out[t]["hits"]) + int(p.get("hits", 0))
		out[t]["faceoff_wins"] = int(out[t]["faceoff_wins"]) + int(p.get("faceoff_wins", 0))
		out[t]["takeaways"] = int(out[t]["takeaways"]) + int(p.get("takeaways", 0))
		out[t]["giveaways"] = int(out[t]["giveaways"]) + int(p.get("giveaways", 0))
	return out


# Per-team aggregates, summed from the broadcast PlayerStats counters — the same
# numbers the scoreboard and career screen show, so the tape can't drift from
# them. (The map reads the event list; both derive from the same shots.)
func _team_totals() -> Array[Dictionary]:
	var out: Array[Dictionary] = [_empty_totals(), _empty_totals()]
	for t: int in 2:
		out[t]["box"] = true
		out[t]["icings"] = 0
	var players: Dictionary[int, PlayerRecord] = GameManager.get_players()
	for peer_id: int in players:
		var rec: PlayerRecord = players[peer_id]
		if rec == null or rec.team == null or rec.stats == null:
			continue
		var t: int = rec.team.team_id
		if t < 0 or t > 1:
			continue
		var s: PlayerStats = rec.stats
		out[t]["goals"] = int(out[t]["goals"]) + s.goals
		out[t]["corsi"] = int(out[t]["corsi"]) + s.shot_attempts
		out[t]["fenwick"] = int(out[t]["fenwick"]) \
				+ (s.shot_attempts - s.shot_attempts_blocked)
		out[t]["xg"] = float(out[t]["xg"]) + s.xg_for
		out[t]["blocks"] = int(out[t]["blocks"]) + s.shots_blocked
		out[t]["hits"] = int(out[t]["hits"]) + s.hits
		out[t]["faceoff_wins"] = int(out[t]["faceoff_wins"]) + s.faceoff_wins
		out[t]["takeaways"] = int(out[t]["takeaways"]) + s.takeaways
		out[t]["giveaways"] = int(out[t]["giveaways"]) + s.giveaways
		out[t]["icings"] = int(out[t]["icings"]) + s.icings
	for t: int in 2:
		out[t]["sog"] = GameManager.get_team_shots(t)
	return out


func _build_tape_rows(totals: Array[Dictionary]) -> void:
	for box: Container in [_tape, _advanced]:
		for child: Node in box.get_children():
			child.queue_free()
	var home: Dictionary = totals[0]
	var away: Dictionary = totals[1]
	var has_box: bool = bool(home["box"]) or bool(away["box"])
	_add_count_row(_tape, &"TAPE_GOALS", home["goals"], away["goals"])
	_add_count_row(_tape, &"TAPE_SHOTS_ON_GOAL", home["sog"], away["sog"])
	# Each draw is one team's win, so the two teams' wins are every draw taken.
	var draws: int = int(home["faceoff_wins"]) + int(away["faceoff_wins"])
	if has_box and draws > 0:
		var home_pct: int = roundi(100.0 * float(home["faceoff_wins"]) / float(draws))
		_add_tape_row(_tape, tr(&"TAPE_FACEOFF_PCT"), home_pct, 100 - home_pct, "%d%%")
	if has_box:
		_add_count_row(_tape, &"TAPE_HITS", home["hits"], away["hits"])
	_add_count_row(_tape, &"TAPE_BLOCKED_SHOTS", home["blocks"], away["blocks"])
	if has_box:
		_add_count_row(_tape, &"TAPE_TAKEAWAYS", home["takeaways"], away["takeaways"])
		_add_count_row(_tape, &"TAPE_GIVEAWAYS", home["giveaways"], away["giveaways"], false)
	# Live game only (no stored record carries icings), and only where icing is
	# called.
	if home.has("icings") and GameManager.get_rule_set() == GameRules.RuleSet.NHL:
		_add_count_row(_tape, &"TAPE_ICINGS", home["icings"], away["icings"], false)

	_add_count_row(_advanced, &"TAPE_CORSI", home["corsi"], away["corsi"])
	_add_count_row(_advanced, &"TAPE_FENWICK", home["fenwick"], away["fenwick"])
	_add_tape_row(_advanced, tr(&"TAPE_XG"), float(home["xg"]), float(away["xg"]), "%.2f")


func _add_count_row(into: Container, key: StringName, home: int, away: int,
		higher_is_better: bool = true) -> void:
	_add_tape_row(into, tr(key), home, away, "%d", higher_is_better)


# One head-to-head row: the two values either side of a centred label, over a
# proportional two-segment bar. The side ahead (fewer, where `higher_is_better`
# is false) takes its team colour; the other stays neutral ink.
func _add_tape_row(into: Container, label_text: String, home: float, away: float,
		fmt: String, higher_is_better: bool = true) -> void:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 2)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var home_leads: bool = home >= away if higher_is_better else home <= away
	var home_lbl := _lbl(fmt % home, 16, _team_colors[0] if home_leads else _DIM)
	home_lbl.custom_minimum_size = Vector2(56, 0)
	head.add_child(home_lbl)
	var lbl := _lbl(label_text.to_upper(), 11, _MUTED)
	lbl.add_theme_font_override("font", MenuStyle.UI_FONT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lbl)
	var away_lbl := _lbl(fmt % away, 16, _team_colors[1] if not home_leads else _DIM)
	away_lbl.custom_minimum_size = Vector2(56, 0)
	away_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(away_lbl)
	row.add_child(head)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	bar.custom_minimum_size = Vector2(0, 5)
	var total: float = maxf(home + away, 0.0001)
	bar.add_child(_bar_segment(_team_colors[0], maxf(home / total, 0.02), home_leads))
	bar.add_child(_bar_segment(_team_colors[1], maxf(away / total, 0.02), not home_leads))
	row.add_child(bar)

	into.add_child(row)


func _bar_segment(color: Color, ratio: float, leading: bool) -> Control:
	var seg := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color if leading else Color(color.r, color.g, color.b, 0.42)
	style.set_corner_radius_all(3)
	seg.add_theme_stylebox_override("panel", style)
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_stretch_ratio = ratio
	return seg


# Each team wears its own PRIMARY here, via the same score-stripe rule the
# scorebug and the box score's period summary use — a team's colour has to be
# the same on every score surface or the identity channel stops being one. The
# jersey/* keys are the 3D uniform's colours (and away's is near-white), which
# read as muddy or invisible in flat UI; see TeamColorRegistry's doc-block.
func _resolve_team_colors() -> Array[Color]:
	var out: Array[Color] = [_team_colors[0], _team_colors[1]]
	if GameManager.teams.size() > 1 and GameManager.teams[0] != null \
			and GameManager.teams[1] != null:
		var pair: Dictionary = TeamColorRegistry.get_score_stripe_pair(
				GameManager.teams[0].color_slot, GameManager.teams[1].color_slot)
		out[0] = pair.home
		out[1] = pair.away
	return out


# ── Shared builders ──────────────────────────────────────────────────────────

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.BROADCAST_BG
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = _SEP
	style.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", style)
	return p


func _section_title(title: String, note: String, color: Color = _CREAM) -> Control:
	var row := HBoxContainer.new()
	var t := _lbl(title, 13, color)
	t.add_theme_font_override("font", MenuStyle.UI_FONT)
	row.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if not note.is_empty():
		var n := _lbl(note, 11, _MUTED)
		n.add_theme_font_override("font", MenuStyle.UI_FONT)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(n)
	return row


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuStyle.DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# ── Rink shot map ────────────────────────────────────────────────────────────

class RinkMap extends Control:
	const LEGEND_GOAL: int = 0
	const LEGEND_ON_NET: int = 1
	const LEGEND_MISSED: int = 2
	const LEGEND_BLOCKED: int = 3

	const _ICE := Color(0.075, 0.098, 0.141, 1.0)
	const _BOARDS := Color(0.24, 0.27, 0.33, 1.0)
	const _RED := Color(0.69, 0.31, 0.35, 0.75)
	const _BLUE := Color(0.23, 0.44, 0.69, 0.75)
	# Goal marker ring — the accent, never a jersey colour (see _draw_shot).
	const _GOAL_RING := MenuStyle.GOLD
	# Dot radius in rink metres: floor + xG-scaled growth.
	const _DOT_MIN_M: float = 0.18
	const _DOT_XG_M: float = 0.55

	var _events: Array[ShotEvent] = []
	var _colors: Array[Color] = [Color.ORANGE, Color.SKY_BLUE]
	var _scale: float = 1.0
	var _origin := Vector2.ZERO

	func configure(events: Array[ShotEvent], colors: Array[Color]) -> void:
		_events = events
		_colors = colors
		queue_redraw()

	# Rink (z along the length) → control-local pixels, letterboxed to fit.
	func _p(rz: float, rx: float) -> Vector2:
		return _origin + Vector2(rz * _scale, rx * _scale)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 4.0 or h <= 4.0:
			return
		_scale = minf(w / (_HALF_LEN * 2.0 + 1.0), h / (_HALF_WID * 2.0 + 1.0))
		_origin = Vector2(w * 0.5, h * 0.5)
		_draw_ice()
		_draw_markings()
		_draw_shots()

	func _draw_ice() -> void:
		var tl: Vector2 = _p(-_HALF_LEN, -_HALF_WID)
		var br: Vector2 = _p(_HALF_LEN, _HALF_WID)
		draw_rect(Rect2(tl, br - tl), _ICE, true)
		draw_rect(Rect2(tl, br - tl), _BOARDS, false, 1.5)

	func _draw_markings() -> void:
		# Goal lines, blue lines, centre line — vertical in this orientation.
		for z: float in [-_GOAL_LINE, _GOAL_LINE]:
			draw_line(_p(z, -_HALF_WID), _p(z, _HALF_WID), _RED, 1.0)
		for z: float in [-_BLUE_LINE, _BLUE_LINE]:
			draw_line(_p(z, -_HALF_WID), _p(z, _HALF_WID), _BLUE, 2.0)
		draw_line(_p(0.0, -_HALF_WID), _p(0.0, _HALF_WID), _RED, 2.0)
		# Creases: a half-disc opening toward centre ice at each goal line. Angle 0
		# is +screen-x = +rink-z, so the arc must START at -90° for the -Z crease
		# (bulging toward +z) and at +90° for the +Z one — i.e. it swings with
		# `inward`. A fixed start bulged the far crease out through the end boards.
		for z: float in [-_GOAL_LINE, _GOAL_LINE]:
			var inward: float = 1.0 if z < 0.0 else -1.0
			var start: float = -PI * 0.5 * inward
			draw_arc(_p(z, 0.0), 1.8 * _scale,
					start, start + PI, 24, _BLUE, 1.0)
			# Net footprint just outside the goal line.
			var mouth_a: Vector2 = _p(z - inward * 1.0, -GameRules.NET_HALF_WIDTH)
			var mouth_b: Vector2 = _p(z, GameRules.NET_HALF_WIDTH)
			draw_rect(Rect2(mouth_a, mouth_b - mouth_a), _BOARDS, false, 1.0)
		# Faceoff dots (4 end-zone + centre).
		for z: float in [-20.0, 20.0]:
			for x: float in [-6.5, 6.5]:
				draw_arc(_p(z, x), 4.5 * _scale, 0.0, TAU, 32, _RED, 0.8)
				draw_circle(_p(z, x), maxf(1.5, 0.18 * _scale), _RED)
		draw_arc(_p(0.0, 0.0), 4.5 * _scale, 0.0, TAU, 32, _BLUE, 0.8)
		draw_circle(_p(0.0, 0.0), maxf(1.5, 0.18 * _scale), _BLUE)

	# Dot size carries xG; outcome carries the style. Drawn attempts-first so the
	# goals (ringed, brightest) land on top of the clutter.
	func _draw_shots() -> void:
		for pass_idx: int in 2:
			for e: ShotEvent in _events:
				var is_goal: bool = e.outcome == ShotEvent.Outcome.GOAL
				if (pass_idx == 0) == is_goal:
					continue
				_draw_shot(e)

	func _draw_shot(e: ShotEvent) -> void:
		var team: int = clampi(e.team_id, 0, 1)
		var col: Color = _colors[team]
		var at: Vector2 = _p(e.z, e.x)
		# Radius is sized in RINK METRES, then scaled — so the dots keep the same
		# on-ice footprint at any resolution. (Deriving it from pixel scale made
		# the slot one blob on a wide screen.)
		var r: float = maxf(2.0, (_DOT_MIN_M + e.xg * _DOT_XG_M) * _scale)
		match e.outcome:
			ShotEvent.Outcome.GOAL:
				draw_circle(at, r * 1.8, Color(col.r, col.g, col.b, 0.26))
				draw_circle(at, r, col)
				# Gold, not white: one team's kit IS white, and a white ring on a
				# white dot made their goals unreadable.
				draw_arc(at, r + 2.0, 0.0, TAU, 24, _GOAL_RING, 1.8)
			ShotEvent.Outcome.SAVED:
				draw_circle(at, r, Color(col.r, col.g, col.b, 0.92))
			ShotEvent.Outcome.MISSED:
				draw_arc(at, r, 0.0, TAU, 20, col, 1.4)
			_:  # BLOCKED
				draw_circle(at, r * 0.85, Color(col.r, col.g, col.b, 0.34))


# One legend swatch, drawn in the same styles the map uses.
class LegendDot extends Control:
	var kind: int = 0

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var col := Color(0.78, 0.80, 0.85, 1.0)
		var r: float = 4.5
		match kind:
			RinkMap.LEGEND_GOAL:
				draw_circle(c, r, col)
				draw_arc(c, r + 1.6, 0.0, TAU, 20, RinkMap._GOAL_RING, 1.6)
			RinkMap.LEGEND_ON_NET:
				draw_circle(c, r, col)
			RinkMap.LEGEND_MISSED:
				draw_arc(c, r, 0.0, TAU, 20, col, 1.4)
			_:
				draw_circle(c, r * 0.85, Color(col.r, col.g, col.b, 0.34))

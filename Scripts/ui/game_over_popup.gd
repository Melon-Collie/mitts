class_name GameOverPopup
extends CanvasLayer

# End-of-game card over the highlight reel: one dark panel on the scorebug's
# surface, centred, the reel still running round it through the modal scrim.
# Top to bottom: the local player's VICTORY / DEFEAT tag, FINAL and the score
# row (the scorebug's team badges at hero scale, away first), the winner line,
# the tournament outcome when there is one, the teams' stats side by side, the
# Three Stars (landing 3rd → 2nd → 1st, arena order), and the actions along the
# card's foot: the one primary action, the others, and Exit set apart. HUD owns
# the timing (it lets the final-horn beat play on the ice first) and fills a
# GameOverSummary; this class is pure presentation plus the action buttons.
#
# The box score is not embedded here: Tab still raises the Scoreboard over it,
# which the footer says.

signal rematch_toggled
signal lobby_vote_toggled
signal free_play_pressed
signal exit_pressed
signal analytics_pressed
signal save_goal_pressed

const _GOLD := MenuStyle.GOLD
const _WHITE := MenuStyle.BROADCAST_CREAM
const _DIM := MenuStyle.BROADCAST_DIM
const _CARD_BG := Color(MenuStyle.BROADCAST_BG, 0.96)

const _CARD_WIDTH: float = 900.0
const _CARD_RADIUS: int = 8
const _SECTION_MARGIN: int = 30
# The card settles in from a touch small.
const _ENTER_SCALE: float = 0.97
const _ENTER_TIME: float = 0.35
# Reveal cadence: the card settles first, then the stars land 3rd → 2nd → 1st
# so the first star is the climax beat.
const _STAR_REVEAL_DELAY: float = 0.45
const _STAR_REVEAL_GAP: float = 0.5

const _MAX_STARS: int = 3
# The tournament line under the result: a quiet note for most games, and the
# club's crest beside gold lettering when the game just won the cup.
const _OUTCOME_SIZE: int = 20
const _CUP_SIZE: int = 40
const _CUP_CREST_PX: float = 60.0
const _CUP_REVEAL_DELAY: float = 0.45
const _CUP_REVEAL_OVERSCALE: float = 1.35
const _RANK_TAG_KEYS: Array[String] = ["STAR_FIRST", "STAR_SECOND", "STAR_THIRD"]
# The first star reads bigger than the runners-up: rank is carried by scale and
# colour, not by borders.
const _RANK_NAME_SIZES: Array[int] = [32, 22, 22]
const _RANK_LINE_SIZES: Array[int] = [17, 15, 15]
const _STAR_ROW_WIDTH: float = 640.0
const _STAR_TAG_WIDTH: float = 104.0
# A star's team badge (TeamBadge), the scorebug's at its own size.
const _STAR_BADGE := Vector2(64.0, 34.0)
const _STAR_CREST_PX: float = 70.0
# The final score's team badges, the scorebug's at hero scale: the crest about
# twice the badge's height, cropped at its outer edge.
const _SCORE_BADGE_WIDTH: float = 124.0
const _SCORE_BADGE_HEIGHT: float = 60.0
const _SCORE_CREST_PX: float = 124.0
const _SCORE_ABBR_SIZE: int = 32
const _SCORE_ABBR_INSET: float = 24.0
const _STAT_VALUE_WIDTH: float = 120.0
const _STAT_LABEL_WIDTH: float = 180.0

var _root: Control = null
var _scrim: ColorRect = null
var _card: PanelContainer = null
var _personal_tag: PanelContainer = null
var _personal_style: StyleBoxFlat = null
var _personal_label: Label = null
var _home_stripe_style: StyleBoxFlat = null
var _away_stripe_style: StyleBoxFlat = null
var _home_badge: TeamBadge = null
var _away_badge: TeamBadge = null
var _home_score_label: Label = null
var _away_score_label: Label = null
var _result_label: Label = null
var _stats_section: Control = null
var _stats_grid: GridContainer = null
var _stars_section: Control = null
var _star_rows: Array[Control] = []
var _star_badges: Array[TeamBadge] = []
var _star_name_labels: Array[Label] = []
var _star_line_labels: Array[Label] = []
var _star_title_labels: Array[Label] = []
var _save_goal_btn: Button = null
var _rematch_btn: Button = null
var _lobby_btn: Button = null
var _vote_label: Label = null
var _tournament_row: HBoxContainer = null
var _tournament_label: Label = null
var _cup_crest: ClubCrest = null
var _cup_club: int = TournamentRules.NO_CLUB
var _cup_tween: Tween = null
var _present_tween: Tween = null
var _is_spectator: bool = false
# A tournament game has no rematch, and its way on is the bracket.
var _in_tournament: bool = false
# The button the card leads with: Rematch, or Continue / Lobby without one.
var _primary: Button = null
# The local player's vote (RematchVoteRules.Choice), which the two vote buttons
# are worded from.
var _local_vote: int = RematchVoteRules.Choice.NONE


func _ready() -> void:
	layer = 5
	_build_ui()
	visible = false


# The popup's content root, handed to a screen that opens OVER this one (the
# analytics reader) so focus can be walled off from these buttons while it's up.
func focus_root() -> Control:
	return _root


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_root = root

	# Dims the reel behind the card and makes this modal: the same dim every
	# popup uses.
	_scrim = ColorRect.new()
	_scrim.color = MenuStyle.SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_scrim)

	var centering := CenterContainer.new()
	centering.set_anchors_preset(Control.PRESET_FULL_RECT)
	centering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centering)

	var style := StyleBoxFlat.new()
	style.bg_color = _CARD_BG
	style.set_corner_radius_all(_CARD_RADIUS)
	style.border_color = MenuStyle.BROADCAST_BORDER_T
	style.border_width_top = 1
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", style)
	_card.custom_minimum_size = Vector2(_CARD_WIDTH, 0)
	centering.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)
	col.add_child(_build_header())
	_stats_section = _section(_build_stats())
	col.add_child(_stats_section)
	_stars_section = _section(_build_stars())
	col.add_child(_stars_section)
	col.add_child(_build_footer())


# The tag, FINAL, the score row, the winner and the tournament outcome.
func _build_header() -> Control:
	var margin := _margin(_SECTION_MARGIN, 26, 22)
	var head := VBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	margin.add_child(head)

	_personal_style = StyleBoxFlat.new()
	_personal_style.set_corner_radius_all(4)
	_personal_style.set_content_margin(SIDE_LEFT, 14)
	_personal_style.set_content_margin(SIDE_RIGHT, 14)
	_personal_style.set_content_margin(SIDE_TOP, 4)
	_personal_style.set_content_margin(SIDE_BOTTOM, 4)
	_personal_tag = PanelContainer.new()
	_personal_tag.add_theme_stylebox_override("panel", _personal_style)
	_personal_tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_personal_label = _lbl("", 16, _WHITE)
	_personal_label.add_theme_font_override("font", MenuStyle.display_font_spaced())
	_personal_tag.add_child(_personal_label)
	head.add_child(_personal_tag)

	var final_tag := _lbl(tr(&"FINAL"), 16, _DIM)
	final_tag.add_theme_font_override("font", MenuStyle.display_font_spaced())
	final_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(final_tag)

	head.add_child(_build_score_row())

	_result_label = _lbl("", 44, _WHITE)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_result_label)

	_tournament_row = HBoxContainer.new()
	_tournament_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tournament_row.add_theme_constant_override("separation", 14)
	_tournament_row.visible = false
	head.add_child(_tournament_row)
	_cup_crest = ClubCrest.new(_CUP_CREST_PX)
	_cup_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cup_crest.visible = false
	_tournament_row.add_child(_cup_crest)
	_tournament_label = _lbl("", _OUTCOME_SIZE, _DIM)
	_tournament_row.add_child(_tournament_label)
	return margin


# [stripe|AWAY badge]  3  —  2  [HOME badge|stripe]: the scorebug's teams at
# hero scale, away first as it lists them, each badge's crest cropped at the
# row's outer edge.
func _build_score_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)

	_away_stripe_style = _stripe_style()
	_away_badge = TeamBadge.new(_SCORE_BADGE_WIDTH, _SCORE_CREST_PX, _SCORE_ABBR_SIZE,
			_SCORE_ABBR_INSET)
	row.add_child(_team_unit(_stripe(_away_stripe_style), _away_badge))
	_away_score_label = _lbl("0", 56, _WHITE)
	row.add_child(_away_score_label)

	var dash := _lbl("—", 30, _DIM)
	dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dash)

	_home_score_label = _lbl("0", 56, _WHITE)
	row.add_child(_home_score_label)
	_home_stripe_style = _stripe_style()
	_home_badge = TeamBadge.new(_SCORE_BADGE_WIDTH, _SCORE_CREST_PX, _SCORE_ABBR_SIZE,
			_SCORE_ABBR_INSET, HORIZONTAL_ALIGNMENT_CENTER, true)
	row.add_child(_team_unit(_home_badge, _stripe(_home_stripe_style)))
	return row


# A team's stripe and badge, flush, as one unit of the score row.
func _team_unit(first: Control, second: Control) -> HBoxContainer:
	var unit := HBoxContainer.new()
	unit.add_theme_constant_override("separation", 0)
	unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for part: Control in [first, second]:
		part.custom_minimum_size.y = _SCORE_BADGE_HEIGHT
		unit.add_child(part)
	return unit


# Away value | stat | home value, a row per stat, under the score's own order.
func _build_stats() -> Control:
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 3
	_stats_grid.add_theme_constant_override("h_separation", 0)
	_stats_grid.add_theme_constant_override("v_separation", 6)
	_stats_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return _stats_grid


func _build_stars() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 10)
	block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tag := _lbl(tr(&"STARS_OF_THE_GAME"), 15, _GOLD)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(tag)
	for rank: int in _MAX_STARS:
		block.add_child(_build_star_row(rank))
	return block


# rank tag | team badge | NAME title ......... stat line, every row the same
# width so the badges, names and lines each share an edge down the block.
func _build_star_row(rank: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(_STAR_ROW_WIDTH, 0)
	var first: bool = rank == 0

	var tag := _lbl(tr(_RANK_TAG_KEYS[rank]), 15 if first else 13, _GOLD if first else _DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.custom_minimum_size = Vector2(_STAR_TAG_WIDTH, 0)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tag)

	var badge := TeamBadge.new(_STAR_BADGE.x, _STAR_CREST_PX, 15, 8.0)
	badge.custom_minimum_size.y = _STAR_BADGE.y
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_star_badges.append(badge)
	row.add_child(badge)

	var name_label := _lbl("", _RANK_NAME_SIZES[rank], _WHITE)
	name_label.uppercase = true
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_star_name_labels.append(name_label)
	row.add_child(name_label)

	var title_label := _lbl("", 13, _GOLD)
	title_label.uppercase = true
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_star_title_labels.append(title_label)
	row.add_child(title_label)

	var line_label := _lbl("", _RANK_LINE_SIZES[rank], _DIM)
	line_label.add_theme_font_override("font", MenuStyle.UI_FONT)
	line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_star_line_labels.append(line_label)
	row.add_child(line_label)

	_star_rows.append(row)
	return row


# The actions along the card's foot: what's next on the left, the views of this
# game beside them, Exit set apart at the right; the vote tally and the box
# score hint under them.
func _build_footer() -> Control:
	var foot_style := StyleBoxFlat.new()
	foot_style.bg_color = MenuStyle.SURFACE_ELEV
	foot_style.corner_radius_bottom_left = _CARD_RADIUS
	foot_style.corner_radius_bottom_right = _CARD_RADIUS
	foot_style.set_content_margin(SIDE_LEFT, 22)
	foot_style.set_content_margin(SIDE_RIGHT, 22)
	foot_style.set_content_margin(SIDE_TOP, 16)
	foot_style.set_content_margin(SIDE_BOTTOM, 12)
	var foot := PanelContainer.new()
	foot.add_theme_stylebox_override("panel", foot_style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	foot.add_child(rows)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	rows.add_child(actions)

	_rematch_btn = _action_button(tr(&"GAME_OVER_REMATCH"))
	_rematch_btn.pressed.connect(func() -> void: rematch_toggled.emit())
	actions.add_child(_rematch_btn)

	# "Return to Lobby" is the second flavor of the same play-again vote (see
	# RematchVoteRules): once the pool is unanimous, any lobby vote routes the
	# whole group to the shared lobby instead of an instant rematch. Shown
	# unconditionally — every real match starts from the unified lobby (offline
	# included), and game over never fires in the lobby-less modes (free play,
	# tutorial, drills). Offline the voter pool is just the host, so the vote
	# resolves on the click; a host who wants to force the lobby without
	# waiting on the vote still has the pause menu's instant Return to Lobby.
	_lobby_btn = _action_button(tr(&"GAME_OVER_RETURN_LOBBY"))
	_lobby_btn.pressed.connect(func() -> void: lobby_vote_toggled.emit())
	actions.add_child(_lobby_btn)

	# Always available: drop to solo free play. Offline this is the only leave
	# action; for an online client it disconnects just them; for an online host
	# it tears down the server (everyone drops out).
	var free_play_btn := _action_button(tr(&"GAME_OVER_RETURN_FREE_PLAY"))
	free_play_btn.pressed.connect(func() -> void: free_play_pressed.emit())
	actions.add_child(free_play_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)

	var analytics_btn := _action_button(tr(&"GAME_OVER_ANALYTICS"))
	analytics_btn.pressed.connect(func() -> void: analytics_pressed.emit())
	actions.add_child(analytics_btn)

	# Hidden until set_goal_saving says there is a goal to save.
	_save_goal_btn = _action_button(tr(&"GAME_OVER_SAVE_GOAL"))
	_save_goal_btn.pressed.connect(func() -> void: save_goal_pressed.emit())
	_save_goal_btn.visible = false
	actions.add_child(_save_goal_btn)

	actions.add_child(_exit_button())

	var notes := HBoxContainer.new()
	rows.add_child(notes)
	_vote_label = _lbl("", 13, _DIM)
	_vote_label.add_theme_font_override("font", MenuStyle.UI_FONT)
	notes.add_child(_vote_label)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_child(gap)
	var hint := _lbl(tr(&"HINT_TAB_BOX_SCORE"), 13, _DIM)
	hint.add_theme_font_override("font", MenuStyle.UI_FONT)
	notes.add_child(hint)

	_set_primary(_rematch_btn)
	return foot


# Quits the whole game: quieter than the rest, red only when reached.
func _exit_button() -> Button:
	var btn := Button.new()
	btn.text = tr(&"GAME_OVER_EXIT")
	btn.flat = true
	btn.custom_minimum_size = Vector2(0, 42)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", MenuStyle.DANGER)
	btn.add_theme_color_override("font_focus_color", MenuStyle.DANGER)
	btn.pressed.connect(func() -> void: exit_pressed.emit())
	SoundManager.wire_button(btn)
	MenuStyle.apply_focus_ring(btn)
	return btn


# Fill the card with this game and play the reveal: the card fades and settles,
# then the stars land 3rd → 2nd → 1st. A summary without stars (a nothing game)
# hides that block.
func present(summary: GameOverSummary) -> void:
	_home_score_label.text = str(summary.home_score)
	_away_score_label.text = str(summary.away_score)
	var known: bool = summary.home_club >= 0 and summary.away_club >= 0
	if known:
		var stripes: Dictionary = TeamColorRegistry.get_score_stripe_pair(
				summary.home_club, summary.away_club)
		_home_stripe_style.bg_color = stripes.home
		_away_stripe_style.bg_color = stripes.away
	_home_badge.set_team(summary.home_club, _abbr_of(summary.home_club))
	_away_badge.set_team(summary.away_club, _abbr_of(summary.away_club))
	_result_label.text = summary.result_text
	_result_label.add_theme_color_override("font_color", summary.result_color)
	_show_personal(summary.personal)
	_fill_stats(summary)

	var star_count: int = mini(summary.star_names.size(), _MAX_STARS)
	_stars_section.visible = star_count > 0
	for rank: int in _MAX_STARS:
		var filled: bool = rank < star_count
		_star_rows[rank].visible = filled
		if not filled:
			continue
		var club: int = summary.star_clubs[rank] if rank < summary.star_clubs.size() else -1
		_star_badges[rank].set_team(club, _abbr_of(club))
		_star_name_labels[rank].text = summary.star_names[rank]
		var title: String = summary.star_titles[rank] if rank < summary.star_titles.size() else ""
		_star_title_labels[rank].text = title
		_star_title_labels[rank].visible = not title.is_empty()
		var line: String = summary.star_lines[rank] if rank < summary.star_lines.size() else ""
		_star_line_labels[rank].text = line

	visible = true
	# Controller: focus the card's lead action so the pad can act at once.
	if _primary != null and _primary.visible:
		ControllerNav.grab_focus(_primary)
	if _present_tween != null and _present_tween.is_running():
		_present_tween.kill()
	_scrim.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2.ONE * _ENTER_SCALE
	for rank: int in star_count:
		_star_rows[rank].modulate.a = 0.0
	_present_tween = create_tween()
	_present_tween.tween_property(_scrim, "modulate:a", 1.0, 0.30)
	_present_tween.parallel().tween_property(_card, "modulate:a", 1.0, _ENTER_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_present_tween.parallel().tween_property(_card, "scale", Vector2.ONE, _ENTER_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _cup_club != TournamentRules.NO_CLUB:
		_play_cup_reveal(_CUP_REVEAL_DELAY)
	else:
		_tournament_row.modulate.a = 1.0
		_tournament_row.scale = Vector2.ONE
	if star_count > 0:
		_present_tween.tween_interval(_STAR_REVEAL_DELAY)
		# Arena order: lowest rank announced first, first star last.
		for rank: int in range(star_count - 1, -1, -1):
			_append_star_reveal(rank)
			if rank > 0:
				_present_tween.tween_interval(_STAR_REVEAL_GAP)


# VICTORY in gold for the winners, DEFEAT on a quiet plate for the losers; no
# tag for a tie or a spectator.
func _show_personal(personal: GameOverSummary.Personal) -> void:
	_personal_tag.visible = personal != GameOverSummary.Personal.NONE
	var won: bool = personal == GameOverSummary.Personal.VICTORY
	_personal_label.text = tr(&"GAME_OVER_VICTORY") if won else tr(&"GAME_OVER_DEFEAT")
	_personal_label.add_theme_color_override("font_color", MenuStyle.ON_TEAL if won else _WHITE)
	_personal_style.bg_color = _GOLD if won else MenuStyle.SURFACE_ELEV


func _fill_stats(summary: GameOverSummary) -> void:
	for child: Node in _stats_grid.get_children():
		child.queue_free()
	_stats_section.visible = not summary.stat_labels.is_empty()
	for i: int in summary.stat_labels.size():
		_stats_grid.add_child(_stat_value(summary.away_stats[i]))
		var label := _lbl(summary.stat_labels[i], 14, _DIM)
		label.add_theme_font_override("font", MenuStyle.display_font_spaced())
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(_STAT_LABEL_WIDTH, 0)
		_stats_grid.add_child(label)
		_stats_grid.add_child(_stat_value(summary.home_stats[i]))


func _stat_value(text: String) -> Label:
	var value := _lbl(text, 24, _WHITE)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(_STAT_VALUE_WIDTH, 0)
	return value


# One star row's landing: a quick fade with a spring settle from a slight
# overscale, a bigger one for the first star.
func _append_star_reveal(rank: int) -> void:
	var row: Control = _star_rows[rank]
	var overscale: float = 1.10 if rank == 0 else 1.05
	_present_tween.tween_callback(func() -> void:
		row.pivot_offset = row.size / 2.0
		row.scale = Vector2(overscale, overscale))
	_present_tween.tween_property(row, "modulate:a", 1.0, 0.18)
	_present_tween.parallel().tween_property(row, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)


func set_spectator(is_spec: bool) -> void:
	_is_spectator = is_spec
	_refresh_actions()


# `outcome` is what the result did to the player's tournament ("Advance to the
# Semifinal"), empty while that is not known yet. `cup_club` is the player's
# club when this game won it the cup, which the line then celebrates.
func set_tournament(in_tournament: bool, outcome: String,
		cup_club: int = TournamentRules.NO_CLUB) -> void:
	var won_cup: bool = cup_club != TournamentRules.NO_CLUB
	var cup_just_arrived: bool = won_cup and _cup_club == TournamentRules.NO_CLUB
	_in_tournament = in_tournament
	_cup_club = cup_club
	_cup_crest.set_club(cup_club)
	_cup_crest.visible = won_cup
	# At headline size it is lettered like the headline above it.
	_tournament_label.text = outcome.to_upper() if won_cup else outcome
	_tournament_label.add_theme_font_size_override("font_size",
			_CUP_SIZE if won_cup else _OUTCOME_SIZE)
	_tournament_label.add_theme_color_override("font_color", _GOLD if won_cup else _DIM)
	_tournament_row.visible = in_tournament and not outcome.is_empty()
	_local_vote = RematchVoteRules.Choice.NONE
	_refresh_actions()
	# On a client the result can land with the screen already up.
	if cup_just_arrived and visible:
		_play_cup_reveal(0.0)


# The cup line lands the way a first star does: a spring from an overscale.
func _play_cup_reveal(delay: float) -> void:
	if _cup_tween != null and _cup_tween.is_running():
		_cup_tween.kill()
	_tournament_row.modulate.a = 0.0
	_cup_tween = create_tween()
	_cup_tween.tween_interval(delay)
	_cup_tween.tween_callback(func() -> void:
		_tournament_row.pivot_offset = _tournament_row.size / 2.0
		_tournament_row.scale = Vector2(_CUP_REVEAL_OVERSCALE, _CUP_REVEAL_OVERSCALE))
	_cup_tween.tween_property(_tournament_row, "modulate:a", 1.0, 0.2)
	_cup_tween.parallel().tween_property(_tournament_row, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)


# Which actions exist, and which one leads: Rematch, or Continue / Lobby when a
# tournament or a spectator has no rematch.
func _refresh_actions() -> void:
	_rematch_btn.visible = not _is_spectator and not _in_tournament
	_lobby_btn.visible = not _is_spectator
	_vote_label.visible = not _is_spectator
	if _rematch_btn.visible:
		_set_primary(_rematch_btn)
	elif _lobby_btn.visible:
		_set_primary(_lobby_btn)
	else:
		_set_primary(null)


func _set_primary(btn: Button) -> void:
	for b: Button in [_rematch_btn, _lobby_btn]:
		var lead: bool = b == btn
		b.theme_type_variation = &"ButtonPrimary" if lead else &""
		if lead:
			b.add_theme_font_override("font", MenuStyle.name_font_spaced())
		else:
			b.remove_theme_font_override("font")
	_primary = btn
	_refresh_vote_texts()


# The two vote buttons' wording from the local vote. The lead one is lettered in
# capitals, as MenuStyle.apply_primary_cta letters every lead button.
func _refresh_vote_texts() -> void:
	var rematch: String = tr(&"GAME_OVER_UNVOTE") \
			if _local_vote == RematchVoteRules.Choice.REMATCH else tr(&"GAME_OVER_REMATCH")
	var lobby: String = _lobby_button_text(_local_vote)
	_rematch_btn.text = rematch.to_upper() if _rematch_btn == _primary else rematch
	_lobby_btn.text = lobby.to_upper() if _lobby_btn == _primary else lobby


func _lobby_button_text(local_vote: int) -> String:
	if local_vote == RematchVoteRules.Choice.LOBBY:
		return tr(&"GAME_OVER_UNVOTE")
	return tr(&"GAME_OVER_CONTINUE") if _in_tournament else tr(&"GAME_OVER_RETURN_LOBBY")


# Shown when the match has a goal to save and GIF export is built in; disabled
# while a save is under way.
func set_goal_saving(available: bool, can_save: bool) -> void:
	_save_goal_btn.visible = available
	_save_goal_btn.disabled = not can_save


func hide_popup() -> void:
	if _present_tween != null and _present_tween.is_running():
		_present_tween.kill()
	if _cup_tween != null and _cup_tween.is_running():
		_cup_tween.kill()
	visible = false


# `votes` is peer_id -> RematchVoteRules.Choice; `local_vote` is the local
# player's current flavor. The button you voted flips to "Unvote" (pressing
# the other flavor switches the vote instead); the tally line flags when the
# pool is already headed to the lobby.
func update_votes(votes: Dictionary[int, int], total_voters: int, local_vote: int) -> void:
	_local_vote = local_vote
	_refresh_vote_texts()
	var count: int = RematchVoteRules.count_voted(votes)
	# One key per phrasing rather than a suffix appended to the tally: the
	# clause does not attach at the end in every language.
	var key: StringName = &"GAME_OVER_VOTE_TALLY_LOBBY" \
			if RematchVoteRules.has_lobby_vote(votes) else &"GAME_OVER_VOTE_TALLY"
	_vote_label.text = tr(key) % [count, total_voters]


func _action_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 42)
	btn.add_theme_font_size_override("font_size", 16)
	MenuStyle.wire_hover_scale(btn)
	SoundManager.wire_button(btn)
	MenuStyle.apply_focus_ring(btn)
	return btn


# A section of the card under a hairline rule.
func _section(content: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var rule := ColorRect.new()
	rule.color = MenuStyle.BROADCAST_SEP
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	var margin := _margin(_SECTION_MARGIN, 18, 20)
	margin.add_child(content)
	box.add_child(margin)
	return box


func _margin(side: int, top: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", side)
	m.add_theme_constant_override("margin_right", side)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	return m


func _abbr_of(club: int) -> String:
	return TeamColorRegistry.get_preset_abbr(club) if club >= 0 else ""


func _stripe_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.5, 0.5, 0.5)
	s.set_corner_radius_all(2)
	return s


func _stripe(style: StyleBoxFlat) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style)
	p.custom_minimum_size = Vector2(6, _SCORE_BADGE_HEIGHT)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuStyle.DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

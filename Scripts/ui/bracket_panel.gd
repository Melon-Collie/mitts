class_name BracketPanel
extends MarginContainer
## A tournament drawn as a bracket: the three rounds left to right, then the
## champion. Each game is a cell of two lines (crest, seed, club, score); the
## player's club carries a teal bar and the game it plays next is outlined.

const _CELL_WIDTH: float = 216.0
const _LINE_HEIGHT: float = 26.0
const _CREST_PX: float = 22.0
const _PLAYER_BAR_SIZE: Vector2 = Vector2(3.0, 18.0)
const _CHAMPION_CREST_PX: float = 72.0
const _COLUMN_GAP: int = 32
const _CONNECTOR_WIDTH: float = 1.5
const _LOSER_ALPHA: float = 0.55
const _GAMES_BY_ROUND: Array = [[0, 1, 2, 3], [4, 5], [6]]

var _cells: Array[PanelContainer] = []
var _cell_styles: Array[StyleBoxFlat] = []
var _lines: Array[_Line] = []  # two a game: game * 2 + line
var _champion_crest: ClubCrest = null
var _champion_name: Label = null


class _Line:
	var player_bar: ColorRect
	var crest: ClubCrest
	var seed_label: Label
	var name_label: Label
	var score_label: Label


func _init() -> void:
	_cells.resize(TournamentState.GAME_COUNT)
	_cell_styles.resize(TournamentState.GAME_COUNT)
	_lines.resize(TournamentState.GAME_COUNT * 2)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", _COLUMN_GAP)
	add_child(columns)
	for round_index: int in range(TournamentRules.ROUND_COUNT):
		var games := _column(columns, TournamentCopy.round_name(round_index))
		for game: int in _GAMES_BY_ROUND[round_index]:
			games.add_child(_build_cell(game))
	_build_champion(_column(columns, TournamentCopy.t(&"TOURNAMENT_CHAMPION")))
	resized.connect(queue_redraw)


func show_state(state: TournamentState) -> void:
	var next_game: int = TournamentRules.player_game(state)
	for game: int in range(TournamentState.GAME_COUNT):
		var winner: int = TournamentRules.winner(state, game)
		var home: int = TournamentRules.home_club(state, game)
		for line: int in 2:
			var club: int = TournamentRules.entrant(state, game, line)
			var score: int = TournamentState.UNPLAYED
			if state.is_played(game):
				score = state.home_score(game) if club == home else state.away_score(game)
			_fill_line(_lines[game * 2 + line], state, club, score,
					winner != TournamentRules.NO_CLUB and club != winner,
					club == winner and state.went_to_overtime(game))
		_cell_styles[game].border_color = MenuStyle.TEAL if game == next_game \
				else MenuStyle.SURFACE_ELEV
	var champion: int = TournamentRules.champion(state)
	_champion_crest.set_club(champion)
	_champion_name.text = "—" if champion == TournamentRules.NO_CLUB \
			else TournamentCopy.club_name(champion).to_upper()
	_champion_name.add_theme_color_override("font_color",
			MenuStyle.TEXT_MUTED if champion == TournamentRules.NO_CLUB else MenuStyle.GOLD)
	queue_redraw()


# The mark that says "this club is yours", for a row that names a club. Shown
# by making it visible; it holds its width either way so rows stay aligned.
static func player_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = MenuStyle.TEAL
	bar.custom_minimum_size = _PLAYER_BAR_SIZE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


# An elbow from each feeder game's right edge to the game it feeds.
func _draw() -> void:
	var to_local: Transform2D = get_global_transform().affine_inverse()
	for game: int in range(_GAMES_BY_ROUND[0].size(), TournamentState.GAME_COUNT):
		var target: PanelContainer = _cells[game]
		var into: Vector2 = to_local * target.get_global_transform() \
				* Vector2(0.0, target.size.y * 0.5)
		for line: int in 2:
			var feeder: PanelContainer = _cells[(game - _GAMES_BY_ROUND[0].size()) * 2 + line]
			var out: Vector2 = to_local * feeder.get_global_transform() \
					* Vector2(feeder.size.x, feeder.size.y * 0.5)
			var bend_x: float = (out.x + into.x) * 0.5
			draw_polyline(PackedVector2Array([out, Vector2(bend_x, out.y),
					Vector2(bend_x, into.y), into]), MenuStyle.TEXT_SEP, _CONNECTOR_WIDTH)


# One round's column: its heading over a box the games share evenly, so a
# later round's games sit level with the midpoint of the two that feed them.
func _column(columns: HBoxContainer, heading: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	columns.add_child(column)
	var label := Label.new()
	label.text = heading.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	column.add_child(label)
	var games := VBoxContainer.new()
	games.add_theme_constant_override("separation", 10)
	games.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(games)
	return games


func _build_cell(game: int) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.SURFACE_ELEV
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = MenuStyle.SURFACE_ELEV
	style.set_content_margin_all(6)
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", style)
	cell.custom_minimum_size = Vector2(_CELL_WIDTH, 0.0)
	cell.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	cell.item_rect_changed.connect(queue_redraw)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	cell.add_child(rows)
	for line: int in 2:
		rows.add_child(_build_line(game * 2 + line))
	_cells[game] = cell
	_cell_styles[game] = style
	return cell


func _build_line(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0.0, _LINE_HEIGHT)
	var line := _Line.new()
	line.player_bar = player_bar()
	row.add_child(line.player_bar)
	line.crest = ClubCrest.new(_CREST_PX)
	line.crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line.crest)
	line.seed_label = _label(12, MenuStyle.TEXT_MUTED)
	line.seed_label.custom_minimum_size = Vector2(12.0, 0.0)
	row.add_child(line.seed_label)
	line.name_label = _label(15, MenuStyle.TEXT_BODY)
	line.name_label.add_theme_font_override("font", MenuStyle.NAME_FONT)
	line.name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.name_label.clip_text = true
	row.add_child(line.name_label)
	line.score_label = _label(15, MenuStyle.TEXT_BODY)
	line.score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(line.score_label)
	_lines[index] = line
	return row


func _build_champion(games: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(_CELL_WIDTH * 0.6, 0.0)
	box.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	games.add_child(box)
	_champion_crest = ClubCrest.new(_CHAMPION_CREST_PX)
	_champion_crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_champion_crest)
	_champion_name = _label(18, MenuStyle.TEXT_TITLE)
	_champion_name.add_theme_font_override("font", MenuStyle.DISPLAY_FONT)
	_champion_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_champion_name)


func _fill_line(line: _Line, state: TournamentState, club: int, score: int,
		lost: bool, won_in_overtime: bool) -> void:
	line.crest.set_club(club)
	line.player_bar.modulate.a = 1.0 if club == state.player_club else 0.0
	if club == TournamentRules.NO_CLUB:
		line.seed_label.text = ""
		line.name_label.text = "—"
		line.name_label.add_theme_color_override("font_color", MenuStyle.TEXT_MUTED)
		line.score_label.text = ""
		return
	line.seed_label.text = str(TournamentRules.seed_of(state, club) + 1)
	line.name_label.text = TournamentCopy.club_name(club)
	var ink: Color = MenuStyle.TEXT_BODY
	if lost:
		ink.a = _LOSER_ALPHA
	line.crest.modulate.a = _LOSER_ALPHA if lost else 1.0
	line.name_label.add_theme_color_override("font_color", ink)
	line.score_label.add_theme_color_override("font_color", ink)
	if score == TournamentState.UNPLAYED:
		line.score_label.text = ""
	elif won_in_overtime:
		line.score_label.text = TournamentCopy.t(&"TOURNAMENT_SCORE_OT") % score
	else:
		line.score_label.text = str(score)


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

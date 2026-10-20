extends GutTest

# RosterAnnouncer — which ticker line each roster change reads as. The registry
# signals are stood in for by this script's own, so no skater is spawned.

signal added(record: PlayerRecord)
signal removed(record: PlayerRecord)

var _spectators: Dictionary[int, bool] = {}
var _lines: Array[StringName] = []
var _announcer: RosterAnnouncer = null


func before_each() -> void:
	_spectators.clear()
	_lines.clear()
	_announcer = RosterAnnouncer.new(added, removed,
			func(peer_id: int) -> bool: return _spectators.has(peer_id))
	_announcer.announced.connect(
			func(_n: String, key: StringName, _c: Dictionary) -> void: _lines.append(key))


func _record(peer_id: int, team_id: int, is_local: bool = false) -> PlayerRecord:
	var team := Team.new()
	team.team_id = team_id
	return PlayerRecord.new(peer_id, 0, is_local, team)


func test_a_spawn_is_a_join_and_a_despawn_a_leave() -> void:
	var r: PlayerRecord = _record(7, 0)
	added.emit(r)
	removed.emit(r)
	assert_eq(_lines, [&"TOAST_PLAYER_JOINED", &"TOAST_PLAYER_LEFT"])


func test_a_marked_spectator_is_moving_not_coming_or_going() -> void:
	var r: PlayerRecord = _record(7, 0)
	_spectators[7] = true
	removed.emit(r)
	added.emit(r)
	assert_eq(_lines, [&"TOAST_PLAYER_SPECTATING", &"TOAST_PLAYER_NOW_PLAYING"])


func test_the_local_player_is_never_announced() -> void:
	var r: PlayerRecord = _record(1, 0, true)
	added.emit(r)
	removed.emit(r)
	_announcer.on_swap_confirmed(r, 1)
	assert_eq(_lines.size(), 0)


func test_only_a_change_of_team_is_a_switch() -> void:
	var r: PlayerRecord = _record(7, 1)
	_announcer.on_swap_confirmed(r, 1)
	assert_eq(_lines.size(), 0, "a slot change within the team is silent")
	_announcer.on_swap_confirmed(r, 0)
	assert_eq(_lines, [&"TOAST_PLAYER_SWITCHED_TEAMS"])


func test_the_line_wears_the_record_team_palette() -> void:
	var colors: Array[Dictionary] = []
	_announcer.announced.connect(
			func(_n: String, _k: StringName, c: Dictionary) -> void: colors.append(c))
	var r: PlayerRecord = _record(7, 1)
	r.team.color_slot = 3
	added.emit(r)
	assert_eq(colors[0], TeamColorRegistry.get_ui_colors(3, 1))


func test_every_line_has_a_catalogue_row() -> void:
	var r: PlayerRecord = _record(7, 0)
	added.emit(r)
	removed.emit(r)
	_spectators[7] = true
	removed.emit(r)
	added.emit(r)
	r.team.team_id = 1
	_announcer.on_swap_confirmed(r, 0)
	for key: StringName in _lines:
		assert_ne(TranslationServer.translate(key), String(key), "%s has a translation row" % key)

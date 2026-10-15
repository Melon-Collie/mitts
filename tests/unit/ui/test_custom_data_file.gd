extends GutTest

# The Customization rows tell a player which file the game will use: the
# built-in one, their edited copy, or the built-in one because their copy is
# broken or short of teams. Those verdicts are pure functions of the file
# contents and of the registry's own acceptance test, so they are held here.

const _USER: String = "user://team_colors.json"
const _RES: String = "res://data/team_colors.json"
const _SCRATCH: String = "user://test_custom_data_file.json"
const _State = CustomDataFile.State

var _bundled: String = ""


func before_all() -> void:
	_bundled = FileAccess.get_file_as_string(_RES)


func _colors(text: String) -> int:
	return CustomDataFile.assess(true, text, _bundled, TeamColorRegistry.accepts, "teams")


func _with_teams(count: int) -> String:
	var data: Dictionary = JSON.parse_string(_bundled)
	data.teams = (data.teams as Array).slice(0, count)
	return JSON.stringify(data)


func test_no_copy_means_the_built_in_file() -> void:
	assert_eq(CustomDataFile.assess(false, "", _bundled, TeamColorRegistry.accepts, "teams"),
			_State.NONE)


func test_a_fresh_copy_is_in_use() -> void:
	assert_eq(_colors(_bundled), _State.IN_USE)


func test_a_copy_short_of_teams_is_out_of_date() -> void:
	var shipped: int = (JSON.parse_string(_bundled).teams as Array).size()
	assert_eq(_colors(_with_teams(shipped - 1)), _State.OUTDATED)


func test_a_copy_the_loader_rejects_is_unreadable() -> void:
	assert_eq(_colors("{ not json"), _State.UNREADABLE, "malformed JSON")
	assert_eq(_colors('{"schema": "mitts.jersey.v1", "teams": [{}]}'), _State.UNREADABLE,
			"wrong schema")
	assert_eq(_colors(_with_teams(0)), _State.UNREADABLE, "no teams")


# A shorter bot roster is a choice, so the bots row passes no entries key.
func test_without_an_entries_key_a_short_copy_is_just_in_use() -> void:
	var roster: String = '{"identities": []}'
	assert_eq(CustomDataFile.assess(true, roster,
			FileAccess.get_file_as_string("res://data/bot_identities.json"),
			BotIdentityRegistry.accepts, ""), _State.IN_USE)


func test_restart_is_asked_for_exactly_when_the_loaded_file_is_not_the_next_one() -> void:
	assert_false(CustomDataFile.needs_restart(_State.NONE, _RES, _USER))
	assert_true(CustomDataFile.needs_restart(_State.NONE, _USER, _USER), "copy dropped")
	assert_true(CustomDataFile.needs_restart(_State.IN_USE, _RES, _USER), "copy created")
	assert_false(CustomDataFile.needs_restart(_State.IN_USE, _USER, _USER))
	assert_false(CustomDataFile.needs_restart(_State.OUTDATED, _USER, _USER))
	assert_false(CustomDataFile.needs_restart(_State.UNREADABLE, _RES, _USER),
			"the loader already fell back to the built-in file")


func test_the_registries_accept_their_own_bundled_files() -> void:
	assert_true(TeamColorRegistry.accepts(JSON.parse_string(_bundled)))
	assert_true(BotIdentityRegistry.accepts(JSON.parse_string(
			FileAccess.get_file_as_string("res://data/bot_identities.json"))))
	assert_false(BotIdentityRegistry.accepts(JSON.parse_string('{"bots": []}')))


# The buttons, against a scratch copy so a real edited file is never touched.
func _row(loaded: String) -> CustomDataFile:
	var host: Control = add_child_autofree(Control.new())
	var row := CustomDataFile.new(_RES, _SCRATCH, TeamColorRegistry.accepts,
			func() -> String: return loaded, "teams", "TEAM_COLORS_FILE_OUTDATED")
	host.add_child(row.build_buttons(host))
	host.add_child(row.build_status())
	return row


func after_each() -> void:
	if FileAccess.file_exists(_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_SCRATCH))


func test_create_writes_the_copy_and_asks_for_a_restart() -> void:
	var row: CustomDataFile = _row(_RES)
	assert_true(row._drop_btn.disabled, "nothing to drop yet")
	row._on_create_pressed()
	assert_eq(FileAccess.get_file_as_string(_SCRATCH), _bundled)
	assert_false(row._drop_btn.disabled)
	assert_string_contains(row._status.text, ProjectSettings.globalize_path(_SCRATCH))
	assert_string_contains(row._status.text, row._host.tr("CUSTOM_FILE_RESTART"))


func test_starting_over_asks_before_replacing_edits() -> void:
	var row: CustomDataFile = _row(_SCRATCH)
	row._on_create_pressed()
	var edited := FileAccess.open(_SCRATCH, FileAccess.WRITE)
	edited.store_string(_with_teams(3))
	edited.close()
	row._on_create_pressed()
	assert_true(row._confirm.visible, "a copy exists, so it asks first")
	assert_eq(FileAccess.get_file_as_string(_SCRATCH), _with_teams(3), "and has not written")
	row._confirm._on_confirm()
	assert_eq(FileAccess.get_file_as_string(_SCRATCH), _bundled)


func test_use_built_in_deletes_the_copy_after_asking() -> void:
	var row: CustomDataFile = _row(_SCRATCH)
	row._on_create_pressed()
	row._on_drop_pressed()
	assert_true(FileAccess.file_exists(_SCRATCH), "it asks first")
	row._confirm._on_cancel()
	assert_true(FileAccess.file_exists(_SCRATCH), "cancel keeps it")
	row._on_drop_pressed()
	row._confirm._on_confirm()
	assert_false(FileAccess.file_exists(_SCRATCH))
	assert_true(row._drop_btn.disabled)
	assert_string_contains(row._status.text, row._host.tr("CUSTOM_FILE_RESTART"),
			"the copy is still what this session loaded")

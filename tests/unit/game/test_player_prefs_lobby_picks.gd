extends GutTest

# The lobby picks a host keeps between sessions (PlayerPrefs.preferred_rule_set):
# they survive a save and a load, and a stored value no rule set answers to
# falls back to the default rather than seeding a lobby with it.
#
# Instantiated and redirected as test_player_prefs_bindings.gd does, for the
# same reasons.

const PlayerPrefsScript = preload("res://Scripts/game/player_prefs.gd")

const TEST_CONFIG: String = "user://test_player_prefs_lobby_picks.cfg"


class RedirectedPrefs extends PlayerPrefsScript:
	func _get_save_path() -> String:
		return "user://test_player_prefs_lobby_picks.cfg"


var _saved_input_map: Dictionary = {}


func before_each() -> void:
	_saved_input_map.clear()
	for action: String in PlayerPrefsScript.REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			_saved_input_map[action] = InputMap.action_get_events(action)


func after_each() -> void:
	for action: String in _saved_input_map:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _saved_input_map[action]:
			InputMap.action_add_event(action, ev)
	DirAccess.remove_absolute(TEST_CONFIG)


func _fresh() -> Node:
	return autofree(RedirectedPrefs.new())


func test_every_rule_set_survives_a_save_and_load() -> void:
	for rule_set: int in GameRules.RuleSet.values():
		var writer: Node = _fresh()
		writer.preferred_rule_set = rule_set
		writer.save()

		var reader: Node = _fresh()
		reader._load()
		assert_eq(reader.preferred_rule_set, rule_set,
				"%s did not survive save + load" % GameRules.RULE_SET_NAMES[rule_set])


func test_a_stored_value_that_is_no_rule_set_loads_as_the_default() -> void:
	for stored: int in [-1, GameRules.RULE_SET_NAMES.size()]:
		var cfg := ConfigFile.new()
		cfg.set_value("player", "preferred_rule_set", stored)
		cfg.save(TEST_CONFIG)

		var reader: Node = _fresh()
		reader._load()
		assert_eq(reader.preferred_rule_set, GameRules.DEFAULT_RULE_SET,
				"stored %d should fall back to the default" % stored)


func test_every_rule_set_has_a_name() -> void:
	assert_eq(GameRules.RuleSet.size(), GameRules.RULE_SET_NAMES.size(),
			"is_rule_set bounds a stored pick by the names table")

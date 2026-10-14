extends GutTest

# The agent's collaborators (SkaterAgentShotBlock, SkaterAgentBoardPlay, ...) each
# own the state they write. The state machine hands them what they need per call
# and never writes their fields: a caller that writes a collaborator's field has
# re-derived when to write it, and the collaborator's own lifecycle for it rots
# without failing anything (Scripts/controllers/CLAUDE.md → "What kills a
# collaborator extraction"). Nor does a collaborator name the state machine — its
# inputs come in as arguments.

const _AGENT: String = "res://Scripts/ai/skater_agent_state_machine.gd"


func _strip(src: String) -> String:
	var out := PackedStringArray()
	for line: String in src.split("\n"):
		out.append(line.split("#")[0])
	return "\n".join(out)


# `var _board_play := SkaterAgentBoardPlay.new()` -> {"_board_play": "SkaterAgentBoardPlay"}
func _collaborators(src: String) -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.create_from_string(
			"(?m)^var (_[a-z_0-9]+)\\s*:?=\\s*(SkaterAgent[A-Za-z0-9]+)\\.new\\(\\)")
	for m: RegExMatch in re.search_all(src):
		out[m.get_string(1)] = m.get_string(2)
	return out


func _path_for(cls: String) -> String:
	var snake: String = ""
	for i: int in cls.length():
		var c: String = cls[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower():
			snake += "_"
		snake += c.to_lower()
	return "res://Scripts/ai/%s.gd" % snake


func test_the_agent_never_writes_a_collaborator_field() -> void:
	var src: String = _strip(FileAccess.get_file_as_string(_AGENT))
	var found: Dictionary = _collaborators(src)
	assert_gt(found.size(), 1, "expected the agent to hold its collaborators")
	for holder: String in found:
		var re := RegEx.create_from_string(
				"%s\\.([a-z_][a-z_0-9]*)\\s*(?:=(?!=)|\\+=|-=|\\*=)\\s" % holder)
		var writes := PackedStringArray()
		for m: RegExMatch in re.search_all(src):
			writes.append(m.get_string(1))
		assert_eq(writes.size(), 0, "the agent writes %s's fields %s — pass them in instead" % [
				found[holder], writes])


func test_no_collaborator_names_the_agent() -> void:
	var found: Dictionary = _collaborators(_strip(FileAccess.get_file_as_string(_AGENT)))
	for holder: String in found:
		var path: String = _path_for(found[holder])
		assert_true(FileAccess.file_exists(path), "no source at %s" % path)
		var src: String = _strip(FileAccess.get_file_as_string(path))
		assert_false(src.contains("SkaterAgentStateMachine"),
				"%s names SkaterAgentStateMachine — its inputs come in as arguments" % found[holder])

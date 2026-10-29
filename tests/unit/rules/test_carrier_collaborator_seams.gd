extends GutTest

# AIRoleCarrier's collaborators: AICarrierField (what it sees and what a spot is
# worth) and the searches over it (AICarrierPassSearch, AICarrierCarrySearch).
# The carrier reads their results and never writes their
# fields; no search names the carrier; and the field's lists are written only
# by its own fill passes, so every search in a phase reads the same field.

const _DIR: String = "res://Scripts/domain/ai/role_behaviors/"
const _CARRIER: String = _DIR + "carrier.gd"
const _FIELD: String = _DIR + "carrier_field.gd"
const _SEARCHES: Array[String] = [
	_DIR + "carrier_pass_search.gd",
	_DIR + "carrier_carry_search.gd",
	_DIR + "carrier_dump_search.gd",
	_DIR + "carrier_destinations.gd",
	_DIR + "carrier_wheel.gd",
]
# The field's members a search may drive: the hold solver is a tool whose
# results are read back after each solve.
const _FIELD_TOOLS: Array[String] = ["holds"]
const _LIST_WRITE := "(?:\\s*(?:=(?!=)|\\+=|-=)|\\.(?:clear|append|resize|fill|push_back)\\()"


func _strip(src: String) -> String:
	var out := PackedStringArray()
	for line: String in src.split("\n"):
		out.append(line.split("#")[0])
	return "\n".join(out)


func _src(path: String) -> String:
	return _strip(FileAccess.get_file_as_string(path))


func test_the_carrier_never_writes_a_collaborator_field() -> void:
	var src: String = _src(_CARRIER)
	for holder: String in ["_field", "_pass", "_carry", "_dump"]:
		assert_true(src.contains("var %s := " % holder), "the carrier holds %s" % holder)
		var re := RegEx.create_from_string("%s\\.([a-z_][a-z_0-9]*)%s" % [holder, _LIST_WRITE])
		var writes := PackedStringArray()
		for m: RegExMatch in re.search_all(src):
			writes.append(m.get_string(1))
		assert_eq(writes.size(), 0, "the carrier writes %s.%s — read results, pass inputs in" % [
				holder, writes])


func test_no_collaborator_names_the_carrier() -> void:
	for path: String in _SEARCHES + [_FIELD]:
		assert_false(_src(path).contains("AIRoleCarrier"),
				"%s names AIRoleCarrier — its inputs come in as arguments" % path)


func test_only_the_field_writes_its_lists() -> void:
	var re := RegEx.create_from_string("_field\\.([a-z_][a-z_0-9]*)%s" % _LIST_WRITE)
	for path: String in _SEARCHES:
		var writes := PackedStringArray()
		for m: RegExMatch in re.search_all(_src(path)):
			if not _FIELD_TOOLS.has(m.get_string(1)):
				writes.append(m.get_string(1))
		assert_eq(writes.size(), 0, "%s writes the field's %s" % [path, writes])


func test_inside_the_field_only_the_fill_passes_write_the_lists() -> void:
	var src: String = _src(_FIELD)
	var publics := PackedStringArray()
	for m: RegExMatch in RegEx.create_from_string(
			"(?m)^var ([a-z][a-z_0-9]*)\\s*:\\s*Array").search_all(src):
		publics.append(m.get_string(1))
	assert_gt(publics.size(), 5, "found the field's lists")
	var func_re := RegEx.create_from_string("(?m)^(?:static )?func ([a-z_0-9]+)\\(")
	var bodies: Array[RegExMatch] = func_re.search_all(src)
	for i: int in bodies.size():
		var body_name: String = bodies[i].get_string(1)
		if body_name in ["fill", "fill_receivers"]:
			continue
		var end: int = bodies[i + 1].get_start() if i + 1 < bodies.size() else src.length()
		var body: String = src.substr(bodies[i].get_start(), end - bodies[i].get_start())
		for list: String in publics:
			var w := RegEx.create_from_string("(?<![\\w.])%s%s" % [list, _LIST_WRITE])
			assert_null(w.search(body), "AICarrierField.%s writes %s" % [body_name, list])

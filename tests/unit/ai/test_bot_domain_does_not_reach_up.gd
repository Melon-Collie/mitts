extends GutTest

# Lower layers never reach up (CLAUDE.md → Layer Architecture). The bot's
# decision layer under Scripts/domain/ prices what the agent under Scripts/ai/
# executes, so anything both read — the body's execution constants, the
# strategy interface — lives in the domain, and no domain file names a class
# declared under Scripts/ai/.

const _AGENT_ROOT: String = "res://Scripts/ai"
const _DOMAIN_ROOT: String = "res://Scripts/domain"


func _gd_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	for d: String in dir.get_directories():
		out.append_array(_gd_files("%s/%s" % [root, d]))
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append("%s/%s" % [root, f])
	return out


func test_no_domain_file_names_an_agent_class() -> void:
	var agent_classes := PackedStringArray()
	var decl := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	for path: String in _gd_files(_AGENT_ROOT):
		var m: RegExMatch = decl.search(FileAccess.get_file_as_string(path))
		if m != null:
			agent_classes.append(m.get_string(1))
	assert_gt(agent_classes.size(), 3, "the scan must find the agent classes")
	var word := RegEx.create_from_string("\\b(%s)\\b" % "|".join(agent_classes))
	var hits := PackedStringArray()
	for path: String in _gd_files(_DOMAIN_ROOT):
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			var m: RegExMatch = word.search(lines[i].split("#")[0])
			if m != null:
				hits.append("%s:%d (%s)" % [path, i + 1, m.get_string(1)])
	assert_eq(hits.size(), 0, "domain code names agent classes: %s" % [hits])

extends GutTest

# Scripts/domain/ai/DECISIONS.md is a catalogue of `file.gd:symbol` citations.
# Every one must name a script that exists exactly once under Scripts/ and a
# symbol that script declares, or the catalogue has drifted from the code. A
# trailing `*` cites a family of symbols by prefix.

const DOC_PATH := "res://Scripts/domain/ai/DECISIONS.md"
const DECLARATION := "(?m)^\\s*(static func|func|const|var|class_name|class|signal|enum)\\s+%s"
# The doc's own notation example, not a citation.
const NOTATION_EXAMPLE := "file.gd:func"


func _scripts_by_basename(dir: String, out: Dictionary) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_scripts_by_basename(dir.path_join(sub), out)
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var paths: Array = out.get(f, [])
			paths.append(dir.path_join(f))
			out[f] = paths


func test_every_citation_resolves() -> void:
	var doc: String = FileAccess.get_file_as_string(DOC_PATH)
	assert_false(doc.is_empty(), "read %s" % DOC_PATH)
	var scripts: Dictionary = {}
	_scripts_by_basename("res://Scripts", scripts)
	var cite := RegEx.create_from_string("([a-z_0-9]+\\.gd):([A-Za-z_][A-Za-z_0-9]*)(\\*?)")
	var checked: int = 0
	for m: RegExMatch in cite.search_all(doc):
		if m.get_string() == NOTATION_EXAMPLE:
			continue
		var file: String = m.get_string(1)
		var symbol: String = m.get_string(2)
		var paths: Array = scripts.get(file, [])
		if paths.size() != 1:
			fail_test("%s cites %s, which matches %d scripts" % [DOC_PATH, file, paths.size()])
			continue
		var pattern: String = DECLARATION % symbol
		if m.get_string(3).is_empty():
			pattern += "\\b"
		var src: String = FileAccess.get_file_as_string(paths[0])
		assert_not_null(RegEx.create_from_string(pattern).search(src),
				"%s cites %s:%s%s, which %s does not declare"
				% [DOC_PATH, file, symbol, m.get_string(3), paths[0]])
		checked += 1
	assert_gt(checked, 100, "the citations were found")

extends GutTest

# Every Image and Performance setting in Options → Video tells the player what
# it costs: a row is followed by its impact note. A setting added without one
# is a knob the player has to guess about, which is what the notes exist to end.


func _tab() -> OptionsVideoTab:
	var tab := OptionsVideoTab.new()
	tab.build()
	add_child_autofree(tab)
	return tab


func test_every_image_and_performance_row_has_an_impact_note() -> void:
	var tab: OptionsVideoTab = _tab()
	var in_scope: bool = false
	var rows: int = 0
	var children: Array[Node] = tab.get_children()
	for i: int in children.size():
		var child: Node = children[i]
		if child is Label and (child as Label).text in ["IMAGE", "PERFORMANCE"]:
			in_scope = true
			continue
		if not in_scope or not child is HBoxContainer:
			continue
		rows += 1
		var label: String = ((child as HBoxContainer).get_child(0) as Label).text
		var next: Node = children[i + 1] if i + 1 < children.size() else null
		assert_true(next != null and next.has_meta(&"impact"),
				"%s has no impact note under it" % label)
	assert_gt(rows, 15, "the Image and Performance sections were found")


func test_notes_and_tags_are_translated() -> void:
	var tab: OptionsVideoTab = _tab()
	for child: Node in tab.get_children():
		if not child.has_meta(&"impact"):
			continue
		for note: RichTextLabel in child.find_children("*", "RichTextLabel", true, false):
			assert_false(note.get_parsed_text().contains("OPTIONS_"),
					"%s renders a raw key" % note.get_parsed_text())

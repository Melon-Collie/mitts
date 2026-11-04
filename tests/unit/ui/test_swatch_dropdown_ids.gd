extends GutTest

# SwatchDropdown with ids: a filtered palette takes and reports the caller's own
# indices, so a shown entry's position never leaks out as a palette index.

var _dd: SwatchDropdown = null


func before_each() -> void:
	_dd = SwatchDropdown.new()
	add_child_autofree(_dd)
	var colors: Array[Color] = [Color.RED, Color.WHITE, Color.BLACK]
	var names: Array[String] = ["a", "b", "c"]
	var ids: Array[int] = [0, 11, 2]
	_dd.set_palette(colors, names, [], ids)


func test_selection_reports_the_id_not_the_position() -> void:
	var got: Array[int] = []
	_dd.selected.connect(func(id: int) -> void: got.append(id))
	_dd._on_swatch_pressed(1)
	assert_eq(got, [11] as Array[int])


func test_selecting_an_id_shows_its_entry() -> void:
	_dd.set_selected(2)
	assert_eq(_dd._selected_index, 2)
	_dd.set_selected(11)
	assert_eq(_dd._selected_index, 1)
	_dd.set_selected(5)
	assert_eq(_dd._selected_index, 0, "an id not shown selects the first entry")

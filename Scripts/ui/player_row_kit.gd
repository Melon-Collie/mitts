class_name PlayerRowKit

# Widget factories for the player screen's rows. Static, so every caller hands
# in text it has already translated.
#
# A row is a fixed label gutter (the name, plus the gold asterisk when the pick
# changes how the skater plays) beside a content column holding the control and,
# for gameplay picks, a one-line hint saying what the current choice does.

const LABEL_W: float = 118.0
const FIELD_W: float = 420.0
const CONTROL_H: float = 40.0
const _SWATCH_STRIP := Vector2i(36, 18)


# Adds a labelled row to `parent` and returns its content column. The label
# and asterisk are `MOUSE_FILTER_STOP` so hovering them reports the row too:
# `reached` fires on hover anywhere in the row.
static func row(parent: Container, label_text: String, gameplay: bool,
		reached: Callable) -> VBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.mouse_entered.connect(reached)
	parent.add_child(line)

	var gutter := HBoxContainer.new()
	gutter.custom_minimum_size = Vector2(LABEL_W, CONTROL_H)
	gutter.add_theme_constant_override("separation", 3)
	gutter.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(gutter)

	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, CONTROL_H)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", MenuStyle.TEXT_BODY)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_entered.connect(reached)
	gutter.add_child(label)
	if gameplay:
		gutter.add_child(star())

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	content.custom_minimum_size = Vector2(FIELD_W, 0)
	line.add_child(content)
	return content


# The gold asterisk that marks a pick that changes play. Its meaning is the
# screen's legend, so it carries no tooltip of its own.
static func star() -> Label:
	var s := Label.new()
	s.text = "*"
	s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 20)
	s.add_theme_color_override("font_color", MenuStyle.GOLD)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


# The dim line under a gameplay row naming what the current pick does.
static func hint(parent: Container) -> Label:
	var h := Label.new()
	h.add_theme_font_size_override("font_size", 13)
	h.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.custom_minimum_size = Vector2(FIELD_W, 0)
	parent.add_child(h)
	return h


# One toggle button per label, sharing the field width. `on_pick(index)` fires
# on a press; the caller owns which one shows as picked (`select`), so a press
# on the picked button can never leave the row with none.
static func segmented(parent: Container, labels: Array[String],
		on_pick: Callable) -> Array[Button]:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.custom_minimum_size = Vector2(FIELD_W, 0)
	parent.add_child(bar)
	var buttons: Array[Button] = []
	for i: int in labels.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, CONTROL_H)
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 15)
		_style_segment(btn)
		SoundManager.wire_button(btn)
		btn.pressed.connect(on_pick.bind(i))
		bar.add_child(btn)
		buttons.append(btn)
	return buttons


static func select(buttons: Array[Button], index: int) -> void:
	for i: int in buttons.size():
		buttons[i].set_pressed_no_signal(i == index)


# Rewrites the labels in place — the flex row's numbers follow the weight.
static func relabel(buttons: Array[Button], labels: Array[String]) -> void:
	for i: int in mini(buttons.size(), labels.size()):
		buttons[i].text = labels[i]


# One toggle swatch per colour, filling the field width; the picked one wears a
# white ring. Selection works as `segmented` does.
static func swatches(parent: Container, colors: Array[Color], names: Array[String],
		on_pick: Callable) -> Array[Button]:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.custom_minimum_size = Vector2(FIELD_W, 0)
	parent.add_child(bar)
	var buttons: Array[Button] = []
	for i: int in colors.size():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.tooltip_text = names[i] if i < names.size() else ""
		btn.custom_minimum_size = Vector2(0, CONTROL_H)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var plain := StyleBoxFlat.new()
		plain.bg_color = colors[i]
		plain.set_corner_radius_all(6)
		var ringed := plain.duplicate() as StyleBoxFlat
		ringed.border_color = Color.WHITE
		ringed.set_border_width_all(3)
		btn.add_theme_stylebox_override("normal", plain)
		btn.add_theme_stylebox_override("hover", ringed)
		btn.add_theme_stylebox_override("pressed", ringed)
		btn.add_theme_stylebox_override("hover_pressed", ringed)
		MenuStyle.apply_focus_ring(btn)
		SoundManager.wire_button(btn)
		btn.pressed.connect(on_pick.bind(i))
		bar.add_child(btn)
		buttons.append(btn)
	return buttons


static func option_button(parent: Container, on_pick: Callable) -> OptionButton:
	var btn := OptionButton.new()
	btn.custom_minimum_size = Vector2(FIELD_W, CONTROL_H)
	btn.add_theme_font_size_override("font_size", 15)
	SoundManager.wire_button(btn)
	btn.item_selected.connect(on_pick)
	parent.add_child(btn)
	return btn


# An option button listing `keys`, translated, each item's id its index.
static func option_list(parent: Container, keys: Array[StringName],
		on_pick: Callable) -> OptionButton:
	var btn: OptionButton = option_button(parent, on_pick)
	for i: int in keys.size():
		btn.add_item(TranslationServer.translate(keys[i]), i)
	return btn


# A slider with its value read out beside it; returns [slider, value label].
static func slider(parent: Container, on_change: Callable) -> Array[Control]:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.custom_minimum_size = Vector2(FIELD_W, CONTROL_H)
	parent.add_child(line)
	var s := HSlider.new()
	s.step = 1
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(on_change)
	line.add_child(s)
	var value := Label.new()
	value.custom_minimum_size = Vector2(76, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", MenuStyle.TEXT_BODY)
	line.add_child(value)
	return [s, value]


# One design's zones as a strip of equal vertical bands. The last band absorbs
# the rounding remainder so a 3-zone strip fills the same width as a 5-zone one.
static func swatch_strip(zones: Array[Color]) -> ImageTexture:
	var img := Image.create(_SWATCH_STRIP.x, _SWATCH_STRIP.y, false, Image.FORMAT_RGBA8)
	var band: int = _SWATCH_STRIP.x / zones.size()
	for i: int in zones.size():
		var x0: int = i * band
		var w: int = _SWATCH_STRIP.x - x0 if i == zones.size() - 1 else band
		img.fill_rect(Rect2i(x0, 0, w, _SWATCH_STRIP.y), zones[i])
	return ImageTexture.create_from_image(img)


# Ghost at rest, teal fill when picked — the pick reads at a glance across a
# row of equals.
static func _style_segment(btn: Button) -> void:
	var rest := StyleBoxFlat.new()
	rest.bg_color = MenuStyle.BTN_FILL
	rest.border_color = MenuStyle.TEXT_SEP
	rest.set_border_width_all(1)
	rest.set_corner_radius_all(6)
	rest.set_content_margin_all(6)
	var hover := rest.duplicate() as StyleBoxFlat
	hover.bg_color = MenuStyle.BTN_HOVER
	var picked := rest.duplicate() as StyleBoxFlat
	picked.bg_color = MenuStyle.TEAL
	picked.border_color = MenuStyle.TEAL
	btn.add_theme_stylebox_override("normal", rest)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", picked)
	btn.add_theme_stylebox_override("hover_pressed", picked)
	btn.add_theme_color_override("font_color", MenuStyle.TEXT_BODY)
	btn.add_theme_color_override("font_hover_color", MenuStyle.TEXT_BODY)
	btn.add_theme_color_override("font_pressed_color", MenuStyle.ON_TEAL)
	btn.add_theme_color_override("font_hover_pressed_color", MenuStyle.ON_TEAL)
	btn.add_theme_color_override("font_focus_color", MenuStyle.TEXT_BODY)
	MenuStyle.apply_focus_ring(btn)

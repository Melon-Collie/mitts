class_name BuildStatPanel
extends PanelContainer

# The player screen's readout of what a build does to play: every
# BuildReadout stat as a bar diverging from the neutral build, with its signed
# percentage. The rows a region's dials can move stay bright and the rest dim,
# so a pick and its consequences read together.

# Full bar at ±25%: the widest real spread (mass) runs past it and clips, while
# a one-step gear lean (3–7%) still reads as a visible bar.
const _FULL_SCALE: float = 0.25
const _GAIN_COLOR := MenuStyle.TEAL
# Warm rather than red: a cost is the other side of a trade, not an error.
const _COST_COLOR := Color(0.91, 0.64, 0.35)
const _DIM_ALPHA: float = 0.32

var _rows: Array[HBoxContainer] = []
var _bars: Array[_DivergingBar] = []
var _values: Array[Label] = []
var _note: Label = null


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.SURFACE_INPUT
	style.border_color = MenuStyle.TEXT_SEP
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	_build()


func show_build(attrs: PlayerAttributes) -> void:
	for s: int in BuildReadout.STAT_COUNT:
		var delta: float = BuildReadout.ratio(attrs, s) - 1.0
		var pct: int = roundi(delta * 100.0)
		var color: Color = _GAIN_COLOR if pct > 0 else (_COST_COLOR if pct < 0 else MenuStyle.TEXT_MUTED)
		_bars[s].set_value(clampf(delta / _FULL_SCALE, -1.0, 1.0), color)
		_values[s].text = "—" if pct == 0 else ("+%d%%" % pct if pct > 0 else "−%d%%" % -pct)
		_values[s].add_theme_color_override("font_color", color)


# `stats` empty = nothing to single out, every row at full strength.
func emphasize(stats: Array[int], note: String) -> void:
	for s: int in BuildReadout.STAT_COUNT:
		_rows[s].modulate.a = 1.0 if stats.is_empty() or stats.has(s) else _DIM_ALPHA
	_note.text = note


func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	add_child(col)

	var title := Label.new()
	title.text = tr(&"STAT_PANEL_TITLE")
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	col.add_child(title)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(300, 0)
	col.add_child(_note)

	var group: int = -1
	for s: int in BuildReadout.STAT_COUNT:
		if BuildReadout.GROUP_OF[s] != group:
			group = BuildReadout.GROUP_OF[s]
			var header := Label.new()
			header.text = tr(BuildReadout.GROUP_KEYS[group])
			header.add_theme_font_size_override("font_size", 12)
			header.add_theme_color_override("font_color", MenuStyle.TEAL)
			col.add_child(header)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		col.add_child(line)
		var name_label := Label.new()
		name_label.text = tr(BuildReadout.NAME_KEYS[s])
		name_label.custom_minimum_size = Vector2(140, 22)
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", MenuStyle.TEXT_BODY)
		line.add_child(name_label)
		var bar := _DivergingBar.new()
		bar.custom_minimum_size = Vector2(120, 22)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(bar)
		var value := Label.new()
		value.custom_minimum_size = Vector2(48, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 14)
		line.add_child(value)
		_rows.append(line)
		_bars.append(bar)
		_values.append(value)


# A track with a centre tick, filled from the centre toward −1 (left) or +1.
class _DivergingBar:
	extends Control

	const _TRACK_H: float = 8.0
	var _value: float = 0.0
	var _color: Color = Color.WHITE

	func set_value(value: float, color: Color) -> void:
		_value = value
		_color = color
		queue_redraw()

	func _draw() -> void:
		var y: float = (size.y - _TRACK_H) * 0.5
		var mid: float = size.x * 0.5
		draw_rect(Rect2(0.0, y, size.x, _TRACK_H), MenuStyle.SURFACE_ELEV)
		var w: float = absf(_value) * mid
		var x: float = mid if _value >= 0.0 else mid - w
		draw_rect(Rect2(x, y, w, _TRACK_H), _color)
		draw_rect(Rect2(mid - 0.5, y - 3.0, 1.0, _TRACK_H + 6.0), MenuStyle.TEXT_MUTED)

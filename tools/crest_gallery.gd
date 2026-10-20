extends SceneTree

# Dev visualizer: every crest still being chosen, large — one row per fruit, each
# of its CrestFruits variants on the team's home and away jersey color — in one
# PNG for judging the drawings. The on-garment scale is render-kits.sh with
# KIT_PREVIEW_FRONT=crest KIT_PREVIEW_CREST_VARIANT=<variant>.
#
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#       --rendering-method gl_compatibility -s res://tools/crest_gallery.gd
#
# CREST_GALLERY_OUT (default user://crest_gallery.png).

const _CELL: float = 160.0
const _CREST_R: float = 60.0
const _LABEL_W: float = 170.0
const _HEADER_H: float = 64.0
const _VARIANT_GAP: float = 16.0
const _BG: Color = Color(0.13, 0.14, 0.17)
const _INK: Color = Color(0.93, 0.94, 0.96)
const _OUT_ENV: String = "CREST_GALLERY_OUT"

var _slots: Array[int] = []
var _sheet: SubViewport
var _canvas: Node2D


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	await process_frame
	for slot: int in TeamColorRegistry.get_all_slots():
		var fruit: String = TeamColorRegistry.get_preset_name(slot).to_lower()
		if CrestFruits.has("%s:current" % fruit):
			_slots.append(slot)
	_sheet = SubViewport.new()
	_sheet.size = Vector2i(_size())
	_sheet.transparent_bg = false
	_sheet.disable_3d = true
	_sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sheet)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_sheet)
	_sheet.add_child(_canvas)
	for _i: int in 4:
		await process_frame
	var path: String = OS.get_environment(_OUT_ENV)
	if path.is_empty():
		path = "user://crest_gallery.png"
	_sheet.get_texture().get_image().save_png(path)
	print("[crest_gallery] -> %s" % ProjectSettings.globalize_path(path))
	quit()


func _size() -> Vector2:
	var variants: int = CrestFruits.VARIANT_NAMES.size()
	return Vector2(_LABEL_W + (_CELL * 2.0 + _VARIANT_GAP) * variants,
			_HEADER_H + _CELL * _slots.size())


func _column_x(variant: int, side: int) -> float:
	return _LABEL_W + (_CELL * 2.0 + _VARIANT_GAP) * variant + _CELL * side


func _draw_sheet() -> void:
	var c: Node2D = _canvas
	var font: Font = JerseyDecal.FONT
	c.draw_rect(Rect2(Vector2.ZERO, _size()), _BG)
	for v: int in CrestFruits.VARIANT_NAMES.size():
		c.draw_string(font, Vector2(_column_x(v, 0), 28.0),
				CrestFruits.VARIANT_NAMES[v].to_upper(),
				HORIZONTAL_ALIGNMENT_CENTER, _CELL * 2.0, 24, _INK)
		for side: int in 2:
			c.draw_string(font, Vector2(_column_x(v, side), 54.0),
					"HOME" if side == 0 else "AWAY", HORIZONTAL_ALIGNMENT_CENTER, _CELL, 16, _INK)
	for row: int in _slots.size():
		var preset: Dictionary = TeamColorRegistry.get_preset(_slots[row])
		var fruit: String = String(preset.name).to_lower()
		var y: float = _HEADER_H + _CELL * float(row)
		c.draw_string(font, Vector2(12.0, y + _CELL * 0.5 + 8.0), fruit.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, _INK)
		for v: int in CrestFruits.VARIANT_NAMES.size():
			var id: String = CrestFruits.resolve(fruit, CrestFruits.VARIANT_NAMES[v])
			for side: int in 2:
				var kit: Dictionary = preset.home if side == 0 else preset.away
				var x: float = _column_x(v, side)
				c.draw_rect(Rect2(x + 2.0, y + 2.0, _CELL - 4.0, _CELL - 4.0), kit.jersey.base)
				TeamCrest.draw(c, id, Transform2D(0.0, Vector2.ONE * _CREST_R, 0.0,
						Vector2(x + _CELL * 0.5, y + _CELL * 0.5)), preset)

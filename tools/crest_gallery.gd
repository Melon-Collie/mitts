extends SceneTree

# Dev visualizer: every team's chest crest (TeamCrest), large, on its home and
# away jersey color, in one PNG for judging the drawings. The on-garment scale
# is render-kits.sh.
#
#   xvfb-run -a godot --path . --rendering-driver opengl3 \
#       --rendering-method gl_compatibility -s res://tools/crest_gallery.gd
#
# CREST_GALLERY_OUT (default user://crest_gallery.png).

const _CELL: float = 160.0
const _CREST_R: float = 60.0
const _LABEL_W: float = 90.0
const _HEADER_H: float = 44.0
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
	_slots = TeamColorRegistry.get_all_slots()
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
	return Vector2(_LABEL_W + _CELL * _slots.size(), _HEADER_H + _CELL * 2.0)


func _draw_sheet() -> void:
	var c: Node2D = _canvas
	var font: Font = JerseyDecal.FONT
	c.draw_rect(Rect2(Vector2.ZERO, _size()), _BG)
	for side: int in 2:
		c.draw_string(font, Vector2(12.0, _HEADER_H + _CELL * (float(side) + 0.5) + 8.0),
				"HOME" if side == 0 else "AWAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, _INK)
	for col: int in _slots.size():
		var preset: Dictionary = TeamColorRegistry.get_preset(_slots[col])
		var x: float = _LABEL_W + _CELL * float(col)
		c.draw_string(font, Vector2(x, 30.0), String(preset.name).to_upper(),
				HORIZONTAL_ALIGNMENT_CENTER, _CELL, 20, _INK)
		var fruit: String = TeamCrest.fruit_for(preset)
		for side: int in 2:
			var kit: Dictionary = preset.home if side == 0 else preset.away
			var y: float = _HEADER_H + _CELL * float(side)
			c.draw_rect(Rect2(x + 2.0, y + 2.0, _CELL - 4.0, _CELL - 4.0), kit.jersey.base)
			if not fruit.is_empty():
				TeamCrest.draw(c, fruit, Transform2D(0.0, Vector2.ONE * _CREST_R, 0.0,
						Vector2(x + _CELL * 0.5, y + _CELL * 0.5)), preset)

class_name BoardPuckMarks
extends Node3D

# Black rubber scuffs on the dasher boards where pucks hit them.
#
# A paint canvas (a SubViewport that never clears) holds the board face unrolled
# by arc length (BoardArc) and height above the ice, and a ribbon over the
# kickplate and the white board multiplies it onto them: white is bare board, a
# mark darkens whatever is under it, yellow lip, white board or sponsor panel.
# The loop is folded into ROWS rows so the canvas stays under 8192 px wide.
#
# Marks come only from the authoritative board hit (GameManager.
# puck_marked_boards), and every roll a mark makes is seeded from that hit, so
# every peer paints the same scuff in the same place. A peer that joins late
# never sees the marks made before it arrived.
#
# The canvas redraws only on the frame a mark lands: nothing here runs per frame.

const PX_PER_M: float = 100.0
const ROWS: int = 2
# Ahead of the sponsor ribbon (HockeyRink.AD_BAND_INSET) and every painted stripe.
const RIBBON_INSET: float = 0.003

const RUBBER: Color = Color(0.06, 0.06, 0.07)
# Below this the puck kisses the boards without leaving anything.
const MARK_MIN_SPEED: float = 3.0
# Where the darkest, longest marks top out — a hard slapshot off the boards.
const MARK_FULL_SPEED: float = 25.0
const MARK_ALPHA_SOFT: float = 0.22
const MARK_ALPHA_HARD: float = 0.65
# A puck's face is ~7.6 cm across and 2.5 cm thick; it skids along the boards
# as it turns, so a mark runs from a puck's width to a short streak.
const MARK_MIN_LEN_M: float = 0.05
const MARK_STREAK_SOFT_M: float = 0.06
const MARK_STREAK_HARD_M: float = 0.35
# Most marks are close to level; a tumbling puck smears at an angle.
const MARK_MAX_TILT_RAD: float = 0.25
# The smudge soft-edges well past the rubber that touched.
const SMUDGE_SPREAD: float = 1.6

# The worn boards every match starts on. Fixed seed, so every peer starts from
# the same wear.
const BASELINE_SEED: int = 0x5C0FF
const BASELINE_MARKS: int = 260
const BASELINE_ALPHA_MIN: float = 0.06
const BASELINE_ALPHA_MAX: float = 0.3
# Share of the wear that falls on the side walls at centre ice, against the
# corners and end boards, where dump-ins and rims put most pucks.
const BASELINE_CENTRE_SHARE: float = 0.25

var _half_w: float = 0.0
var _half_l: float = 0.0
var _corner_r: float = 0.0
var _board_top: float = 0.0
var _perimeter: float = 0.0
var _row_len: float = 0.0
var _row_px: Vector2i = Vector2i.ZERO
var _px_per_m: Vector2 = Vector2.ZERO

var _viewport: SubViewport = null
var _painter: Node2D = null
var _material: StandardMaterial3D = null
var _blob: GradientTexture2D = null
# Pending draws, six floats each: centre x, centre y, length, height (px), tilt
# (rad), alpha.
var _pending: PackedFloat32Array = PackedFloat32Array()
var _wipe_pending: bool = false
var _torn_down: bool = false


# The ribbon for these marks: one face over the kickplate and one over the white
# board above it, in the frame HockeyRink builds its perimeter in. Each face is
# ROWS placements, one per canvas row.
static func build_ribbon(stations: Array, board_face: float, kick_face: float,
		kick_top: float, board_top: float) -> ArrayMesh:
	var cumulative: PackedFloat32Array = BoardAdBandBuilder.cumulative_arcs(stations)
	var row_len: float = BoardAdBandBuilder.perimeter_of(cumulative) / float(ROWS)
	var row_v: float = 1.0 / float(ROWS)
	var kick_v: float = row_v * (board_top - kick_top) / board_top
	var placements: Array[Vector2] = []
	var kick_cells: Array[Rect2] = []
	var board_cells: Array[Rect2] = []
	for row: int in ROWS:
		placements.append(Vector2(row_len * float(row), row_len))
		kick_cells.append(Rect2(0.0, row_v * float(row) + kick_v, 1.0, row_v - kick_v))
		board_cells.append(Rect2(0.0, row_v * float(row), 1.0, kick_v))
	var mesh: ArrayMesh = BoardAdBandBuilder.build_band(stations, cumulative, placements,
			kick_cells, kick_face + RIBBON_INSET, 0.0, kick_top)
	var board: ArrayMesh = BoardAdBandBuilder.build_band(stations, cumulative, placements,
			board_cells, board_face + RIBBON_INSET, kick_top, board_top)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, board.surface_get_arrays(0))
	return mesh


func setup(ribbon: ArrayMesh, half_w: float, half_l: float, corner_r: float,
		board_top: float) -> void:
	_half_w = half_w
	_half_l = half_l
	_corner_r = corner_r
	_board_top = board_top
	_perimeter = BoardArc.perimeter(half_w, half_l, corner_r)
	_row_len = _perimeter / float(ROWS)
	_row_px = Vector2i(ceili(_row_len * PX_PER_M), ceili(board_top * PX_PER_M))
	_px_per_m = Vector2(float(_row_px.x) / _row_len, float(_row_px.y) / board_top)

	_viewport = SubViewport.new()
	_viewport.name = "BoardPuckMarksCanvas"
	_viewport.size = Vector2i(_row_px.x, _row_px.y * ROWS)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_painter = Node2D.new()
	_painter.draw.connect(_on_painter_draw)
	_viewport.add_child(_painter)

	_blob = GradientTexture2D.new()
	_blob.width = 32
	_blob.height = 32
	_blob.fill = GradientTexture2D.FILL_RADIAL
	_blob.fill_from = Vector2(0.5, 0.5)
	_blob.fill_to = Vector2(1.0, 0.5)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_blob.gradient = ramp

	_material = StandardMaterial3D.new()
	_material.albedo_texture = _viewport.get_texture()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# After the sponsor panels and the painted stripes (1), so it marks them too.
	_material.render_priority = 2
	var mi := MeshInstance3D.new()
	mi.name = "BoardPuckMarks"
	mi.mesh = ribbon
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	reset()


# Back to the worn boards a match starts on.
func reset() -> void:
	if _viewport == null:
		return
	_pending.clear()
	_wipe_pending = true
	var rng := RandomNumberGenerator.new()
	rng.seed = BASELINE_SEED
	var placed: int = 0
	while placed < BASELINE_MARKS:
		var s: float = rng.randf() * _perimeter
		var at: Vector2 = BoardArc.point_at(s, _half_w, _half_l, _corner_r)
		var depth: float = absf(at.y) / _half_l
		if rng.randf() > lerpf(BASELINE_CENTRE_SHARE, 1.0, depth * depth):
			continue
		# Mostly at ice height; a few lifted pucks higher up the board.
		var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT \
				+ pow(rng.randf(), 5.0) * (_board_top - 0.1)
		var t: float = rng.randf()
		_queue_mark(s, y, t, lerpf(BASELINE_ALPHA_MIN, BASELINE_ALPHA_MAX, rng.randf()), rng)
		placed += 1
	_request_paint()


# A puck hit the boards at `local_pos` (this node's frame) at `speed` m/s.
func add_mark(local_pos: Vector3, speed: float) -> void:
	if _viewport == null or speed < MARK_MIN_SPEED:
		return
	var s: float = BoardArc.arc_at(Vector2(local_pos.x, local_pos.z), _half_w, _half_l, _corner_r)
	var t: float = clampf(inverse_lerp(MARK_MIN_SPEED, MARK_FULL_SPEED, speed), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(roundi(s * 1000.0), roundi(local_pos.y * 1000.0),
			roundi(speed * 100.0)))
	_queue_mark(s, clampf(local_pos.y, 0.0, _board_top), t,
			lerpf(MARK_ALPHA_SOFT, MARK_ALPHA_HARD, t), rng)
	_request_paint()


# Releases the canvas before the RenderingServer finalizes (HockeyRink calls
# this from its own teardown; _exit_tree covers being freed on its own).
func teardown() -> void:
	if _torn_down:
		return
	_torn_down = true
	if _material != null:
		_material.albedo_texture = null
	if is_instance_valid(_viewport):
		_viewport.free()
	_viewport = null
	_painter = null


func _exit_tree() -> void:
	teardown()


# `t` is how hard (0..1), and stretches the streak.
func _queue_mark(s: float, y: float, t: float, alpha: float,
		rng: RandomNumberGenerator) -> void:
	var streak: float = lerpf(MARK_STREAK_SOFT_M, MARK_STREAK_HARD_M, t) * pow(rng.randf(), 2.0)
	var length: float = (MARK_MIN_LEN_M + streak) * _px_per_m.x
	var height: float = GameRules.PUCK_COLLISION_HALF_HEIGHT * 2.0 \
			* rng.randf_range(0.8, 1.3) * _px_per_m.y
	var tilt: float = rng.randf_range(-MARK_MAX_TILT_RAD, MARK_MAX_TILT_RAD) * rng.randf()
	var at: Vector2 = _canvas_point(s, y)
	var row: int = int(at.y) / _row_px.y
	var x: float = at.x
	var v: float = at.y - float(row * _row_px.y)
	_push(x, at.y, length, height, tilt, alpha)
	# A mark across a fold of the loop is drawn into both rows it touches.
	var reach: float = length * SMUDGE_SPREAD * 0.5
	if x < reach:
		var prev: int = (row + ROWS - 1) % ROWS
		_push(x + float(_row_px.x), float(prev * _row_px.y) + v, length, height, tilt, alpha)
	if x > float(_row_px.x) - reach:
		var next: int = (row + 1) % ROWS
		_push(x - float(_row_px.x), float(next * _row_px.y) + v, length, height, tilt, alpha)


# The canvas pixel for arc `s` at height `y` on the boards. The ribbon's UVs
# (build_ribbon) read the canvas the same way.
func _canvas_point(s: float, y: float) -> Vector2:
	var row: int = mini(int(s / _row_len), ROWS - 1)
	return Vector2((s - _row_len * float(row)) * _px_per_m.x,
			float(row * _row_px.y) + (_board_top - y) * _px_per_m.y)


func _push(x: float, y: float, length: float, height: float, tilt: float,
		alpha: float) -> void:
	_pending.append_array(PackedFloat32Array([x, y, length, height, tilt, alpha]))


func _request_paint() -> void:
	_painter.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_painter_draw() -> void:
	# The canvas never clears, so a wipe is painting it white.
	if _wipe_pending:
		_painter.draw_rect(Rect2(Vector2.ZERO, Vector2(_viewport.size)), Color.WHITE)
		_wipe_pending = false
	for i: int in range(0, _pending.size(), 6):
		var size := Vector2(_pending[i + 2], _pending[i + 3]) * SMUDGE_SPREAD
		var ink := Color(RUBBER, _pending[i + 5])
		_painter.draw_set_transform(Vector2(_pending[i], _pending[i + 1]), _pending[i + 4])
		_painter.draw_texture_rect(_blob, Rect2(-size * 0.5, size), false, ink)
		# A darker core where the rubber actually touched.
		_painter.draw_texture_rect(_blob, Rect2(-size * 0.25, size * 0.5), false, ink)
	_painter.draw_set_transform(Vector2.ZERO)
	_pending.clear()

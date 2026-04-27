class_name OffScreenPlayerIndicators
extends Control

const _ARROW_BASE_SIZE: float = 36.0
const _ARROW_MIN_SCALE: float = 0.45
const _ARROW_MAX_SCALE: float = 1.0
const _NEAR_DISTANCE: float = 6.0
const _FAR_DISTANCE: float = 30.0
const _EDGE_MARGIN: float = 28.0
const _OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)
const _OUTLINE_WIDTH: float = 2.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var local_record: PlayerRecord = GameManager.get_local_player()
	if local_record == null or local_record.skater == null:
		return
	var rect_size: Vector2 = size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return
	var local_pos: Vector3 = local_record.skater.global_position
	var center: Vector2 = rect_size * 0.5
	var inner: Rect2 = Rect2(
		Vector2(_EDGE_MARGIN, _EDGE_MARGIN),
		rect_size - Vector2(_EDGE_MARGIN * 2.0, _EDGE_MARGIN * 2.0))
	var screen_rect: Rect2 = Rect2(Vector2.ZERO, rect_size)

	var players: Dictionary[int, PlayerRecord] = GameManager.get_players()
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		if record == null or record.is_local or record.skater == null or record.team == null:
			continue
		var world_pos: Vector3 = record.skater.global_position
		var behind: bool = camera.is_position_behind(world_pos)
		var raw: Vector2 = camera.unproject_position(world_pos)
		if not behind and screen_rect.has_point(raw):
			continue
		var dir: Vector2
		if behind:
			# unproject_position returns the wrong-side point when behind the camera; mirror it.
			dir = (center - raw).normalized()
		else:
			dir = (raw - center).normalized()
		if dir == Vector2.ZERO or not (is_finite(dir.x) and is_finite(dir.y)):
			continue
		var edge_pos: Vector2 = _intersect_rect_from_center(center, dir, inner)
		var dist: float = local_pos.distance_to(world_pos)
		var t: float = clampf(inverse_lerp(_NEAR_DISTANCE, _FAR_DISTANCE, dist), 0.0, 1.0)
		var arrow_scale: float = lerpf(_ARROW_MAX_SCALE, _ARROW_MIN_SCALE, t)
		var color: Color = PlayerRules.slot_color(record.team.team_id, record.team_slot)
		_draw_arrow(edge_pos, dir, arrow_scale, color)

func _draw_arrow(pos: Vector2, dir: Vector2, arrow_scale: float, color: Color) -> void:
	var sz: float = _ARROW_BASE_SIZE * arrow_scale
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = pos + dir * (sz * 0.55)
	var base_left: Vector2 = pos - dir * (sz * 0.45) + perp * (sz * 0.40)
	var base_right: Vector2 = pos - dir * (sz * 0.45) - perp * (sz * 0.40)
	var fill: PackedVector2Array = PackedVector2Array([tip, base_left, base_right])
	var fill_colors: PackedColorArray = PackedColorArray([color, color, color])
	draw_polygon(fill, fill_colors)
	var outline: PackedVector2Array = PackedVector2Array([tip, base_left, base_right, tip])
	draw_polyline(outline, _OUTLINE_COLOR, _OUTLINE_WIDTH, true)

func _intersect_rect_from_center(c: Vector2, dir: Vector2, r: Rect2) -> Vector2:
	var t_x: float = INF
	var t_y: float = INF
	if dir.x > 0.0001:
		t_x = (r.position.x + r.size.x - c.x) / dir.x
	elif dir.x < -0.0001:
		t_x = (r.position.x - c.x) / dir.x
	if dir.y > 0.0001:
		t_y = (r.position.y + r.size.y - c.y) / dir.y
	elif dir.y < -0.0001:
		t_y = (r.position.y - c.y) / dir.y
	return c + dir * minf(t_x, t_y)

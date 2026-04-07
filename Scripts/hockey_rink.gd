@tool
class_name HockeyRink
extends StaticBody3D

@export var rink_length: float = 60.0:
	set(v):
		rink_length = v
		_rebuild()
@export var rink_width: float = 26.0:
	set(v):
		rink_width = v
		_rebuild()
@export var corner_radius: float = 8.5:
	set(v):
		corner_radius = v
		_rebuild()
@export var wall_height: float = 1.0:
	set(v):
		wall_height = v
		_rebuild()
@export var wall_thickness: float = 0.3:
	set(v):
		wall_thickness = v
		_rebuild()
@export var corner_segments: int = 8:
	set(v):
		corner_segments = v
		_rebuild()
@export var wall_color: Color = Color(0.2, 0.2, 0.8):
	set(v):
		wall_color = v
		_rebuild()
@export var ice_color: Color = Color(0.9, 0.95, 1.0):
	set(v):
		ice_color = v
		_rebuild()
@export var red_line_color: Color = Color(0.8, 0.1, 0.1):
	set(v):
		red_line_color = v
		_rebuild()
@export var blue_line_color: Color = Color(0.1, 0.1, 0.8):
	set(v):
		blue_line_color = v
		_rebuild()
@export var ice_friction: float = 0.05:
	set(v):
		ice_friction = v
		_rebuild()
@export var rebuild: bool = false:
	set(v):
		_rebuild()

# Texture resolution: pixels per meter
var _px_per_meter: float = 20.0

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if rink_length <= 0 or rink_width <= 0:
		return
	
	for child in get_children():
		child.queue_free()
	
	var half_l = rink_length / 2.0
	var half_w = rink_width / 2.0
	var r = corner_radius
	
	# --- Ice surface ---
	_add_ice(half_l)
	
	# --- Walls ---
	_add_wall(
		Vector3(half_w, wall_height / 2.0, 0),
		Vector3(wall_thickness, wall_height, rink_length - 2.0 * r)
	)
	_add_wall(
		Vector3(-half_w, wall_height / 2.0, 0),
		Vector3(wall_thickness, wall_height, rink_length - 2.0 * r)
	)
	_add_wall(
		Vector3(0, wall_height / 2.0, -half_l),
		Vector3(rink_width - 2.0 * r, wall_height, wall_thickness)
	)
	_add_wall(
		Vector3(0, wall_height / 2.0, half_l),
		Vector3(rink_width - 2.0 * r, wall_height, wall_thickness)
	)
	
	_add_corner(Vector3(half_w - r, 0, -half_l + r), -PI / 2.0, 0.0)
	_add_corner(Vector3(half_w - r, 0, half_l - r), 0.0, PI / 2.0)
	_add_corner(Vector3(-half_w + r, 0, half_l - r), PI / 2.0, PI)
	_add_corner(Vector3(-half_w + r, 0, -half_l + r), PI, 3.0 * PI / 2.0)

func _add_ice(half_l: float) -> void:
	var img_w = int(rink_width * _px_per_meter)
	var img_h = int(rink_length * _px_per_meter)
	
	var img = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(ice_color)
	
	# Line widths in pixels
	var thick_line = int(0.3 * _px_per_meter)  # 30cm for center/blue lines
	var thin_line = int(0.15 * _px_per_meter)   # 15cm for goal lines, circles  # 5cm for goal lines, circles
	thin_line = max(thin_line, 1)
	
	# Helper: image coordinates
	# X axis (rink width) = image X
	# Z axis (rink length) = image Y
	# Center of rink = center of image
	
	# Center red line (at Z=0)
	_draw_h_line(img, img_h / 2.0, thick_line, red_line_color)
	
	# Blue lines (NHL: 7.62m from center, which is 25ft)
	var blue_z = int(7.62 * _px_per_meter)
	_draw_h_line(img, img_h / 2.0 - blue_z, thick_line, blue_line_color)
	_draw_h_line(img, img_h / 2.0 + blue_z, thick_line, blue_line_color)
	
	# Goal lines (3.4m from end boards)
	var goal_z = int((half_l - 3.4) * _px_per_meter)
	_draw_h_line(img, img_h / 2.0 - goal_z, thin_line, red_line_color)
	_draw_h_line(img, img_h / 2.0 + goal_z, thin_line, red_line_color)
	
	# Center ice circle (radius 4.5m)
	_draw_circle(img, img_w / 2.0, img_h / 2.0, int(4.5 * _px_per_meter), thin_line, blue_line_color)
	
	# Center ice dot
	_draw_filled_circle(img, img_w / 2.0, img_h / 2.0, int(0.15 * _px_per_meter), blue_line_color)
	
	# Faceoff dots and circles in end zones
	# NHL: dots are 6.1m from goal line, 6.7m from center of rink (width)
	var dot_offset_z = int(6.1 * _px_per_meter)
	var dot_offset_x = int(6.7 * _px_per_meter)
	var dot_radius = int(0.15 * _px_per_meter)
	var circle_radius = int(4.5 * _px_per_meter)
	
	# End zone faceoff spots (4 total, 2 per end)
	var end_zone_dots = [
		[img_w / 2.0 - dot_offset_x, img_h / 2.0 - goal_z + dot_offset_z],
		[img_w / 2.0 + dot_offset_x, img_h / 2.0 - goal_z + dot_offset_z],
		[img_w / 2.0 - dot_offset_x, img_h / 2.0 + goal_z - dot_offset_z],
		[img_w / 2.0 + dot_offset_x, img_h / 2.0 + goal_z - dot_offset_z],
	]
	
	for dot in end_zone_dots:
		_draw_filled_circle(img, dot[0], dot[1], dot_radius, red_line_color)
		_draw_circle(img, dot[0], dot[1], circle_radius, thin_line, red_line_color)
	
	# Neutral zone faceoff dots (4 total)
	# NHL: just inside blue lines, same X offset
	var neutral_dots = [
		[img_w / 2.0 - dot_offset_x, img_h / 2.0 - blue_z + int(1.5 * _px_per_meter)],
		[img_w / 2.0 + dot_offset_x, img_h / 2.0 - blue_z + int(1.5 * _px_per_meter)],
		[img_w / 2.0 - dot_offset_x, img_h / 2.0 + blue_z - int(1.5 * _px_per_meter)],
		[img_w / 2.0 + dot_offset_x, img_h / 2.0 + blue_z - int(1.5 * _px_per_meter)],
	]
	
	for dot in neutral_dots:
		_draw_filled_circle(img, dot[0], dot[1], dot_radius, red_line_color)
	
	# Create texture
	var tex = ImageTexture.create_from_image(img)
	
	# Ice mesh
	var mesh_instance = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(rink_width, rink_length)
	mesh_instance.mesh = plane
	mesh_instance.position = Vector3(0, 0, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	
	# Ice collision with its own physics material
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(rink_width, 0.01, rink_length)
	col.shape = shape
	col.position = Vector3(0, -0.005, 0)
	add_child(col)
	
	var phys_mat = PhysicsMaterial.new()
	phys_mat.friction = ice_friction
	phys_mat.bounce = 0.0
	col.set_meta("physics_material_override", phys_mat)

func _draw_h_line(img: Image, y: int, thickness: int, color: Color) -> void:
	var half_t = thickness / 2.0
	for py in range(y - half_t, y + half_t + 1):
		if py >= 0 and py < img.get_height():
			for px in range(img.get_width()):
				img.set_pixel(px, py, color)

func _draw_circle(img: Image, cx: int, cy: int, radius: int, thickness: int, color: Color) -> void:
	var r_outer = radius + thickness / 2.0
	var r_inner = radius - thickness / 2.0
	for py in range(cy - r_outer - 1, cy + r_outer + 2):
		for px in range(cx - r_outer - 1, cx + r_outer + 2):
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				var dist = sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
				if dist >= r_inner and dist <= r_outer:
					img.set_pixel(px, py, color)

func _draw_filled_circle(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	for py in range(cy - radius, cy + radius + 1):
		for px in range(cx - radius, cx + radius + 1):
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				var dist = sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
				if dist <= radius:
					img.set_pixel(px, py, color)

func _add_wall(pos: Vector3, size: Vector3) -> void:
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	var mat = StandardMaterial3D.new()
	mat.albedo_color = wall_color
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	add_child(col)

func _add_corner(center: Vector3, angle_start: float, angle_end: float) -> void:
	var angle_step = (angle_end - angle_start) / corner_segments
	for i in corner_segments:
		var a1 = angle_start + i * angle_step
		var a2 = angle_start + (i + 1) * angle_step
		
		var p1 = center + Vector3(cos(a1) * corner_radius, 0, sin(a1) * corner_radius)
		var p2 = center + Vector3(cos(a2) * corner_radius, 0, sin(a2) * corner_radius)
		
		var mid = (p1 + p2) / 2.0
		mid.y = wall_height / 2.0
		
		var seg_length = p1.distance_to(p2)
		
		var dir = (p2 - p1).normalized()
		var rot_y = atan2(dir.x, dir.z)
		
		var mesh_instance = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(wall_thickness, wall_height, seg_length)
		mesh_instance.mesh = box
		mesh_instance.position = mid
		mesh_instance.rotation.y = rot_y
		var mat = StandardMaterial3D.new()
		mat.albedo_color = wall_color
		mesh_instance.material_override = mat
		add_child(mesh_instance)
		
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(wall_thickness, wall_height, seg_length)
		col.shape = shape
		col.position = mid
		col.rotation.y = rot_y
		add_child(col)

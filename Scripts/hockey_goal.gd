@tool
class_name HockeyGoal
extends StaticBody3D

signal goal_scored

# NHL regulation Art Ross net. Spec coordinate system:
#   X = left/right (positive = right facing net)
#   Vector2.y = depth into net (used as world Z offset from goal line)
#   Y = up (constant per curve: 0 for base, NET_HEIGHT for top shelf)

# Base curve control points (right half, mirrored for left).
# Flares wider than the posts — P2.x > P0.x.
const BASE_P0 := Vector2(0.915, 0.0)
const BASE_P1 := Vector2(0.915, 0.46)
const BASE_P2 := Vector2(1.12,  0.92)
const BASE_P3 := Vector2(0.0,   1.02)

# Top shelf control points (right half, mirrored for left).
# Pulls inward — P2.x < P0.x. Perfectly flat in Y at crossbar height.
const TOP_P0 := Vector2(0.915, 0.0)
const TOP_P1 := Vector2(0.915, 0.28)
const TOP_P2 := Vector2(0.60,  0.52)
const TOP_P3 := Vector2(0.0,   0.56)

const POST_HALF_WIDTH: float = 0.915  # half of 1.83m opening
const NET_HEIGHT: float = 1.22        # 48 inches
const POST_RADIUS: float = 0.03       # 2 3/8" OD = ~0.06m diameter
const SEGMENTS: int = 16              # per half-curve; 33 total points (2*SEGMENTS + 1)

# +1 for positive-Z end (Team 0 defends), -1 for negative-Z end (Team 1 defends)
@export var facing: int = 1:
	set(v):
		facing = v
		_rebuild()
@export var distance_from_end: float = 3.4:
	set(v):
		distance_from_end = v
		_rebuild()
@export var rink_length: float = 60.0:
	set(v):
		rink_length = v
		_rebuild()
@export var post_color: Color = Color(0.9, 0.1, 0.1):
	set(v):
		post_color = v
		_rebuild()
@export var base_frame_color: Color = Color(0.95, 0.95, 0.95):
	set(v):
		base_frame_color = v
		_rebuild()
@export var net_color: Color = Color(1.0, 1.0, 1.0, 0.3):
	set(v):
		net_color = v
		_rebuild()
@export var rebuild: bool = false:
	set(v):
		_rebuild()

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var base_pts := _get_curve_points(BASE_P0, BASE_P1, BASE_P2, BASE_P3)
	var top_pts  := _get_curve_points(TOP_P0,  TOP_P1,  TOP_P2,  TOP_P3)
	var goal_z: float = facing * (rink_length / 2.0 - distance_from_end)

	_build_goal(goal_z, facing, base_pts, top_pts)
	_build_goal_sensor(goal_z)

func _build_goal(
	goal_z: float,
	facing: float,
	base_pts: PackedVector2Array,
	top_pts: PackedVector2Array
) -> void:
	var tube_dia: float = POST_RADIUS * 2.0

	# Posts (vertical cylinders)
	for post_x: float in [-POST_HALF_WIDTH, POST_HALF_WIDTH]:
		var cyl := CylinderMesh.new()
		cyl.height = NET_HEIGHT
		cyl.top_radius = POST_RADIUS
		cyl.bottom_radius = POST_RADIUS
		cyl.radial_segments = 8
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = cyl
		mesh_inst.position = Vector3(post_x, NET_HEIGHT / 2.0, goal_z)
		_apply_mat(mesh_inst, post_color)
		add_child(mesh_inst)

		var post_shape := CylinderShape3D.new()
		post_shape.height = NET_HEIGHT
		post_shape.radius = POST_RADIUS
		var post_col := CollisionShape3D.new()
		post_col.shape = post_shape
		post_col.position = Vector3(post_x, NET_HEIGHT / 2.0, goal_z)
		add_child(post_col)

	# Crossbar (horizontal cylinder along X)
	var cross_cyl := CylinderMesh.new()
	cross_cyl.height = POST_HALF_WIDTH * 2.0
	cross_cyl.top_radius = POST_RADIUS
	cross_cyl.bottom_radius = POST_RADIUS
	cross_cyl.radial_segments = 8
	var cross_mesh := MeshInstance3D.new()
	cross_mesh.mesh = cross_cyl
	cross_mesh.position = Vector3(0.0, NET_HEIGHT, goal_z)
	cross_mesh.rotation.z = PI / 2.0
	_apply_mat(cross_mesh, post_color)
	add_child(cross_mesh)

	var cross_shape := CylinderShape3D.new()
	cross_shape.height = POST_HALF_WIDTH * 2.0
	cross_shape.radius = POST_RADIUS
	var cross_col := CollisionShape3D.new()
	cross_col.shape = cross_shape
	cross_col.position = Vector3(0.0, NET_HEIGHT, goal_z)
	cross_col.rotation.z = PI / 2.0
	add_child(cross_col)

	# Curve tube segments.
	# Segment SEGMENTS-1 (index 15 for SEGMENTS=16) spans from near-left-post to
	# right-post — that is the front opening. Skip it for both curves.
	for i in range(2 * SEGMENTS):
		if i == SEGMENTS - 1:
			continue

		# Base curve (white, at Y = 0)
		_add_tube_segment(
			Vector3(base_pts[i].x,     0.0, goal_z + facing * base_pts[i].y),
			Vector3(base_pts[i + 1].x, 0.0, goal_z + facing * base_pts[i + 1].y),
			tube_dia, base_frame_color
		)

		# Top shelf (red, at Y = NET_HEIGHT)
		_add_tube_segment(
			Vector3(top_pts[i].x,     NET_HEIGHT, goal_z + facing * top_pts[i].y),
			Vector3(top_pts[i + 1].x, NET_HEIGHT, goal_z + facing * top_pts[i + 1].y),
			tube_dia, post_color
		)

	# Netting — ruled surface between the two curves
	_build_netting(base_pts, top_pts, goal_z, facing)

func _build_netting(
	base_pts: PackedVector2Array,
	top_pts: PackedVector2Array,
	goal_z: float,
	facing: float
) -> void:
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var indices := PackedInt32Array()

	for i in range(2 * SEGMENTS):
		if i == SEGMENTS - 1:  # skip front opening
			continue

		var bl := Vector3(base_pts[i].x,     0.0,        goal_z + facing * base_pts[i].y)
		var br := Vector3(base_pts[i + 1].x, 0.0,        goal_z + facing * base_pts[i + 1].y)
		var tl := Vector3(top_pts[i].x,      NET_HEIGHT, goal_z + facing * top_pts[i].y)
		var tr := Vector3(top_pts[i + 1].x,  NET_HEIGHT, goal_z + facing * top_pts[i + 1].y)

		var normal := (br - bl).cross(tl - bl).normalized()
		var base_idx: int = verts.size()
		verts.append_array([bl, br, tr, tl])
		normals.append_array([normal, normal, normal, normal])
		uvs.append_array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
		indices.append_array([
			base_idx, base_idx + 1, base_idx + 2,
			base_idx, base_idx + 2, base_idx + 3,
		])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]  = verts
	arrays[Mesh.ARRAY_NORMAL]  = normals
	arrays[Mesh.ARRAY_TEX_UV]  = uvs
	arrays[Mesh.ARRAY_INDEX]   = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = net_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	# ConcavePolygonShape3D from the same triangles — accurate puck collision
	var faces := PackedVector3Array()
	for j in range(0, indices.size(), 3):
		faces.append(verts[indices[j]])
		faces.append(verts[indices[j + 1]])
		faces.append(verts[indices[j + 2]])
	var net_shape := ConcavePolygonShape3D.new()
	net_shape.set_faces(faces)
	net_shape.backface_collision = true
	var net_col := CollisionShape3D.new()
	net_col.shape = net_shape
	add_child(net_col)

func _build_goal_sensor(goal_z: float) -> void:
	var area := Area3D.new()
	# Collision layer 0: this area doesn't need to be detected by others.
	# Collision mask 8 (layer 4): matches the detection layer set on Puck in _ready().
	area.collision_layer = 0
	area.collision_mask = 8
	area.monitoring = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Spans the full goal opening; shallow depth so it sits just inside the mouth.
	box.size = Vector3(POST_HALF_WIDTH * 2.0, NET_HEIGHT, 0.3)
	shape.shape = box
	area.add_child(shape)
	# Centered vertically on the opening, offset half the box depth behind the goal line.
	area.position = Vector3(0.0, NET_HEIGHT / 2.0, goal_z + facing * 0.15)
	add_child(area)
	area.body_entered.connect(_on_goal_area_body_entered)

func _on_goal_area_body_entered(body: Node3D) -> void:
	if body is Puck:
		goal_scored.emit()

func _add_tube_segment(p_start: Vector3, p_end: Vector3, diameter: float, color: Color) -> void:
	var seg := p_end - p_start
	var seg_len := seg.length()
	if seg_len < 0.001:
		return
	var mid := (p_start + p_end) / 2.0
	var rot_y := atan2(seg.x, seg.z)
	var size := Vector3(diameter, diameter, seg_len)

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.position = mid
	mesh_inst.rotation.y = rot_y
	_apply_mat(mesh_inst, color)
	add_child(mesh_inst)

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = mid
	col.rotation.y = rot_y
	add_child(col)

func _apply_mat(mesh_inst: MeshInstance3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat

func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3

func _get_curve_points(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> PackedVector2Array:
	# Sample the right half (post → center back), then mirror to build the full curve:
	# left half (center back → near left post) + right half (right post → center back).
	# Total: 2*SEGMENTS + 1 points. Segment SEGMENTS-1 spans the front opening.
	var right_half: Array[Vector2] = []
	for i in range(SEGMENTS + 1):
		right_half.append(_cubic_bezier(p0, p1, p2, p3, float(i) / float(SEGMENTS)))

	var points := PackedVector2Array()
	for i in range(SEGMENTS, 0, -1):  # reverse right half, negate X — skip i=0 (would dupe center)
		points.append(Vector2(-right_half[i].x, right_half[i].y))
	for pt: Vector2 in right_half:
		points.append(pt)
	return points

@tool
class_name HockeyGoal
extends StaticBody3D

signal goal_scored

var vfx: GoalVFX = null

# Trapezoidal prism net. Viewed from above the net widens from the front
# opening (POST_HALF_WIDTH each side) to the back (NET_BACK_HW each side).
# All values in metres. Must stay in sync with GameRules net constants.

const POST_HALF_WIDTH: float = 0.915  # half of 1.83 m opening — matches GameRules.NET_HALF_WIDTH
const NET_BACK_HW: float     = 1.02   # half-width at back — matches GameRules.NET_BACK_HALF_WIDTH
const NET_HEIGHT: float      = 1.22   # 48 inches
const NET_DEPTH: float       = 1.02   # goal line to back frame — matches GameRules.NET_DEPTH
const POST_RADIUS: float     = 0.03   # 2 3/8" OD = ~0.06 m diameter
const PANEL_THICKNESS: float = 0.04   # visual frame tube / wall thickness

var defending_team_id: int = -1  # set by GameManager when goals are assigned to teams

# +1 for positive-Z end (Team 0 defends), -1 for negative-Z end (Team 1 defends)
@export var facing: int = 1:
	set(v):
		facing = v
		_rebuild()
@export var distance_from_end: float = 3.35:
	set(v):
		distance_from_end = v
		_rebuild()
@export var rink_length: float = 60.0:
	set(v):
		rink_length = v
		_rebuild()
@export var post_color: Color = Color(0.784, 0.063, 0.180):
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

	var goal_z: float = facing * (rink_length / 2.0 - distance_from_end)
	_build_goal(goal_z)
	_build_goal_sensor(goal_z)

	var goal_vfx := GoalVFX.new()
	goal_vfx.name = "GoalVFX"
	goal_vfx.position = Vector3(0.0, NET_HEIGHT / 2.0, goal_z)
	add_child(goal_vfx)
	vfx = goal_vfx

func _build_goal(goal_z: float) -> void:
	# Posts (vertical cylinders at the front opening)
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

	_build_trap_net(goal_z)

func _build_trap_net(goal_z: float) -> void:
	# Side panels: each runs from (±POST_HALF_WIDTH, goal_z) to (±NET_BACK_HW, goal_z + facing*NET_DEPTH).
	# The panel is a thin box rotated to match the flare angle.
	var flare: float = NET_BACK_HW - POST_HALF_WIDTH  # 0.105 m each side
	var panel_len: float = sqrt(flare * flare + NET_DEPTH * NET_DEPTH)
	# Angle from the depth axis (world Z) toward the outside — positive for right side.
	var flare_angle: float = atan2(flare, NET_DEPTH)

	for side: float in [-1.0, 1.0]:
		var mid_x: float = side * (POST_HALF_WIDTH + NET_BACK_HW) / 2.0
		var mid_z: float = goal_z + facing * NET_DEPTH / 2.0

		# Visual mesh
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(PANEL_THICKNESS, NET_HEIGHT, panel_len)
		var side_mesh := MeshInstance3D.new()
		side_mesh.mesh = box_mesh
		side_mesh.position = Vector3(mid_x, NET_HEIGHT / 2.0, mid_z)
		side_mesh.rotation.y = facing * side * -flare_angle
		_apply_mat_net(side_mesh)
		add_child(side_mesh)

		# Collision
		var side_shape := BoxShape3D.new()
		side_shape.size = Vector3(PANEL_THICKNESS, NET_HEIGHT, panel_len)
		var side_col := CollisionShape3D.new()
		side_col.shape = side_shape
		side_col.position = Vector3(mid_x, NET_HEIGHT / 2.0, mid_z)
		side_col.rotation.y = facing * side * -flare_angle
		add_child(side_col)

		# Base bar along ice for each side (visual only, thin rod at Y=0)
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(PANEL_THICKNESS, PANEL_THICKNESS, panel_len)
		var bar_inst := MeshInstance3D.new()
		bar_inst.mesh = bar_mesh
		bar_inst.position = Vector3(mid_x, 0.0, mid_z)
		bar_inst.rotation.y = facing * side * -flare_angle
		_apply_mat(bar_inst, base_frame_color)
		add_child(bar_inst)

	# Back wall (solid, full width at NET_BACK_HW)
	var back_z: float = goal_z + facing * NET_DEPTH
	var back_wall := BoxShape3D.new()
	back_wall.size = Vector3(NET_BACK_HW * 2.0 + PANEL_THICKNESS, NET_HEIGHT + PANEL_THICKNESS, PANEL_THICKNESS)
	var back_col := CollisionShape3D.new()
	back_col.shape = back_wall
	back_col.position = Vector3(0.0, NET_HEIGHT / 2.0, back_z)
	add_child(back_col)

	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(NET_BACK_HW * 2.0 + PANEL_THICKNESS, NET_HEIGHT, PANEL_THICKNESS)
	var back_inst := MeshInstance3D.new()
	back_inst.mesh = back_mesh
	back_inst.position = Vector3(0.0, NET_HEIGHT / 2.0, back_z)
	_apply_mat_net(back_inst)
	add_child(back_inst)

	# Top / ceiling panel (flat box at NET_HEIGHT, trapezoidal footprint approximated as box)
	var top_shape := BoxShape3D.new()
	top_shape.size = Vector3(NET_BACK_HW * 2.0, PANEL_THICKNESS, NET_DEPTH)
	var top_col := CollisionShape3D.new()
	top_col.shape = top_shape
	top_col.position = Vector3(0.0, NET_HEIGHT, goal_z + facing * NET_DEPTH / 2.0)
	add_child(top_col)

	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(NET_BACK_HW * 2.0, PANEL_THICKNESS, NET_DEPTH)
	var top_inst := MeshInstance3D.new()
	top_inst.mesh = top_mesh
	top_inst.position = Vector3(0.0, NET_HEIGHT, goal_z + facing * NET_DEPTH / 2.0)
	_apply_mat_net(top_inst)
	add_child(top_inst)

func _build_goal_sensor(goal_z: float) -> void:
	var area := Area3D.new()
	# Collision layer 0: this area doesn't need to be detected by others.
	# Collision mask 8 (layer 4): matches the detection layer set on Puck in _ready().
	area.collision_layer = 0
	area.collision_mask = 8
	area.monitoring = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Fill the full interior so any puck that enters through the front opening is caught,
	# even on steep-angle shots. Side/back walls are solid so entry is always through the front.
	var inner_hw: float = POST_HALF_WIDTH - POST_RADIUS
	var inner_height: float = NET_HEIGHT - POST_RADIUS
	var sensor_depth: float = NET_DEPTH - POST_RADIUS
	box.size = Vector3(inner_hw * 2.0, inner_height, sensor_depth)
	shape.shape = box
	area.add_child(shape)
	area.position = Vector3(0.0, inner_height / 2.0, goal_z + facing * (sensor_depth / 2.0))
	add_child(area)
	area.body_entered.connect(_on_goal_area_body_entered)

func _on_goal_area_body_entered(body: Node3D) -> void:
	if body is Puck:
		# Puck must be travelling into the net (positive Z component for +Z goal,
		# negative for -Z goal). Rejects lateral carries and behind-net entry.
		var vel: Vector3 = (body as Puck).linear_velocity
		if vel.z * float(facing) > 0.0:
			goal_scored.emit()

func _apply_mat(mesh_inst: MeshInstance3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat

func _apply_mat_net(mesh_inst: MeshInstance3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = net_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat

class_name Skater
extends CharacterBody3D

# ── Character ─────────────────────────────────────────────────────────────────
@export var is_left_handed: bool = true

# ── Blade Tuning ──────────────────────────────────────────────────────────────
@export var blade_height: float = 0.0
@export var plane_reach: float = 1.5
@export var shoulder_offset: float = 0.35
@export var wall_squeeze_threshold: float = 0.3

# ── Node References ───────────────────────────────────────────────────────────
@onready var lower_body: Node3D = $LowerBody
@onready var upper_body: Node3D = $UpperBody
@onready var blade: Marker3D = $UpperBody/Blade
@onready var shoulder: Marker3D = $UpperBody/Shoulder
@onready var stick_raycast: RayCast3D = $StickRaycast
@onready var stick_mesh: MeshInstance3D = $UpperBody/StickMesh

# ── Runtime ───────────────────────────────────────────────────────────────────
var _facing: Vector2 = Vector2.DOWN

func _ready() -> void:
	var hand_sign: float = -1.0 if is_left_handed else 1.0
	shoulder.position = Vector3(hand_sign * shoulder_offset, 0.0, 0.0)
	
	var blade_area = Area3D.new()
	blade_area.name = "BladeArea"
	blade_area.collision_layer = 2
	blade_area.collision_mask = 0
	var blade_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.3
	blade_shape.shape = sphere
	blade_area.add_child(blade_shape)
	blade.add_child(blade_area)
	
	shoulder.position = Vector3(hand_sign * shoulder_offset, 0.0, 0.0)
	blade_area.position = Vector3(0, -1.0, 0)

func _physics_process(_delta: float) -> void:
	move_and_slide()

# ── Facing ────────────────────────────────────────────────────────────────────
func set_facing(facing: Vector2) -> void:
	_facing = facing
	rotation.y = atan2(-_facing.x, -_facing.y)
	lower_body.rotation.y = 0.0

func get_facing() -> Vector2:
	return _facing

# ── Blade ─────────────────────────────────────────────────────────────────────
func set_blade_position(pos: Vector3) -> void:
	blade.position = pos

func get_blade_position() -> Vector3:
	return blade.position

# ── Upper Body ────────────────────────────────────────────────────────────────
func set_upper_body_rotation(angle: float) -> void:
	upper_body.rotation.y = angle

func get_upper_body_rotation() -> float:
	return upper_body.rotation.y

# ── Wall Clamping ─────────────────────────────────────────────────────────────
func clamp_blade_to_walls(local_pos: Vector3) -> Vector3:
	var to_blade: Vector3 = local_pos
	to_blade.y = 0.0
	stick_raycast.target_position = to_blade
	stick_raycast.force_raycast_update()

	if stick_raycast.is_colliding():
		var hit_dist: float = global_position.distance_to(stick_raycast.get_collision_point())
		var blade_dist: float = to_blade.length()
		if hit_dist < blade_dist:
			var clamped_dist: float = maxf(hit_dist - 0.05, 0.1)
			local_pos = to_blade.normalized() * clamped_dist
			local_pos.y = blade_height

	return local_pos

func get_wall_squeeze(intended_pos: Vector3, clamped_pos: Vector3) -> float:
	return intended_pos.length() - clamped_pos.length()

func get_blade_wall_normal() -> Vector3:
	if stick_raycast.is_colliding():
		return stick_raycast.get_collision_normal()
	return Vector3.ZERO

# ── Stick Mesh ────────────────────────────────────────────────────────────────
func update_stick_mesh() -> void:
	var stick_origin: Vector3 = shoulder.position
	var to_blade: Vector3 = blade.position - stick_origin
	stick_mesh.position = stick_origin + to_blade / 2.0
	stick_mesh.scale.z = to_blade.length()
	stick_mesh.look_at(upper_body.to_global(blade.position), Vector3.UP)

# ── Coordinate Helpers ────────────────────────────────────────────────────────
func upper_body_to_global(local_pos: Vector3) -> Vector3:
	return upper_body.to_global(local_pos)

func upper_body_to_local(world_pos: Vector3) -> Vector3:
	return upper_body.to_local(world_pos)

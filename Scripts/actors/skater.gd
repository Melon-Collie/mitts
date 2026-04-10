class_name Skater
extends CharacterBody3D

# ── Character ─────────────────────────────────────────────────────────────────
@export var is_left_handed: bool = true

# ── Blade Tuning ──────────────────────────────────────────────────────────────
@export var blade_height: float = 0.0
@export var plane_reach: float = 1.5
@export var shoulder_offset: float = 0.35
@export var wall_squeeze_threshold: float = 0.3

# ── Body Check Tuning ─────────────────────────────────────────────────────────
@export var weight: float = 1.0                   # dimensionless — scale up for heavy players
@export var body_check_restitution: float = 0.3   # fraction of approach speed bounced back to self
@export var body_check_transfer: float = 0.8      # fraction of approach speed pushed to victim (before weight ratio)

# ── Body Block Tuning ─────────────────────────────────────────────────────────
@export var body_block_radius: float = 0.5

# ── Node References ───────────────────────────────────────────────────────────
@onready var lower_body: Node3D = $LowerBody
@onready var upper_body: Node3D = $UpperBody
@onready var blade: Marker3D = $UpperBody/Blade
@onready var shoulder: Marker3D = $UpperBody/Shoulder
@onready var stick_raycast: RayCast3D = $StickRaycast
@onready var stick_mesh: MeshInstance3D = $UpperBody/StickMesh

signal body_checked_player(victim: Skater, impact_force: float, hit_direction: Vector3)
signal body_block_hit(body: Node3D)

# ── Runtime ───────────────────────────────────────────────────────────────────
var _facing: Vector2 = Vector2.DOWN
var is_elevated: bool = false
var blade_world_velocity: Vector3 = Vector3.ZERO
var _prev_blade_world_pos: Vector3 = Vector3.ZERO
var _body_block_area: Area3D = null

func _ready() -> void:
	var hand_sign: float = -1.0 if is_left_handed else 1.0
	shoulder.position = Vector3(hand_sign * shoulder_offset, 0.0, 0.0)
	_prev_blade_world_pos = upper_body.to_global(blade.position)

	collision_layer = Constants.LAYER_SKATER_BODIES
	collision_mask  = Constants.MASK_SKATER
	stick_raycast.collision_mask = Constants.MASK_SKATER

	var blade_area = Area3D.new()
	blade_area.name = "BladeArea"
	blade_area.collision_layer = Constants.LAYER_BLADE_AREAS
	blade_area.collision_mask = 0
	var blade_shape = CollisionShape3D.new()
	var blade_sphere = SphereShape3D.new()
	blade_sphere.radius = 0.3
	blade_shape.shape = blade_sphere
	blade_area.add_child(blade_shape)
	blade.add_child(blade_area)

	_body_block_area = Area3D.new()
	_body_block_area.name = "BodyBlockArea"
	_body_block_area.collision_layer = 0
	_body_block_area.collision_mask = Constants.LAYER_PUCK
	var block_shape = CollisionShape3D.new()
	var block_sphere = SphereShape3D.new()
	block_sphere.radius = body_block_radius
	block_shape.shape = block_sphere
	_body_block_area.add_child(block_shape)
	add_child(_body_block_area)
	_body_block_area.body_entered.connect(func(body: Node3D) -> void: body_block_hit.emit(body))
	
	shoulder.position = Vector3(hand_sign * shoulder_offset, 0.0, 0.0)
	blade_area.position = Vector3.ZERO

func _physics_process(delta: float) -> void:
	var blade_world_pos: Vector3 = upper_body.to_global(blade.position)
	blade_world_velocity = (blade_world_pos - _prev_blade_world_pos) / delta
	_prev_blade_world_pos = blade_world_pos
	var vel_before: Vector3 = velocity
	move_and_slide()
	_resolve_player_collisions(vel_before)

func _resolve_player_collisions(vel_before: Vector3) -> void:
	for i: int in get_slide_collision_count():
		var col := get_slide_collision(i)
		if not col.get_collider() is Skater:
			continue
		var other := col.get_collider() as Skater
		# Use horizontal normal only — skater collisions are on the XZ plane.
		var raw_normal: Vector3 = col.get_normal()
		var normal := Vector3(raw_normal.x, 0.0, raw_normal.z)
		if normal.length() < 0.001:
			continue
		normal = normal.normalized()
		var vel_horiz := Vector3(vel_before.x, 0.0, vel_before.z)
		var approach: float = vel_horiz.dot(-normal)
		if approach <= 0.0:
			continue
		# Bounce self back away from other.
		velocity += normal * approach * body_check_restitution
		# Push other away; heavier checker transfers more to a lighter victim.
		other.velocity -= normal * approach * (weight / other.weight) * body_check_transfer
		# Signal for server-side puck strip check.
		body_checked_player.emit(other, weight * approach, -normal)

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
	# Rotate blade (and its children: mesh, BladeArea) to face along the shaft.
	# Use horizontal projection so the blade stays upright despite blade_height offset.
	var blade_world: Vector3 = upper_body.to_global(pos)
	var shoulder_world: Vector3 = upper_body.to_global(shoulder.position)
	var shaft_horiz: Vector3 = blade_world - shoulder_world
	shaft_horiz.y = 0.0
	if shaft_horiz.length() > 0.001:
		blade.look_at(blade_world + shaft_horiz.normalized(), Vector3.UP)

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

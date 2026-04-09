class_name Puck
extends RigidBody3D

signal puck_picked_up(carrier: Skater)
signal puck_released()

@export var max_speed: float = 30.0
@export var reattach_cooldown: float = 0.5
@export var ice_height: float = 0.05
@export var pickup_max_speed: float = 8.0
@export var deflect_min_speed: float = 20.0
@export var deflect_blend: float = 0.5
@export var deflect_speed_retain: float = 0.7
@export var deflect_cooldown: float = 0.3

var carrier: Skater = null
var pickup_locked: bool = false
var _cooldown_timer: float = 0.0
var _is_server: bool = false

func _ready() -> void:
	# Layer 4 (value 8) — no physics effect, but lets goal sensor Area3Ds detect this body.
	collision_layer = 8
	process_physics_priority = 1  # Run after Skater.move_and_slide so blade world pos is current

	var pickup_zone = Area3D.new()
	pickup_zone.name = "PickupZone"
	pickup_zone.collision_layer = 3
	pickup_zone.collision_mask = 2
	var pickup_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.5
	pickup_shape.shape = sphere
	pickup_zone.add_child(pickup_shape)
	add_child(pickup_zone)
	pickup_zone.area_entered.connect(_on_blade_entered)

# ── Server Mode ───────────────────────────────────────────────────────────────
func set_server_mode(is_server: bool) -> void:
	_is_server = is_server
	if not is_server:
		freeze = true

# ── Contract for PuckController ───────────────────────────────────────────────
func get_puck_position() -> Vector3:
	return global_position

func get_puck_velocity() -> Vector3:
	return linear_velocity

func set_puck_position(pos: Vector3) -> void:
	global_position = pos

func set_puck_velocity(vel: Vector3) -> void:
	linear_velocity = vel

func get_carrier() -> Skater:
	return carrier

func set_carrier(skater: Skater) -> void:
	carrier = skater
	freeze = true

func clear_carrier() -> void:
	carrier = null
	freeze = false

# ── Physics ───────────────────────────────────────────────────────────────────
func _on_blade_entered(area: Area3D) -> void:
	if not _is_server:
		return
	if carrier != null:
		return
	if _cooldown_timer > 0.0:
		return
	if pickup_locked:
		return

	var node = area
	while node and not node is Skater:
		node = node.get_parent()

	if not node:
		return

	var speed = linear_velocity.length()

	if speed <= pickup_max_speed:
		carrier = node
		puck_picked_up.emit(node)
	elif speed >= deflect_min_speed:
		_deflect_off_blade(area)
	else:
		carrier = node
		puck_picked_up.emit(node)

func _deflect_off_blade(area: Area3D) -> void:
	var blade_forward = area.global_transform.basis.z
	blade_forward.y = 0.0
	blade_forward = blade_forward.normalized()
	var current_dir = linear_velocity.normalized()
	var new_dir = current_dir.lerp(blade_forward, deflect_blend).normalized()
	linear_velocity = new_dir * linear_velocity.length() * deflect_speed_retain
	_cooldown_timer = deflect_cooldown

func release(direction: Vector3, power: float) -> void:
	clear_carrier()
	if direction.y > 0:
		position.y = ice_height + 0.1
	linear_velocity = direction * power
	_cooldown_timer = reattach_cooldown
	puck_released.emit()

func drop() -> void:
	clear_carrier()
	linear_velocity = Vector3.ZERO
	puck_released.emit()

func reset() -> void:
	clear_carrier()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = Vector3(0, ice_height, 0)
	_cooldown_timer = 0.0
	puck_released.emit()

func _is_airborne() -> bool:
	return position.y > ice_height + 0.05

func _physics_process(delta: float) -> void:
	if not _is_server:
		return
		
	if carrier != null:
		freeze = true
		var blade_node = carrier.get_node("UpperBody/Blade")
		global_position = blade_node.global_position
		global_position.y = ice_height
	else:
		if _cooldown_timer > 0.0:
			_cooldown_timer -= delta
		if linear_velocity.length() > max_speed:
			linear_velocity = linear_velocity.normalized() * max_speed
		if _is_airborne():
			pass
		else:
			linear_velocity.y = 0.0
			position.y = ice_height

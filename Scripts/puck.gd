class_name Puck
extends RigidBody3D

signal puck_picked_up(carrier: SkaterController)
signal puck_released()

@export var max_speed: float = 30.0
@export var reattach_cooldown: float = 0.5
@export var ice_height: float = 0.05
@export var pickup_max_speed: float = 8.0
@export var deflect_min_speed: float = 20.0
@export var deflect_blend: float = 0.5          # 0 = puck keeps its direction, 1 = fully redirected by blade
@export var deflect_speed_retain: float = 0.7   # how much speed the puck keeps after deflection
@export var deflect_cooldown: float = 0.3

var carrier: Node3D = null
var _cooldown_timer: float = 0.0

func _ready() -> void:
	$PickupZone.area_entered.connect(_on_blade_entered)

func _on_blade_entered(area: Area3D) -> void:
	if carrier != null:
		return
	if _cooldown_timer > 0.0:
		return
	
	var node = area
	while node and not node is SkaterController:
		node = node.get_parent()
	if not node:
		return
	
	var speed = linear_velocity.length()
	
	if speed <= pickup_max_speed:
		# Clean pickup
		carrier = node
		puck_picked_up.emit(node)
	elif speed >= deflect_min_speed:
		# Always deflect
		_deflect_off_blade(area)
	else:
		# Middle zone — for now, just pick up. Can add readiness check later.
		carrier = node
		puck_picked_up.emit(node)

func _deflect_off_blade(area: Area3D) -> void:
	var blade_forward = area.global_transform.basis.z
	blade_forward.y = 0.0
	blade_forward = blade_forward.normalized()
	
	var current_dir = linear_velocity.normalized()
	var new_dir = current_dir.lerp(blade_forward, deflect_blend).normalized()
	var new_speed = linear_velocity.length() * deflect_speed_retain
	
	linear_velocity = new_dir * new_speed
	_cooldown_timer = deflect_cooldown

func release(direction: Vector3, power: float) -> void:
	carrier = null
	freeze = false
	if direction.y > 0:
		position.y = ice_height + 0.1
	linear_velocity = direction * power
	_cooldown_timer = reattach_cooldown
	puck_released.emit()
	
func drop() -> void:
	carrier = null
	freeze = false
	linear_velocity = Vector3.ZERO
	puck_released.emit()

func reset() -> void:
	carrier = null
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = Vector3(0, ice_height, 0)
	_cooldown_timer = 0.0
	puck_released.emit()

func _is_airborne() -> bool:
	return position.y > ice_height + 0.05

func _physics_process(delta: float) -> void:
	if carrier != null:
		freeze = true
		var blade_node = carrier.get_node("UpperBody/Blade")
		global_position = blade_node.global_position
		global_position.y = ice_height
	else:
		freeze = false
		if _cooldown_timer > 0.0:
			_cooldown_timer -= delta
		if linear_velocity.length() > max_speed:
			linear_velocity = linear_velocity.normalized() * max_speed
		
		if _is_airborne():
			pass
		else:
			linear_velocity.y = 0.0
			position.y = ice_height

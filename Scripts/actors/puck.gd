class_name Puck
extends RigidBody3D

signal puck_picked_up(carrier: Skater)
signal puck_released()
signal puck_stripped(ex_carrier: Skater)
signal puck_touched_loose(skater: Skater)  # any loose-puck touch (deflection, body block)
signal puck_touched_goalie(goalie: Goalie)  # puck contacted a goalie StaticBody3D part while uncarried

@export var max_speed: float = 30.0
@export var reattach_cooldown: float = 0.5
@export var ice_height: float = 0.05
@export var pickup_max_speed: float = 8.0
@export var deflect_min_speed: float = 14.0
@export var deflect_blend: float = 0.5
@export var deflect_speed_retain: float = 0.7
@export var deflect_cooldown: float = 0.3
@export var deflect_elevation_angle: float = 35.0
@export var poke_strip_speed: float = 6.0
@export var poke_carrier_vel_blend: float = 0.5
@export var poke_checker_cooldown: float = 0.1
@export var body_check_strip_threshold: float = 6.0  # weight × approach_speed needed to strip
@export var body_check_puck_speed: float = 5.0
@export var body_block_dampen: float = 0.5
@export var body_block_cooldown: float = 0.1

var carrier: Skater = null
var pickup_locked: bool = false
var _cooldown_timers: Dictionary = {}  # Skater -> float
var _is_server: bool = false
var _pending_reset: bool = false
# Callable (Skater) -> int team_id, or -1 if the skater isn't registered. Set
# by GameManager at spawn time so Puck doesn't reach upward for team checks.
var _team_resolver: Callable = Callable()

func set_team_resolver(resolver: Callable) -> void:
	_team_resolver = resolver

func _ready() -> void:
	# Puck body sits on its own layer so goal sensors can detect it.
	# Mask = LAYER_WALLS only: bounces off boards + goalie bodies, not skater bodies.
	collision_layer = Constants.LAYER_PUCK
	collision_mask  = Constants.MASK_PUCK
	process_physics_priority = 1  # Run after Skater.move_and_slide so blade world pos is current
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	var vfx := PuckVFX.new()
	vfx.name = "VFX"
	add_child(vfx)

# ── Server Mode ───────────────────────────────────────────────────────────────
func set_server_mode(is_server: bool) -> void:
	_is_server = is_server
	if not is_server:
		freeze = true

func set_client_prediction_mode(active: bool) -> void:
	if _is_server:
		return
	freeze = not active
	if not active:
		linear_velocity = Vector3.ZERO

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

# ── Cooldown Helpers ──────────────────────────────────────────────────────────
func is_on_cooldown(skater: Skater) -> bool:
	return _cooldown_timers.get(skater, 0.0) > 0.0

func _set_cooldown(skater: Skater, duration: float) -> void:
	_cooldown_timers[skater] = duration

func remove_skater_cooldown(skater: Skater) -> void:
	_cooldown_timers.erase(skater)

# ── Physics ───────────────────────────────────────────────────────────────────
func apply_blade_deflect(skater: Skater) -> void:
	# Use the blade face normal — perpendicular to the stick shaft in the horizontal
	# plane — as the reflection surface. This makes the deflection angle depend on
	# how the player has angled their blade, not just where the puck contacted.
	var top_hand_world: Vector3 = skater.top_hand.global_position
	var blade_world: Vector3 = skater.get_blade_contact_global()
	var stick_horiz: Vector3 = blade_world - top_hand_world
	stick_horiz.y = 0.0
	if stick_horiz.length() < 0.001:
		stick_horiz = -skater.global_transform.basis.z
	stick_horiz = stick_horiz.normalized()
	# 90° rotation around Y gives the face normal; pick the face opposing the puck.
	var contact_normal: Vector3 = Vector3(-stick_horiz.z, 0.0, stick_horiz.x)
	if contact_normal.dot(linear_velocity) > 0.0:
		contact_normal = -contact_normal

	var new_vel: Vector3 = PuckCollisionRules.deflect_velocity(
			linear_velocity, contact_normal, deflect_blend, deflect_speed_retain)

	if skater.is_elevated:
		var new_dir: Vector3 = PuckCollisionRules.apply_deflection_elevation(
				new_vel.normalized(), deflect_elevation_angle)
		new_vel = new_dir * new_vel.length()

	linear_velocity = new_vel
	_set_cooldown(skater, deflect_cooldown)
	puck_touched_loose.emit(skater)

func on_body_block(blocker: Skater, dampen_override: float = -1.0) -> void:
	if not _is_server:
		return
	if pickup_locked:
		return
	if blocker.is_ghost:
		return
	if carrier != null:
		return  # only deflect loose/airborne pucks, not carried ones
	var body_world: Vector3 = blocker.global_position
	body_world.y = 0.0
	var puck_pos: Vector3 = global_position
	puck_pos.y = 0.0
	var contact_normal: Vector3 = puck_pos - body_world
	if contact_normal.length() < 0.001:
		contact_normal = -blocker.global_transform.basis.z
	contact_normal = contact_normal.normalized()
	var effective_dampen: float = dampen_override if dampen_override >= 0.0 else body_block_dampen
	linear_velocity = PuckCollisionRules.body_block_velocity(
			linear_velocity, contact_normal, effective_dampen)
	_set_cooldown(blocker, body_block_cooldown)
	puck_touched_loose.emit(blocker)

func on_body_check(checker: Skater, victim: Skater, impact_force: float, hit_direction: Vector3) -> void:
	if not _is_server:
		return
	if checker.is_ghost or victim.is_ghost:
		return
	if carrier == null or carrier != victim:
		return
	if pickup_locked:
		return
	if impact_force < body_check_strip_threshold:
		return
	_body_check_strip(checker, hit_direction)

func _body_check_strip(checker: Skater, hit_direction: Vector3) -> void:
	var ex_carrier: Skater = carrier
	clear_carrier()
	linear_velocity = PuckCollisionRules.body_check_strip_velocity(hit_direction, body_check_puck_speed)
	_set_cooldown(ex_carrier, reattach_cooldown)
	_set_cooldown(checker, poke_checker_cooldown)
	puck_stripped.emit(ex_carrier)
	puck_released.emit()

func apply_poke_check(checker_skater: Skater) -> void:
	var ex_carrier: Skater = carrier  # capture before clear_carrier()
	var fallback_dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	clear_carrier()
	linear_velocity = PuckCollisionRules.poke_strip_velocity(
			checker_skater.blade_world_velocity,
			ex_carrier.blade_world_velocity,
			ex_carrier.global_position,
			checker_skater.global_position,
			poke_carrier_vel_blend,
			poke_strip_speed,
			fallback_dir)
	_set_cooldown(ex_carrier, reattach_cooldown)
	_set_cooldown(checker_skater, poke_checker_cooldown)
	puck_stripped.emit(ex_carrier)
	puck_released.emit()

func release(direction: Vector3, power: float) -> void:
	var ex_carrier: Skater = carrier
	clear_carrier()
	if direction.y > 0:
		position.y = ice_height + 0.1
	linear_velocity = direction * power
	if ex_carrier != null:
		_set_cooldown(ex_carrier, reattach_cooldown)
	puck_released.emit()

func drop() -> void:
	var ex_carrier: Skater = carrier
	clear_carrier()
	linear_velocity = Vector3.ZERO
	if ex_carrier != null:
		_set_cooldown(ex_carrier, reattach_cooldown)
	puck_released.emit()

func reset() -> void:
	carrier = null
	freeze = false  # ensure _integrate_forces is called on the next step
	_cooldown_timers.clear()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_pending_reset = true
	puck_released.emit()

func is_airborne() -> bool:
	return position.y > ice_height + 0.05

func _on_body_entered(body: Node3D) -> void:
	if carrier != null:
		return
	if body.get_parent() is Goalie:
		puck_touched_goalie.emit(body.get_parent() as Goalie)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_reset:
		_pending_reset = false
		state.transform = Transform3D(Basis(), Vector3(0, ice_height, 0))
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return
	if state.linear_velocity.length() > max_speed:
		state.linear_velocity = state.linear_velocity.normalized() * max_speed

func _physics_process(delta: float) -> void:
	if not _is_server:
		return

	# Tick per-skater cooldowns regardless of carrier state
	var _expired: Array = []
	for skater in _cooldown_timers.keys():
		if not is_instance_valid(skater):
			_expired.append(skater)
			continue
		_cooldown_timers[skater] -= delta
		if _cooldown_timers[skater] <= 0.0:
			_expired.append(skater)
	for s in _expired:
		_cooldown_timers.erase(s)

	if carrier != null:
		freeze = true
		# Pin at the blade contact point (mid-blade), not the heel (Marker3D).
		global_position = carrier.get_blade_contact_global()
		global_position.y = ice_height
	elif not is_airborne():
		# Max-speed clamp already runs every physics substep in _integrate_forces.
		linear_velocity.y = 0.0
		position.y = ice_height

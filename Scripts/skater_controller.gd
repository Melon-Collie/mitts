class_name SkaterController
extends CharacterBody3D

@export var camera: Camera3D

# ── State Machine ─────────────────────────────────────────────────────────────
enum State {
	SKATING_WITHOUT_PUCK,
	SKATING_WITH_PUCK,
	WRISTER_AIM,
	SLAPPER_CHARGE_WITH_PUCK,
	SLAPPER_CHARGE_WITHOUT_PUCK,
	FOLLOW_THROUGH,
}

# ── Movement Tuning ───────────────────────────────────────────────────────────
@export var thrust: float = 20.0
@export var friction: float = 5.0
@export var max_speed: float = 10.0
@export var rotation_speed: float = 6.0
@export var move_deadzone: float = 0.1
@export var brake_multiplier: float = 5.0

# ── Facing Tuning ─────────────────────────────────────────────────────────────
@export var facing_drag_speed: float = 3.0
@export var facing_snap_speed: float = 20.0

# ── Blade Tuning ──────────────────────────────────────────────────────────────
@export var blade_height: float = 0.0
@export var plane_reach: float = 1.5
@export var shoulder_offset: float = 0.35
@export var wall_squeeze_threshold: float = 0.3
@export var blade_forehand_limit: float = 90.0	# degrees
@export var blade_backhand_limit: float = 80.0	# degrees

# ── Upper Body Tuning ─────────────────────────────────────────────────────────
@export var upper_body_twist_ratio: float = 0.5
@export var upper_body_return_speed: float = 10.0

# ── Wrister Tuning ────────────────────────────────────────────────────────────
@export var min_wrister_power: float = 8.0
@export var max_wrister_power: float = 25.0
@export var max_wrister_charge_distance: float = 3.0
@export var backhand_power_coefficient: float = 0.75
@export var max_charge_direction_variance: float = 45.0	# degrees
@export var quick_shot_power: float = 12.0
@export var quick_shot_threshold: float = 0.1
@export var wrister_elevation: float = 0.3

# ── Slapper Tuning ────────────────────────────────────────────────────────────
@export var min_slapper_power: float = 20.0
@export var max_slapper_power: float = 40.0
@export var max_slapper_charge_time: float = 1.0
@export var slapper_blade_x: float = 1.0
@export var slapper_blade_z: float = -0.5
@export var slapper_aim_arc: float = 45.0	# degrees either side
@export var slapper_elevation: float = 0.15

# ── Follow Through Tuning ─────────────────────────────────────────────────────
@export var follow_through_duration: float = 0.15

# ── Character ─────────────────────────────────────────────────────────────────
@export var is_left_handed: bool = true
@export var puck: Puck

# ── Self Pass / Shot ──────────────────────────────────────────────────────────
@export var self_pass_power: float = 12.0
@export var self_shot_power: float = 30.0

# ── Node References ───────────────────────────────────────────────────────────
@onready var lower_body: Node3D = $LowerBody
@onready var upper_body: Node3D = $UpperBody
@onready var blade: Marker3D = $UpperBody/Blade
@onready var shoulder: Marker3D = $UpperBody/Shoulder
@onready var stick_raycast: RayCast3D = $StickRaycast
@onready var stick_mesh: MeshInstance3D = $UpperBody/StickMesh

# ── Runtime State ─────────────────────────────────────────────────────────────
var _input: InputState
var _gatherer: LocalInputGatherer
var _state: State = State.SKATING_WITHOUT_PUCK

# Facing
var _facing: Vector2 = Vector2.DOWN

# Blade
var _blade_relative_angle: float = 0.0

# Upper body
var _upper_body_angle: float = 0.0

# Shooting
var _is_elevated: bool = false
var _shot_dir: Vector3 = Vector3.ZERO
var _follow_through_timer: float = 0.0
var _charge_distance: float = 0.0
var _prev_blade_pos: Vector3 = Vector3.ZERO
var _prev_blade_dir: Vector3 = Vector3.ZERO
var _slapper_charge_timer: float = 0.0

func _ready() -> void:
	_gatherer = LocalInputGatherer.new(camera)
	add_child(_gatherer)

	var hand_sign: float = -1.0 if is_left_handed else 1.0
	shoulder.position = Vector3(hand_sign * shoulder_offset, 0.0, 0.0)

	puck.puck_picked_up.connect(_on_puck_picked_up)
	puck.puck_released.connect(_on_puck_released)

func _physics_process(delta: float) -> void:
	_input = _gatherer.gather()

	# Self pass / shot
	if _input.self_pass and puck.carrier == null:
		var dir: Vector3 = (global_position - puck.global_position).normalized()
		dir.y = 0.0
		puck.linear_velocity = dir * self_pass_power

	if _input.self_shot and puck.carrier == null:
		var dir: Vector3 = (global_position - puck.global_position).normalized()
		dir.y = 0.0
		puck.linear_velocity = dir * self_shot_power
		
	if _input.elevation_up:
		_is_elevated = true
	if _input.elevation_down:
		_is_elevated = false

	_apply_movement(delta)
	_apply_facing(delta)
	_apply_state(delta)
	_apply_upper_body(delta)
	_update_stick_mesh()
	move_and_slide()

# ── Puck Signals ──────────────────────────────────────────────────────────────
func _on_puck_picked_up(carrier: SkaterController) -> void:
	if carrier == self:
		if _input.shoot_held:
			_enter_wrister_aim()
		elif _state == State.SLAPPER_CHARGE_WITHOUT_PUCK:
			_state = State.SLAPPER_CHARGE_WITH_PUCK
		else:
			_state = State.SKATING_WITH_PUCK
		var local_blade: Vector3 = blade.position - shoulder.position
		_blade_relative_angle = atan2(local_blade.x, -local_blade.z)

func _on_puck_released() -> void:
	if _state == State.FOLLOW_THROUGH:
		return
	_transition_to_skating()

# ── State Machine ─────────────────────────────────────────────────────────────
func _apply_state(delta: float) -> void:
	match _state:
		State.SKATING_WITHOUT_PUCK:
			_state_skating_without_puck(delta)
		State.SKATING_WITH_PUCK:
			_state_skating_with_puck(delta)
		State.WRISTER_AIM:
			_state_wrister_aim(delta)
		State.SLAPPER_CHARGE_WITH_PUCK:
			_state_slapper_charge_with_puck(delta)
		State.SLAPPER_CHARGE_WITHOUT_PUCK:
			_state_slapper_charge_without_puck(delta)
		State.FOLLOW_THROUGH:
			_state_follow_through(delta)

# ── Skating Without Puck ──────────────────────────────────────────────────────
func _state_skating_without_puck(delta: float) -> void:
	_apply_blade_from_mouse(delta)

	if _input.shoot_pressed:
		_state = State.WRISTER_AIM
		_shot_dir = Vector3.ZERO

	if _input.slap_pressed:
		_enter_slapper_charge()

# ── Skating With Puck ─────────────────────────────────────────────────────────
func _state_skating_with_puck(delta: float) -> void:
	_apply_blade_from_mouse(delta)

	if _input.shoot_pressed:
		_enter_wrister_aim()

	if _input.slap_pressed:
		_enter_slapper_charge()

# ── Wrister Aim ───────────────────────────────────────────────────────────────
func _state_wrister_aim(delta: float) -> void:
	_apply_blade_from_mouse(delta)

	# Track blade movement for charge
	if puck.carrier == self:
		var blade_delta: Vector3 = blade.position - _prev_blade_pos
		blade_delta.y = 0.0
		var dist: float = blade_delta.length()
		if dist > 0.001:
			var current_dir: Vector3 = blade_delta.normalized()
			if _prev_blade_dir != Vector3.ZERO:
				var angle: float = rad_to_deg(_prev_blade_dir.angle_to(current_dir))
				if angle > max_charge_direction_variance:
					_charge_distance = 0.0
			_charge_distance += dist
			_prev_blade_dir = current_dir

	_prev_blade_pos = blade.position

	# Update shot direction from blade position
	var local_blade: Vector3 = blade.position - shoulder.position
	local_blade.y = 0.0
	if local_blade.length() > 0.01:
		_shot_dir = (global_transform.basis * local_blade).normalized()

	if not _input.shoot_held:
		_release_wrister()

# ── Slapper Charge With Puck ──────────────────────────────────────────────────
func _state_slapper_charge_with_puck(delta: float) -> void:
	_slapper_charge_timer += delta
	_apply_slapper_blade_position()

	# Glide on existing momentum, natural friction only
	var slapper_vel: Vector2 = Vector2(velocity.x, velocity.z)
	slapper_vel = slapper_vel.move_toward(Vector2.ZERO, friction * delta)
	velocity.x = slapper_vel.x
	velocity.z = slapper_vel.y

	# Upper body rotates toward mouse within arc
	var mouse_world: Vector3 = _input.mouse_world_pos
	mouse_world.y = 0.0
	var to_mouse: Vector3 = mouse_world - global_position
	to_mouse.y = 0.0
	if to_mouse.length() > move_deadzone:
		var local_dir: Vector3 = global_transform.basis.inverse() * to_mouse.normalized()
		var raw_angle: float = atan2(local_dir.x, -local_dir.z)
		var clamped_angle: float = clampf(raw_angle, -deg_to_rad(slapper_aim_arc), deg_to_rad(slapper_aim_arc))
		_upper_body_angle = lerp_angle(_upper_body_angle, -clamped_angle, upper_body_return_speed * delta)
		upper_body.rotation.y = _upper_body_angle

	if not _input.slap_held:
		_release_slapper()

# ── Slapper Charge Without Puck ───────────────────────────────────────────────
func _state_slapper_charge_without_puck(delta: float) -> void:
	_slapper_charge_timer += delta
	_apply_slapper_blade_position()

	# Full facing toward mouse
	var mouse_world: Vector3 = _input.mouse_world_pos
	mouse_world.y = 0.0
	var to_mouse: Vector2 = Vector2(
		mouse_world.x - global_position.x,
		mouse_world.z - global_position.z
	)
	if to_mouse.length() > move_deadzone:
		_facing = _facing.lerp(to_mouse.normalized(), rotation_speed * delta).normalized()
		rotation.y = atan2(-_facing.x, -_facing.y)
		lower_body.rotation.y = 0.0

	if not _input.slap_held:
		_release_slapper()

# ── Follow Through ────────────────────────────────────────────────────────────
func _state_follow_through(delta: float) -> void:
	_apply_blade_from_relative_angle()
	_follow_through_timer -= delta
	if _follow_through_timer <= 0.0:
		_transition_to_skating()

# ── State Helpers ─────────────────────────────────────────────────────────────
func _transition_to_skating() -> void:
	if puck.carrier == self:
		_state = State.SKATING_WITH_PUCK
	else:
		_state = State.SKATING_WITHOUT_PUCK
	_shot_dir = Vector3.ZERO
	_upper_body_angle = 0.0

func _enter_wrister_aim() -> void:
	_state = State.WRISTER_AIM
	_shot_dir = Vector3.ZERO
	_charge_distance = 0.0
	_prev_blade_pos = blade.position
	_prev_blade_dir = Vector3.ZERO

func _enter_slapper_charge() -> void:
	_slapper_charge_timer = 0.0
	_shot_dir = Vector3.ZERO
	_upper_body_angle = 0.0
	upper_body.rotation.y = 0.0
	if puck.carrier == self:
		_state = State.SLAPPER_CHARGE_WITH_PUCK
	else:
		_state = State.SLAPPER_CHARGE_WITHOUT_PUCK

func _release_wrister() -> void:
	if puck.carrier == self and _shot_dir != Vector3.ZERO:
		var charge_t: float = clampf(_charge_distance / max_wrister_charge_distance, 0.0, 1.0)

		if charge_t < quick_shot_threshold:
			# Quick shot — fire in blade direction at fixed power
			var local_blade: Vector3 = blade.position - shoulder.position
			local_blade.y = 0.0
			var blade_dir: Vector3 = (global_transform.basis * local_blade).normalized()
			var y_component: float = wrister_elevation if _is_elevated else 0.0
			var blade_dir_elevated: Vector3 = Vector3(blade_dir.x, y_component, blade_dir.z).normalized()
			puck.release(blade_dir_elevated, quick_shot_power)
		else:
			# Full wrister — use aimed direction and charged power
			var power: float = lerpf(min_wrister_power, max_wrister_power, charge_t)
			var hand_sign: float = -1.0 if is_left_handed else 1.0
			var is_backhand: bool = sign(blade.position.x - shoulder.position.x) != sign(hand_sign)
			if is_backhand:
				power *= backhand_power_coefficient
			var y_component: float = wrister_elevation if _is_elevated else 0.0
			var shot_dir_elevated: Vector3 = Vector3(_shot_dir.x, y_component, _shot_dir.z).normalized()
			puck.release(shot_dir_elevated, power)

	_state = State.FOLLOW_THROUGH
	_follow_through_timer = follow_through_duration

func _release_slapper() -> void:
	if puck.carrier == self:
		var upper_body_world_angle: float = rotation.y + _upper_body_angle
		_shot_dir = Vector3(-sin(upper_body_world_angle), 0.0, -cos(upper_body_world_angle))
		var charge_t: float = clampf(_slapper_charge_timer / max_slapper_charge_time, 0.0, 1.0)
		var power: float = lerpf(min_slapper_power, max_slapper_power, charge_t)
		var y_component: float = slapper_elevation if _is_elevated else 0.0
		var shot_dir_elevated: Vector3 = Vector3(_shot_dir.x, y_component, _shot_dir.z).normalized()
		puck.release(shot_dir_elevated, power)

	_state = State.FOLLOW_THROUGH
	_follow_through_timer = follow_through_duration

func _apply_slapper_blade_position() -> void:
	var hand_sign: float = -1.0 if is_left_handed else 1.0
	blade.position = shoulder.position + Vector3(hand_sign * slapper_blade_x, blade_height, slapper_blade_z)

func _is_in_slapper_state() -> bool:
	return _state in [State.SLAPPER_CHARGE_WITH_PUCK, State.SLAPPER_CHARGE_WITHOUT_PUCK]

# ── Blade: From Mouse ─────────────────────────────────────────────────────────
func _apply_blade_from_mouse(delta: float) -> void:
	var mouse_world: Vector3 = _input.mouse_world_pos
	mouse_world.y = 0.0

	var shoulder_world: Vector3 = upper_body.to_global(shoulder.position)
	shoulder_world.y = 0.0
	var to_mouse: Vector3 = mouse_world - shoulder_world

	if to_mouse.length() < 0.01:
		return

	# Raw angle from shoulder to mouse in upper_body local space
	var local_to_mouse: Vector3 = upper_body.to_local(shoulder_world + to_mouse.normalized() * minf(to_mouse.length(), plane_reach))
	local_to_mouse.y = 0.0
	var raw_angle: float = atan2((local_to_mouse - shoulder.position).x, -(local_to_mouse - shoulder.position).z)

	# Flip into forehand-positive space, clamp asymmetrically, flip back
	var hand_sign: float = -1.0 if is_left_handed else 1.0
	var handed_angle: float = raw_angle * hand_sign
	var clamped_handed: float = clampf(handed_angle, -deg_to_rad(blade_backhand_limit), deg_to_rad(blade_forehand_limit))
	var clamped_angle: float = clamped_handed * hand_sign

	# If past clamp limit, rotate facing to follow
	if not _is_in_slapper_state() and _state != State.WRISTER_AIM:
		if abs(handed_angle) > abs(clamped_handed):
			var excess: float = (handed_angle - clamped_handed) * hand_sign
			_facing = _facing.rotated(excess * facing_drag_speed * delta).normalized()
			rotation.y = atan2(-_facing.x, -_facing.y)
			lower_body.rotation.y = 0.0

	# Reposition blade from clamped angle
	var clamped_dir: Vector3 = Vector3(sin(clamped_angle), 0.0, -cos(clamped_angle))
	var clamped_target: Vector3 = shoulder.position + clamped_dir * minf(to_mouse.length(), plane_reach)
	clamped_target.y = blade_height
	clamped_target = _apply_wall_clamping(clamped_target)
	blade.position = clamped_target

	_blade_relative_angle = clamped_angle

# ── Blade: From Stored Relative Angle ────────────────────────────────────────
func _apply_blade_from_relative_angle() -> void:
	var local_dir: Vector3 = Vector3(sin(_blade_relative_angle), 0.0, -cos(_blade_relative_angle))
	var local_target: Vector3 = shoulder.position + local_dir * plane_reach
	local_target.y = blade_height
	local_target = _apply_wall_clamping(local_target)
	blade.position = local_target

# ── Wall Clamping ─────────────────────────────────────────────────────────────
func _apply_wall_clamping(local_pos: Vector3) -> Vector3:
	var intended_pos: Vector3 = local_pos
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

			if puck.carrier == self:
				var squeeze: float = intended_pos.length() - local_pos.length()
				if squeeze > wall_squeeze_threshold:
					var wall_normal: Vector3 = stick_raycast.get_collision_normal()
					if wall_normal.length() > 0.0:
						puck.release(wall_normal.normalized(), 3.0)
					else:
						var nudge: Vector3 = global_transform.basis * (-to_blade.normalized())
						puck.release(nudge.normalized(), 3.0)

	return local_pos

# ── Upper Body ────────────────────────────────────────────────────────────────
func _apply_upper_body(delta: float) -> void:
	if _state == State.SLAPPER_CHARGE_WITH_PUCK:
		return

	var target_angle: float = 0.0

	if _state == State.WRISTER_AIM:
		# Blade direction drives upper body twist during wrister
		var local_blade: Vector3 = blade.position - shoulder.position
		local_blade.y = 0.0
		if local_blade.length() > 0.01:
			var blade_angle: float = atan2(local_blade.x, -local_blade.z)
			target_angle = -blade_angle * upper_body_twist_ratio
	elif _state not in [State.SLAPPER_CHARGE_WITHOUT_PUCK, State.FOLLOW_THROUGH]:
		# Normal skating — upper body twists toward blade
		var local_blade: Vector3 = blade.position - shoulder.position
		local_blade.y = 0.0
		if local_blade.length() > 0.01:
			var blade_angle: float = atan2(local_blade.x, -local_blade.z)
			target_angle = -blade_angle * upper_body_twist_ratio

	_upper_body_angle = lerp_angle(_upper_body_angle, target_angle, upper_body_return_speed * delta)
	upper_body.rotation.y = _upper_body_angle

# ── Facing ────────────────────────────────────────────────────────────────────
func _apply_facing(delta: float) -> void:
	# Facing locked during these states
	if _state in [State.WRISTER_AIM, State.SLAPPER_CHARGE_WITH_PUCK, State.SLAPPER_CHARGE_WITHOUT_PUCK]:
		return

	var mouse_world: Vector3 = _input.mouse_world_pos
	var to_mouse: Vector2 = Vector2(
		mouse_world.x - global_position.x,
		mouse_world.z - global_position.z
	)

	if to_mouse.length() <= move_deadzone:
		return

	if _input.facing_held:
		# Continuous facing toward mouse
		_facing = _facing.lerp(to_mouse.normalized(), rotation_speed * delta).normalized()
	elif _input.facing_pressed:
		# Fast lerp snap toward mouse
		_facing = _facing.lerp(to_mouse.normalized(), facing_snap_speed * delta).normalized()

	rotation.y = atan2(-_facing.x, -_facing.y)
	lower_body.rotation.y = 0.0

# ── Movement ──────────────────────────────────────────────────────────────────
func _apply_movement(delta: float) -> void:
	if _state == State.SLAPPER_CHARGE_WITH_PUCK:
		# Glide handled in state function
		return

	var move: Vector2 = _input.move_vector

	if move.length() > move_deadzone:
		var thrust_dir: Vector3 = Vector3(move.x, 0.0, move.y)
		velocity += thrust_dir * thrust * delta

		var speed: float = Vector2(velocity.x, velocity.z).length()
		if speed > max_speed:
			var pre_thrust_speed: float = Vector2(
				velocity.x - thrust_dir.x * thrust * delta,
				velocity.z - thrust_dir.z * thrust * delta
			).length()
			var target_speed: float = maxf(pre_thrust_speed, max_speed)
			if speed > target_speed:
				var limited: Vector2 = Vector2(velocity.x, velocity.z).normalized() * target_speed
				velocity.x = limited.x
				velocity.z = limited.y

	var horizontal_vel: Vector2 = Vector2(velocity.x, velocity.z)
	var current_friction: float = friction * brake_multiplier if _input.brake else friction
	horizontal_vel = horizontal_vel.move_toward(Vector2.ZERO, current_friction * delta)
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.y

# ── Stick Mesh ────────────────────────────────────────────────────────────────
func _update_stick_mesh() -> void:
	var stick_origin: Vector3 = shoulder.position
	var to_blade: Vector3 = blade.position - stick_origin
	stick_mesh.position = stick_origin + to_blade / 2.0
	stick_mesh.scale.z = to_blade.length()
	stick_mesh.look_at(upper_body.to_global(blade.position), Vector3.UP)

class_name SkaterController
extends Node

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
@export var puck_carry_speed_multiplier: float = 0.88
@export var backward_thrust_multiplier: float = 0.7
@export var crossover_thrust_multiplier: float = 0.85
@export var facing_lag_speed: float = 6.0

# ── Facing Tuning ─────────────────────────────────────────────────────────────
@export var facing_drag_speed: float = 3.0

# ── Blade Tuning ──────────────────────────────────────────────────────────────
@export var blade_height: float = -0.95
@export var plane_reach: float = 1.5
@export var shoulder_offset: float = 0.35
@export var blade_forehand_limit: float = 90.0
@export var blade_backhand_limit: float = 80.0
@export var max_mouse_distance: float = 4.0
@export var min_blade_reach: float = 0.3

# ── Upper Body Tuning ─────────────────────────────────────────────────────────
@export var upper_body_twist_ratio: float = 0.5
@export var upper_body_return_speed: float = 10.0

# ── Wrister Tuning ────────────────────────────────────────────────────────────
@export var min_wrister_power: float = 8.0
@export var max_wrister_power: float = 25.0
@export var max_wrister_charge_distance: float = 3.0
@export var backhand_power_coefficient: float = 0.75
@export var max_charge_direction_variance: float = 45.0
@export var quick_shot_power: float = 12.0
@export var quick_shot_threshold: float = 0.1
@export var wrister_elevation: float = 0.3

# ── Slapper Tuning ────────────────────────────────────────────────────────────
@export var min_slapper_power: float = 20.0
@export var max_slapper_power: float = 40.0
@export var max_slapper_charge_time: float = 1.0
@export var slapper_blade_x: float = 1.0
@export var slapper_blade_z: float = -0.5
@export var slapper_aim_arc: float = 45.0
@export var slapper_elevation: float = 0.15

# ── Follow Through Tuning ─────────────────────────────────────────────────────
@export var follow_through_duration: float = 0.15

# ── References ────────────────────────────────────────────────────────────────
var skater: Skater = null
var puck: Puck = null
# Injected at setup. Expected methods:
#   is_host() -> bool             — changes only per session; cached in _is_host
#   is_movement_locked() -> bool  — polled per frame
var _game_state: Node = null
var _is_host: bool = false

# ── Runtime State ─────────────────────────────────────────────────────────────
var _state: State = State.SKATING_WITHOUT_PUCK
var _facing: Vector2 = Vector2.DOWN
var _blade_relative_angle: float = 0.0
var _upper_body_angle: float = 0.0
var _is_elevated: bool = false
var _shot_dir: Vector3 = Vector3.ZERO
var _follow_through_timer: float = 0.0
var _charge_distance: float = 0.0
var _prev_blade_pos: Vector3 = Vector3.ZERO
var _prev_blade_dir: Vector3 = Vector3.ZERO
var _slapper_charge_timer: float = 0.0
var last_processed_sequence: int = 0
var has_puck: bool = false

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(assigned_skater: Skater, assigned_puck: Puck, game_state: Node) -> void:
	skater = assigned_skater
	puck = assigned_puck
	_game_state = game_state
	_is_host = game_state.is_host()
	process_physics_priority = -1  # Run before Skater.move_and_slide
	skater.body_checked_player.connect(_on_body_checked_player)
	skater.body_block_hit.connect(_on_body_block_hit)

func _on_body_checked_player(victim: Skater, impact_force: float, hit_direction: Vector3) -> void:
	if not _is_host:
		return
	puck.on_body_check(skater, victim, impact_force, hit_direction)

func _on_body_block_hit(body: Node3D) -> void:
	if not _is_host:
		return
	if not body is Puck:
		return
	puck.on_body_block(skater)

# ── Entry Point ───────────────────────────────────────────────────────────────
func _process_input(input: InputState, delta: float) -> void:
	if input.elevation_up:
		_is_elevated = true
	if input.elevation_down:
		_is_elevated = false
	skater.is_elevated = _is_elevated

	_apply_movement(input, delta)
	_apply_facing(input, delta)
	_apply_state(input, delta)
	_apply_upper_body(delta)
	skater.update_stick_mesh()

# ── Network State ─────────────────────────────────────────────────────────────
func get_network_state() -> Array:
	var state := SkaterNetworkState.new()
	state.position = skater.global_position
	state.rotation = skater.global_rotation
	state.velocity = skater.velocity
	state.blade_position = skater.get_blade_position()
	state.upper_body_rotation_y = skater.get_upper_body_rotation()
	state.facing = skater.get_facing()
	state.last_processed_sequence = last_processed_sequence
	state.is_ghost = skater.is_ghost
	return state.to_array()

func apply_network_state(state: SkaterNetworkState) -> void:
	pass  # overridden by RemoteController on client
	
signal puck_release_requested(direction: Vector3, power: float)

func _do_release(direction: Vector3, power: float) -> void:
	puck_release_requested.emit(direction, power)

# ── Puck Signals ──────────────────────────────────────────────────────────────
func on_puck_picked_up_network() -> void:
	has_puck = true
	_state = State.SKATING_WITH_PUCK
	var local_blade: Vector3 = skater.get_blade_position() - skater.shoulder.position
	_blade_relative_angle = atan2(local_blade.x, -local_blade.z)

func on_puck_released_network() -> void:
	if not has_puck:
		return
	has_puck = false
	_transition_to_skating()

func teleport_to(pos: Vector3) -> void:
	skater.global_position = pos
	skater.velocity = Vector3.ZERO

# ── State Machine ─────────────────────────────────────────────────────────────
func _apply_state(input: InputState, delta: float) -> void:
	match _state:
		State.SKATING_WITHOUT_PUCK:
			_state_skating_without_puck(input, delta)
		State.SKATING_WITH_PUCK:
			_state_skating_with_puck(input, delta)
		State.WRISTER_AIM:
			_state_wrister_aim(input, delta)
		State.SLAPPER_CHARGE_WITH_PUCK:
			_state_slapper_charge_with_puck(input, delta)
		State.SLAPPER_CHARGE_WITHOUT_PUCK:
			_state_slapper_charge_without_puck(input, delta)
		State.FOLLOW_THROUGH:
			_state_follow_through(delta)

func _state_skating_without_puck(input: InputState, delta: float) -> void:
	_apply_blade_from_mouse(input, delta)
	if input.shoot_pressed:
		_state = State.WRISTER_AIM
		_shot_dir = Vector3.ZERO
	if input.slap_pressed:
		_enter_slapper_charge()

func _state_skating_with_puck(input: InputState, delta: float) -> void:
	_apply_blade_from_mouse(input, delta)
	if input.shoot_pressed:
		_enter_wrister_aim()
	if input.slap_pressed:
		_enter_slapper_charge()

func _state_wrister_aim(input: InputState, delta: float) -> void:
	_apply_blade_from_mouse(input, delta)

	if has_puck:
		var result: Dictionary = ChargeTracking.accumulate(
				_prev_blade_pos,
				skater.get_blade_position(),
				_prev_blade_dir,
				_charge_distance,
				max_charge_direction_variance)
		_charge_distance = result.charge
		_prev_blade_dir = result.direction

	_prev_blade_pos = skater.get_blade_position()

	if not input.shoot_held:
		_release_wrister(input)

func _state_slapper_charge_with_puck(input: InputState, delta: float) -> void:
	_slapper_charge_timer += delta
	_apply_slapper_blade_position()

	var slapper_vel: Vector2 = Vector2(skater.velocity.x, skater.velocity.z)
	slapper_vel = slapper_vel.move_toward(Vector2.ZERO, friction * delta)
	skater.velocity.x = slapper_vel.x
	skater.velocity.z = slapper_vel.y

	var mouse_world: Vector3 = input.mouse_world_pos
	mouse_world.y = 0.0
	var to_mouse: Vector3 = mouse_world - skater.global_position
	to_mouse.y = 0.0
	if to_mouse.length() > move_deadzone:
		var local_dir: Vector3 = skater.global_transform.basis.inverse() * to_mouse.normalized()
		var raw_angle: float = atan2(local_dir.x, -local_dir.z)
		var clamped_angle: float = clampf(raw_angle, -deg_to_rad(slapper_aim_arc), deg_to_rad(slapper_aim_arc))
		_upper_body_angle = lerp_angle(_upper_body_angle, -clamped_angle, upper_body_return_speed * delta)
		skater.set_upper_body_rotation(_upper_body_angle)

	if not input.slap_held:
		_release_slapper(input)

func _state_slapper_charge_without_puck(input: InputState, delta: float) -> void:
	_slapper_charge_timer += delta
	_apply_slapper_blade_position()

	var mouse_world: Vector3 = input.mouse_world_pos
	mouse_world.y = 0.0
	var to_mouse: Vector2 = Vector2(
		mouse_world.x - skater.global_position.x,
		mouse_world.z - skater.global_position.z
	)
	if to_mouse.length() > move_deadzone:
		_facing = _facing.lerp(to_mouse.normalized(), rotation_speed * delta).normalized()
		skater.set_facing(_facing)

	if not input.slap_held:
		_release_slapper(input)

func _state_follow_through(delta: float) -> void:
	_apply_blade_from_relative_angle()
	_follow_through_timer -= delta
	if _follow_through_timer <= 0.0:
		_transition_to_skating()

# ── State Helpers ─────────────────────────────────────────────────────────────
func _transition_to_skating() -> void:
	if has_puck:
		_state = State.SKATING_WITH_PUCK
	else:
		_state = State.SKATING_WITHOUT_PUCK
	_shot_dir = Vector3.ZERO
	_upper_body_angle = 0.0

func _enter_wrister_aim() -> void:
	_state = State.WRISTER_AIM
	_shot_dir = Vector3.ZERO
	_charge_distance = 0.0
	_prev_blade_pos = skater.get_blade_position()
	_prev_blade_dir = Vector3.ZERO

func _enter_slapper_charge() -> void:
	_slapper_charge_timer = 0.0
	_shot_dir = Vector3.ZERO
	_upper_body_angle = 0.0
	skater.set_upper_body_rotation(0.0)
	if has_puck:
		_state = State.SLAPPER_CHARGE_WITH_PUCK
	else:
		_state = State.SLAPPER_CHARGE_WITHOUT_PUCK

func _release_wrister(input: InputState) -> void:
	if has_puck:
		var result := ShotMechanics.release_wrister(
				skater.global_position,
				input.mouse_world_pos,
				skater.upper_body_to_global(skater.get_blade_position()),
				skater.get_blade_position(),
				skater.shoulder.position,
				skater.is_left_handed,
				_is_elevated,
				_charge_distance,
				_wrister_config())
		_shot_dir = result.direction
		_do_release(result.direction, result.power)

	_state = State.FOLLOW_THROUGH
	_follow_through_timer = follow_through_duration

func _release_slapper(input: InputState) -> void:
	if has_puck:
		var result := ShotMechanics.release_slapper(
				skater.upper_body_to_global(skater.get_blade_position()),
				input.mouse_world_pos,
				_is_elevated,
				_slapper_charge_timer,
				_slapper_config())
		_shot_dir = result.direction
		_do_release(result.direction, result.power)

	_state = State.FOLLOW_THROUGH
	_follow_through_timer = follow_through_duration

func _apply_slapper_blade_position() -> void:
	var hand_sign: float = -1.0 if skater.is_left_handed else 1.0
	var pos: Vector3 = skater.shoulder.position + Vector3(hand_sign * slapper_blade_x, blade_height, slapper_blade_z)
	skater.set_blade_position(pos)

func _is_in_slapper_state() -> bool:
	return _state in [State.SLAPPER_CHARGE_WITH_PUCK, State.SLAPPER_CHARGE_WITHOUT_PUCK]

# ── Blade: From Mouse ─────────────────────────────────────────────────────────
func _apply_blade_from_mouse(input: InputState, delta: float) -> void:
	var mouse_world: Vector3 = input.mouse_world_pos
	mouse_world.y = 0.0

	var shoulder_world: Vector3 = skater.upper_body_to_global(skater.shoulder.position)
	shoulder_world.y = 0.0
	var to_mouse: Vector3 = mouse_world - shoulder_world

	if to_mouse.length() < 0.01:
		return

	var local_to_mouse: Vector3 = skater.upper_body_to_local(shoulder_world + to_mouse.normalized())
	local_to_mouse.y = 0.0
	var raw_angle: float = atan2((local_to_mouse - skater.shoulder.position).x, -(local_to_mouse - skater.shoulder.position).z)

	var hand_sign: float = -1.0 if skater.is_left_handed else 1.0
	var handed_angle: float = raw_angle * hand_sign
	var clamped_handed: float = clampf(handed_angle, -deg_to_rad(blade_backhand_limit), deg_to_rad(blade_forehand_limit))
	var clamped_angle: float = clamped_handed * hand_sign

	if not _is_in_slapper_state() and _state != State.WRISTER_AIM:
		if abs(handed_angle) > abs(clamped_handed):
			var excess: float = (handed_angle - clamped_handed) * hand_sign
			_facing = _facing.rotated(excess * facing_drag_speed * delta).normalized()
			skater.set_facing(_facing)

	var clamped_dir: Vector3 = Vector3(sin(clamped_angle), 0.0, -cos(clamped_angle))
	var t: float = clampf(to_mouse.length() / max_mouse_distance, 0.0, 1.0)
	var reach: float = lerpf(min_blade_reach, plane_reach, t)
	var clamped_target: Vector3 = skater.shoulder.position + clamped_dir * reach
	clamped_target.y = blade_height

	var intended_pos: Vector3 = clamped_target
	clamped_target = skater.clamp_blade_to_walls(clamped_target)

	if has_puck:
		var squeeze: float = skater.get_wall_squeeze(intended_pos, clamped_target)
		if ShotMechanics.should_release_on_wall_pin(squeeze, skater.wall_squeeze_threshold):
			var wall_normal: Vector3 = skater.get_blade_wall_normal()
			if wall_normal.length() > 0.0:
				_do_release(wall_normal.normalized(), 3.0)
			else:
				var nudge: Vector3 = skater.global_transform.basis * (-clamped_target.normalized())
				_do_release(nudge.normalized(), 3.0)

	skater.set_blade_position(clamped_target)
	_blade_relative_angle = clamped_angle

# ── Blade: From Stored Relative Angle ────────────────────────────────────────
func _apply_blade_from_relative_angle() -> void:
	var local_dir: Vector3 = Vector3(sin(_blade_relative_angle), 0.0, -cos(_blade_relative_angle))
	var local_target: Vector3 = skater.shoulder.position + local_dir * plane_reach
	local_target.y = blade_height
	local_target = skater.clamp_blade_to_walls(local_target)
	skater.set_blade_position(local_target)

# ── Upper Body ────────────────────────────────────────────────────────────────
func _apply_upper_body(delta: float) -> void:
	if _state == State.SLAPPER_CHARGE_WITH_PUCK:
		return

	var target_angle: float = 0.0
	var blade_pos: Vector3 = skater.get_blade_position() - skater.shoulder.position
	blade_pos.y = 0.0

	if blade_pos.length() > 0.01:
		var blade_angle: float = atan2(blade_pos.x, -blade_pos.z)
		target_angle = -blade_angle * upper_body_twist_ratio

	_upper_body_angle = lerp_angle(_upper_body_angle, target_angle, upper_body_return_speed * delta)
	skater.set_upper_body_rotation(_upper_body_angle)

# ── Facing ────────────────────────────────────────────────────────────────────
func _apply_facing(input: InputState, delta: float) -> void:
	if _state in [State.WRISTER_AIM, State.SLAPPER_CHARGE_WITH_PUCK, State.SLAPPER_CHARGE_WITHOUT_PUCK]:
		return

	if input.facing_held:
		var mouse_world: Vector3 = input.mouse_world_pos
		var to_mouse: Vector2 = Vector2(
			mouse_world.x - skater.global_position.x,
			mouse_world.z - skater.global_position.z
		)
		if to_mouse.length() > move_deadzone:
			_facing = _facing.lerp(to_mouse.normalized(), rotation_speed * delta).normalized()
	else:
		if input.move_vector.length() > move_deadzone:
			_facing = _facing.lerp(input.move_vector.normalized(), facing_lag_speed * delta).normalized()

	skater.set_facing(_facing)

# ── Movement ──────────────────────────────────────────────────────────────────
func _apply_movement(input: InputState, delta: float) -> void:
	if _state == State.SLAPPER_CHARGE_WITH_PUCK:
		return
	skater.velocity = SkaterMovementRules.apply_movement(
			skater.velocity,
			input.move_vector,
			skater.rotation.y,
			has_puck,
			input.brake,
			delta,
			_movement_config())

func _movement_config() -> Dictionary:
	return {
		"thrust": thrust,
		"friction": friction,
		"max_speed": max_speed,
		"move_deadzone": move_deadzone,
		"brake_multiplier": brake_multiplier,
		"puck_carry_speed_multiplier": puck_carry_speed_multiplier,
		"backward_thrust_multiplier": backward_thrust_multiplier,
		"crossover_thrust_multiplier": crossover_thrust_multiplier,
	}

func _wrister_config() -> Dictionary:
	return {
		"min_wrister_power": min_wrister_power,
		"max_wrister_power": max_wrister_power,
		"max_wrister_charge_distance": max_wrister_charge_distance,
		"backhand_power_coefficient": backhand_power_coefficient,
		"quick_shot_power": quick_shot_power,
		"quick_shot_threshold": quick_shot_threshold,
		"wrister_elevation": wrister_elevation,
	}

func _slapper_config() -> Dictionary:
	return {
		"min_slapper_power": min_slapper_power,
		"max_slapper_power": max_slapper_power,
		"max_slapper_charge_time": max_slapper_charge_time,
		"slapper_elevation": slapper_elevation,
	}

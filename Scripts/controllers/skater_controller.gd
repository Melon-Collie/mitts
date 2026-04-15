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
	SHOT_BLOCKING,
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

# ── Blade / Stick / Top-Hand IK Tuning ────────────────────────────────────────
# Blade Y in upper-body-local space. Locked — blade always plays along ice.
@export var blade_height: float = -0.95
# Fixed, rigid shaft length (hand to blade heel). Baseline 1.30 m ≈ adult
# senior stick shaft (butt-to-heel). The blade mesh extends forward from the
# heel; see Skater.blade_length. Total hand-to-toe is stick_length + blade_length.
@export var stick_length: float = 1.30
# Hand Y in upper-body-local space. Baseline resting position (used in the
# FAR regime). In the CLOSE regime the hand rises toward `hand_y_max` so the
# stick tilts more vertical and the blade can tuck in close to the body.
@export var hand_rest_y: float = 0.0
# Ceiling for hand Y in the CLOSE regime. When aiming very close to the
# skater, the hand rises to shorten the stick's horizontal projection; this
# cap keeps the pose anatomical (hand won't climb past chin level). With
# default stick_length = 1.30 m, hand_y_max = 0.30 → min horizontal stick
# reach ≈ 0.36 m.
@export var hand_y_max: float = 0.30
# Asymmetric ROM for the top hand (measured from shoulder in upper-body-local
# horizontal plane, expressed in "forehand side = positive angle" convention).
# Forehand cross-body reach is anatomically limited; backhand same-side reach
# allows full arm extension, supporting one-handed backhand plays.
# Note: the upper body twists toward the blade (upper_body_twist_ratio = 1.0),
# which effectively reduces how far the hand must reach in upper-body-local space
# — these values assume that twist is active.
@export var rom_forehand_angle_max_deg: float = 90.0
@export var rom_backhand_angle_max_deg: float = 120.0
@export var rom_forehand_reach_max: float = 0.45
@export var rom_backhand_reach_max: float = 0.70

# ── Bottom-Hand IK Tuning ─────────────────────────────────────────────────────
# The bottom hand is purely reactive: each tick it targets a point a short way
# down the stick shaft (from the top hand toward the blade). It releases toward
# a shoulder rest only when the blade's world angle exceeds the upper body's
# rotation limit — ensuring the hand stays connected during any normal swing.
# Never influences blade placement. See domain/rules/bottom_hand_ik.gd.
# Fraction along the shaft (0 = top hand, 1 = blade heel) that the bottom hand
# grips. ~0.25 on a 1.30 m shaft ≈ a typical hockey grip width.
@export var bottom_hand_grip_fraction: float = 0.25
# Bottom hand resting Y in upper-body-local. Same height as top hand rest.
@export var bh_hand_y: float = 0.0
# Blade world angle (from skater forward, toward backhand) at which the bottom
# hand starts releasing toward the shoulder rest. Match upper_body_max_twist_deg
# so the hand releases exactly when the body can no longer rotate to follow.
@export var bh_release_angle_deg: float = 67.0
# Degrees past bh_release_angle_deg over which the hand blends to full rest.
@export var bh_release_angle_band_deg: float = 15.0

# ── Upper Body Tuning ─────────────────────────────────────────────────────────
@export var upper_body_twist_ratio: float = 1.0
@export var upper_body_max_twist_deg: float = 67.0   # caps rotation so extreme angles don't over-rotate
@export var upper_body_return_speed: float = 10.0
@export var upper_body_lean_max_deg: float = 8.0
@export var upper_body_lean_return_speed: float = 8.0

# ── Velocity Lean Tuning ──────────────────────────────────────────────────────
@export var velocity_lean_max_deg: float = 10.0
@export var velocity_lean_speed: float = 6.0

# ── Lower Body Lag Tuning ─────────────────────────────────────────────────────
@export var lower_body_lag_max_deg: float = 20.0
@export var lower_body_lag_speed: float = 5.0

# ── Wrister Tuning ────────────────────────────────────────────────────────────
@export var min_wrister_power: float = 8.0
@export var max_wrister_power: float = 25.0
@export var max_wrister_charge_distance: float = 3.0
@export var backhand_power_coefficient: float = 0.75
@export var max_charge_direction_variance: float = 45.0
@export var quick_shot_power: float = 12.0
@export var quick_shot_threshold: float = 0.1
@export var wrister_elevation: float = 0.3

# ── Head Tracking Tuning ─────────────────────────────────────────────────────
@export var head_track_speed: float = 8.0
@export var head_track_max_deg: float = 60.0

# ── Slapper Tuning ────────────────────────────────────────────────────────────
@export var slapper_wind_up_height: float = 0.4
@export var slapper_wind_up_time: float = 0.3
@export var slapper_zone_radius: float = 0.8
@export var slapper_zone_offset_x: float = 0.8  # lateral offset toward blade side
@export var min_slapper_power: float = 20.0
@export var max_slapper_power: float = 40.0
@export var max_slapper_charge_time: float = 1.0
@export var slapper_blade_x: float = 1.0
@export var slapper_blade_z: float = -0.5
@export var slapper_aim_arc: float = 45.0
@export var slapper_elevation: float = 0.15

# ── Follow Through Tuning ─────────────────────────────────────────────────────
@export var follow_through_duration: float = 0.15
@export var wrister_follow_through_hand_y: float = 0.35
@export var wrister_follow_through_blade_lift: float = 0.20

# ── Shot-Block Tuning ─────────────────────────────────────────────────────────
@export var block_speed_multiplier: float = 0.45   # movement speed while blocking
@export var active_block_dampen: float = 0.35      # puck energy retention on active block

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
var _upper_body_lean: float = 0.0
var _velocity_lean_x: float = 0.0
var _velocity_lean_z: float = 0.0
var _lower_body_lag: float = 0.0
var _head_angle: float = 0.0
var _follow_through_is_slapper: bool = false
var _one_timer_acquired: bool = false
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
	var dampen: float = active_block_dampen if _state == State.SHOT_BLOCKING else puck.body_block_dampen
	puck.on_body_block(skater, dampen)

# ── Entry Point ───────────────────────────────────────────────────────────────
func _process_input(input: InputState, delta: float) -> void:
	if input.elevation_up:
		_is_elevated = true
	if input.elevation_down:
		_is_elevated = false
	skater.is_elevated = _is_elevated

	_apply_movement(input, delta)
	_apply_velocity_lean(delta)
	_apply_facing(input, delta)
	_apply_state(input, delta)
	# Save blade/hand world positions before upper body rotation. After the body
	# rotates toward the blade, re-expressing these in the new local frame gives
	# the bottom-hand IK the post-rotation geometry — so arm reach is evaluated
	# as if the body has fully caught up, independent of lerp speed.
	var blade_world_pre: Vector3 = skater.upper_body_to_global(skater.get_blade_position())
	var hand_world_pre: Vector3 = skater.upper_body_to_global(skater.get_top_hand_position())
	_apply_upper_body(delta)
	_apply_head_tracking(input, delta)
	skater.set_top_hand_position(skater.upper_body_to_local(hand_world_pre))
	skater.set_blade_position(skater.upper_body_to_local(blade_world_pre))
	_update_bottom_hand()
	# All mesh updates happen after upper body rotation is finalised so look_at
	# orientations are computed against the correct parent transform this frame.
	skater.update_stick_mesh()
	skater.update_arm_mesh()
	skater.update_bottom_arm_mesh()

# ── Network State ─────────────────────────────────────────────────────────────
func get_network_state() -> Array:
	var state := SkaterNetworkState.new()
	state.position = skater.global_position
	state.rotation = skater.global_rotation
	state.velocity = skater.velocity
	state.blade_position = skater.get_blade_position()
	state.top_hand_position = skater.get_top_hand_position()
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
	var local_blade: Vector3 = skater.get_blade_position() - skater.shoulder.position
	_blade_relative_angle = atan2(local_blade.x, -local_blade.z)
	if _state == State.SLAPPER_CHARGE_WITHOUT_PUCK:
		# One-timer: puck arrived during a slapper charge. Switch to the
		# with-puck charge state and flag for immediate auto-release next tick.
		skater.set_slapper_zone(false)
		skater.set_slapper_mode(true)
		_one_timer_acquired = true
		_state = State.SLAPPER_CHARGE_WITH_PUCK
	else:
		_state = State.SKATING_WITH_PUCK

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
		State.SHOT_BLOCKING:
			_state_shot_blocking(input, delta)

func _state_skating_without_puck(input: InputState, delta: float) -> void:
	if input.block_held:
		_enter_shot_block()
		return
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
	if input.block_held:
		_transition_to_skating()
		return

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
	if input.block_held:
		_cancel_slapper()
		return

	# One-timer: puck was picked up mid-charge — auto-fire immediately.
	if _one_timer_acquired:
		_one_timer_acquired = false
		_release_slapper(input)
		return

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
	if input.block_held:
		_cancel_slapper()
		return

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
	if _follow_through_is_slapper:
		_apply_slapper_follow_through()
	else:
		_apply_wrister_follow_through()
	_follow_through_timer -= delta
	if _follow_through_timer <= 0.0:
		_transition_to_skating()

func _apply_wrister_follow_through() -> void:
	var t: float = 1.0 - (_follow_through_timer / follow_through_duration)
	var arc: float = sin(t * PI)
	var stick_horiz: float = _stick_horiz()
	var local_dir := Vector3(sin(_blade_relative_angle), 0.0, -cos(_blade_relative_angle))
	var hand_pos := skater.shoulder.position
	hand_pos.y = hand_rest_y + arc * wrister_follow_through_hand_y
	var intended_target: Vector3 = hand_pos + local_dir * stick_horiz
	intended_target.y = blade_height + arc * wrister_follow_through_blade_lift
	var local_target: Vector3 = skater.clamp_blade_to_walls(intended_target)
	var clamp_delta_xz := Vector3(
		local_target.x - intended_target.x, 0.0, local_target.z - intended_target.z)
	if clamp_delta_xz.length_squared() > 0.0:
		hand_pos.x += clamp_delta_xz.x
		hand_pos.z += clamp_delta_xz.z
	skater.set_top_hand_position(hand_pos)
	skater.set_blade_position(local_target)

func _apply_slapper_follow_through() -> void:
	var t: float = 1.0 - (_follow_through_timer / follow_through_duration)
	var blade_side_sign: float = -1.0 if skater.is_left_handed else 1.0
	var shot_xz := Vector2(_shot_dir.x, _shot_dir.z)
	if shot_xz.length() > 0.001:
		shot_xz = shot_xz.normalized()
	var blade_pos := Vector3(
		skater.shoulder.position.x + blade_side_sign * slapper_blade_x + shot_xz.x * t * 0.4,
		lerpf(slapper_wind_up_height, blade_height, smoothstep(0.0, 1.0, t)),
		skater.shoulder.position.z + slapper_blade_z + shot_xz.y * t * 0.4)
	var hand_pos := Vector3(
		skater.shoulder.position.x,
		hand_rest_y + t * wrister_follow_through_hand_y,
		skater.shoulder.position.z)
	skater.set_top_hand_position(hand_pos)
	skater.set_blade_position(blade_pos)

func _state_shot_blocking(input: InputState, delta: float) -> void:
	if not input.block_held or _game_state.is_movement_locked():
		_exit_shot_block()
		return
	skater.velocity = SkaterMovementRules.apply_movement(
			skater.velocity,
			input.move_vector,
			skater.rotation.y,
			false,
			input.brake,
			delta,
			_block_movement_config())

# ── State Helpers ─────────────────────────────────────────────────────────────
func _transition_to_skating() -> void:
	if has_puck:
		_state = State.SKATING_WITH_PUCK
	else:
		_state = State.SKATING_WITHOUT_PUCK
	_shot_dir = Vector3.ZERO
	_upper_body_angle = 0.0
	_upper_body_lean = 0.0
	_velocity_lean_x = 0.0
	_velocity_lean_z = 0.0
	_lower_body_lag = 0.0
	skater.set_lower_body_lag(0.0)
	skater.set_slapper_mode(false)
	skater.set_slapper_zone(false)

func _enter_shot_block() -> void:
	_state = State.SHOT_BLOCKING
	skater.set_block_stance(true)
	# Snap facing toward puck on entry — locked for duration of stance
	var to_puck: Vector3 = puck.global_position - skater.global_position
	to_puck.y = 0.0
	if to_puck.length() > 0.01:
		_facing = Vector2(to_puck.x, to_puck.z).normalized()
		skater.set_facing(_facing)

func _exit_shot_block() -> void:
	skater.set_block_stance(false)
	_transition_to_skating()

func _enter_wrister_aim() -> void:
	_state = State.WRISTER_AIM
	_shot_dir = Vector3.ZERO
	_charge_distance = 0.0
	_prev_blade_pos = skater.get_blade_position()
	_prev_blade_dir = Vector3.ZERO

func _cancel_slapper() -> void:
	_slapper_charge_timer = 0.0
	_transition_to_skating()

func _enter_slapper_charge() -> void:
	_slapper_charge_timer = 0.0
	_shot_dir = Vector3.ZERO
	_upper_body_angle = 0.0
	_upper_body_lean = 0.0
	_velocity_lean_x = 0.0
	_velocity_lean_z = 0.0
	_lower_body_lag = 0.0
	skater.set_upper_body_rotation(0.0)
	skater.set_upper_body_lean(0.0)
	skater.set_lower_body_lean(0.0, 0.0)
	skater.set_lower_body_lag(0.0)
	if has_puck:
		skater.set_slapper_mode(true)
		_state = State.SLAPPER_CHARGE_WITH_PUCK
	else:
		# Activate the ice-level slapper zone so the puck can be detected at
		# ground level even though the blade is lifted during wind-up.
		skater.set_slapper_zone(true, slapper_zone_radius, slapper_zone_offset_x)
		_state = State.SLAPPER_CHARGE_WITHOUT_PUCK

func _release_wrister(input: InputState) -> void:
	if has_puck:
		var blade_world: Vector3 = skater.upper_body_to_global(skater.get_blade_position())
		# Aim along the stick shaft — top_hand (moving IK grip point) to blade.
		var hand_world: Vector3 = skater.upper_body_to_global(skater.get_top_hand_position())
		var aim_dir: Vector3 = blade_world - hand_world
		aim_dir.y = 0.0
		var result := ShotMechanics.release_wrister(
				skater.global_position,
				input.mouse_world_pos,
				blade_world,
				skater.get_blade_position(),
				skater.shoulder.position,
				skater.is_left_handed,
				_is_elevated,
				_charge_distance,
				_wrister_config(),
				aim_dir)
		_shot_dir = result.direction
		_do_release(result.direction, result.power)

	_follow_through_is_slapper = false
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

	_follow_through_is_slapper = true
	_state = State.FOLLOW_THROUGH
	_follow_through_timer = follow_through_duration

func _apply_slapper_blade_position() -> void:
	# Slapper has a fixed blade pose offset from the shoulder — separate from
	# the IK flow (this is a charged pre-shot pose, not player-aimed). Hand
	# sits at the shoulder XZ at `hand_rest_y`; blade XZ is offset from the
	# shoulder by slapper_blade_x/z, but its Y is pinned to `blade_height`
	# directly (not summed with shoulder.y) so the blade always lands on the
	# ice regardless of where the shoulder anchor sits vertically.
	var blade_side_sign: float = -1.0 if skater.is_left_handed else 1.0
	var wind_up_t: float = clampf(_slapper_charge_timer / slapper_wind_up_time, 0.0, 1.0)
	var current_blade_y: float = lerpf(blade_height, slapper_wind_up_height, wind_up_t)
	var pos := Vector3(
			skater.shoulder.position.x + blade_side_sign * slapper_blade_x,
			current_blade_y,
			skater.shoulder.position.z + slapper_blade_z)
	var hand_pos := Vector3(skater.shoulder.position.x, hand_rest_y, skater.shoulder.position.z)
	skater.set_top_hand_position(hand_pos)
	skater.set_blade_position(pos)

func _is_in_slapper_state() -> bool:
	return _state in [State.SLAPPER_CHARGE_WITH_PUCK, State.SLAPPER_CHARGE_WITHOUT_PUCK]

# ── Blade: From Mouse (Top-Hand IK) ───────────────────────────────────────────
# Input is treated as a desired blade position. The top hand is solved as a
# consequence, clamped to an asymmetric ROM. See domain/rules/top_hand_ik.gd.
func _apply_blade_from_mouse(input: InputState, delta: float) -> void:
	var mouse_world: Vector3 = input.mouse_world_pos
	mouse_world.y = 0.0

	var shoulder_world: Vector3 = skater.upper_body_to_global(skater.shoulder.position)
	shoulder_world.y = 0.0
	var to_mouse: Vector3 = mouse_world - shoulder_world

	if to_mouse.length() < 0.01:
		return

	# Convert mouse world position into upper-body-local XZ for the solver.
	var mouse_local: Vector3 = skater.upper_body_to_local(mouse_world)
	var desired_blade_xz := Vector2(mouse_local.x, mouse_local.z)

	var blade_side_sign: float = -1.0 if skater.is_left_handed else 1.0

	# Facing drag: if the player aims past the hand's angular ROM, rotate the
	# body so the target comes into range. Skipped during shot-aim states
	# (wrister aim / slapper charge) where the body shouldn't twist.
	if not _is_in_slapper_state() and _state != State.WRISTER_AIM:
		var shoulder_xz := Vector2(skater.shoulder.position.x, skater.shoulder.position.z)
		var delta_xz: Vector2 = desired_blade_xz - shoulder_xz
		if delta_xz.length() > 0.001:
			var angle_raw: float = atan2(delta_xz.x, -delta_xz.y)
			var angle_to_forehand: float = angle_raw * blade_side_sign
			var fore_limit: float = deg_to_rad(rom_forehand_angle_max_deg)
			var back_limit: float = deg_to_rad(rom_backhand_angle_max_deg)
			var clamped_forehand: float = clampf(angle_to_forehand, -back_limit, fore_limit)
			if not is_equal_approx(angle_to_forehand, clamped_forehand):
				var excess: float = (angle_to_forehand - clamped_forehand) * blade_side_sign
				_facing = _facing.rotated(excess * facing_drag_speed * delta).normalized()
				skater.set_facing(_facing)

	# Solve IK — returns (hand, blade) in upper-body-local space.
	var ik: Dictionary = TopHandIK.solve(
			skater.shoulder.position,
			desired_blade_xz,
			blade_side_sign,
			_ik_config())
	var hand_local: Vector3 = ik.hand
	var blade_local: Vector3 = ik.blade

	# Wall clamp on the solved blade. Wall-pin auto-release (when carrying).
	var intended_blade: Vector3 = blade_local
	var wall_clamped: Vector3 = skater.clamp_blade_to_walls(blade_local)

	if has_puck:
		var squeeze: float = skater.get_wall_squeeze(intended_blade, wall_clamped)
		if ShotMechanics.should_release_on_wall_pin(squeeze, skater.wall_squeeze_threshold):
			var wall_normal: Vector3 = skater.get_blade_wall_normal()
			if wall_normal.length() > 0.0:
				_do_release(wall_normal.normalized(), 3.0)
			else:
				var nudge: Vector3 = skater.global_transform.basis * (-wall_clamped.normalized())
				_do_release(nudge.normalized(), 3.0)

	# When the blade got pulled back by the wall clamp, slide the hand by the
	# same horizontal offset so |hand − blade| stays at stick_horiz. Prevents
	# the stick mesh from compressing; reads as "pulling the stick back".
	var clamp_delta_xz := Vector3(
			wall_clamped.x - intended_blade.x, 0.0, wall_clamped.z - intended_blade.z)
	if clamp_delta_xz.length_squared() > 0.0:
		hand_local.x += clamp_delta_xz.x
		hand_local.z += clamp_delta_xz.z

	skater.set_top_hand_position(hand_local)
	skater.set_blade_position(wall_clamped)

	# Store the blade's bearing from the shoulder for follow-through.
	var bearing: Vector3 = wall_clamped - skater.shoulder.position
	if Vector2(bearing.x, bearing.z).length() > 0.001:
		_blade_relative_angle = atan2(bearing.x, -bearing.z)

# ── Blade: From Stored Relative Angle (follow-through) ───────────────────────
# Keeps the stick length invariant: hand rests at shoulder, blade sits
# stick_horiz away along the stored bearing.
func _apply_blade_from_relative_angle() -> void:
	var stick_horiz: float = _stick_horiz()
	var local_dir := Vector3(sin(_blade_relative_angle), 0.0, -cos(_blade_relative_angle))
	var hand_pos := skater.shoulder.position
	hand_pos.y = hand_rest_y
	var intended_target: Vector3 = hand_pos + local_dir * stick_horiz
	intended_target.y = blade_height
	var local_target: Vector3 = skater.clamp_blade_to_walls(intended_target)
	# Same wall-clamp hand retraction as _apply_blade_from_mouse so follow-
	# through keeps stick length constant when pinned.
	var clamp_delta_xz := Vector3(
			local_target.x - intended_target.x, 0.0, local_target.z - intended_target.z)
	if clamp_delta_xz.length_squared() > 0.0:
		hand_pos.x += clamp_delta_xz.x
		hand_pos.z += clamp_delta_xz.z
	skater.set_top_hand_position(hand_pos)
	skater.set_blade_position(local_target)

# ── Upper Body ────────────────────────────────────────────────────────────────
func _apply_upper_body(delta: float) -> void:
	if _state in [State.SLAPPER_CHARGE_WITH_PUCK, State.SHOT_BLOCKING]:
		return

	var target_angle: float = 0.0
	var target_lean: float = 0.0
	var hand_vec := Vector2(
		skater.top_hand.position.x - skater.shoulder.position.x,
		skater.top_hand.position.z - skater.shoulder.position.z)
	var hand_reach: float = hand_vec.length()

	if hand_reach > 0.01:
		var reach_factor: float = clampf(hand_reach / rom_backhand_reach_max, 0.0, 1.0)
		# Drive twist from the blade's world direction in the skater body frame.
		# Using skater-local (not upper-body-local) gives a stable target that
		# doesn't shrink as the body rotates — the old hand-angle approach had a
		# dampening feedback loop that capped steady-state rotation at ~43% of the
		# world angle. Now the body tracks 1:1 up to upper_body_max_twist_deg.
		var blade_world: Vector3 = skater.upper_body_to_global(skater.get_blade_position())
		var to_blade: Vector3 = blade_world - skater.global_position
		to_blade.y = 0.0
		if to_blade.length() > 0.01:
			var local_dir: Vector3 = skater.global_transform.basis.inverse() * to_blade.normalized()
			var blade_angle: float = atan2(local_dir.x, -local_dir.z)
			var max_twist: float = deg_to_rad(upper_body_max_twist_deg)
			target_angle = clampf(-blade_angle * upper_body_twist_ratio, -max_twist, max_twist)
		target_lean = reach_factor * deg_to_rad(upper_body_lean_max_deg)

	_upper_body_angle = lerp_angle(_upper_body_angle, target_angle, upper_body_return_speed * delta)
	_upper_body_lean = lerpf(_upper_body_lean, target_lean, upper_body_lean_return_speed * delta)
	skater.set_upper_body_rotation(_upper_body_angle)
	skater.set_upper_body_lean(_upper_body_lean + _velocity_lean_x, _velocity_lean_z)
	skater.set_lower_body_lean(_velocity_lean_x, _velocity_lean_z)

# ── Facing ────────────────────────────────────────────────────────────────────
func _apply_facing(input: InputState, delta: float) -> void:
	if not _state in [State.WRISTER_AIM, State.SLAPPER_CHARGE_WITH_PUCK,
			State.SLAPPER_CHARGE_WITHOUT_PUCK, State.SHOT_BLOCKING]:
		var prev_angle: float = skater.rotation.y
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
		var turn_delta: float = angle_difference(prev_angle, skater.rotation.y)
		_lower_body_lag = clampf(
			_lower_body_lag - turn_delta,
			-deg_to_rad(lower_body_lag_max_deg),
			deg_to_rad(lower_body_lag_max_deg))

	# Always decay and apply — even during locked states.
	_lower_body_lag = lerpf(_lower_body_lag, 0.0, lower_body_lag_speed * delta)
	skater.set_lower_body_lag(_lower_body_lag)

# ── Head Tracking ─────────────────────────────────────────────────────────────
func _apply_head_tracking(input: InputState, delta: float) -> void:
	var mouse_local: Vector3 = skater.upper_body_to_local(input.mouse_world_pos)
	mouse_local.y = 0.0
	var target_angle: float = 0.0
	if mouse_local.length() > 0.01:
		target_angle = clampf(
			atan2(mouse_local.x, -mouse_local.z),
			-deg_to_rad(head_track_max_deg),
			deg_to_rad(head_track_max_deg))
	_head_angle = lerpf(_head_angle, target_angle, head_track_speed * delta)
	skater.set_head_angle(_head_angle)

# ── Velocity Lean ─────────────────────────────────────────────────────────────
func _apply_velocity_lean(delta: float) -> void:
	var max_speed: float = _movement_config().max_speed
	var local_vel: Vector3 = skater.global_transform.basis.inverse() * skater.velocity
	var lean_max: float = deg_to_rad(velocity_lean_max_deg)
	var target_x: float = -clampf(local_vel.z / max_speed, -1.0, 1.0) * lean_max
	var target_z: float =  clampf(local_vel.x / max_speed, -1.0, 1.0) * lean_max
	_velocity_lean_x = lerpf(_velocity_lean_x, target_x, velocity_lean_speed * delta)
	_velocity_lean_z = lerpf(_velocity_lean_z, target_z, velocity_lean_speed * delta)

# ── Movement ──────────────────────────────────────────────────────────────────
func _apply_movement(input: InputState, delta: float) -> void:
	if _state in [State.SLAPPER_CHARGE_WITH_PUCK, State.SHOT_BLOCKING]:
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

func _block_movement_config() -> Dictionary:
	var cfg: Dictionary = _movement_config()
	cfg["max_speed"] = max_speed * block_speed_multiplier
	cfg["thrust"] = thrust * block_speed_multiplier
	return cfg

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

func _ik_config() -> Dictionary:
	return {
		"stick_length": stick_length,
		"blade_y": blade_height,
		"hand_rest_y": hand_rest_y,
		"hand_y_max": hand_y_max,
		"rom_forehand_angle_max": deg_to_rad(rom_forehand_angle_max_deg),
		"rom_backhand_angle_max": deg_to_rad(rom_backhand_angle_max_deg),
		"rom_forehand_reach_max": rom_forehand_reach_max,
		"rom_backhand_reach_max": rom_backhand_reach_max,
	}

func _bottom_hand_ik_config() -> Dictionary:
	return {
		"hand_y": bh_hand_y,
		"backhand_angle": _bh_backhand_angle(),
		"release_angle_max": deg_to_rad(bh_release_angle_deg),
		"release_angle_band": deg_to_rad(bh_release_angle_band_deg),
	}

# Blade world angle toward the backhand side, in the skater's body frame.
# Returns a positive value when the blade is on the backhand side; 0 on forehand.
func _bh_backhand_angle() -> float:
	var blade_world: Vector3 = skater.upper_body_to_global(skater.get_blade_position())
	var to_blade: Vector3 = blade_world - skater.global_position
	to_blade.y = 0.0
	if to_blade.length() < 0.01:
		return 0.0
	var skater_dir: Vector3 = skater.global_transform.basis.inverse() * to_blade.normalized()
	var blade_angle: float = atan2(skater_dir.x, -skater_dir.z)
	# For a lefty the backhand side is +X (positive angle); negate blade_side_sign
	# so the result is always positive toward backhand regardless of handedness.
	var blade_side_sign: float = -1.0 if skater.is_left_handed else 1.0
	return blade_angle * -blade_side_sign

# Recompute the bottom hand pose from the current top_hand + blade positions.
# Purely reactive — does not affect blade or top-hand placement. Caller must
# have already written the top hand and blade for this tick before calling.
func _update_bottom_hand() -> void:
	var blade_local: Vector3 = skater.get_blade_position()
	var hand_local: Vector3 = skater.get_top_hand_position()
	var grip_target_xz := Vector2(
			lerpf(hand_local.x, blade_local.x, bottom_hand_grip_fraction),
			lerpf(hand_local.z, blade_local.z, bottom_hand_grip_fraction))
	var bh: Vector3 = BottomHandIK.solve(
			skater.bottom_shoulder.position,
			grip_target_xz,
			_bottom_hand_ik_config())
	skater.set_bottom_hand_position(bh)

# Horizontal projection of the stick onto the XZ plane, given the fixed
# vertical drop from hand to blade. Used by follow-through to keep stick
# length consistent with the IK solver.
func _stick_horiz() -> float:
	var drop: float = hand_rest_y - blade_height
	var sq: float = stick_length * stick_length - drop * drop
	return sqrt(maxf(sq, 0.0001))

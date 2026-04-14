class_name GoalieController
extends Node

# ── Tuning ────────────────────────────────────────────────────────────────────
@export var catches_left: bool = true

@export var depth_aggressive: float = 1.2
@export var depth_base: float = 0.6
@export var depth_conservative: float = 0.3
@export var depth_defensive: float = 0.1
@export var zone_post_z: float = 2.0
@export var zone_aggressive_z: float = 8.0
@export var zone_base_z: float = 12.0
@export var zone_conservative_z: float = 20.0
@export var depth_speed: float = 2.0

@export var shuffle_speed: float = 1.3
@export var t_push_speed: float = 3.0
@export var lateral_threshold: float = 0.3
@export var max_facing_angle: float = 70.0
@export var rotation_speed: float = 8.0
@export var rvh_transition_speed: float = 6.0

@export var reaction_delay: float = 0.10
@export var butterfly_recovery_time: float = 0.4

@export var shot_speed_threshold: float = 5.0
@export var net_half_width: float = 0.915
@export var net_margin: float = 1.0

@export var rvh_depth: float = 0.1
@export var rvh_early_angle: float = 60.0
@export var rvh_post_pad_angle: float = 15.0

@export var five_hole_base: float = 0.02
@export var five_hole_shuffle_max: float = 0.06
@export var five_hole_t_push_max: float = 0.15

@export var tracking_speed: float = 6.0
@export var part_lerp_speed: float = 6.0
@export var interpolation_delay: float = 0.1

# ── References ────────────────────────────────────────────────────────────────
var goalie: Goalie = null
var puck: Puck = null
var is_server: bool = false

# ── Goal Geometry ─────────────────────────────────────────────────────────────
var _goal_line_z: float = 0.0
var _goal_center_x: float = 0.0
var _direction_sign: int = 1

# ── State Machine ─────────────────────────────────────────────────────────────
enum State { STANDING, BUTTERFLY, RVH_LEFT, RVH_RIGHT }
var _state: State = State.STANDING

# ── Runtime ───────────────────────────────────────────────────────────────────
var _current_depth: float = 0.1
var _current_x: float = 0.0
var _target_x: float = 0.0
var _five_hole_openness: float = 0.0
var _tracked_puck_position: Vector3 = Vector3.ZERO
var _shot_timer: float = 0.0
var _recovery_timer: float = 0.0

# ── Client Interpolation ──────────────────────────────────────────────────────
var _current_time: float = 0.0
var _state_buffer: Array[BufferedGoalieState] = []

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(assigned_goalie: Goalie, assigned_puck: Puck, assigned_goal_line_z: float, assigned_is_server: bool) -> void:
	goalie = assigned_goalie
	puck = assigned_puck
	is_server = assigned_is_server
	_goal_line_z = assigned_goal_line_z
	_goal_center_x = 0.0
	_direction_sign = sign(-_goal_line_z)
	_current_x = _goal_center_x
	_target_x = _goal_center_x
	_current_depth = depth_defensive
	_tracked_puck_position = puck.global_position
	goalie.set_goalie_rotation_y(PI if _direction_sign == 1 else 0.0)
	if is_server:
		puck.puck_released.connect(_on_puck_released)

func reset_to_crease() -> void:
	_state = State.STANDING
	_current_depth = depth_defensive
	_current_x = _goal_center_x
	_target_x = _goal_center_x
	_five_hole_openness = 0.0
	_shot_timer = 0.0
	_recovery_timer = 0.0
	_tracked_puck_position = puck.global_position if puck != null else Vector3.ZERO
	goalie.set_goalie_position(_current_x, _goal_line_z + _direction_sign * _current_depth)
	goalie.set_goalie_rotation_y(PI if _direction_sign == 1 else 0.0)

# ── Process ───────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if goalie == null or puck == null:
		return
	if not is_server:
		_current_time += delta
		_interpolate()
		return
	_update_tracking(delta)
	_update_shot_timer(delta)
	_update_state(delta)
	_update_depth(delta)
	_update_position(delta)
	_update_facing(delta)
	_update_body_parts(delta)

# ── Tracking ──────────────────────────────────────────────────────────────────
func _update_tracking(delta: float) -> void:
	_tracked_puck_position = _tracked_puck_position.lerp(puck.global_position, tracking_speed * delta)

# ── Shot Timer ────────────────────────────────────────────────────────────────
func _update_shot_timer(delta: float) -> void:
	if _shot_timer <= 0.0:
		return
	_shot_timer -= delta
	if _shot_timer <= 0.0 and _state == State.STANDING:
		_state = State.BUTTERFLY
		_recovery_timer = 0.0

# ── State Machine ─────────────────────────────────────────────────────────────
func _update_state(delta: float) -> void:
	if _state != State.STANDING:
		_shot_timer = 0.0
	# Convert puck global X into goalie local X. The -Z goal goalie is rotated PI
	# so its local +X is global -X; multiplying by -_direction_sign corrects for that.
	var puck_local_x: float = (_tracked_puck_position.x - _goal_center_x) * -_direction_sign
	match _state:
		State.STANDING:
			if _is_puck_in_defensive_zone():
				_state = State.RVH_LEFT if puck_local_x < 0.0 else State.RVH_RIGHT
		State.BUTTERFLY:
			var moving_away: bool = puck.linear_velocity.z * _direction_sign > 0.0
			if puck.linear_velocity.length() < shot_speed_threshold or moving_away:
				_recovery_timer += delta
				if _recovery_timer >= butterfly_recovery_time:
					_state = State.STANDING
					_recovery_timer = 0.0
			else:
				_recovery_timer = 0.0
		State.RVH_LEFT:
			if not _is_puck_in_defensive_zone():
				_state = State.STANDING
			elif puck_local_x >= 0.0:
				_state = State.RVH_RIGHT
		State.RVH_RIGHT:
			if not _is_puck_in_defensive_zone():
				_state = State.STANDING
			elif puck_local_x < 0.0:
				_state = State.RVH_LEFT

# ── Depth ─────────────────────────────────────────────────────────────────────
func _update_depth(delta: float) -> void:
	if _state == State.RVH_LEFT or _state == State.RVH_RIGHT:
		_current_depth = lerpf(_current_depth, rvh_depth, depth_speed * delta)
		return
	if _state != State.STANDING:
		return
	var puck_z_dist: float = abs(_tracked_puck_position.z - _goal_line_z)
	var target_depth: float = GoalieBehaviorRules.target_depth_for_puck_distance(
			puck_z_dist, _depth_config())
	_current_depth = lerpf(_current_depth, target_depth, depth_speed * delta)

# ── Position ──────────────────────────────────────────────────────────────────
func _update_position(delta: float) -> void:
	match _state:
		State.STANDING:
			_update_lateral_standing(delta)
		State.BUTTERFLY:
			_update_target_x()
			_current_x = move_toward(_current_x, _target_x, shuffle_speed * 0.5 * delta)
			_five_hole_openness = lerpf(_five_hole_openness, 0.0, part_lerp_speed * delta)
		State.RVH_LEFT:
			# 0.88 = post pad local x (0.46) + pad half-height when rotated 90° (0.42)
			# positions the outer edge of the post pad flush with the post
			_current_x = move_toward(_current_x, _goal_center_x + (net_half_width - 0.88) * _direction_sign, rvh_transition_speed * delta)
		State.RVH_RIGHT:
			_current_x = move_toward(_current_x, _goal_center_x - (net_half_width - 0.88) * _direction_sign, rvh_transition_speed * delta)
	goalie.set_goalie_position(_current_x, _goal_line_z + _direction_sign * _current_depth)

func _update_target_x() -> void:
	_target_x = GoalieBehaviorRules.target_lateral_x(
			_tracked_puck_position, _goal_line_z, _goal_center_x,
			_current_depth, net_half_width)

func _update_lateral_standing(delta: float) -> void:
	_update_target_x()
	var delta_x: float = _target_x - _current_x
	var five_hole_target: float
	if abs(delta_x) < 0.01:
		_current_x = move_toward(_current_x, _target_x, shuffle_speed * delta)
		five_hole_target = five_hole_base
	elif abs(delta_x) > lateral_threshold:
		_current_x = move_toward(_current_x, _target_x, t_push_speed * delta)
		five_hole_target = five_hole_t_push_max
	else:
		_current_x = move_toward(_current_x, _target_x, shuffle_speed * delta)
		five_hole_target = five_hole_shuffle_max
	_five_hole_openness = lerpf(_five_hole_openness, five_hole_target, part_lerp_speed * delta)

# ── Facing ────────────────────────────────────────────────────────────────────
func _update_facing(delta: float) -> void:
	if _state == State.RVH_LEFT or _state == State.RVH_RIGHT:
		var target_y: float = PI if _direction_sign == 1 else 0.0
		goalie.set_goalie_rotation_y(lerp_angle(goalie.get_goalie_rotation_y(), target_y, rotation_speed * delta))
		return
	if _shot_timer > 0.0 or _state == State.BUTTERFLY:
		return
	var dx: float = _tracked_puck_position.x - goalie.global_position.x
	var dz: float = _tracked_puck_position.z - goalie.global_position.z
	if Vector2(dx, dz).length() > 0.1:
		var base_angle: float = PI if _direction_sign == 1 else 0.0
		var target_y: float = atan2(-dx, -dz)
		var max_rad: float = deg_to_rad(max_facing_angle)
		var deviation: float = clampf(angle_difference(base_angle, target_y), -max_rad, max_rad)
		target_y = base_angle + deviation
		var new_y: float = lerp_angle(goalie.get_goalie_rotation_y(), target_y, rotation_speed * delta)
		goalie.set_goalie_rotation_y(new_y)

# ── Body Parts ────────────────────────────────────────────────────────────────
func _update_body_parts(delta: float) -> void:
	var config: GoalieBodyConfig = _get_config(_state)
	goalie.apply_body_config(config, part_lerp_speed * delta)

func _get_config(state: State) -> GoalieBodyConfig:
	var c := GoalieBodyConfig.new()
	match state:
		State.STANDING:
			c.left_pad_pos  = Vector3(-0.22 - _five_hole_openness, 0.44, -0.20)
			c.left_pad_rot  = Vector3(0.0, 0.0, -12.0)
			c.right_pad_pos = Vector3( 0.22 + _five_hole_openness, 0.44, -0.20)
			c.right_pad_rot = Vector3(0.0, 0.0,  12.0)
			c.body_pos      = Vector3(0.0,  1.16,  0.0)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3(0.0,  1.69,  0.08)
			c.head_rot      = Vector3.ZERO
			c.blocker_pos   = Vector3( 0.38, 1.24, -0.18)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = Vector3(-0.35, 1.19, -0.18)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3(0.0,  0.02,  -0.25)
			c.stick_rot     = Vector3.ZERO
		State.BUTTERFLY:
			c.left_pad_pos  = Vector3(-0.42, 0.14, -0.20)
			c.left_pad_rot  = Vector3(0.0, 0.0, -90.0)
			c.right_pad_pos = Vector3( 0.42, 0.14, -0.20)
			c.right_pad_rot = Vector3(0.0, 0.0,  90.0)
			c.body_pos      = Vector3(0.0,  0.46,  0.0)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3(0.0,  0.99,  0.08)
			c.head_rot      = Vector3.ZERO
			c.blocker_pos   = Vector3( 0.46, 0.49, -0.18)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = Vector3(-0.42, 0.44, -0.18)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3(0.0,  0.02,  -0.30)
			c.stick_rot     = Vector3.ZERO
		State.RVH_LEFT:
			c.left_pad_pos  = Vector3(-0.46, 0.14, 0.0)
			c.left_pad_rot  = Vector3(0.0, rvh_post_pad_angle, -90.0)
			c.right_pad_pos = Vector3(-0.05, 0.33, 0.0)
			c.right_pad_rot = Vector3(0.0, 0.0,  60.0)
			c.body_pos      = Vector3(-0.52, 0.66,  0.05)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3(-0.52, 1.19,  0.08)
			c.head_rot      = Vector3.ZERO
			c.glove_pos     = Vector3(-0.62, 0.69, -0.18)
			c.glove_rot     = Vector3.ZERO
			c.blocker_pos   = Vector3(-0.10, 0.64, -0.18)
			c.blocker_rot   = Vector3.ZERO
			c.stick_pos     = Vector3(-0.30, 0.02, -0.20)
			c.stick_rot     = Vector3.ZERO
		State.RVH_RIGHT:
			c.right_pad_pos = Vector3( 0.46, 0.14, 0.0)
			c.right_pad_rot = Vector3(0.0, -rvh_post_pad_angle,  90.0)
			c.left_pad_pos  = Vector3( 0.05, 0.33, 0.0)
			c.left_pad_rot  = Vector3(0.0, 0.0, -60.0)
			c.body_pos      = Vector3( 0.52, 0.66,  0.05)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3( 0.52, 1.19,  0.08)
			c.head_rot      = Vector3.ZERO
			c.blocker_pos   = Vector3( 0.62, 0.69, -0.18)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = Vector3( 0.10, 0.64, -0.18)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3( 0.30, 0.02, -0.20)
			c.stick_rot     = Vector3.ZERO
	if not catches_left:
		var tmp_pos: Vector3 = c.glove_pos
		var tmp_rot: Vector3 = c.glove_rot
		c.glove_pos   = Vector3(-c.blocker_pos.x, c.blocker_pos.y, c.blocker_pos.z)
		c.glove_rot   = c.blocker_rot
		c.blocker_pos = Vector3(-tmp_pos.x, tmp_pos.y, tmp_pos.z)
		c.blocker_rot = tmp_rot
	return c

# ── Shot Detection ────────────────────────────────────────────────────────────
func _on_puck_released() -> void:
	if _state != State.STANDING:
		return
	var delay: float = GoalieBehaviorRules.detect_shot(
			puck.global_position,
			puck.linear_velocity,
			_goal_line_z,
			_goal_center_x,
			_shot_detection_config())
	if delay >= 0.0:
		_shot_timer = delay

# ── State Serialization ───────────────────────────────────────────────────────
func get_state() -> Array:
	var s := GoalieNetworkState.new()
	s.position_x = goalie.global_position.x
	s.position_z = goalie.global_position.z
	s.rotation_y = goalie.get_goalie_rotation_y()
	s.state_enum = _state as int
	s.five_hole_openness = _five_hole_openness
	return s.to_array()

func apply_state(network_state: GoalieNetworkState) -> void:
	if is_server:
		return
	var buffered := BufferedGoalieState.new()
	buffered.timestamp = _current_time
	buffered.state = network_state
	_state_buffer.append(buffered)
	if _state_buffer.size() > 10:
		_state_buffer.pop_front()

func _interpolate() -> void:
	var render_time: float = _current_time - interpolation_delay
	if _state_buffer.size() < 2:
		return
	var from_state: BufferedGoalieState = null
	var to_state: BufferedGoalieState = null
	for i in range(_state_buffer.size() - 1):
		var a: BufferedGoalieState = _state_buffer[i]
		var b: BufferedGoalieState = _state_buffer[i + 1]
		if a.timestamp <= render_time and render_time <= b.timestamp:
			from_state = a
			to_state = b
			break
	if from_state == null or to_state == null:
		_apply_network_state(_state_buffer.back().state)
		return
	var t: float = clampf(
		(render_time - from_state.timestamp) / (to_state.timestamp - from_state.timestamp),
		0.0, 1.0)
	var interpolated := GoalieNetworkState.new()
	interpolated.position_x = lerpf(from_state.state.position_x, to_state.state.position_x, t)
	interpolated.position_z = lerpf(from_state.state.position_z, to_state.state.position_z, t)
	interpolated.rotation_y = lerp_angle(from_state.state.rotation_y, to_state.state.rotation_y, t)
	interpolated.five_hole_openness = lerpf(from_state.state.five_hole_openness, to_state.state.five_hole_openness, t)
	interpolated.state_enum = to_state.state.state_enum
	_apply_network_state(interpolated)
	while _state_buffer.size() > 2 and _state_buffer[1].timestamp < render_time:
		_state_buffer.pop_front()

func _apply_network_state(s: GoalieNetworkState) -> void:
	goalie.set_goalie_position(s.position_x, s.position_z)
	goalie.set_goalie_rotation_y(s.rotation_y)
	_five_hole_openness = s.five_hole_openness
	var config := _get_config(s.state_enum as State)
	goalie.apply_body_config(config, 1.0)

# ── Helpers ───────────────────────────────────────────────────────────────────
func _is_puck_in_defensive_zone() -> bool:
	return GoalieBehaviorRules.is_puck_in_defensive_zone(
			_tracked_puck_position, _goal_line_z, _goal_center_x,
			_direction_sign, _defensive_zone_config())

# ── Rule configs ──────────────────────────────────────────────────────────────
func _shot_detection_config() -> Dictionary:
	return {
		"shot_speed_threshold": shot_speed_threshold,
		"net_half_width": net_half_width,
		"net_margin": net_margin,
		"reaction_delay": reaction_delay,
	}

func _defensive_zone_config() -> Dictionary:
	return {
		"zone_post_z": zone_post_z,
		"rvh_early_angle": rvh_early_angle,
	}

func _depth_config() -> Dictionary:
	return {
		"zone_post_z": zone_post_z,
		"zone_aggressive_z": zone_aggressive_z,
		"zone_base_z": zone_base_z,
		"zone_conservative_z": zone_conservative_z,
		"depth_aggressive": depth_aggressive,
		"depth_base": depth_base,
		"depth_conservative": depth_conservative,
		"depth_defensive": depth_defensive,
	}

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
@export var rvh_early_angle: float = 80.0
@export var rvh_post_pad_angle: float = 15.0

@export var five_hole_base: float = 0.02
@export var five_hole_shuffle_max: float = 0.06
@export var five_hole_t_push_max: float = 0.15

@export var extrapolation_max_ms: float = 50.0
@export var tracking_speed: float = 6.0
@export var part_lerp_speed: float = 6.0
@export var reaction_lerp_speed: float = 18.0
@export var recovery_lerp_speed: float = 3.0
@export var interpolation_delay: float = Constants.NETWORK_INTERPOLATION_DELAY

@export var low_shot_threshold: float = 0.45
@export var elevated_threshold: float = 0.45
@export var react_hand_y_min: float = 0.50
@export var react_hand_y_max: float = 1.55
@export var react_hand_z: float = -0.28

@export var pressure_butterfly_distance: float = 2.5
@export var pressure_velocity_threshold: float = 1.0
@export var pressure_lateral_margin: float = 0.5

@export var butterfly_rotation_speed: float = 4.0
@export var butterfly_max_facing_angle: float = 25.0
@export var butterfly_slide_speed: float = 3.5
@export var five_hole_butterfly_move_max: float = 0.18

# ── References ────────────────────────────────────────────────────────────────
signal state_transitioned(team_id: int, new_state: int)
signal shot_reaction_started(team_id: int, impact_x: float, impact_y: float, is_elevated: bool)

var goalie: Goalie = null
var puck: Puck = null
var is_server: bool = false
var team_id: int = -1

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
var _reacting_to_shot: bool = false
var _shot_impact_x: float = 0.0
var _shot_impact_y: float = 0.0
var _shot_is_elevated: bool = false
var _recovering_from_butterfly: bool = false
var _prev_puck_position: Vector3 = Vector3.ZERO
var _puck_approach_velocity: float = 0.0

# ── Client Interpolation ──────────────────────────────────────────────────────
var _current_time: float = 0.0
var _state_buffer: Array[BufferedGoalieState] = []
var is_extrapolating: bool = false
var _transition_override_state: int = -1
var _transition_override_until: float = 0.0
var _client_reaction_timer: float = 0.0

func get_buffer_depth() -> int:
	return _state_buffer.size()

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
	_prev_puck_position = puck.global_position
	goalie.set_goalie_rotation_y(PI if _direction_sign == 1 else 0.0)
	if is_server:
		puck.puck_released.connect(_on_puck_released)

func is_butterfly() -> bool:
	return _state == State.BUTTERFLY

func reset_to_crease() -> void:
	_state = State.STANDING
	_current_depth = depth_defensive
	_current_x = _goal_center_x
	_target_x = _goal_center_x
	_five_hole_openness = 0.0
	_shot_timer = 0.0
	_recovery_timer = 0.0
	_reacting_to_shot = false
	_shot_impact_x = 0.0
	_shot_impact_y = 0.0
	_shot_is_elevated = false
	_recovering_from_butterfly = false
	_puck_approach_velocity = 0.0
	_tracked_puck_position = puck.global_position if puck != null else Vector3.ZERO
	_prev_puck_position = _tracked_puck_position
	goalie.set_goalie_position(_current_x, _goal_line_z + _direction_sign * _current_depth)
	goalie.set_goalie_rotation_y(PI if _direction_sign == 1 else 0.0)

# ── Process ───────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if goalie == null or puck == null:
		return
	if not is_server:
		_current_time += delta
		if _client_reaction_timer > 0.0:
			_client_reaction_timer -= delta
			if _client_reaction_timer <= 0.0:
				_reacting_to_shot = false
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
	# Approach velocity from raw position delta — works for carried puck too (linear_velocity is ~0).
	var dz: float = (puck.global_position.z - _prev_puck_position.z) * -_direction_sign
	_puck_approach_velocity = dz / maxf(delta, 0.0001)
	_prev_puck_position = puck.global_position
	if not _reacting_to_shot:
		return
	# Re-project each frame so impact position stays accurate (handles bounces, deflections).
	# detect_shot returns is_shot=false if puck slowed or moved away from net — clears reaction.
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
			puck.global_position, puck.linear_velocity,
			_goal_line_z, _goal_center_x, _shot_detection_config())
	if not result.is_shot:
		_reacting_to_shot = false
		_shot_is_elevated = false
		return
	_shot_impact_x = result.impact_x
	_shot_impact_y = result.impact_y
	# If an elevated shot has since hit the ice and is now tracking low, drop butterfly.
	if _shot_is_elevated and result.is_low and _shot_timer <= 0.0:
		_shot_is_elevated = false
		_shot_timer = reaction_delay

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
	var prev_state := _state
	if _state != State.STANDING:
		_shot_timer = 0.0
	# Convert puck global X into goalie local X. The -Z goal goalie is rotated PI
	# so its local +X is global -X; multiplying by -_direction_sign corrects for that.
	var puck_local_x: float = (_tracked_puck_position.x - _goal_center_x) * -_direction_sign
	match _state:
		State.STANDING:
			if _is_puck_in_defensive_zone():
				_reacting_to_shot = false
				_recovering_from_butterfly = false
				_state = State.RVH_LEFT if puck_local_x < 0.0 else State.RVH_RIGHT
			elif _is_under_pressure():
				_recovering_from_butterfly = false
				_state = State.BUTTERFLY
				_recovery_timer = 0.0
		State.BUTTERFLY:
			var moving_away: bool = puck.linear_velocity.z * _direction_sign > 0.0
			# Don't recover while a player is still charging the net.
			if _is_under_pressure():
				_recovery_timer = 0.0
			elif puck.linear_velocity.length() < shot_speed_threshold or moving_away:
				_recovery_timer += delta
				if _recovery_timer >= butterfly_recovery_time:
					_state = State.STANDING
					_recovery_timer = 0.0
					_reacting_to_shot = false
					_recovering_from_butterfly = true
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
	if _state != prev_state:
		state_transitioned.emit(team_id, _state as int)

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
			if not _reacting_to_shot:
				_update_target_x()
			# Scale slide speed by how saturated the facing angle is — rotation and
			# lateral movement are coupled in butterfly (you push to turn, not pivot).
			var base_angle: float = PI if _direction_sign == 1 else 0.0
			var dx: float = _tracked_puck_position.x - goalie.global_position.x
			var dz: float = _tracked_puck_position.z - goalie.global_position.z
			var facing_deviation: float = abs(angle_difference(base_angle, atan2(-dx, -dz)))
			var butterfly_max_rad: float = deg_to_rad(butterfly_max_facing_angle)
			var rotation_demand: float = clampf(facing_deviation / maxf(butterfly_max_rad, 0.001), 0.0, 1.0)
			var slide_speed: float = lerpf(shuffle_speed * 0.5, butterfly_slide_speed, rotation_demand)
			var remaining_x: float = abs(_target_x - _current_x)
			_current_x = move_toward(_current_x, _target_x, slide_speed * delta)
			var five_hole_target: float = five_hole_butterfly_move_max if remaining_x > 0.05 else 0.0
			_five_hole_openness = lerpf(_five_hole_openness, five_hole_target, part_lerp_speed * delta)
		State.RVH_LEFT:
			# 0.38 = outer pad reach (0.88) - 0.50 body inset toward post.
			# Body sits 0.535m from center; body parts shift +0.50 in local X to keep
			# the same world coverage (outer pad edge stays flush with the post).
			_current_x = move_toward(_current_x, _goal_center_x + (net_half_width - 0.38) * _direction_sign, rvh_transition_speed * delta)
		State.RVH_RIGHT:
			_current_x = move_toward(_current_x, _goal_center_x - (net_half_width - 0.38) * _direction_sign, rvh_transition_speed * delta)
	goalie.set_goalie_position(_current_x, _goal_line_z + _direction_sign * _current_depth)

func _update_target_x() -> void:
	_target_x = GoalieBehaviorRules.target_lateral_x(
			_tracked_puck_position, _goal_line_z, _goal_center_x,
			_current_depth, net_half_width, _direction_sign)

func _update_lateral_standing(delta: float) -> void:
	if not _reacting_to_shot:
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
	if _shot_timer > 0.0:
		return
	var dx: float = _tracked_puck_position.x - goalie.global_position.x
	var dz: float = _tracked_puck_position.z - goalie.global_position.z
	if Vector2(dx, dz).length() > 0.1:
		var base_angle: float = PI if _direction_sign == 1 else 0.0
		var target_y: float = atan2(-dx, -dz)
		var angle_cap: float = butterfly_max_facing_angle if _state == State.BUTTERFLY else max_facing_angle
		var max_rad: float = deg_to_rad(angle_cap)
		var deviation: float = clampf(angle_difference(base_angle, target_y), -max_rad, max_rad)
		target_y = base_angle + deviation
		var spd: float = butterfly_rotation_speed if _state == State.BUTTERFLY else rotation_speed
		var new_y: float = lerp_angle(goalie.get_goalie_rotation_y(), target_y, spd * delta)
		goalie.set_goalie_rotation_y(new_y)

# ── Body Parts ────────────────────────────────────────────────────────────────
func _update_body_parts(delta: float) -> void:
	var config: GoalieBodyConfig = _get_config(_state)
	var lerp_t: float
	if _reacting_to_shot or _state == State.BUTTERFLY:
		lerp_t = reaction_lerp_speed * delta
	elif _recovering_from_butterfly:
		lerp_t = recovery_lerp_speed * delta
	else:
		lerp_t = part_lerp_speed * delta
	goalie.apply_body_config(config, lerp_t)

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
			_apply_elevated_shot_reaction(c)
		State.BUTTERFLY:
			c.left_pad_pos  = Vector3(-0.42 - _five_hole_openness, 0.14, -0.20)
			c.left_pad_rot  = Vector3(0.0, 0.0, -90.0)
			c.right_pad_pos = Vector3( 0.42 + _five_hole_openness, 0.14, -0.20)
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
			_apply_elevated_shot_reaction(c)
		State.RVH_LEFT:
			c.left_pad_pos  = Vector3( 0.04, 0.14, 0.0)
			c.left_pad_rot  = Vector3(0.0, rvh_post_pad_angle, -90.0)
			c.right_pad_pos = Vector3( 0.45, 0.33, 0.0)
			c.right_pad_rot = Vector3(0.0, 0.0,  60.0)
			c.body_pos      = Vector3(-0.02, 0.66,  0.05)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3(-0.02, 1.19,  0.08)
			c.head_rot      = Vector3.ZERO
			c.glove_pos     = Vector3(-0.12, 0.69, -0.18)
			c.glove_rot     = Vector3.ZERO
			c.blocker_pos   = Vector3( 0.40, 0.64, -0.18)
			c.blocker_rot   = Vector3.ZERO
			c.stick_pos     = Vector3( 0.20, 0.02, -0.20)
			c.stick_rot     = Vector3.ZERO
		State.RVH_RIGHT:
			c.right_pad_pos = Vector3(-0.04, 0.14, 0.0)
			c.right_pad_rot = Vector3(0.0, -rvh_post_pad_angle,  90.0)
			c.left_pad_pos  = Vector3(-0.45, 0.33, 0.0)
			c.left_pad_rot  = Vector3(0.0, 0.0, -60.0)
			c.body_pos      = Vector3( 0.02, 0.66,  0.05)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3( 0.02, 1.19,  0.08)
			c.head_rot      = Vector3.ZERO
			c.blocker_pos   = Vector3( 0.12, 0.69, -0.18)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = Vector3(-0.40, 0.64, -0.18)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3(-0.20, 0.02, -0.20)
			c.stick_rot     = Vector3.ZERO
	if not catches_left:
		var tmp_pos: Vector3 = c.glove_pos
		var tmp_rot: Vector3 = c.glove_rot
		c.glove_pos   = Vector3(-c.blocker_pos.x, c.blocker_pos.y, c.blocker_pos.z)
		c.glove_rot   = c.blocker_rot
		c.blocker_pos = Vector3(-tmp_pos.x, tmp_pos.y, tmp_pos.z)
		c.blocker_rot = tmp_rot
	return c

# Move glove or blocker toward projected impact height when reacting to an
# elevated shot. shot_local_x > 0 = goalie's right = blocker side (for
# catches_left=true). Called from STANDING/BUTTERFLY branches of _get_config.
func _apply_elevated_shot_reaction(c: GoalieBodyConfig) -> void:
	if not _reacting_to_shot or not _shot_is_elevated:
		return
	var shot_local_x: float = (_shot_impact_x - _goal_center_x) * -_direction_sign
	var target_y: float = clampf(_shot_impact_y, react_hand_y_min, react_hand_y_max)
	if shot_local_x <= 0.0:
		c.glove_pos = Vector3(c.glove_pos.x, target_y, react_hand_z)
		c.glove_rot = Vector3(-25.0, 0.0, 0.0)
	else:
		c.blocker_pos = Vector3(c.blocker_pos.x, target_y, react_hand_z)
		c.blocker_rot = Vector3(-25.0, 0.0, 0.0)

# ── Shot Detection ────────────────────────────────────────────────────────────
func _on_puck_released() -> void:
	if _state != State.STANDING:
		return
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
			puck.global_position,
			puck.linear_velocity,
			_goal_line_z,
			_goal_center_x,
			_shot_detection_config())
	if not result.is_shot:
		return
	_shot_impact_x = result.impact_x
	_shot_impact_y = result.impact_y
	_shot_is_elevated = result.is_elevated
	_reacting_to_shot = true
	_recovering_from_butterfly = false  # new shot supersedes recovery mode
	shot_reaction_started.emit(team_id, _shot_impact_x, _shot_impact_y, _shot_is_elevated)
	if result.is_low:
		_shot_timer = result.reaction_delay
	# Elevated shot: stay standing, _get_config raises the glove or blocker

# ── State Serialization ───────────────────────────────────────────────────────
# Returns the typed network state object. Flattening to Array happens at the
# RPC boundary (GameManager.get_world_state), not here.
func get_state() -> GoalieNetworkState:
	var s := GoalieNetworkState.new()
	s.position_x = goalie.global_position.x
	s.position_z = goalie.global_position.z
	s.rotation_y = goalie.get_goalie_rotation_y()
	s.state_enum = _state as int
	s.five_hole_openness = _five_hole_openness
	return s

func apply_state(network_state: GoalieNetworkState) -> void:
	if is_server:
		return
	var buffered := BufferedGoalieState.new()
	buffered.timestamp = _current_time
	buffered.state = network_state
	_state_buffer.append(buffered)
	if _state_buffer.size() > 30:
		_state_buffer.pop_front()
	_adapt_interpolation_delay()

func _adapt_interpolation_delay() -> void:
	var target: float = NetworkManager.get_target_interpolation_delay()
	var change: float = lerpf(interpolation_delay, target, 0.15) - interpolation_delay
	interpolation_delay += clampf(change, -0.001, 0.005)

func _interpolate() -> void:
	var render_time: float = _current_time - interpolation_delay
	var bracket: BufferedStateInterpolator.BracketResult = BufferedStateInterpolator.find_bracket(
			_state_buffer, render_time)
	is_extrapolating = bracket != null and bracket.is_extrapolating
	if bracket == null:
		return
	var interpolated := GoalieNetworkState.new()
	if bracket.is_extrapolating:
		# GoalieNetworkState has no velocity field — hold the newest known state.
		var newest: GoalieNetworkState = bracket.to_state
		interpolated.position_x = newest.position_x
		interpolated.position_z = newest.position_z
		interpolated.rotation_y = newest.rotation_y
		interpolated.five_hole_openness = newest.five_hole_openness
		interpolated.state_enum = newest.state_enum
	else:
		var from_state: GoalieNetworkState = bracket.from_state
		var to_state: GoalieNetworkState = bracket.to_state
		var t: float = bracket.t
		interpolated.position_x = lerpf(from_state.position_x, to_state.position_x, t)
		interpolated.position_z = lerpf(from_state.position_z, to_state.position_z, t)
		interpolated.rotation_y = lerp_angle(from_state.rotation_y, to_state.rotation_y, t)
		interpolated.five_hole_openness = lerpf(from_state.five_hole_openness, to_state.five_hole_openness, t)
		interpolated.state_enum = to_state.state_enum
	_apply_network_state(interpolated)
	BufferedStateInterpolator.drop_stale(_state_buffer, render_time)

func apply_state_transition(new_state: int) -> void:
	if is_server:
		return
	_transition_override_state = new_state
	_transition_override_until = _current_time + 0.15
	if new_state == State.STANDING as int:
		_reacting_to_shot = false
		_client_reaction_timer = 0.0

func apply_shot_reaction(impact_x: float, impact_y: float, is_elevated: bool) -> void:
	if is_server:
		return
	_reacting_to_shot = true
	_shot_impact_x = impact_x
	_shot_impact_y = impact_y
	_shot_is_elevated = is_elevated
	_client_reaction_timer = 1.5

func _apply_network_state(s: GoalieNetworkState) -> void:
	goalie.set_goalie_position(s.position_x, s.position_z)
	goalie.set_goalie_rotation_y(s.rotation_y)
	_five_hole_openness = s.five_hole_openness
	var effective_state: int = s.state_enum
	if _transition_override_state >= 0:
		if _current_time < _transition_override_until:
			effective_state = _transition_override_state
		else:
			_transition_override_state = -1
	var config := _get_config(effective_state as State)
	goalie.apply_body_config(config, 1.0)

# ── Helpers ───────────────────────────────────────────────────────────────────
func _is_puck_in_defensive_zone() -> bool:
	return GoalieBehaviorRules.is_puck_in_defensive_zone(
			_tracked_puck_position, _goal_line_z, _goal_center_x,
			_direction_sign, _defensive_zone_config())

# ── Rule configs ──────────────────────────────────────────────────────────────
func _shot_detection_config() -> GoalieBehaviorRules.ShotDetectionConfig:
	var cfg := GoalieBehaviorRules.ShotDetectionConfig.new()
	cfg.shot_speed_threshold = shot_speed_threshold
	cfg.net_half_width = net_half_width
	cfg.net_margin = net_margin
	cfg.reaction_delay = reaction_delay
	cfg.low_shot_threshold = low_shot_threshold
	cfg.elevated_threshold = elevated_threshold
	return cfg

func _pressure_config() -> GoalieBehaviorRules.PressureConfig:
	var cfg := GoalieBehaviorRules.PressureConfig.new()
	cfg.pressure_butterfly_distance = pressure_butterfly_distance
	cfg.pressure_velocity_threshold = pressure_velocity_threshold
	cfg.pressure_lateral_margin = pressure_lateral_margin
	cfg.net_half_width = net_half_width
	return cfg

func _is_under_pressure() -> bool:
	return GoalieBehaviorRules.is_under_pressure(
			puck.global_position, _puck_approach_velocity,
			_goal_line_z, _goal_center_x, _pressure_config())

func _defensive_zone_config() -> GoalieBehaviorRules.DefensiveZoneConfig:
	var cfg := GoalieBehaviorRules.DefensiveZoneConfig.new()
	cfg.zone_post_z = zone_post_z
	cfg.rvh_early_angle = rvh_early_angle
	return cfg

func _depth_config() -> GoalieBehaviorRules.DepthConfig:
	var cfg := GoalieBehaviorRules.DepthConfig.new()
	cfg.zone_post_z = zone_post_z
	cfg.zone_aggressive_z = zone_aggressive_z
	cfg.zone_base_z = zone_base_z
	cfg.zone_conservative_z = zone_conservative_z
	cfg.depth_aggressive = depth_aggressive
	cfg.depth_base = depth_base
	cfg.depth_conservative = depth_conservative
	cfg.depth_defensive = depth_defensive
	return cfg

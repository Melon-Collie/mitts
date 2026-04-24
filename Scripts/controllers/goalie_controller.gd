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

@export var shuffle_speed: float = 1.0
@export var t_push_speed: float = 3.5
@export var lateral_threshold: float = 0.4
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

@export var tracking_speed: float = 6.0
@export var part_lerp_speed: float = 6.0
@export var reaction_lerp_speed: float = 18.0
@export var recovery_lerp_speed: float = 3.0

# ── Client Correction Tuning ──────────────────────────────────────────────────
@export var correction_blend: float = 0.40
@export var correction_hard_snap: float = 1.5
@export var correction_dead_zone: float = 0.02

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
@export var butterfly_slide_speed: float = 4.0
@export var five_hole_butterfly_move_max: float = 0.18

# ── Butterfly Slide Tuning ────────────────────────────────────────────────────
@export var slide_trigger_distance: float = 0.6
@export var slide_trigger_speed: float = 8.0
@export var slide_decel_distance: float = 0.5
@export var slide_settle_distance: float = 0.1
@export var slide_recommit_delay: float = 0.15
@export var five_hole_slide_max: float = 0.22

# ── Short-Side Bias Tuning ────────────────────────────────────────────────────
@export var short_side_bias: float = 0.15
@export var sharp_angle_distance: float = 5.0

# ── Hand Pose Blend Tuning ────────────────────────────────────────────────────
@export var butterfly_blocking_dist_min: float = 1.5
@export var butterfly_blocking_dist_max: float = 3.0

# ── Shot Intent Tuning ────────────────────────────────────────────────────────
@export var shot_intent_enabled: bool = false
@export var shot_intent_max_distance: float = 18.0
@export var shot_intent_commit_close: float = 0.55
@export var shot_intent_commit_mid: float = 0.75
@export var shot_intent_commit_far: float = 0.90

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
enum State { STANDING, BUTTERFLY, BUTTERFLY_SLIDE_LEFT, BUTTERFLY_SLIDE_RIGHT, RVH_LEFT, RVH_RIGHT }
var _state: State = State.STANDING

# ── Runtime ───────────────────────────────────────────────────────────────────
var _current_depth: float = 0.1
var _current_x: float = 0.0
var _target_x: float = 0.0
var _target_arc_z: float = 0.0
var _slide_target_x: float = 0.0
var _slide_recommit_timer: float = 0.0
var _velocity_x: float = 0.0
var _velocity_z: float = 0.0
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

# ── Client Simulation ─────────────────────────────────────────────────────────
var is_extrapolating: bool = false
var _client_reaction_timer: float = 0.0
var _last_server_ts: float = 0.0

func get_buffer_depth() -> int:
	return 0

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
	_target_arc_z = _goal_line_z + _direction_sign * depth_defensive
	_slide_target_x = _goal_center_x
	_current_depth = depth_defensive
	_tracked_puck_position = puck.global_position
	_prev_puck_position = puck.global_position
	goalie.set_goalie_rotation_y(PI if _direction_sign == 1 else 0.0)
	if is_server:
		puck.puck_released.connect(_on_puck_released)

func is_butterfly() -> bool:
	return _state == State.BUTTERFLY \
		or _state == State.BUTTERFLY_SLIDE_LEFT \
		or _state == State.BUTTERFLY_SLIDE_RIGHT

func reset_to_crease() -> void:
	_state = State.STANDING
	_current_depth = depth_defensive
	_current_x = _goal_center_x
	_target_x = _goal_center_x
	_target_arc_z = _goal_line_z + _direction_sign * depth_defensive
	_slide_target_x = _goal_center_x
	_slide_recommit_timer = 0.0
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
	if not is_server and _client_reaction_timer > 0.0:
		_client_reaction_timer -= delta
		if _client_reaction_timer <= 0.0:
			_reacting_to_shot = false
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
	var dz: float = (puck.global_position.z - _prev_puck_position.z) * -_direction_sign
	_puck_approach_velocity = dz / maxf(delta, 0.0001)
	_prev_puck_position = puck.global_position
	if not _reacting_to_shot or not is_server:
		return
	var result: GoalieBehaviorRules.ShotResult = GoalieBehaviorRules.detect_shot(
			puck.global_position, puck.linear_velocity,
			_goal_line_z, _goal_center_x, _shot_detection_config())
	if not result.is_shot:
		_reacting_to_shot = false
		_shot_is_elevated = false
		return
	_shot_impact_x = result.impact_x
	_shot_impact_y = result.impact_y
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
	var puck_local_x: float = (_tracked_puck_position.x - _goal_center_x) * -_direction_sign
	match _state:
		State.STANDING:
			if _is_puck_in_defensive_zone():
				_reacting_to_shot = false
				_recovering_from_butterfly = false
				_state = State.RVH_LEFT if puck_local_x < 0.0 else State.RVH_RIGHT
			else:
				var triggered_down: bool = false
				if shot_intent_enabled:
					var intent: float = _compute_shot_intent()
					var puck_z_dist: float = abs(_tracked_puck_position.z - _goal_line_z)
					var threshold: float = GoalieBehaviorRules.shot_intent_commit_threshold(
							puck_z_dist, _shot_intent_config())
					if intent >= threshold:
						_recovering_from_butterfly = false
						triggered_down = true
				if not triggered_down and _is_under_pressure():
					_recovering_from_butterfly = false
					triggered_down = true
				if triggered_down:
					_enter_down_state()
		State.BUTTERFLY:
			if _slide_recommit_timer > 0.0:
				_slide_recommit_timer -= delta
			var speed_low: bool
			var moving_away: bool
			if is_server:
				speed_low = puck.linear_velocity.length() < shot_speed_threshold
				moving_away = puck.linear_velocity.z * _direction_sign > 0.0
			else:
				speed_low = absf(_puck_approach_velocity) < shot_speed_threshold
				moving_away = _puck_approach_velocity < 0.0
			if _is_under_pressure():
				_recovery_timer = 0.0
			elif speed_low or moving_away:
				_recovery_timer += delta
				if _recovery_timer >= butterfly_recovery_time:
					_state = State.STANDING
					_recovery_timer = 0.0
					_reacting_to_shot = false
					_recovering_from_butterfly = true
			else:
				_recovery_timer = 0.0
			# Re-trigger slide if lateral gap exceeds threshold and recommit cooldown expired.
			if _slide_recommit_timer <= 0.0 and not _reacting_to_shot and _state == State.BUTTERFLY:
				_update_target_x()
				var lateral_delta: float = abs(_target_x - _current_x)
				if lateral_delta > slide_trigger_distance:
					var slide_dir_local: float = (_target_x - _current_x) * -_direction_sign
					_state = State.BUTTERFLY_SLIDE_LEFT if slide_dir_local < 0.0 else State.BUTTERFLY_SLIDE_RIGHT
					_slide_target_x = _target_x
		State.BUTTERFLY_SLIDE_LEFT, State.BUTTERFLY_SLIDE_RIGHT:
			var dist_remaining: float = abs(_slide_target_x - _current_x)
			if dist_remaining < slide_settle_distance:
				_state = State.BUTTERFLY
				_recovery_timer = 0.0
				_slide_recommit_timer = slide_recommit_delay
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

func _enter_down_state() -> void:
	_update_target_x()
	var lateral_delta: float = abs(_target_x - _current_x)
	var puck_lateral_speed: float = abs(puck.linear_velocity.x) if is_server else 0.0
	var puck_approaching: bool = _puck_approach_velocity > 2.0
	if lateral_delta > slide_trigger_distance or (puck_lateral_speed > slide_trigger_speed and puck_approaching):
		var slide_dir_local: float = (_target_x - _current_x) * -_direction_sign
		_state = State.BUTTERFLY_SLIDE_LEFT if slide_dir_local < 0.0 else State.BUTTERFLY_SLIDE_RIGHT
		_slide_target_x = _target_x
	else:
		_state = State.BUTTERFLY
	_recovery_timer = 0.0

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
	var prev_x: float = _current_x
	var prev_z: float = _goal_line_z + _direction_sign * _current_depth
	var new_z: float
	match _state:
		State.STANDING:
			_update_lateral_standing(delta)
			new_z = _target_arc_z
		State.BUTTERFLY:
			if not _reacting_to_shot:
				_update_target_x()
			var base_angle: float = PI if _direction_sign == 1 else 0.0
			var dx: float = _tracked_puck_position.x - goalie.global_position.x
			var dz: float = _tracked_puck_position.z - goalie.global_position.z
			var facing_deviation: float = abs(angle_difference(base_angle, atan2(-dx, -dz)))
			var butterfly_max_rad: float = deg_to_rad(butterfly_max_facing_angle)
			var rotation_demand: float = clampf(facing_deviation / maxf(butterfly_max_rad, 0.001), 0.0, 1.0)
			var slide_speed: float = lerpf(shuffle_speed * 0.5, butterfly_slide_speed, rotation_demand)
			var remaining_x: float = abs(_target_x - _current_x)
			_current_x = move_toward(_current_x, _target_x, slide_speed * delta)
			if is_server:
				var five_hole_target: float = five_hole_butterfly_move_max if remaining_x > 0.05 else 0.0
				_five_hole_openness = lerpf(_five_hole_openness, five_hole_target, part_lerp_speed * delta)
			new_z = _goal_line_z + _direction_sign * _current_depth
		State.BUTTERFLY_SLIDE_LEFT, State.BUTTERFLY_SLIDE_RIGHT:
			var dist_remaining: float = abs(_slide_target_x - _current_x)
			var slide_speed_cur: float = butterfly_slide_speed
			if dist_remaining < slide_decel_distance:
				slide_speed_cur *= smoothstep(0.0, slide_decel_distance, dist_remaining)
			_current_x = move_toward(_current_x, _slide_target_x, slide_speed_cur * delta)
			if is_server:
				_five_hole_openness = lerpf(_five_hole_openness, five_hole_slide_max, part_lerp_speed * delta)
			new_z = _goal_line_z + _direction_sign * _current_depth
		State.RVH_LEFT:
			_current_x = move_toward(_current_x, _goal_center_x + (net_half_width - 0.38) * _direction_sign, rvh_transition_speed * delta)
			new_z = _goal_line_z + _direction_sign * _current_depth
		State.RVH_RIGHT:
			_current_x = move_toward(_current_x, _goal_center_x - (net_half_width - 0.38) * _direction_sign, rvh_transition_speed * delta)
			new_z = _goal_line_z + _direction_sign * _current_depth
		_:
			new_z = _goal_line_z + _direction_sign * _current_depth
	if delta > 0.0:
		_velocity_x = (_current_x - prev_x) / delta
		_velocity_z = (new_z - prev_z) / delta
	goalie.set_goalie_position(_current_x, new_z)

func _update_target_x() -> void:
	var arc := GoalieBehaviorRules.target_position_on_arc(
			_tracked_puck_position, _goal_line_z, _goal_center_x,
			_current_depth, net_half_width, _direction_sign)
	_target_x = arc.x

func _update_lateral_standing(delta: float) -> void:
	if not _reacting_to_shot:
		var arc := GoalieBehaviorRules.target_position_on_arc(
				_tracked_puck_position, _goal_line_z, _goal_center_x,
				_current_depth, net_half_width, _direction_sign)
		_target_x = arc.x
		_target_arc_z = arc.y
		# Short-side bias: cheat toward near post on sharp angles
		var puck_z_dist: float = abs(_tracked_puck_position.z - _goal_line_z)
		var puck_x_dist: float = abs(_tracked_puck_position.x - _goal_center_x)
		if puck_z_dist < zone_post_z * 2.5 and puck_x_dist > net_half_width:
			var near_post_x: float = _goal_center_x + sign(_tracked_puck_position.x - _goal_center_x) * net_half_width
			_target_x = lerpf(_target_x, near_post_x, short_side_bias)
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
	if is_server:
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
		var is_down: bool = _state != State.STANDING
		var angle_cap: float = butterfly_max_facing_angle if is_down else max_facing_angle
		var max_rad: float = deg_to_rad(angle_cap)
		var deviation: float = clampf(angle_difference(base_angle, target_y), -max_rad, max_rad)
		target_y = base_angle + deviation
		var spd: float = butterfly_rotation_speed if is_down else rotation_speed
		var new_y: float = lerp_angle(goalie.get_goalie_rotation_y(), target_y, spd * delta)
		goalie.set_goalie_rotation_y(new_y)

# ── Body Parts ────────────────────────────────────────────────────────────────
func _update_body_parts(delta: float) -> void:
	var config: GoalieBodyConfig = _get_config(_state)
	var lerp_t: float
	if _reacting_to_shot or _state == State.BUTTERFLY \
			or _state == State.BUTTERFLY_SLIDE_LEFT or _state == State.BUTTERFLY_SLIDE_RIGHT:
		lerp_t = reaction_lerp_speed * delta
	elif _recovering_from_butterfly:
		lerp_t = recovery_lerp_speed * delta
	else:
		lerp_t = part_lerp_speed * delta
	goalie.apply_body_config(config, lerp_t)

func _get_config(state: State) -> GoalieBodyConfig:
	var c := GoalieBodyConfig.new()
	# catches_left swap for slide states: swap effective state so the drive/lead
	# leg designations match the actual slide direction for right-catching goalies.
	var effective_state := state
	if not catches_left:
		match state:
			State.BUTTERFLY_SLIDE_LEFT:  effective_state = State.BUTTERFLY_SLIDE_RIGHT
			State.BUTTERFLY_SLIDE_RIGHT: effective_state = State.BUTTERFLY_SLIDE_LEFT
	match effective_state:
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
			# Hand pose blends between reaction butterfly (hands up/out for shot reach)
			# and blocking butterfly (hands low/tucked on pads) based on puck distance.
			var puck_dist: float = _tracked_puck_position.distance_to(goalie.global_position)
			var blocking_blend: float = 1.0 - smoothstep(butterfly_blocking_dist_min,
					butterfly_blocking_dist_max, puck_dist)
			var reaction_blocker_pos := Vector3( 0.46, 0.49, -0.18)
			var reaction_glove_pos   := Vector3(-0.42, 0.44, -0.18)
			var blocking_blocker_pos := Vector3( 0.28, 0.22, -0.10)
			var blocking_glove_pos   := Vector3(-0.28, 0.22, -0.10)
			c.left_pad_pos  = Vector3(-0.42 - _five_hole_openness, 0.14, -0.20)
			c.left_pad_rot  = Vector3(0.0, 0.0, -90.0)
			c.right_pad_pos = Vector3( 0.42 + _five_hole_openness, 0.14, -0.20)
			c.right_pad_rot = Vector3(0.0, 0.0,  90.0)
			c.body_pos      = Vector3(0.0,  0.46,  0.0)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3(0.0,  0.99,  0.08)
			c.head_rot      = Vector3.ZERO
			c.blocker_pos   = reaction_blocker_pos.lerp(blocking_blocker_pos, blocking_blend)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = reaction_glove_pos.lerp(blocking_glove_pos, blocking_blend)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3(0.0,  0.02,  -0.30)
			c.stick_rot     = Vector3.ZERO
			_apply_elevated_shot_reaction(c)
		State.BUTTERFLY_SLIDE_LEFT:
			# Drive leg = right pad (push), lead leg = left pad (gliding toward shot lane).
			# Five-hole opens slightly (drive push separates pads).
			# Hands stay in reaction zone — goalie is reading the shot during the slide.
			# TODO: tune these values in-editor against the actual scene (spec §11).
			c.left_pad_pos  = Vector3(-0.42 - _five_hole_openness, 0.14, -0.20)
			c.left_pad_rot  = Vector3(0.0, 0.0, -90.0)
			c.right_pad_pos = Vector3( 0.42 + _five_hole_openness, 0.20, -0.18)
			c.right_pad_rot = Vector3(10.0, 0.0,  80.0)
			c.body_pos      = Vector3(-0.04, 0.46,  0.0)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3(-0.02, 0.99,  0.08)
			c.head_rot      = Vector3.ZERO
			c.blocker_pos   = Vector3( 0.46, 0.49, -0.18)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = Vector3(-0.42, 0.44, -0.18)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3(0.0,  0.02,  -0.30)
			c.stick_rot     = Vector3.ZERO
			_apply_elevated_shot_reaction(c)
		State.BUTTERFLY_SLIDE_RIGHT:
			# Drive leg = left pad (push), lead leg = right pad (gliding toward shot lane).
			# TODO: tune these values in-editor against the actual scene (spec §11).
			c.left_pad_pos  = Vector3(-0.42 - _five_hole_openness, 0.20, -0.18)
			c.left_pad_rot  = Vector3(10.0, 0.0, -80.0)
			c.right_pad_pos = Vector3( 0.42 + _five_hole_openness, 0.14, -0.20)
			c.right_pad_rot = Vector3(0.0, 0.0,  90.0)
			c.body_pos      = Vector3( 0.04, 0.46,  0.0)
			c.body_rot      = Vector3.ZERO
			c.head_pos      = Vector3( 0.02, 0.99,  0.08)
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
	# catches_left swap: flip blocker/glove X for right-catching goalies.
	# Skip for slide states — their effective_state mapping already handles handedness.
	if not catches_left and state != State.BUTTERFLY_SLIDE_LEFT and state != State.BUTTERFLY_SLIDE_RIGHT:
		var tmp_pos: Vector3 = c.glove_pos
		var tmp_rot: Vector3 = c.glove_rot
		c.glove_pos   = Vector3(-c.blocker_pos.x, c.blocker_pos.y, c.blocker_pos.z)
		c.glove_rot   = c.blocker_rot
		c.blocker_pos = Vector3(-tmp_pos.x, tmp_pos.y, tmp_pos.z)
		c.blocker_rot = tmp_rot
	return c

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
	_recovering_from_butterfly = false
	shot_reaction_started.emit(team_id, _shot_impact_x, _shot_impact_y, _shot_is_elevated)
	if result.is_low:
		_shot_timer = result.reaction_delay

# ── State Serialization ───────────────────────────────────────────────────────
func get_state() -> GoalieNetworkState:
	var s := GoalieNetworkState.new()
	s.position_x = goalie.global_position.x
	s.position_z = goalie.global_position.z
	s.rotation_y = goalie.get_goalie_rotation_y()
	s.state_enum = _state as int
	s.five_hole_openness = _five_hole_openness
	s.velocity_x = _velocity_x
	s.velocity_z = _velocity_z
	return s

func apply_state(network_state: GoalieNetworkState, host_ts: float) -> void:
	if is_server:
		return
	if host_ts <= _last_server_ts:
		return
	_last_server_ts = host_ts
	var elapsed: float = clampf(NetworkManager.estimated_host_time() - host_ts, 0.0, 0.15)
	var predicted_x: float = network_state.position_x + network_state.velocity_x * elapsed
	var predicted_z: float = network_state.position_z + network_state.velocity_z * elapsed
	var server_depth: float = (predicted_z - _goal_line_z) * _direction_sign
	var client_z: float = _goal_line_z + _direction_sign * _current_depth
	var dist: float = Vector2(_current_x - predicted_x, client_z - predicted_z).length()
	if dist > correction_hard_snap:
		_current_x = predicted_x
		_current_depth = server_depth
	elif dist > correction_dead_zone:
		_current_x = lerpf(_current_x, predicted_x, correction_blend)
		_current_depth = lerpf(_current_depth, server_depth, correction_blend)
	_five_hole_openness = lerpf(_five_hole_openness, network_state.five_hole_openness, 0.80)

func apply_state_transition(new_state: int) -> void:
	if is_server:
		return
	_state = new_state as State
	if new_state == State.STANDING as int:
		_reacting_to_shot = false
		_client_reaction_timer = 0.0
		_shot_timer = 0.0
	elif new_state == State.BUTTERFLY_SLIDE_LEFT as int or new_state == State.BUTTERFLY_SLIDE_RIGHT as int:
		# Latch slide target from current _target_x so client slide runs in the
		# right direction — server will position-correct via apply_state broadcasts.
		_slide_target_x = _target_x

func apply_shot_reaction(impact_x: float, impact_y: float, is_elevated: bool) -> void:
	if is_server:
		return
	_reacting_to_shot = true
	_shot_impact_x = impact_x
	_shot_impact_y = impact_y
	_shot_is_elevated = is_elevated
	_client_reaction_timer = 1.5
	if not is_elevated and _state == State.STANDING:
		_shot_timer = reaction_delay

# ── Helpers ───────────────────────────────────────────────────────────────────
func _compute_shot_intent() -> float:
	var carrier: Skater = puck.get_carrier() if puck != null else null
	if carrier == null:
		return 0.0
	return GoalieBehaviorRules.compute_shot_intent(
			carrier.global_position,
			carrier.rotation.y,
			carrier.velocity,
			-1.0,
			_tracked_puck_position,
			_goal_line_z, _goal_center_x,
			_shot_intent_config())

func _is_puck_in_defensive_zone() -> bool:
	return GoalieBehaviorRules.is_puck_in_defensive_zone(
			_tracked_puck_position, _goal_line_z, _goal_center_x,
			_direction_sign, _defensive_zone_config())

func _is_under_pressure() -> bool:
	return GoalieBehaviorRules.is_under_pressure(
			puck.global_position, _puck_approach_velocity,
			_goal_line_z, _goal_center_x, _pressure_config())

# ── Rule Configs ──────────────────────────────────────────────────────────────
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

func _shot_intent_config() -> GoalieBehaviorRules.ShotIntentConfig:
	var cfg := GoalieBehaviorRules.ShotIntentConfig.new()
	cfg.shot_intent_max_distance = shot_intent_max_distance
	cfg.shot_intent_commit_close = shot_intent_commit_close
	cfg.shot_intent_commit_mid   = shot_intent_commit_mid
	cfg.shot_intent_commit_far   = shot_intent_commit_far
	return cfg

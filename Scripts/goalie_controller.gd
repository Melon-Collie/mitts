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
@export var depth_speed: float = 3.0

@export var shuffle_speed: float = 2.0
@export var t_push_speed: float = 5.0
@export var lateral_threshold: float = 0.3
@export var max_facing_angle: float = 70.0
@export var rotation_speed: float = 8.0
@export var rvh_transition_speed: float = 6.0

@export var reaction_delay: float = 0.15
@export var butterfly_recovery_time: float = 0.4

@export var shot_speed_threshold: float = 5.0
@export var net_half_width: float = 0.915
@export var net_margin: float = 1.0

@export var five_hole_base: float = 0.02
@export var five_hole_shuffle_max: float = 0.06
@export var five_hole_t_push_max: float = 0.15

@export var part_lerp_speed: float = 12.0

# ── References ────────────────────────────────────────────────────────────────
var goalie: Goalie = null
var puck: Puck = null

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
var _shot_timer: float = 0.0
var _recovery_timer: float = 0.0

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(assigned_goalie: Goalie, assigned_puck: Puck, assigned_goal_line_z: float) -> void:
	goalie = assigned_goalie
	puck = assigned_puck
	_goal_line_z = assigned_goal_line_z
	_goal_center_x = 0.0
	_direction_sign = sign(-_goal_line_z)
	_current_x = _goal_center_x
	_target_x = _goal_center_x
	_current_depth = depth_defensive
	goalie.set_goalie_rotation_y(PI if _direction_sign == 1 else 0.0)
	puck.puck_released.connect(_on_puck_released)

# ── Process ───────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if goalie == null or puck == null:
		return
	_update_shot_timer(delta)
	_update_state(delta)
	_update_depth(delta)
	_update_position(delta)
	_update_facing(delta)
	_update_body_parts(delta)

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
	match _state:
		State.STANDING:
			if _is_puck_behind_goal():
				_state = State.RVH_LEFT if puck.global_position.x < _goal_center_x else State.RVH_RIGHT
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
			if not _is_puck_behind_goal():
				_state = State.STANDING
			elif puck.global_position.x >= _goal_center_x:
				_state = State.RVH_RIGHT
		State.RVH_RIGHT:
			if not _is_puck_behind_goal():
				_state = State.STANDING
			elif puck.global_position.x < _goal_center_x:
				_state = State.RVH_LEFT

# ── Depth ─────────────────────────────────────────────────────────────────────
func _update_depth(delta: float) -> void:
	if _state == State.RVH_LEFT or _state == State.RVH_RIGHT:
		_current_depth = lerpf(_current_depth, 0.0, depth_speed * delta)
		return
	if _state != State.STANDING:
		return
	var puck_z_dist: float = abs(puck.global_position.z - _goal_line_z)
	var target_depth: float
	if puck_z_dist <= zone_post_z:
		var t: float = puck_z_dist / zone_post_z
		target_depth = lerpf(depth_defensive, depth_aggressive, t)
	elif puck_z_dist <= zone_aggressive_z:
		target_depth = depth_aggressive
	elif puck_z_dist <= zone_base_z:
		var t: float = (puck_z_dist - zone_aggressive_z) / (zone_base_z - zone_aggressive_z)
		target_depth = lerpf(depth_aggressive, depth_base, t)
	elif puck_z_dist <= zone_conservative_z:
		var t: float = (puck_z_dist - zone_base_z) / (zone_conservative_z - zone_base_z)
		target_depth = lerpf(depth_base, depth_conservative, t)
	else:
		var t: float = clampf((puck_z_dist - zone_conservative_z) / zone_conservative_z, 0.0, 1.0)
		target_depth = lerpf(depth_conservative, depth_defensive, t)
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
			_current_x = move_toward(_current_x, _goal_center_x - net_half_width, rvh_transition_speed * delta)
		State.RVH_RIGHT:
			_current_x = move_toward(_current_x, _goal_center_x + net_half_width, rvh_transition_speed * delta)
	goalie.set_goalie_position(_current_x, _goal_line_z + _direction_sign * _current_depth)

func _update_target_x() -> void:
	var puck_z_dist: float = abs(puck.global_position.z - _goal_line_z)
	if puck_z_dist > 0.01:
		_target_x = _goal_center_x + (puck.global_position.x - _goal_center_x) * (_current_depth / puck_z_dist)
	else:
		_target_x = _goal_center_x
	_target_x = clampf(_target_x, _goal_center_x - net_half_width, _goal_center_x + net_half_width)

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
	var dx: float = puck.global_position.x - goalie.global_position.x
	var dz: float = puck.global_position.z - goalie.global_position.z
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
			c.left_pad_pos  = Vector3(-0.22 - _five_hole_openness, 0.0, 0.0)
			c.left_pad_rot  = Vector3(0.0, 0.0,  12.0)
			c.right_pad_pos = Vector3( 0.22 + _five_hole_openness, 0.0, 0.0)
			c.right_pad_rot = Vector3(0.0, 0.0, -12.0)
			c.body_pos      = Vector3(0.0, 0.50, 0.0)
			c.body_rot      = Vector3.ZERO
			c.blocker_pos   = Vector3(-0.35, 0.43, 0.0)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = Vector3( 0.40, 0.48, 0.0)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3(0.0, 0.02, -0.25)
			c.stick_rot     = Vector3.ZERO
		State.BUTTERFLY:
			c.left_pad_pos  = Vector3(-0.33, 0.0, 0.0)
			c.left_pad_rot  = Vector3(0.0, 0.0,  90.0)
			c.right_pad_pos = Vector3( 0.33, 0.0, 0.0)
			c.right_pad_rot = Vector3(0.0, 0.0, -90.0)
			c.body_pos      = Vector3(0.0, 0.28, 0.0)
			c.body_rot      = Vector3.ZERO
			c.blocker_pos   = Vector3(-0.40, 0.30, 0.0)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = Vector3( 0.45, 0.35, 0.0)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3(0.0, 0.02, -0.30)
			c.stick_rot     = Vector3.ZERO
		State.RVH_LEFT:
			c.left_pad_pos  = Vector3(-0.50, 0.0, 0.0)
			c.left_pad_rot  = Vector3(0.0, 0.0,  90.0)
			c.right_pad_pos = Vector3(-0.18, 0.0, 0.0)
			c.right_pad_rot = Vector3(0.0, 0.0,   5.0)
			c.body_pos      = Vector3(-0.30, 0.42, 0.0)
			c.body_rot      = Vector3.ZERO
			c.glove_pos     = Vector3(-0.48, 0.45, 0.0)
			c.glove_rot     = Vector3.ZERO
			c.blocker_pos   = Vector3( 0.0,  0.40, 0.0)
			c.blocker_rot   = Vector3.ZERO
			c.stick_pos     = Vector3(-0.25, 0.02, -0.20)
			c.stick_rot     = Vector3.ZERO
		State.RVH_RIGHT:
			c.left_pad_pos  = Vector3( 0.18, 0.0, 0.0)
			c.left_pad_rot  = Vector3(0.0, 0.0,  -5.0)
			c.right_pad_pos = Vector3( 0.50, 0.0, 0.0)
			c.right_pad_rot = Vector3(0.0, 0.0, -90.0)
			c.body_pos      = Vector3( 0.30, 0.42, 0.0)
			c.body_rot      = Vector3.ZERO
			c.blocker_pos   = Vector3( 0.48, 0.45, 0.0)
			c.blocker_rot   = Vector3.ZERO
			c.glove_pos     = Vector3( 0.0,  0.40, 0.0)
			c.glove_rot     = Vector3.ZERO
			c.stick_pos     = Vector3( 0.25, 0.02, -0.20)
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
	var vel: Vector3 = puck.linear_velocity
	if vel.length() < shot_speed_threshold:
		return
	if abs(vel.z) < 0.001:
		return
	var t_to_goal: float = (_goal_line_z - puck.global_position.z) / vel.z
	if t_to_goal <= 0.0:
		return
	var projected_x: float = puck.global_position.x + vel.x * t_to_goal
	if abs(projected_x - _goal_center_x) > net_half_width + net_margin:
		return
	_shot_timer = reaction_delay

# ── Helpers ───────────────────────────────────────────────────────────────────
func _is_puck_behind_goal() -> bool:
	return (puck.global_position.z - _goal_line_z) * _direction_sign < 0.0

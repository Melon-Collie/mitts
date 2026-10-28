class_name GoalieController
extends Node

# The goalie's seat in the game: what every caller, the puck, the wire and the
# replays address, whoever plays him. KeeperController plays him; this half
# holds his node, his puck and his net, the host's snapshots of him and a
# client's interpolation of them, and the reads the shot log takes of him.

# Emitted by whoever plays him, when he secures the puck.
@warning_ignore("unused_signal")
signal puck_covered(covering_team_id: int)

var goalie: Goalie = null
var puck: Puck = null
var is_server: bool = false
var team_id: int = -1

# Dead-reckoning past the newest snapshot is capped here, and the seam back
# from it smoothstepped over the blend window.
var extrapolation_max_ms: float = 50.0
var rejoin_blend_duration: float = 0.075

var _goal_line_z: float = 0.0
var _goal_center_x: float = 0.0
var _sm: GoalieStateMachine = GoalieStateMachine.new()
var _view: GoalieWorldView = GoalieWorldView.new()
var _skater_getter: Callable = Callable()

# Where he stands as the shot log reads him: across the net, and his distance
# out from its centre.
var _current_x: float = 0.0
var _current_depth: float = 0.0
var _velocity_x: float = 0.0
var _velocity_z: float = 0.0
var _last_save_time: float = -1.0
var _pending_reaction_back_date: float = 0.0

# The longest a screen hides a shot from him, for the shot log's read; and the
# speed he counts as fully on the move, for its unset share.
const SCREEN_MAX_DELAY_S: float = 0.30
const MOVING_M_S: float = 2.5
var _screen_cfg := GoalieScreenRules.ScreenConfig.new()

# The host's snapshots, sorted by timestamp, bounded to the skater buffer's
# 30 (~0.67 s at the 45 Hz broadcast).
var _state_buffer: Array[BufferedGoalieState] = []
var _scratch_bracket := BufferedStateInterpolator.BracketResult.new()
var _scratch_state := GoalieNetworkState.new()
var is_extrapolating: bool = false
# The root's seam back from extrapolation: < 0 inactive. The pose is held
# through a gap, not dead-reckoned, so only the root needs it.
var _rejoin_blend_elapsed: float = -1.0
var _rejoin_blend_from_x: float = 0.0
var _rejoin_blend_from_z: float = 0.0


# `_profile` (null: Hard) is the tier of whoever plays him.
func setup(assigned_goalie: Goalie, assigned_puck: Puck, assigned_goal_line_z: float, assigned_is_server: bool,
		_profile: GoalieSkillProfile = null) -> void:
	goalie = assigned_goalie
	puck = assigned_puck
	is_server = assigned_is_server
	_goal_line_z = assigned_goal_line_z
	_goal_center_x = 0.0
	# On the goal line, turned up the ice, before the first tick: otherwise the
	# node is drawn at the scene default and skates out of it.
	goalie.set_goalie_position(_goal_center_x, _goal_line_z)
	goalie.set_goalie_rotation_y(PI if _goal_line_z < 0.0 else 0.0)
	goalie.reset_physics_interpolation()
	if is_server:
		puck.puck_released.connect(_on_puck_released)
		puck.puck_touched_goalie.connect(_on_puck_contact)
		puck.puck_caught_by_goalie.connect(_on_puck_caught)
		puck.puck_hit_boards.connect(_on_reaction_resolved)
		puck.puck_touched_post.connect(_on_reaction_resolved)
		puck.puck_hit_goal_body.connect(_on_reaction_resolved)


# A tier onto a goalie already playing (free play changes it without a
# respawn), for whoever plays him. Absolute values, so applying one twice is
# applying it once.
func apply_skill_profile(_profile: GoalieSkillProfile) -> void:
	pass


# The skaters he reads (GameManager's, so the controller knows no registry).
func set_skater_getter(getter: Callable) -> void:
	_skater_getter = getter


# The back-date for the next puck_released, set just before the release so its
# synchronous handler takes it.
func set_pending_reaction_back_date(seconds: float) -> void:
	_pending_reaction_back_date = maxf(seconds, 0.0)


func _ensure_view() -> void:
	if not _skater_getter.is_valid():
		_view.invalidate()
		return
	_view.ensure(Engine.get_physics_frames(), _skater_getter.call(),
			team_id, puck.global_position, puck.get_carrier())


func get_buffer_depth() -> int:
	return _state_buffer.size()


# ── What the player plays: overridden by KeeperController ─────────────────────
func reset_to_crease() -> void:
	pass


# The stationary drill's goalie, posed once with his processing off.
func snap_to_standing_pose(_open_five_hole: bool = false) -> void:
	pass


func is_butterfly() -> bool:
	return false


func _on_puck_released() -> void:
	pass


func _on_puck_contact(_contacted: Goalie) -> void:
	pass


func _on_puck_caught(_contacted: Goalie) -> void:
	pass


func _on_reaction_resolved() -> void:
	pass


# ── Release context for the shot log ─────────────────────────────────────────
# Read once per resolved shot by GameManager, never per tick, so a logged shot
# carries the situation that produced it (ShotEvent's release-context block).
func stance() -> int:
	return _sm.current as int


func unset_fraction() -> float:
	return clampf(Vector2(_velocity_x, _velocity_z).length() / MOVING_M_S, 0.0, 1.0)


func challenge_radius() -> float:
	return _current_depth


func lateral_x() -> float:
	return _current_x


# How long the bodies between him and this shot hide it, from his eyes where
# his mask is.
func screen_delay_for(shot_velocity: Vector3) -> float:
	_ensure_view()
	if _view.screeners.is_empty():
		return 0.0
	_screen_cfg.eye_height = goalie.get_mask_world_position().y - goalie.global_position.y
	return minf(GoalieScreenRules.screen_occlusion_delay(puck.global_position, shot_velocity,
			goalie.global_position, _view.screeners, _screen_cfg), SCREEN_MAX_DELAY_S)


# Seconds since the puck last touched him, or -1 if it has not this game: the
# rebound discriminator.
func seconds_since_last_save() -> float:
	if _last_save_time < 0.0:
		return -1.0
	return maxf(float(Time.get_ticks_msec()) * 0.001 - _last_save_time, 0.0)


# ── State serialization ───────────────────────────────────────────────────────
# Into a caller-owned instance (the per-tick StateBufferManager capture), so
# this must not allocate.
func fill_state(s: GoalieNetworkState) -> void:
	s.position_x = goalie.global_position.x
	s.position_z = goalie.global_position.z
	s.rotation_y = goalie.get_goalie_rotation_y()
	s.state_enum = _sm.current as int
	s.five_hole_openness = 0.0
	s.velocity_x = _velocity_x
	s.velocity_z = _velocity_z


func apply_state(network_state: GoalieNetworkState, host_ts: float) -> void:
	if is_server:
		return
	# Out of order: the buffer must stay sorted for the bracket search.
	if not _state_buffer.is_empty() and host_ts <= _state_buffer.back().timestamp:
		NetworkTelemetry.record_ooo_drop()
		return
	# The evicted front entry is recycled as the new back one (see
	# PuckController.apply_state): the bracket search re-reads the buffer every
	# render, so no consumer holds a wrapper across frames.
	var entry: BufferedGoalieState
	if _state_buffer.size() >= 30:
		entry = _state_buffer.pop_front()
	else:
		entry = BufferedGoalieState.new()
	entry.timestamp = host_ts
	entry.state = network_state
	_state_buffer.append(entry)


# Renders him at `now - interpolation_delay` from the buffered snapshots; past
# the newest, dead-reckons the root by its velocity, the pose held.
func _interpolate_and_apply() -> void:
	var prev_extrapolating: bool = is_extrapolating
	if _state_buffer.is_empty():
		is_extrapolating = false
		return
	var render_time: float = NetworkManager.estimated_host_time() - NetworkManager.get_interpolation_delay()
	var bracket: BufferedStateInterpolator.BracketResult = BufferedStateInterpolator.find_bracket(
			_state_buffer, render_time, _scratch_bracket)
	if bracket == null:
		is_extrapolating = false
		return
	is_extrapolating = bracket.is_extrapolating
	var interpolated: GoalieNetworkState
	if bracket.is_extrapolating:
		var dt: float = minf(bracket.extrapolation_dt, extrapolation_max_ms / 1000.0)
		interpolated = _extrapolate_goalie_state(bracket.to_state, dt)
	else:
		interpolated = _lerp_goalie_state(bracket.from_state, bracket.to_state, bracket.t)
	if prev_extrapolating and not is_extrapolating:
		_rejoin_blend_from_x = goalie.global_position.x
		_rejoin_blend_from_z = goalie.global_position.z
		_rejoin_blend_elapsed = 0.0
	if _rejoin_blend_elapsed >= 0.0:
		var ease_t: float = clampf(_rejoin_blend_elapsed / rejoin_blend_duration, 0.0, 1.0)
		var eased: float = smoothstep(0.0, 1.0, ease_t)
		interpolated.position_x = lerpf(_rejoin_blend_from_x, interpolated.position_x, eased)
		interpolated.position_z = lerpf(_rejoin_blend_from_z, interpolated.position_z, eased)
		if ease_t >= 1.0:
			_rejoin_blend_elapsed = -1.0
	_apply_interpolated(interpolated)
	BufferedStateInterpolator.drop_stale(_state_buffer, render_time)


# Fills and returns the reused _scratch_state.
func _lerp_goalie_state(from_s: GoalieNetworkState, to_s: GoalieNetworkState, t: float) -> GoalieNetworkState:
	var r := _scratch_state
	r.position_x = lerpf(from_s.position_x, to_s.position_x, t)
	r.position_z = lerpf(from_s.position_z, to_s.position_z, t)
	r.rotation_y = lerp_angle(from_s.rotation_y, to_s.rotation_y, t)
	# The stance can't lerp: the freshest, so it does not lag the host's.
	r.state_enum = to_s.state_enum
	r.five_hole_openness = lerpf(from_s.five_hole_openness, to_s.five_hole_openness, t)
	r.velocity_x = lerpf(from_s.velocity_x, to_s.velocity_x, t)
	r.velocity_z = lerpf(from_s.velocity_z, to_s.velocity_z, t)
	return r


func _extrapolate_goalie_state(newest: GoalieNetworkState, dt: float) -> GoalieNetworkState:
	var r := _scratch_state
	r.copy_from(newest)
	r.position_x = newest.position_x + newest.velocity_x * dt
	r.position_z = newest.position_z + newest.velocity_z * dt
	return r


func _apply_interpolated(_s: GoalieNetworkState) -> void:
	pass


# A replay poses him from the snapshot the host captured, never from an AI of
# its own.
func apply_replay_state(_state: GoalieNetworkState, _delta: float) -> void:
	pass

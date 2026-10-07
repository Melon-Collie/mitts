class_name GaitShotLayer
extends GaitLayer

# The shot's legs, driven from the replicated current_shot_state and
# shot_charge exactly like the stick flex. The wrister load tracks the
# drag-charge through WRISTER_AIM, the slapper load tracks the wind-up through
# the charge states. Entering FOLLOW_THROUGH latches the smoothed load as the
# release kick's power (floored by the min pop so an uncharged snap still reads
# and a short-wind slap still commits), with the kick's amplitude set picked by
# which charge it came from — a quick-shot pass (no charge state at all) rides
# the wrister set, the same split the stick flex uses. The kick rides the shared
# asymmetric arc (fast weight transfer through the release, slow settle) on its
# own cosmetic timer: remotes see the state flip, not the state machine's
# follow-through timer.

const State = SkaterStateMachine.State

# Radians of lower-body rotation.y, republished by the coordinator for the pose
# coordinator's yaw sum.
var hip_yaw: float = 0.0
var _prev_state: int = 0
var _wrister_load: float = 0.0      # smoothed 0..1 drag-charge engagement
var _slap_load: float = 0.0         # smoothed 0..1 wind-up engagement
var _kick_t: float = -1.0           # seconds into the release kick; <0 = idle
var _kick_power: float = 0.0        # load latched at release (min-pop floored)
var _kick_is_slap: bool = false
var _kick_env: float = 0.0


func stages() -> int:
	return Stage.HOLD | Stage.FLOOR | Stage.LEGS


func reset() -> void:
	hip_yaw = 0.0
	_prev_state = 0
	_wrister_load = 0.0
	_slap_load = 0.0
	_kick_t = -1.0
	_kick_power = 0.0
	_kick_is_slap = false
	_kick_env = 0.0


# Re-stamps the transition latch with the live state. reset() clears it to 0,
# which reads as a transition on the next pass.
func sync_state() -> void:
	_prev_state = _skater.current_shot_state


func is_quiet() -> bool:
	var s: int = _skater.current_shot_state
	return (s == State.SKATING_WITH_PUCK or s == State.SKATING_WITHOUT_PUCK) \
			and s == _prev_state and _kick_t < 0.0


# The one-timer's retention hold is the loaded tail of the wind-up, so the legs
# stay in the slapper load through it — and the follow-through it hands off to
# is a slap kick, not a wrister's.
static func _is_slap_charge(state: int) -> bool:
	return state == State.SLAPPER_CHARGE_WITH_PUCK \
			or state == State.SLAPPER_CHARGE_WITHOUT_PUCK \
			or state == State.ONE_TIMER_RETENTION


func advance(delta: float) -> bool:
	var state: int = _skater.current_shot_state
	if state != _prev_state:
		if state == State.FOLLOW_THROUGH:
			_kick_t = 0.0
			_kick_is_slap = _is_slap_charge(_prev_state)
			if _kick_is_slap:
				_kick_power = maxf(_slap_load, _controller.slapper_kick_min_power)
			else:
				# Latch from the release charge as well as the smoothed aim load:
				# the frozen wrister is a quick flick, so _wrister_load never builds
				# over the brief coil and would pin the kick at the min-power floor.
				# shot_charge holds the release power through the follow-through;
				# on the non-frozen path _wrister_load ≈ shot_charge.
				_kick_power = maxf(maxf(_wrister_load, _skater.shot_charge),
						_controller.wrister_kick_min_power)
		_prev_state = state
	var ease: float = minf(_controller.wrister_load_blend_speed * delta, 1.0)
	_wrister_load = lerpf(_wrister_load,
			_skater.shot_charge if state == State.WRISTER_AIM else 0.0, ease)
	# shot_charge and the wind-up pose both fill over max_slapper_charge_time
	# (SkaterController.slapper_wind_up_t), so shot_charge IS the wind-up
	# progress; sqrt-eased to match the torso coil's front-loaded snap
	# (SkaterPoseCoordinator.apply_upper_body).
	var slap_target: float = 0.0
	if _is_slap_charge(state):
		slap_target = sqrt(clampf(_skater.shot_charge, 0.0, 1.0))
	_slap_load = lerpf(_slap_load, slap_target, ease)
	_kick_env = 0.0
	if _kick_t >= 0.0:
		_kick_t += delta
		var kick_total: float = _controller.slapper_kick_time if _kick_is_slap \
				else _controller.wrister_kick_time
		var kt: float = _kick_t / maxf(kick_total, 0.001)
		if kt >= 1.0:
			_kick_t = -1.0
		else:
			_kick_env = sin(PI * pow(kt, _controller.follow_through_arc_skew)) * _kick_power
	# Hips coil with the load (stick-side hip pulls back, riding the torso coil)
	# and uncoil THROUGH the release — the stick-side hip drives forward past
	# square, mirroring the follow-through's torso `through` term. Positive
	# lower-body yaw turns the legs toward −X, i.e. pulls the +X hip forward.
	var stick_side: float = -1.0 if _skater.is_left_handed else 1.0
	var kick_hip_yaw_deg: float = _controller.slapper_kick_hip_yaw_deg if _kick_is_slap \
			else _controller.wrister_kick_hip_yaw_deg
	hip_yaw = -stick_side * (
				deg_to_rad(_controller.wrister_load_hip_coil_deg) * _wrister_load
				+ deg_to_rad(_controller.slapper_load_hip_coil_deg) * _slap_load) \
			+ stick_side * deg_to_rad(kick_hip_yaw_deg) * _kick_env
	return _wrister_load > 0.001 or _slap_load > 0.001 or _kick_env > 0.0


# Shooting is a glide: the feet set through the load and drive through the
# release.
func stride_hold() -> float:
	return maxf(maxf(_wrister_load, _slap_load), _kick_env) * _controller.shot_stride_fade


# The loads sit INTO the shot as the charge builds (the slapper wind-up deepest
# — the power position), and the release keeps the front leg seated through the
# drive (the back knee is pulled out of this flex by the kick extension — that
# asymmetry IS the weight transfer read).
func stance_floor() -> float:
	var kick_stance: float = _controller.slapper_kick_stance if _kick_is_slap \
			else _controller.wrister_kick_stance
	return maxf(maxf(_controller.wrister_load_stance * _wrister_load,
			_controller.slapper_load_stance * _slap_load), kick_stance * _kick_env)


# Load: the shooting base — the stick-side foot staggers back and both legs roll
# toward it, settling the weight over the back leg while the charge builds (a
# common roll rides the body over that side's leg). Wrister and slapper loads
# sum, but their charge states are exclusive, so only the decay tails overlap.
# Release: the roll flips to land the weight over the FRONT foot while the back
# leg drives into extension behind, its knee straightening (never past straight)
# so the freed shin carries into the kick's rearward reach.
func shape_legs(p: GaitPose) -> void:
	var load_split_deg: float = _controller.wrister_load_split_deg * _wrister_load \
			+ _controller.slapper_load_split_deg * _slap_load
	var load_lean_deg: float = _controller.wrister_load_lean_deg * _wrister_load \
			+ _controller.slapper_load_lean_deg * _slap_load
	if load_split_deg > 0.001 or load_lean_deg > 0.001:
		var load_split: float = deg_to_rad(load_split_deg) * p.stick_side
		p.l_pitch += load_split
		p.r_pitch -= load_split
		var load_lean: float = deg_to_rad(load_lean_deg) * p.stick_side
		p.l_roll += load_lean
		p.r_roll += load_lean
	if _kick_env <= 0.001:
		return
	var kick_lean_deg: float = _controller.slapper_kick_lean_deg if _kick_is_slap \
			else _controller.wrister_kick_lean_deg
	var kick_lean: float = deg_to_rad(kick_lean_deg) * _kick_env * p.stick_side
	p.l_roll -= kick_lean
	p.r_roll -= kick_lean
	var kick_back_deg: float = _controller.slapper_kick_back_deg if _kick_is_slap \
			else _controller.wrister_kick_back_deg
	var kick_back: float = deg_to_rad(kick_back_deg) * _kick_env
	var extend_deg: float = _controller.slapper_kick_knee_extend_deg if _kick_is_slap \
			else _controller.wrister_kick_knee_extend_deg
	var extend: float = deg_to_rad(extend_deg) * _kick_env
	if p.stick_side > 0.0:
		p.r_pitch -= kick_back
		p.knee_extend_r = extend
	else:
		p.l_pitch -= kick_back
		p.knee_extend_l = extend

class_name SkaterLocomotion
extends RefCounted

# The skating half of the gait: which locomotion state the skater is in, and the
# leg stroke each state skates. SkaterSkatingCoordinator turns the stroke into
# joint angles, with the overlays (GaitLayer) composed on top.
#
# The state is the physics' own decision (LocomotionRules), crossfaded: each
# state owns its legs outright while it holds weight and the weights sum to one,
# so no state needs a fade against another. Everything is derived from
# replicated velocity, move intent, brake and facing, so a wire-fed remote skates
# exactly what the simulating machine does.
#
# Runs at render rate, guarded against reconcile replay by its caller, so it may
# own no timer that gameplay reads.

# Acceleration and turn rate are sampled over the time since velocity last
# changed (it only steps on physics ticks), held at most this long.
const _FD_WINDOW_MAX: float = 0.1

var _skater: Skater = null
var _controller: SkaterController = null

# Eased state weights (read by the coordinator; written only here).
var mix := LocomotionRules.Mix.new()
var _target := LocomotionRules.Mix.new()

var stride_phase: float = 0.0
# Stroke engagement 0..1: how hard the striding states are working.
var intensity: float = 0.0
# Tangential acceleration over stride_effort_ref_accel, −1..1: pushing vs coasting.
var effort: float = 0.0
# Signed turn rate of the travel direction, rad/s, smoothed.
var turn_rate: float = 0.0
# Share of the edge's lateral grip the travel's curve is using, signed by the
# way it curves (CarveRules' sign), −1..1: the centripetal acceleration
# speed·turn_rate over the most the movement model's edges give
# (turn_accel · lateral_grip). What LocomotionRules calls turning.
var turning: float = 0.0
# The loaded stance's engagement 0..1, eased from the controller's stance_active.
var loaded: float = 0.0
var cruise_gear: float = 0.0
var push_scale: float = 1.0
# The hockey stop's side, latched when the stop comes on so the legs never flip
# mid-skid (HockeyStopRules.latch_side).
var stop_side: float = 1.0
# Radians of lower-body yaw the stop turns the hips across travel.
var stop_yaw: float = 0.0

# Stroke layers, hip frame, radians; the coordinator adds the stance and the
# overlays and resolves the knees.
var l_pitch: float = 0.0
var r_pitch: float = 0.0
var l_roll: float = 0.0
var r_roll: float = 0.0
# Push extension 0..1 per leg — the knee release and the edge load read it.
var l_ext: float = 0.0
var r_ext: float = 0.0
# Extra knee fold per leg: recovery tuck, crossover clearance, glide inside tuck.
var l_tuck: float = 0.0
var r_tuck: float = 0.0
# Crouch engagement before the overlays' floors; vertical body bob (m).
var stance: float = 0.0
var bob: float = 0.0
# Edge load floor from the states skated on the edges (stop, tight turn, carve).
var edge_floor: float = 0.0
var trunk_pitch: float = 0.0
var trunk_roll: float = 0.0

var _stop_latched: bool = false
# The turning states' weights with their side as the sign: eased as one number,
# so a turn that changes side has to pass through zero on the way, and the legs
# posed from it slide through centre rather than swapping.
var _cross_signed: float = 0.0
var _carve_signed: float = 0.0
var _tight_signed: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _have_prev_velocity: bool = false
var _fd_time: float = 0.0
var _fd_effort_target: float = 0.0
var _fd_turn: float = 0.0
var _glide_phase: float = 0.0
var _weight_shift: float = 0.0
var _weight_shift_vel: float = 0.0
var _ground_speed: float = 0.0
var _speed_t: float = 0.0
var _start: float = 0.0


func setup(skater: Skater, controller: SkaterController) -> void:
	_skater = skater
	_controller = controller


func reset() -> void:
	mix.clear()
	mix.glide = 1.0
	_cross_signed = 0.0
	_carve_signed = 0.0
	_tight_signed = 0.0
	stride_phase = 0.0
	intensity = 0.0
	effort = 0.0
	turn_rate = 0.0
	turning = 0.0
	loaded = 0.0
	stop_yaw = 0.0
	_stop_latched = false
	_have_prev_velocity = false
	_fd_time = 0.0
	_fd_effort_target = 0.0
	_fd_turn = 0.0
	_glide_phase = 0.0
	_weight_shift = 0.0
	_weight_shift_vel = 0.0
	_clear_strokes()


# Reads the state and advances the shared clocks. `planted` hands the legs to an
# overlay outright (the block); `hold` is the share of the stroke an overlay
# suppresses (a shot sets its feet, the pivot glides through its transit).
func sense(delta: float, planted: bool, hold: float) -> void:
	var c: SkaterController = _controller
	var vel: Vector3 = _skater.velocity
	_ground_speed = Vector2(vel.x, vel.z).length()
	_speed_t = clampf(_ground_speed / maxf(c.max_speed, 0.001), 0.0, 1.0)
	_sample_velocity(delta, vel)
	effort = lerpf(effort, _fd_effort_target, c.stride_effort_speed * delta)
	turn_rate = lerpf(turn_rate, _fd_turn, c.carve_engage_speed * delta)
	turning = clampf(_ground_speed * turn_rate
			/ maxf(c.turn_accel * c.lateral_grip, 0.001), -1.0, 1.0)
	loaded = lerpf(loaded, 1.0 if (c.stance_active and not planted) else 0.0,
			c.locomotion_blend_speed * delta)

	var basis: Basis = _skater.global_transform.basis
	var facing := Vector2(-basis.z.x, -basis.z.z)
	LocomotionRules.classify(Vector2(vel.x, vel.z), _skater.move_intent,
			_skater.brake_intent, c.stance_active, facing, turning, _target)
	# A brake below the stop's speed floor is no skid, and a turn below the carve
	# floor is steps, not crossovers.
	if _ground_speed < c.hockey_stop_min_speed:
		_target.glide += _target.stop
		_target.stop = 0.0
	if _ground_speed < c.carve_min_speed:
		_target.stride += _target.crossover
		_target.crossover = 0.0
	if planted:
		_target.clear()
		_target.glide = 1.0
	_ease_mix(delta)

	var local_vel: Vector3 = basis.inverse() * vel
	if _target.stop > 0.5 and not _stop_latched:
		_stop_latched = true
		stop_side = HockeyStopRules.latch_side(local_vel)
	elif _target.stop < 0.1:
		_stop_latched = false
	stop_yaw = HockeyStopRules.stop_yaw(local_vel, stop_side,
			deg_to_rad(c.hockey_stop_max_yaw_deg)) * mix.stop if mix.stop > 0.001 else 0.0

	# The start: first strides from a standstill are short, quick chops, fading
	# out as the body gets moving.
	_start = clampf(1.0 - _ground_speed / maxf(c.dig_in_fade_speed, 0.001), 0.0, 1.0)
	var stroking: float = mix.stride + mix.crossover + mix.backward + mix.shuffle
	var target_intensity: float = 0.0
	if _target.stride + _target.crossover + _target.backward + _target.shuffle > 0.01:
		target_intensity = maxf(_speed_t, maxf(c.dig_in_intensity * _start * (mix.stride + mix.backward),
				c.shuffle_intensity * mix.shuffle))
	intensity = lerpf(intensity, target_intensity * (1.0 - hold), c.stride_intensity_speed * delta)

	push_scale = clampf(1.0 + effort * c.stride_push_gain, c.stride_glide_floor, c.stride_push_ceiling) \
			* (1.0 + loaded * c.stance_stride_gain)
	cruise_gear = _speed_t * (1.0 - clampf(effort, 0.0, 1.0))

	# Cadence: each striding state's own rate, weighted. Straight-line strides
	# saturate toward a ceiling (speed comes from longer strides, not faster
	# ones) and slow further at cruise; crossovers step per radian of heading
	# change; side-steps and the start chop work under the speed law.
	var ceiling: float = maxf(c.stride_cadence_max_rate, 0.001)
	var stride_rate: float = ceiling * tanh(_ground_speed * c.stride_cadence / ceiling) \
			* (1.0 - c.cadence_cruise_falloff * cruise_gear)
	stride_rate = maxf(stride_rate, c.dig_in_cadence_rate * _start)
	var cross_rate: float = maxf(absf(turn_rate) * c.crossover_phase_per_turn, stride_rate)
	# Averaged over the stroking states alone: a crossover sharing the mix with a
	# carve, or a stride with a glide, fades in amplitude, never in tempo.
	var rate: float = 0.0
	if stroking > 0.001:
		rate = ((mix.stride + mix.backward) * stride_rate + mix.crossover * cross_rate
				+ mix.shuffle * c.shuffle_cadence_rate) / stroking
	stride_phase = wrapf(stride_phase + rate * (1.0 - hold) * delta, 0.0, TAU)
	if mix.glide > 0.01:
		_glide_phase = wrapf(_glide_phase + TAU * c.glide_sway_hz * mix.glide * delta, 0.0, TAU)
	if stroking < 0.001:
		intensity = minf(intensity, 1.0)


# The stroke each state skates, blended by the mix. `fwd` is the hip-frame
# forward velocity.
func strokes(delta: float, fwd: float) -> void:
	var c: SkaterController = _controller
	_clear_strokes()
	# The turning states' inside skate leads along TRAVEL; the legs can only
	# lead along the hips, so the lead is travel's share of the hips' forward
	# axis (the cosine, signed). Skated backward to the hips it changes legs, and
	# with travel straight across them it is zero. Never reduce it to a sign:
	# that swaps the leading skate in one frame wherever the hips cross travel.
	var along: float = clampf(fwd / maxf(_ground_speed, 0.1), -1.0, 1.0)
	var skew: float = clampf(c.stride_skew + c.glide_hold_skew * cruise_gear, 0.0, 0.95)
	var s: float = sin(stride_phase - skew * sin(stride_phase))
	var phase_opp: float = stride_phase + PI
	var s_opp: float = sin(phase_opp - skew * sin(phase_opp))
	# Swing-direction samples (d/dθ of the warped sine, normalized to its peak):
	# positive while the leg swings forward through its recovery.
	var cs: float = cos(stride_phase - skew * sin(stride_phase)) \
			* (1.0 - skew * cos(stride_phase)) / (1.0 + skew)
	var cs_opp: float = cos(phase_opp - skew * sin(phase_opp)) \
			* (1.0 - skew * cos(phase_opp)) / (1.0 + skew)
	var ext_l: float = maxf(-s, 0.0)
	var ext_r: float = maxf(-s_opp, 0.0)
	var amp: float = intensity * push_scale
	var bias: float = c.stride_rear_bias

	# Forward stride: a rear-biased fore/aft push (the skate drives BACK and
	# recovers under the hips), an in-phase edge rock, the V-flare of the
	# extending leg, the push extension and the recovery tuck.
	var w: float = mix.stride
	if w > 0.001:
		var push: float = deg_to_rad(c.stride_pitch_deg) * amp * (1.0 - c.dig_in_chop * _start)
		_stroke(w, push, deg_to_rad(c.stride_roll_deg) * amp, deg_to_rad(c.stride_abduction_deg) * amp,
				deg_to_rad(c.stride_knee_deg) * amp, s, s_opp, cs, cs_opp, ext_l, ext_r, bias)

	# Backward: C-cuts. The push reverses and shrinks (the long pull is out
	# front), the edge rock and the out-and-in sweep widen, and the blades stay
	# down through the recovery.
	w = mix.backward
	if w > 0.001:
		var push_b: float = -deg_to_rad(c.stride_back_pitch_deg) * amp * (1.0 - c.backpedal_pitch_fade)
		_stroke(w, push_b,
				deg_to_rad(c.stride_roll_deg + c.backpedal_ccut_roll_deg) * amp,
				deg_to_rad(c.stride_abduction_deg + c.backpedal_ccut_sweep_deg) * amp,
				deg_to_rad(c.stride_knee_deg) * amp * (1.0 - c.backpedal_tuck_fade),
				s, s_opp, cs, cs_opp, ext_l, ext_r, bias)
		trunk_pitch += deg_to_rad(c.backpedal_chest_deg) * w

	# Crossovers: fixed roles by the turn's side, two-beat — the outside leg
	# lifts and steps across in front on one half of the cycle, the inside leg
	# extends in an under-push beneath the body on the other — over a residual
	# of the straight stride.
	w = mix.crossover
	if w > 0.001:
		var residual: float = 1.0 - c.carve_stride_fade
		_stroke(w, deg_to_rad(c.stride_pitch_deg) * amp * residual, 0.0, 0.0,
				deg_to_rad(c.stride_knee_deg) * amp * residual,
				s, s_opp, cs, cs_opp, ext_l, ext_r, bias)
		var over: float = maxf(s, 0.0)
		var under: float = maxf(-s, 0.0)
		var over_roll: float = deg_to_rad(c.carve_over_roll_deg) * intensity * over * w
		var under_roll: float = deg_to_rad(c.carve_under_roll_deg) * intensity * under * w
		var over_pitch: float = deg_to_rad(c.carve_over_pitch_deg) * intensity * over * w
		var clearance: float = deg_to_rad(c.carve_clearance_knee_deg) * intensity * maxf(cs, 0.0) * w
		if _cross_signed > 0.0:
			l_roll += over_roll
			l_pitch += over_pitch
			l_tuck += clearance
			r_roll -= under_roll
			r_ext = maxf(r_ext, under * w)
		else:
			r_roll -= over_roll
			r_pitch += over_pitch
			r_tuck += clearance
			l_roll += under_roll
			l_ext = maxf(l_ext, under * w)

	# Side-step: a scissor 180° out of phase between the legs, leaning into the
	# step.
	w = mix.shuffle
	if w > 0.001:
		var lean: float = mix.side * deg_to_rad(c.crossover_lean_deg) * intensity
		var scissor: float = deg_to_rad(c.crossover_scissor_deg) * amp
		l_roll += w * (lean + s * scissor)
		r_roll += w * (lean + s_opp * scissor)

	# Glide: both blades down, a lazy edge-to-edge sway far below stride cadence,
	# and coming out of a turn the inside knee tucks light — weight on the
	# outside leg.
	w = mix.glide * _speed_t
	if w > 0.001:
		var sway: float = sin(_glide_phase) * deg_to_rad(c.glide_sway_deg) * w
		trunk_roll += sway
		l_roll += sway * 0.5
		r_roll += sway * 0.5
		var curve: float = clampf(absf(turn_rate) / maxf(c.carve_ref_turn_rate, 0.001), 0.0, 1.0)
		var inside_tuck: float = deg_to_rad(c.glide_inside_tuck_deg) * curve * w
		if turn_rate > 0.0:
			r_tuck += inside_tuck
		else:
			l_tuck += inside_tuck

	# Tight turn: both blades dug in, the inside skate leading.
	var tight_in: float = _tight_signed * along
	if absf(tight_in) > 0.001:
		var split: float = deg_to_rad(c.tight_turn_split_deg) * tight_in
		r_pitch += split
		l_pitch -= split

	# Carve: both blades on the edges the lean puts them on, the inside skate
	# leading, the weight on the outside one — the inside knee tucks light. The
	# inside is the signed weight's sign, so a reversal slides through centre.
	var carve_in: float = _carve_signed * along
	if absf(carve_in) > 0.001:
		var lead: float = deg_to_rad(c.carve_lead_deg) * carve_in
		r_pitch += lead
		l_pitch -= lead
		var light: float = deg_to_rad(c.glide_inside_tuck_deg)
		r_tuck += light * maxf(carve_in, 0.0)
		l_tuck += light * maxf(-carve_in, 0.0)

	# Hockey stop, in the TURNED leg frame (stop_yaw turns the hips across):
	# the leading leg braces ahead, the trailing one tucks behind, both rolled
	# the same way onto the edges digging into the skid.
	w = mix.stop
	if w > 0.001:
		var stop_split: float = deg_to_rad(c.hockey_stop_split_deg) * w * stop_side
		l_pitch += stop_split
		r_pitch -= stop_split
		var edge: float = deg_to_rad(c.hockey_stop_edge_deg) * w * stop_side
		l_roll += edge
		r_roll += edge

	# Skid: fighting momentum to go the other way plants both legs in a wide
	# outward V.
	w = mix.skid
	if w > 0.001:
		var plant: float = deg_to_rad(c.reversal_plant_deg) * w
		l_roll -= plant
		r_roll += plant

	_stance(s)
	edge_floor = mix.stop + mix.tight + mix.carve

	# Trunk: sway over the loaded leg on the stride fundamental (the trunk is
	# too massive to carry the stroke's snap), a damped spring that lets the
	# weight settle over each leg with follow-through.
	var fore_aft: float = mix.stride + mix.backward + mix.crossover
	var s_fund: float = sin(stride_phase)
	trunk_roll += deg_to_rad(c.stride_sway_deg) * intensity * fore_aft * s_fund
	var shift_target: float = fore_aft * s_fund * intensity
	var shift_accel: float = c.weight_spring_stiffness * (shift_target - _weight_shift) \
			- c.weight_spring_damping * _weight_shift_vel
	_weight_shift_vel += shift_accel * delta
	_weight_shift += _weight_shift_vel * delta
	trunk_roll += deg_to_rad(c.weight_shift_deg) * _weight_shift


# One leg-pair stroke, weighted: fore/aft push (rear-biased), in-phase edge rock,
# V-flare of the extending leg, push extension, recovery tuck.
func _stroke(w: float, push: float, rock: float, flare: float, tuck: float,
		s: float, s_opp: float, cs: float, cs_opp: float,
		ext_l: float, ext_r: float, bias: float) -> void:
	l_pitch += w * (s - bias) * push
	r_pitch += w * (s_opp - bias) * push
	l_roll += w * (s * rock - flare * ext_l)
	r_roll += w * (s * rock + flare * ext_r)
	l_ext = maxf(l_ext, w * ext_l)
	r_ext = maxf(r_ext, w * ext_r)
	l_tuck += w * tuck * maxf(cs, 0.0)
	r_tuck += w * tuck * maxf(cs_opp, 0.0)


# Crouch engagement per state: the striding states sit with speed and effort,
# the dug-edge states sit deep, the glide keeps working knees at speed.
func _stance(s: float) -> void:
	var c: SkaterController = _controller
	var stroke: float = clampf(intensity / maxf(c.stance_full_speed_fraction, 0.01), 0.0, 1.0) \
			* clampf(1.0 + effort * c.stance_push_gain, 0.0, 1.35) \
			* (1.0 + loaded * c.stance_sit_gain) \
			* (1.0 + c.cadence_glide_stance_gain * cruise_gear)
	var stride_sit: float = maxf(stroke, c.dig_in_stance * _start * (1.0 if intensity > 0.01 else 0.0))
	stance = (mix.stride + mix.backward + mix.shuffle) * stride_sit \
			+ mix.crossover * maxf(stroke, c.carve_stance) \
			+ mix.glide * maxf(stroke, c.glide_stance * _speed_t) \
			+ mix.carve * c.carve_stance \
			+ mix.tight * c.tight_turn_stance \
			+ mix.stop * c.hockey_stop_stance \
			+ mix.skid * c.reversal_stance
	bob = c.stride_bob_m * intensity * (1.0 - s * s) * (mix.stride + mix.backward + mix.crossover)


func _ease_mix(delta: float) -> void:
	var c: SkaterController = _controller
	var k: float = minf(c.locomotion_blend_speed * delta, 1.0)
	# Crossovers come on slower than anything else, and signed: a quick steering
	# correction rides the edges, corrections alternating sides cancel, and only
	# a turn held to one side long enough is skated with crossovers.
	var kc: float = minf(c.crossover_commit_speed * delta, 1.0)
	mix.stride = lerpf(mix.stride, _target.stride, k)
	_cross_signed = lerpf(_cross_signed, _target.crossover * _target.side, kc)
	mix.crossover = absf(_cross_signed)
	# What the turn has not yet committed to crossovers is skated on the edges.
	var uncommitted: float = maxf(_target.crossover - mix.crossover, 0.0)
	_carve_signed = lerpf(_carve_signed, (_target.carve + uncommitted) * _target.side, k)
	mix.carve = absf(_carve_signed)
	mix.backward = lerpf(mix.backward, _target.backward, k)
	mix.shuffle = lerpf(mix.shuffle, _target.shuffle, k)
	mix.skid = lerpf(mix.skid, _target.skid, k)
	_tight_signed = lerpf(_tight_signed, _target.tight * _target.side, k)
	mix.tight = absf(_tight_signed)
	mix.stop = lerpf(mix.stop, _target.stop, k)
	var held: float = mix.stride + mix.crossover + mix.carve + mix.backward + mix.shuffle \
			+ mix.skid + mix.tight + mix.stop
	if held > 1.0:
		var scale: float = 1.0 / held
		mix.stride *= scale
		mix.crossover *= scale
		mix.carve *= scale
		_cross_signed *= scale
		_carve_signed *= scale
		mix.backward *= scale
		mix.shuffle *= scale
		mix.skid *= scale
		mix.tight *= scale
		_tight_signed *= scale
		mix.stop *= scale
		held = 1.0
	# The glide is what is left: the crossfade's remainder.
	mix.glide = 1.0 - held
	if _target.tight > 0.0 or _target.shuffle > 0.0 or _target.carve > 0.0 \
			or _target.crossover > 0.0:
		mix.side = _target.side


func _sample_velocity(delta: float, vel: Vector3) -> void:
	var c: SkaterController = _controller
	_fd_time += delta
	if not _have_prev_velocity:
		_prev_velocity = vel
		_have_prev_velocity = true
		_fd_time = 0.0
		return
	if vel == _prev_velocity and _fd_time < _FD_WINDOW_MAX:
		return
	var accel: Vector3 = (vel - _prev_velocity) / _fd_time
	var travel := Vector2(vel.x, vel.z)
	_fd_effort_target = 0.0
	if travel.length() > 0.1:
		_fd_effort_target = clampf(Vector2(accel.x, accel.z).dot(travel.normalized())
				/ maxf(c.stride_effort_ref_accel, 0.001), -1.0, 1.0)
	_fd_turn = CarveRules.turn_rate(Vector2(_prev_velocity.x, _prev_velocity.z), travel,
			_fd_time, c.carve_min_speed)
	_prev_velocity = vel
	_fd_time = 0.0


func _clear_strokes() -> void:
	l_pitch = 0.0
	r_pitch = 0.0
	l_roll = 0.0
	r_roll = 0.0
	l_ext = 0.0
	r_ext = 0.0
	l_tuck = 0.0
	r_tuck = 0.0
	trunk_pitch = 0.0
	trunk_roll = 0.0
	bob = 0.0
	edge_floor = 0.0

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
#
# Mirrored in C++ by NativeSkaterGait (native/src/native_skater_gait.cpp);
# test_native_gait_parity.gd fails if the two drift. Change both or neither.

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
# Radians of lower-body yaw the stop turns the hips across travel, and the
# whole turn it is easing toward.
var stop_yaw: float = 0.0
var _stop_yaw_full: float = 0.0

# The glide's joint-space texture, hip frame, radians: its edge sway as a leg
# roll and, out of a turn, its light inside knee as extra fold; GaitPose places
# the ankle from them on the stance.
var l_roll: float = 0.0
var r_roll: float = 0.0
var l_tuck: float = 0.0
var r_tuck: float = 0.0
# The states authored as where the skates go (`authored`): each ankle's offset
# from where the joint strokes above put it, hip-pivot frame, metres at leg_scale
# 1 (+X right, +Y up, −Z forward), and the leg's yaw (positive turns it toward
# −X). GaitPose lays them on before the leg solve.
var l_dx: float = 0.0
var l_dy: float = 0.0
var l_dz: float = 0.0
var l_yaw: float = 0.0
var r_dx: float = 0.0
var r_dy: float = 0.0
var r_dz: float = 0.0
var r_yaw: float = 0.0
# The stride's push per leg 0..1, for the edge load.
var l_push: float = 0.0
var r_push: float = 0.0
# How far out from under its hip an authored stroke's skate reaches on the ice,
# metres at leg_scale 1, at that stroke's own amplitude: the crouch has to let a
# leg get there (GaitPose.reach_hip), by the authored share.
var push_reach: float = 0.0
# The share of the mix authored as where the skates go: GaitPose stands those on
# the ice. `sliding` is the part of it whose skates scrape along with the body
# (the stop and the skid) rather than gripping the ice it goes over.
var authored: float = 0.0
var sliding: float = 0.0
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
	_stop_yaw_full = HockeyStopRules.stop_yaw(local_vel, stop_side,
			deg_to_rad(c.hockey_stop_max_yaw_deg))
	stop_yaw = _stop_yaw_full * mix.stop if mix.stop > 0.001 else 0.0

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
	# change; side-steps and the start chop work under the speed law. Driving
	# hard steps quicker at any speed, past the ceiling: a push gives only so
	# much, so an acceleration takes more of them, and the steps lengthen into
	# the speed law's as it tapers off.
	var ceiling: float = maxf(c.stride_cadence_max_rate, 0.001)
	var stride_rate: float = ceiling * tanh(_ground_speed * c.stride_cadence / ceiling) \
			* (1.0 - c.cadence_cruise_falloff * cruise_gear)
	stride_rate = maxf(stride_rate, maxf(c.dig_in_cadence_rate * _start,
			c.accel_cadence_rate * clampf(effort, 0.0, 1.0)))
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


# The stroke each state skates, blended by the mix. `travel` is the velocity in
# the hips' aligned frame, (right, forward).
func strokes(delta: float, travel: Vector2) -> void:
	var c: SkaterController = _controller
	_clear_strokes()
	var fwd: float = travel.y
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
	var amp: float = intensity * push_scale

	var w: float = mix.stride
	if w > 0.001:
		_stride_path(w, amp * (1.0 - c.dig_in_chop * _start), s, s_opp, cs, cs_opp)

	w = mix.backward
	if w > 0.001:
		_ccut_path(w, amp, s, s_opp, cs, cs_opp)
		trunk_pitch += deg_to_rad(c.backpedal_chest_deg) * w

	w = mix.crossover
	if w > 0.001:
		_crossover_path(w, signf(_cross_signed), amp, s, s_opp, cs, cs_opp)

	w = mix.shuffle
	if w > 0.001:
		_shuffle_path(w, mix.side, amp, s, s_opp, cs, cs_opp)

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

	# Tight turn: both skates down, the inside one leading, dug onto their edges
	# by the bank (GaitPose stands them on the ice under it).
	var tight_in: float = _tight_signed * along
	if absf(tight_in) > 0.001:
		var split: float = 0.5 * c.tight_turn_lead_m * tight_in
		r_dz -= split
		l_dz += split
		push_reach = maxf(push_reach, 0.5 * c.tight_turn_lead_m)

	# Carve: both skates down at hip width, the inside one leading; the lean
	# puts them on their edges (GaitPose stands them on the ice under it). The
	# inside is the signed weight's sign, so a reversal slides through centre.
	var carve_in: float = _carve_signed * along
	if absf(carve_in) > 0.001:
		var lead: float = 0.5 * c.carve_lead_m * carve_in
		r_dz -= lead
		l_dz += lead

	w = mix.stop
	if w > 0.001:
		# The legs' frame is the aligned one turned by the stop (the lower body
		# sums both); travel in it, (right, back).
		_stop_path(w, _in_legs(travel, stop_yaw), _in_legs(travel, _stop_yaw_full))

	w = mix.skid
	if w > 0.001:
		_skid_path(w, Vector2(travel.x, -travel.y))

	_stance(s)
	edge_floor = mix.stop + mix.tight + mix.carve
	sliding = mix.stop + mix.skid
	authored = 1.0 - mix.glide

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


# The forward stride, as where the skates go. Each push leaves from under the
# hips and drives out and back, the toe turning out; the recovery lifts and
# swings the skate back in along the same line to land under the hips, ahead of
# them. `p` runs from 0 at the landing to 1 at full extension, so the push and
# the recovery keep the stroke's own timing (the skew makes the push the fast
# half). Both skates shift under the body toward the support leg in phase (the
# rock), the body riding over the leg it stands on. `a` is the amplitude.
func _stride_path(w: float, a: float, s: float, s_opp: float, cs: float, cs_opp: float) -> void:
	var c: SkaterController = _controller
	var rock: float = c.stride_rock_m * a * s
	var p_l: float = 0.5 * (1.0 - s)
	var p_r: float = 0.5 * (1.0 - s_opp)
	var out: float = c.stride_push_out_m * a
	var land: float = -c.stride_land_fwd_m * a
	var travel: float = (c.stride_push_back_m + c.stride_land_fwd_m) * a
	var lift: float = c.stride_lift_m * a
	var toe: float = deg_to_rad(c.stride_toe_out_deg) * minf(a, 1.0)
	l_dx += w * (rock - out * p_l)
	r_dx += w * (rock + out * p_r)
	l_dz += w * (land + travel * p_l)
	r_dz += w * (land + travel * p_r)
	l_dy += w * lift * maxf(cs, 0.0)
	r_dy += w * lift * maxf(cs_opp, 0.0)
	l_yaw += w * toe * p_l
	r_yaw -= w * toe * p_r
	l_push = maxf(l_push, w * maxf(-s, 0.0))
	r_push = maxf(r_push, w * maxf(-s_opp, 0.0))
	push_reach = maxf(push_reach, Vector2(out, c.stride_push_back_m * a).length())


# Crossovers, as where the skates go: the stride's phase law on each leg, half
# a cycle apart, with landings and extensions of their own, `side` the turn's
# inside (+1 right). The outside skate lands crossed over to the inside and
# pushes back out along the ice, and its recovery is the over-step, lifted and
# passing in front. The inside skate lands at its own side and pushes under the
# body, and recovers back out from behind. Half a cycle apart, the outside lands
# crossed while the inside is under the body, so they cross every step: the
# over-step rides the inside skate's under-push, and the two pushes alternate.
# The crossing is the stroke's engagement (`_engaged`), which is full well below
# top speed, so a crossover crosses at any pace; how far back each push goes is
# the amplitude `a`.
func _crossover_path(w: float, side: float, a: float, s: float, s_opp: float,
		cs: float, cs_opp: float) -> void:
	var c: SkaterController = _controller
	var e: float = _engaged()
	var cross: float = c.crossover_cross_m * e
	var out: float = c.crossover_out_m * e
	var lands: float = c.crossover_side_m * e
	var under: float = c.crossover_under_m * e
	var land: float = -c.crossover_land_fwd_m * a
	var travel: float = (c.crossover_back_m + c.crossover_land_fwd_m) * a
	var lift: float = c.crossover_lift_m * e
	var clear: float = c.crossover_pass_m * e
	# Per leg: 0 at the landing, 1 at full extension.
	var p_l: float = 0.5 * (1.0 - s)
	var p_r: float = 0.5 * (1.0 - s_opp)
	var up_l: float = maxf(cs, 0.0)
	var up_r: float = maxf(cs_opp, 0.0)
	# The left skate is the outside one in a right turn.
	var left_out: bool = side > 0.0
	var l_from: float = cross if left_out else lands
	var l_to: float = out if left_out else under
	var r_from: float = lands if left_out else cross
	var r_to: float = under if left_out else out
	l_dx += w * side * (l_from * (1.0 - p_l) - l_to * p_l)
	r_dx += w * side * (r_from * (1.0 - p_r) - r_to * p_r)
	l_dz += w * (land + travel * p_l + clear * up_l * (-1.0 if left_out else 1.0))
	r_dz += w * (land + travel * p_r + clear * up_r * (1.0 if left_out else -1.0))
	l_dy += w * lift * up_l
	r_dy += w * lift * up_r
	l_push = maxf(l_push, w * maxf(-s, 0.0))
	r_push = maxf(r_push, w * maxf(-s_opp, 0.0))
	push_reach = maxf(push_reach, maxf(Vector2(cross, c.crossover_land_fwd_m * a).length(),
			maxf(Vector2(out, c.crossover_back_m * a).length(),
					Vector2(under, c.crossover_back_m * a).length())))


# `travel` (right, forward) in the legs' frame turned `yaw` further, as (right,
# back).
static func _in_legs(travel: Vector2, yaw: float) -> Vector2:
	var cy: float = cos(yaw)
	var sy: float = sin(yaw)
	return Vector2(travel.x * cy + travel.y * sy, travel.x * sy - travel.y * cy)


# The hockey stop, as where the skates go, `along` the travel in the legs' frame
# (right, back), and `turned` the same in the frame the hips are turning to. Both skates plant wide along the line of travel, set toward it
# so the body sits back over them, turned square across it, the one on the
# travel side a little ahead. Under hips sitting back of them, both blades go
# onto the edges that dig in (the front one's inside, the back one's outside),
# without a roll of their own.
func _stop_path(w: float, along: Vector2, turned: Vector2) -> void:
	var c: SkaterController = _controller
	if along.length_squared() < 1e-6:
		return
	var t: Vector2 = along.normalized()
	var spread: float = c.hockey_stop_spread_m
	var lead: float = c.hockey_stop_lead_m
	# Which way across is the latched side (HockeyStopRules.latch_side), never
	# the travel's own sign, which flickers while the hips are still square to
	# it. The legs turn toward +X on side +1, so travel runs off their left: the
	# left skate is the front one.
	var front: float = -stop_side
	var stagger: float = c.hockey_stop_stagger_m
	l_dx += w * (t.x * lead - spread)
	r_dx += w * (t.x * lead + spread)
	l_dz += w * (t.y * lead + stagger * front)
	r_dz += w * (t.y * lead - stagger * front)
	# Square across travel, on the latched side: the hips' turn is capped short
	# of it, and the legs turn the rest — measured where the hips are turning
	# to, so the legs make up the cap and not the turn still to come
	# (rotation.y positive turns a leg toward −X).
	var u: Vector2 = turned.normalized() if turned.length_squared() > 1e-6 else t
	var across := Vector2(-u.y, u.x) if stop_side > 0.0 else Vector2(u.y, -u.x)
	var square: float = clampf(atan2(-across.x, -across.y), -PI * 0.5, PI * 0.5)
	l_yaw += w * square
	r_yaw += w * square
	push_reach = maxf(push_reach, Vector2(spread + lead, stagger).length())


# The skid — the stick pulled against travel at speed — as a snowplow: both
# skates out wide and set toward the travel, toes in, so the splayed legs put
# both blades on their inside edges against it. `along` is the travel in the
# legs' frame, (right, back).
func _skid_path(w: float, along: Vector2) -> void:
	var c: SkaterController = _controller
	var t: Vector2 = along.normalized() if along.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	var spread: float = c.reversal_spread_m
	var lead: float = c.reversal_lead_m
	l_dx += w * (t.x * lead - spread)
	r_dx += w * (t.x * lead + spread)
	l_dz += w * t.y * lead
	r_dz += w * t.y * lead
	var toe_in: float = deg_to_rad(c.reversal_toe_in_deg)
	l_yaw -= w * toe_in
	r_yaw += w * toe_in
	push_reach = maxf(push_reach, Vector2(spread + lead, 0.0).length())


# Backward C-cuts, as where the skates go. Skating backward the push goes ahead
# of the hips: each skate sweeps out and forward and curls back in, drawing a C
# out front, then returns close to centre with its blade still down. The toe
# turns out as the C starts and in as it ends. `p` runs from 0 under the hips to
# 1 at the C's end; the push is the stroke's falling half, its return the
# rising one, and the bulge is zero at both ends, where they hand over.
func _ccut_path(w: float, a: float, s: float, s_opp: float, cs: float, cs_opp: float) -> void:
	var c: SkaterController = _controller
	var out: float = c.ccut_out_m * a
	var front: float = c.ccut_front_m * a
	var toe: float = deg_to_rad(c.ccut_toe_deg) * minf(a, 1.0)
	var p_l: float = 0.5 * (1.0 - s)
	var p_r: float = 0.5 * (1.0 - s_opp)
	var bulge_l: float = sin(PI * p_l) * (1.0 if cs <= 0.0 else c.ccut_return_share)
	var bulge_r: float = sin(PI * p_r) * (1.0 if cs_opp <= 0.0 else c.ccut_return_share)
	l_dx -= w * out * bulge_l
	r_dx += w * out * bulge_r
	l_dz -= w * front * p_l
	r_dz -= w * front * p_r
	l_yaw += w * toe * cos(PI * p_l)
	r_yaw -= w * toe * cos(PI * p_r)
	l_push = maxf(l_push, w * maxf(-cs, 0.0))
	r_push = maxf(r_push, w * maxf(-cs_opp, 0.0))
	push_reach = maxf(push_reach, Vector2(out, front).length())


# The side-step, as where the skates go: the skates scissor sideways half a
# cycle apart, each stepping toward the travel (`side`, +1 right) with a lift and
# pushing back away from it along the ice.
func _shuffle_path(w: float, side: float, a: float, s: float, s_opp: float,
		cs: float, cs_opp: float) -> void:
	var c: SkaterController = _controller
	var step: float = c.shuffle_step_m * a
	var lift: float = c.shuffle_lift_m * a
	l_dx += w * side * step * s
	r_dx += w * side * step * s_opp
	l_dy += w * lift * maxf(cs, 0.0)
	r_dy += w * lift * maxf(cs_opp, 0.0)
	l_push = maxf(l_push, w * maxf(-cs, 0.0))
	r_push = maxf(r_push, w * maxf(-cs_opp, 0.0))
	push_reach = maxf(push_reach, step)


# How hard the stroking states push, for the push sounds: the stroke's amplitude
# by their share of the mix (0 coasting, ~1 striding flat out, more driving hard).
func push_strength() -> float:
	return intensity * push_scale * (mix.stride + mix.crossover + mix.backward + mix.shuffle)


# How hard a start digs in, for its chop: the acceleration the physics is making
# against the one that reads as full effort, by how near a standstill it is and
# the share of the states that start from one. The share is the one being
# skated toward, not the eased mix: a start's first push is under way before
# the stride has eased in, and it is the hardest one.
func dig_strength() -> float:
	return _start * clampf(_fd_effort_target, 0.0, 1.0) * (_target.stride + _target.backward)


# How engaged the stroke is, 0..1: its intensity against the share of top speed
# the crouch fully engages at.
func _engaged() -> float:
	return clampf(intensity / maxf(_controller.stance_full_speed_fraction, 0.01), 0.0, 1.0)


# Crouch engagement per state: the striding states sit with speed and effort,
# the dug-edge states sit deep, the glide keeps working knees at speed.
func _stance(s: float) -> void:
	var c: SkaterController = _controller
	var stroke: float = _engaged() \
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
	l_roll = 0.0
	r_roll = 0.0
	l_tuck = 0.0
	r_tuck = 0.0
	l_dx = 0.0
	l_dy = 0.0
	l_dz = 0.0
	l_yaw = 0.0
	r_dx = 0.0
	r_dy = 0.0
	r_dz = 0.0
	r_yaw = 0.0
	l_push = 0.0
	r_push = 0.0
	push_reach = 0.0
	authored = 0.0
	sliding = 0.0
	trunk_pitch = 0.0
	trunk_roll = 0.0
	bob = 0.0
	edge_floor = 0.0

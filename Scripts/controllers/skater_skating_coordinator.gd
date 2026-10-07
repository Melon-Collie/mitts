class_name SkaterSkatingCoordinator
extends RefCounted

# The procedural gait — no animation clips. The locomotion state and its leg
# stroke are SkaterLocomotion's; this class layers everything else on them —
# the shot loads and kicks, the block, the faceoff stance, the knockdown, the
# check and the stick lift — resolves the legs into joint angles and a crouch
# drop, and publishes the trunk texture and the lower-body yaw channels.
# Purely cosmetic and derived entirely from replicated state, so it costs zero
# network state: remote skaters animate identically from what interpolation
# already hands them.
#
# Runs on real render ticks only — SkaterController guards the call with
# `not is_replaying` so reconcile re-simulation doesn't over-spin the gait.

const State = SkaterStateMachine.State

# MESH-NATIVE leg segment spans from Scenes/Skater.tscn — hip pivot to knee
# pivot (LegL → ShinL) and knee pivot to skate sole (ShinL → FootL). Used to
# derive the stance knee flex and body drop from the hip flex so the crouch
# keeps the skates planted. Keep in sync with the scene if the leg pivots
# move. The knee-flex math only reads their RATIO, so it is build-independent;
# the vertical drop is a length and rides `leg_scale` below.
const _THIGH_LEN: float = 0.31
const _SHIN_LEN: float = 0.45
# Forward offset from the shin's end to the FOOT pivot (ShinL → FootL local −Z):
# the boot's centre sits ahead of the ankle, not under it. Folding the shin
# swings this offset from horizontal toward straight DOWN, so any solve that
# holds the boot LEVEL — the shot block's extended leg, the faceoff centre's
# address — owes the height it costs, or it buries that skate in the ice. A boot
# left to tilt with its shin does not: it keeps its sole planted, which is the
# model the stance crouch solves.
const _FOOT_FWD: float = 0.10

# Quiet time before the settled early-out in apply() engages. Sized to sit well
# past the slowest smoothed channel's convergence (the eases run at ≥ ~5/s, so
# one second leaves residuals under e⁻⁵ ≈ 0.7% of amplitude).
const _SETTLE_SECONDS: float = 1.0

# Smoothing rate of the ψ-rate signal the pivot detector thresholds. A trigger,
# not a pose channel, so a plain smoothed per-frame FD suffices (high-fps
# zero-tick frames average out through the ease instead of aliasing a pose).
const _PSI_RATE_EASE: float = 10.0

# Low-pass rate of the ψ every POSE-side consumer reads (the hemisphere fade
# and the whole pivot read). Raw ψ carries high-frequency content the pose must
# not: per-tick velocity-direction noise, and the facing tracker's
# freeze/unfreeze stutter at its unreachable-wedge gate — and the pivot
# consumes ψ multiplicatively (authority × phase × anchors), so every wiggle
# hits the hips three ways. One angle-aware filter upstream quiets all of them;
# the rate detector keeps reading raw ψ.
const _PSI_SMOOTH_EASE: float = 15.0

var _skater: Skater = null
var _sm: SkaterStateMachine = null
var _controller: SkaterController = null  # tunables live as @export on the controller

# Settled early-out state (see the block at the top of apply()).
var _settle_timer: float = 0.0
var _settled: bool = false

# Height multiplier for this build's legs, set by SkaterController
# .apply_attributes alongside the skeleton scaling (the appearance pass
# lengthens the actual leg pivot chain by the same factor). Scales the
# crouch's vertical body drop so the flexed legs' deficit matches the longer
# segments; the knee ANGLES are ratio-derived and stay build-independent.
var leg_scale: float = 1.0


# This build's (thigh, shin) segment lengths in metres — the knockdown sprawl
# solve (SkaterController._apply_knockdown_fall) shares the leg geometry the
# crouch solve uses, served from the one place that owns it.
func leg_segment_lengths() -> Vector2:
	return Vector2(_THIGH_LEN, _SHIN_LEN) * leg_scale


# How far the centre's faceoff address drops his body, in metres — the same
# crouch the gait settles at over the dot, derived instead of measured because
# the placement that needs it runs at the whistle, before the pose exists (and
# on a body still carrying whatever depth it was skating at). Full leg length
# minus the vertical span left by the address's hip flex, its knee (the flex
# that keeps the skate under the hip) and the cosine the width splay costs.
# test_faceoff_prep_pose.gd holds this against the settled live crouch.
func faceoff_address_drop() -> float:
	var hip: float = deg_to_rad(
			_controller.stance_hip_deg * _controller.faceoff_center_stance)
	var knee: float = hip + asin(
			clampf(_THIGH_LEN / _SHIN_LEN * sin(hip), -1.0, 1.0))
	var shin: float = knee - hip
	var span: float = leg_scale * (_THIGH_LEN * cos(hip) + _SHIN_LEN * cos(shin)
			+ _FOOT_FWD * sin(shin))
	return leg_scale * (_THIGH_LEN + _SHIN_LEN) \
			- span * cos(deg_to_rad(_controller.faceoff_center_width_deg))

# ── Runtime State ─────────────────────────────────────────────────────────────
var stride_phase: float = 0.0
# Per-stride trunk texture, written onto the cosmetic torso/helmet/shoulder
# BONES via Skater.set_trunk_texture — never onto the UpperBody node, whose
# rotation carries the blade markers (gameplay geometry; see the invariant in
# SkaterPoseCoordinator._apply_lean). Radians; updated on real ticks only, so
# it holds steady through reconcile replay like the rest of the gait.
var trunk_pitch_add: float = 0.0
var trunk_roll_add: float = 0.0
# Body drop of the crouch this pose pass settled on, in metres. Published
# because the faceoff placement measures the stick's span from the hand height
# the crouch leaves, and a skater's live depth is whatever he was skating at.
var crouch_drop: float = 0.0
# Inertia-filter state for the summed trunk texture (see the publish tail of
# apply() and trunk_texture_smooth_rate).
var _trunk_pitch_s: float = 0.0
var _trunk_roll_s: float = 0.0
# Eased 0..1 "committing a check" stance factor, tracked toward skater.hit_committed
# at render rate. Drives the load-up lean and crouch below.
var _hit_commit_blend: float = 0.0
# Smoothed faceoff ready-stance engagement, so the crouch eases in over the
# countdown and releases into the draw instead of popping on the phase flip.
# Published: the address is not only a leg pose — the hands take their draw grip
# on the same ease (SkaterIKCoordinator.update_bottom_hand).
var faceoff_blend: float = 0.0
# Radians of lower-body rotation.y the hockey stop turns the hips across travel
# (SkaterLocomotion.stop_yaw, republished for the pose coordinator's yaw sum).
var stop_yaw_offset: float = 0.0
# Hip-to-travel alignment (see the block in apply()).
var travel_align_yaw: float = 0.0
var _hip_align_yaw: float = 0.0
# Pivot read (PivotRules; the pivot block in apply()). The ψ finite difference
# mirrors the effort FD idiom; the engage/sense latches and blend mirror the
# hockey stop. Published THROUGH travel_align_yaw — while engaged the pivot IS
# the hip-alignment law, so it needs no lower-body channel of its own.
var _prev_psi: float = 0.0
var _have_prev_psi: bool = false
var _psi_smooth: float = 0.0
var _psi_rate: float = 0.0
var _pivot_engaged: bool = false
var _pivot_sense: float = 1.0
var _pivot_blend: float = 0.0
var _pivot_dwell: float = 0.0
# Pivot authority [0, 1], published for SkaterPoseCoordinator: while the hold
# owns the lower-body channel, the generic facing-lag pump fades out of the
# sum — two writers tracking the same rotation on different clocks is a
# wobble, not a pose.
var pivot_hold: float = 0.0
# Shot body animation (see the Shot block in apply()). Driven from the
# replicated current_shot_state + shot_charge, exactly like the stick flex:
# the wrister load tracks the drag-charge through WRISTER_AIM, the slapper
# load tracks the wind-up through the charge states, and the transition into
# FOLLOW_THROUGH latches the smoothed load as the release kick's power (the
# raw charge may already be zeroed by then), with the kick's amplitude set
# picked by which charge it came from. shot_hip_yaw is radians of lower-body
# rotation.y.
var shot_hip_yaw: float = 0.0
var _shot_prev_state: int = 0
var _wrister_load: float = 0.0      # smoothed 0..1 drag-charge engagement
var _slap_load: float = 0.0         # smoothed 0..1 wind-up engagement
var _shot_kick_t: float = -1.0      # seconds into the release kick; <0 = idle
var _shot_kick_power: float = 0.0   # load latched at release (min-pop floored)
var _shot_kick_is_slap: bool = false
# Smoothed shot-block engagement: the one-knee drop snaps in with the committed
# plant and eases back out on release. Keyed off the replicated
# current_shot_state like the shot signals above.
var _block_blend: float = 0.0
# Check-delivery drive: the hitter's shoulder finishing through the contact.
# Started by SkaterController.start_check_drive off the host-authoritative
# body_check_landed broadcast (and the replay event dispatcher), so every
# machine plays the identical drive the same frame as the burst/thud.
var _drive_dir: Vector3 = Vector3.ZERO  # world-space, attacker → victim
var _drive_t: float = -1.0              # seconds into the drive; <0 = idle
var _drive_intensity: float = 0.0       # 0..1 VFX hit hardness
# Smoothed stick-lift engagement — the working posture while jabbing under an
# opponent's stick. Keyed off the replicated blade_up.
var _lift_blend: float = 0.0

var _locomotion := SkaterLocomotion.new()

func setup(skater: Skater, sm: SkaterStateMachine, controller: SkaterController) -> void:
	_skater = skater
	_sm = sm
	_controller = controller
	_locomotion.setup(skater, controller)


# Snaps the gait back to a clean standstill and plants the legs at their rest
# pose. Called on faceoff / respawn teleports so a skater doesn't drop into the
# dot mid-stride carrying the previous shift's leg swing.
func reset_to_rest() -> void:
	_locomotion.reset()
	stride_phase = 0.0
	crouch_drop = 0.0
	faceoff_blend = 0.0
	trunk_pitch_add = 0.0
	trunk_roll_add = 0.0
	_trunk_pitch_s = 0.0
	_trunk_roll_s = 0.0
	stop_yaw_offset = 0.0
	travel_align_yaw = 0.0
	_hip_align_yaw = 0.0
	_prev_psi = 0.0
	_have_prev_psi = false
	_psi_smooth = 0.0
	_psi_rate = 0.0
	_pivot_engaged = false
	_pivot_sense = 1.0
	_pivot_blend = 0.0
	_pivot_dwell = 0.0
	pivot_hold = 0.0
	shot_hip_yaw = 0.0
	_shot_prev_state = 0
	_wrister_load = 0.0
	_slap_load = 0.0
	_shot_kick_t = -1.0
	_shot_kick_power = 0.0
	_shot_kick_is_slap = false
	_block_blend = 0.0
	_drive_dir = Vector3.ZERO
	_drive_t = -1.0
	_drive_intensity = 0.0
	_lift_blend = 0.0
	if _skater != null:
		_skater.set_leg_swing(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		_skater.set_skating_crouch_drop(0.0)
		_skater.set_trunk_texture(0.0, 0.0)
		_skater.set_edge_loads(0.0, 0.0)


# The ready-stance crouch floor and foot split for this skater's role at the
# dot: the centre taking the draw sits deeper and splits wider than the players
# lined up behind him (see SkaterController.faceoff_center_stance). Both read
# the same replicated-by-derivation flag, so a wire-fed remote centre poses
# identically to a locally-simulated one.
func _faceoff_stance_floor() -> float:
	return _controller.faceoff_center_stance if _skater.is_faceoff_center \
			else _controller.faceoff_stance


func _faceoff_split_deg() -> float:
	return _controller.faceoff_center_split_deg if _skater.is_faceoff_center \
			else _controller.faceoff_split_deg


# Arms the check-delivery drive (see the runtime state above). During
# sustained contact or a quick follow-up hit inside an active drive the
# broadcast can re-fire: harden the intensity but never restart the clock —
# a re-zeroed envelope would pin the pose at its rise for as long as the
# contact grinds.
func start_check_drive(hit_dir: Vector3, intensity: float) -> void:
	var flat := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if flat.length_squared() < 0.0001 or intensity <= 0.0:
		return
	if _drive_t >= 0.0:
		_drive_intensity = maxf(_drive_intensity, intensity)
		return
	_drive_dir = flat.normalized()
	_drive_intensity = intensity
	_drive_t = 0.0

# ── Per-Tick Application ──────────────────────────────────────────────────────
func apply(delta: float) -> void:
	if _skater == null or delta <= 0.0:
		return

	# ── Settled early-out ──────────────────────────────────────────────────────
	# At true rest the converged gait pose is static: with no inputs, no speed,
	# no timers and a plain skating state, every smoothed channel decays to zero
	# and the pass rewrites the same rest pose every frame — the fixed cost the
	# micro-benchmark's "at rest" row measures. Detect the steady state from the
	# same replicated inputs the pass itself reads (so remotes settle too), and
	# once quiet has held for _SETTLE_SECONDS — long past every ease/spring's
	# convergence, residuals far below perception — snap to the exact rest pose
	# once (reset_to_rest) and hold. Any input, speed, timer, or state change
	# fails `quiet` and the full pass runs again the same frame.
	var qvel: Vector3 = _skater.velocity
	var quiet: bool = (
			qvel.x * qvel.x + qvel.z * qvel.z < 0.0025
			and _skater.move_intent.length_squared() <= 0.0025
			and not _skater.brake_intent
			and not _controller.sprint_active
			and not _skater.hit_committed
			and not _skater.blade_up
			and (_skater.current_shot_state == State.SKATING_WITH_PUCK
				or _skater.current_shot_state == State.SKATING_WITHOUT_PUCK)
			and _skater.current_shot_state == _shot_prev_state
			and _controller.stagger_timer <= 0.0
			and _controller.knockdown_timer <= 0.0
			and _drive_t < 0.0 and _shot_kick_t < 0.0
			and not _controller.is_faceoff_ready()
			and _controller.celebration_progress() <= 0.0)
	if quiet:
		_settle_timer = minf(_settle_timer + delta, _SETTLE_SECONDS)
		if _settle_timer >= _SETTLE_SECONDS:
			if not _settled:
				_settled = true
				reset_to_rest()
				# reset_to_rest clears the shot-transition latch to 0; re-stamp
				# the live state or `quiet` fails every other frame and the
				# settle/reset cycle never holds.
				_shot_prev_state = _skater.current_shot_state
			return
	else:
		_settle_timer = 0.0
		_settled = false

	var vel: Vector3 = _skater.velocity
	# Ground speed only — vertical velocity never feeds the stride.
	var ground_speed: float = Vector2(vel.x, vel.z).length()
	# Plant the legs while shot-blocking (the one-knee drop below owns them). Read
	# off the REPLICATED shot state, not the state machine — a wire-fed remote's
	# state machine is never ticked, so it would never see the block.
	var planted: bool = _skater.current_shot_state == State.SHOT_BLOCKING

	# ── Shots: load + release kick signals ─────────────────────────────────────
	# The wrister load tracks the drag-charge through WRISTER_AIM; the slapper
	# load tracks the wind-up through the charge states. Entering FOLLOW_THROUGH
	# latches the smoothed load as the kick's power (floored by the min pop so
	# an uncharged snap still reads and a short-wind slap still commits), with
	# the amplitude set picked by which charge it came from — a quick-shot pass
	# (no charge state at all) rides the wrister set, the same split the stick
	# flex uses. The kick then rides the shared asymmetric arc (fast weight
	# transfer through the release, slow settle) on its own cosmetic timer —
	# remotes don't see the state machine's follow-through timer, only the
	# state flip.
	var shot_state: int = _skater.current_shot_state
	# The one-timer's retention hold is the loaded tail of the wind-up, so the
	# legs stay in the slapper load through it — and the follow-through it hands
	# off to is a slap kick, not a wrister's (every one-timer now reaches
	# FOLLOW_THROUGH via retention, so omitting it here would misclassify all of
	# them).
	var in_slap_charge: bool = shot_state == State.SLAPPER_CHARGE_WITH_PUCK \
			or shot_state == State.SLAPPER_CHARGE_WITHOUT_PUCK \
			or shot_state == State.ONE_TIMER_RETENTION
	if shot_state != _shot_prev_state:
		if shot_state == State.FOLLOW_THROUGH:
			_shot_kick_t = 0.0
			_shot_kick_is_slap = _shot_prev_state == State.SLAPPER_CHARGE_WITH_PUCK \
					or _shot_prev_state == State.SLAPPER_CHARGE_WITHOUT_PUCK \
					or _shot_prev_state == State.ONE_TIMER_RETENTION
			if _shot_kick_is_slap:
				_shot_kick_power = maxf(_slap_load, _controller.slapper_kick_min_power)
			else:
				# Latch from the release charge as well as the smoothed aim load:
				# the frozen wrister is a quick flick, so _wrister_load never builds
				# over the brief coil and would pin the kick at the min-power floor.
				# shot_charge holds the release power through the follow-through, so
				# a hard flick drives a hard leg kick; on the non-frozen path
				# _wrister_load ≈ shot_charge and the max changes nothing.
				_shot_kick_power = maxf(
						maxf(_wrister_load, _skater.shot_charge),
						_controller.wrister_kick_min_power)
		_shot_prev_state = shot_state
	var wrister_target: float = _skater.shot_charge if shot_state == State.WRISTER_AIM else 0.0
	_wrister_load = lerpf(_wrister_load, wrister_target,
			minf(_controller.wrister_load_blend_speed * delta, 1.0))
	# Slapper wind-up engagement, re-derived from the replicated charge the way
	# every machine can: shot_charge and the wind-up pose both fill over
	# max_slapper_charge_time (the pose is the charge gauge — see
	# SkaterController.slapper_wind_up_t), so shot_charge IS the wind-up
	# progress; sqrt-ease to match the torso coil's front-loaded snap
	# (SkaterPoseCoordinator.apply_upper_body).
	var slap_target: float = 0.0
	if in_slap_charge:
		slap_target = sqrt(clampf(_skater.shot_charge, 0.0, 1.0))
	_slap_load = lerpf(_slap_load, slap_target,
			minf(_controller.wrister_load_blend_speed * delta, 1.0))
	var kick_env: float = 0.0
	if _shot_kick_t >= 0.0:
		_shot_kick_t += delta
		var kick_total: float = _controller.slapper_kick_time if _shot_kick_is_slap \
				else _controller.wrister_kick_time
		var kt: float = _shot_kick_t / maxf(kick_total, 0.001)
		if kt >= 1.0:
			_shot_kick_t = -1.0
		else:
			kick_env = sin(PI * pow(kt, _controller.follow_through_arc_skew)) * _shot_kick_power
	# Shot-block engagement: fast into the committed plant, eased back out on
	# release so the knee drop doesn't pop back to a stride.
	_block_blend = lerpf(_block_blend, 1.0 if planted else 0.0,
			minf(_controller.block_pose_blend_speed * delta, 1.0))
	# Check-delivery drive envelope: an explosive rise (peaks ~15% in) easing
	# out over check_drive_time — the shoulder finishing through the contact.
	var drive_env: float = 0.0
	if _drive_t >= 0.0:
		_drive_t += delta
		var du: float = _drive_t / maxf(_controller.check_drive_time, 0.001)
		if du >= 1.0:
			_drive_t = -1.0
		else:
			drive_env = sin(PI * pow(du, 0.35)) * _drive_intensity
	# Stick-lift read, off the replicated blade_up (own lift or a forced pop —
	# either way the body reacts).
	_lift_blend = lerpf(_lift_blend, 1.0 if _skater.blade_up else 0.0,
			minf(_controller.stick_lift_blend_speed * delta, 1.0))
	# Celebration window: this pass runs at RENDER rate (Skater._process) and is
	# visibility-gated, so it only READS the progress — the callers age the timer
	# at physics rate (SkaterController._process_input / RemoteController.
	# _physics_process) so it stays deterministic and never freezes off-screen.
	var celebr_p: float = _controller.celebration_progress()
	# Combined engagement, for the stride suppression below — shooting is a
	# glide (the feet set through the load and drive through the release), and
	# a landed check plants through the finish.
	var shot_body: float = maxf(maxf(_wrister_load, _slap_load), maxf(kick_env, drive_env))
	var stick_side: float = -1.0 if _skater.is_left_handed else 1.0
	# Hips coil with the load (stick-side hip pulls back, riding the torso coil
	# — the wrister's blade-tracking twist or the slapper's authored wind-up
	# coil) and uncoil THROUGH the release — the stick-side hip drives forward
	# past square, mirroring the follow-through's torso `through` term.
	# Positive lower-body yaw turns the legs toward −X, i.e. pulls the +X hip
	# forward, hence the signs.
	var kick_hip_yaw_deg: float = _controller.slapper_kick_hip_yaw_deg if _shot_kick_is_slap \
			else _controller.wrister_kick_hip_yaw_deg
	shot_hip_yaw = -stick_side * (
				deg_to_rad(_controller.wrister_load_hip_coil_deg) * _wrister_load
				+ deg_to_rad(_controller.slapper_load_hip_coil_deg) * _slap_load) \
			+ stick_side * deg_to_rad(kick_hip_yaw_deg) * kick_env

	# ── Locomotion ─────────────────────────────────────────────────────────────
	# Which skating state the skater is in and the stroke it skates
	# (SkaterLocomotion). Shooting sets the feet and the pivot glides through its
	# transit, so both hold the stroke; the block takes the legs outright.
	var basis_inv: Basis = _skater.global_transform.basis.inverse()
	_locomotion.sense(delta, planted, maxf(shot_body * _controller.shot_stride_fade,
			_pivot_blend * _controller.pivot_stride_fade))
	var mix: LocomotionRules.Mix = _locomotion.mix
	stride_phase = _locomotion.stride_phase
	stop_yaw_offset = _locomotion.stop_yaw
	# Path curvature as a carve engagement, 0..1: blades committed to carving
	# edges cannot pivot.
	var curve: float = clampf(absf(_locomotion.turn_rate)
			/ maxf(_controller.carve_ref_turn_rate, 0.001), 0.0, 1.0)
	var local_vel: Vector3 = basis_inv * vel
	var fwd: float = -local_vel.z

	# ── Hip-to-travel alignment ────────────────────────────────────────────────
	# Real skaters' hips align with the direction of MOTION while the torso
	# twists toward the play; the legs stride along travel, not along the
	# chest. Facing follows the cursor here (twin-stick), so without this any
	# cursor-vs-movement misalignment bled the stride into the crossover /
	# backward blends and read as leg flail — systematically worse in the
	# rink direction where the tilted camera makes leading the cursor
	# awkward. The hips yaw toward travel (speed-gated so they settle back
	# under the torso at rest, clamped so genuinely backward/lateral skating
	# still plays the C-cut/crossover gaits on the residual), and the gait
	# below re-decomposes velocity in the HIP frame the legs actually occupy.
	# The hockey stop overrides alignment while blended in — perpendicular
	# beats parallel on the same lower-body channel.
	var align_target: float = 0.0
	# ψ — the travel direction in the body frame. Zero speed leaves it at the
	# previous sample: atan2 of a near-zero vector is noise, and the pivot
	# below releases on the speed floor anyway.
	var psi: float = _prev_psi
	if ground_speed > 0.1:
		psi = atan2(local_vel.x, fwd)
		var align_engage: float = clampf(
				_locomotion.intensity / maxf(_controller.stance_full_speed_fraction, 0.01), 0.0, 1.0)
		# rotation.y positive turns the legs toward −X, i.e. toward NEGATIVE
		# body-frame angles — hence the negation.
		align_target = clampf(-psi,
				-deg_to_rad(_controller.hip_align_max_deg),
				deg_to_rad(_controller.hip_align_max_deg)) * align_engage
	# ψ low-passed for every pose-side consumer (see _PSI_SMOOTH_EASE). Snapped
	# on the first sample so a mid-motion spawn doesn't sweep the filter
	# through the band from zero.
	if not _have_prev_psi:
		_psi_smooth = psi
	else:
		_psi_smooth = wrapf(_psi_smooth
				+ angle_difference(_psi_smooth, psi) * minf(_PSI_SMOOTH_EASE * delta, 1.0),
				-PI, PI)
	var abs_psi: float = absf(_psi_smooth)
	var band_lo: float = deg_to_rad(_controller.pivot_band_lo_deg)
	var band_hi: float = deg_to_rad(_controller.pivot_band_hi_deg)
	# A deliberate backpedal or sidestep is an AIM-LOCKED stance — the
	# defender back-skates and the net-front shuffler side-steps with hips
	# square to the chest, so intent suppresses the travel alignment and the
	# body-frame backward / lateral gaits play in full.
	align_target *= 1.0 - maxf(mix.backward, mix.shuffle)
	# Hips align TOWARD travel only while travel is broadly ahead: past 90° the
	# sensible anchor flips to hips-square (the backward C-cut stance), so the
	# clamp's ±hip_align_max pull fades out geometrically across the band's
	# back half. The intent suppression above covers the deliberate backpedal;
	# this covers the same geometry when no intent is held — most visibly the
	# pivot's release tail, which would otherwise hand the hips from the
	# step-around straight to a ±50° yank toward a behind-the-back travel line.
	align_target *= 1.0 - clampf(
			(abs_psi - PI * 0.5) / maxf(band_hi - PI * 0.5, 0.001), 0.0, 1.0)
	# ── Pivot: the facing↔travel swap ──────────────────────────────────────────
	# ψ transiting the lateral band at speed is a pivot — the one event the
	# twin-stick scheme produces two ways (cursor swung across a held travel
	# line, or travel swung under a held cursor) that are identical in the body
	# frame, so one read covers both. The dψ/dt trigger separates it from a
	# carve for free: ψ = travel heading − facing heading, and a coordinated
	# carve rotates both together (ψ barely moves) while a pivot whips facing
	# against travel. While engaged the hips get the one thing the alignment
	# clamp forbids — tracking ψ fully — holding the entry orientation on the
	# gliding blades, then stepping around to the exit orientation over the
	# transit's tail (PivotRules.pivot_yaw). Phase derives from ψ's actual
	# progress, not a timer: a snap pivot and a slow open-hip glide both read
	# right, and an aborted swing unwinds back through the same poses.
	var psi_rate_raw: float = 0.0
	if _have_prev_psi:
		psi_rate_raw = angle_difference(_prev_psi, psi) / delta
	_prev_psi = psi
	_have_prev_psi = true
	_psi_rate = lerpf(_psi_rate, psi_rate_raw, minf(_PSI_RATE_EASE * delta, 1.0))
	if _pivot_engaged:
		if PivotRules.should_release(abs_psi, ground_speed, band_lo, band_hi,
				_controller.pivot_min_speed):
			_pivot_engaged = false
	elif PivotRules.should_engage(abs_psi, absf(_psi_rate), ground_speed,
			band_lo, band_hi, _controller.pivot_rate_min, _controller.pivot_min_speed):
		_pivot_engaged = true
		_pivot_sense = PivotRules.latch_sense(abs_psi, band_lo, band_hi)
	# The blend eases toward authority earned three ways, never a latched 1 —
	# because this cursor also stickhandles and aims, and the blend gates the
	# STRIDE (gait_scale + phase rate), so spurious authority reads as the
	# legs stuttering mid-stride, not just a hip nudge:
	# depth — a flick clipping the band's shallow edge gets only a light lag;
	# dwell — a flick RETURNS inside ~150 ms while a pivot PARKS ψ across the
	# body, so full authority needs pivot_commit_time of continuous residence
	# (a real skater takes about that long to commit the hips anyway);
	# no carve — leading the cursor through a hard turn can carry ψ deep, but
	# blades committed to carving edges cannot pivot, so real path curvature
	# vetoes (the same smoothed curvature signal the crossover cadence uses).
	var pivot_target_blend: float = 0.0
	if _pivot_engaged:
		_pivot_dwell += delta
		pivot_target_blend = PivotRules.hold_depth(abs_psi, band_lo,
				deg_to_rad(_controller.pivot_depth_ramp_deg)) \
				* clampf(_pivot_dwell / maxf(_controller.pivot_commit_time, 0.001), 0.0, 1.0) \
				* (1.0 - curve)
	else:
		_pivot_dwell = 0.0
	_pivot_blend = lerpf(_pivot_blend, pivot_target_blend,
			_controller.pivot_blend_speed * delta)
	pivot_hold = _pivot_blend
	var align_speed: float = _controller.hip_align_speed
	var pivot_yaw_l: float = 0.0
	var pivot_yaw_r: float = 0.0
	if _pivot_blend > 0.001:
		var pivot_p: float = PivotRules.phase(abs_psi, _pivot_sense, band_lo, band_hi)
		var pivot_target: float = PivotRules.pivot_yaw(_psi_smooth, _pivot_sense, pivot_p,
				_controller.pivot_step_begin)
		# Mohawk V — the replay-camera read: the LEAD skate externally rotates
		# toward the step direction while the trail skate holds the old line,
		# heel-to-heel through the middle of the transit. A half-sine of the
		# phase opens the V out of the entry and closes it into the step; the
		# yaw lands on the hip pivot so the shin and boot carry it. The lead
		# is the leg on the side the hips will rotate toward (positive
		# lower-body yaw turns the legs toward −X → left leads).
		var v_open: float = deg_to_rad(_controller.pivot_mohawk_deg) * _pivot_blend \
				* sin(PI * pivot_p)
		var step_sign: float = signf(_psi_smooth) * _pivot_sense
		if step_sign > 0.0:
			pivot_yaw_l = v_open
		elif step_sign < 0.0:
			pivot_yaw_r = -v_open
		# The pivot target overrides the intent suppression above on purpose: a
		# key held through the swing flips to a backpedal read mid-transit,
		# which must not zero the hold.
		align_target = lerpf(align_target, pivot_target, _pivot_blend)
		align_speed = lerpf(align_speed, _controller.pivot_yaw_speed, _pivot_blend)
	_hip_align_yaw = lerpf(_hip_align_yaw, align_target, align_speed * delta)
	travel_align_yaw = _hip_align_yaw * (1.0 - mix.stop)
	# Velocity in the yawed hip frame: v_hip = RotY(−ψ) · v_local.
	var hip_cos: float = cos(travel_align_yaw)
	var hip_sin: float = sin(travel_align_yaw)
	var hip_x: float = local_vel.x * hip_cos - local_vel.z * hip_sin
	var hip_z: float = local_vel.x * hip_sin + local_vel.z * hip_cos
	fwd = -hip_z

	_locomotion.strokes(delta, fwd)

	# ── Stance: the crouch ─────────────────────────────────────────────────────
	# The locomotion state's own sit, floored by everything layered on it. From
	# the hip flex alone, the knee flex that keeps the skate under the hip
	# (knee = hip + asin(thigh/shin · sin(hip))) and the vertical deficit of the
	# bent leg both follow from the leg geometry; the deficit is applied as a
	# whole-body drop (Skater.set_skating_crouch_drop) so the skates stay on the
	# ice.
	var stance: float = _locomotion.stance
	# Faceoff ready stance: at the dot the skater is at a standstill, so the
	# speed-driven envelope leaves them bolt upright — floor the engagement
	# through the countdown instead. Eased both ways: the crouch settles in
	# over the prep and releases into the draw as the players explode out.
	# The two centres sit far deeper than the players behind them.
	faceoff_blend = lerpf(faceoff_blend,
			1.0 if _controller.is_faceoff_ready() else 0.0,
			_controller.stride_intensity_speed * delta)
	if faceoff_blend > 0.001:
		stance = maxf(stance, _faceoff_stance_floor() * faceoff_blend)
	# The pivot sits too: the open-hip glide and the step-around are both done
	# on bent knees.
	stance = maxf(stance, _controller.pivot_stance * _pivot_blend)
	# Shot loads sit INTO the shot as the charge builds (the slapper wind-up
	# deepest — the power position), and the release keeps the front leg seated
	# through the drive (the back knee is pulled out of this flex by the kick
	# extension below — that asymmetry IS the weight transfer read).
	stance = maxf(stance, _controller.wrister_load_stance * _wrister_load)
	stance = maxf(stance, _controller.slapper_load_stance * _slap_load)
	var kick_stance: float = _controller.slapper_kick_stance if _shot_kick_is_slap \
			else _controller.wrister_kick_stance
	stance = maxf(stance, kick_stance * kick_env)
	# A landed check drives with the LEGS — the finishing base under the
	# shoulder — and a stick lift works from a light coil.
	stance = maxf(stance, _controller.check_drive_stance * drive_env)
	stance = maxf(stance, _controller.stick_lift_stance * _lift_blend)
	# Celebration bounce: knee pumps between straight and seated (the body
	# drop follows, so it reads as a hop bob) — 3 pumps across the window,
	# double the raised-stick pose's bob rate. Gated to plain skating like the
	# pose (SkaterController's celebration block) so it never fights a
	# follow-through kick, and ramped in over the same first 20%.
	if celebr_p > 0.0 and (shot_state == State.SKATING_WITH_PUCK
			or shot_state == State.SKATING_WITHOUT_PUCK):
		var cel_ramp: float = clampf(celebr_p / 0.2, 0.0, 1.0)
		cel_ramp = cel_ramp * cel_ramp * (3.0 - 2.0 * cel_ramp)
		var pump: float = 0.5 - 0.5 * cos(celebr_p * TAU * 3.0)
		stance = maxf(stance, _controller.celebration_leg_stance * cel_ramp * pump)
	var stance_hip: float = deg_to_rad(_controller.stance_hip_deg) * stance
	var stance_knee: float = stance_hip + asin(
			clampf(_THIGH_LEN / _SHIN_LEN * sin(stance_hip), -1.0, 1.0))
	var stance_shin: float = stance_knee - stance_hip
	var drop: float = leg_scale * (_THIGH_LEN * (1.0 - cos(stance_hip)) \
			+ _SHIN_LEN * (1.0 - cos(stance_shin)))

	var l_pitch: float = stance_hip + _locomotion.l_pitch
	var l_roll: float = _locomotion.l_roll
	var r_pitch: float = stance_hip + _locomotion.r_pitch
	var r_roll: float = _locomotion.r_roll
	var l_ext: float = _locomotion.l_ext
	var r_ext: float = _locomotion.r_ext

	# Faceoff stance: the stick-side foot drops back, braced for the draw, and
	# the centre splays both legs into the wide base he sets over the dot — a sit
	# this deep over feet at hip width is a squat, not an address. The splay
	# rotates the whole leg chain, so its vertical span is span·cos(splay) and the
	# body pays the deficit as extra drop; without it the skates ride up off the
	# ice. The ankles give the whole chain back below (foot_flat_*) so the blades
	# still lie flat — the shot block's argument, at a gentler angle.
	var faceoff_splay: float = 0.0
	var faceoff_flat: float = 0.0
	if faceoff_blend > 0.001:
		var split: float = deg_to_rad(_faceoff_split_deg()) * faceoff_blend \
				* (-1.0 if _skater.is_left_handed else 1.0)
		l_pitch += split
		r_pitch -= split
		if _skater.is_faceoff_center:
			faceoff_splay = deg_to_rad(_controller.faceoff_center_width_deg) \
					* faceoff_blend
			l_roll -= faceoff_splay
			r_roll += faceoff_splay
			drop += (leg_scale * (_THIGH_LEN + _SHIN_LEN) - drop) \
					* (1.0 - cos(faceoff_splay))
			# A sit this deep, over a base this wide, would stand both blades on
			# their heels and outside edges; the ankles give it back (an address
			# is held on flat blades, and a real ankle has the range for it).
			faceoff_flat = faceoff_blend
			# Which changes what the drop above owes. A skate left to tilt with
			# its shin keeps its SOLE planted, and that is the crouch's model; a
			# level one hangs its blade below the FOOT pivot instead, and that
			# pivot swings down as the shin folds (_FOOT_FWD), so the hip rides
			# the same amount higher. The shot block's own solve pays it too.
			drop -= leg_scale * _FOOT_FWD * sin(stance_shin) * faceoff_blend

	# Shot stance. Load: the shooting base — stick-side foot staggers back and
	# both legs roll toward it, settling the weight over the back leg while the
	# charge builds (same shared-roll idiom as the strafe lean: a common roll
	# rides the body over that side's leg); wrister and slapper loads sum, but
	# their charge states are exclusive so only the decay tails ever overlap.
	# Release: the roll flips to land the weight over the FRONT foot while the
	# back leg drives into extension behind — the kick pitch here; the knee
	# straighten below frees the shin into it.
	var shot_load_split_deg: float = _controller.wrister_load_split_deg * _wrister_load \
			+ _controller.slapper_load_split_deg * _slap_load
	var shot_load_lean_deg: float = _controller.wrister_load_lean_deg * _wrister_load \
			+ _controller.slapper_load_lean_deg * _slap_load
	if shot_load_split_deg > 0.001 or shot_load_lean_deg > 0.001:
		var load_split: float = deg_to_rad(shot_load_split_deg) * stick_side
		l_pitch += load_split
		r_pitch -= load_split
		var load_lean: float = deg_to_rad(shot_load_lean_deg) * stick_side
		l_roll += load_lean
		r_roll += load_lean
	if kick_env > 0.001:
		var kick_lean_deg: float = _controller.slapper_kick_lean_deg if _shot_kick_is_slap \
				else _controller.wrister_kick_lean_deg
		var kick_lean: float = deg_to_rad(kick_lean_deg) * kick_env * stick_side
		l_roll -= kick_lean
		r_roll -= kick_lean
		var kick_back_deg: float = _controller.slapper_kick_back_deg if _shot_kick_is_slap \
				else _controller.wrister_kick_back_deg
		var kick_back: float = deg_to_rad(kick_back_deg) * kick_env
		if stick_side > 0.0:
			r_pitch -= kick_back
		else:
			l_pitch -= kick_back

	# Knee flex — three layers that read as one leg working. (1) The stance flex,
	# the seated base both knees carry. (2) Push extension: the loaded leg
	# straightens as it extends back (stance_knee_release of the stance flex gone
	# at full extension) — the power stroke. (3) The locomotion state's own
	# folds: recovery tuck, crossover clearance, the glide's inside tuck.
	# Negative folds the shin back under the body.
	var release: float = _controller.stance_knee_release * _locomotion.intensity
	var l_knee: float = -(stance_knee * (1.0 - release * l_ext) + _locomotion.l_tuck)
	var r_knee: float = -(stance_knee * (1.0 - release * r_ext) + _locomotion.r_tuck)

	# Shot release: the back (stick-side) knee straightens through the kick —
	# extension toward 0, never past straight — while the front knee keeps the
	# full stance flex (the kick_stance floor above). Applied before the
	# fore-aft compensation so the freed shin carries into the kick's rearward
	# reach, same anatomical bookkeeping as the stride's knee layers.
	if kick_env > 0.001:
		var kick_extend_deg: float = _controller.slapper_kick_knee_extend_deg \
				if _shot_kick_is_slap else _controller.wrister_kick_knee_extend_deg
		var kick_extend: float = deg_to_rad(kick_extend_deg) * kick_env
		if stick_side > 0.0:
			r_knee = minf(r_knee + kick_extend, 0.0)
		else:
			l_knee = minf(l_knee + kick_extend, 0.0)

	# ── Knee fore-aft compensation ────────────────────────────────────────────
	# The dynamic knee layers (push extension, recovery tuck, carve clearance)
	# exist for LIFT and leg-length texture, but each also drags the FOOT
	# fore-aft: uncompensated, unfolding mid-push shoves the skate forward
	# against the thigh's backward sweep and the tuck's release adds to the
	# forward swing, so measured AT THE SKATE the stride's fast phase comes out
	# FORWARD (recovery) — the inverse of a real push (test_gait_stroke_profile
	# pins the corrected profile). Counter-pitch the thigh by the small-angle
	# FK term (Δpitch = −Δknee · L_shin / L_leg) so the foot tracks the
	# thigh-design curve — slow recovery, fast push — while the knee keeps its
	# full fold/extend range and vertical travel. Anatomically this reads
	# right: a folded shin needs more hip flex for the same skate position,
	# and the compensated full extension sits the knee joint farther back.
	var shin_frac: float = _SHIN_LEN / (_THIGH_LEN + _SHIN_LEN)
	l_pitch += -(l_knee + stance_knee) * shin_frac
	r_pitch += -(r_knee + stance_knee) * shin_frac

	drop += _locomotion.bob

	# Trunk texture: the locomotion state's sway and weight shift, then the
	# overlays' leans.
	trunk_pitch_add = _locomotion.trunk_pitch
	trunk_roll_add = _locomotion.trunk_roll
	# Check-delivery drive: the trunk drives INTO the hit — the shoulder
	# finishing through the contact. Same directional decomposition as the
	# reach lean (pitch = mag·local.z folds toward local −Z, roll = −mag·local.x),
	# re-derived body-local each tick so the lean stays on the victim line
	# while the body carries through.
	if drive_env > 0.0:
		var drive_local: Vector3 = basis_inv * _drive_dir
		var drive_mag: float = deg_to_rad(_controller.check_drive_lean_deg) * drive_env
		trunk_pitch_add += drive_mag * drive_local.z
		trunk_roll_add += -drive_mag * drive_local.x
	# Stick lift: a slight chest-up pop while jabbing under the opponent's
	# stick (positive pitch tips the shoulders back).
	trunk_pitch_add += deg_to_rad(_controller.stick_lift_trunk_deg) * _lift_blend

	# Knockdown pose factor: holds full while more than knockdown_getup_seconds
	# remains on the timer, then eases to 0 over that tail (the get-up). Derived FROM
	# the replicated knockdown_timer, so it renders identically everywhere and through
	# reconcile — same discipline as the stagger stumble below. The entry end is
	# ramped over the buckle window (KnockdownFallRules.entry_ramp — kd_t alone
	# is 1 on the first down frame, landing the whole crumple in one frame);
	# the smoothstep is inlined here because the native port mirrors this body.
	var kd_t: float = clampf(
			_controller.knockdown_timer / maxf(_controller.knockdown_getup_seconds, 0.001), 0.0, 1.0)
	if kd_t > 0.0:
		var buckle_t: float = clampf(_controller.knockdown_elapsed()
				/ maxf(_controller.knockdown_fall_buckle_seconds, 0.001), 0.0, 1.0)
		kd_t *= buckle_t * buckle_t * (3.0 - 2.0 * buckle_t)

	# Stagger stumble: a checked player visibly fights for balance. The wobble
	# phase is derived FROM stagger_timer (a uniform countdown), so every
	# machine — and reconcile replay, which snaps the timer from the host —
	# renders the identical stumble with zero new network state. Amplitude
	# tracks the time left, so the wobble eases out with the recovery window;
	# the two axes run at incommensurate frequencies so it reads as a stumble,
	# not a metronome. It is kept OUT of the summed texture and added after the
	# inertia filter at the publish tail — a stumble is supposed to shake, and
	# the filter would blunt exactly the frequencies that sell it.
	var stagger_pitch: float = 0.0
	var stagger_roll: float = 0.0
	var stagger_t: float = clampf(
			_controller.stagger_timer / maxf(_controller.stagger_max_seconds, 0.001), 0.0, 1.0)
	if stagger_t > 0.0:
		# Knockdown supersedes the stumble — fade the wobble out as the player goes down.
		var wobble_amp: float = deg_to_rad(_controller.stagger_wobble_deg) * stagger_t * (1.0 - kd_t)
		var wobble_phase: float = _controller.stagger_timer * TAU * _controller.stagger_wobble_hz
		stagger_pitch = wobble_amp * sin(wobble_phase)
		stagger_roll = wobble_amp * 0.7 * sin(wobble_phase * 1.31)

	# How much of each leg's splay and fold its ankle gives back, so the blade
	# under it lies flat on the ice (SkaterLegRig.set_ankle_flatten). Seeded by
	# the faceoff address; the block overwrites both when it takes the legs (the
	# two poses never overlap — the whistle stands a blocker up).
	var foot_flat_l: float = faceoff_flat
	var foot_flat_r: float = faceoff_flat

	# ── Shot block: the one-knee drop ─────────────────────────────────────────
	# The block a real skater plays. The STICK-SIDE knee sinks toward the ice
	# with the shin folded back along it; the far leg extends out to the other
	# side, shin low and skate on the ice. Body and stick then seal opposite
	# halves of the lane — the blade lies flat on the stick side
	# (SkaterShotPoseCoordinator.apply_block_blade_position), the extended pad
	# covers the other, which is why the block's reach is wider than the torso.
	#
	# Geometry, not authored numbers: the kneeling hip height falls out of the
	# down leg's thigh/shin angles AND the boot's forward offset under them
	# (_FOOT_FWD), and the extended leg's abduction is SOLVED from that same
	# height (its vertical span is exactly leg·cos(roll), since the knee folds in
	# the rolled leg's own sagittal plane) so its skate lands on the ice instead
	# of floating above it or scissoring through it.
	#
	# The pose REPLACES the stance rather than layering on it — lerped on
	# _block_blend like the knockdown crumple below, which supersedes it (a
	# blocker who gets run over goes down, he doesn't hold the knee).
	if _block_blend > 0.001:
		var kneel_hip: float = deg_to_rad(_controller.block_kneel_hip_deg)
		var kneel_shin: float = deg_to_rad(_controller.block_kneel_shin_deg)
		var hip_h: float = leg_scale * (_THIGH_LEN * cos(kneel_hip)
				+ _SHIN_LEN * cos(kneel_shin) + _FOOT_FWD * sin(kneel_shin))
		var ext_knee: float = deg_to_rad(_controller.block_extend_knee_deg)
		var ext_len: float = leg_scale * (_THIGH_LEN
				+ _SHIN_LEN * cos(ext_knee) + _FOOT_FWD * sin(ext_knee))
		var ext_roll: float = acos(clampf(hip_h / maxf(ext_len, 0.001), -1.0, 1.0))
		# Knee value is the total fold (hip + shin-from-vertical), negative-folds-
		# back, matching the stance_knee convention above. The extended leg rolls
		# AWAY from the body: left toward −X (negative roll), right toward +X.
		var down_knee: float = -(kneel_hip + kneel_shin)
		# The extended leg's ankle gives back what that leg took, so its blade
		# lies flat on the ice instead of swinging up onto an edge under a leg
		# splayed 60° out of vertical. The kneeling leg keeps its fold — that
		# skate is up on its toe by design.
		if stick_side > 0.0:
			foot_flat_l = _block_blend
			foot_flat_r = 0.0
		else:
			foot_flat_r = _block_blend
			foot_flat_l = 0.0
		if stick_side > 0.0:
			r_pitch = lerpf(r_pitch, kneel_hip, _block_blend)
			r_roll = lerpf(r_roll, 0.0, _block_blend)
			r_knee = lerpf(r_knee, down_knee, _block_blend)
			l_pitch = lerpf(l_pitch, 0.0, _block_blend)
			l_roll = lerpf(l_roll, -ext_roll, _block_blend)
			l_knee = lerpf(l_knee, -ext_knee, _block_blend)
		else:
			l_pitch = lerpf(l_pitch, kneel_hip, _block_blend)
			l_roll = lerpf(l_roll, 0.0, _block_blend)
			l_knee = lerpf(l_knee, down_knee, _block_blend)
			r_pitch = lerpf(r_pitch, 0.0, _block_blend)
			r_roll = lerpf(r_roll, ext_roll, _block_blend)
			r_knee = lerpf(r_knee, -ext_knee, _block_blend)
		drop = lerpf(drop, leg_scale * (_THIGH_LEN + _SHIN_LEN) - hip_h, _block_blend)

	# Knockdown crumple: sink the body toward the ice and let the stride swing go
	# limp, blended by kd_t so a downed body doesn't keep pumping strides while it
	# slides. The torso fold is layered in SkaterPoseCoordinator._apply_lean (the
	# recoil channel); here it's the drop + limp legs. Both ease back over the get-up.
	if kd_t > 0.0:
		drop = lerpf(drop, _controller.knockdown_pose_drop_m, kd_t)
		l_pitch = lerpf(l_pitch, 0.0, kd_t)
		r_pitch = lerpf(r_pitch, 0.0, kd_t)
		l_roll = lerpf(l_roll, 0.0, kd_t)
		r_roll = lerpf(r_roll, 0.0, kd_t)
		l_knee = lerpf(l_knee, 0.0, kd_t)
		r_knee = lerpf(r_knee, 0.0, kd_t)

	# Commit stance: holding the Hit button loads the skater up for the check — lean
	# forward into it and sink a touch. Off the replicated skater.hit_committed
	# (renders on remotes), eased at render rate. Suppressed while going down (kd_t)
	# so it can't fight the crumple.
	#
	# The gait owns no shoulder channel here, and must not grow one: the trunk
	# texture is symmetric, so a roll raises the trailing shoulder by exactly what
	# it drops the leading one, which is a skater tipping over rather than one
	# loading up. The per-side geometry lives in CheckStanceRules, eased at physics
	# rate on the skater (Skater._update_commit_stance) — the loaded blade reads it.
	_hit_commit_blend = move_toward(_hit_commit_blend,
			1.0 if _skater.hit_committed else 0.0, _controller.hit_commit_pose_speed * delta)
	var commit_t: float = _hit_commit_blend * (1.0 - kd_t)
	if commit_t > 0.001:
		trunk_pitch_add += -deg_to_rad(_controller.hit_commit_lean_deg) * commit_t
		drop += _controller.hit_commit_crouch_m * commit_t

	# The centre's fold over the dot. It rides the trunk TEXTURE rather than the
	# torso lean the block uses, because the lean rotates the UpperBody node the
	# blade markers hang from: the blade-first IK then has to solve a stick onto
	# the ice out of a pitched frame, and at any fold worth seeing it gives up
	# and stands the shaft on end. The texture is bones only, so the chest reads
	# folded while the stick keeps the address the centre actually took.
	if faceoff_blend > 0.001 and _skater.is_faceoff_center:
		trunk_pitch_add += -deg_to_rad(_controller.faceoff_center_lean_deg) * faceoff_blend

	# The mohawk yaw fades with the crumple like every other leg channel.
	_skater.set_leg_swing(l_pitch, l_roll, l_knee, r_pitch, r_roll, r_knee,
			pivot_yaw_l * (1.0 - kd_t), pivot_yaw_r * (1.0 - kd_t))
	# Publish per-blade edge load for the ice VFX: the push half-wave (which
	# already carries the crossover under-stroke) scaled by stroke engagement,
	# floored by the dug edges of the stop and the tight turn — and released
	# through the crumple.
	_skater.set_edge_loads(
			clampf(maxf(l_ext * _locomotion.intensity, _locomotion.edge_floor), 0.0, 1.0) * (1.0 - kd_t),
			clampf(maxf(r_ext * _locomotion.intensity, _locomotion.edge_floor), 0.0, 1.0) * (1.0 - kd_t))
	_skater.set_ankle_flatten(foot_flat_l, foot_flat_r)
	_skater.set_faceoff_address(faceoff_flat)
	crouch_drop = drop
	_skater.set_skating_crouch_drop(drop)
	# Trunk inertia: filter the summed texture, then layer the stumble wobble
	# back on top (see trunk_texture_smooth_rate).
	var tex_ease: float = 1.0
	if _controller.trunk_texture_smooth_rate > 0.0:
		tex_ease = minf(_controller.trunk_texture_smooth_rate * delta, 1.0)
	_trunk_pitch_s = lerpf(_trunk_pitch_s, trunk_pitch_add, tex_ease)
	_trunk_roll_s = lerpf(_trunk_roll_s, trunk_roll_add, tex_ease)
	trunk_pitch_add = _trunk_pitch_s + stagger_pitch
	trunk_roll_add = _trunk_roll_s + stagger_roll
	_skater.set_trunk_texture(trunk_pitch_add, trunk_roll_add)

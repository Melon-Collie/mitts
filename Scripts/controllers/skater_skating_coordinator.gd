class_name SkaterSkatingCoordinator
extends RefCounted

# The procedural gait — no animation clips. SkaterLocomotion decides the skating
# state and its stroke; this class reads the hip-to-travel alignment and the
# pivot off it, solves the stance crouch, runs the overlay layers (GaitLayer) in
# priority order over the result, and publishes the legs, the crouch drop, the
# trunk texture and the lower-body yaw channels. Purely cosmetic and derived
# entirely from replicated state, so it costs zero network state: remote skaters
# animate identically from what interpolation already hands them.
#
# Where the extension is built, the locomotion, the alignment and pivot read and
# the leg solve run in NativeSkaterGait instead (see the numeric-core section of
# Scripts/controllers/CLAUDE.md); the layers shape its pose here either way.
#
# Runs on real render ticks only — SkaterController guards the call with
# `not is_replaying` so reconcile re-simulation doesn't over-spin the gait.

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

# NativeSkaterGait.locomote flag bits.
const _NATIVE_BRAKE: int = 1
const _NATIVE_STANCE: int = 2
const _NATIVE_PLANTED: int = 4

var _skater: Skater = null
var _sm: SkaterStateMachine = null
var _controller: SkaterController = null  # tunables live on the controller

# Settled early-out state (see the block at the top of apply()).
var _settle_timer: float = 0.0
var _settled: bool = false

var _locomotion := SkaterLocomotion.new()
var _pose := GaitPose.new()
# NativeSkaterGait (native/README.md); null when the extension is absent, and the
# GDScript runs.
var _native: RefCounted = null

# The overlays, lowest priority first — the order IS the priority: an additive
# stage lays on everything before it, an override takes everything before it
# with the channels it owns. The block holds the legs over every additive
# layer; a blocker who gets run over goes down, so the knockdown is last.
var _faceoff := GaitFaceoffLayer.new()
var _stance := GaitStanceLayer.new()
var _shot := GaitShotLayer.new()
var _check := GaitCheckLayer.new()
var _lift := GaitStickLiftLayer.new()
var _celebration := GaitCelebrationLayer.new()
var _stagger := GaitStaggerLayer.new()
var _block := GaitBlockLayer.new()
var _knockdown := GaitKnockdownLayer.new()
var _layers: Array[GaitLayer] = [_faceoff, _stance, _shot, _check, _lift, _celebration,
		_stagger, _block, _knockdown]
# Per-stage subsets of _layers in the same order, each beside its layers' bits
# in the pass's active mask (built in setup).
var _hold_layers: Array[GaitLayer] = []
var _floor_layers: Array[GaitLayer] = []
var _leg_layers: Array[GaitLayer] = []
var _trunk_layers: Array[GaitLayer] = []
var _override_layers: Array[GaitLayer] = []
var _hold_bits := PackedInt32Array()
var _floor_bits := PackedInt32Array()
var _leg_bits := PackedInt32Array()
var _trunk_bits := PackedInt32Array()
var _override_bits := PackedInt32Array()

# Height multiplier for this build's legs, set by SkaterController
# .apply_attributes alongside the skeleton scaling (the appearance pass
# lengthens the actual leg pivot chain by the same factor). Scales every
# vertical length the crouch solves; the knee ANGLES are ratio-derived and stay
# build-independent.
var leg_scale: float = 1.0:
	set(value):
		leg_scale = value
		_pose.leg_scale = value
		if _native != null:
			_native.set_leg_scale(value)


# (thigh, shin, foot offset) for this build, metres — the knockdown sprawl
# (KnockdownFallRules.buckle_angles) shares the leg geometry the crouch solve
# uses. The build lengthens the leg, not the boot.
func leg_segment_lengths() -> Vector3:
	return Vector3(GaitPose.THIGH_LEN * leg_scale, GaitPose.SHIN_LEN * leg_scale, GaitPose.FOOT_FWD)


# How far the centre's faceoff address drops his body (GaitFaceoffLayer).
func faceoff_address_drop() -> float:
	return _faceoff.address_drop(leg_scale)

# ── Runtime State ─────────────────────────────────────────────────────────────
var stride_phase: float = 0.0
# Per-stride trunk texture, written onto the cosmetic torso/helmet/shoulder
# BONES via Skater.set_trunk_texture — never onto the UpperBody node, whose
# rotation carries the blade markers (gameplay geometry; see the invariant in
# SkaterPoseCoordinator._apply_lean). Radians; updated on real ticks only, so
# it holds steady through reconcile replay like the rest of the gait.
var trunk_pitch_add: float = 0.0
var trunk_roll_add: float = 0.0
# Body drop of the crouch this pose pass settled on, in metres, and the part of
# it the gameplay frame took (GaitPose.frame_share). The faceoff placement
# measures the stick's span from the hand height the frame's drop leaves.
var crouch_drop: float = 0.0
var frame_drop: float = 0.0
# Inertia-filter state for the summed trunk texture (see the publish tail of
# apply() and trunk_texture_smooth_rate).
var _trunk_pitch_s: float = 0.0
var _trunk_roll_s: float = 0.0
# The faceoff layer's engagement (GaitFaceoffLayer.blend).
var faceoff_blend: float:
	get:
		return _faceoff.blend
# Radians of lower-body rotation.y the shot coils and kicks the hips through
# (GaitShotLayer.hip_yaw).
var shot_hip_yaw: float:
	get:
		return _shot.hip_yaw
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
# The mohawk V's yaw per leg (the pivot block in _align_to_travel).
var _pivot_yaw_l: float = 0.0
var _pivot_yaw_r: float = 0.0
# Pivot authority [0, 1], published for SkaterPoseCoordinator: while the hold
# owns the lower-body channel, the generic facing-lag pump fades out of the
# sum — two writers tracking the same rotation on different clocks is a
# wobble, not a pose.
var pivot_hold: float = 0.0


func setup(skater: Skater, sm: SkaterStateMachine, controller: SkaterController) -> void:
	_skater = skater
	_sm = sm
	_controller = controller
	_locomotion.setup(skater, controller)
	for i: int in _layers.size():
		var layer: GaitLayer = _layers[i]
		layer.setup(skater, controller)
		var stages: int = layer.stages()
		var bit: int = 1 << i
		if stages & GaitLayer.Stage.HOLD:
			_hold_layers.append(layer)
			_hold_bits.append(bit)
		if stages & GaitLayer.Stage.FLOOR:
			_floor_layers.append(layer)
			_floor_bits.append(bit)
		if stages & GaitLayer.Stage.LEGS:
			_leg_layers.append(layer)
			_leg_bits.append(bit)
		if stages & GaitLayer.Stage.TRUNK:
			_trunk_layers.append(layer)
			_trunk_bits.append(bit)
		if stages & GaitLayer.Stage.OVERRIDE:
			_override_layers.append(layer)
			_override_bits.append(bit)
	if ClassDB.class_exists(&"NativeSkaterGait"):
		_native = ClassDB.instantiate(&"NativeSkaterGait")
		native_reconfigure()


# Reloads the native port's tunables and leg scale from the controller. Called
# from setup and from SkaterController.apply_attributes, which rewrites the
# tunables the config was read from.
func native_reconfigure() -> void:
	if _native == null:
		return
	var missing: String = _native.configure(_controller)
	if missing != "":
		# Running the port on stale values would be a silent fork: fall back, loudly.
		push_error("NativeSkaterGait disabled — controller tunables missing: %s" % missing)
		_native = null
		return
	_native.set_leg_scale(leg_scale)


# The eased locomotion weights, from whichever path runs. Diagnostics: read,
# never stored; the native read allocates.
func locomotion_mix() -> LocomotionRules.Mix:
	if _native == null:
		return _locomotion.mix
	var m: PackedFloat64Array = _native.get_mix()
	var out := LocomotionRules.Mix.new()
	out.glide = m[0]
	out.stride = m[1]
	out.crossover = m[2]
	out.carve = m[3]
	out.backward = m[4]
	out.shuffle = m[5]
	out.skid = m[6]
	out.tight = m[7]
	out.stop = m[8]
	out.side = m[9]
	return out


# Snaps the gait back to a clean standstill and plants the legs at their rest
# pose. Called on faceoff / respawn teleports so a skater doesn't drop into the
# dot mid-stride carrying the previous shift's leg swing.
func reset_to_rest() -> void:
	_locomotion.reset()
	if _native != null:
		_native.reset()
	for layer: GaitLayer in _layers:
		layer.reset()
	stride_phase = 0.0
	crouch_drop = 0.0
	frame_drop = 0.0
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
	_pivot_yaw_l = 0.0
	_pivot_yaw_r = 0.0
	if _skater != null:
		_skater.set_leg_swing(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		_skater.set_leg_contact(1.0, 1.0, INF)
		_skater.set_skating_crouch_drop(0.0)
		_skater.set_trunk_texture(0.0, 0.0)
		_skater.set_edge_loads(0.0, 0.0)


# Arms the check-delivery drive (GaitCheckLayer.start_drive).
func start_check_drive(hit_dir: Vector3, intensity: float) -> void:
	_check.start_drive(hit_dir, intensity)

# ── Per-Tick Application ──────────────────────────────────────────────────────
func apply(delta: float) -> void:
	if _skater == null or delta <= 0.0:
		return

	# ── Settled early-out ──────────────────────────────────────────────────────
	# At true rest the converged gait pose is static: with no inputs, no speed
	# and every layer's trigger idle, every smoothed channel decays to zero and
	# the pass rewrites the same rest pose every frame — the fixed cost the
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
			and not _controller.stance_active)
	if quiet:
		for layer: GaitLayer in _layers:
			if not layer.is_quiet():
				quiet = false
				break
	if quiet:
		_settle_timer = minf(_settle_timer + delta, _SETTLE_SECONDS)
		if _settle_timer >= _SETTLE_SECONDS:
			if not _settled:
				_settled = true
				reset_to_rest()
				# reset_to_rest clears the shot-transition latch; re-stamp it or
				# `quiet` fails every other frame and the settle never holds.
				_shot.sync_state()
			return
	else:
		_settle_timer = 0.0
		_settled = false

	# Which layers contribute this pass; an idle one's stages are skipped.
	var active: int = 0
	for i: int in _layers.size():
		if _layers[i].advance(delta):
			active |= 1 << i
	var p: GaitPose = _pose
	p.stick_side = -1.0 if _skater.is_left_handed else 1.0
	# The stride holds for whatever sets the feet: the pivot's transit, and any
	# layer's.
	var hold: float = pivot_hold * _controller.pivot_stride_fade
	if active:
		for i: int in _hold_layers.size():
			if active & _hold_bits[i]:
				hold = maxf(hold, _hold_layers[i].stride_hold())

	var stance: float
	var authored: float
	if _native != null:
		var demand: Vector2 = _native.locomote(delta, _skater.velocity, _skater.move_intent,
				_skater.global_transform.basis, _native_flags(), hold)
		var channels: Vector4 = _native.get_channels()
		stride_phase = channels.x
		stop_yaw_offset = channels.y
		travel_align_yaw = channels.z
		pivot_hold = channels.w
		stance = demand.x
		authored = demand.y
	else:
		# Which skating state the skater is in and the stroke it skates
		# (SkaterLocomotion). Shooting sets the feet and the pivot glides through
		# its transit, so both hold the stroke; the block takes the legs outright.
		_locomotion.sense(delta, _block.planted, hold)
		stride_phase = _locomotion.stride_phase
		stop_yaw_offset = _locomotion.stop_yaw
		_locomotion.strokes(delta, _align_to_travel(delta))
		authored = _locomotion.authored
		# The pivot sits too: the open-hip glide and the step-around are both
		# done on bent knees.
		stance = maxf(_locomotion.stance, _controller.pivot_stance * _pivot_blend)
		# The authored strokes sit as low as their pushes need to reach the ice,
		# by their share, so the sit fades with them.
		if authored > 0.001:
			var reach_sit: float = minf(GaitPose.reach_hip(_locomotion.push_reach),
					deg_to_rad(_controller.stride_sit_max_deg)) / deg_to_rad(_controller.stance_hip_deg)
			stance = maxf(stance, lerpf(stance, reach_sit, authored))

	# ── Stance and pose ────────────────────────────────────────────────────────
	if active:
		for i: int in _floor_layers.size():
			if active & _floor_bits[i]:
				stance = maxf(stance, _floor_layers[i].stance_floor())
	if authored > 0.001:
		tilt_hips(p)
	else:
		p.lean = Basis.IDENTITY
		p.ice = Basis.IDENTITY
	if _native != null:
		_native.solve(stance, p.lean, p.ice)
		p.load_native_legs(_native)
	else:
		p.solve_stance(deg_to_rad(_controller.stance_hip_deg) * stance)
		p.seed_legs(_locomotion, _pivot_yaw_l, _pivot_yaw_r)
	if active:
		for i: int in _leg_layers.size():
			if active & _leg_bits[i]:
				_leg_layers[i].shape_legs(p)
	p.extend_knees()
	if _native != null:
		p.load_native_trunk(_native)
	else:
		p.seed_trunk(_locomotion)
	if active:
		for i: int in _trunk_layers.size():
			if active & _trunk_bits[i]:
				_trunk_layers[i].shape_trunk(p)
		for i: int in _override_layers.size():
			if active & _override_bits[i]:
				_override_layers[i].override(p)

	_skater.set_faceoff_address(_faceoff.address)
	# Off camera the legs and trunk are mesh nobody draws; the crouch is not.
	if _skater.on_camera():
		p.publish_legs(_skater, delta)
	else:
		_skater.set_skating_crouch_drop(p.drop, p.frame_drop(), p.plant)
	crouch_drop = p.drop
	frame_drop = p.frame_drop()
	# Trunk inertia: filter the summed texture, then lay the wobble back on top
	# (see trunk_texture_smooth_rate).
	var tex_ease: float = 1.0
	if _controller.trunk_texture_smooth_rate > 0.0:
		tex_ease = minf(_controller.trunk_texture_smooth_rate * delta, 1.0)
	_trunk_pitch_s = lerpf(_trunk_pitch_s, p.trunk_pitch, tex_ease)
	_trunk_roll_s = lerpf(_trunk_roll_s, p.trunk_roll, tex_ease)
	trunk_pitch_add = _trunk_pitch_s + p.wobble_pitch
	trunk_roll_add = _trunk_roll_s + p.wobble_roll
	if _skater.on_camera():
		_skater.set_trunk_texture(trunk_pitch_add, trunk_roll_add)


func _native_flags() -> int:
	var flags: int = 0
	if _skater.brake_intent:
		flags |= _NATIVE_BRAKE
	if _controller.stance_active:
		flags |= _NATIVE_STANCE
	if _block.planted:
		flags |= _NATIVE_PLANTED
	return flags


# The hips' tilt against the ice, turned to their heading (GaitPose.lean / ice):
# the spine tips them by the balance lean (Skater.balance_tilt) in skeleton
# space over their yaw and the lower body's pitch (SkaterSpineRig), the twist
# limit aside.
func tilt_hips(p: GaitPose) -> void:
	var lower: Vector3 = _skater.lower_body.rotation
	var pitch := Basis(Vector3.RIGHT, lower.x)
	p.lean = Basis.IDENTITY
	var tilt: Vector2 = _skater.balance_tilt()
	if tilt != Vector2.ZERO:
		var tilt3: Vector3 = _skater.global_transform.basis.inverse() * Vector3(tilt.x, 0.0, tilt.y)
		var theta: float = tilt3.length()
		if theta > 1e-4:
			var heading := Basis(Vector3.UP, lower.y)
			p.lean = heading.inverse() * Basis(Vector3.UP.cross(tilt3 / theta), theta) * heading
	p.ice = p.lean * pitch


# ── Hip-to-travel alignment and the pivot ─────────────────────────────────────
# Returns the travel velocity in the yawed hip frame, (right, forward), which the
# stroke needs (the turning states lead along travel as the legs face it).
# Mirrored by NativeSkaterGait.align_and_pivot; test_native_gait_parity.gd fails
# if the two drift.
func _align_to_travel(delta: float) -> Vector2:
	var vel: Vector3 = _skater.velocity
	# Ground speed only — vertical velocity never feeds the stride.
	var ground_speed: float = Vector2(vel.x, vel.z).length()
	var mix: LocomotionRules.Mix = _locomotion.mix
	# Path curvature as a carve engagement, 0..1: blades committed to carving
	# edges cannot pivot.
	var curve: float = clampf(absf(_locomotion.turn_rate)
			/ maxf(_controller.carve_ref_turn_rate, 0.001), 0.0, 1.0)
	var local_vel: Vector3 = _skater.global_transform.basis.inverse() * vel
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
	_pivot_yaw_l = 0.0
	_pivot_yaw_r = 0.0
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
			_pivot_yaw_l = v_open
		elif step_sign < 0.0:
			_pivot_yaw_r = -v_open
		# The pivot target overrides the intent suppression above on purpose: a
		# key held through the swing flips to a backpedal read mid-transit,
		# which must not zero the hold.
		align_target = lerpf(align_target, pivot_target, _pivot_blend)
		align_speed = lerpf(align_speed, _controller.pivot_yaw_speed, _pivot_blend)
	_hip_align_yaw = lerpf(_hip_align_yaw, align_target, align_speed * delta)
	travel_align_yaw = _hip_align_yaw * (1.0 - mix.stop)
	# Forward speed in the yawed hip frame: v_hip = RotY(−ψ) · v_local.
	return Vector2(local_vel.x * cos(travel_align_yaw) - local_vel.z * sin(travel_align_yaw),
			-(local_vel.x * sin(travel_align_yaw) + local_vel.z * cos(travel_align_yaw)))


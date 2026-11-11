class_name SkaterIKCoordinator
extends RefCounted

# Owns the per-tick blade and arm IK pipeline:
# - Mouse → top-hand IK + blade placement (asymmetric ROM intersected with the
#   open ice via _board_reach_limit, then wall/goalie/net clamps).
# - Bottom-hand IK from the placed top hand + blade.
# - Geometry helpers shared with SkaterShotPoseCoordinator: blade_y_local,
#   blade_y_lean_corrected, stick_horiz.
# - Net exclusion zone and goalie body / butterfly box clamps. Both clamps
#   strip the puck on contact via _controller._do_release.
#
# Stateless rule layers (TopHandIK, BottomHandIK) live in domain/rules/. This
# class is the controller-facing dispatcher that builds configs from the
# controller's @export tunables and writes blade/hand positions onto Skater.

const State = SkaterStateMachine.State
# How far past the blade's whole reach the boards and the near net must be for
# the reach limit to cast no ray, metres: float room on the limit it skips.
const _OPEN_ICE_MARGIN_M: float = 0.05
# Seconds the stride's pump takes to hand the drawn hand to a shot and back.
const PUMP_HANDOFF_S: float = 0.15
# Times the goalie is resolved again against the arm rebuilt for a clamped
# blade: each rebuild turns the toe, so the hold settles over a few.
const GOALIE_SETTLE_PASSES: int = 4

# ── References ────────────────────────────────────────────────────────────────
var _skater: Skater = null
var _controller: SkaterController = null  # tunables, _do_release, _game_state, has_puck
# The gait, for the one channel the hand pose reads off it: how far into his
# faceoff address the centre is (see _grip_fraction).
var _skating: SkaterSkatingCoordinator = null

# ── Blade Smoothing State ─────────────────────────────────────────────────────
# World-XZ blade position after the per-tick speed cap, which is applied to the
# RESOLVED (ROM-clamped) target rather than the raw cursor — see step 2 of
# apply_blade_from_mouse.
var _smoothed_blade_world: Vector3 = Vector3.ZERO
var _smoothed_blade_initialized: bool = false
# Dangle velocity (world XZ, relative to the skater) — the second-order blade's
# state when max_blade_accel > 0 (see the arrive-law branch in
# apply_blade_from_mouse). Kept coherent through the first-order and
# wrister-aim paths so mode transitions never hand the inertia model a stale
# velocity. Reset with the smoothing baseline.
var _blade_dangle_vel: Vector3 = Vector3.ZERO
# Skater world position (XZ) at the previous smoothing tick — the blade-speed cap
# is applied RELATIVE to the skater (step 2 of apply_blade_from_mouse).
var _prev_skater_pos: Vector3 = Vector3.ZERO

# World-XZ ROM-clamped blade TARGET for this tick, captured BEFORE the
# speed-cap smoothing below. The releases (SkaterController._release_wrister,
# _fire_quick_pass) read this rather than the smoothed/capped blade: it is a
# function of (mouse, body pose, ROM) alone, so host and client agree on it
# without replaying the stateful smoother. y = 0.
var last_target_blade_world: Vector3 = Vector3.ZERO
# The settle's held reach target, in the skater root's frame (hold_seat).
var _held_seat_local: Vector3 = Vector3.ZERO
var _seat_held: bool = false
# Whether the stick has the puck to reach for (ReachPurposeRules), from the tick's
# target solve: the blade rests in at two hands, and the trunk stays out of the
# reach lean, as it falls.
var reach_purpose: float = 1.0
var _purpose_rim: float = -1.0
# The bottom hand's eased release off the shaft, 0 held to 1 at rest, and its rate.
var _bh_release: float = 0.0
var _bh_release_vel: float = 0.0
# A pose that takes the free hand off the stick (the celebration's fist pump):
# where, and by how much.
var _held_free_hand := Vector3.ZERO
var _held_free_weight: float = 0.0
var _pump_hold: float = 1.0
# The drawn top hand's swing round the blade that holds the drawn shaft out of
# the body (_shaft_clearance; UpperBody's frame), its rate, and the legs' joints
# it reads.
var _clear_offset := Vector3.ZERO
var _clear_vel := Vector3.ZERO
var _leg_joints := PackedVector3Array()

# ── Cached Solver Objects ─────────────────────────────────────────────────────
# The IK configs read only controller @exports, which change exclusively in
# SkaterController.apply_attributes — so they're built once and invalidated
# from there. Per-tick fields (blade_y, backhand_angle) are written
# into the cached instance each use. Building fresh configs per solve was the
# hottest allocation site in the game (~7 RefCounted/Dictionary allocs per
# skater per physics tick across the 3-pass loop).
var _cached_top_cfg: TopHandIK.Config = null
var _cached_hold_cfg: StickHoldRules.Config = null
# The reach solve's own top hand for the blade last placed (UpperBody's frame):
# how far the arm is out, which the reach lean reads. The marker's is the held
# one (_held_hand).
var reach_hand_local := Vector3.ZERO
# The ready fold's ease (ready_fold), which the skater steps on the tick and a
# replay plays back.
var ready := SkaterReadyFold.new(_ready_fold_target)
var _cached_bottom_cfg: BottomHandIK.Config = null
var _two_hand_scratch := TopHandIK.Result.new()
var _ik_result := TopHandIK.Result.new()
var _net_result := NetBladeCollision.Result.new()
# See resolve_blade_against_net.
var _net_side_anchor: Vector3 = Vector3.ZERO
var _has_net_side_anchor: bool = false
var _rigid_result := TopHandIK.Result.new()
# Native IK solvers (null = extension absent, GDScript fallback). Config
# properties sync inside the cached-config builders — the same rebuild moment —
# so invalidate_configs() covers both representations.
var _native_top: RefCounted = null
# Native blade-dangle smoother (null = extension absent, GDScript fallback).
# In native mode it OWNS the cross-tick smoothing state (_prev_skater_pos,
# _blade_dangle_vel, the init flag) — only _smoothed_blade_world is mirrored
# back, because the hand solve below the block reads it.
var _native_dangle: RefCounted = null
# The tie state the dangle config was last synced for (the blade cap follows it).
var _dangle_synced_tied: bool = false
# The whole blade pass in C++ (null = extension absent or stale: the GDScript
# below runs). It drives the two kernels above, so they keep one state between
# the paths. native_pass_enabled routes round it for the parity test.
var _native_pass: RefCounted = null
var native_pass_enabled: bool = true
var _pass_scalars := PackedFloat64Array()
# The hold config the native pass last took (_sync_hold_config).
var _native_hold_cfg: StickHoldRules.Config = null
var _pass_vectors := PackedVector3Array()
var _no_goalies := PackedFloat32Array()
# NativeBladePass.run's inputs, by index (its Scalar and Vec enums).
enum PassS {
	DELTA, HOLD_BLADE, HOLD_SEAT, HAS_PUCK, LEFT_HANDED, WRISTER_AIM, TRUNK_FOLD,
	ADDRESS, FOREHAND_FACTOR, TRANSIT_FACTOR, LIFT_BLEND, COMMIT_BLEND, GRIP_CHOKE,
	CHECK_LEAD, HAS_PUCK_NODE, PURPOSE_RIM, BLADE_LENGTH, CARRY_BLADE_OFFSET,
	CARRY_TRANSIT_LIFT, WALL_SQUEEZE_THRESHOLD, WALL_PIN_INWARD_BIAS, BOTTOM_REACH,
	GLOVE_SPACING, HAS_NET_ANCHOR, REACH_PURPOSE, CHEST_FOLD, REACH_FLOOR, HAND_FORWARD,
	HOLD_SHARE, LAY_FOLD, READY_FOLD, COUNT,
}
enum PassV {
	TARGET, SHOULDER, BOTTOM_SHOULDER, BLADE_MARKER, BLADE_FORWARD, PREV_CONTACT,
	PUCK_POS, PUCK_VEL, VELOCITY, UB_ROTATION, LAST_TARGET, NET_ANCHOR, COUNT,
}

func setup(skater: Skater, controller: SkaterController,
		skating: SkaterSkatingCoordinator) -> void:
	_skater = skater
	_controller = controller
	_skating = skating
	if ClassDB.class_exists(&"NativeTopHandIK"):
		_native_top = ClassDB.instantiate(&"NativeTopHandIK")
		# Stale-binary guard, one level finer than NativeKernels' class census:
		# the forehand floor (set_hand_forward) is the newest thing ADDED to an
		# existing kernel, so a binary predating it still registers the class and
		# passes that check. Fall back to GDScript, which is slower and correct,
		# rather than solve without it.
		if not _native_top.has_method(&"set_hand_forward"):
			push_warning("NativeTopHandIK predates the forehand floor — "
					+ "using the GDScript solver. Rebuild native/ (bash native/build.sh).")
			_native_top = null
	if ClassDB.class_exists(&"NativeBladeDangle"):
		_native_dangle = ClassDB.instantiate(&"NativeBladeDangle")
		_sync_dangle_config()
	if _native_top != null and _native_dangle != null and ClassDB.class_exists(&"NativeBladePass"):
		_native_pass = ClassDB.instantiate(&"NativeBladePass")
		_native_pass.bind(_native_top, _native_dangle)
		_native_pass.set_rink(GameRules.INNER_HALF_WIDTH, GameRules.INNER_HALF_LENGTH,
				GameRules.INNER_CORNER_RADIUS, GameRules.CORNER_CENTER_X, GameRules.CORNER_CENTER_Z)
		_native_pass.set_net(GameRules.GOAL_LINE_Z, GameRules.NET_HALF_WIDTH,
				GameRules.NET_POST_RADIUS, GameRules.NET_DEPTH, GameRules.NET_TOP_DEPTH,
				GameRules.NET_HEIGHT, GameRules.NET_BACK_HALF_WIDTH, GameRules.NET_CROWN_HALF_WIDTH,
				GameRules.NET_MOUTH_CORNER_RADIUS, GameRules.NET_BLADE_MESH_GIVE)
		_pass_scalars.resize(PassS.COUNT)
		_pass_vectors.resize(PassV.COUNT)
		_sync_pass_config()

# Drop the cached configs so the next solve rebuilds them from the controller
# exports. Called by SkaterController.apply_attributes (stick length, ROM, and
# hand heights all scale with attributes).
func invalidate_configs() -> void:
	_cached_top_cfg = null
	_cached_hold_cfg = null
	_cached_bottom_cfg = null
	_purpose_rim = -1.0
	_sync_dangle_config()
	_sync_pass_config()


# The tunables the native pass reads, on the moment they change (apply_attributes).
# A binary older than one of them takes the GDScript path.
func _sync_pass_config() -> void:
	if _native_pass == null:
		return
	if not _native_pass.has_method(&"configure_hold"):
		push_warning("NativeBladePass predates the hold — using the GDScript blade pass. "
				+ "Rebuild native/ (bash native/build.sh).")
		_native_pass = null
		return
	var c: SkaterController = _controller
	var ok: bool = _native_pass.configure({
		"hand_rest_y": c.hand_rest_y, "hand_y_max": c.hand_y_max,
		"faceoff_center_hand_rise": c.faceoff_center_hand_rise,
		"faceoff_center_lean_deg": c.faceoff_center_lean_deg,
		"stick_length": c.stick_length, "rom_forward_reach_max": c.rom_forward_reach_max,
		"rom_forehand_reach_max": c.rom_forehand_reach_max,
		"rom_backhand_reach_max": c.rom_backhand_reach_max,
		"rom_forehand_angle_max": deg_to_rad(c.rom_forehand_angle_max_deg),
		"rom_backhand_angle_max": deg_to_rad(c.rom_backhand_angle_max_deg),
		"net_blade_half_thickness": c.net_blade_half_thickness,
		"blade_height": c.blade_height, "blade_lift_height": c.blade_lift_height,
		"hit_commit_blade_lift_m": c.hit_commit_blade_lift_m,
		"bh_release_angle_deg": c.bh_release_angle_deg,
		"reach_purpose_lookahead_s": c.reach_purpose_lookahead_s,
		"reach_purpose_near_m": c.reach_purpose_near_m,
		"reach_purpose_far_m": c.reach_purpose_far_m,
		"hit_commit_hand_local_x": c.hit_commit_hand_local_x,
		"hit_commit_hand_local_y": c.hit_commit_hand_local_y,
		"hit_commit_hand_local_z": c.hit_commit_hand_local_z,
		"hit_commit_blade_bearing_x": c.hit_commit_blade_bearing_x,
		"hit_commit_blade_bearing_z": c.hit_commit_blade_bearing_z,
		"hit_commit_blade_sweep": c.hit_commit_blade_sweep,
		"bottom_hand_grip_fraction": c.bottom_hand_grip_fraction,
		"faceoff_center_grip_fraction": c.faceoff_center_grip_fraction,
		"twist_limit": SkaterSpineRig.TWIST_LIMIT,
		"top_hand_forward_none_m": c.top_hand_forward_none_m,
		"top_hand_forward_full_m": c.top_hand_forward_full_m,
	})
	if not ok:
		push_warning("NativeBladePass lacks a tunable — using the GDScript blade pass. "
				+ "Rebuild native/ (bash native/build.sh).")
		_native_pass = null

# The hold's config and bands, to the native pass, each time the config is
# rebuilt.
func _sync_hold_config() -> void:
	var cfg: StickHoldRules.Config = _hold_config()
	_native_hold_cfg = cfg
	_native_pass.configure_hold({
		"lie": cfg.lie, "home_out": cfg.home_out, "home_ahead": cfg.home_ahead,
		"reach_ahead": cfg.reach_ahead, "reach_out": cfg.reach_out,
		"reach_across": cfg.reach_across, "draw": cfg.draw, "draw_out": cfg.draw_out,
		"draw_back": cfg.draw_back, "draw_share": cfg.draw_share, "low_share": cfg.low_share,
		"edge_band": StickHoldRules.EDGE_BAND_M, "rest_band": StickHoldRules.REST_BAND_M,
		"draw_from_lo": StickHoldRules.DRAW_FROM.x, "draw_from_hi": StickHoldRules.DRAW_FROM.y,
		"reaching_from": _HOLD_REACHING_OF_ARM.x, "reaching_to": _HOLD_REACHING_OF_ARM.y,
		"reach_band": _HOLD_REACH_BAND,
	})


# The dangle tunables are plain controller @exports (not part of the cached IK
# configs), so they sync here — covered by the same invalidate_configs moment
# that rebuilds the config objects on apply_attributes.
func _sync_dangle_config() -> void:
	_dangle_synced_tied = _skater != null and _skater.stick_tied
	if _native_dangle != null:
		_native_dangle.set_config(
				_blade_speed_cap(),
				_controller.wrister_on_axis_blade_speed,
				_controller.max_blade_accel)


# Two tied sticks push against each other: both blades chase at the tie's speed.
func _blade_speed_cap() -> float:
	if _skater != null and _skater.stick_tied:
		return minf(_controller.max_blade_speed, StickCheckRules.TIE_BLADE_SPEED_M_S)
	return _controller.max_blade_speed

# Drop the smoothed-blade baseline so the next solve re-seeds it deterministically
# from the first replayed input (the init branch in apply_blade_from_mouse snaps
# the smoothed blade to that input's ROM-clamped target). Called by
# LocalController at reconcile entry so replay starts from a deterministic blade
# baseline rather than carrying the live smoothed value across the snap.
func reset_blade_smoothing() -> void:
	_smoothed_blade_initialized = false
	ready.unseed()
	_blade_dangle_vel = Vector3.ZERO
	if _native_dangle != null:
		_native_dangle.reset_smoothing()

# Seed the smoothed-blade baseline to a specific world position so the next solve
# steps toward the cursor FROM there rather than from a stale value. Called by
# SkaterController when handing off from the follow-through to normal skating:
# the blade smoother was frozen at the wound-back release position while the FT
# choreographed the blade directly, so without re-seeding the blade would snap
# back to that stale spot and dangle forward again. Seeding it to the FT's final
# blade lets the normal dangle continue from where the finish left it.
# `velocity`: the dangle's own, for a seed taken mid-dangle (a reconcile's, from
# the ack); a follow-through's finish choreographed the blade directly, so the
# dangle resumes from rest there.
func seed_blade_smoothing(world_pos: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	_smoothed_blade_world = Vector3(world_pos.x, 0.0, world_pos.z)
	_prev_skater_pos = Vector3(_skater.global_position.x, 0.0, _skater.global_position.z)
	_smoothed_blade_initialized = true
	_blade_dangle_vel = velocity
	if _native_dangle != null:
		_native_dangle.seed_moving(world_pos, _skater.global_position, velocity)


# The dangle's velocity after the last solve — what a reconcile seeds back from.
func blade_dangle_velocity() -> Vector3:
	return _native_dangle.get_dangle_velocity() if _native_dangle != null else _blade_dangle_vel

# ── Blade From Mouse (Top-Hand IK) ────────────────────────────────────────────
# Input is treated as a desired blade position. The top hand is solved as a
# consequence, clamped to an asymmetric ROM. See domain/rules/top_hand_ik.gd.
func apply_blade_from_mouse(input: InputState, delta: float, hold_blade: bool = false,
		hold_seat: bool = false) -> void:
	apply_blade_toward(input.mouse_world_pos, delta, hold_blade, hold_seat)


# The tracked blade reaching for `target_world` as it would for a cursor there —
# the same reach, rim and speed cap — for a reach the player did not point at
# (a slapshot's set-up taking the puck to the strike spot).
func apply_blade_toward(target_world: Vector3, delta: float, hold_blade: bool = false,
		hold_seat: bool = false) -> void:
	# The pass drives the two kernels it was bound to; with either taken away it
	# would keep driving the stale one.
	if _native_pass != null and native_pass_enabled and _native_top != null \
			and _native_dangle != null:
		_native_blade_toward(target_world, delta, hold_blade, hold_seat)
		return
	var mouse_world: Vector3 = target_world
	mouse_world.y = 0.0

	var skater_pos: Vector3 = _skater.global_position
	skater_pos.y = 0.0

	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0

	# The carry-side state this pipeline reads (get_carry_forehand_factor, via
	# _blade_target_for below) is advanced in Skater._update_carry_contact —
	# on the physics tick, for every peer — not here: the push model keys it
	# off blade motion, which remote skaters have and this pipeline does not run
	# for them.

	# FREEZE (hold_blade, set for the WRISTER_AIM state): during a wrister
	# charge, hold the blade at its current body-local pose instead of chasing the
	# cursor. The puck pins to this held blade (get_carry_target_global), so it
	# sits still AT the shot origin while the torso still coils toward the cursor
	# (apply_upper_body preserves the blade world across the coil). Target ==
	# current blade → the speed-cap/translation bookkeeping below runs with a
	# ~zero step, keeping _smoothed_blade coherent so resuming normal tracking
	# after the shot doesn't pop.
	# SEAT (hold_seat, the settle lock): hold the reach TARGET where it was when the
	# hold began, in the skater's own frame — so it turns with the body's facing
	# but not with the torso's twist. The freeze above re-reads the SOLVED blade,
	# and in tight the hand solve lands the blade past its target, so re-reading
	# it walks the blade out along the aim line tick after tick; a held target is
	# a fixed point.
	var target_blade_world: Vector3
	if hold_seat and not _seat_held:
		_held_seat_local = _skater.global_transform.affine_inverse() * last_target_blade_world
	_seat_held = hold_seat
	if hold_seat:
		target_blade_world = _skater.global_transform * _held_seat_local
		target_blade_world.y = 0.0
		last_target_blade_world = target_blade_world
	elif hold_blade:
		target_blade_world = _skater.upper_body_to_global(_skater.get_blade_position())
		target_blade_world.y = 0.0
		last_target_blade_world = target_blade_world
	else:
		mouse_world = _held_out(mouse_world)
		var shoulder: Vector3 = arm_shoulder()
		var shoulder_world: Vector3 = _skater.upper_body_to_global(shoulder)
		shoulder_world.y = 0.0
		if (mouse_world - shoulder_world).length() < 0.01:
			return

		# 1. Resolve the RAW cursor to the blade the player is actually reaching for:
		#    convert to upper-body-local, apply the carry offset, then clamp to the
		#    reachable set — ROM intersected with the open ice (see
		#    _board_reach_limit; every consumer of this resolved target, from the
		#    speed cap below to the wrister charge gate that reads
		#    last_target_blade_world, inherits the boards for free because the limit
		#    lands here rather than on the solved pose). This is the TARGET the
		#    speed cap chases. ROM
		#    clamping the target up front (rather than after the cap) is the whole
		#    point: the cap then limits the speed of the REACHABLE blade, not the
		#    intent point far out past ROM. A distant cursor maps to a point on the
		#    ROM boundary, so sweeping it laterally slides the target along that
		#    boundary at cursor speed — and the cap bounds the blade's actual travel
		#    rather than being spent dragging the intent through unreachable space.
		var mouse_local: Vector3 = _skater.upper_body_to_local(mouse_world)
		var cursor_xz := Vector2(mouse_local.x, mouse_local.z)
		var target_blade_xz: Vector2 = _blade_target_along(cursor_xz, cursor_xz - Vector2(
				_skater.shoulder.position.x, _skater.shoulder.position.z))
		# Projected by the solve that places the hand, so the target sits on the rim
		# the hand reaches (Scripts/controllers/CLAUDE.md, "The top hand is solved
		# where the arm is").
		var target_reach: float = _board_reach_limit(target_blade_xz, shoulder_world)
		reach_purpose = _reach_purpose(skater_pos)
		# The blade lies along the shaft from the hand that holds it, not along
		# the shoulder's aim the first target was laid on: laid again along the
		# held shaft where that one landed, mid-blade, and the puck pinned
		# beside it, come to rest on the cursor. Held under the carry's settled
		# fold whoever has the puck (_lay_fold): the blade is a function of the
		# tick's state, and a pickup does not step it.
		var aimed: TopHandIK.Result = _solve_top_hand(
				target_blade_xz, blade_side_sign, target_reach, true)
		var held: Vector3 = _held_hand(aimed.hand, aimed.blade, _lay_fold())
		target_blade_xz = _blade_target_along(cursor_xz,
				Vector2(aimed.blade.x - held.x, aimed.blade.z - held.z))
		var target_blade_local: Vector3 = _solve_top_hand(
				target_blade_xz, blade_side_sign, target_reach, true).blade
		if _controller.has_puck:
			# The backhand stop is an angle about the hips, and the solve slides the
			# blade along the shoulder's aim line off it: stopped again from where
			# it landed, it holds the stop.
			target_blade_local = _solve_top_hand(Vector2(target_blade_local.x,
					target_blade_local.z), blade_side_sign, target_reach, true).blade
		target_blade_world = _skater.upper_body_to_global(target_blade_local)
		target_blade_world.y = 0.0
		last_target_blade_world = target_blade_world

	# 2. Speed-cap the smoothed blade toward the resolved target, RELATIVE TO THE
	#    SKATER. max_blade_speed bounds how fast the blade traverses its ROM in
	#    front of the player (dangle speed). The blade's WORLD position drifts at
	#    the skater's skating velocity (the camera follows the player), so capping
	#    in world space would bleed skating speed into the budget — the blade
	#    would drag while skating and, once skating speed exceeds the cap, never
	#    catch up. So carry the smoothed blade along with the skater's translation
	#    first, then cap only the residual dangle relative to the player.
	if _skater.stick_tied != _dangle_synced_tied:
		_sync_dangle_config()
	if _native_dangle != null:
		# Native port of the block below (native/src/native_blade_dangle.cpp).
		# It owns the smoothing state; the returned smoothed blade is mirrored
		# because the hand solve below reads _smoothed_blade_world.
		_smoothed_blade_world = _native_dangle.advance(
				target_blade_world, skater_pos, delta,
				_controller.get_shot_state() == State.WRISTER_AIM)
		_smoothed_blade_initialized = true
	else:
		if not _smoothed_blade_initialized:
			_smoothed_blade_world = target_blade_world
			_prev_skater_pos = skater_pos
			_smoothed_blade_initialized = true
			_blade_dangle_vel = Vector3.ZERO
		_smoothed_blade_world += skater_pos - _prev_skater_pos
		_smoothed_blade_world.y = 0.0
		_prev_skater_pos = skater_pos
		var step: Vector3 = target_blade_world - _smoothed_blade_world
		step.y = 0.0
		var max_step: float = _blade_speed_cap() * delta
		if max_step > 0.0:
			# During a wrister aim, uncap blade motion ALONG the shot axis — the
			# wind-back-and-snap that makes the shot feel responsive on every build —
			# while keeping the PERPENDICULAR component capped at the normal
			# dangle budget (max_step). Lateral blade sweep IS dangling; capping only
			# that axis fixes slow-blade shot feel without letting "shoot mode" become
			# a way to dangle at full blade speed. The axis is skater→smoothed-blade
			# (the current aim line). Reading the LAGGED smoothed blade (not the raw
			# target) self-stabilizes the split: a fast lateral whip can't drag the
			# axis along with it (off-axis is capped, so the axis can only rotate as
			# fast as that cap allows), while a slow re-aim turns the axis naturally.
			# The on-axis budget is flat so shooting feels the same for everyone;
			# the off-axis dangle stays capped at the build's max_blade_speed.
			var axis_vec: Vector3 = _smoothed_blade_world - skater_pos
			axis_vec.y = 0.0
			if _controller.get_shot_state() == State.WRISTER_AIM and axis_vec.length_squared() > 0.0001:
				var axis: Vector3 = axis_vec.normalized()
				var on_axis: Vector3 = axis * step.dot(axis)
				var off_axis: Vector3 = step - on_axis
				var on_max: float = _controller.wrister_on_axis_blade_speed * delta
				var on_len: float = on_axis.length()
				if on_len > on_max:
					on_axis *= on_max / on_len
				var off_len: float = off_axis.length()
				if off_len > max_step:
					off_axis *= max_step / off_len
				_smoothed_blade_world += on_axis + off_axis
				# Keep the dangle-velocity state coherent through the aim mode so
				# exiting a wrister aim doesn't hand the inertia model a stale
				# velocity from before the wind-up.
				_blade_dangle_vel = (on_axis + off_axis) / delta
			elif _controller.max_blade_accel > 0.0:
				# SECOND-ORDER BLADE (attributes v4 hands model): the stick has
				# inertia. Dangle velocity chases an arrive-law target — speed
				# toward the target is bounded by both the tip-speed cap and
				# sqrt(2·A·dist) (the fastest approach that can still stop on the
				# target), and the velocity itself may only change at A per second.
				# Traverse speed is barely touched (the caps are tuned to bind only
				# at gesture extremes); direction REVERSALS pay the inertia — the
				# lever seesaw's whole point. No spring, no overshoot: the arrive
				# law decays approach speed to zero at the target, and the landing
				# snap below catches the final sub-tick step exactly like the
				# first-order path does.
				var accel: float = _controller.max_blade_accel
				var dist: float = step.length()
				var desired := Vector3.ZERO
				if dist > 0.00001:
					var arrive_speed: float = minf(
							_blade_speed_cap(), sqrt(2.0 * accel * dist))
					desired = step * (arrive_speed / dist)
				_blade_dangle_vel = _blade_dangle_vel.move_toward(desired, accel * delta)
				var move: Vector3 = _blade_dangle_vel * delta
				if move.length() >= dist and _blade_dangle_vel.dot(step) >= 0.0:
					_smoothed_blade_world = target_blade_world
				else:
					_smoothed_blade_world += move
			else:
				# First-order path: max_blade_accel 0 disables the inertia model
				# and the blade steps straight toward the target at the cap.
				var step_len: float = step.length()
				if step_len > max_step:
					# Target is beyond the dangle-speed budget this tick — step toward it.
					_smoothed_blade_world += step * (max_step / step_len)
					_blade_dangle_vel = step * (max_step / step_len) / delta
				else:
					# Within budget this tick — the blade can reach the target.
					_smoothed_blade_world = target_blade_world
					_blade_dangle_vel = step / delta if delta > 0.0 else Vector3.ZERO
		# else (delta == 0): no wall-clock elapsed, so the blade traverses no ROM.
		# This is the reconcile final re-apply path (LocalController.reconcile passes
		# delta 0.0 to re-place the blade in the post-snap body frame). Snapping to
		# the target here would zero out the hands speed cap on every reconcile —
		# clients reconcile constantly, the host never does, so the host would feel
		# the clamp at full strength while clients barely felt it. Keep the replayed
		# (already clamped) smoothed blade instead of snapping.

	# 3. Solve the hand (and lean-corrected blade_y) for the CAPPED blade. The
	#    smoothed blade is already within ROM (it stepped from one in-ROM point
	#    toward another), so this resolves the matching hand/stick pose at the
	#    capped position rather than the raw target. The reach limits step 1 laid
	#    on the target (the carry's two hands, the rest without purpose) are not
	#    laid again: the blade comes in to them at the speed cap, where clamping
	#    the capped blade snapped it there in a tick (a pickup at the rim moved
	#    the hands half a metre).
	var capped_blade_local: Vector3 = _skater.upper_body_to_local(_smoothed_blade_world)
	var capped_blade_xz := Vector2(capped_blade_local.x, capped_blade_local.z)
	# Commit stance: ease the blade OFF the cursor toward a body-local "loaded"
	# pose while committing (empty-handed), so the stick settles into a distinct
	# ready-to-hit silhouette instead of tracking. Blended by _commit_lift_blend
	# (0 except during a commit), so it lerps in as Ctrl is held and back to cursor
	# tracking on release — the underlying _smoothed_blade keeps tracking beneath the
	# override, so there's no pop. Gameplay-inert (the blade is withdrawn from puck
	# play while committed); the Y lift rides blade_y_local. Only the hand solve
	# reads this local copy — _smoothed_blade state is untouched, staying coherent
	# for the exit.
	var commit_t: float = _skater.get_commit_lift_blend()
	# The board limit is re-derived for the CAPPED aim line, not reused from the
	# target above: the smoothed blade lags the target (and is carried along by
	# the skater's own translation), so the two can point at different stretches
	# of wall. Without it the FAR regime would extend this solve back out past the
	# boards, which is exactly what the clamp below then has to undo.
	var ik: TopHandIK.Result = _solve_top_hand(
			capped_blade_xz, blade_side_sign,
			_board_reach_limit(capped_blade_xz, _skater.upper_body_to_global(arm_shoulder())))
	reach_hand_local = ik.hand
	var blade_local: Vector3 = ik.blade
	var hand_local: Vector3 = _held_hand(reach_hand_local, blade_local, ready_fold())
	if commit_t > 0.0:
		var posed: TopHandIK.Result = _commit_hand_pose(
				hand_local, blade_local, blade_side_sign, commit_t)
		hand_local = posed.hand
		blade_local = posed.blade

	# Carry transit lift: while carrying, raise the blade over the puck during
	# a pushing-face flip. One sin-envelope hop per flip (Skater
	# .get_carry_transit_factor) rather than (1 − |smoothed factor|): under a
	# fast dangle the smoothed factor lives near zero, which would hold the
	# blade permanently mid-air — the hop bounces once per stroke instead.
	# cos(p)*cos(r) divisor converts world-Y target into upper-body-local Y so
	# the lift lands at the intended height in world space (matches the
	# lean-correction math).
	if _controller.has_puck and _skater.carry_transit_lift > 0.0:
		var transit: float = _skater.get_carry_transit_factor()
		if transit > 0.0001:
			var lift_world: float = transit * _skater.carry_transit_lift
			var cpcr: float = maxf(
					cos(_skater.upper_body.rotation.x) * cos(_skater.upper_body.rotation.z),
					0.01)
			blade_local.y += lift_world / cpcr

	# Wall clamp on the solved blade. Wall-pin auto-release (when carrying).
	var intended_blade: Vector3 = blade_local
	var wall_clamped: Vector3 = _skater.clamp_blade_to_walls(blade_local)

	if _controller.has_puck:
		var squeeze: float = _skater.get_wall_squeeze(intended_blade, wall_clamped)
		if ShotMechanics.should_release_on_wall_pin(squeeze, _skater.wall_squeeze_threshold):
			# Lose it ALONG the boards in the carrier's travel direction, not straight
			# out into the slot — the wall normal points inward, so releasing along it
			# would fire the puck away from the wall (an unnatural giveaway). A small
			# inward bias peels it a touch off the boards so it doesn't hug them.
			var wall_normal: Vector3 = _skater.get_blade_wall_normal()
			var release_dir: Vector3 = ShotMechanics.wall_pin_release_direction(
					wall_normal, _skater.velocity, _skater.wall_pin_inward_bias)
			if release_dir.length() > 0.0:
				_controller._do_release(release_dir, 3.0)
			else:
				# Fully degenerate: no wall normal and no along-wall momentum. A squeeze
				# past the threshold implies a wall normal, so this is essentially
				# unreachable — but keep a sane free by shoving the puck back toward the
				# body (blade → body center), falling to facing if that's degenerate too.
				var blade_world: Vector3 = _skater.upper_body_to_global(wall_clamped)
				var back: Vector3 = _skater.global_position - blade_world
				back.y = 0.0
				if back.length_squared() < 0.0001:
					back = -_skater.global_transform.basis.z
				_controller._do_release(back.normalized(), 3.0)

	# The goalie, then the net, both pure collision: neither strips.
	# All work in world space; convert back once at the end.
	var heel_world: Vector3 = _skater.upper_body_to_global(wall_clamped)
	var clamped_heel: Vector3 = heel_world + resolve_blade_against_goalies(heel_world,
			_skater.upper_body_to_global(hand_local))
	# The net is pure collision here — no strip, no legality. The blade stops on
	# iron and sinks into twine; whether the PUCK survives that is the puck's own
	# collision to resolve (SkaterController._collide_pinned_puck_with_net), which
	# is the only place that can answer it correctly since the puck rides a pin
	# OFF the blade. The blade is a segment here, so heel and toe are tested
	# directly rather than through a mid-blade contact-point proxy.
	clamped_heel += resolve_blade_against_net(clamped_heel).offset
	if clamped_heel != heel_world:
		wall_clamped = _skater.upper_body_to_local(clamped_heel)

	# Rebuild the arm for the FINAL blade whenever a clamp moved it. The blade is
	# authoritative from here (gameplay decided it — net legality, goalie contact,
	# the board surface), so the arm is solved to reach it and the stick chokes up
	# to make up the difference. Sliding the hand by the clamp offset instead
	# preserves stick length at the cost of arm length, which is what walked the
	# hand behind the shoulder against the boards and stretched it across the net.
	# Skipped when nothing moved: the reconstruction is an exact inverse of the
	# solve there, so it would only redo work.
	if wall_clamped != intended_blade:
		var arm: TopHandIK.Result = _arm_for_clamped_blade(wall_clamped, blade_side_sign)
		hand_local = _held_hand(arm.hand, arm.blade, ready_fold())
		# The rebuilt hand turns the blade along its new shaft, and the toe with it,
		# which can swing it into the goalie the first resolve held it off.
		for _settle: int in GOALIE_SETTLE_PASSES:
			var settled_heel: Vector3 = _skater.upper_body_to_global(arm.blade)
			var more: Vector3 = resolve_blade_against_goalies(settled_heel,
					_skater.upper_body_to_global(hand_local))
			if more == Vector3.ZERO:
				break
			arm = _arm_for_clamped_blade(_skater.upper_body_to_local(settled_heel + more),
					blade_side_sign)
			hand_local = _held_hand(arm.hand, arm.blade, ready_fold())
		reach_hand_local = arm.hand
		wall_clamped = arm.blade

	_skater.set_top_hand_position(hand_local)
	_skater.set_blade_position(wall_clamped)

# apply_blade_toward in C++ (NativeBladePass): its inputs gathered once, its
# releases fired where the GDScript fires them (mid-pass, each resumed with
# the live has_puck), the reach target and wall normal written before them and
# the markers after, as there.
func _native_blade_toward(target_world: Vector3, delta: float, hold_blade: bool,
		hold_seat: bool) -> void:
	if _skater.stick_tied != _dangle_synced_tied:
		_sync_dangle_config()
	var has_puck: bool = _controller.has_puck
	var puck: Puck = _controller.puck
	var s: PackedFloat64Array = _pass_scalars
	s[PassS.DELTA] = delta
	s[PassS.HOLD_BLADE] = 1.0 if hold_blade else 0.0
	s[PassS.HOLD_SEAT] = 1.0 if hold_seat else 0.0
	s[PassS.HAS_PUCK] = 1.0 if has_puck else 0.0
	s[PassS.LEFT_HANDED] = 1.0 if _skater.is_left_handed else 0.0
	s[PassS.WRISTER_AIM] = 1.0 if _controller.get_shot_state() == State.WRISTER_AIM else 0.0
	s[PassS.TRUNK_FOLD] = _skater.trunk_fold()
	s[PassS.ADDRESS] = _address_blend()
	s[PassS.FOREHAND_FACTOR] = _skater.get_carry_forehand_factor() if has_puck else 0.0
	s[PassS.TRANSIT_FACTOR] = _skater.get_carry_transit_factor() \
			if has_puck and _skater.carry_transit_lift > 0.0 else 0.0
	s[PassS.LIFT_BLEND] = _skater.get_blade_lift_blend()
	s[PassS.COMMIT_BLEND] = _skater.get_commit_lift_blend()
	s[PassS.GRIP_CHOKE] = _skater.grip_choke()
	s[PassS.CHECK_LEAD] = _skater.get_check_lead()
	s[PassS.HAS_PUCK_NODE] = 1.0 if puck != null else 0.0
	if puck != null and not has_puck and _purpose_rim < 0.0:
		_purpose_rim = full_blade_reach()
	s[PassS.PURPOSE_RIM] = _purpose_rim
	s[PassS.BLADE_LENGTH] = _skater.blade_length
	s[PassS.CARRY_BLADE_OFFSET] = _skater.carry_blade_offset
	s[PassS.CARRY_TRANSIT_LIFT] = _skater.carry_transit_lift
	s[PassS.WALL_SQUEEZE_THRESHOLD] = _skater.wall_squeeze_threshold
	s[PassS.WALL_PIN_INWARD_BIAS] = _skater.wall_pin_inward_bias
	s[PassS.BOTTOM_REACH] = (_skater.upper_arm_length + _skater.forearm_length) \
			* _skater.arm_working_extension + _skater.shoulder_reach_m
	s[PassS.GLOVE_SPACING] = _glove_spacing()
	s[PassS.HAS_NET_ANCHOR] = 1.0 if _has_net_side_anchor else 0.0
	s[PassS.REACH_PURPOSE] = reach_purpose
	s[PassS.CHEST_FOLD] = chest_fold()
	s[PassS.REACH_FLOOR] = _reach_floor()
	s[PassS.HAND_FORWARD] = _hand_forward()
	s[PassS.HOLD_SHARE] = _hold_share()
	s[PassS.LAY_FOLD] = _lay_fold()
	s[PassS.READY_FOLD] = ready_fold()
	if _native_hold_cfg != _hold_config():
		_sync_hold_config()
	var v: PackedVector3Array = _pass_vectors
	v[PassV.TARGET] = target_world
	v[PassV.SHOULDER] = _skater.shoulder.position
	v[PassV.BOTTOM_SHOULDER] = _skater.bottom_shoulder.position
	v[PassV.BLADE_MARKER] = _skater.get_blade_position()
	v[PassV.BLADE_FORWARD] = -_skater.blade.global_transform.basis.z
	v[PassV.PREV_CONTACT] = _skater.get_prev_blade_contact_global()
	if puck != null:
		v[PassV.PUCK_POS] = puck.global_position
		v[PassV.PUCK_VEL] = puck.linear_velocity
	v[PassV.VELOCITY] = _skater.velocity
	v[PassV.UB_ROTATION] = _skater.upper_body.rotation
	v[PassV.LAST_TARGET] = last_target_blade_world
	v[PassV.NET_ANCHOR] = _net_side_anchor
	_native_pass.run(_skater.global_transform, _skater.upper_body.global_transform,
			s, v, _goalie_boxes())
	if _native_pass.get_skipped():
		return
	last_target_blade_world = _native_pass.get_last_target()
	reach_purpose = _native_pass.get_reach_purpose()
	_smoothed_blade_world = _native_pass.get_smoothed_blade()
	_smoothed_blade_initialized = true
	_skater.set_blade_wall_normal(_native_pass.get_wall_normal())
	while _native_pass.get_pending():
		_controller._do_release(_native_pass.get_pending_dir(), _native_pass.get_pending_power())
		_native_pass.resume(_controller.has_puck)
	_net_side_anchor = _native_pass.get_net_anchor()
	_has_net_side_anchor = _native_pass.get_has_net_anchor()
	reach_hand_local = _native_pass.get_reach_hand()
	_skater.set_top_hand_position(_native_pass.get_hand())
	_skater.set_blade_position(_native_pass.get_blade())

# ── Board Reach Limit ─────────────────────────────────────────────────────────
# How far the blade may sit from the shoulder along the aim toward
# `target_blade_xz` before it runs into the boards, in metres (INF on open ice).
# Fed to TopHandIK as max_blade_reach so the reachable blade set is the ROM
# envelope INTERSECTED with the rink, rather than ROM alone with the wall
# discovered afterwards.
#
# `target_blade_xz` is upper-body-local and the boards live in world space, so
# the aim direction is rotated through the torso basis before the cast; the
# returned scalar is then compared against an upper-body-local radius inside the
# solver, so the two disagree by the lean's cosine (sub-centimetre at the reach
# where this binds). The exact heel/toe clamp downstream remains the backstop —
# this limit exists so that clamp has almost nothing left to correct.
func _board_reach_limit(target_blade_xz: Vector2, shoulder_world: Vector3) -> float:
	var origin := Vector2(shoulder_world.x, shoulder_world.z)
	# Open ice: a limit past the blade's whole reach poses it exactly as no limit
	# does (TopHandIK clamps to its ROM first), so no ray is cast.
	var clear: float = minf(GameRules.distance_to_rink_inner(origin),
			NetGeometry.distance_to_near_net(origin, _controller.net_blade_half_thickness))
	if clear > _controller.stick_length + _controller.rom_forward_reach_max + _OPEN_ICE_MARGIN_M:
		return INF
	var shoulder: Vector3 = arm_shoulder()
	var aim_local := Vector3(
			target_blade_xz.x - shoulder.x, 0.0, target_blade_xz.y - shoulder.z)
	if aim_local.length_squared() < 0.000001:
		return INF
	var aim_world: Vector3 = _skater.upper_body.global_transform.basis * aim_local
	var dir := Vector2(aim_world.x, aim_world.z)
	if dir.length_squared() < 0.000001:
		return INF
	var unit: Vector2 = dir.normalized()
	# The net is the second obstacle on this aim line, and it earns the same
	# treatment as the boards: bound the REACH so the stick is never aimed through
	# the mesh, instead of letting it solve full reach and clamping the pose back.
	# NetGeometry.ray_to_solid_face leaves the open mouth unlimited, so reaching in
	# from the front — the whole of net-front play — is untouched.
	return minf(
			GameRules.ray_to_rink_inner(origin, unit),
			NetGeometry.ray_to_net(
					origin, unit, _controller.blade_height,
					_controller.net_blade_half_thickness))

# The cursor (on the ice) no closer in than the stick is held (_reach_floor),
# measured across the ice in the facing's frame: the chest's pitches with a
# lean, and reads a cursor at his skates as one well out.
func _held_out(cursor_world: Vector3) -> Vector3:
	var facing: Transform3D = _skater.global_transform
	var local: Vector3 = facing.affine_inverse() * cursor_world
	var held: Vector2 = CarryPostureRules.held_out(Vector2(local.x, local.z), _reach_floor())
	var world: Vector3 = facing * Vector3(held.x, local.y, held.y)
	world.y = 0.0
	return world


# A centre's address is set over a dot wherever the placement put it.
func _reach_floor() -> float:
	if _controller.has_puck:
		return carry_reach_floor()
	return _controller.stick_reach_min_m * (1.0 - _address_blend())


# How close in a carried puck comes (m off his centre), from his skating fold:
# tick state on every peer, so the floor needs no wire field.
func carry_reach_floor() -> float:
	var folded: float = clampf(-_skater.trunk_fold()
			/ deg_to_rad(_controller.velocity_lean_forward_max_deg), 0.0, 1.0)
	return _controller.carry_reach_min_m + _controller.carry_reach_fold_m * folded


# The solve places the Blade marker, the heel, but the blade plays the puck at
# mid-blade (Skater.get_blade_contact_global, where a carried puck pins and every
# claim measures), so the target steps half a blade back along the shaft
# (`shaft`, hand → blade across the ice, any length): the cursor names the
# contact. While carrying it also steps across, so the blade sits on the
# forehand or backhand side of the cursor and the puck, pinned the same offset
# back (Skater.get_carry_target_global), lands on it.
func _blade_target_along(cursor_xz: Vector2, shaft: Vector2) -> Vector2:
	if shaft.length() <= 0.001:
		return cursor_xz
	var stick_dir: Vector2 = shaft.normalized()
	var target: Vector2 = cursor_xz - stick_dir * (_skater.blade_length * 0.5)
	if _controller.has_puck:
		# 90° rotation in XZ: (X, Z) → (−Z, X). Sign matched in
		# Skater.get_carry_target_global so subtraction inverts cleanly.
		target += Vector2(-stick_dir.y, stick_dir.x) \
				* _skater.get_carry_forehand_factor() * _skater.carry_blade_offset
	return target

# The top-hand solve, in the arm's level frame (UpperBody's yaw without its pitch
# and roll; Scripts/controllers/CLAUDE.md, "The top hand is solved where the arm
# is"), where the ice is flat at blade_y_local(). `desired_blade_xz` is
# UpperBody-local, a point on the ice; the result is too. Writes into and returns
# the shared _ik_result — callers must consume it before the next solve.
# `limits`: lay the reach the body would hold the blade at (the carry's two
# hands, the rest the purpose eases it from) over the arm's own.
func _solve_top_hand(desired_blade_xz: Vector2, blade_side_sign: float,
		max_blade_reach: float = INF, limits: bool = false) -> TopHandIK.Result:
	if limits and _controller.has_puck:
		desired_blade_xz = _carry_backhand_stop(desired_blade_xz, blade_side_sign)
	var tilt: Basis = _level_tilt()
	var shoulder: Vector3 = tilt * arm_shoulder()
	var hang_y: float = (tilt * _trunk_shoulder()).y
	var target: Vector3 = tilt * Vector3(desired_blade_xz.x,
			blade_y_lean_corrected(desired_blade_xz.x, desired_blade_xz.y), desired_blade_xz.y)
	var cfg: TopHandIK.Config = _level_config(hang_y, blade_y_local(), max_blade_reach)
	if limits and _controller.has_puck:
		max_blade_reach = minf(max_blade_reach, _two_hand_reach(
				tilt, shoulder, Vector2(target.x, target.z), blade_side_sign, cfg))
		cfg.max_blade_reach = max_blade_reach
	elif limits and reach_purpose < 1.0:
		max_blade_reach = _rest_reach(tilt, shoulder, Vector2(target.x, target.z),
				blade_side_sign, cfg)
		cfg.max_blade_reach = max_blade_reach
	var ik: TopHandIK.Result = _ik_result
	if _native_top != null:
		_native_top.hand_rest_y = cfg.hand_rest_y
		_native_top.solve_on_ice(shoulder, Vector2(target.x, target.z), blade_side_sign,
				cfg.blade_y, 0.0, 0.0, max_blade_reach, cfg.stick_length, cfg.hand_y_max)
		ik.hand = _native_top.get_hand()
		ik.blade = _native_top.get_blade()
	else:
		TopHandIK.solve(shoulder, Vector2(target.x, target.z), blade_side_sign, cfg, ik)
	var untilt: Basis = tilt.transposed()
	ik.hand = untilt * ik.hand
	ik.blade = untilt * ik.blade
	return ik


# ── Carrying with both hands (Scripts/controllers/CLAUDE.md) ─────────────────
# How far along the aim a carrier's blade can go with the bottom hand still on
# the shaft (TopHandIK.two_hand_reach), in the solve's level frame.
func _two_hand_reach(tilt: Basis, shoulder: Vector3, target_xz: Vector2,
		blade_side_sign: float, cfg: TopHandIK.Config) -> float:
	var bottom: Vector3 = tilt * CarryPostureRules.folded_shoulder(
			SkaterSpineRig.shoulder_in_frame(_skater.bottom_shoulder.position,
			_skater.upper_body.rotation, 0.0, _skater.trunk_fold()), chest_fold())
	var reach: float = (_skater.upper_arm_length + _skater.forearm_length) \
			* _skater.arm_working_extension + _skater.shoulder_reach_m
	if _native_top != null:
		_native_top.hand_rest_y = cfg.hand_rest_y
		_native_top.blade_y = cfg.blade_y
		_native_top.max_blade_reach = cfg.max_blade_reach
		_native_top.stick_length = cfg.stick_length
		_native_top.hand_y_max = cfg.hand_y_max
		return _native_top.two_hand_reach(shoulder, target_xz, blade_side_sign,
				bottom, _grip_fraction(), reach, _glove_spacing())
	return TopHandIK.two_hand_reach(shoulder, target_xz, blade_side_sign, cfg,
			bottom, _grip_fraction(), reach, _glove_spacing(), _two_hand_scratch)


# With nothing to reach for the blade rests where both hands hold the stick, and
# reaches out along the aim to the arm's rim as the purpose comes on. The arm's
# own answer is the scratch solve two_hand_reach starts from.
func _rest_reach(tilt: Basis, shoulder: Vector3, target_xz: Vector2,
		blade_side_sign: float, cfg: TopHandIK.Config) -> float:
	var held: float = _two_hand_reach(tilt, shoulder, target_xz, blade_side_sign, cfg)
	if held == INF:
		return cfg.max_blade_reach
	var arm_blade: Vector3
	if _native_top != null:
		_native_top.solve(shoulder, target_xz, blade_side_sign)
		arm_blade = _native_top.get_blade()
	else:
		TopHandIK.solve(shoulder, target_xz, blade_side_sign, cfg, _two_hand_scratch)
		arm_blade = _two_hand_scratch.blade
	var arm: float = Vector2(arm_blade.x - shoulder.x, arm_blade.z - shoulder.z).length()
	return lerpf(held, arm, reach_purpose)


func _reach_purpose(skater_pos: Vector3) -> float:
	var puck: Puck = _controller.puck
	if puck == null or _controller.has_puck:
		return 1.0
	if _purpose_rim < 0.0:
		_purpose_rim = full_blade_reach()
	var at: Vector3 = puck.global_position
	var vel: Vector3 = puck.linear_velocity
	return ReachPurposeRules.purpose(Vector2(skater_pos.x, skater_pos.z), _purpose_rim,
			Vector2(at.x, at.z), Vector2(vel.x, vel.z), _controller.reach_purpose_lookahead_s,
			_controller.reach_purpose_near_m, _controller.reach_purpose_far_m)


# This build's farthest blade off its body origin (TopHandIK.full_reach): the
# host's claim clamp, the bots' max_blade_reach and the rim the purpose measures
# a puck against.
func full_blade_reach() -> float:
	var c: SkaterController = _controller
	return TopHandIK.full_reach(_skater.shoulder.position,
			deg_to_rad(maxf(c.velocity_lean_forward_max_deg, c.carry_fold_deg)
					+ c.upper_body_lean_forward_max_deg),
			GameRules.FACEOFF_SPAWN_HEIGHT + _skater.upper_body.position.y,
			_skater.shoulder.position.y - c.hand_rest_y, c.rom_forward_reach_max, c.stick_length,
			c.blade_height, _skater.blade_length * 0.5, GameRules.FACEOFF_SPAWN_HEIGHT)


# How far down the shaft the bottom hand must hold to clear the top glove: the
# drawn fist's width across its knuckle roll, so the gloves meet and never
# overlap.
func _glove_spacing() -> float:
	return _skater.arm_ball_radius(SkaterMeshBuilder.UpperBone.TOP_HAND) \
			* SkaterMeshBuilder.GLOVE_FIST_SPAN


# The backhand angle past which the bottom hand lets go (bh_release_angle_deg,
# off the body as _bh_backhand_angle measures it): a carrier's blade stops on it.
func _carry_backhand_stop(target_xz: Vector2, blade_side_sign: float) -> Vector2:
	var on_ice: Vector3 = _skater.upper_body_to_global(Vector3(target_xz.x,
			blade_y_lean_corrected(target_xz.x, target_xz.y), target_xz.y))
	var body: Basis = _skater.global_transform.basis
	var rel: Vector3 = body.inverse() * (on_ice - _skater.global_position)
	var r: float = Vector2(rel.x, rel.z).length()
	var limit: float = deg_to_rad(_controller.bh_release_angle_deg)
	if r < 0.01 or atan2(rel.x, -rel.z) * -blade_side_sign <= limit:
		return target_xz
	var a: float = limit * -blade_side_sign
	var stopped: Vector3 = _skater.upper_body_to_local(_skater.global_position
			+ body * Vector3(sin(a) * r, rel.y, -cos(a) * r))
	return Vector2(stopped.x, stopped.z)


# UpperBody's pitch and roll: level-frame = _level_tilt() * UpperBody-local.
func _level_tilt() -> Basis:
	var lean: Vector3 = _skater.upper_body.rotation
	return Basis.from_euler(Vector3(lean.x, 0.0, lean.z))


# The solve's config with the hand heights (authored as drops below the shoulder
# marker) hung below `hang_y`: the trunk's shoulder in the level frame, not the
# address-folded one the faceoff's hand heights were never authored against.
func _level_config(hang_y: float, blade_y: float, max_blade_reach: float) -> TopHandIK.Config:
	var cfg: TopHandIK.Config = _ik_config(blade_y, max_blade_reach)
	var marker_y: float = _skater.shoulder.position.y
	cfg.hand_rest_y = hang_y - (marker_y - _controller.hand_rest_y)
	cfg.hand_y_max = hang_y - (marker_y - cfg.hand_y_max)
	return cfg

# ── Bottom Hand ───────────────────────────────────────────────────────────────
# Recompute the bottom hand pose from the current top_hand + blade positions.
# Purely reactive — does not affect blade or top-hand placement, and nothing
# but the arm rig reads it. Caller must have already written the top hand and
# blade for this tick before calling.
#
# The grip is where the arm can hold, not a fixed fraction: the hand slides up
# the shaft to stay within reach, and lets go of the stick when none of it is.
# The reach is the arm at its working extension plus the shoulder girdle's give
# (SkaterArmRig roots the arm with the same give), measured from the shoulder
# the arm hangs from on the visible trunk — in a hard turn the balance lean puts
# that up to ~0.14 m from the marker — so the drawn arm is never shorter than
# the span it bridges.
#
# Letting go and taking hold again take time: the release the geometry asks for
# is eased by a critically damped spring at render rate (`delta`; below 0 it
# lands at once, for the paths with no clock), since a blade dangling at speed
# crosses the release bands in a tick or two and the hand jumped ~0.4 m between
# shaft and rest. A let-go hand swings with the stride.
const BH_GRIP_SLIDE_BAND: float = 0.08
# The drawn shaft held out of the body: where along it from the top hand it is
# measured (below the top fist, which sits on it, to above the blade, which the
# hand's swing barely moves), at how many points, over how many passes, how
# far clear of the pants and the jersey (m), the swing's most (m) and its
# spring (rad/s).
const _CLEAR_FROM: float = 0.12
const _CLEAR_TO: float = 0.85
const _CLEAR_SAMPLES: int = 10
const _CLEAR_PASSES: int = 4
const _CLEAR_MARGIN_M: float = 0.01
const _CLEAR_MAX_M: float = 0.4
const _CLEAR_OMEGA: float = 12.0
const _SHAFT_RADIUS_M: float = 0.015

func update_bottom_hand(delta: float = -1.0) -> void:
	var blade_local: Vector3 = _skater.drawn_blade().origin
	var pump: Vector3 = _stride_pump(delta)
	_skater.set_hand_pump(pump)
	_skater.set_hand_pump(pump + _shaft_clearance(_skater.drawn_top_hand(), blade_local, delta))
	var hand_local: Vector3 = _skater.drawn_top_hand()
	var shoulder: Vector3 = _skater.visible_shoulder(_skater.bottom_shoulder.position)
	var arm: float = _skater.upper_arm_length + _skater.forearm_length
	var reach: float = arm * _skater.arm_working_extension + _skater.shoulder_reach_m
	var held: Vector2 = BottomHandIK.soft_reachable_grip(shoulder, hand_local, blade_local,
			_grip_fraction(), reach, _glove_spacing(), BH_GRIP_SLIDE_BAND)
	var grip: float = held.x
	var grip_target_xz := Vector2(
			lerpf(hand_local.x, blade_local.x, grip),
			lerpf(hand_local.z, blade_local.z, grip))
	# Derive grip Y from the stick shaft so the hand stays on the stick regardless
	# of pitch lean or reach. bh_hand_y offsets for fine-tuning.
	var grip_y: float = lerpf(hand_local.y, blade_local.y, grip) + _controller.bh_hand_y
	var cfg: BottomHandIK.Config = _bottom_hand_ik_config()
	var release: float = BottomHandIK.release_weight(cfg)
	if held.y > 0.0:
		release = 1.0 - (1.0 - release) \
				* (1.0 - smoothstep(0.0, _controller.bh_reach_release_band_m, held.y))
	if delta < 0.0:
		_bh_release = release
		_bh_release_vel = 0.0
	elif delta > 0.0:
		var eased: Vector4 = BalanceRules.spring_step(Vector2(_bh_release, 0.0),
				Vector2(_bh_release_vel, 0.0), Vector2(release, 0.0),
				_controller.bh_release_omega, delta)
		_bh_release = clampf(eased.x, 0.0, 1.0)
		_bh_release_vel = eased.z if _bh_release == eased.x else 0.0
	var side: float = signf(_skater.bottom_shoulder.position.x)
	var rest_arm: Vector3 = _controller.bh_free_hand_rest_arm + _free_hand_swing(side)
	var rest: Vector3 = shoulder + Vector3(rest_arm.x * side, rest_arm.y, rest_arm.z) * arm
	var bh: Vector3 = Vector3(grip_target_xz.x, grip_y, grip_target_xz.y).lerp(rest, _bh_release)
	if _held_free_weight > 0.0:
		bh = bh.lerp(_held_free_hand, _held_free_weight)
	# Off the stick, the hand hangs where the arm can put it.
	var span: Vector3 = bh - shoulder
	if span.length() > reach:
		bh = shoulder + span.normalized() * reach
	_skater.set_bottom_hand_position(bh)

# Takes the free hand to `pos` (upper-body local) by `weight`; 0 hands it back.
func hold_free_hand(pos: Vector3, weight: float) -> void:
	_held_free_hand = pos
	_held_free_weight = weight


# The let-go hand's swing off its rest, arm lengths (x out, y up, z back): it
# comes forward and across as the leg on its own side pushes out, the way a
# skater's free arm balances the stroke, by how hard the legs are stroking.
func _free_hand_swing(side: float) -> Vector3:
	if _skating == null:
		return Vector3.ZERO
	var drive: float = clampf(_skating.push_strength, 0.0, 1.0)
	return _controller.bh_free_hand_swing_arm * (side * sin(_skating.stride_phase) * drive)

# Both hands on the stick, the stroke pumps them across the body with the
# stride, the stick pivoting about its blade: drawn only (Skater.drawn_top_hand),
# so the blade and the hand every claim reads stay where the tick put them.
# While the tracked IK has the stick, handing over to the shots and the block,
# which pose their own, across PUMP_HANDOFF_S.
func _stride_pump(delta: float) -> Vector3:
	if _skating == null:
		return Vector3.ZERO
	var state := _controller.get_shot_state() as State
	var tracked: bool = SkaterPoseBridge.owner_of(state) == SkaterPoseBridge.Owner.TRACKED
	if delta < 0.0:
		_pump_hold = 1.0 if tracked else 0.0
	else:
		_pump_hold = move_toward(_pump_hold, 1.0 if tracked else 0.0, delta / PUMP_HANDOFF_S)
	var drive: float = clampf(_skating.push_strength, 0.0, 1.0) * (1.0 - _bh_release) \
			* smoothstep(0.0, 1.0, _pump_hold)
	return _controller.stride_hand_pump_m * (sin(_skating.stride_phase) * drive)

# ── The hold (StickHoldRules) ─────────────────────────────────────────────────
# The pocket's size as shares of the arm (StickHoldRules.Config): its middle
# off the shoulder (inside it, toward the belt buckle, and ahead), then its
# reach ahead, out and across.
const _HOLD_HOME_OF_ARM := Vector2(-0.15, 0.27)
const _HOLD_REACH_OF_ARM := Vector3(0.44, 0.37, 0.44)
# How far it draws out to its own side from a blade in close, of the arm.
const _HOLD_DRAW_OF_ARM: float = 0.32
# A blade lifted this far off the ice (m: a stick lift, a deflect's rise, the
# commit's raise) is turned up about the hands: the hold, which describes a
# blade on the ice, is gone by the second.
const _HOLD_LIFT_M := Vector2(0.1, 0.3)
# How far out the arm is (of its reach, along the line from the shoulder to
# the blade) as the hand leaves its pocket for the reach solve's own
# (StickHoldRules.reaching): both hands' carry ends about half out, and the
# one-handed reach is all of it.
const _HOLD_REACHING_OF_ARM := Vector2(0.5, 0.9)
# The corner (radians of the stick's turn about its blade) over which a held
# hand at the arm's reach starts coming round toward its shoulder.
const _HOLD_REACH_BAND: float = 0.1

# Where the top hand holds a tracked stick whose blade the reach solve put at
# `blade_local` with its own hand at `reach_hand` (both UpperBody's frame),
# under a chest folded `fold`: where a player holds it (StickHoldRules), turned
# there round the blade so the stick keeps the length the solve gave it, and no
# further off its shoulder than the arm reaches. The solve's hand says where
# the blade may go and how long the stick is; this one is the marker's, so the
# stick every peer draws and every claim reads is the held one.
func _held_hand(reach_hand: Vector3, blade_local: Vector3, fold: float) -> Vector3:
	var share: float = _hold_share()
	if share <= 0.0:
		return reach_hand
	var tilt: Basis = _level_tilt()
	var blade: Vector3 = tilt * blade_local
	var reached: Vector3 = tilt * reach_hand
	var length: float = reached.distance_to(blade)
	if length < 0.01:
		return reach_hand
	var shoulder: Vector3 = tilt * CarryPostureRules.folded_shoulder(_trunk_shoulder(), fold)
	var arm: float = _arm_reach()
	var held: Vector3 = StickHoldRules.top_hand(shoulder, blade, length,
			signf(_skater.shoulder.position.x), _hold_config())
	held = StickHoldRules.reaching(held, reached, blade, shoulder,
			length + arm * _HOLD_REACHING_OF_ARM.x, length + arm * _HOLD_REACHING_OF_ARM.y)
	held = StickHoldRules.within_reach(held, blade, shoulder, arm, _HOLD_REACH_BAND)
	if share < 1.0:
		held = blade + ((reached - blade) / length).slerp((held - blade) / length, share) * length
	return tilt.transposed() * held


# How much of the hold a tracked stick takes, before its reach: none of it at
# the centre's address or on the ice in a knockdown, which pose their own
# hands, and none on a blade lifted off the ice.
func _hold_share() -> float:
	return (1.0 - _address_blend()) * (1.0 - _controller.knockdown_pose_weight()) \
			* (1.0 - smoothstep(_HOLD_LIFT_M.x, _HOLD_LIFT_M.y, _blade_lift()))


func _arm_reach() -> float:
	return (_skater.upper_arm_length + _skater.forearm_length) \
			* _skater.arm_working_extension + _skater.shoulder_reach_m


func _hold_config() -> StickHoldRules.Config:
	if _cached_hold_cfg == null:
		var arm: float = _skater.upper_arm_length + _skater.forearm_length
		var cfg := StickHoldRules.Config.new()
		cfg.lie = deg_to_rad(_skater.blade_lie_deg)
		cfg.home_out = _HOLD_HOME_OF_ARM.x * arm
		cfg.home_ahead = _HOLD_HOME_OF_ARM.y * arm
		cfg.reach_ahead = _HOLD_REACH_OF_ARM.x * arm
		cfg.reach_out = _HOLD_REACH_OF_ARM.y * arm
		cfg.reach_across = _HOLD_REACH_OF_ARM.z * arm
		cfg.draw = _HOLD_DRAW_OF_ARM * arm
		_cached_hold_cfg = cfg
	return _cached_hold_cfg


# The drawn top hand (`hand_local`, UpperBody's frame, the pump on it) swung
# round the drawn blade, the stick keeping its length, until the drawn shaft is
# out of the jersey and the legs: the offset that takes it there, eased on a critically
# damped spring (`delta` below 0 lands at once). Mesh only: the markers, the
# blade and the puck stay where the tick put them. Each pass moves the hand by
# what lifts the deepest point clear, more the nearer that point is to the
# blade, the pivot.
func _shaft_clearance(hand_local: Vector3, blade_local: Vector3, delta: float) -> Vector3:
	var ub: Transform3D = _skater.drawn_upper_body()
	var blade: Vector3 = ub * blade_local
	var start: Vector3 = ub * hand_local
	var hand: Vector3 = start
	var length: float = hand.distance_to(blade)
	if length > 0.001:
		_skater.drawn_leg_joints(_leg_joints)
		var girth: Vector2 = _skater.leg_girth()
		for _pass: int in _CLEAR_PASSES:
			var worst: float = 0.0
			var push := Vector3.ZERO
			var at: float = 0.0
			for k: int in _CLEAR_SAMPLES:
				var t: float = lerpf(_CLEAR_FROM, _CLEAR_TO, float(k) / float(_CLEAR_SAMPLES - 1))
				var out: Vector4 = _into_body(hand.lerp(blade, t), girth)
				if out.w > worst:
					worst = out.w
					push = Vector3(out.x, out.y, out.z)
					at = t
			if worst <= 0.0:
				break
			hand += push * (worst / (1.0 - at))
			hand = blade + (hand - blade).normalized() * length
	var target: Vector3 = (ub.affine_inverse() * hand - ub.affine_inverse() * start) \
			.limit_length(_CLEAR_MAX_M)
	# The spring carries its state frame to frame, so one non-finite input would
	# hold the drawn stick and both arms at NaN, undrawn, for the rest of the
	# match. Such a frame holds the last offset; a state already poisoned lands.
	if not target.is_finite():
		return _clear_offset if _clear_offset.is_finite() else Vector3.ZERO
	if delta < 0.0 or not (_clear_offset.is_finite() and _clear_vel.is_finite()):
		_clear_offset = target
		_clear_vel = Vector3.ZERO
	elif delta > 0.0:
		var x: Vector3 = _clear_offset - target
		var decay: float = exp(-_CLEAR_OMEGA * delta)
		var kick: Vector3 = _clear_vel + x * _CLEAR_OMEGA
		_clear_offset = target + (x + kick * delta) * decay
		_clear_vel = (_clear_vel - kick * (_CLEAR_OMEGA * delta)) * decay
	return _clear_offset


# How deep `point` (the skeleton's space) sits in the jersey or the legs past
# the shaft's thickness and the margin (w, m), and the way out (xyz): the
# deepest of the jersey and each thigh and shin.
func _into_body(point: Vector3, girth: Vector2) -> Vector4:
	var reach: float = _SHAFT_RADIUS_M + _CLEAR_MARGIN_M
	var clear: float = _skater.torso_clearance(point)
	var best := Vector4(0.0, 0.0, 0.0, reach - clear)
	if best.w > 0.0:
		var e: float = 0.01
		var grad := Vector3(
				_skater.torso_clearance(point + Vector3(e, 0.0, 0.0)) - clear,
				_skater.torso_clearance(point + Vector3(0.0, e, 0.0)) - clear,
				_skater.torso_clearance(point + Vector3(0.0, 0.0, e)) - clear)
		grad = grad.normalized() if grad.length_squared() > 1e-12 else Vector3.BACK
		best = Vector4(grad.x, grad.y, grad.z, best.w)
	for leg: int in 2:
		for seg: int in 2:
			var a: Vector3 = _leg_joints[leg * 3 + seg]
			var b: Vector3 = _leg_joints[leg * 3 + seg + 1]
			var q: Vector3 = Geometry3D.get_closest_point_to_segment(point, a, b)
			var off: Vector3 = point - q
			var d: float = off.length()
			var depth: float = (girth.x if seg == 0 else girth.y) + reach - d
			if depth > best.w:
				var n: Vector3 = off / d if d > 1e-5 else Vector3.BACK
				best = Vector4(n.x, n.y, n.z, depth)
	return best


# ── The shoulder the top hand works from ───────────────────────────────────────
# Where the top arm is drawn from — the trunk's shoulder, then the faceoff
# address's fold or the chest's over the stick — from tick state alone
# (Scripts/controllers/CLAUDE.md).
func arm_shoulder() -> Vector3:
	return CarryPostureRules.folded_shoulder(address_shoulder(_trunk_shoulder()), chest_fold())


# How far the chest folds over the stick (CarryPostureRules), from the blade
# marker where the tick has it and the posture's own fold; the centre's address
# folds it instead, and a shot or the block, which pose their own stick, not at
# all. The reach the tick allows is measured from shoulders under this fold;
# the hands are held and the body drawn under ready_fold.
func chest_fold() -> float:
	if _skater == null or not tracking() or not _controller.has_puck:
		return 0.0
	return _fold_over(_controller.carry_fold_deg, CarryPostureRules.OUT_M) \
			* (1.0 - _address_blend())


# How far the chest is folded over a tracked stick, as the hands hold it and
# the body is drawn: eased on the tick (SkaterReadyFold), so a pickup, a shot
# taking the stick and the blade coming in all move the hands and the trunk
# together. Deeper than the fold the reach solve measures its shoulders at
# (chest_fold), which is the reach the tick allows: shoulders ahead of the
# solve's are only ever nearer the hands it placed.
func ready_fold() -> float:
	if _controller == null:
		return 0.0
	# A celebration and the centre's address take it off on their own ramps:
	# their hands are posed off shoulders this has not folded.
	return ready.value() * (1.0 - _controller.celebration_share()) * (1.0 - _address_blend())


func _ready_fold_target() -> float:
	if _controller == null:
		return 0.0
	return _settled_fold(_controller.hold_fold_deg if _controller.has_puck
			else _controller.ready_fold_deg)


# The fold the blade's target is laid by: a carrier's, settled.
func _lay_fold() -> float:
	return _settled_fold(_controller.hold_fold_deg)


# The ready fold of `full_deg` at most, where the blade puts it once the
# spring has settled.
func _settled_fold(full_deg: float) -> float:
	if _skater == null or not tracking():
		return 0.0
	return maxf(_fold_over(full_deg, _READY_FOLD_OUT_M),
			_fold_over(_READY_FOLD_NEAR_DEG, CarryPostureRules.OUT_M))


# The blade's distance off his centre (m) the ready fold comes on over: none
# of it at the first, where the chest is up over a puck in close and the
# shoulders are back off the stick, all of it by the second, a stick's span out.
const _READY_FOLD_OUT_M := Vector2(0.95, 1.5)
# And the lean a dangle keeps inside that: with none he sits bolt upright over
# bent knees.
const _READY_FOLD_NEAR_DEG: float = 8.0
# Whether the tracked solve has the stick (a shot, the block and the rest pose
# their own).
func tracking() -> bool:
	return _controller != null \
			and SkaterPoseBridge.owner_of(_controller.get_shot_state() as State) \
			== SkaterPoseBridge.Owner.TRACKED


# The chest's fold of `full_deg` at most over the blade where the tick has it,
# coming on over `out_m` (m off his centre).
func _fold_over(full_deg: float, out_m: Vector2) -> float:
	var blade: Vector3 = _skater.upper_body.transform * _skater.blade.position
	return CarryPostureRules.fold(Vector2(blade.x, blade.z), _skater.trunk_fold(),
			deg_to_rad(full_deg), out_m)


func _trunk_shoulder() -> Vector3:
	return SkaterSpineRig.shoulder_in_frame(_skater.shoulder.position,
			_skater.upper_body.rotation, 0.0, _skater.trunk_fold())


# ── The centre's faceoff address ──────────────────────────────────────────────
# What the hand solves owe a centre set over the dot. Why each exists, and what
# the pose does without it, is in Scripts/controllers/CLAUDE.md under "The
# faceoff pose is two poses". All of it rides the gait's address ease, which
# advances on ticks through the countdown (the locked-phase path drives the gait
# itself), so these stay a function of tick state.

# Where a shoulder sits once the address has folded the chest over the dot. The
# ARMS are rooted there, not at the marker (SkaterArmRig._textured_shoulder), so
# a hand solved off the marker lands a third of a metre behind the shoulder it
# hangs from — which the two-bone IK can only answer by putting the elbow in
# front of the wrist. Rebuilt from the AUTHORED fold rather than read off the
# render-rate trunk channel: per-stride texture in the hands would shake the
# stick at stride frequency.
func address_shoulder(marker: Vector3) -> Vector3:
	var fold: float = deg_to_rad(_controller.faceoff_center_lean_deg) * _address_blend()
	if fold < 0.001:
		return marker
	return Basis.from_euler(Vector3(-fold, 0.0, 0.0)) * marker


# The ceiling the top hand may rise to. TopHandIK answers a puck inside the
# stick's own reach by raising the hand and steepening the shaft — right for a
# carry in tight, wrong for an address, where it walks the hand up to the
# shoulder and folds the arm shut behind it.
func _address_hand_ceiling() -> float:
	var address: float = _address_blend()
	if address < 0.001:
		return _controller.hand_y_max
	return lerpf(_controller.hand_y_max, _address_hand_y(), address)


func _address_hand_y() -> float:
	return _controller.hand_rest_y + _controller.faceoff_center_hand_rise


# The forward carry of the shoulder, and the shaft's horizontal span, in the
# SETTLED address — for the placement, which runs at the whistle on a body that
# is still standing, still holding a full stick, with the fold not yet eased in,
# so every one of them measured live is the wrong number.
func address_carry() -> float:
	var marker: Vector3 = _skater.shoulder.position
	var folded: Vector3 = Basis.from_euler(Vector3(
			-deg_to_rad(_controller.faceoff_center_lean_deg), 0.0, 0.0)) * marker
	return marker.z - folded.z


func address_stick_horiz() -> float:
	var drop: float = _address_hand_y() - blade_y_local() \
			- (_skating.faceoff_address_drop() - _skating.frame_drop)
	var length: float = _controller.stick_length - _skater.faceoff_choke_m
	return sqrt(maxf(length * length - drop * drop, 0.0001))


# How far down the shaft the bottom hand holds: the short lever a draw is won
# with, walked down over the countdown rather than jumped to.
func _grip_fraction() -> float:
	return lerpf(_controller.bottom_hand_grip_fraction,
			_controller.faceoff_center_grip_fraction, _address_blend())


func _address_blend() -> float:
	if _skating == null or not _skater.is_faceoff_center:
		return 0.0
	return _skating.faceoff_blend


# The commit stance poses the HAND and derives the blade from it, rather than
# posing the blade and letting the hand fall out. Why blade-first cannot work
# here — and why the elbow reversed when it was used — is in
# Scripts/controllers/CLAUDE.md under "Pose the hand, not the blade".
func _commit_hand_pose(hand_local: Vector3, blade_local: Vector3,
		blade_side_sign: float, commit_t: float) -> TopHandIK.Result:
	var posed_hand := Vector3(
			_controller.hit_commit_hand_local_x * blade_side_sign,
			_controller.hit_commit_hand_local_y,
			_controller.hit_commit_hand_local_z)
	# Authoring both ends over-constrains a rigid stick, and enforce_rigid_stick
	# only ever SHORTENS an over-long span — an under-long pair passes straight
	# through and draws a stick too short for the body holding it.
	var stick: float = solve_stick_length()
	var drop: float = posed_hand.y - blade_local.y
	var horiz: float = sqrt(maxf(stick * stick - drop * drop, 0.0001))
	# Where the stick POINTS while it is held ready, as a bearing off the hand —
	# the choke decides how far along it the blade sits. Swept off the shoulder
	# being thrown: that shoulder is driving into the contact, and a stick planted
	# on it swings through it.
	var bearing := Vector2(
			(_controller.hit_commit_blade_bearing_x
					- _skater.get_check_lead() * _controller.hit_commit_blade_sweep)
					* blade_side_sign,
			_controller.hit_commit_blade_bearing_z)
	if bearing.length_squared() < 0.000001:
		bearing = Vector2(0.0, -1.0)
	bearing = bearing.normalized()
	var posed_blade := Vector3(
			posed_hand.x + bearing.x * horiz,
			blade_local.y,
			posed_hand.z + bearing.y * horiz)
	_rigid_result.hand = hand_local.lerp(posed_hand, commit_t)
	_rigid_result.blade = blade_local.lerp(posed_blade, commit_t)
	return _rigid_result


# Rigid-stick correction for a POSED hand/blade pair — this skater's shoulder and
# cached config wrapped around the pure rule (TopHandIK.enforce_rigid_stick).
# Shared with SkaterShotPoseCoordinator, which runs every pose it authors through
# this and runs it again once the obstacle clamps have had their say, so no shot
# pose can draw a shaft longer than the stick. The returned Result is shared and
# overwritten by the next call: consume it before correcting again.
#
# The tracked path does not need it — it authors its pose through TopHandIK, which
# is rigid by construction, and rebuilds through the exact inverse.
# The arm rebuilt to reach a blade a clamp put at `blade_local`. The rebuild
# bounds the ARM but leaves stick length free, so a clamp that puts the blade
# past arm + stick has nowhere to put the difference except the shaft — a
# stretched stick, the one thing a rigid object cannot do. Reaching in through
# the open mouth is where that bites: the reach limit deliberately leaves the
# mouth unbounded (net-front play depends on it), so the twine is free to move
# the blade a long way. The rigid pass is inert whenever the blade is reachable.
# Returns the shared rigid_stick Result.
func _arm_for_clamped_blade(blade_local: Vector3, blade_side_sign: float) -> TopHandIK.Result:
	var tilt: Basis = _level_tilt()
	var clamped_level: Vector3 = tilt * blade_local
	var hand_local: Vector3 = tilt.transposed() * TopHandIK.hand_for_clamped_blade(
			tilt * arm_shoulder(),
			Vector2(clamped_level.x, clamped_level.z),
			clamped_level.y,
			blade_side_sign,
			_level_config((tilt * _trunk_shoulder()).y, blade_y_local(), INF))
	return rigid_stick(hand_local, blade_local, blade_side_sign)


func rigid_stick(hand_local: Vector3, blade_local: Vector3,
		blade_side_sign: float) -> TopHandIK.Result:
	TopHandIK.enforce_rigid_stick(
			arm_shoulder(), hand_local, blade_local, blade_side_sign,
			_ik_config(blade_local.y), _rigid_result)
	return _rigid_result

# ── Net Collision ─────────────────────────────────────────────────────────────
# Resolves the blade SEGMENT (heel → toe) against the net for a proposed heel,
# and returns the correction to apply. Pure collision: iron stops the stick, the
# twine lets it sink in and stops it there, and neither strips the puck — see
# NetBladeCollision, and docs/net-play-plan.md §3 for why there is no legality
# concept on this path any more.
#
# Which face holds the stick is classified from NetBladeCollision.side_anchor,
# never last tick's raw contact, which can sit on the far side of the twine.
#
# The returned Result is shared and overwritten by the next call, like _ik_result:
# consume it before resolving again.
func resolve_blade_against_net(heel_world: Vector3) -> NetBladeCollision.Result:
	var prev: Vector3 = _skater.get_prev_blade_contact_global()
	_net_side_anchor = NetBladeCollision.side_anchor(_net_side_anchor, prev) \
			if _has_net_side_anchor else prev
	_has_net_side_anchor = true
	NetBladeCollision.resolve(
			_net_side_anchor,
			heel_world,
			_blade_toe_for(heel_world),
			_controller.net_blade_half_thickness,
			GameRules.NET_BLADE_MESH_GIVE,
			_net_result)
	return _net_result

# The blade's far end for a hypothetical heel, using the blade node's CURRENT
# forward. Same approximation Skater.clamp_blade_to_walls makes for the boards:
# this tick's orientation applied to the position the solve is proposing.
func _blade_toe_for(heel_world: Vector3) -> Vector3:
	var forward: Vector3 = -_skater.blade.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return heel_world
	return heel_world + forward.normalized() * _skater.blade_length

# ── The goalie ────────────────────────────────────────────────────────────────
# The translation that holds the blade at `heel_world` out of every goalie's
# gear (GoalieGearCollision): a wall it slides along, carrying or not, that
# never strips. Swept from the blade's middle at the start of the tick. The
# blade lies along the shaft from this tick's hand at `hand_world`, as
# Skater.set_blade_position will turn it, not along last tick's facing: a stick
# swept across him turns a long way in a tick, and its toe with it.
func resolve_blade_against_goalies(heel_world: Vector3, hand_world: Vector3) -> Vector3:
	var boxes: PackedFloat32Array = _goalie_boxes()
	if boxes.is_empty():
		return Vector3.ZERO
	var along: Vector3 = heel_world - hand_world
	along.y = 0.0
	var toe: Vector3 = heel_world + along.normalized() * _skater.blade_length \
			if along.length_squared() > 0.000001 else heel_world
	return GoalieGearCollision.resolve(_skater.get_prev_blade_contact_global(), heel_world, toe,
			_controller.net_blade_half_thickness, boxes)


func _goalie_boxes() -> PackedFloat32Array:
	if not _controller._game_state.has_method("get_goalie_boxes"):
		return _no_goalies
	return _controller._game_state.get_goalie_boxes()

# ── Geometry Helpers ──────────────────────────────────────────────────────────
# Converts the world-space blade_height to upper-body-local Y.
# Uses the upper body's world Y so the result is correct regardless of where
# the skater's body origin sits above the ice.
func blade_y_local() -> float:
	return (_controller.blade_height + _blade_lift()) - _skater.upper_body.global_position.y


# How far the tracked blade is held up off the ice (m).
func _blade_lift() -> float:
	# The eased stick lift, so a lifted blade (and the hand/stick the IK solves
	# from it) rises off the ice. blend is 0 in all shot/carry states (blade_up
	# is gated off then), so this is nothing except during a lift. A deflect's
	# blend stops at its share of the full height (Skater.deflect_lift_share).
	var lift: float = _skater.get_blade_lift_blend() * _controller.blade_lift_height
	# Plus the commit-stance stick raise: a body-check commit pulls the stick off
	# the ice as a readable tell. Gameplay-inert (the blade is already withdrawn
	# from puck play while committed); 0 except during an empty-handed commit.
	return lift + _skater.get_commit_lift_blend() * _controller.hit_commit_blade_lift_m

# Lean-corrected blade Y for a given blade local (X, Z). Computes the local Y
# that — after the upper body's pitch (X) and roll (Z) rotations under Godot's
# default YXZ Euler order — lands the blade at world Y = blade_height.
# Solving world_y = ub.y + (x*sin(r) + y*cos(r))*cos(p) - z*sin(p) for y gives:
#   y = (blade_y_local() + z*sin(p) - x*sin(r)*cos(p)) / (cos(p)*cos(r))
# A small-angle approximation (drop the cos divisors) drifts ~3 cm at max reach
# with full reach lean (18° forward pitch); the exact form is used here so the
# IK can consume the correct blade_y up front and produce a hand consistent
# with stick_length, instead of post-IK overriding blade.y and stretching the
# visible stick mesh.
func blade_y_lean_corrected(blade_local_x: float, blade_local_z: float) -> float:
	var pitch: float = _skater.upper_body.rotation.x
	var roll: float = _skater.upper_body.rotation.z
	var cp: float = cos(pitch)
	var cr: float = cos(roll)
	# Guard against the degenerate near-90° case so the solver never divides
	# by zero. In practice the upper body never approaches 90° lean.
	if cp < 0.001:
		cp = 0.001
	if cr < 0.001:
		cr = 0.001
	var numerator: float = blade_y_local() + blade_local_z * sin(pitch) - blade_local_x * sin(roll) * cp
	return numerator / (cp * cr)

# The stick length every arm solve must use THIS instant: the rigid shaft minus
# however far the top hand has slid down it (zero outside a check commit). One
# accessor, because two sites solving one frame from different lengths draw two
# different sticks — and the shot poses do overlap a commit (a one-timer can be
# charged empty-handed with the Hit button down).
func solve_stick_length() -> float:
	return _controller.stick_length - _skater.grip_choke()


# Horizontal projection of the stick onto the XZ plane, given the fixed
# vertical drop from hand to blade. Used by follow-through to keep stick
# length consistent with the IK solver.
func stick_horiz() -> float:
	var drop: float = _controller.hand_rest_y - blade_y_local()
	var length: float = solve_stick_length()
	return sqrt(maxf(length * length - drop * drop, 0.0001))


# ── Config Builders ───────────────────────────────────────────────────────────
# Cached: export-derived fields are filled once (until invalidate_configs);
# only the per-tick fields are written per call.
func _ik_config(blade_y: float, max_blade_reach: float = INF) -> TopHandIK.Config:
	if _cached_top_cfg == null:
		_cached_top_cfg = TopHandIK.Config.new()
		_cached_top_cfg.hand_rest_y = _controller.hand_rest_y
		_cached_top_cfg.hand_y_max = _controller.hand_y_max
		_cached_top_cfg.rom_forehand_angle_max = deg_to_rad(_controller.rom_forehand_angle_max_deg)
		_cached_top_cfg.rom_backhand_angle_max = deg_to_rad(_controller.rom_backhand_angle_max_deg)
		_cached_top_cfg.rom_forward_reach_max = _controller.rom_forward_reach_max
		_cached_top_cfg.rom_forehand_reach_max = _controller.rom_forehand_reach_max
		_cached_top_cfg.rom_backhand_reach_max = _controller.rom_backhand_reach_max
		if _native_top != null:
			_native_top.rom_forward_reach_max = _cached_top_cfg.rom_forward_reach_max
			_native_top.hand_rest_y = _cached_top_cfg.hand_rest_y
			_native_top.hand_y_max = _cached_top_cfg.hand_y_max
			_native_top.rom_forehand_angle_max = _cached_top_cfg.rom_forehand_angle_max
			_native_top.rom_backhand_angle_max = _cached_top_cfg.rom_backhand_angle_max
			_native_top.rom_forehand_reach_max = _cached_top_cfg.rom_forehand_reach_max
			_native_top.rom_backhand_reach_max = _cached_top_cfg.rom_backhand_reach_max
	# All three per-tick fields are written on EVERY call, never left to carry
	# over: max_blade_reach is a property of the aim line being solved, so a stale
	# one would silently constrain an unrelated later solve this tick, and the
	# choked stick_length below is a property of this instant's grip.
	_cached_top_cfg.blade_y = blade_y
	_cached_top_cfg.hand_rest_y = _controller.hand_rest_y
	_cached_top_cfg.max_blade_reach = max_blade_reach
	_cached_top_cfg.stick_length = solve_stick_length()
	_cached_top_cfg.hand_y_max = _address_hand_ceiling()
	_cached_top_cfg.hand_forward = _hand_forward()
	_cached_top_cfg.hand_forward_none = _controller.top_hand_forward_none_m
	_cached_top_cfg.hand_forward_full = _controller.top_hand_forward_full_m
	if _native_top != null:
		_native_top.blade_y = blade_y
		_native_top.max_blade_reach = max_blade_reach
		_native_top.stick_length = _cached_top_cfg.stick_length
		_native_top.hand_y_max = _cached_top_cfg.hand_y_max
		_native_top.hand_forward = _cached_top_cfg.hand_forward
		_native_top.hand_forward_none = _cached_top_cfg.hand_forward_none
		_native_top.hand_forward_full = _cached_top_cfg.hand_forward_full
	return _cached_top_cfg

# The forehand floor's strength (TopHandIK.Config.hand_forward): the centre's
# address holds its own hands (its ceiling, its fold), and a shot or the block,
# posing their own stick, keep the floorless solve.
func _hand_forward() -> float:
	if SkaterPoseBridge.owner_of(_controller.get_shot_state() as State) \
			!= SkaterPoseBridge.Owner.TRACKED:
		return 0.0
	return _controller.top_hand_forward_m * (1.0 - _address_blend())


func _bottom_hand_ik_config() -> BottomHandIK.Config:
	if _cached_bottom_cfg == null:
		_cached_bottom_cfg = BottomHandIK.Config.new()
		_cached_bottom_cfg.release_angle_max = deg_to_rad(_controller.bh_release_angle_deg)
		_cached_bottom_cfg.release_angle_band = deg_to_rad(_controller.bh_release_angle_band_deg)
	_cached_bottom_cfg.backhand_angle = _bh_backhand_angle()
	return _cached_bottom_cfg

# Blade world angle toward the backhand side, in the skater's body frame.
# Returns a positive value when the blade is on the backhand side; 0 on forehand.
func _bh_backhand_angle() -> float:
	var blade_world: Vector3 = _skater.upper_body_to_global(_skater.get_blade_position())
	var to_blade: Vector3 = blade_world - _skater.global_position
	to_blade.y = 0.0
	if to_blade.length() < 0.01:
		return 0.0
	var skater_dir: Vector3 = _skater.global_transform.basis.inverse() * to_blade.normalized()
	var blade_angle: float = atan2(skater_dir.x, -skater_dir.z)
	# For a lefty the backhand side is +X (positive angle); negate blade_side_sign
	# so the result is always positive toward backhand regardless of handedness.
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	return blade_angle * -blade_side_sign

class_name SkaterPoseCoordinator
extends RefCounted

# Owns the per-tick pose layer: facing, upper-body twist/lean, velocity lean,
# lower-body lag, and head tracking. Stateless transforms live on the rules
# layer; this class carries the smoothed runtime state plus angular-velocity
# bookkeeping for network export.
#
# Pose state is read by LocalController.reconcile (facing snap, IK lock reset,
# lower-body-lag reset, post-replay re-apply) and by SkaterController to seed
# the upper-body angular-velocity tracker — kept public so those callsites
# stay terse.

const State = SkaterStateMachine.State

# ── Runtime State ─────────────────────────────────────────────────────────────
var facing: Vector2 = Vector2.DOWN
var upper_body_angle: float = 0.0
# Reach lean, split by axis: pitch (rotation.x) + roll (rotation.z). The lean
# points TOWARD the blade's reach direction, not just forward — see
# compute_upper_body_lean_target. Because the blade IK solves in the leaned
# upper-body frame, leaning toward the target genuinely extends world reach
# (the shoulder displaces toward it and the hands drop closer to the ice,
# lengthening the stick's horizontal footprint) — the same mechanism a real
# player uses.
var upper_body_lean: float = 0.0
var upper_body_lean_roll: float = 0.0
var velocity_lean_x: float = 0.0
var lower_body_lag: float = 0.0
var head_angle: float = 0.0
var _head_rate: float = 0.0
var head_nod: float = 0.0
var _head_nod_rate: float = 0.0
# Upper-body twist follow-through (secondary motion): a damped spring trails the
# tracked twist so the shoulders whip through a fast cut and settle, instead of
# tracking rigidly. Converges to the tracked angle at steady state (adds nothing
# to a settled pose), so the cosmetic-rig dirty-gate still skips it. Advanced
# only on the local-sim path (apply_upper_body) like the rest of that pass.
var _twist_follow: float = 0.0
var _twist_follow_vel: float = 0.0

# ── Angular-Velocity Tracking ─────────────────────────────────────────────────
var facing_angular_velocity: float = 0.0
var upper_body_angular_velocity: float = 0.0
var _prev_facing_angle: float = 0.0
var _prev_upper_body_angle: float = 0.0
# The rate apply_facing turned the body at last tick (rad/s, Vector2.angle_to's
# sense — the wire's bearing rate negated): FacingRules.turn_rate's state.
var facing_turn_rate: float = 0.0

# ── References ────────────────────────────────────────────────────────────────
var _skater: Skater = null
var _sm: SkaterStateMachine = null
var _aiming: SkaterAimingBehavior = null
var _controller: SkaterController = null  # tunables live as @export on the controller
# Read-only source of the gait's lower-body yaw channels (hockey stop, hip
# alignment, shot hip coil). The trunk texture goes straight onto the torso
# bones (Skater.set_trunk_texture), not through this coordinator — see the
# invariant in _apply_lean; this class stays the single writer of the
# upper/lower-body NODE lean.
var _skating: SkaterSkatingCoordinator = null

func setup(skater: Skater, sm: SkaterStateMachine, aiming: SkaterAimingBehavior,
		controller: SkaterController, skating: SkaterSkatingCoordinator) -> void:
	_skater = skater
	_sm = sm
	_aiming = aiming
	_controller = controller
	_skating = skating
	_prev_facing_angle = atan2(facing.x, facing.y)
	_prev_upper_body_angle = skater.get_upper_body_rotation()

# ── Per-Tick Application ──────────────────────────────────────────────────────
func apply_velocity_lean(delta: float) -> void:
	var leg_scale: float = _skating.leg_scale if _skating != null else 1.0
	var target: float = compute_velocity_lean_target(
			_skater.velocity, _skater.global_transform.basis,
			_controller.gait_full_speed * leg_scale,
			_controller.velocity_lean_forward_max_deg,
			_controller.velocity_lean_back_max_deg)
	velocity_lean_x = lerpf(velocity_lean_x, target, _controller.velocity_lean_speed * delta)


# The lean is INTO travel: forward skating folds the trunk forward (the
# skating posture — negative rotation.x pitches the torso top toward local
# −Z), backward skating sits slightly back. Pitch only, radians: sideways
# travel is not a lean — a strafe doesn't bank, and the facing leads travel
# through a carve, so a roll toward body-frame lateral velocity would lean OUT
# of the turn. The turn's bank is the balance lean's (SkaterSpineRig).
static func compute_velocity_lean_target(
		world_velocity: Vector3, body_basis: Basis, full_speed: float,
		fwd_lean_max_deg: float, back_lean_max_deg: float) -> float:
	if full_speed <= 0.0:
		return 0.0
	var local_vel: Vector3 = body_basis.inverse() * world_velocity
	# −Z is the body's forward axis, so negate for a "how forward" fraction.
	var fwd_t: float = clampf(-local_vel.z / full_speed, -1.0, 1.0)
	var pitch_max_deg: float = fwd_lean_max_deg if fwd_t >= 0.0 else back_lean_max_deg
	return -fwd_t * deg_to_rad(pitch_max_deg)


# Directional reach lean: the torso tips TOWARD the hand's reach direction
# (pitch AND roll), the way a real player leans into a poke or a wide dangle —
# a forward-only fold wastes the lean on side reaches.
# Magnitude ramps with reach fraction through engage_power (>1 keeps the
# torso quiet mid-ROM and commits the lean near the rim, where a real player
# actually leans). Returns Vector2(pitch = rotation.x, roll = rotation.z):
# negative rotation.x pitches the torso top toward local −Z (forward),
# negative rotation.z rolls it toward local +X — hence (dir.y, −dir.x).
static func compute_upper_body_lean_target(
		hand_local_xz: Vector2, shoulder_local_xz: Vector2,
		rom_max_reach: float, lean_max_deg: float, engage_power: float = 1.0) -> Vector2:
	var hand_vec: Vector2 = hand_local_xz - shoulder_local_xz
	var hand_reach: float = hand_vec.length()
	if hand_reach <= 0.01 or rom_max_reach <= 0.0:
		return Vector2.ZERO
	var reach_factor: float = clampf(hand_reach / rom_max_reach, 0.0, 1.0)
	var mag: float = deg_to_rad(lean_max_deg) * pow(reach_factor, maxf(engage_power, 0.01))
	var dir: Vector2 = hand_vec / hand_reach
	return Vector2(mag * dir.y, -mag * dir.x)


# The reach lean's cap toward the hand: the side cap out to either side, rising
# to the forward cap straight ahead. Ahead is the skater's facing, not the
# shoulders' — a backhand reach twists them toward the stick, and in their frame
# a hand out to the side reads as straight ahead. A one-handed reach ahead folds
# deep at the waist; one to the side leans over the hip.
func _reach_lean_max_deg(hand_vec: Vector2) -> float:
	var dir: Vector3 = Basis(Vector3.UP, _skater.upper_body.rotation.y) \
			* Vector3(hand_vec.x, 0.0, hand_vec.y)
	var ahead: float = maxf(-dir.z, 0.0) / maxf(dir.length(), 0.0001)
	return lerpf(_controller.upper_body_lean_max_deg,
			_controller.upper_body_lean_forward_max_deg, ahead * ahead)


# The torso's lean off the wire (remote, replay and goal-replay paths): the
# simulating machine's smoothed state, applied through the one torso writer.
# Must run BEFORE set_blade_position — the wire blade is local to the tilted
# frame.
func apply_wire_lean(state: SkaterNetworkState) -> void:
	adopt_wire_lean(state)
	_apply_lean()


# The reconcile's half: adopt the host's lean at the ack, and let the replay
# step it forward.
func adopt_wire_lean(state: SkaterNetworkState) -> void:
	upper_body_lean = state.torso_lean.x
	upper_body_lean_roll = state.torso_lean.y
	velocity_lean_x = state.posture_lean


# The frame's yaw is the tracked angle plus the follow spring's whip, and the
# yaw is what goes on the wire — so the reconcile history records both halves.
func record_twist(snap: PredictedState) -> void:
	snap.upper_body_rotation_y = _skater.get_upper_body_rotation()
	snap.twist_whip = angle_difference(upper_body_angle, snap.upper_body_rotation_y)
	snap.twist_follow = _twist_follow
	snap.twist_follow_vel = _twist_follow_vel


# The reconcile's half: put the frame on the host's yaw and rebuild the tracked
# angle and spring under it from this machine's record of the same instant.
# Taking the yaw as the tracked angle instead plants the whip in it. With no
# record, the spring settles on the host's yaw.
func adopt_wire_twist(frame_yaw: float, at_ack: PredictedState) -> void:
	if at_ack != null:
		upper_body_angle = frame_yaw - at_ack.twist_whip
		_twist_follow = at_ack.twist_follow
		_twist_follow_vel = at_ack.twist_follow_vel
	else:
		upper_body_angle = frame_yaw
		_twist_follow = frame_yaw
		_twist_follow_vel = 0.0
	_skater.set_upper_body_rotation(frame_yaw)


static func _is_slapper_charge(state: int) -> bool:
	return state == State.SLAPPER_CHARGE_WITH_PUCK \
			or state == State.SLAPPER_CHARGE_WITHOUT_PUCK \
			or state == State.ONE_TIMER_RETENTION


# Torso roll of the shot block, as a rotation.z: the chest leans onto the down
# knee, which the gait drops on the STICK side (so body and stick seal opposite
# halves of the lane). Negative rotation.z rolls the torso top toward local +X,
# where a righty's stick — and therefore his kneeling leg — is.
func _block_trunk_roll() -> float:
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	return -blade_side_sign * deg_to_rad(_controller.block_trunk_roll_deg)


# Single writer for the torso/leg lean rotations. Layers, in order: the reach
# lean (directional tip toward the blade — pitch + roll), the velocity lean
# (skating posture pitch + carve bank), and the per-stride trunk texture the
# gait computes (effort dig pitch + weight-shift sway roll — see
# SkaterSkatingCoordinator). The lower body banks fully with the carve but
# follows the forward pitch only fractionally, so the legs stay planted under
# the hips while the trunk folds forward over them.
func _apply_lean() -> void:
	# Body-check recoil: while staggered, the torso reels the way the hit shoved
	# it — further while rocked, easing down onto the stagger's reel as he comes
	# out of it — and out as the timer decays (same directional pitch/roll decomposition
	# as the reach lean). Runs on every path — local, bot, and remote, off the
	# replicated timer and direction — since _apply_lean is the single torso
	# writer both the live pass and apply_wire_lean go through.
	var recoil_pitch: float = 0.0
	var recoil_roll: float = 0.0
	var recoil_t: float = clampf(
			_controller.stagger_timer / maxf(_controller.stagger_max_seconds, 0.001), 0.0, 1.0)
	# Knockdown adds a torso fold on top of the whole-body fall tilt (the tilt
	# itself lives on MeshRoot — SkaterController._apply_knockdown_fall): a
	# reflexive curl while airborne that resolves to the ground-plane complement
	# as the body reaches the ice (KnockdownFallRules.fold_at), so the landed
	# torso lies IN the ice plane instead of curling through it or propping up
	# as a plank. It rides the SAME recoil direction (fall the way you were hit)
	# and the same replicated timer, layered on top of the stagger recoil, and
	# lets go as he comes up onto his knees.
	var kd_t: float = _controller.knockdown_getup_left()
	var lie: float = KnockdownFallRules.lie_share(kd_t)
	var mag: float = deg_to_rad(_controller.stagger_recoil_deg) * recoil_t \
			+ deg_to_rad(_controller.rocked_recoil_deg - _controller.stagger_recoil_deg) \
			* _controller.rocked_share()
	if lie > 0.0:
		mag += _controller.knockdown_fold_rad() * lie
	if mag > 0.0:
		var d: Vector2 = _controller.stagger_recoil_dir
		recoil_pitch = mag * d.y
		recoil_roll = -mag * d.x
	# Standing up off the knee, the trunk takes up the forward stagger he finds
	# his legs in (knockdown_getup_stagger_seconds), so that stagger starts from
	# the lean it already has.
	if kd_t > 0.0:
		recoil_pitch -= deg_to_rad(_controller.stagger_recoil_deg) \
				* (1.0 - KnockdownFallRules.stand_hold(kd_t)) \
				* _controller.knockdown_getup_stagger_seconds \
				/ maxf(_controller.stagger_max_seconds, 0.001)
	# The gait's per-stride trunk texture is deliberately NOT folded in here: the
	# blade markers hang under upper_body, so anything added to its rotation moves
	# the blade's WORLD position (pickup / poke geometry, which must match across
	# machines for reconcile). The gait runs at render rate now, so letting its
	# stride pitch reach this frame would make the blade world depend on frame
	# rate. Reach + velocity lean stay (both physics-rate, deterministic); the
	# stride texture instead lands on the cosmetic torso/helmet/shoulder BONES
	# via Skater.set_trunk_texture — mesh-only, so the invariant holds.
	_skater.set_upper_body_lean(
			upper_body_lean + velocity_lean_x + recoil_pitch,
			upper_body_lean_roll + recoil_roll, velocity_lean_x)
	_skater.set_lower_body_lean(velocity_lean_x * _controller.lower_body_pitch_follow)

# Through a finish the hips turn onto the shot line as far as the torso drove
# the shot (SkaterStateMachine.finish_facing_dir) and come back to the cursor
# over the same tail as the torso and blade (ShotMechanics.follow_through_aim),
# so they hold the finish with them rather than chase the live cursor.
func _finish_facing_dir(cursor_dir: Vector2) -> Vector2:
	var dir_world: Vector3 = _sm.finish_facing_dir
	if dir_world.length_squared() <= 0.0001:
		dir_world = _sm.shot_dir
	if dir_world.length_squared() <= 0.0001 and _sm.follow_through_is_slapper:
		dir_world = Vector3(_sm.locked_slapper_dir.x, 0.0, _sm.locked_slapper_dir.y)
	var total: float = maxf(_sm.follow_through_duration_total, 0.001)
	var t: float = clampf(1.0 - _sm.follow_through_timer / total, 0.0, 1.0)
	var aim: Vector3 = ShotMechanics.follow_through_aim(dir_world,
			Vector3(cursor_dir.x, 0.0, cursor_dir.y), t, _controller.follow_through_return_frac)
	if aim.length_squared() < 0.0001:
		return cursor_dir
	return Vector2(aim.x, aim.z)


func apply_facing(input: InputState, delta: float) -> void:
	var s: SkaterStateMachine.State = _sm.get_state()
	# A downed body doesn't steer: facing freezes while the knockdown timer runs
	# (the fall pose tips about this frozen frame). Deterministic — the timer
	# decays in _apply_movement earlier this tick and is reconcile-snapped, so
	# every machine and replay freezes over the identical window.
	if not (s == State.WRISTER_AIM or s == State.SLAPPER_CHARGE_WITH_PUCK
			or s == State.SLAPPER_CHARGE_WITHOUT_PUCK or s == State.SHOT_BLOCKING
			or s == State.ONE_TIMER_RETENTION) and _controller.knockdown_timer <= 0.0:
		var prev_angle: float = _skater.rotation.y
		var mouse_world: Vector3 = input.mouse_world_pos
		var to_mouse: Vector2 = Vector2(
			mouse_world.x - _skater.global_position.x,
			mouse_world.z - _skater.global_position.z
		)
		if to_mouse.length() > _controller.move_deadzone:
			var cursor_dir: Vector2 = to_mouse.normalized()
			if s == State.FOLLOW_THROUGH:
				cursor_dir = _finish_facing_dir(cursor_dir)
			var lefty: bool = _skater.is_left_handed
			var rules: FacingRules.Config = _controller.facing_rules
			# A carrier's hips pivot where its blade stops on the backhand, and
			# yield to the puck before it stops on the forehand.
			FacingRules.solve(_facing_rule, facing, cursor_dir,
					Vector2(_skater.velocity.x, _skater.velocity.z), input.brake,
					_controller.stance_active, lefty,
					_controller.carry_facing_rules if _controller.has_puck else rules)
			var facing_target: Vector2 = _facing_rule.target
			var behind: bool = absf(facing.angle_to(cursor_dir)) \
					>= FacingRules.reach_edge(rules, facing, cursor_dir, lefty)
			var drag: float = _controller.facing_drag_speed_braking if input.brake else _controller.facing_drag_speed
			# Re-square hard through the follow-through: the coil left facing stale
			# at the wind-up cursor, and a lazy drag can't square it to the shot
			# line in a soft wrister's finish, so the blade handoff snaps to the
			# wrong side (ROM-clamped to the stale facing) before reaching the
			# cursor. See follow_through_facing_recover_speed.
			if s == State.FOLLOW_THROUGH:
				drag = maxf(drag, _controller.follow_through_facing_recover_speed)
			# Board shield: a carrier working the wall squares up ALONG it and
			# protects the puck rather than facing into it. Gated to carrying —
			# digging a loose puck out of the corner keeps full facing freedom,
			# because there's nothing to shield. Pure in the skater's position and
			# the cursor, so it re-derives identically through reconcile replay.
			if _controller.has_puck:
				facing_target = BoardPlayRules.board_shield_facing(
						facing_target,
						BoardPlayRules.board_proximity(
								Vector2(_skater.global_position.x, _skater.global_position.z),
								_controller.board_shield_probe),
						deg_to_rad(_controller.board_shield_max_deg))
			var turned: Vector2
			if behind or absf(facing.angle_to(facing_target)) \
					>= FacingRules.reach_edge(rules, facing, facing_target, lefty):
				# Turning round to a cursor or a target behind, standing or moving: a
				# chord lerp toward a near-opposed vector barely moves, so turn by angle.
				turned = facing.rotated(FacingRules.turn_round_angle(
						facing, facing_target, cursor_dir) * minf(drag * delta, 1.0))
			else:
				turned = facing.lerp(facing_target, drag * delta).normalized()
			if _controller.has_puck:
				turned = FacingRules.yield_on_forehand(turned, cursor_dir, lefty,
						_controller.carry_facing_rules)
			_turn_toward(turned, delta)
		else:
			facing_turn_rate = 0.0
		_skater.set_facing(facing)
		var turn_delta: float = angle_difference(prev_angle, _skater.rotation.y)
		lower_body_lag = clampf(
			lower_body_lag - turn_delta,
			-deg_to_rad(_controller.lower_body_lag_max_deg),
			deg_to_rad(_controller.lower_body_lag_max_deg))
	elif _is_slapper_charge(s) and _controller.knockdown_timer <= 0.0:
		_turn_to_slapper_stance(delta)
	else:
		facing_turn_rate = 0.0

	apply_lower_body_yaw(delta)


# A slapshot is struck side-on (SlapperRules.stance_facing): the hips pivot from
# wherever the press found them to the stance for the locked line at a steady
# rate, under the wind-up every other turn obeys — never in one tick.
func _turn_to_slapper_stance(delta: float) -> void:
	var prev_angle: float = _skater.rotation.y
	var stance: Vector2 = _controller.slapper_stance_facing()
	var step: float = deg_to_rad(_controller.slapper_stance_turn_deg_s) * delta
	var turned: Vector2 = facing.rotated(clampf(facing.angle_to(stance), -step, step))
	_turn_toward(turned, delta)
	_skater.set_facing(facing)
	var turn_delta: float = angle_difference(prev_angle, _skater.rotation.y)
	lower_body_lag = clampf(
		lower_body_lag - turn_delta,
		-deg_to_rad(_controller.lower_body_lag_max_deg),
		deg_to_rad(_controller.lower_body_lag_max_deg))


# Turns facing toward where the rule put it this tick, at the rate the body can
# wind up to.
func _turn_toward(turned: Vector2, delta: float) -> void:
	if delta <= 0.0:
		facing = turned
		return
	facing_turn_rate = FacingRules.turn_rate(facing_turn_rate, facing.angle_to(turned) / delta,
			_controller.facing_turn_accel_max, delta)
	facing = facing.rotated(facing_turn_rate * delta)

# Where facing heads this tick (FacingRules); a caller-owned scratch.
var _facing_rule: FacingRules.Result = FacingRules.Result.new()


# Sole writer of the lower body's yaw. Decays the facing-driven turn lag and
# sums the gait's two published yaw channels onto it — the hockey-stop turn
# (legs across travel while the torso keeps facing the play) and the
# hip-to-travel alignment (legs striding along motion under a torso facing the
# cursor).
#
# Runs on EVERY path that poses the body, not just the live one: the faceoff
# skate-in and the prep freeze replace apply_facing entirely, and a path that
# skips this leaves the lower body frozen at the last yaw anyone published —
# which is how skaters used to arrive at the dot with their hips still turned
# down the line they skated in on, for the whole countdown.
# How much of the torso's forward tip the faceoff address has already claimed.
# The reach lean measures the hand's reach off the shoulder MARKER, and the
# address carries the hands forward with the chest it folds — so left alone the
# reach model reads that carry as a reach and leans the torso a second time for
# it. Two consequences, neither wanted: the fold comes out deeper than the one
# authored, and the blade IK is handed a pitched frame to solve the address in,
# where a dot laid out on the flat lands short.
func _address_share() -> float:
	if _skating == null or not _skater.is_faceoff_center:
		return 0.0
	return _skating.faceoff_blend


func apply_lower_body_yaw(delta: float) -> void:
	lower_body_lag = lerpf(lower_body_lag, 0.0, _controller.lower_body_lag_speed * delta)
	var lag_share: float = lower_body_lag
	var gait_yaw: float = 0.0
	if _skating != null:
		gait_yaw = _skating.stop_yaw_offset + _skating.travel_align_yaw \
				+ _skating.shot_hip_yaw
		# During a pivot the hold IS the turn lag: the facing-driven lag pump
		# tracks the same rotation on the same node with its own decay clock,
		# and the sum of the two wobbles. The hold's authority fades the
		# generic lag out; it returns as the pivot releases.
		lag_share *= 1.0 - _skating.pivot_hold
	_skater.set_lower_body_lag(lag_share + gait_yaw)


# The torso twist off the hips that squares the shoulders to `world_point`,
# clamped to the twist limit; 0 for a point on top of the body.
func _twist_toward(world_point: Vector3) -> float:
	var to_point: Vector3 = world_point - _skater.global_position
	to_point.y = 0.0
	if to_point.length() <= 0.01:
		return 0.0
	var local_dir: Vector3 = _skater.global_transform.basis.inverse() * to_point.normalized()
	var max_twist: float = deg_to_rad(_controller.upper_body_max_twist_deg)
	return clampf(-atan2(local_dir.x, -local_dir.z) * _controller.upper_body_twist_ratio,
			-max_twist, max_twist)


func apply_upper_body(delta: float) -> void:
	if _sm.get_state() == State.SHOT_BLOCKING:
		# Chest tips forward AND onto the down knee — the weight sits over the
		# kneeling leg, off the one extended along the ice (the gait solves that
		# drop) — and the shoulders square to the snapped facing (the block faces
		# the shooter dead-on), both eased from whatever pose the block began in.
		# The block blade pose solves its ice height through
		# blade_y_lean_corrected, so the stick stays flat on the ice under the
		# pitching torso.
		var block_ease: float = minf(_controller.block_pose_blend_speed * delta, 1.0)
		upper_body_lean = lerpf(upper_body_lean,
				-deg_to_rad(_controller.block_trunk_pitch_deg), block_ease)
		upper_body_lean_roll = lerpf(upper_body_lean_roll, _block_trunk_roll(), block_ease)
		upper_body_angle = lerp_angle(upper_body_angle, 0.0, block_ease)
		_twist_follow = upper_body_angle
		_twist_follow_vel = 0.0
		_skater.set_upper_body_rotation(upper_body_angle)
		_apply_lean()
		return

	var charge_state: SkaterStateMachine.State = _sm.get_state()
	# ONE_TIMER_RETENTION rides this branch too: the wind-up charge timer is
	# frozen through the hold, so the coil simply holds at its apex — loaded and
	# still — instead of unwinding to the generic tracking pose for a beat.
	if _is_slapper_charge(charge_state):
		# The shoulders ride the open hips — the stance already points the top
		# hand's shoulder down the shot line — and coil back toward the stick side
		# as the wind-up fills.
		var wind_up_eased: float = sqrt(_controller.slapper_wind_up_t())
		var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
		var coil: float = -blade_side_sign * deg_to_rad(_controller.slapper_wind_up_twist_deg) * wind_up_eased
		upper_body_angle = lerp_angle(upper_body_angle, coil, _controller.slapper_wind_up_lerp_speed * delta)
		_skater.set_upper_body_rotation(upper_body_angle)
		# Glued to the tracked angle, as through the follow-through: the exit
		# keeps the pose, so skating must find the spring settled on it.
		_twist_follow = upper_body_angle
		_twist_follow_vel = 0.0
		# The wind-up's hands are authored, not reached for, so there is no reach
		# lean; the posture under the coil — the
		# skating lean, a stagger's reel — carries on as in every other state.
		var settle: float = minf(_controller.upper_body_lean_return_speed * delta, 1.0)
		upper_body_lean = lerpf(upper_body_lean, 0.0, settle)
		upper_body_lean_roll = lerpf(upper_body_lean_roll, 0.0, settle)
		_apply_lean()
		return

	if charge_state == State.FOLLOW_THROUGH:
		# Rotate the shoulders THROUGH the shot: the torso squares to the shot
		# line and uncoils past it (opposite sign to the wind-up coil — the back
		# shoulder comes through) on the blade's envelope, so the body snaps
		# through the release, holds the finish and relaxes out of it — a
		# slapper's shoulders come through over its downswing. The
		# trunk also drives forward over the front foot. Both targets decay to
		# the neutral aim pose by the end of the timer, handing the generic
		# blade-tracking branch a torso it can pick up without a pop. Whiffed
		# wristers (no shot_dir) fall through to blade tracking. The shoulders
		# square to the line the stick drove (SkaterStateMachine.finish_stick_dir),
		# which is the shot line only when the torso drove the shot.
		var dir_world: Vector3 = _sm.finish_stick_dir
		if dir_world.length_squared() <= 0.0001:
			dir_world = _sm.shot_dir
		if dir_world.length_squared() <= 0.0001 and _sm.follow_through_is_slapper:
			dir_world = Vector3(_sm.locked_slapper_dir.x, 0.0, _sm.locked_slapper_dir.y)
		if dir_world.length_squared() > 0.0001:
			var total: float = maxf(_sm.follow_through_duration_total, 0.001)
			var t: float = clampf(1.0 - _sm.follow_through_timer / total, 0.0, 1.0)
			var attack_s: float = _controller.slapper_downswing_time \
					if _sm.follow_through_is_slapper else _controller.whip_attack_time
			var env: float = SkaterShotPoseCoordinator.finish_envelope(t, total, attack_s,
					_controller.wrister_whip_release_frac) * _sm.follow_through_power
			# Ease the finish aim from the shot line back to the live cursor over
			# the tail (follow_through_return_frac), so the shoulders end squared
			# to where the mouse now is and the generic tracker picks the torso up
			# without a re-rotate. Meat of the timer keeps the shot-line uncoil.
			var cursor_dir: Vector3 = _controller._current_aim_world - _skater.global_position
			var aim_world: Vector3 = ShotMechanics.follow_through_aim(
					dir_world, cursor_dir, t, _controller.follow_through_return_frac)
			if aim_world.length_squared() > 0.0001:
				dir_world = aim_world
			var shot_local: Vector3 = _skater.global_transform.basis.inverse() * dir_world
			var shot_angle: float = atan2(shot_local.x, -shot_local.z)
			var ft_max_twist: float = deg_to_rad(_controller.upper_body_max_twist_deg)
			var ft_aim: float = clampf(
					-shot_angle * _controller.upper_body_twist_ratio, -ft_max_twist, ft_max_twist)
			var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
			var through_deg: float = _controller.slapper_follow_through_twist_deg \
					if _sm.follow_through_is_slapper else _controller.wrister_follow_through_twist_deg
			var through: float = blade_side_sign * deg_to_rad(through_deg) * env
			if not _sm.follow_through_is_slapper:
				# A backhand turns the other way, so it overshoots the other way.
				if _controller.last_release_hand == "BH":
					through = -through
				# The overshoot discharges WITH the release: driven off env, since a
				# lerp can't catch its ~40 ms attack. The unwind is rate-limited rather
				# than snapped, because the coil can sit well off the shot line.
				upper_body_angle = rotate_toward(upper_body_angle, ft_aim + through,
						deg_to_rad(_controller.wrister_release_unwind_speed_deg) * delta)
			else:
				upper_body_angle = lerp_angle(upper_body_angle, ft_aim + through,
						_controller.follow_through_twist_lerp_speed * delta)
			_skater.set_upper_body_rotation(upper_body_angle)
			# Keep the twist-follow spring glued to the tracked angle through the
			# FT (it isn't advanced on this branch): the handoff preserves the
			# pose instead of zeroing it (see SkaterController._transition_to_skating),
			# so the first skating tick must find the spring already settled or it
			# whips off the stale pre-shot value.
			_twist_follow = upper_body_angle
			_twist_follow_vel = 0.0
			# Trunk drives TOWARD the shot line (pitch + roll, same directional
			# decomposition as the reach lean) — a cross-body finish tips the
			# shoulders over the front foot toward the target, not just forward.
			var lean_dir3: Vector3 = _skater.upper_body.global_transform.basis.inverse() * dir_world
			var lean_dir := Vector2(lean_dir3.x, lean_dir3.z)
			var ft_lean_target := Vector2.ZERO
			if lean_dir.length_squared() > 0.0001:
				lean_dir = lean_dir.normalized()
				var ft_lean_mag: float = deg_to_rad(_controller.follow_through_lean_deg) * env
				ft_lean_target = Vector2(ft_lean_mag * lean_dir.y, -ft_lean_mag * lean_dir.x)
			upper_body_lean = lerpf(upper_body_lean, ft_lean_target.x,
					_controller.follow_through_twist_lerp_speed * delta)
			upper_body_lean_roll = lerpf(upper_body_lean_roll, ft_lean_target.y,
					_controller.follow_through_twist_lerp_speed * delta)
			_apply_lean()
			return

	var target_angle: float = 0.0
	var target_lean: Vector2 = Vector2.ZERO
	# Measured as the solve measures it (SkaterIKCoordinator._solve_top_hand): off
	# the shoulder the arm is drawn from, in the arm's level frame — less the
	# faceoff fold, which the address share zeroes this lean through anyway.
	var rot: Vector3 = _skater.upper_body.rotation
	var tilt: Basis = Basis.from_euler(Vector3(rot.x, 0.0, rot.z))
	var shoulder: Vector3 = tilt * SkaterSpineRig.shoulder_in_frame(
			_skater.shoulder.position, rot, 0.0, _skater.trunk_fold())
	var hand: Vector3 = tilt * _skater.top_hand.position
	var hand_vec := Vector2(hand.x - shoulder.x, hand.z - shoulder.z)
	var hand_reach: float = hand_vec.length()

	# Drive twist from the blade's world direction in the skater body frame.
	# Using skater-local (not upper-body-local) gives a stable target that
	# doesn't shrink as the body rotates: driving it from the HAND angle closes
	# a dampening feedback loop that caps steady-state rotation at ~43% of the
	# world angle. This way the body tracks 1:1 up to upper_body_max_twist_deg.
	# It never reads the hand: in close the hand sits over the shoulder, and a
	# twist gated on its reach squared the chest to a blade beside the hips.
	# FREEZE: the coil normally faces the blade (which tracks the cursor), but a
	# FROZEN blade can't lead the wind-up, so the shoulders turn from the puck
	# toward the CURSOR by the share of the shot the body can drive along it
	# (SkaterController.wrister_drive_share): squared on the aim when it can,
	# left on the puck when the shot goes somewhere the body cannot push it.
	target_angle = _twist_toward(_skater.upper_body_to_global(_skater.get_blade_position()))
	if _sm.get_state() == State.WRISTER_AIM:
		target_angle = lerp_angle(target_angle, _twist_toward(_controller._current_aim_world),
				_controller.wrister_drive_share() if _controller.has_puck else 1.0)
	# A wrist shot winds the torso up by the power it would release with, from
	# there to the full wind-up.
	if _sm.get_state() == State.WRISTER_AIM and _controller.has_puck:
		target_angle = lerp_angle(target_angle, _controller.wrister_load.wound_yaw,
				_controller.wrister_coil)

	if hand_reach > 0.01:
		# Measured against the rim in the hand's own direction, so the lean commits
		# at full reach whichever way the arm is extending.
		var rim_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
		target_lean = compute_upper_body_lean_target(
				Vector2(hand.x, hand.z),
				Vector2(shoulder.x, shoulder.z),
				TopHandIK.rim_reach(atan2(hand_vec.x, -hand_vec.y) * rim_side_sign,
						_controller.rom_forward_reach_max, _controller.rom_forehand_reach_max,
						_controller.rom_backhand_reach_max),
				_reach_lean_max_deg(hand_vec),
				_controller.upper_body_lean_engage_power) \
				* (1.0 - _address_share()) * _controller.reach_purpose()

	upper_body_angle = lerp_angle(upper_body_angle, target_angle, _controller.upper_body_return_speed * delta)
	upper_body_lean = lerpf(upper_body_lean, target_lean.x, _controller.upper_body_lean_return_speed * delta)
	upper_body_lean_roll = lerpf(upper_body_lean_roll, target_lean.y, _controller.upper_body_lean_return_speed * delta)
	# Follow-through: a damped spring trails the tracked twist so the shoulders
	# whip through a fast cut and settle. We RENDER the tracked angle plus the
	# spring's lag (whip in the direction of motion), but keep upper_body_angle
	# itself the rigidly-tracked value so the network angular-velocity export and
	# next-frame lerp are unaffected. Converges to zero lag at steady state.
	var tw_accel: float = _controller.upper_body_follow_stiffness * (upper_body_angle - _twist_follow) \
			- _controller.upper_body_follow_damping * _twist_follow_vel
	_twist_follow_vel += tw_accel * delta
	_twist_follow += _twist_follow_vel * delta
	var rendered_twist: float = upper_body_angle \
			+ (upper_body_angle - _twist_follow) * _controller.upper_body_follow_gain
	_skater.set_upper_body_rotation(rendered_twist)
	_apply_lean()

func apply_head_tracking(input: InputState, delta: float) -> void:
	apply_head_tracking_aim(input.mouse_world_pos, delta)

# Head tracking from a raw aim point rather than an InputState — used by the
# render-rate cosmetic pass (Skater.render_pose_update), which has no input
# frame, off the controller's last-seen aim world position. `aim_known` is false
# on a peer drawing someone else's skater, which has no cursor for it.
func apply_head_tracking_aim(aim_world: Vector3, delta: float, aim_known: bool = true) -> void:
	var target_angle: float = 0.0
	# A downed head lolls to neutral instead of tracking anything across the
	# ice (the spring carries it there and back smoothly).
	if _controller.knockdown_timer <= 0.0:
		var look: Vector3
		var has_look: bool = true
		var puck: Puck = _controller.puck
		var state: int = _skater.current_shot_state
		match HeadLookRules.target(SkaterStateMachine.state_aims_shot(state),
				SkaterStateMachine.state_has_puck(state), aim_known,
				puck != null and HeadLookRules.is_puck_in_play(puck.global_position)):
			HeadLookRules.Target.AIM:
				look = aim_world
			HeadLookRules.Target.PUCK:
				look = puck.global_position
			HeadLookRules.Target.NET:
				look = HeadLookRules.attacking_net(_skater.get_team_id())
			_:
				has_look = false
		if has_look:
			target_angle = HeadLookRules.yaw(_skater.upper_body_to_local(look), head_angle,
					deg_to_rad(_controller.head_track_max_deg))
	# On a spring rather than a lag, so the head starts after its target from rest.
	var omega: float = _controller.head_track_speed * EaseRules.OMEGA_PER_RATE
	var was: float = head_angle
	head_angle = EaseRules.critical_x(was, _head_rate, target_angle, omega, delta)
	_head_rate = EaseRules.critical_v(was, _head_rate, target_angle, omega, delta)
	var nod_target: float = _puck_nod() if _controller.knockdown_timer <= 0.0 else 0.0
	var nod_was: float = head_nod
	head_nod = EaseRules.critical_x(nod_was, _head_nod_rate, nod_target, omega * 0.5, delta)
	_head_nod_rate = EaseRules.critical_v(nod_was, _head_nod_rate, nod_target, omega * 0.5,
			delta)
	_skater.set_head_angle(head_angle, head_nod)


# How far a carrier's head nods down to the puck: the larger of the hands
# working it and it coming in tight, eased off by skating speed.
func _puck_nod() -> float:
	if not _controller.has_puck:
		return 0.0
	var c: SkaterController = _controller
	var hands: float = smoothstep(c.head_puck_hands_band.x, c.head_puck_hands_band.y,
			_skater.carry_hands_velocity.length())
	var to_puck: Vector3 = _skater.get_carry_target_global() - _skater.global_position
	var close: float = smoothstep(c.head_puck_close_band.x, c.head_puck_close_band.y,
			Vector2(to_puck.x, to_puck.z).length())
	var open_ice: float = smoothstep(c.head_puck_skate_band.x, c.head_puck_skate_band.y,
			Vector2(_skater.velocity.x, _skater.velocity.z).length())
	return deg_to_rad(c.head_puck_nod_deg) * maxf(hands, close) * (1.0 - open_ice)

# ── Angular Velocity Bookkeeping ──────────────────────────────────────────────
# Called at the end of _process_input on real (non-replay) frames so the
# network state carries C1-continuous facing / upper-body rotation. The
# upper-body rate is the FRAME yaw's (whip included), the angle it rides with.
func update_angular_velocities(delta: float) -> void:
	if delta <= 0.0:
		return
	var cur_fa: float = atan2(facing.x, facing.y)
	var frame_yaw: float = _skater.get_upper_body_rotation()
	facing_angular_velocity = angle_difference(_prev_facing_angle, cur_fa) / delta
	upper_body_angular_velocity = angle_difference(_prev_upper_body_angle, frame_yaw) / delta
	_prev_facing_angle = cur_fa
	_prev_upper_body_angle = frame_yaw

# ── Pose Resets ───────────────────────────────────────────────────────────────
# Used by the teleports and the spawn. Clears smoothed pose state so the next
# tick starts from a neutral torso/lean.
func reset_lean_and_lag() -> void:
	upper_body_angle = 0.0
	upper_body_lean = 0.0
	upper_body_lean_roll = 0.0
	velocity_lean_x = 0.0
	lower_body_lag = 0.0
	facing_turn_rate = 0.0
	_twist_follow = 0.0
	_twist_follow_vel = 0.0

class_name SkaterShotPoseCoordinator
extends RefCounted

# Owns the blade and top-hand pose during shot states: the slapper wind-up
# (charge with or without puck) and the post-release follow-through for both
# wrister and slapper. The aim/IK flow in SkaterIKCoordinator is bypassed for
# these states because the blade pose is choreographed, not player-aimed.
#
# All clamp helpers (net exclusion, goalie body / butterfly) and the small
# geometry utilities (blade_y_local, stick_horiz) live on SkaterIKCoordinator
# because they are also used by the per-tick IK pipeline.

const State = SkaterStateMachine.State

# Every pose in this file is AUTHORED — hand and blade placed from tunables
# rather than solved against each other — so nothing in the placement keeps them
# a stick-length apart, and the rendered shaft is exactly that distance
# (Skater.update_stick_mesh). The slapper finish drew 2.00 m of a 1.30 m stick at
# its peak with nothing in the way, and any obstacle clamp added its whole
# correction on top. So every pose here runs through `_ik.rigid_stick` twice:
# once on what it authored, once on what the clamps left. Where length has to
# come off, it comes off the REACH — see TopHandIK.enforce_rigid_stick.

# ── References ────────────────────────────────────────────────────────────────
var _skater: Skater = null
var _sm: SkaterStateMachine = null
var _aiming: SkaterAimingBehavior = null
var _ik: SkaterIKCoordinator = null
var _controller: SkaterController = null

func setup(skater: Skater, sm: SkaterStateMachine, aiming: SkaterAimingBehavior,
		ik: SkaterIKCoordinator, controller: SkaterController) -> void:
	_skater = skater
	_sm = sm
	_aiming = aiming
	_ik = ik
	_controller = controller


# ── Slapper Charge Pose ───────────────────────────────────────────────────────
# Authored, not aimed: the blade starts on the ice where the puck is struck
# (_contact_local) and rises to the wind-up apex out on the stick side
# (slapper_wind_up_blade_x/z, height slapper_wind_up_height) as the charge
# fills, while the top hand comes up and across the chest. The pose is the
# charge gauge, so it fills over the full charge time.
func apply_slapper_blade_position() -> void:
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	var wind_up_t: float = _controller.slapper_wind_up_t()
	# Full-charge tell: a small quiver at the apex (see slapper_full_quiver_m).
	# Phase runs off the charge timer past max — deterministic through reconcile
	# replay; remotes see it through the replicated hand/blade wire state like
	# the rest of the pose.
	var quiver: float = 0.0
	if wind_up_t >= 1.0:
		quiver = sin(_controller.slapper_overcharge_seconds()
				* TAU * _controller.slapper_full_quiver_hz) * _controller.slapper_full_quiver_m
	var pos: Vector3 = _wind_up_blade(wind_up_t)
	pos.y += quiver
	var hand_pos: Vector3 = _wind_up_hand(wind_up_t)
	hand_pos.y += quiver * 0.5
	var rigid: TopHandIK.Result = _ik.rigid_stick(hand_pos, pos, blade_side_sign)
	hand_pos = rigid.hand
	pos = _skater.clamp_blade_to_walls(rigid.blade)
	var blade_world: Vector3 = _skater.upper_body_to_global(pos)
	var clamped_heel: Vector3 = blade_world
	if _controller.has_puck:
		clamped_heel = _ik.clamp_blade_from_goalies(clamped_heel)
	clamped_heel += _ik.resolve_blade_against_net(clamped_heel).offset
	if clamped_heel != blade_world:
		pos = _skater.upper_body_to_local(clamped_heel)
	rigid = _ik.rigid_stick(hand_pos, pos, blade_side_sign)
	_skater.set_top_hand_position(rigid.hand)
	_skater.set_blade_position(rigid.blade)


# Where the blade meets the puck, upper-body-local, on the ice: the pinned puck
# while there is one, else the strike spot. Both are fixed in the hips' frame,
# so this turns against the shoulders as they coil.
func _contact_local() -> Vector3:
	var spot: Vector2 = _skater.slapshot_pin_local() if _skater.is_slapshot_pinning() \
			else _controller.slapper_strike_local()
	var local: Vector3 = _skater.upper_body_to_local(_skater.to_global(Vector3(spot.x, 0.0, spot.y)))
	local.y = _ik.blade_y_lean_corrected(local.x, local.z)
	return local


# The blade `wind_up_t` (0..1) of the way through the backswing: the XZ eases
# out front-loaded (sqrt, matching the torso coil) and the height climbs with
# the raw charge, so the swing snaps into motion and creeps to its apex at max.
func _wind_up_blade(wind_up_t: float) -> Vector3:
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	var eased: float = sqrt(wind_up_t)
	var contact: Vector3 = _contact_local()
	var apex := Vector3(
			_skater.shoulder.position.x + blade_side_sign * _controller.slapper_wind_up_blade_x,
			_controller.slapper_wind_up_height,
			_skater.shoulder.position.z + _controller.slapper_wind_up_blade_z)
	return Vector3(
			lerpf(contact.x, apex.x, eased),
			lerpf(contact.y, apex.y, wind_up_t),
			lerpf(contact.z, apex.z, eased))


func _wind_up_hand(wind_up_t: float) -> Vector3:
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	var eased: float = sqrt(wind_up_t)
	return Vector3(
			_skater.shoulder.position.x + blade_side_sign * _controller.slapper_wind_up_hand_inward * eased,
			_controller.hand_rest_y + _controller.slapper_wind_up_hand_up * eased,
			_skater.shoulder.position.z + (_controller.slapper_wind_up_hand_back
				- _controller.slapper_wind_up_hand_forward) * eased)

# ── Shot-Block Pose ───────────────────────────────────────────────────────────
# Choreographed "stick down" block: the blade lies flat on the ice extended
# forward (toward the shooter the stance snapped to on entry) and slightly to
# the stick side, with the top hand dropped low and pushed forward so the shaft
# lies across the lane. Authored in upper-body-local space like the slapper
# pose; the torso stays yaw-locked at the snapped facing for the duration
# (SkaterPoseCoordinator's block branch only pitches the chest over the knees
# — blade_y_lean_corrected re-lands the blade on the ice under that pitch), so
# the pose holds steady relative to the snapped facing.
func apply_block_blade_position() -> void:
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	var blade_x: float = _skater.shoulder.position.x + blade_side_sign * _controller.block_blade_x
	var blade_z: float = _skater.shoulder.position.z - _controller.block_blade_reach
	var blade_y: float = _ik.blade_y_lean_corrected(blade_x, blade_z)
	var blade_local := Vector3(blade_x, blade_y, blade_z)
	var hand_pos := Vector3(
			_skater.shoulder.position.x + blade_side_sign * _controller.block_hand_x,
			_controller.block_hand_y,
			_skater.shoulder.position.z - _controller.block_hand_forward)
	var rigid: TopHandIK.Result = _ik.rigid_stick(hand_pos, blade_local, blade_side_sign)
	hand_pos = rigid.hand
	blade_local = _skater.clamp_blade_to_walls(rigid.blade)
	rigid = _ik.rigid_stick(hand_pos, blade_local, blade_side_sign)
	_skater.set_top_hand_position(rigid.hand)
	_skater.set_blade_position(rigid.blade)

# Seconds the celebration's raised stick eases in and back out over.
const CELEBRATION_EASE_S: float = 0.25

# ── Goal Celebration Pose ─────────────────────────────────────────────────────
# Cosmetic raised-stick celebration for the scorer: top hand punches up with
# the stick held overhead (blade above the hand, tilted so the shaft never
# goes dead vertical — the stick/blade look_at needs a horizontal component),
# off hand pumps up on the free side. t runs [0,1] across the celebration
# window; the pose eases in from the stick the tick placed over its first
# CELEBRATION_EASE_S and back out to it over its last, holding a gentle bob
# between. Applied AFTER the tick's normal hand/blade placement, which it
# blends from; runs only on the scorer's own machine and rides the hand/blade
# wire state to everyone else like every other pose. `elapsed` and `left` are
# seconds into and remaining of the window.
func apply_celebration_pose(t: float, elapsed: float, left: float) -> void:
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	var ramp: float = smoothstep(0.0, CELEBRATION_EASE_S, elapsed) \
			* smoothstep(0.0, CELEBRATION_EASE_S, left)
	var bob: float = sin(t * TAU * 1.5) * 0.03 * ramp
	var hand_pos := Vector3(
			_skater.shoulder.position.x,
			lerpf(_controller.hand_rest_y, _controller.celebration_hand_y, ramp) + bob,
			_skater.shoulder.position.z - 0.10)
	var blade_pos := Vector3(
			_skater.shoulder.position.x + blade_side_sign * 0.18,
			hand_pos.y + _controller.celebration_stick_rise * ramp,
			_skater.shoulder.position.z - 0.28)
	# The rigid pass reads the same here as anywhere, and it is why the raised
	# stick survives it: this pose holds the blade well inside a stick-length of
	# the hand, so the correction is inert until a board clamp actually moves the
	# blade — and then it slides the hand rather than redrawing the arm from
	# scratch, which is what keeps the stick overhead where the celebration wants it.
	hand_pos = _skater.get_top_hand_position().lerp(hand_pos, ramp)
	blade_pos = _skater.get_blade_position().lerp(blade_pos, ramp)
	var rigid: TopHandIK.Result = _ik.rigid_stick(hand_pos, blade_pos, blade_side_sign)
	hand_pos = rigid.hand
	blade_pos = _skater.clamp_blade_to_walls(rigid.blade)
	rigid = _ik.rigid_stick(hand_pos, blade_pos, blade_side_sign)
	_skater.set_top_hand_position(rigid.hand)
	_skater.set_blade_position(rigid.blade)
	# Off hand: a fist pump on the free side, taken from the shaft by the same
	# ramp (SkaterIKCoordinator.update_bottom_hand).
	_ik.hold_free_hand(Vector3(
			_skater.bottom_shoulder.position.x,
			_controller.celebration_hand_y + bob * 1.4,
			_skater.bottom_shoulder.position.z - 0.12), ramp)


# ── Wrister Follow-Through ────────────────────────────────────────────────────
# The release swing continued: the blade sweeps from wherever the release left
# it onto the shot line while the stick carries FORWARD along that line and
# climbs to a high finish pointed at the target, then settles back to the ice
# by the end of the timer (a clean handoff to the aim IK). The forward carry
# (wrister_follow_through_reach) is what makes the finish read as the player
# reaching THROUGH the shot rather than the blade bobbing up and down over the
# release spot — a genuine continuation, not a canned pump. Reach and heights
# ride finish_envelope, scaled by follow_through_power so a full-charge wrister
# finishes extended and high while a snap pass barely flicks. The blade stays a rigid stick_length
# from the top hand (the horizontal reach re-solves as the blade climbs), so
# the finish reads as the stick swinging up about the hands rather than the
# shaft stretching.
func apply_wrister_follow_through() -> void:
	var total: float = maxf(_sm.follow_through_duration_total, 0.001)
	var t: float = clampf(1.0 - _sm.follow_through_timer / total, 0.0, 1.0)
	# Aim axis (world XZ): the shot line, eased back to the LIVE cursor over the
	# tail (follow_through_return_frac) so the finish hands off to blade-tracking
	# without a re-rotate. Whiffed releases (shot_dir zero) return ZERO here.
	var cursor_dir: Vector3 = _controller._current_aim_world - _skater.global_position
	var aim_world: Vector3 = ShotMechanics.follow_through_aim(
			_sm.shot_dir, cursor_dir, t, _controller.follow_through_return_frac)
	var stick_line: Vector3 = _sm.finish_stick_dir
	if stick_line.length_squared() <= 0.0001:
		stick_line = _sm.shot_dir
	var stick_world: Vector3 = ShotMechanics.follow_through_aim(
			stick_line, cursor_dir, t, _controller.follow_through_return_frac)
	_apply_wrister_whip(t, aim_world, stick_world)

# Blade whip for the frozen wrister (coil → instant release → blade replays the
# shot). ARM-CONTROLLED, same geometry as the tracked follow-through: the hand
# sits near the shoulder plus a carry along the shot line, and the blade is one
# stick-length beyond it along `stick_world`, the finish line
# (SkaterStateMachine.finish_stick_dir): the shot line when the torso drove the
# shot, where the puck sat when only the arms pushed it. So a loaded shot's blade
# extends along the shot vector FROM THE BODY — never radially outward — and an
# unloaded one pushes the stick through the puck rather than swinging it round
# the body; the arm stays short (= the carry) so it can't stretch. The
# frozen-specific parts: the aim points straight down the shot line from t=0 (no
# coiled-back sweep, no retracted-origin bridge) and the reach rides an
# attack-hold-release envelope, so the blade SNAPS to the extended finish, HOLDS
# it, then relaxes — the explosive discharge, committed.
func _apply_wrister_whip(t: float, aim_world: Vector3, stick_world: Vector3) -> void:
	var env: float = finish_envelope(t, _sm.follow_through_duration_total,
			_controller.whip_attack_time, _controller.wrister_whip_release_frac) \
			* _sm.follow_through_power
	var axis: Vector3 = aim_world
	if axis.length_squared() < 0.0001:
		axis = -_skater.global_transform.basis.z  # whiff: skate-forward, never radial
		axis.y = 0.0
	var upper_basis: Basis = _skater.upper_body.global_transform.basis
	var local_dir: Vector3 = ShotMechanics.whip_local_dir(axis, upper_basis)
	if local_dir.length_squared() < 0.0001:
		return
	var stick_dir: Vector3 = ShotMechanics.whip_local_dir(stick_world, upper_basis)
	if stick_dir.length_squared() < 0.0001:
		stick_dir = local_dir
	# Hand near the shoulder + a carry along the shot, blade one stick-length
	# along the finish line at ice + lift. This is the shared finish shape — the
	# slapper's is the same pose reached a different way (see _place_finish).
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	var carry: float = env * _controller.wrister_follow_through_reach
	var hand_pos: Vector3 = _skater.shoulder.position + local_dir * carry
	hand_pos.y = _controller.hand_rest_y + env * _controller.wrister_follow_through_hand_y
	var probe: Vector3 = hand_pos + stick_dir * _ik.stick_horiz()
	var blade_y: float = _ik.blade_y_lean_corrected(probe.x, probe.z) \
			+ env * _controller.wrister_follow_through_blade_lift
	var drop: float = hand_pos.y - blade_y
	var stick: float = _ik.solve_stick_length()
	var horiz: float = sqrt(maxf(stick * stick - drop * drop, 0.0001))
	var blade_pos: Vector3 = hand_pos + stick_dir * horiz
	blade_pos.y = blade_y
	_place_finish(hand_pos, blade_pos, blade_side_sign)

# ── Slapper Follow-Through ────────────────────────────────────────────────────
# A real swing in two phases. Downswing (the first slapper_downswing_time of
# the timer): the blade falls from wherever the wind-up
# actually left it — re-derived from the charge timer so an early release
# starts from the half-coiled pose instead of popping to full wind-up — down to
# the contact point, accelerating like a swing under gravity, hands riding down
# from the wind-up grip. Finish (the rest): the blade releases through contact,
# arcs out along the shot line and up into a high finish, hands rising with it,
# then settles back to the ice by the end of the timer for a clean handoff to
# the aim IK. The shot line is re-derived body-local each frame so the finish
# stays on target while the torso rotates through the swing.
func apply_slapper_follow_through() -> void:
	var total: float = maxf(_sm.follow_through_duration_total, 0.001)
	var t: float = clampf(1.0 - _sm.follow_through_timer / total, 0.0, 1.0)
	var blade_side_sign: float = -1.0 if _skater.is_left_handed else 1.0
	# Whiffed swings (shot never fired) follow the direction locked at charge.
	var dir_world: Vector3 = _sm.shot_dir
	if dir_world.length_squared() <= 0.0001:
		dir_world = Vector3(_sm.locked_slapper_dir.x, 0.0, _sm.locked_slapper_dir.y)
	# Shot line in the upper-body frame — the SAME primitive the wrister whip uses,
	# so both shots' finishes stay on the shot vector as the torso rotates through.
	var dir_local: Vector3 = ShotMechanics.whip_local_dir(
			dir_world, _skater.upper_body.global_transform.basis)
	if dir_local.length_squared() < 0.0001:
		dir_local = Vector3.FORWARD
	var contact: Vector3 = _contact_local()
	var hand_pos := Vector3(
			_skater.shoulder.position.x, _controller.hand_rest_y, _skater.shoulder.position.z)
	var blade_pos: Vector3
	var cf: float = clampf(_controller.slapper_downswing_time / total, 0.05, 0.9)
	if t < cf:
		# Downswing: quadratic ease-in — the blade accelerates into the ice from
		# wherever the wind-up was at release (an early release starts from the
		# half-coiled pose; the apex quiver is skipped — a ±2 cm start offset is
		# invisible in the downswing).
		var u: float = t / cf
		u *= u
		var wind_up_t: float = _controller.slapper_wind_up_t()
		blade_pos = _wind_up_blade(wind_up_t).lerp(contact, u)
		hand_pos = _wind_up_hand(wind_up_t).lerp(hand_pos, u)
	else:
		# Finish: out along the shot line and up into the high finish, held,
		# then settled — the wrister's envelope over what is left of the timer.
		var v: float = (t - cf) / (1.0 - cf)
		var env: float = finish_envelope(v, total * (1.0 - cf),
				_controller.whip_attack_time, _controller.wrister_whip_release_frac) \
				* _sm.follow_through_power
		var reach: float = env * _controller.slapper_follow_through_arc_dist
		blade_pos = contact + dir_local * reach
		blade_pos.y = _ik.blade_y_lean_corrected(blade_pos.x, blade_pos.z) \
				+ env * _controller.slapper_follow_through_height
		hand_pos.y += env * _controller.slapper_follow_through_hand_y
		var hand_follow: float = reach * _controller.slapper_follow_through_hand_follow
		hand_pos.x += dir_local.x * hand_follow
		hand_pos.z += dir_local.z * hand_follow
	_place_finish(hand_pos, blade_pos, blade_side_sign)


# Attack-hold-release, 0..1 at `t` (0..1 through a finish `span` seconds long):
# SNAPS up over `attack_s` seconds, HOLDS, then relaxes over the last
# `release_frac` of the span. Never a symmetric bell: it eases the stick out and
# straight back, never commits to the finish, and reads as delayed. The attack
# is seconds, not a share, so a longer finish holds longer rather than snapping
# slower, and eased at both ends, so the motion starts rather than appears.
static func finish_envelope(t: float, span: float, attack_s: float, release_frac: float) -> float:
	var attack: float = smoothstep(0.0, maxf(attack_s, 0.001), t * span)
	var release_start: float = 1.0 - clampf(release_frac, 0.0, 1.0)
	return attack * (1.0 - smoothstep(release_start, 1.0, t))


# ── The finish, shared ────────────────────────────────────────────────────────
# Both finishes end here: make the pose rigid, run it past the boards and the
# net, make it rigid again. They differ in how they GET here — the wrister's is a
# whip from the hands out along the shot line (rigid by construction, so the
# first pass is inert), the slapper's a swing whose blade arcs from the contact
# point and is NOT rigid — ungoverned it draws 2.00 m of a 1.30 m stick at the
# peak of the finish, so the arc has to cost the reach it cannot afford.
#
# The clamps sit BETWEEN the two passes on purpose. Correcting first means the
# boards and the net see the pose the body can actually hold, rather than one
# reaching through them; correcting again after means a clamp that moves the
# blade cannot buy its correction in stick length.
func _place_finish(hand_pos: Vector3, blade_pos: Vector3, blade_side_sign: float) -> void:
	var rigid: TopHandIK.Result = _ik.rigid_stick(hand_pos, blade_pos, blade_side_sign)
	var hand: Vector3 = rigid.hand
	var blade: Vector3 = _skater.clamp_blade_to_walls(rigid.blade)
	var heel: Vector3 = _skater.upper_body_to_global(blade)
	var offset: Vector3 = _ik.resolve_blade_against_net(heel).offset
	if offset != Vector3.ZERO:
		blade = _skater.upper_body_to_local(heel + offset)
	rigid = _ik.rigid_stick(hand, blade, blade_side_sign)
	_skater.set_top_hand_position(rigid.hand)
	_skater.set_blade_position(rigid.blade)

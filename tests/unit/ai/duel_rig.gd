extends RefCounted

# A skater's arms and stick as the controller places them, for the duel harness:
# the upper body's twist and reach lean (SkaterPoseCoordinator.apply_upper_body),
# and the blade resolved from the cursor through the top hand's range of motion,
# the carry's two hands and backhand stop, and the rest reach without a puck to
# reach for, then chased at the hands' speed (SkaterIKCoordinator
# .apply_blade_toward). Every number is read once off a set-up body (capture) and
# the solves are the controller's own pure ones (TopHandIK); what this leaves out
# is the skating lean, the trunk's fold and the boards' reach limit, and the
# carry's side is read off the blade (Skater._update_carry_contact strokes it).
# test_duel_rig_mirrors.gd holds the resolved target to the live coordinator.

# Per-skater state the controller keeps across ticks.
class Arm:
	var twist: float = 0.0          # UpperBody yaw off the facing, as tracked
	var follow: float = 0.0         # the twist's follow spring
	var follow_vel: float = 0.0
	var rendered: float = 0.0       # the twist the frame is set to
	var lean := Vector2.ZERO        # reach lean (pitch, roll)
	var heel := Vector3.ZERO        # the smoothed blade marker, world
	var heel_vel := Vector3.ZERO
	var prev_pos := Vector3.ZERO
	var started: bool = false
	var hand_local := Vector3.ZERO  # top hand, UpperBody-local
	var contact := Vector3.ZERO     # the blade's contact point, world (on the ice)
	var hand := Vector3.ZERO        # the top hand, world
	var speed_cap: float = INF      # under the hands' own (a tie's)


var shoulder: Vector3
var bottom_shoulder: Vector3
var ub_offset: Vector3
var blade_y: float
var blade_half: float
var carry_offset: float
var marker_y: float
var hand_rest_y: float
var hand_y_max: float
var stick_length: float
var rom_forehand_angle: float
var rom_backhand_angle: float
var rom_forward: float
var rom_forehand: float
var rom_backhand: float
var pivot_forward: float
var pivot_inward: float
var grip: float
var bottom_reach: float
var spacing: float
var bh_release: float
var blade_speed: float
var blade_accel: float
var twist_ratio: float
var max_twist: float
var twist_return: float
var follow_k: float
var follow_c: float
var follow_gain: float
var lean_side_max_deg: float
var lean_forward_max_deg: float
var lean_power: float
var lean_return: float
var purpose_lookahead: float
var purpose_near: float
var purpose_far: float
var rim: float

var _cfg := TopHandIK.Config.new()
var _ik := TopHandIK.Result.new()
var _scratch := TopHandIK.Result.new()


# The body `ctrl` drives, standing at rest.
static func capture(skater: Skater, ctrl: SkaterController) -> RefCounted:
	var rig: RefCounted = (load("res://tests/unit/ai/duel_rig.gd") as GDScript).new()
	var ik: SkaterIKCoordinator = ctrl._ik
	rig.shoulder = ik.arm_shoulder()
	rig.bottom_shoulder = skater.bottom_shoulder.position
	rig.ub_offset = skater.upper_body.position
	rig.blade_y = ctrl.blade_height - (GameRules.FACEOFF_SPAWN_HEIGHT + skater.upper_body.position.y)
	rig.blade_half = skater.blade_length * 0.5
	rig.carry_offset = skater.carry_blade_offset
	rig.marker_y = skater.shoulder.position.y
	rig.hand_rest_y = ctrl.hand_rest_y
	rig.hand_y_max = ctrl.hand_y_max
	rig.stick_length = ik.solve_stick_length()
	rig.rom_forehand_angle = deg_to_rad(ctrl.rom_forehand_angle_max_deg)
	rig.rom_backhand_angle = deg_to_rad(ctrl.rom_backhand_angle_max_deg)
	rig.rom_forward = ctrl.rom_forward_reach_max
	rig.rom_forehand = ctrl.rom_forehand_reach_max
	rig.rom_backhand = ctrl.rom_backhand_reach_max
	rig.pivot_forward = ctrl.hand_pivot_forward
	rig.pivot_inward = ctrl.hand_pivot_inward
	rig.grip = ik._grip_fraction()
	rig.bottom_reach = (skater.upper_arm_length + skater.forearm_length) \
			* skater.arm_working_extension + skater.shoulder_reach_m
	rig.spacing = ik._glove_spacing()
	rig.bh_release = deg_to_rad(ctrl.bh_release_angle_deg)
	rig.blade_speed = ctrl.max_blade_speed
	rig.blade_accel = ctrl.max_blade_accel
	rig.twist_ratio = ctrl.upper_body_twist_ratio
	rig.max_twist = deg_to_rad(ctrl.upper_body_max_twist_deg)
	rig.twist_return = ctrl.upper_body_return_speed
	rig.follow_k = ctrl.upper_body_follow_stiffness
	rig.follow_c = ctrl.upper_body_follow_damping
	rig.follow_gain = ctrl.upper_body_follow_gain
	rig.lean_side_max_deg = ctrl.upper_body_lean_max_deg
	rig.lean_forward_max_deg = ctrl.upper_body_lean_forward_max_deg
	rig.lean_power = ctrl.upper_body_lean_engage_power
	rig.lean_return = ctrl.upper_body_lean_return_speed
	rig.purpose_lookahead = ctrl.reach_purpose_lookahead_s
	rig.purpose_near = ctrl.reach_purpose_near_m
	rig.purpose_far = ctrl.reach_purpose_far_m
	rig.rim = ik.full_blade_reach()
	return rig


# One tick of the arm for a body at `pos` facing `facing`, reaching for `cursor`:
# the blade solved in the frame the twist left, chased at the hands' speed, then
# the twist and lean following it, the blade held where it is in the world.
# `held` freezes the blade marker at `held_offset` off the body (a wrister
# charge).
func step(arm: Arm, pos: Vector3, facing: Vector2, cursor: Vector3, carrying: bool,
		lefty: bool, puck_pos: Vector3, puck_vel: Vector3, held: bool,
		held_offset: Vector3, dt: float) -> void:
	var side: float = -1.0 if lefty else 1.0
	var body := Basis(Vector3.UP, atan2(-facing.x, -facing.y))
	var purpose: float = 1.0 if carrying else ReachPurposeRules.purpose(
			Vector2(pos.x, pos.z), rim, Vector2(puck_pos.x, puck_pos.z),
			Vector2(puck_vel.x, puck_vel.z), purpose_lookahead, purpose_near, purpose_far)
	var ub: Transform3D = ub_transform(arm, pos, body)
	var target: Vector3
	if held:
		target = Vector3(pos.x + held_offset.x, 0.0, pos.z + held_offset.z)
	else:
		target = resolve(arm, ub, body, pos, cursor, carrying, purpose, side,
				_carry_factor(arm, pos, body, side) if carrying else 0.0)
	if not arm.started:
		arm.heel = target
		arm.prev_pos = pos
		arm.started = true
	arm.heel += Vector3(pos.x - arm.prev_pos.x, 0.0, pos.z - arm.prev_pos.z)
	arm.prev_pos = pos
	if held:
		arm.heel = target
		arm.heel_vel = Vector3.ZERO
	else:
		_chase(arm, target, dt)
	var local: Vector3 = ub.affine_inverse() * arm.heel
	var ik: TopHandIK.Result = _solve(arm, Vector2(local.x, local.z), side, INF, false,
			carrying, purpose, ub, body, pos)
	arm.hand_local = ik.hand
	arm.hand = ub * ik.hand
	var shaft := Vector2(arm.heel.x - arm.hand.x, arm.heel.z - arm.hand.z)
	if shaft.length() < 0.001:
		shaft = facing
	shaft = shaft.normalized()
	arm.contact = Vector3(arm.heel.x + shaft.x * blade_half, 0.0, arm.heel.z + shaft.y * blade_half)
	_follow(arm, pos, body, cursor, held, purpose, side, dt)


func ub_transform(arm: Arm, pos: Vector3, body: Basis) -> Transform3D:
	var basis: Basis = body * Basis.from_euler(Vector3(arm.lean.x, arm.rendered, arm.lean.y))
	return Transform3D(basis, Vector3(pos.x, GameRules.FACEOFF_SPAWN_HEIGHT, pos.z)
			+ body * ub_offset)


# Which side of the cursor a carried puck sits, as Skater.get_carry_forehand_factor
# reads it: its forehand side while the blade is on the forehand, its backhand
# side once the blade has crossed.
func _carry_factor(arm: Arm, pos: Vector3, body: Basis, side: float) -> float:
	var rel: Vector3 = body.inverse() * (arm.heel - Vector3(pos.x, 0.0, pos.z))
	var forehand: float = 1.0 if rel.x * side >= 0.0 else -1.0
	return forehand * -side


# The cursor resolved to the blade marker it reaches for (world, on the ice).
# `carry_factor` is Skater.get_carry_forehand_factor.
func resolve(arm: Arm, ub: Transform3D, body: Basis, pos: Vector3, cursor: Vector3,
		carrying: bool, purpose: float, side: float, carry_factor: float) -> Vector3:
	var mouse := Vector3(cursor.x, 0.0, cursor.z)
	var shoulder_world: Vector3 = ub * shoulder
	shoulder_world.y = 0.0
	if (mouse - shoulder_world).length() < 0.01:
		return arm.heel
	var mouse_local: Vector3 = ub.affine_inverse() * mouse
	var aim := Vector2(mouse_local.x, mouse_local.z)
	_level_config(shoulder.y, INF)
	var to_target: Vector2 = aim - TopHandIK.hand_xz_for(Vector2(shoulder.x, shoulder.z), aim,
			blade_y, side, _cfg)
	if to_target.length() > 0.001:
		var stick_dir: Vector2 = to_target.normalized()
		aim -= stick_dir * blade_half
		if carrying:
			aim += Vector2(-stick_dir.y, stick_dir.x) * carry_factor * carry_offset
	var blade: Vector3 = _solve(arm, aim, side, INF, true, carrying, purpose, ub, body, pos).blade
	if carrying:
		blade = _solve(arm, Vector2(blade.x, blade.z), side, INF, true, carrying, purpose,
				ub, body, pos).blade
	var world: Vector3 = ub * blade
	world.y = 0.0
	return world


# SkaterIKCoordinator._solve_top_hand, in the arm's level frame.
func _solve(arm: Arm, desired: Vector2, side: float, max_reach: float, limits: bool,
		carrying: bool, purpose: float, ub: Transform3D, body: Basis,
		pos: Vector3) -> TopHandIK.Result:
	if limits and carrying:
		desired = _backhand_stop(arm, desired, side, ub, body, pos)
	var tilt: Basis = Basis.from_euler(Vector3(arm.lean.x, 0.0, arm.lean.y))
	var sh: Vector3 = tilt * shoulder
	var target: Vector3 = tilt * Vector3(desired.x, _blade_y_at(arm, desired), desired.y)
	_level_config(sh.y, max_reach)
	var target_xz := Vector2(target.x, target.z)
	if limits and carrying:
		_cfg.max_blade_reach = minf(max_reach, TopHandIK.two_hand_reach(sh, target_xz, side,
				_cfg, tilt * bottom_shoulder, grip, bottom_reach, spacing, _scratch))
	elif limits and purpose < 1.0:
		var held: float = TopHandIK.two_hand_reach(sh, target_xz, side, _cfg,
				tilt * bottom_shoulder, grip, bottom_reach, spacing, _scratch)
		if held != INF:
			TopHandIK.solve(sh, target_xz, side, _cfg, _scratch)
			var arm_reach: float = Vector2(_scratch.blade.x - sh.x, _scratch.blade.z - sh.z).length()
			_cfg.max_blade_reach = lerpf(held, arm_reach, purpose)
	TopHandIK.solve(sh, target_xz, side, _cfg, _ik)
	var untilt: Basis = tilt.transposed()
	_ik.hand = untilt * _ik.hand
	_ik.blade = untilt * _ik.blade
	return _ik


func _level_config(hang_y: float, max_reach: float) -> void:
	_cfg.stick_length = stick_length
	_cfg.blade_y = blade_y
	_cfg.hand_rest_y = hang_y - (marker_y - hand_rest_y)
	_cfg.hand_y_max = hang_y - (marker_y - hand_y_max)
	_cfg.rom_forehand_angle_max = rom_forehand_angle
	_cfg.rom_backhand_angle_max = rom_backhand_angle
	_cfg.rom_forward_reach_max = rom_forward
	_cfg.rom_forehand_reach_max = rom_forehand
	_cfg.rom_backhand_reach_max = rom_backhand
	_cfg.pivot_forward = pivot_forward
	_cfg.pivot_inward = pivot_inward
	_cfg.max_blade_reach = max_reach


# SkaterIKCoordinator.blade_y_lean_corrected under the reach lean.
func _blade_y_at(arm: Arm, xz: Vector2) -> float:
	var cp: float = maxf(cos(arm.lean.x), 0.001)
	var cr: float = maxf(cos(arm.lean.y), 0.001)
	return (blade_y + xz.y * sin(arm.lean.x) - xz.x * sin(arm.lean.y) * cp) / (cp * cr)


# SkaterIKCoordinator._carry_backhand_stop: the angle off the body past which the
# bottom hand lets go.
func _backhand_stop(arm: Arm, target: Vector2, side: float, ub: Transform3D, body: Basis,
		pos: Vector3) -> Vector2:
	var on_ice: Vector3 = ub * Vector3(target.x, _blade_y_at(arm, target), target.y)
	var rel: Vector3 = body.inverse() * (on_ice - Vector3(pos.x, 0.0, pos.z))
	var r: float = Vector2(rel.x, rel.z).length()
	if r < 0.01 or atan2(rel.x, -rel.z) * -side <= bh_release:
		return target
	var a: float = bh_release * -side
	var stopped: Vector3 = ub.affine_inverse() * (Vector3(pos.x, 0.0, pos.z)
			+ body * Vector3(sin(a) * r, rel.y, -cos(a) * r))
	return Vector2(stopped.x, stopped.z)


# The smoothed blade chasing its target relative to the body: the arrive law at
# the hands' speed and acceleration.
func _chase(arm: Arm, target: Vector3, dt: float) -> void:
	var step_v: Vector3 = target - arm.heel
	step_v.y = 0.0
	var dist: float = step_v.length()
	var desired := Vector3.ZERO
	if dist > 0.00001:
		desired = step_v * (minf(minf(blade_speed, arm.speed_cap),
				sqrt(2.0 * blade_accel * dist)) / dist)
	arm.heel_vel = arm.heel_vel.move_toward(desired, blade_accel * dt)
	var move: Vector3 = arm.heel_vel * dt
	if move.length() >= dist and arm.heel_vel.dot(step_v) >= 0.0:
		arm.heel = target
	else:
		arm.heel += move


# The upper body following the blade (SkaterPoseCoordinator.apply_upper_body):
# the twist toward it, the reach lean toward the hand's rim by the purpose, and
# the twist's follow spring, the blade's world point kept across the turn.
func _follow(arm: Arm, pos: Vector3, body: Basis, cursor: Vector3, held: bool,
		purpose: float, side: float, dt: float) -> void:
	var source: Vector3 = cursor if held else arm.heel
	var to_blade := Vector3(source.x - pos.x, 0.0, source.z - pos.z)
	var target_twist: float = 0.0
	if to_blade.length() > 0.01:
		var local_dir: Vector3 = body.inverse() * to_blade.normalized()
		target_twist = clampf(-atan2(local_dir.x, -local_dir.z) * twist_ratio,
				-max_twist, max_twist)
	var tilt: Basis = Basis.from_euler(Vector3(arm.lean.x, 0.0, arm.lean.y))
	var sh: Vector3 = tilt * shoulder
	var hand: Vector3 = tilt * arm.hand_local
	var sh_xz := Vector2(sh.x, sh.z)
	var pivot: Vector2 = TopHandIK.pivot_at(sh_xz, side, pivot_forward, pivot_inward)
	var hand_vec: Vector2 = Vector2(hand.x, hand.z) - pivot
	var target_lean := Vector2.ZERO
	if hand_vec.length() > 0.01:
		var dir: Vector3 = Basis(Vector3.UP, arm.rendered) * Vector3(hand_vec.x, 0.0, hand_vec.y)
		var ahead: float = maxf(-dir.z, 0.0) / maxf(dir.length(), 0.0001)
		target_lean = SkaterPoseCoordinator.compute_upper_body_lean_target(
				Vector2(hand.x, hand.z), pivot,
				TopHandIK.rim_exit_of(pivot - sh_xz, hand_vec.normalized(), side, rom_forward,
						rom_forehand, rom_backhand),
				lerpf(lean_side_max_deg, lean_forward_max_deg, ahead * ahead),
				lean_power) * purpose
	arm.twist = lerp_angle(arm.twist, target_twist, twist_return * dt)
	arm.lean = arm.lean.lerp(target_lean, lean_return * dt)
	var accel: float = follow_k * (arm.twist - arm.follow) - follow_c * arm.follow_vel
	arm.follow_vel += accel * dt
	arm.follow += arm.follow_vel * dt
	arm.rendered = arm.twist + (arm.twist - arm.follow) * follow_gain

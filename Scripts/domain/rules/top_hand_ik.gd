class_name TopHandIK

# Pure top-hand inverse kinematics. Given a desired blade target in
# upper-body-local XZ space and a fixed stick length, produces the hand and
# blade positions such that:
#
#   1. |blade.xz − hand.xz| == stick_horiz (fixed horizontal stick length).
#   2. The hand lies within an asymmetric range-of-motion envelope centered
#      on the shoulder — small reach on the forehand (cross-body) side, large
#      reach on the backhand (same side as the top hand) side.
#   3. When the target is reachable by extending the hand within ROM, the
#      blade lands exactly on the target. When unreachable, the blade falls
#      short along the aim line (radial from the hand through the target),
#      preserving aim direction but clipping distance.
#
# Blade-first feel: input is treated as a desired blade position, and the
# hand is solved as a consequence. No per-frame smoothing here — caller owns
# any smoothing if desired.
#
# All coordinates are in upper-body-local space.
#
# cfg keys (all floats):
#   stick_length              — rigid stick length (meters)
#   blade_y                   — fixed local Y for the blade
#   hand_rest_y               — fixed local Y for the hand (Phase 1)
#   rom_forehand_angle_max    — radians; angular ROM on forehand side (small)
#   rom_backhand_angle_max    — radians; angular ROM on backhand side (large)
#   rom_forehand_reach_max    — meters;  max hand displacement on forehand side
#   rom_backhand_reach_max    — meters;  max hand displacement on backhand side
#
# blade_side_sign: −1.0 for a left-handed shooter (blade lives on −X),
#                  +1.0 for a right-handed shooter (blade lives on +X).
# The shoulder is expected to live on the opposite (top-hand) side.
#
# Returns: { "hand": Vector3, "blade": Vector3 } in upper-body-local space.
static func solve(
		shoulder: Vector3,
		desired_blade_xz: Vector2,
		blade_side_sign: float,
		cfg: Dictionary) -> Dictionary:
	var stick_length: float = cfg.stick_length
	var blade_y: float = cfg.blade_y
	var hand_rest_y: float = cfg.hand_rest_y
	var vertical_drop: float = hand_rest_y - blade_y
	var stick_horiz_sq: float = stick_length * stick_length - vertical_drop * vertical_drop
	var stick_horiz: float = sqrt(maxf(stick_horiz_sq, 0.0001))

	var shoulder_xz := Vector2(shoulder.x, shoulder.z)
	var delta: Vector2 = desired_blade_xz - shoulder_xz
	var r: float = delta.length()

	# Aim direction from shoulder to target. Fallback to straight-forward
	# (−Z) when target coincides with the shoulder.
	var aim_dir: Vector2 = delta / r if r > 0.0001 else Vector2(0.0, -1.0)

	# Desired hand displacement from shoulder, before ROM clamp: if target is
	# farther from shoulder than stick_horiz, the hand must extend toward it
	# by (r − stick_horiz). Otherwise hand stays at the shoulder.
	var disp_len: float = maxf(0.0, r - stick_horiz)
	var disp: Vector2 = aim_dir * disp_len

	# Forehand-signed polar: angle > 0 always means "displaced toward forehand
	# side of body" regardless of handedness. The shoulder lives on the
	# top-hand (backhand) side, so for a lefty a +X displacement is toward
	# the backhand side → angle_to_forehand ends up negative.
	var angle_raw: float = atan2(disp.x, -disp.y)
	var angle_to_forehand: float = angle_raw * blade_side_sign
	var radius: float = disp.length()

	# Clamp angle asymmetrically: forehand side is tight, backhand is open.
	var fore_angle_max: float = cfg.rom_forehand_angle_max
	var back_angle_max: float = cfg.rom_backhand_angle_max
	angle_to_forehand = clampf(angle_to_forehand, -back_angle_max, fore_angle_max)

	# Max reach is asymmetric: cross-body forehand reach is limited by
	# anatomy, same-side backhand reach allows full arm extension. Small
	# linear blend across zero avoids a seam.
	var blend_band: float = deg_to_rad(5.0)
	var fore_reach: float = cfg.rom_forehand_reach_max
	var back_reach: float = cfg.rom_backhand_reach_max
	var max_reach: float
	if angle_to_forehand >= blend_band:
		max_reach = fore_reach
	elif angle_to_forehand <= -blend_band:
		max_reach = back_reach
	else:
		var t: float = (angle_to_forehand + blend_band) / (2.0 * blend_band)
		max_reach = lerpf(back_reach, fore_reach, t)
	radius = clampf(radius, 0.0, max_reach)

	# Back to Cartesian. world_angle undoes the forehand-sign flip.
	var world_angle: float = angle_to_forehand * blade_side_sign
	var hand_disp := Vector2(sin(world_angle) * radius, -cos(world_angle) * radius)
	var hand_xz: Vector2 = shoulder_xz + hand_disp

	# Blade sits exactly stick_horiz from the hand along the line pointing
	# at the original target — so when target is reachable, blade == target;
	# when target is beyond ROM, blade lands short along the same aim line.
	var hand_to_target: Vector2 = desired_blade_xz - hand_xz
	var blade_dir: Vector2
	if hand_to_target.length_squared() > 0.0001:
		blade_dir = hand_to_target.normalized()
	else:
		blade_dir = aim_dir
	var blade_xz: Vector2 = hand_xz + blade_dir * stick_horiz

	return {
		"hand": Vector3(hand_xz.x, hand_rest_y, hand_xz.y),
		"blade": Vector3(blade_xz.x, blade_y, blade_xz.y),
	}

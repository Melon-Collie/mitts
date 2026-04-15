class_name BottomHandIK

# Pure bottom-hand inverse kinematics. Given a desired grip target on the stick
# shaft in upper-body-local XZ space, returns the bottom hand's position in
# upper-body-local space. Purely reactive — it does not influence blade or
# top-hand placement; the caller owns those and derives the grip target from
# their positions (e.g. top_hand.lerp(blade, grip_fraction)).
#
# The bottom hand anchors at the shoulder opposite the top hand's shoulder —
# for a left-handed shooter, the bottom hand lives on the left (−X) side while
# the blade also lives on −X.
#
# Three behaviours:
#   1. Reachable target → hand lands exactly on the grip target (hand grips the
#      shaft).
#   2. Target past asymmetric ROM (angle clamp + reach clamp) on the SAME-SIDE
#      (toward the blade) → hand clamps short along the aim line; it's still
#      trying to hold on, just can't extend that far.
#   3. Target swinging into the CROSS-BODY direction (toward the top-hand side
#      of the body), past `rom_cross_body_angle_max − release_angle_band` →
#      hand smoothly releases back to a rest pose at the bottom shoulder (the
#      one-handed backhand look). The release uses the PRE-clamp raw angle so
#      it kicks in regardless of where the ROM-clamped hand would have landed.
#
# ROM naming convention: "same-side" = toward the blade (the bottom hand's
# own side of the body; large reach, like the top hand's "backhand" side).
# "cross-body" = toward the top hand (tight reach).
#
# side_sign: +1.0 for a left-handed shooter (bottom hand on −X; blade on −X),
#            −1.0 for a right-handed shooter (bottom hand on +X; blade on +X).
# Conventionally this is the negation of the TopHandIK `blade_side_sign`.
#
# cfg keys (all floats):
#   hand_y                    — fixed local Y for the bottom hand
#   rom_cross_body_angle_max  — radians; angular ROM toward top-hand side (tight)
#   rom_same_side_angle_max   — radians; angular ROM toward blade side (loose)
#   rom_cross_body_reach_max  — meters;  max hand displacement cross-body
#   rom_same_side_reach_max   — meters;  max hand displacement same-side
#   release_angle_band        — radians; smoothstep width before the cross-body
#                               ROM max where the hand begins releasing to rest
#
# Returns: Vector3 hand position in upper-body-local space.
static func solve(
		shoulder: Vector3,
		grip_target_xz: Vector2,
		side_sign: float,
		cfg: Dictionary) -> Vector3:
	var hand_y: float = cfg.hand_y

	var shoulder_xz := Vector2(shoulder.x, shoulder.z)
	var delta: Vector2 = grip_target_xz - shoulder_xz
	var r: float = delta.length()

	# Degenerate: target coincides with shoulder. Return rest pose — there's
	# no meaningful aim direction and the hand is effectively at its anchor.
	if r < 0.0001:
		return Vector3(shoulder_xz.x, hand_y, shoulder_xz.y)

	var aim_dir: Vector2 = delta / r

	# Forehand-signed polar: angle > 0 always means "displaced cross-body"
	# (toward the top-hand side) regardless of handedness; angle < 0 means
	# same-side (toward the blade).
	var angle_raw: float = atan2(delta.x, -delta.y)
	var angle_cross_body: float = angle_raw * side_sign
	var radius: float = r

	# Clamp angle asymmetrically: cross-body is tight, same-side is open.
	var cross_angle_max: float = cfg.rom_cross_body_angle_max
	var same_angle_max: float = cfg.rom_same_side_angle_max
	var angle_clamped: float = clampf(angle_cross_body, -same_angle_max, cross_angle_max)

	# Max reach is asymmetric: same-side reach is large, cross-body is small.
	# Small linear blend across zero avoids a seam. Matches the idiom used in
	# top_hand_ik.gd:104-114.
	var blend_band: float = deg_to_rad(5.0)
	var cross_reach: float = cfg.rom_cross_body_reach_max
	var same_reach: float = cfg.rom_same_side_reach_max
	var max_reach: float
	if angle_clamped >= blend_band:
		max_reach = cross_reach
	elif angle_clamped <= -blend_band:
		max_reach = same_reach
	else:
		var t: float = (angle_clamped + blend_band) / (2.0 * blend_band)
		max_reach = lerpf(same_reach, cross_reach, t)
	radius = clampf(radius, 0.0, max_reach)

	# Back to Cartesian.
	var world_angle: float = angle_clamped * side_sign
	var hand_disp := Vector2(sin(world_angle) * radius, -cos(world_angle) * radius)
	var ideal_hand_xz: Vector2 = shoulder_xz + hand_disp

	# Release blend: as the raw cross-body angle approaches (and then exceeds)
	# its ROM max, smoothly pull the hand back to the rest pose at the shoulder.
	# Uses the pre-clamp `angle_cross_body` so it fires independently of reach.
	var release_band: float = cfg.release_angle_band
	var release_start: float = cross_angle_max - release_band
	var release_t: float = smoothstep(release_start, cross_angle_max, angle_cross_body)
	var hand_xz: Vector2 = ideal_hand_xz.lerp(shoulder_xz, release_t)

	return Vector3(hand_xz.x, hand_y, hand_xz.y)

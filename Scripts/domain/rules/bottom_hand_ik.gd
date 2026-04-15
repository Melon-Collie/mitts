class_name BottomHandIK

# Pure bottom-hand inverse kinematics. Places the bottom hand on the grip target
# unless the blade has swung past the backhand angle the upper body can track.
#
# Release behaviour — driven by blade world angle toward the backhand side:
#   Within release_angle_max        → hand exactly on the grip target (on the stick).
#   release_angle_max → +band       → smoothstep blend toward shoulder rest.
#   Beyond release_angle_max + band → hand at shoulder rest (one-handed look).
#
# This ties the release directly to the upper body rotation limit rather than arm
# reach distance, so the hand never gives up during a normal swing — only when the
# blade is genuinely past what the body can rotate to follow.
#
# cfg keys:
#   hand_y              — target local Y for the hand
#   backhand_angle      — current blade angle toward backhand side (radians, >=0)
#   release_angle_max   — angle at which blending begins (radians)
#   release_angle_band  — blend band width past release_angle_max (radians)
#
# Returns: Vector3 hand position in upper-body-local space.
static func solve(
		shoulder: Vector3,
		grip_target_xz: Vector2,
		cfg: Dictionary) -> Vector3:
	var hand_y: float = cfg.hand_y
	var target := Vector3(grip_target_xz.x, hand_y, grip_target_xz.y)
	var rest := Vector3(shoulder.x, hand_y, shoulder.z)

	var backhand_angle: float = cfg.backhand_angle
	var release_max: float = cfg.release_angle_max
	var release_band: float = cfg.release_angle_band
	var t: float = smoothstep(release_max, release_max + release_band, backhand_angle)
	return target.lerp(rest, t)

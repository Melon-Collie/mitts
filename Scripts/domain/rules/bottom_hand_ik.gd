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
# Returns: Vector3 hand position in upper-body-local space.

class Config:
	var hand_y: float = 0.0              # target local Y for the hand
	var backhand_angle: float = 0.0      # current blade angle toward backhand (rad, >=0)
	var release_angle_max: float = 0.0   # angle at which blending begins (radians)
	var release_angle_band: float = 0.0  # blend band width past release_angle_max (rad)

static func solve(
		shoulder: Vector3,
		grip_target_xz: Vector2,
		cfg: Config) -> Vector3:
	var hand_y: float = cfg.hand_y
	var target := Vector3(grip_target_xz.x, hand_y, grip_target_xz.y)
	var rest := Vector3(shoulder.x, hand_y, shoulder.z)

	var backhand_angle: float = cfg.backhand_angle
	var release_max: float = cfg.release_angle_max
	var release_band: float = cfg.release_angle_band
	var t: float = smoothstep(release_max, release_max + release_band, backhand_angle)
	return target.lerp(rest, t)


# Where on the shaft the bottom hand can hold, as a fraction from the top hand
# (0) to the blade (1): the point nearest the preferred `grip` that lies within
# `reach` of the shoulder — the hand slides up the shaft rather than out-reach
# its arm. Returned as (fraction, overshoot): when no point of the shaft is in
# reach, the fraction is the nearest point and the overshoot how far beyond
# reach it lies (0 otherwise), which is what lets the hand come off the stick.
static func reachable_grip(shoulder: Vector3, top: Vector3, blade: Vector3,
		grip: float, reach: float) -> Vector2:
	var u: Vector3 = blade - top
	var w: Vector3 = top - shoulder
	var a: float = u.length_squared()
	if a < 0.000001:
		return Vector2(grip, maxf(w.length() - reach, 0.0))
	# |w + g·u|² = reach²  →  a·g² + 2b·g + c = 0
	var b: float = u.dot(w)
	var c: float = w.length_squared() - reach * reach
	var disc: float = b * b - a * c
	if disc >= 0.0:
		var root: float = sqrt(disc)
		var lo: float = maxf((-b - root) / a, 0.0)
		var hi: float = minf((-b + root) / a, 1.0)
		if lo <= hi:
			return Vector2(clampf(grip, lo, hi), 0.0)
	var nearest: float = clampf(-b / a, 0.0, 1.0)
	return Vector2(nearest, maxf((w + u * nearest).length() - reach, 0.0))

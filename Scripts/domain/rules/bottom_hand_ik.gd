class_name BottomHandIK

# Pure bottom-hand rules: how far the blade's swing to the backhand lets the hand
# off the stick (release_weight), and where on the shaft it can hold
# (reachable_grip). SkaterIKCoordinator.update_bottom_hand composes them.
#
# The release is driven by the blade's angle toward the backhand side:
#   Within release_angle_max        → on the stick.
#   release_angle_max → +band       → smoothstep toward the free hand's rest.
#   Beyond release_angle_max + band → at rest (one-handed look).
#
# This ties the release to the upper body's rotation limit rather than the arm's
# reach, so the hand never gives up during a normal swing — only when the blade is
# genuinely past what the body can rotate to follow.

class Config:
	var backhand_angle: float = 0.0      # current blade angle toward backhand (rad, >=0)
	var release_angle_max: float = 0.0   # angle at which blending begins (radians)
	var release_angle_band: float = 0.0  # blend band width past release_angle_max (rad)


# How far the angle has let the hand go, 0 (on the stick) to 1 (at rest).
static func release_weight(cfg: Config) -> float:
	return smoothstep(cfg.release_angle_max, cfg.release_angle_max + cfg.release_angle_band,
			cfg.backhand_angle)


# Where on the shaft the bottom hand can hold, as a fraction from the top hand
# (0) to the blade (1): the point nearest the preferred `grip` that lies within
# `reach` of the shoulder and at least `spacing` metres down from the top hand
# (the shaft the top glove takes up) — the hand slides up the shaft rather than
# out-reach its arm, as far as the top glove. Returned as (fraction, overshoot):
# when no such point is in reach, the fraction is the nearest one and the
# overshoot how far beyond reach it lies (0 otherwise), which is what lets the
# hand come off the stick.
static func reachable_grip(shoulder: Vector3, top: Vector3, blade: Vector3,
		grip: float, reach: float, spacing: float = 0.0) -> Vector2:
	var u: Vector3 = blade - top
	var w: Vector3 = top - shoulder
	var a: float = u.length_squared()
	if a < 0.000001:
		return Vector2(grip, maxf(w.length() - reach, 0.0))
	var floor_g: float = minf(spacing / sqrt(a), 1.0)
	# |w + g·u|² = reach²  →  a·g² + 2b·g + c = 0
	var b: float = u.dot(w)
	var c: float = w.length_squared() - reach * reach
	var disc: float = b * b - a * c
	if disc >= 0.0:
		var root: float = sqrt(disc)
		var lo: float = maxf((-b - root) / a, floor_g)
		var hi: float = minf((-b + root) / a, 1.0)
		if lo <= hi:
			return Vector2(clampf(grip, lo, hi), 0.0)
	var nearest: float = clampf(-b / a, floor_g, 1.0)
	return Vector2(nearest, maxf((w + u * nearest).length() - reach, 0.0))

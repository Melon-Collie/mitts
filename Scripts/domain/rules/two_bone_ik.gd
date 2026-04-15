class_name TwoBoneIK

# Classic analytical 2-bone inverse kinematics. Given a shoulder anchor, a
# hand target, two bone lengths, and a pole-direction hint, returns the elbow
# world position such that:
#
#   |shoulder − elbow| ≈ upper_len  (exact when hand is within reach)
#   |elbow − hand|     ≈ forearm_len
#
# and the elbow sits on the side of the shoulder→hand axis pointed at by the
# pole direction. Used for rendering the top-hand arm; no gameplay constraint.
#
# Reach handling: if |hand − shoulder| > upper_len + forearm_len the math is
# clamped to max reach (elbow ends up on the shoulder→hand line); the caller
# is responsible for gating hand-within-reach if that matters. We keep this
# solver forgiving rather than snapping.
#
# Pole hint: any non-zero world-space direction. It's projected onto the
# plane perpendicular to the shoulder→hand axis — callers don't need to
# pre-project. If the pole happens to be parallel to the axis, a stable
# fallback (Vector3.DOWN, or Vector3.FORWARD if the axis is vertical) is
# substituted so the elbow still has a defined direction.
static func solve_elbow(
		shoulder: Vector3,
		hand: Vector3,
		upper_len: float,
		forearm_len: float,
		pole_world: Vector3) -> Vector3:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	if d < 0.0001:
		# Degenerate: hand coincides with shoulder. Arm is fully folded; no
		# meaningful direction. Return shoulder as a safe fallback; the caller's
		# bone mesh will have zero length but won't crash.
		return shoulder

	var axis: Vector3 = d_vec / d
	var d_clamped: float = clampf(d, absf(upper_len - forearm_len), upper_len + forearm_len)
	var foot_t: float = (upper_len * upper_len - forearm_len * forearm_len + d_clamped * d_clamped) / (2.0 * d_clamped)
	var h_sq: float = upper_len * upper_len - foot_t * foot_t
	var h: float = sqrt(maxf(h_sq, 0.0))
	var foot: Vector3 = shoulder + axis * foot_t

	# Project pole onto plane perpendicular to axis.
	var pole_dir: Vector3 = pole_world - axis * pole_world.dot(axis)
	if pole_dir.length() < 0.0001:
		var fallback: Vector3 = Vector3.DOWN if absf(axis.y) < 0.9 else Vector3.FORWARD
		pole_dir = fallback - axis * fallback.dot(axis)
	return foot + pole_dir.normalized() * h

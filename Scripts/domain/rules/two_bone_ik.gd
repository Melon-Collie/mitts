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


# The elbow of an arm that HANGS: of every elbow the two bone lengths allow — a
# circle around the shoulder→hand axis — the lowest one that stays out of the
# trunk. It may not fold inside the shoulder (`outward`), and it may not go back
# past the shoulder (`forward`) while it is still within `clear_out` of it —
# that is behind the chest. Once it is `clear_out` outboard it is beside the
# body, and hanging back there is exactly what a low hand's elbow does. Unlike
# a fixed pole, this holds up when the hand moves around the shoulder: a pole
# says "down", and for a hand out in front and below, down projects to
# down-and-BEHIND, which puts the elbow in the chest.
#
# Sampled rather than solved, which is plenty for a cosmetic joint and
# allocates nothing. When no sample stays clear, the one that intrudes least
# wins, so the arm still folds somewhere sensible for a hand pulled into the body.
const _HANG_SAMPLES: int = 24

static func solve_elbow_hanging(
		shoulder: Vector3,
		hand: Vector3,
		upper_len: float,
		forearm_len: float,
		forward: Vector3,
		outward: Vector3,
		clear_out: float = INF) -> Vector3:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	if d < 0.0001:
		return shoulder
	var axis: Vector3 = d_vec / d
	var d_clamped: float = clampf(d, absf(upper_len - forearm_len), upper_len + forearm_len)
	var foot_t: float = (upper_len * upper_len - forearm_len * forearm_len + d_clamped * d_clamped) / (2.0 * d_clamped)
	var h: float = sqrt(maxf(upper_len * upper_len - foot_t * foot_t, 0.0))
	var foot: Vector3 = shoulder + axis * foot_t
	var ref: Vector3 = Vector3.UP if absf(axis.y) < 0.9 else Vector3.FORWARD
	var e1: Vector3 = (ref - axis * ref.dot(axis)).normalized()
	var e2: Vector3 = axis.cross(e1)
	var best: Vector3 = foot
	var best_y: float = INF
	var best_miss: float = INF
	for i: int in _HANG_SAMPLES:
		var a: float = TAU * float(i) / float(_HANG_SAMPLES)
		var e: Vector3 = foot + (e1 * cos(a) + e2 * sin(a)) * h
		var off: Vector3 = e - shoulder
		var out: float = off.dot(outward)
		var behind: float = maxf(-off.dot(forward), 0.0) if out < clear_out else 0.0
		var miss: float = behind + maxf(-out, 0.0)
		if miss < best_miss - 0.0001 or (absf(miss - best_miss) <= 0.0001 and e.y < best_y):
			best_miss = miss
			best_y = e.y
			best = e
	return best

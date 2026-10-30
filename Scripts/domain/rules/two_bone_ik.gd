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
	return foot + bend_direction(shoulder, hand, pole_world) * h


# The unit direction solve_elbow pushes the elbow off the shoulder→hand line:
# the pole, squared to that line — which way the elbow's point faces. Zero when
# the hand sits on the shoulder.
static func bend_direction(shoulder: Vector3, hand: Vector3, pole_world: Vector3) -> Vector3:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	if d < 0.0001:
		return Vector3.ZERO
	var axis: Vector3 = d_vec / d
	var pole_dir: Vector3 = pole_world - axis * pole_world.dot(axis)
	if pole_dir.length() < 0.0001:
		var fallback: Vector3 = Vector3.DOWN if absf(axis.y) < 0.9 else Vector3.FORWARD
		pole_dir = fallback - axis * fallback.dot(axis)
	return pole_dir.normalized()


# Where an arm roots once the shoulder girdle has given: a hand past `arm_len`
# (the arm's working length) draws the shoulder toward it — the shoulder blade
# protracting and dropping — by up to `slack`. Past that the arm straightens,
# and past its full length solve_elbow stretches the forearm, so callers keep
# their hands within (arm_len + slack).
static func reach_root(shoulder: Vector3, hand: Vector3, arm_len: float,
		slack: float) -> Vector3:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	var over: float = d - arm_len
	if over <= 0.0 or d < 0.0001:
		return shoulder
	return shoulder + d_vec / d * minf(over, slack)


# How far an arm holding a shaft running `grip` (unit, toward the working end —
# a stick's blade) wants its elbow turned up the shaft, 0..1 (bend_for_grip).
# A fist holds a shaft like a sword, the working end leaving by the thumb, and a
# wrist turns the hand only so far toward the thumb: an elbow on the working
# end's side of the hand — under a hand holding a stick upright — puts that end
# back toward the elbow, a dagger held point down. So it is _GRIP_TURN · (1 −
# exp(−_GRIP_LEAN · shortfall²)), the shortfall (in forearm lengths) by which the pole's elbow
# brings the forearm in at more than acos(`min_cos`) off the shaft's run: easing
# in from nothing. Only a shaft running down from the hand (`grip` in a Y-up
# frame) reads as a dagger, so it fades out as the shaft comes up to level.
const _GRIP_LEAN: float = 12.0
# The most of the way round toward up the shaft and out it turns: a stick held
# upright puts the elbow out level with the fist, not up at the shoulder.
const _GRIP_TURN: float = 0.6

static func grip_lean(shoulder: Vector3, hand: Vector3, upper_len: float,
		forearm_len: float, pole_world: Vector3, grip: Vector3, min_cos: float) -> float:
	var elbow: Vector3 = solve_elbow(shoulder, hand, upper_len, forearm_len, pole_world)
	var short: float = min_cos - (hand - elbow).dot(grip) / forearm_len
	if short <= 0.0:
		return 0.0
	return _GRIP_TURN * (1.0 - exp(-_GRIP_LEAN * short * short)) * smoothstep(0.0, 0.5, -grip.y)


# The pole's bend turned `share` of the way round the elbow's circle toward up
# the shaft (−`grip`) and `outward` (the arm's own side) together, through the
# arc between them: out and then up, never through the circle's middle, so the
# elbow cannot jump sides. A unit bend direction, which solve_elbow takes as its
# pole.
static func bend_for_grip(shoulder: Vector3, hand: Vector3, pole_world: Vector3,
		grip: Vector3, outward: Vector3, share: float) -> Vector3:
	var bend: Vector3 = bend_direction(shoulder, hand, pole_world)
	if share <= 0.0 or bend == Vector3.ZERO:
		return bend
	var axis: Vector3 = (hand - shoulder).normalized()
	var toward: Vector3 = outward.normalized() - grip
	toward -= axis * toward.dot(axis)
	if toward.length_squared() < 0.000001:
		return bend
	var hinge: Vector3 = bend.cross(toward.normalized())
	if hinge.length_squared() < 0.000001:
		return bend
	return bend.rotated(hinge.normalized(), bend.angle_to(toward) * share)


# The elbow of an arm beside a trunk: the pole's (solve_elbow), leant round
# the shoulder→hand axis away from the trunk as far as its arm runs into it. A
# fixed pole only knows which way is down and out: an arm reaching across the
# front of the body to a hand on the stick points that elbow back into the belly.
#
# The trunk is an upright elliptic cylinder in `trunk`'s frame (which maps it
# into the arm's space, scale and all): `keep_out` is (half width, half depth,
# lowest y, highest y) there. The upper arm counts from `root_skip` of the way
# down it, past the shoulder its root sits in. The pole's bend takes on the
# trunk's outward normal at that elbow, weighted by _CLEAR_LEAN times the square
# of how far the arm runs in (a unit is the trunk's own size): the square eases
# the lean in from nothing, so the elbow neither kinks where it starts nor jumps
# — a search for the nearest elbow that keeps out jumps across the arm wherever
# its best answer changes sides. It need not keep the arm out; it takes it out
# of the trunk's middle.
const _CLEAR_LEAN: float = 60.0

static func solve_elbow_clear(
		shoulder: Vector3,
		hand: Vector3,
		upper_len: float,
		forearm_len: float,
		pole_world: Vector3,
		trunk: Transform3D,
		keep_out: Vector4,
		root_skip: float) -> Vector3:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	if d < 0.0001:
		return shoulder
	var axis: Vector3 = d_vec / d
	var d_clamped: float = clampf(d, absf(upper_len - forearm_len), upper_len + forearm_len)
	var foot_t: float = (upper_len * upper_len - forearm_len * forearm_len + d_clamped * d_clamped) / (2.0 * d_clamped)
	var h: float = sqrt(maxf(upper_len * upper_len - foot_t * foot_t, 0.0))
	var foot: Vector3 = shoulder + axis * foot_t
	var bend: Vector3 = bend_direction(shoulder, hand, pole_world)
	var to_trunk: Transform3D = trunk.affine_inverse()
	var e: Vector3 = to_trunk * (foot + bend * h)
	var into: float = _arm_intrusion(to_trunk * shoulder, e, to_trunk * hand, keep_out, root_skip)
	if into <= 0.0:
		return foot + bend * h
	var away: Vector3 = trunk.basis * Vector3(e.x / (keep_out.x * keep_out.x), 0.0,
			e.z / (keep_out.y * keep_out.y))
	away -= axis * away.dot(axis)
	if away.length_squared() < 0.000001:
		return foot + bend * h
	var leant: Vector3 = bend + away.normalized() * (_CLEAR_LEAN * into * into)
	if leant.length_squared() < 0.000001:
		return foot + bend * h
	return foot + leant.normalized() * h


# How far into the trunk (solve_elbow_clear's, in the trunk's frame) an arm from
# `s` through elbow `e` to `w` goes, as a fraction of the section's size: 0 when
# it stays out.
static func _arm_intrusion(s: Vector3, e: Vector3, w: Vector3, keep_out: Vector4,
		root_skip: float) -> float:
	return maxf(_segment_intrusion(s.lerp(e, root_skip), e, keep_out),
			_segment_intrusion(e, w, keep_out))


static func _segment_intrusion(a: Vector3, b: Vector3, keep_out: Vector4) -> float:
	var t0: float = 0.0
	var t1: float = 1.0
	var dy: float = b.y - a.y
	if absf(dy) < 0.000001:
		if a.y < keep_out.z or a.y > keep_out.w:
			return 0.0
	else:
		var ta: float = (keep_out.z - a.y) / dy
		var tb: float = (keep_out.w - a.y) / dy
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return 0.0
	var p := Vector2(a.x / keep_out.x, a.z / keep_out.y)
	var u: Vector2 = Vector2(b.x / keep_out.x, b.z / keep_out.y) - p
	var len_sq: float = u.length_squared()
	var t: float = t0
	if len_sq > 0.000001:
		t = clampf(-p.dot(u) / len_sq, t0, t1)
	return maxf(1.0 - (p + u * t).length(), 0.0)


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
# `forearm_max_off_down` (radians) keeps the forearm within that angle of
# hanging straight down to the hand: an elbow that would lay it flatter is not
# clear either, so the elbow rises only as far as that takes. Staying out of
# the trunk comes first.
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
		clear_out: float = INF,
		forearm_max_off_down: float = PI) -> Vector3:
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
	var min_down_cos: float = cos(forearm_max_off_down)
	var best: Vector3 = foot
	var best_y: float = INF
	var best_miss: float = INF
	var best_flat: float = INF
	for i: int in _HANG_SAMPLES:
		var a: float = TAU * float(i) / float(_HANG_SAMPLES)
		var e: Vector3 = foot + (e1 * cos(a) + e2 * sin(a)) * h
		var off: Vector3 = e - shoulder
		var out: float = off.dot(outward)
		var behind: float = maxf(-off.dot(forward), 0.0) if out < clear_out else 0.0
		var miss: float = behind + maxf(-out, 0.0)
		var fore: Vector3 = hand - e
		var fore_len: float = fore.length()
		var down_cos: float = -fore.y / fore_len if fore_len > 0.0001 else 1.0
		var flat: float = maxf(min_down_cos - down_cos, 0.0)
		if miss < best_miss - 0.0001 \
				or (absf(miss - best_miss) <= 0.0001 and (flat < best_flat - 0.0001
					or (absf(flat - best_flat) <= 0.0001 and e.y < best_y))):
			best_miss = miss
			best_flat = flat
			best_y = e.y
			best = e
	return best

class_name StickHoldRules

# Where the top hand holds a stick whose blade is already placed, with both
# hands on it: a carrier's. (A stick without the puck is the top hand's alone,
# on the line from its shoulder to the blade, which is the reach solve's own
# hand; SkaterIKCoordinator._held_hand blends the two by the grip.)
#
# The stick is rigid and its blade is on the ice, so the hand is somewhere on a
# sphere about the blade; which point of it is the player's choice, and players
# make the same one. The hand lives in a pocket out in front of its own hip,
# off the body, and the stick pivots through it: a blade further off than the
# stick spans at its lie draws the hand out toward it, and a nearer one sends
# it out to its own side and back toward the hip, the stick coming across the
# front of the body. Only what the pocket cannot take up stands the shaft off
# its lie. The height is never chosen: it is what the rigid stick leaves once
# the hand's place across the ice is.
#
# Everything is in one level frame, y up and −z ahead of the chest; lengths in
# metres, angles in radians.

class Config:
	# The shaft's elevation off the ice with the blade flat: the stick's lie.
	var lie: float = deg_to_rad(43.3)
	# The pocket's middle off the top shoulder: out to the hand's own side, and
	# ahead.
	var home_out: float = 0.03
	var home_ahead: float = 0.28
	# How far the hand reaches off that middle toward a blade past the stick's
	# span: ahead, out to its own side, and across the body.
	var reach_ahead: float = 0.25
	var reach_out: float = 0.25
	var reach_across: float = 0.4
	# How far it draws off that middle from a blade inside the span, and the
	# way: out to its own side and back.
	var draw: float = 0.22
	var draw_out: float = 0.82
	var draw_back: float = 0.57
	# The share of the draw that would keep the stick on its lie the hand
	# takes; the shaft stands up off its lie for the rest. All of it moves the
	# hand sideways twice as fast as a blade coming straight in moves.
	var draw_share: float = 0.5
	# The lowest the hand rides over the blade, as a share of the stick: a
	# shaft laid flatter than this has its blade up on the heel.
	var low_share: float = 0.5


# Half-width of the corner the hand's travel is rounded over where it meets
# the pocket's edge (m).
const EDGE_BAND_M: float = 0.05
# Half-width of the band about the stick's span over which the hand's reach
# toward a far blade and its draw from a near one each ease in (m).
const REST_BAND_M: float = 0.08


# How much of the draw a blade off toward the draw's own way still gets, by
# how far the blade lies from the pocket's middle against the draw's way, in
# spans of the stick: off toward the way, the first of the draw brings the
# hand toward the blade. In spans, not by the blade's bearing off the middle,
# which a blade passing close by the middle swings through in a few ticks.
const DRAW_FROM := Vector2(-0.2, 0.5)


# The top hand for a blade at `blade`, off the top shoulder at `shoulder`
# (only its place across the ice is read), exactly `stick_length` from the
# blade wherever a hand could be. `own_side` is the sign of x on the top
# hand's side of the body.
static func top_hand(shoulder: Vector3, blade: Vector3, stick_length: float,
		own_side: float, cfg: Config) -> Vector3:
	var pivot := Vector2(shoulder.x + own_side * cfg.home_out, shoulder.z - cfg.home_ahead)
	var to_blade: Vector2 = Vector2(blade.x, blade.z) - pivot
	var r: float = to_blade.length()
	var dir: Vector2 = to_blade / r if r > 0.0001 else Vector2(0.0, -1.0)
	var rest_span: float = stick_length * cos(cfg.lie)
	# The blade past the span reaches the hand out, the blade inside it draws
	# the hand aside: each eases in from nothing across REST_BAND_M about the
	# span itself, where one hands over to the other, or the hand's path turns
	# a corner at the middle of its pocket.
	var past: float = eased_in(r - rest_span, REST_BAND_M)
	var short: float = eased_in(rest_span - r, REST_BAND_M)
	var at: Vector2 = pivot
	if past > 0.0:
		var travel: float = soft_cap(past, reach(dir, own_side, cfg), EDGE_BAND_M)
		# A blade past the pocket's far edge lays the shaft down, as far as the
		# hand stays over the ice; past that the hand follows it out.
		var widest: float = stick_length * sqrt(1.0 - cfg.low_share * cfg.low_share)
		at += dir * (travel + eased_in(r - widest - travel, EDGE_BAND_M))
	if short > 0.0:
		# Along the draw's way, the distance that puts the stick back on its lie
		# from a blade `short` inside the span: the root of
		# |pivot + way·e − blade| = rest_span.
		var way := Vector2(own_side * cfg.draw_out, cfg.draw_back).normalized()
		var near: float = rest_span - short
		var against: float = -(dir * near).dot(way)
		var needed: float = -against + sqrt(maxf(
				against * against + rest_span * rest_span - near * near, 0.0))
		var most: float = cfg.draw * smoothstep(DRAW_FROM.x, DRAW_FROM.y, against / rest_span)
		at += way * soft_cap(needed * cfg.draw_share, most, EDGE_BAND_M)
	var span: float = at.distance_to(Vector2(blade.x, blade.z))
	return Vector3(at.x, blade.y + sqrt(maxf(stick_length * stick_length - span * span, 0.0)),
			at.y)


# The hand of an arm reaching for a far blade. `hand` (from top_hand) turned
# about the blade toward `reaching_hand`, the pose a reach holds the same
# stick in, by how far the blade is off the shoulder: none of it at `from`
# (m), all of it by `to`, which lies inside the arm's reach, so the pocket is
# left before the arm is straight. (Held in the pocket to the arm's very end
# and brought inside its reach only then, the stick swings off the arm's line
# at the instant the blade comes back, as fast as a straight elbow unlocks.)
static func reaching(hand: Vector3, reaching_hand: Vector3, blade: Vector3, shoulder: Vector3,
		from: float, to: float) -> Vector3:
	var share: float = smoothstep(from, to, shoulder.distance_to(blade))
	var stick: Vector3 = hand - blade
	var reached: Vector3 = reaching_hand - blade
	var length: float = stick.length()
	if share <= 0.0 or length < 0.0001 or reached.length_squared() < 0.00000001:
		return hand
	return blade + (stick / length).slerp(reached.normalized(), share) * length


# The hand at `hand`, on a stick from the blade at `blade`, brought within
# `arm` of the shoulder it hangs from where it lies past it: turned about the
# blade toward the shoulder, so the stick keeps its length, by as little as
# brings it inside, the corner where that starts rounded over `band` radians.
# An arm out at its reach lies along the line from its shoulder to the blade.
static func within_reach(hand: Vector3, blade: Vector3, shoulder: Vector3, arm: float,
		band: float) -> Vector3:
	var stick: Vector3 = hand - blade
	var to_shoulder: Vector3 = shoulder - blade
	var length: float = stick.length()
	var away: float = to_shoulder.length()
	if length < 0.0001 or away < 0.0001:
		return hand
	var from: Vector3 = stick / length
	var toward: Vector3 = to_shoulder / away
	# The widest the stick may stand off the shoulder's line with the hand
	# still in reach (the triangle blade, shoulder, hand).
	var widest: float = acos(clampf(
			(length * length + away * away - arm * arm) / (2.0 * length * away), -1.0, 1.0))
	var off: float = from.angle_to(toward)
	var held: float = soft_cap(off, widest, band)
	if off - held < 0.000001:
		return hand
	return blade + from.slerp(toward, (off - held) / off) * length


# How far the hand reaches off the pocket's middle along `dir` (unit, across
# the ice, ahead of it): two quarter-ellipses, which meet with no seam.
static func reach(dir: Vector2, own_side: float, cfg: Config) -> float:
	var lateral: float = cfg.reach_out if dir.x * own_side >= 0.0 else cfg.reach_across
	var fore: float = cfg.reach_ahead
	var denom: float = sqrt(fore * fore * dir.x * dir.x + lateral * lateral * dir.y * dir.y)
	return fore * lateral / denom if denom > 0.000001 else 0.0


# `x` eased in from nothing: none of it below −band, all of it past +band, and
# a quadratic between with no step in its slope at either end.
static func eased_in(x: float, band: float) -> float:
	if x >= band:
		return x
	if x <= -band:
		return 0.0
	return (x + band) * (x + band) / (4.0 * band)


# `x` (never negative) held under `cap`, the corner rounded over `band` either
# side of it so its slope has no step there: exactly x below the corner and
# exactly the cap beyond it.
static func soft_cap(x: float, cap: float, band: float) -> float:
	var b: float = minf(band, cap * 0.5)
	if b <= 0.0:
		return minf(x, maxf(cap, 0.0))
	if x <= cap - b:
		return x
	var over: float = minf(x - (cap - b), 2.0 * b)
	return cap - b + over - over * over / (4.0 * b)

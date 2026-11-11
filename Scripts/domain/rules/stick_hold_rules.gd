class_name StickHoldRules

# Where the top hand holds a stick whose blade is already placed.
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
	# The lowest the hand rides over the blade, as a share of the stick: a
	# shaft laid flatter than this has its blade up on the heel.
	var low_share: float = 0.5


# Half-width of the corner the hand's travel is rounded over where it meets
# the pocket's edge (m).
const EDGE_BAND_M: float = 0.05


# How much of the draw a blade off toward the draw's own way still gets, by
# the cosine between the way to the blade and the way against the draw: there
# the first of the draw brings the hand toward the blade.
const _DRAW_FROM := Vector2(-0.2, 0.5)


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
	var at: Vector2 = pivot
	if r >= rest_span:
		var travel: float = soft_cap(r - rest_span, reach(dir, own_side, cfg), EDGE_BAND_M)
		# A blade past the pocket's far edge lays the shaft down, as far as the
		# hand stays over the ice; past that the hand follows it out.
		var widest: float = stick_length * sqrt(1.0 - cfg.low_share * cfg.low_share)
		at += dir * maxf(travel, r - widest)
	else:
		# Along the draw's way, the distance that puts the stick back on its lie:
		# the root of |pivot + way·e − blade| = rest_span.
		var way := Vector2(own_side * cfg.draw_out, cfg.draw_back).normalized()
		var against: float = -to_blade.dot(way)
		var needed: float = -against + sqrt(against * against + rest_span * rest_span - r * r)
		var most: float = cfg.draw * smoothstep(_DRAW_FROM.x, _DRAW_FROM.y,
				against / maxf(r, 0.0001))
		at += way * soft_cap(needed, most, EDGE_BAND_M)
	var span: float = at.distance_to(Vector2(blade.x, blade.z))
	return Vector3(at.x, blade.y + sqrt(maxf(stick_length * stick_length - span * span, 0.0)),
			at.y)


# How far the hand reaches off the pocket's middle along `dir` (unit, across
# the ice, ahead of it): two quarter-ellipses, which meet with no seam.
static func reach(dir: Vector2, own_side: float, cfg: Config) -> float:
	var lateral: float = cfg.reach_out if dir.x * own_side >= 0.0 else cfg.reach_across
	var fore: float = cfg.reach_ahead
	var denom: float = sqrt(fore * fore * dir.x * dir.x + lateral * lateral * dir.y * dir.y)
	return fore * lateral / denom if denom > 0.000001 else 0.0


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

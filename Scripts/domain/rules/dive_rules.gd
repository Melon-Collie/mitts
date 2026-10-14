class_name DiveRules
extends RefCounted

# The dive (stance + block: Shift + C, LB + A): the defenseman's 2-on-1 play,
# down on the ice across the pass lane with the stick out. It rides the
# knockdown's rail — a replicated down timer, the friction slide, the fall and
# the get-up — so it adds no velocity of its own: the body keeps the momentum it
# had and slides on the way it was going. The cursor only decides how the body
# is LAID OUT (the fall direction), and so where the low block lies and where
# the stick reaches.

# Down at least this long, the get-up included (SkaterController
# .knockdown_getup_seconds is its tail); block held keeps him lying there until
# it is let go.
const DOWN_S: float = 1.4
# The fall is thrown, not taken: the diver leaves his skates at the hardest hit's
# tip rate (the knockdown's knockdown_fall_max_entry_omega) whatever his speed,
# after a push this long, and lands without a rebound — on purpose, onto his
# hands and side. At those numbers he is on the ice a third of a second in,
# leaving the lie its time before the get-up.
const TIP_RATE_RAD_S: float = 4.2
const PUSH_S: float = 0.05
# Lying tilt about the blades: the legs stay long, so the hips (~0.92 m above
# the blades standing) rest on the side of the pelvis ~0.15 m up — acos(0.15 / 0.92).
const LIE_DEG: float = 80.6
# His belt (the centre of mass of a body laid out long) keeps the line he was
# skating as he tips: nothing on the ice holds the skates back, so they go out
# from under him the far side of it.
const COM_HEIGHT_M: float = 0.95
# The lying body and its stick as one low block: a capsule from the skates out
# along the layout to the blade, sealed from the ice to about a lying body's
# height. A puck over it goes through — the same trade as the standing block.
const BODY_RADIUS_M: float = 0.22
const SEAL_HEIGHT_M: float = 0.3
# The top hand lies this far out along the layout from the skates, just off the
# ice: the outstretched arm of a body the fall laid down (the knockdown's
# knockdown_fall_body_reach_m).
const HAND_REACH_M: float = 1.9
const HAND_HEIGHT_M: float = 0.15
# The block runs to the blade of a league-default stick laid flat from that hand,
# rather than the diver's own stick (the drawn one is his own).
const BLOCK_LENGTH_M: float = HAND_REACH_M + GameRules.DEFAULT_STICK_LENGTH_M


# A dive starts from plain puckless skating with both buttons down; not while
# already down, carrying, or in any other state (a held block that becomes a
# stance + block is not a dive).
static func starts(stance_held: bool, block_held: bool, skating_without_puck: bool,
		down: bool) -> bool:
	return stance_held and block_held and skating_without_puck and not down


# The knockdown's fall model as a dive takes it (the constants above); the rest
# of the model is the knockdown's own.
static func fall_config(knockdown: KnockdownFallRules.Config) -> KnockdownFallRules.Config:
	var cfg := KnockdownFallRules.Config.new()
	cfg.buckle_seconds = PUSH_S
	cfg.fall_accel = knockdown.fall_accel
	cfg.settle_angle = deg_to_rad(LIE_DEG)
	cfg.restitution = 0.0
	cfg.rest_omega = knockdown.rest_omega
	cfg.com_height = COM_HEIGHT_M
	cfg.max_entry_omega = TIP_RATE_RAD_S
	cfg.sprawl_in_seconds = knockdown.sprawl_in_seconds
	cfg.sprawl_splay = knockdown.sprawl_splay
	return cfg


# How far the tipped body has carried back from his skates along the layout, at
# `tilt` radians: what keeps the belt over his line.
static func com_carry_m(tilt: float) -> float:
	return COM_HEIGHT_M * sin(tilt)


# Lying, the skates are this far behind his line, and the block runs from them
# BLOCK_LENGTH_M out along the layout.
static func feet_back_m() -> float:
	return com_carry_m(deg_to_rad(LIE_DEG))


# How far past his line the dive reaches across a lane.
static func reach_m() -> float:
	return BLOCK_LENGTH_M - feet_back_m()


# The layout (unit XZ, world) toward the cursor; along `fallback` when the cursor
# sits on the body.
static func layout_dir(body_pos: Vector3, cursor: Vector3, fallback: Vector2) -> Vector2:
	var to_cursor := Vector2(cursor.x - body_pos.x, cursor.z - body_pos.z)
	if to_cursor.length_squared() > 1e-4:
		return to_cursor.normalized()
	return fallback.normalized() if fallback.length_squared() > 1e-8 else Vector2(0.0, -1.0)


# The point on the lying body's axis (`a`→`b`, XZ) nearest a puck that moved from
# `puck_prev` to `puck_curr` this tick: the body point a swept block test and its
# contact normal are taken against, as a standing block's are against its axis.
static func block_point(puck_prev: Vector3, puck_curr: Vector3, a: Vector2,
		b: Vector2) -> Vector2:
	var p0 := Vector2(puck_prev.x, puck_prev.z)
	var p1 := Vector2(puck_curr.x, puck_curr.z)
	var cross: Vector2 = _crossing(p0, p1, a, b)
	if cross.is_finite():
		return cross
	var best: Vector2 = a
	var best_d: float = _gap_to(a, p0, p1)
	var q: Vector2 = b
	var d: float = _gap_to(q, p0, p1)
	if d < best_d:
		best_d = d
		best = q
	q = _closest_on(p0, a, b)
	d = _gap_to(q, p0, p1)
	if d < best_d:
		best_d = d
		best = q
	q = _closest_on(p1, a, b)
	if _gap_to(q, p0, p1) < best_d:
		best = q
	return best


static func _gap_to(q: Vector2, p0: Vector2, p1: Vector2) -> float:
	return _closest_on(q, p0, p1).distance_squared_to(q)


static func _crossing(p0: Vector2, p1: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var r: Vector2 = p1 - p0
	var s: Vector2 = b - a
	var denom: float = r.cross(s)
	if absf(denom) < 1e-10:
		return Vector2.INF
	var t: float = (a - p0).cross(s) / denom
	var u: float = (a - p0).cross(r) / denom
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return Vector2.INF
	return a + s * u


static func _closest_on(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	var t: float = 0.0 if len_sq < 1e-10 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t

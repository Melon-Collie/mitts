class_name BoardCheckRules
extends RefCounted

# Whether a body check drives its victim into the boards, and where he meets
# them: what the board reactions (the heavy thud, the glass rattle, the snow off
# the boards, the fans at the glass) fire from. Cosmetic, worked out on every
# machine from the same landed check, so nothing of it is sent.

# How far off the boards (the kickplate's inner face) a victim may stand and
# still be driven into them: half a body's width, a stride of knockback, and the
# glass he leans into above the kickplate.
const REACH_M: float = 1.3
# The push must head at the boards, within this of square on (cos 60°): a check
# along the wall rubs, it does not drive anyone into it.
const MIN_INTO_COS: float = 0.5
# The point of contact sits at shoulder height, on the glass above the boards.
const CONTACT_HEIGHT_M: float = 1.35

const NONE := Vector3(INF, INF, INF)


# The point on the boards a check on a victim at `pos` pushed along `hit_dir`
# drives him into, at CONTACT_HEIGHT_M; NONE when it does not.
static func contact(pos: Vector3, hit_dir: Vector3) -> Vector3:
	var xz := Vector2(pos.x, pos.z)
	if GameRules.distance_to_rink_inner(xz) > REACH_M:
		return NONE
	var outward: Vector2 = outward_at(xz)
	var push := Vector2(hit_dir.x, hit_dir.z)
	if push.length_squared() < 1e-6 or push.normalized().dot(outward) < MIN_INTO_COS:
		return NONE
	var at: Vector2 = nearest_board(xz)
	return Vector3(at.x, CONTACT_HEIGHT_M, at.y)


# The boards' nearest point to `xz`, inside the rink: the nearer wall's, or the
# corner's arc in a corner quadrant.
static func nearest_board(xz: Vector2) -> Vector2:
	var qx: float = absf(xz.x) - GameRules.CORNER_CENTER_X
	var qz: float = absf(xz.y) - GameRules.CORNER_CENTER_Z
	if qx > 0.0 and qz > 0.0:
		var centre := Vector2(signf(xz.x) * GameRules.CORNER_CENTER_X,
				signf(xz.y) * GameRules.CORNER_CENTER_Z)
		return centre + (xz - centre).normalized() * GameRules.INNER_CORNER_RADIUS
	if GameRules.INNER_HALF_WIDTH - absf(xz.x) < GameRules.INNER_HALF_LENGTH - absf(xz.y):
		return Vector2(signf(xz.x) * GameRules.INNER_HALF_WIDTH, xz.y)
	return Vector2(xz.x, signf(xz.y) * GameRules.INNER_HALF_LENGTH)


# The unit direction from `xz` out to its nearest board.
static func outward_at(xz: Vector2) -> Vector2:
	var qx: float = absf(xz.x) - GameRules.CORNER_CENTER_X
	var qz: float = absf(xz.y) - GameRules.CORNER_CENTER_Z
	if qx > 0.0 and qz > 0.0:
		var centre := Vector2(signf(xz.x) * GameRules.CORNER_CENTER_X,
				signf(xz.y) * GameRules.CORNER_CENTER_Z)
		return (xz - centre).normalized()
	if GameRules.INNER_HALF_WIDTH - absf(xz.x) < GameRules.INNER_HALF_LENGTH - absf(xz.y):
		return Vector2(signf(xz.x), 0.0)
	return Vector2(0.0, signf(xz.y))

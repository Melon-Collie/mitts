class_name ReachPurposeRules

# How much a skater without the puck means his stick's reach, 0..1. Two things
# say so: the puck is coming within reach (purpose), or he has put his cursor
# where his stick can go (intent). A cursor far off is where he is looking, not
# where he is reaching, so the stick rests; the callers take the greater.

# Whether a skater's stick has something to reach for, 0..1: the puck's nearest
# approach to the rim of his reach over the next `lookahead` seconds, past which
# a stretch buys nothing. 1 once that approach is within `near` of the rim (a
# puck on his own blade is inside it), 0 from `far` beyond it, smoothstepped
# between. Positions are XZ about the body's origin; `rim` is the farthest the
# blade gets from it.
static func purpose(body_xz: Vector2, rim: float, puck_xz: Vector2, puck_vel_xz: Vector2,
		lookahead: float, near: float, far: float) -> float:
	var path: Vector2 = puck_vel_xz * lookahead
	var t: float = 0.0
	var len_sq: float = path.length_squared()
	if len_sq > 1e-8:
		t = clampf((body_xz - puck_xz).dot(path) / len_sq, 0.0, 1.0)
	var gap: float = (puck_xz + path * t - body_xz).length() - rim
	return 1.0 - smoothstep(near, far, gap)


# Whether the cursor itself asks for the reach, 0..1: 1 with the cursor inside
# the rim or within `near` past it (a blade placed, or a reach asked for), 0
# from `far` past it, smoothstepped between.
static func intent(body_xz: Vector2, rim: float, cursor_xz: Vector2, near: float,
		far: float) -> float:
	return 1.0 - smoothstep(near, far, (cursor_xz - body_xz).length() - rim)

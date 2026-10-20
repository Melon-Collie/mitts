class_name ReachPurposeRules

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

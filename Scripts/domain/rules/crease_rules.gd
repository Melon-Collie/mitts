class_name CreaseRules

# Pure geometry for the goalie crease (NHL D-shape). No engine deps — fully
# unit-testable. Used by PuckController to detect a puck stuck in the crease
# (e.g. wedged under the goalie) and shove it back into play.
#
# Crease shape: arc of radius ARC_RADIUS centered on the goal center, capped
# by straight sides at ±HALF_WIDTH. The straight sides extend STRAIGHT_DEPTH
# inward from the goal line; the arc connects their tops. Matches the painted
# crease in HockeyRink._draw_crease_fill.

const ARC_RADIUS: float = 1.83        # 6 ft
const HALF_WIDTH: float = 1.22        # 4 ft to either side of goal center
const STRAIGHT_DEPTH: float = 1.37    # 4.5 ft straight-side depth (here for parity with the painted shape;
                                       # not needed for in/out math because ARC_RADIUS > STRAIGHT_DEPTH)

# Returns true if the XZ position lies within either team's goalie crease.
# Crease centers sit at (0, ±GameRules.GOAL_LINE_Z), opening toward center ice.
static func is_in_crease(xz: Vector2) -> bool:
	var goal_z_sign: float = signf(xz.y)
	if goal_z_sign == 0.0:
		return false
	if absf(xz.x) > HALF_WIDTH:
		return false
	var goal_z: float = goal_z_sign * GameRules.GOAL_LINE_Z
	# dy_inward: positive when xz is on the rink (center) side of the goal line.
	var dy_inward: float = (xz.y - goal_z) * -goal_z_sign
	if dy_inward < 0.0:
		return false
	return xz.x * xz.x + dy_inward * dy_inward <= ARC_RADIUS * ARC_RADIUS

# Returns the unit XZ direction from the nearest goal center outward toward xz.
# Caller should ensure xz is inside a crease (or at least on the correct half);
# the goal-center pick uses signf(xz.y).
static func outward_direction(xz: Vector2) -> Vector2:
	var goal_z_sign: float = signf(xz.y)
	if goal_z_sign == 0.0:
		# Pathological: no clear half. Push toward +Z by default.
		return Vector2(0.0, 1.0)
	var goal_z: float = goal_z_sign * GameRules.GOAL_LINE_Z
	var dir: Vector2 = Vector2(xz.x, xz.y - goal_z)
	if dir.length_squared() < 0.0001:
		# Puck exactly at goal center: push toward center ice.
		return Vector2(0.0, -goal_z_sign)
	return dir.normalized()

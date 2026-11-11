class_name AIPossessionFloor

# What keeping the puck at a spot is worth before anything specific is on: a
# floor by how far up the ice the spot is, plus a bonus for how much net it sees
# from their zone (docs/possession-floor-plan.md §2.1). Pure functions of
# position, in the shot field's unit, read for either side by the goal it
# attacks; neither term reads the goalie or the defence.

# ── Feel tunables (DECISIONS.md §7) ─────────────────────────────────────────
# The floor at each line, linear between them and flat past the goal lines.
const FLOOR_OWN_GOAL_LINE: float = -0.012
const FLOOR_OWN_BLUE_LINE: float = 0.004
const FLOOR_THEIR_BLUE_LINE: float = 0.023
const FLOOR_THEIR_GOAL_LINE: float = 0.021
# The slot bonus's plateau, reached at the mouth a spot SLOT_REF_M straight out
# sees, and held closer in.
const SLOT_BONUS: float = 0.05
const SLOT_REF_M: float = 6.0

# No spot's continuation exceeds this (test_possession_floor.gd sweeps it): the
# most any possession reads, which bounds what a turnover can pay the loser.
const MOST_CONTINUATION: float = FLOOR_THEIR_BLUE_LINE + SLOT_BONUS

static var _ref_mouth: float = 2.0 * atan(GameRules.NET_HALF_WIDTH / SLOT_REF_M)


# The floor at `pos` for the side attacking `goal`.
static func floor_at(pos: Vector3, goal: Vector3) -> float:
	return _floor_up(pos.z * signf(goal.z))


# The floor `a` metres toward the attacking goal from centre ice.
static func _floor_up(a: float) -> float:
	var g: float = GameRules.GOAL_LINE_Z
	var b: float = GameRules.BLUE_LINE_Z
	if a <= -g:
		return FLOOR_OWN_GOAL_LINE
	if a <= -b:
		return lerpf(FLOOR_OWN_GOAL_LINE, FLOOR_OWN_BLUE_LINE, (a + g) / (g - b))
	if a <= b:
		return lerpf(FLOOR_OWN_BLUE_LINE, FLOOR_THEIR_BLUE_LINE, (a + b) / (2.0 * b))
	if a <= g:
		return lerpf(FLOOR_THEIR_BLUE_LINE, FLOOR_THEIR_GOAL_LINE, (a - b) / (g - b))
	return FLOOR_THEIR_GOAL_LINE


# The angle (radians) the net mouth covers seen from `pos`, between the posts of
# `goal`: 0 on or behind its goal line.
static func mouth_angle(pos: Vector3, goal: Vector3) -> float:
	var out: float = (goal.z - pos.z) * signf(goal.z)
	if out <= 0.0:
		return 0.0
	var x: float = pos.x - goal.x
	var h: float = GameRules.NET_HALF_WIDTH
	return atan2(h - x, out) - atan2(-h - x, out)


# The slot bonus at `pos`: SLOT_BONUS × its mouth against the mouth SLOT_REF_M
# straight out, capped there, in their zone only (the line test is
# AIActionScoring.in_offensive_zone's, which a leaf may not read).
static func slot_bonus(pos: Vector3, goal: Vector3) -> float:
	if pos.z * signf(goal.z) <= GameRules.BLUE_LINE_Z:
		return 0.0
	return SLOT_BONUS * minf(1.0, mouth_angle(pos, goal) / _ref_mouth)


# C(spot): what possession at `pos` is worth to the side attacking `goal` over
# the rest of the possession, kept.
static func continuation(pos: Vector3, goal: Vector3) -> float:
	return floor_at(pos, goal) + slot_bonus(pos, goal)


# The most a turnover can pay the side attacking a goal that loses the puck
# anywhere no further toward that goal than `up_ice_m` (floor_at's measure) and no
# nearer its centre than `net_dist_m`: the most max(C, −C_opp) reads there
# (AIPossessionValue.base_ceiling), which a search's exact prunes bound a loss by.
# Outside their zone the floor rises toward their line and the other side's
# continuation is at least its floor at our line; inside it, the slot bonus is
# at most what the mouth subtends from `net_dist_m` straight out.
static func most_lost(up_ice_m: float, net_dist_m: float) -> float:
	if up_ice_m <= GameRules.BLUE_LINE_Z:
		return maxf(_floor_up(up_ice_m), -FLOOR_OWN_BLUE_LINE)
	var h: float = GameRules.NET_HALF_WIDTH
	var mouth: float = PI if net_dist_m <= h else 2.0 * atan(h / net_dist_m)
	return FLOOR_THEIR_BLUE_LINE + SLOT_BONUS * minf(1.0, mouth / _ref_mouth)

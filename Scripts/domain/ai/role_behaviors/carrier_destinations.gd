class_name AICarrierDestinations
extends RefCounted

# The places a carry can be FOR (docs/hybrid-carry-plan.md): the menu of
# destinations legal from where the carrier is, and the one he is carrying to.
# AICarrierCarrySearch prices the menu each search and hands the totals back to
# choose(), which keeps the incumbent unless a challenger beats it by the
# action hysteresis margin, so the plan does not flicker between two near-equal
# places.
#
# Left and right are the carrier's, facing the goal he attacks.

enum Kind {
	SLOT,
	WIDE_LEFT, WIDE_RIGHT,
	EXIT_LEFT, EXIT_RIGHT,
	WALKOUT_LEFT, WALKOUT_RIGHT,
	WHEEL_LEFT, WHEEL_RIGHT,
	REGROUP,
}

# The wide lanes, a body's width plus a stride off the boards. Outside the
# attacking zone they are the entry, a stride past the blue line; inside it, the
# half-wall at the faceoff dots.
const WIDE_LANE_WALL_INSET_M: float = 2.0
const WIDE_ENTRY_LEAD_M: float = 3.0
# Regroup: back to just outside our own blue line on the neutral-zone side —
# never into our zone — at least a lane in from the boards.
const REGROUP_LINE_GAP_M: float = 2.0
const REGROUP_WALL_INSET_M: float = 4.0
# Zone exits, our defensive zone only: up each boards lane to a stride past our
# blue line, a completed exit. The slot runs through centre ice where a forecheck
# sets up, so without these a deep carrier with a clogged middle has only short
# steps and the backpass.
const EXIT_WALL_INSET_M: float = 2.0
const EXIT_NZ_LEAD_M: float = 3.0
# Post walkouts, behind either goal line: one just outside each post, a step onto
# the rink side of the line, where every other route out front crosses the cage.
# The lateral clearance is post half-span + a carried body's half-width + blade
# slop.
const WALKOUT_POST_CLEARANCE_M: float = 0.9
const WALKOUT_FRONT_M: float = 0.7
# The wheel (5v5 — breakout plan §B): from behind our own goal line, around the
# BACK of the cage and out the far half-wall, the escape when the retriever has a
# step on the chaser. Exit depth = the top of the low battle ice
# (AIZoneCoverage.LOW_ZONE_DEPTH_M's value).
const WHEEL_EXIT_UP_ICE_M: float = 8.0
# A destination this close is where the carrier already is: standing still is
# that plan, and it is always in the compete. The slot is exempt: the drive at
# the net is still the plan from on it.
const ARRIVED_M: float = 2.0

# The menu, index-matched, refilled by fill().
var kinds: Array[int] = []
var spots: Array[Vector3] = []

# The destination being carried to; -1 before the first choice of a possession.
var chosen_kind: int = -1
var chosen_spot: Vector3 = Vector3.INF
var chosen_total: float = -INF


func reset() -> void:
	chosen_kind = -1
	chosen_spot = Vector3.INF
	chosen_total = -INF


func fill(ctx: RoleContext) -> void:
	kinds.clear()
	spots.clear()
	var self_pos: Vector3 = ctx.self_pos
	var own: float = ctx.own_goal_dir
	# +X is the carrier's left when he attacks +Z.
	var left: float = -own
	kinds.append(Kind.SLOT)
	spots.append(AICarrierField.slot_anchor(own))
	var in_own_zone: bool = own * self_pos.z > GameRules.BLUE_LINE_Z
	var wide_x: float = GameRules.RINK_HALF_WIDTH - WIDE_LANE_WALL_INSET_M
	if AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos):
		_add_pair(ctx, Kind.WIDE_LEFT, Kind.WIDE_RIGHT, left * wide_x,
				-own * GameRules.ICING_FACEOFF_DOT_Z)
	elif not in_own_zone:
		_add_pair(ctx, Kind.WIDE_LEFT, Kind.WIDE_RIGHT, left * wide_x,
				-own * (GameRules.BLUE_LINE_Z + WIDE_ENTRY_LEAD_M))
		var lane_x: float = GameRules.RINK_HALF_WIDTH - REGROUP_WALL_INSET_M
		_add(ctx, Kind.REGROUP, Vector3(clampf(self_pos.x, -lane_x, lane_x), 0.0,
				own * (GameRules.BLUE_LINE_Z - REGROUP_LINE_GAP_M)))
	var exit_x: float = GameRules.RINK_HALF_WIDTH - EXIT_WALL_INSET_M
	if in_own_zone:
		_add_pair(ctx, Kind.EXIT_LEFT, Kind.EXIT_RIGHT, left * exit_x,
				own * (GameRules.BLUE_LINE_Z - EXIT_NZ_LEAD_M))
	if absf(self_pos.z) <= GameRules.GOAL_LINE_Z:
		return
	_add_pair(ctx, Kind.WALKOUT_LEFT, Kind.WALKOUT_RIGHT,
			left * (GameRules.NET_HALF_WIDTH + WALKOUT_POST_CLEARANCE_M),
			signf(self_pos.z) * (GameRules.GOAL_LINE_Z - WALKOUT_FRONT_M))
	if ctx.team_size < 5 or own * self_pos.z <= 0.0:
		return
	var wheel_z: float = own * (GameRules.GOAL_LINE_Z - WHEEL_EXIT_UP_ICE_M)
	for side: float in [1.0, -1.0]:
		var wheel := Vector3(side * left * exit_x, 0.0, wheel_z)
		# Only where the cage blocks the straight route: a side the straight line
		# reaches is the exit or a near candidate's.
		if AINetObstacle.carry_path_blocked_by_net(self_pos, wheel):
			_add(ctx, Kind.WHEEL_LEFT if side > 0.0 else Kind.WHEEL_RIGHT, wheel)


static func is_walkout(kind: int) -> bool:
	return kind == Kind.WALKOUT_LEFT or kind == Kind.WALKOUT_RIGHT


static func is_wheel(kind: int) -> bool:
	return kind == Kind.WHEEL_LEFT or kind == Kind.WHEEL_RIGHT


# Picks the destination from the menu's `totals` (index-matched, -INF for one
# that cannot be carried to). The incumbent's positive total is scaled by
# (1 + ACTION_HYSTERESIS_MARGIN_FRAC) for the comparison only; chosen_total is
# the honest one.
func choose(totals: Array[float]) -> void:
	var best_i: int = -1
	var best_key: float = -INF
	for i: int in kinds.size():
		var t: float = totals[i]
		if t == -INF:
			continue
		var key: float = t
		if kinds[i] == chosen_kind and t > 0.0:
			key = t * (1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC)
		if key > best_key:
			best_key = key
			best_i = i
	if best_i < 0:
		reset()
		return
	chosen_kind = kinds[best_i]
	chosen_spot = spots[best_i]
	chosen_total = totals[best_i]


func _add_pair(ctx: RoleContext, left_kind: int, right_kind: int, left_x: float,
		z: float) -> void:
	_add(ctx, left_kind, Vector3(left_x, 0.0, z))
	_add(ctx, right_kind, Vector3(-left_x, 0.0, z))


func _add(ctx: RoleContext, kind: int, spot: Vector3) -> void:
	if ctx.self_pos.distance_to(spot) < ARRIVED_M:
		return
	kinds.append(kind)
	spots.append(spot)

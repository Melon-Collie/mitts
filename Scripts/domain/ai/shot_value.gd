class_name AIShotValue

# THE SEAM. Every "how good is a shot from here" the carrier ranks — shooting
# now, what a carry arrives at, a pass receiver, the cost of handing the puck
# over — asks here, so all of them price a shot the same way (the currency rule:
# Scripts/domain/ai/CLAUDE.md → "One currency across the carrier's compete").
#
# The answer is the odds of scoring on today's goalie, read from the field
# measured off the live GoalieController (AIShotOdds;
# docs/shot-currency-plan.md). Nothing here models him.
#
# The keeper comes in one of three ways:
#   now        — as he stands: where he is, how fast he is moving across, whether
#                he is down. Out of his home range (pulled, or chasing a puck) the
#                net is empty, and the odds are only where the puck lands.
#   set_keeper — square and set on the release: what a carry he tracks the whole
#                way, or a drive, arrives at.
#   feed       — square on the passer as the pass leaves; what he manages over the
#                flight is the goalie's own answer. Out of his home range the net
#                is empty, as for `now`. A deflection is a feed whose line is not
#                picked.


# `stance` is an AIShotOdds.Stance; `keeper_yaw` his rotation_y, NAN when not read.
static func now(release: Vector3, goal: Vector3, keeper_pos: Vector3,
		keeper_vel_x: float, stance: int, keeper_yaw: float = NAN) -> float:
	if Vector2(keeper_pos.x - goal.x, keeper_pos.z - goal.z).length() \
			> AIGoalieModel.GOALIE_HOME_M:
		return AIShotOdds.empty_net(release, goal)
	return AIShotOdds.shot_now(release, goal, keeper_pos, keeper_vel_x, stance, keeper_yaw)


# `now` with the crossing scattering by `spread_rad`: what the xG stat reads, at
# the shot's context spread rather than the reference. Once per shot.
static func now_at_spread(release: Vector3, goal: Vector3, keeper_pos: Vector3,
		keeper_vel_x: float, stance: int, spread_rad: float,
		keeper_yaw: float = NAN, query: AIShotOdds.Query = null) -> float:
	if Vector2(keeper_pos.x - goal.x, keeper_pos.z - goal.z).length() \
			> AIGoalieModel.GOALIE_HOME_M:
		return AIShotOdds.empty_net(release, goal, spread_rad)
	return AIShotOdds.shot_now_at_spread(release, goal, keeper_pos, keeper_vel_x, stance,
			spread_rad, keeper_yaw, query)


static func set_keeper(release: Vector3, goal: Vector3) -> float:
	return AIShotOdds.shot_set(release, goal)


# `keeper_pos` INF: none replicated, taken square on the passer at his resting
# depth.
static func feed(passer: Vector3, receiver: Vector3, speed: float, goal: Vector3,
		keeper_pos: Vector3, one_timer: bool) -> float:
	var keeper: Vector3 = _feed_keeper(passer, goal, keeper_pos)
	if not keeper.is_finite():
		return AIShotOdds.empty_net(receiver, goal)
	return AIShotOdds.feed(passer, receiver, speed, goal, keeper, one_timer)


# A shot from `passer` redirected at `receiver`: feed's keeper, the line not
# picked (AIShotOdds.feed_unaimed).
static func deflection(passer: Vector3, receiver: Vector3, speed: float, goal: Vector3,
		keeper_pos: Vector3) -> float:
	var keeper: Vector3 = _feed_keeper(passer, goal, keeper_pos)
	if not keeper.is_finite():
		return AIShotOdds.empty_net(receiver, goal)
	return AIShotOdds.feed_unaimed(passer, receiver, speed, goal, keeper)


# The keeper a feed is read against, or INF when he is out of his home range and
# the net is empty.
static func _feed_keeper(passer: Vector3, goal: Vector3, keeper_pos: Vector3) -> Vector3:
	if not keeper_pos.is_finite():
		return AIGoalieModel.goalie_squared_pos(goal - Vector3(0.0, 0.0,
				signf(goal.z) * AIGoalieModel.GOALIE_RESTING_DEPTH_M), goal, passer)
	if Vector2(keeper_pos.x - goal.x, keeper_pos.z - goal.z).length() \
			> AIGoalieModel.GOALIE_HOME_M:
		return Vector3.INF
	return keeper_pos

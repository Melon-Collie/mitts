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
#                flight is the goalie's own answer.


# `stance` is an AIShotOdds.Stance.
static func now(release: Vector3, goal: Vector3, keeper_pos: Vector3,
		keeper_vel_x: float, stance: int) -> float:
	if Vector2(keeper_pos.x - goal.x, keeper_pos.z - goal.z).length() \
			> AIGoalieModel.GOALIE_HOME_M:
		return AIShotOdds.empty_net(release, goal)
	return AIShotOdds.shot_now(release, goal, keeper_pos, keeper_vel_x, stance)


static func set_keeper(release: Vector3, goal: Vector3) -> float:
	return AIShotOdds.shot_set(release, goal)


static func feed(passer: Vector3, receiver: Vector3, speed: float, goal: Vector3,
		keeper_pos: Vector3, one_timer: bool) -> float:
	return AIShotOdds.feed(passer, receiver, speed, goal, keeper_pos, one_timer)

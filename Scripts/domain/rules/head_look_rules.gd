class_name HeadLookRules
extends RefCounted

# Where a skater's head turns. Read from replicated state alone, so every peer
# turns a skater's head the same way; the shooter's aim is deliberately not an
# input, since only the simulating peer has it.

enum Target { NONE, PUCK, NET }

# A puck this far outside the boards is parked off the rink (drills stash it
# between reps), not in play.
const PUCK_IN_PLAY_MARGIN_M: float = 1.0
# Inside this bearing of straight behind, the head keeps the side it is turned
# to: there the bearing wraps from +π to −π, which would swing it limit to limit.
const BEHIND_HOLD_RAD: float = PI * 5.0 / 6.0


# A carrier, or a shooter whose shot is aimed, looks at the net; everyone else
# watches the puck, including a one-timer wind-up, which is waiting on the feed.
static func target(carrying: bool, aiming_shot: bool, puck_in_play: bool) -> Target:
	if carrying or aiming_shot:
		return Target.NET
	return Target.PUCK if puck_in_play else Target.NONE


static func is_puck_in_play(puck_pos: Vector3) -> bool:
	return GameRules.distance_to_rink_inner(Vector2(puck_pos.x, puck_pos.z)) \
			> -PUCK_IN_PLAY_MARGIN_M


# The centre of the goal mouth `team_id` shoots at.
static func attacking_net(team_id: int) -> Vector3:
	return Vector3(0.0, 0.0, XGBaseline.attacking_goal_z(team_id))


# Head yaw (radians, + toward local +X) toward a target in the upper body's
# frame, within ±max_rad of straight ahead. `current` is the head's yaw now.
static func yaw(target_local: Vector3, current: float, max_rad: float) -> float:
	if target_local.x * target_local.x + target_local.z * target_local.z < 0.0001:
		return 0.0
	var bearing: float = atan2(target_local.x, -target_local.z)
	if absf(bearing) > BEHIND_HOLD_RAD and bearing * current < 0.0:
		bearing = -bearing
	return clampf(bearing, -max_rad, max_rad)

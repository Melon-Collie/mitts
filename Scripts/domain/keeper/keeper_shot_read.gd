class_name KeeperShotRead
extends RefCounted

# What he reads of a shot: nothing until he has watched the puck's own flight
# for his read's delay, then the flight as it is, carried on — its line, and
# under gravity its fall. His legs answer after the leg read, his hands after
# the arm read; a puck touched on the way (a tip, a deflection) is a new shot
# he has to read again. No aim before the release: what the shooter's body
# shows is perception's (docs/goalie-rebuild-plan.md §3.1), and none of it here.
#
# The net frame throughout, as KeeperPositioning reads it: origin at the goal
# line's centre, x across, z back into the net, y up from the ice, the puck by
# its centre. Deterministic: he is beaten when the time to answer runs out, not
# by a draw.

# The ice under a puck lying flat: its centre this high.
const ON_ICE_Y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
# How far a puck is lifted, or rising, before it is in the air.
const AIRBORNE_M: float = 0.002

var leg_delay_s: float = GoalieSkillProfile.hard().reaction_delay_s
var arm_delay_s: float = GoalieSkillProfile.hard().arm_reaction_delay_s

# Seconds since the release or the last touch; below zero, no shot.
var age: float = -1.0
# The puck as he sees it now.
var at := Vector3.ZERO
var velocity := Vector3.ZERO


# A shot leaves a stick, or the puck is touched on its way: read from the start.
func start() -> void:
	age = 0.0


func stop() -> void:
	age = -1.0


func reading() -> bool:
	return age >= 0.0


func legs_read() -> bool:
	return age >= leg_delay_s


func arms_read() -> bool:
	return age >= arm_delay_s


func step(dt: float, puck_at: Vector3, puck_velocity: Vector3) -> void:
	at = puck_at
	velocity = puck_velocity
	if age >= 0.0:
		age += dt


# Where the puck will be `t` seconds on: along its line, falling under gravity
# while it is in the air, and sliding on once it lands.
func position_in(t: float) -> Vector3:
	var p: Vector3 = at + velocity * t
	if at.y > ON_ICE_Y + AIRBORNE_M or velocity.y > 0.0:
		p.y = maxf(at.y + velocity.y * t - 0.5 * GameRules.GRAVITY_M_S2 * t * t, ON_ICE_Y)
	else:
		p.y = ON_ICE_Y
	return p


# Seconds until it reaches the goal line, or INF when it is not going there.
func time_to_line() -> float:
	if velocity.z <= 0.0 or at.z >= 0.0:
		return INF
	return -at.z / velocity.z


# Whether it goes in if nothing stops it: across the goal line inside the iron
# and under the bar.
func on_net() -> bool:
	var t: float = time_to_line()
	if t == INF:
		return false
	var p: Vector3 = position_in(t)
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	return absf(p.x) < GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - r \
			and p.y < GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS - r

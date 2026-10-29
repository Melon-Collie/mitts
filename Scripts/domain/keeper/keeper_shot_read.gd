class_name KeeperShotRead
extends RefCounted

# What he reads of a shot: nothing until he has watched the puck's own flight
# for his read's delay, then the flight as it is, carried on — its line, and
# under gravity its fall. His legs and his hands answer after his read, or the
# primed read for a release off a puck he held in his eyes long enough
# (KeeperPlayRead.primed); a puck touched on the way (a tip, a deflection)
# is a new shot he has to read again, cold. No aim before the release: what the
# shooter's body shows is perception's (docs/goalie-rebuild-plan.md §3.1).
#
# The net frame throughout, as KeeperPositioning reads it: origin at the goal
# line's centre, x across, z back into the net, y up from the ice, the puck by
# its centre. Deterministic: he is beaten when the time to answer runs out, not
# by a draw. A shot that beats his read, into the net or off him before he has
# read it, is still read once he has watched it his read's time: the flight as
# it left the stick (`rewind`), so he answers it late.

# The ice under a puck lying flat: its centre this high.
const ON_ICE_Y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
# How far a puck is lifted, or rising, before it is in the air.
const AIRBORNE_M: float = 0.002

var leg_delay_s: float = GoalieSkillProfile.hard().reaction_delay_s
var primed_delay_s: float = GoalieSkillProfile.hard().prearmed_reaction_delay_s

# Seconds since the release or the last touch; below zero, no shot.
var age: float = -1.0
# The puck as he sees it now.
var at := Vector3.ZERO
var velocity := Vector3.ZERO
var _primed: bool = false
# Whether the next look is his first of this flight.
var _first: bool = false
# The flight as he first saw it, at the release or the touch.
var _from := Vector3.ZERO
var _from_velocity := Vector3.ZERO


# A shot leaves a stick, or the puck is touched on its way: read from the start,
# on the primed read if he had the save programmed; `seen_s` ago for a shot
# whose shooter saw it leave that long before it reached the host (lag comp).
func start(primed: bool = false, seen_s: float = 0.0) -> void:
	age = maxf(seen_s, 0.0)
	_primed = primed
	_first = true


func stop() -> void:
	age = -1.0


func reading() -> bool:
	return age >= 0.0


func legs_read() -> bool:
	return age >= read_s()


# How long after the release or the touch he has read it.
func read_s() -> float:
	return minf(leg_delay_s, primed_delay_s) if _primed else leg_delay_s


func step(dt: float, puck_at: Vector3, puck_velocity: Vector3) -> void:
	at = puck_at
	velocity = puck_velocity
	if _first:
		_first = false
		_from = at
		_from_velocity = velocity
	if age >= 0.0:
		age += dt


# Back to the flight as he first saw it, for a shot that beat his read.
func rewind() -> void:
	at = _from
	velocity = _from_velocity


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

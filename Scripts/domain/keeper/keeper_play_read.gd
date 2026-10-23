class_name KeeperPlayRead
extends RefCounted

# What he sees of the play before a shot: the puck where he last read it,
# carried on along the motion he read it with, the skaters it could be passed
# to, and where a pass he sees will be met. Pure, stepped at the tick, in the
# net's frame (x across, z back into the net).
#
# His read of the play lags it by his leg read (`delay_s`, the tier's), so a
# puck that holds its line is seen where it is, and one that changes direction
# is seen going the old way until the read catches up: a deke beats him by
# exactly his read. The motion is the carrier's body when the puck is carried,
# since a stickhandle swings the puck about a body that holds its line; the
# puck's own when it is loose. A wind-up is read the same way, late by his
# read, and how long he has watched it is what primes the save (`primed`).

# The longest read any tier has, kept at the physics tick.
const MOST_S: float = 0.6
const TICK_HZ: float = 120.0
# How close to a pass's lane a defender's stick takes it away: a stick's length.
const LANE_REACH_M: float = GameRules.DEFAULT_STICK_LENGTH_M
# A wind-up watched this long has the save programmed before the release: the
# old goalie's quiet-eye read (Panchuk & Vickers, a save prepared during the
# fixation and executed ballistically).
const PRIME_S: float = 0.40
# A carried puck swings about its carrier faster than his feet can follow it
# (a stickhandle, a stick's reach either way a few times a second): he reads it
# where it is on average, its place off the carrier followed over the time his
# glide closes a gap in, and the carrier's own skating as it is.
const HANDLE_S: float = KeeperFootwork.CLOSE_S
const NO_CARRIER := Vector2(INF, INF)

var delay_s: float = GameRules.DEFAULT_GOALIE_REACTION_DELAY_S
var primed_delay_s: float = GoalieSkillProfile.hard().prearmed_reaction_delay_s

# The puck as he reads it, and its motion; whether he sees the shooter winding
# up with it on his blade, and for how long he has watched that.
var puck := Vector2.ZERO
var motion := Vector2.ZERO
# Whether he sees it loose: a pass he has not yet seen caught is still one.
var loose: bool = true
# Whether it is carried by one of theirs, who can shoot it now.
var theirs: bool = false
var winding_up: bool = false
var watched_s: float = 0.0
# The attackers off the puck it could be passed to, through a lane no defender's
# stick reaches, in front of the goal line and inside the blue line.
var receivers := PackedVector2Array()
# A loose puck's line read to the first opposing stick it reaches before it
# stops (GoaliePassRead): where that stick meets it, and in how long; none,
# it meets no one.
var meets: bool = false
var meet := Vector2.ZERO
var meet_s: float = INF

# The carried puck's place off its carrier as he follows it.
var _handle := Vector2.ZERO
var _carried: bool = false
var _reception := GoaliePassRead.Reception.new()
var _sticks := PackedVector3Array()

# What he has watched, a tick a sample, oldest overwritten.
var _at := PackedVector2Array()
var _moving := PackedVector2Array()
var _winding := PackedByteArray()
var _loose := PackedByteArray()
var _head: int = -1
var _count: int = 0


func _init() -> void:
	var ticks: int = ceili(MOST_S * TICK_HZ) + 1
	_at.resize(ticks)
	_moving.resize(ticks)
	_winding.resize(ticks)
	_loose.resize(ticks)


func reset() -> void:
	_head = -1
	_count = 0
	receivers.clear()
	winding_up = false
	watched_s = 0.0
	meets = false
	theirs = false
	_carried = false


# One tick's look at the puck at `at` moving at `moving`, carried by a skater
# at `carrier` (NO_CARRIER loose) winding up a shot with it (`winding`), and
# what he reads from what he has watched.
func step(dt: float, at: Vector2, moving: Vector2, winding: bool = false, carrier: Vector2 = NO_CARRIER) -> void:
	var size: int = _at.size()
	_head = (_head + 1) % size
	_at[_head] = _handled(dt, at, carrier)
	_moving[_head] = moving
	_winding[_head] = 1 if winding else 0
	_loose[_head] = 1 if carrier == NO_CARRIER else 0
	_count = mini(_count + 1, size)
	var lag: int = mini(ceili(delay_s / maxf(dt, 1e-6) - 1e-6), _count - 1)
	var seen: int = (_head - lag + size) % size
	motion = _moving[seen]
	puck = _at[seen] + motion * (lag * dt)
	winding_up = _winding[seen] == 1
	loose = _loose[seen] == 1
	watched_s = watched_s + dt if winding_up else 0.0


# The puck at `at` as his feet follow it: off a carrier at `carrier`, where it
# is on average about him.
func _handled(dt: float, at: Vector2, carrier: Vector2) -> Vector2:
	if carrier == NO_CARRIER:
		_carried = false
		return at
	var off: Vector2 = at - carrier
	_handle = _handle.lerp(off, 1.0 - exp(-dt / HANDLE_S)) if _carried else off
	_carried = true
	return carrier + _handle


# Whether he has watched the wind-up long enough to have the save programmed.
func primed() -> bool:
	return watched_s >= PRIME_S


# How long his legs take to answer a shot released now.
func legs_s() -> float:
	return minf(delay_s, primed_delay_s) if primed() else delay_s


# The attackers off the puck (`attackers`) a pass from it could reach, given
# the defenders (`defenders`), both in the net's frame.
func read_receivers(attackers: PackedVector2Array, defenders: PackedVector2Array) -> void:
	receivers.clear()
	var blue: float = GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z
	for a: Vector2 in attackers:
		if a.y >= 0.0 or -a.y > blue:
			continue
		if _lane_open(puck, a, defenders):
			receivers.append(a)


# Where the puck, while he sees it loose, is met by the first of the opposing
# skaters at `attackers` its line reaches before it stops; one it is going
# away from (its passer) it does not.
func read_pass(attackers: PackedVector2Array) -> void:
	meets = false
	meet_s = INF
	if not loose:
		return
	_sticks.clear()
	for a: Vector2 in attackers:
		_sticks.append(Vector3(a.x, 0.0, a.y))
	var from := Vector3(puck.x, 0.0, puck.y)
	if not GoaliePassRead.find_reception(from, Vector3(motion.x, 0.0, motion.y), _sticks, LANE_REACH_M, INF,
			_reception):
		return
	var speed: float = motion.length()
	var along: float = speed * _reception.time
	var decel: float = GameRules.PUCK_ICE_DECEL_M_S2
	var slides: float = speed * speed * 0.5 / decel
	if along > slides:
		return
	meets = true
	meet = Vector2(_reception.point.x, _reception.point.z)
	meet_s = (speed - sqrt(maxf(speed * speed - 2.0 * decel * along, 0.0))) / decel


static func _lane_open(from: Vector2, to: Vector2, defenders: PackedVector2Array) -> bool:
	var lane: Vector2 = to - from
	var length_sq: float = lane.length_squared()
	for d: Vector2 in defenders:
		var t: float = clampf((d - from).dot(lane) / length_sq, 0.0, 1.0) if length_sq > 1e-8 else 0.0
		if d.distance_to(from + lane * t) <= LANE_REACH_M:
			return false
	return true

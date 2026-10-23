class_name KeeperPlayRead
extends RefCounted

# What he sees of the play before a shot: the puck where he last read it,
# carried on along the motion he read it with, and the skaters it could be
# passed to. Pure, stepped at the tick, in the net's frame (x across, z back
# into the net).
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

var delay_s: float = GameRules.DEFAULT_GOALIE_REACTION_DELAY_S

# The puck as he reads it, and its motion; whether he sees the shooter winding
# up with it on his blade, and for how long he has watched that.
var puck := Vector2.ZERO
var motion := Vector2.ZERO
var winding_up: bool = false
var watched_s: float = 0.0
# The attackers off the puck it could be passed to, through a lane no defender's
# stick reaches, in front of the goal line and inside the blue line.
var receivers := PackedVector2Array()

# What he has watched, a tick a sample, oldest overwritten.
var _at := PackedVector2Array()
var _moving := PackedVector2Array()
var _winding := PackedByteArray()
var _head: int = -1
var _count: int = 0


func _init() -> void:
	var ticks: int = ceili(MOST_S * TICK_HZ) + 1
	_at.resize(ticks)
	_moving.resize(ticks)
	_winding.resize(ticks)


func reset() -> void:
	_head = -1
	_count = 0
	receivers.clear()
	winding_up = false
	watched_s = 0.0


# One tick's look at the puck at `at` moving at `moving`, its carrier winding
# up a shot with it (`winding`), and what he reads from what he has watched.
func step(dt: float, at: Vector2, moving: Vector2, winding: bool = false) -> void:
	var size: int = _at.size()
	_head = (_head + 1) % size
	_at[_head] = at
	_moving[_head] = moving
	_winding[_head] = 1 if winding else 0
	_count = mini(_count + 1, size)
	var lag: int = mini(ceili(delay_s / maxf(dt, 1e-6) - 1e-6), _count - 1)
	var seen: int = (_head - lag + size) % size
	motion = _moving[seen]
	puck = _at[seen] + motion * (lag * dt)
	winding_up = _winding[seen] == 1
	watched_s = watched_s + dt if winding_up else 0.0


# Whether he has watched the wind-up long enough to have the save programmed.
func primed() -> bool:
	return watched_s >= PRIME_S


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


static func _lane_open(from: Vector2, to: Vector2, defenders: PackedVector2Array) -> bool:
	var lane: Vector2 = to - from
	var length_sq: float = lane.length_squared()
	for d: Vector2 in defenders:
		var t: float = clampf((d - from).dot(lane) / length_sq, 0.0, 1.0) if length_sq > 1e-8 else 0.0
		if d.distance_to(from + lane * t) <= LANE_REACH_M:
			return false
	return true

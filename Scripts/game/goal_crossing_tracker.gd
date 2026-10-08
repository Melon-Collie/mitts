class_name GoalCrossingTracker
extends RefCounted

# The puck-centre PATH that host goal detection tests, one segment per tick
# (GameManager._check_goal_crossing feeds each segment to every HockeyGoal).
#
# Loose and carried pucks are both tracked, so a stick tuck-in — the carrier
# pushing the puck across the line from the front of the mouth — is a real
# crossing with no rule of its own: the pinned puck collides with the net like any
# other body (SkaterController._collide_pinned_puck_with_net), so the only route
# into the cavity is the mouth.
#
# The pickup snap is part of that path too. The pin's first carried tick sweeps
# from the spot the puck was picked up from, and pickup itself cannot reach
# through the net (PuckInteractionRules), so a snap that crosses the line went
# through the mouth — a puck pulled onto a stick already in the net is in the net.

# Any single-tick puck travel beyond this (metres) is a reset/reposition, not a
# real crossing — the tracker reseeds and skips it. Far above any shot or blade
# speed at 120 Hz (~2 m/tick = 240 m/s); a faceoff/OOB reset jumps much further.
const MAX_TICK_TRAVEL: float = 2.0
# Tighter bound for a puck that was PINNED on both ends of the segment. A carried
# puck teleports to the carry target every tick, and that target can jump
# discontinuously while play is continuous — a forehand/backhand flip swings it
# around the body — and the straight segment across such a jump can pierce the
# goal-line plane inside the mouth while the puck itself went round the net. Real
# carried motion is bounded by skate + blade speed (~13 + 8 m/s -> ~0.18 m/tick);
# 0.5 gives ~3x headroom while the flip artifacts it must reject span the net's
# width (~1 m and up).
const MAX_CARRIED_TICK_TRAVEL: float = 0.5

# The segment to test, valid after advance() returns true.
var segment_start: Vector3 = Vector3.ZERO
var segment_end: Vector3 = Vector3.ZERO

var _prev: Vector3 = Vector3.ZERO
var _has_prev: bool = false
var _was_carried: bool = false


# Forget the path, so the next tick starts a fresh segment rather than spanning
# a gap (a stoppage, a drill).
func reset() -> void:
	_has_prev = false


# Sample this tick's puck and report whether (segment_start, segment_end) is a
# real path to test. Called BEFORE Puck._physics_process, so a carried puck is
# sampled at its pin (Puck.pinned_position), never at global_position: on the
# pickup tick that is still the loose spot, one tick stale, and every carried
# sample after it would trail the pin by a tick.
func advance(puck: Puck) -> bool:
	var carried: bool = puck.carrier != null
	var curr: Vector3 = puck.pinned_position() if carried else puck.global_position
	var was_carried: bool = _was_carried
	_was_carried = carried
	if not _has_prev:
		_prev = curr
		_has_prev = true
		return false
	segment_start = _prev
	segment_end = curr
	_prev = curr
	# Teleport guard: an implausible jump is never a real crossing. Pinned on both
	# ends gets the tight carried bound; the transitions keep the loose one, since
	# a released shot travels a tick of shot speed plus the release reposition and
	# a pickup snaps across up to the pickup radius.
	var max_travel: float = MAX_CARRIED_TICK_TRAVEL \
			if carried and was_carried else MAX_TICK_TRAVEL
	return segment_start.distance_to(segment_end) <= max_travel

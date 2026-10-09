class_name StuckPuckWatchdog
extends RefCounted

# Host-side: a loose puck that is physically stuck and that nothing in play will
# resolve. Two places it happens:
#
# - ON THE NET FRAME. A puck that settles on the frame never touches the ice. Low
#   on the back/skirt it is realistically playable, so it drops to the ice; up on
#   the crossbar/crown it is out of play.
# - IN THE CREASE, at rest against the goalie and not covered: wedged in the pads,
#   or jammed between pad and post. The smother whistle needs the glove to land on
#   it, and every goalie clear is gated on states and heights a wedged puck can
#   sit outside, so play stops while the clock runs. It is dead the way a puck lost
#   under the goalie is dead.
#
# The caller gates on live play and resets on a stoppage. This judges only the
# puck and returns what to do; the whistle is the caller's.

enum Verdict { NONE, DROP_TO_ICE, OUT_OF_PLAY, FROZEN }

var _net_timer: float = 0.0
var _crease_timer: float = 0.0


func reset() -> void:
	_net_timer = 0.0
	_crease_timer = 0.0


# `held` is a carried puck or one the goalie has pinned (catch, secured cover).
func tick(delta: float, pos: Vector3, speed: float, height_above_ice: float,
		airborne: bool, held: bool) -> Verdict:
	if held or speed >= GameRules.NET_STUCK_MAX_SPEED:
		reset()
		return Verdict.NONE
	var xz := Vector2(pos.x, pos.z)
	if airborne and GameRules.is_over_net_footprint(xz):
		_net_timer += delta
		if _net_timer >= GameRules.NET_STUCK_GRACE_DURATION:
			_net_timer = 0.0
			if height_above_ice <= GameRules.NET_STUCK_PLAYABLE_HEIGHT:
				return Verdict.DROP_TO_ICE
			return Verdict.OUT_OF_PLAY
	else:
		_net_timer = 0.0
	# A puck on the goal line is not in yet until all of it is across, so the
	# mouth counts as crease for the one radius behind the line.
	if CreaseRules.is_in_crease(xz, GameRules.PUCK_COLLISION_RADIUS):
		_crease_timer += delta
		if _crease_timer >= GameRules.CREASE_STUCK_GRACE_DURATION:
			_crease_timer = 0.0
			return Verdict.FROZEN
	else:
		_crease_timer = 0.0
	return Verdict.NONE

class_name KeeperFetch
extends RefCounted

# A loose puck near him he goes and gets: one he can reach with a single push
# from where he is, in front of the goal line or beside the post below it,
# never behind the cage; that will be slow enough to cover once there; and
# that no opponent can get a stick on first. He covers it once it is in his
# reach (KeeperCover); this is the skate there. Pure, in the net's frame (x
# across, z back into the net, the ice in front −z).
#
# The race is priced the way the old goalie's trip behind the net was: the
# opponent at full sprint from the first instant, straight at the puck, his
# stick's length short of it, so his time is never overestimated; and the
# keeper's own time a push to where his glove lands on it and a drop onto it,
# with his read of the play as the margin to set out (he sees the opponent
# late). Once he has gone he goes on while he still wins it.

# Where he stands to cover a puck: this far short of it, past the front of his
# blade held out in the low ready with a puck's width to spare (~0.63 m), so
# he never skates his stick onto it, and inside the glove's reach on the ice
# ahead of his knees from the butterfly (KeeperCover's, to ~0.8 m).
const COVER_AHEAD_M: float = 0.7
# Behind the goal line, a puck this near the cage across is behind it.
const CAGE_CLEAR_M: float = GameRules.NET_HALF_WIDTH + GameRules.PUCK_COLLISION_RADIUS + 0.1

# Where he skates to, and his turn there (square to the puck).
var spot := Vector2.ZERO
var facing: float = 0.0


# Whether he goes for the puck at `puck` sliding at `velocity`, with
# `opponents` where they are, from where `motor` has him; his read of the play
# `read_s`; `going` if he already has. Sets `spot` and `facing`.
func plan(puck: Vector2, velocity: Vector2, motor: KeeperMotor, opponents: PackedVector2Array, read_s: float,
		going: bool) -> bool:
	var rest: Vector2 = _stops_at(puck, velocity)
	if rest.y > 0.0 and absf(rest.x) < CAGE_CLEAR_M:
		return false
	var at := Vector2(motor.x, motor.z)
	var way: Vector2 = rest - at
	var d: float = way.length()
	if d > motor.slide.glide_reach(motor.slide.push_speed) + COVER_AHEAD_M:
		return false
	spot = rest - way.normalized() * minf(COVER_AHEAD_M, d) if d > 1e-4 else at
	facing = KeeperPositioning.facing(spot, rest)
	var mine: float = KeeperFootwork.push_time(at.distance_to(spot), motor.footwork.t_push_speed, motor.footwork.accel) \
			+ motor.save_move.drop_s
	return mine + (0.0 if going else read_s) < their_time(rest, opponents)


# How soon the first of `opponents` gets a stick on a puck at `at`: at full
# sprint from the first instant, straight at it, his stick's length short of
# it; INF with none.
static func their_time(at: Vector2, opponents: PackedVector2Array) -> float:
	var theirs: float = INF
	for o: Vector2 in opponents:
		theirs = minf(theirs, maxf(o.distance_to(at) - GameRules.DEFAULT_STICK_LENGTH_M, 0.0)
				/ GameRules.DEFAULT_SKATER_MAX_SPEED_M_S)
	return theirs


# Where a puck at `at` sliding at `v` comes to rest.
static func _stops_at(at: Vector2, v: Vector2) -> Vector2:
	var speed: float = v.length()
	if speed < 1e-6:
		return at
	return at + v / speed * (speed * speed / (2.0 * GameRules.PUCK_ICE_DECEL_M_S2))

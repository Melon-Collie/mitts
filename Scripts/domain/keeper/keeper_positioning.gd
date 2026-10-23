class_name KeeperPositioning
extends RefCounted

# Where he wants to be from the puck as he reads it, and the receivers a pass
# could reach (KeeperPlayRead): the first brain (docs/goalie-rebuild-plan.md,
# Phase 3). Pure: given the puck in the net's frame it sets his motor's goal,
# and the motor gets him there. On
# his feet everywhere in front of the goal line, since every drop there is a
# save and the reflex layer's; sealed in the RVH below it.
#
#   AWAY   the puck beyond the blue line: in the middle of the crease on its
#          angle line, square to it
#   FRONT  in the zone: on the line from the puck to the net's centre, square
#          to it, his skates on the top of the crease; deeper as the play
#          asks (`depth_for`), so a rush is met deep rather than skated round,
#          and as a pass across to a receiver in `play` asks (`pass_depth`);
#          a shot he sees wound up he is set for at depth, not backing in
#
# In the zone he sinks into the low ready once a shot could reach him sooner
# than his legs could answer it from the ready stance (`_cannot_react`): the
# low ready covers more of the net than the butterfly from anywhere in front
# of him, and its drop is the shorter fall.
#
# A pass he reads to an opposing stick (KeeperPlayRead.meets) he plays from
# where that stick meets it, in the zone it is in: skated to at once, turning
# as he goes, and stopped on the one-timer's angle rather than following the
# puck across and sliding past it as it stops.
#   SHARP  below the dots and wide of SHARP_RAD: standing on the near post's
#          overlap, turned to it
#   BELOW  at or below the goal line: sealed on the post on its side; directly
#          behind the net, on the post he holds until the puck's own motion
#          will carry it out the other side before he could get across
#
# Each zone holds him a margin past where it took him in, so a puck on a
# boundary does not flip him between two. The net's frame: x across (+ his
# blocker side, as keeper space), z back into the net from the goal line's
# centre, so the ice in front of it is −z.

enum Zone { AWAY, FRONT, SHARP, BELOW }

const BLUE_LINE_M: float = GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z
const DOT_LINE_M: float = GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z
# Off straight out from the net's centre, past which a puck below the dots is
# at a sharp angle.
const SHARP_RAD: float = deg_to_rad(60.0)
const MARGIN_M: float = 0.5
const MARGIN_RAD: float = deg_to_rad(5.0)
# How deep he waits with the puck out of the zone, of his depth in it.
const AWAY_DEPTH_SHARE: float = 0.5
# How far ahead his spot's own motion is read, along the puck's: a planner
# tick's worth.
const LOOK_AHEAD_S: float = 1.0 / 30.0
# The deepest the play backs him in to: the back of the blue paint, from where
# either post is a short slide.
const DEPTH_FLOOR_M: float = 0.5
# A pass's speed: the quick pass's.
const PASS_M_S: float = GameRules.DEFAULT_QUICK_PASS_POWER_M_S
# The hardest shot a carrier releases without a wind-up he reads: the
# neutral build's full wrister.
const SHOT_M_S: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
# Sunk, he comes back up only once a shot would leave him this much more
# time, so a puck on the boundary does not bob him up and down.
const SINK_MARGIN_S: float = 0.05

var zone: int = Zone.AWAY
# The post he holds below the goal line (+1 his blocker side), 0 none yet.
var post_side: float = 0.0
# What he reads of the play, for its receivers and his read's time; none, no
# pass is read.
var play: KeeperPlayRead = null
# The puck's velocity as decided on.
var _velocity := Vector2.ZERO


# Sets `motor`'s goal for the puck at `puck` moving at `velocity`, both in the
# net's frame.
func decide(puck: Vector2, velocity: Vector2, motor: KeeperMotor) -> void:
	var meeting: bool = play != null and play.meets
	if meeting:
		puck = play.meet
		velocity = Vector2.ZERO
	_velocity = velocity
	zone = _zone_for(puck)
	if zone != Zone.BELOW:
		post_side = 0.0
	motor.low_ready.asked = zone == Zone.FRONT and _cannot_react(puck, meeting, motor)
	match zone:
		Zone.BELOW:
			var side: float = _post_below(puck, velocity, motor)
			motor.seal(Vector2(side * GameRules.NET_HALF_WIDTH, 0.0), side)
		_:
			# His spot moves with the puck: the same spot a look ahead along
			# its motion, which the motor skates him with.
			var spot: Vector2 = _spot(puck, motor)
			var ahead: Vector2 = _spot(puck + velocity * LOOK_AHEAD_S, motor)
			if meeting:
				ahead = spot
			motor.go_to(spot, facing(spot, puck), KeeperRoute.Rest.FEET, (ahead - spot) / LOOK_AHEAD_S, meeting)


# His spot on his feet for the puck at `puck`, in its zone.
func _spot(puck: Vector2, motor: KeeperMotor) -> Vector2:
	if zone == Zone.SHARP:
		var side: float = 1.0 if puck.x >= 0.0 else -1.0
		var post := Vector2(side * GameRules.NET_HALF_WIDTH, 0.0)
		# Where he stands sets how far he turns, and the turn where he stands:
		# twice round settles both.
		var spot: Vector2 = motor.post.overlap_spot(post, side, facing(post, puck))
		for i: int in 2:
			spot = motor.post.overlap_spot(post, side, facing(spot, puck))
		return spot
	var out: Vector2 = puck.normalized() if puck.length() > 1e-4 else Vector2(0.0, -1.0)
	if zone == Zone.AWAY:
		return out * crease_edge(out) * AWAY_DEPTH_SHARE
	# Set for a shot he sees wound up: no retreat for the shooter's approach.
	var winding: bool = play != null and play.winding_up
	var depth: float = depth_for(puck, Vector2.ZERO if winding else _velocity, motor.footwork)
	if play != null:
		for receiver: Vector2 in play.receivers:
			depth = minf(depth, pass_depth(puck, receiver, motor.footwork, play.delay_s))
		depth = maxf(depth, minf(DEPTH_FLOOR_M, crease_edge(out)))
	return out * depth


# Whether a shot from the play at `puck` (a pass's meeting stick when
# `meeting`) could reach him sooner than his legs answer it and his drop
# lands from the ready stance.
func _cannot_react(puck: Vector2, meeting: bool, motor: KeeperMotor) -> bool:
	if play == null or not (meeting or play.theirs):
		return false
	var shot: float = puck.distance_to(Vector2(motor.x, motor.z)) / SHOT_M_S
	if meeting:
		shot += play.meet_s
	var answer: float = play.legs_s() + motor.save_move.drop_s
	return shot < answer + (SINK_MARGIN_S if motor.low_ready.asked else 0.0)


# How far out along the puck's line he stands in the zone: the top of the
# crease, or deeper as the puck at `puck` moving at `velocity` asks, from his
# own skating (`skates`): no further out than C-cuts from a standstill set him
# on the floor by the time a puck coming at him reaches the crease, and no
# further than his square shuffle keeps on the angle of one moving across him.
static func depth_for(puck: Vector2, velocity: Vector2, skates: KeeperFootwork) -> float:
	var out: Vector2 = puck.normalized() if puck.length() > 1e-4 else Vector2(0.0, -1.0)
	var top: float = crease_edge(out)
	var depth: float = top
	var r: float = puck.length()
	var coming: float = -velocity.dot(out)
	if coming > 0.0:
		var arrives: float = maxf(r - top, 0.0) / coming
		depth = minf(depth, DEPTH_FLOOR_M + GoaliePushRules.set_reach(skates.c_cut_speed, skates.accel, arrives))
	var swing: float = absf(out.x * velocity.y - out.y * velocity.x) / maxf(r, 1e-3)
	if swing > 1e-4:
		depth = minf(depth, skates.shuffle_speed / swing)
	return clampf(depth, minf(DEPTH_FLOOR_M, top), top)


# How far out along the line of a puck at `puck` he can stand and still be set
# on the angle of a receiver at `receiver` when a pass gets there: no further
# than the push (`skates`) he has time for, once he has read it (`read_s`),
# reaches the nearest of the receiver's angle line between the floor and the
# top of the crease. A receiver on his line asks nothing.
static func pass_depth(puck: Vector2, receiver: Vector2, skates: KeeperFootwork, read_s: float) -> float:
	var out: Vector2 = puck.normalized()
	var to: Vector2 = receiver.normalized()
	var across: float = absf(out.cross(to))
	if across < 1e-4:
		return INF
	var along: float = out.dot(to)
	var time: float = maxf(puck.distance_to(receiver) / PASS_M_S - read_s, 0.0)
	var reach: float = GoaliePushRules.set_reach(skates.t_push_speed, skates.accel, time)
	# Square onto the receiver's line where that falls inside the paint; else
	# onto the floor's spot on it.
	var square: float = reach / across
	if square * along >= DEPTH_FLOOR_M:
		return square
	return DEPTH_FLOOR_M * along + sqrt(maxf(reach * reach - DEPTH_FLOOR_M * DEPTH_FLOOR_M * across * across, 0.0))


func _zone_for(puck: Vector2) -> int:
	var out: float = -puck.y
	if out <= 0.0 or (zone == Zone.BELOW and out <= MARGIN_M):
		return Zone.BELOW
	var angle: float = atan2(absf(puck.x), out)
	var sharp: bool = out < DOT_LINE_M and angle > SHARP_RAD
	if zone == Zone.SHARP:
		sharp = out < DOT_LINE_M + MARGIN_M and angle > SHARP_RAD - MARGIN_RAD
	if sharp:
		return Zone.SHARP
	var away: bool = out > BLUE_LINE_M + MARGIN_M
	if zone == Zone.AWAY:
		away = out > BLUE_LINE_M
	return Zone.AWAY if away else Zone.FRONT


# The post he holds with the puck below the goal line: the one on its side
# when it is wide of the net; behind it, the one he holds, or the other once
# the puck will be out past that post by the time he could seal it.
func _post_below(puck: Vector2, velocity: Vector2, motor: KeeperMotor) -> float:
	if absf(puck.x) > GameRules.NET_HALF_WIDTH or post_side == 0.0:
		post_side = 1.0 if puck.x >= 0.0 else -1.0
		return post_side
	var other: float = -post_side
	var across: float = motor.time_to_seal(Vector2(other * GameRules.NET_HALF_WIDTH, 0.0), other)
	if (puck.x + velocity.x * across) * other > GameRules.NET_HALF_WIDTH:
		post_side = other
	return post_side


# How far out from the net's centre along `out` (unit, on the ice) the top of
# the crease is: its arc, cut off by its sides.
static func crease_edge(out: Vector2) -> float:
	if absf(out.x) < 1e-6:
		return CreaseRules.ARC_RADIUS
	return minf(CreaseRules.ARC_RADIUS, CreaseRules.HALF_WIDTH / absf(out.x))


# The turn that faces him from `at` to `puck`.
static func facing(at: Vector2, puck: Vector2) -> float:
	var to: Vector2 = puck - at
	return atan2(-to.x, -to.y)

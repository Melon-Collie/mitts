class_name KeeperPositioning
extends RefCounted

# Where he wants to be from the puck alone: the first brain, before he reads
# the skaters (docs/goalie-rebuild-plan.md, Phase 3). Pure: given the puck in
# the net's frame it sets his motor's goal, and the motor gets him there. On
# his feet everywhere in front of the goal line, since every drop there is a
# save and the reflex layer's; sealed in the RVH below it.
#
#   AWAY   the puck beyond the blue line: in the middle of the crease on its
#          angle line, square to it
#   FRONT  in the zone: on the line from the puck to the net's centre, square
#          to it, his skates on the top of the crease; deeper as the play
#          asks (`depth_for`), so a rush is met deep rather than skated round
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

var zone: int = Zone.AWAY
# The post he holds below the goal line (+1 his blocker side), 0 none yet.
var post_side: float = 0.0
# The puck's velocity as decided on.
var _velocity := Vector2.ZERO


# Sets `motor`'s goal for the puck at `puck` moving at `velocity`, both in the
# net's frame.
func decide(puck: Vector2, velocity: Vector2, motor: KeeperMotor) -> void:
	_velocity = velocity
	zone = _zone_for(puck)
	if zone != Zone.BELOW:
		post_side = 0.0
	match zone:
		Zone.BELOW:
			var side: float = _post_below(puck, velocity, motor)
			motor.seal(Vector2(side * GameRules.NET_HALF_WIDTH, 0.0), side)
		_:
			# His spot moves with the puck: the same spot a look ahead along
			# its motion, which the motor skates him with.
			var spot: Vector2 = _spot(puck, motor)
			var ahead: Vector2 = _spot(puck + velocity * LOOK_AHEAD_S, motor)
			motor.go_to(spot, facing(spot, puck), KeeperRoute.Rest.FEET, (ahead - spot) / LOOK_AHEAD_S)


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
	return out * depth_for(puck, _velocity, motor.footwork)


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

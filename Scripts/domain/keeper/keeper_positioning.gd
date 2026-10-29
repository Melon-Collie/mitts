class_name KeeperPositioning
extends RefCounted

# Where he wants to be from the puck as he reads it, and the receivers a pass
# could reach (KeeperPlayRead): the first brain (docs/goalie-rebuild-plan.md,
# Phase 3). Pure: given the puck in the net's frame it sets his motor's goal,
# and the motor gets him there. On his feet in front of the goal line but for
# a post he races a carrier to (below), since every other drop there is a
# save and the reflex layer's; sealed in the RVH below it.
#
#   AWAY   the puck beyond the blue line: in the middle of the crease on its
#          angle line, square to it
#   FRONT  in the zone: on the line from the puck to the net's centre, square
#          to it, his skates on the top of the crease; deeper as the play
#          asks (`depth_for`), so a rush is met deep rather than skated round,
#          and as a pass across to a receiver in `play` asks (`pass_depth`);
#          a shot he sees wound up he is set for at depth, not backing in
#   SHARP  below the dots and wide of SHARP_RAD: standing on the near post,
#          his pad overlapping it, turned to the puck
#   BELOW  at or below the goal line: sealed on the post on its side; directly
#          behind the net, on the post he holds until the puck's own motion
#          will carry it out the other side before he could get across
#
# A carrier of theirs he would race to a post for the RVH (`_race_to_post`)
# in front of the goal line he meets planted in the butterfly on it instead
# (`_plant`), where a wrap across has to go round him. One in tight in front
# of him he plays down: on his spot on his feet he drops there, and down he
# pushes with the carrier on the puck's line (`_stay_down`).
#
# In the zone he sinks into the low ready once a shot could reach him sooner
# than his legs could answer it from the ready stance (`_cannot_react`): the
# low ready covers more of the net than the ready stance, nothing off its gear
# goes on in, and its drop is the shorter fall.
#
# A pass he reads to an opposing stick (KeeperPlayRead.meets) he plays from
# where that stick meets it, in the zone it is in: skated to at once, turning
# as he goes, and stopped on the one-timer's angle rather than following the
# puck across and sliding past it as it stops.
#
# A carrier driving at a post from wide of it, once at a sharp angle or in
# tight, he races there (`_race_to_post`): down into the RVH as the drop-in
# from the post only just beats the puck, slid across if caught off it.
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
# A carrier of theirs in tight: planted on a post, he stays planted while the
# carrier is within this of it, wide of it in front of the goal line; and in
# front of the net, within this of it, he plays it down and pushes across with
# the carrier rather than standing up into the play, which he would lose the
# race to. About two stick lengths, the close range Hockey Canada gives the
# blocking butterfly; out of it a margin further off.
const TIGHT_M: float = 2.0 * GameRules.DEFAULT_STICK_LENGTH_M
# Rounds of solving a spot that hangs on itself: the seal squared to the
# carrier from where it puts him, the slide led by its own time.
const SEAL_ROUNDS: int = 4
# Near the seal, he drops where he is: within half a pad's width of it his pad
# still meets the post. Down, he pushes again only once his spot has moved on
# by as much.
const SEAL_NEAR_M: float = KeeperAnatomy.PAD_WIDTH_M * 0.5

var zone: int = Zone.AWAY
# The post he holds below the goal line (+1 his blocker side), 0 none yet.
var post_side: float = 0.0
# What he reads of the play, for its receivers and his read's time; none, no
# pass is read.
var play: KeeperPlayRead = null
# The puck's velocity as decided on.
var _velocity := Vector2.ZERO
# Sealed on `post_side` for a puck racing him to it (`_race_to_post`).
var _racing: bool = false
# Planted in the butterfly on a post for a carrier in tight beside it, or kept
# down for one in tight in front of him.
var planted: bool = false
var kept_down: bool = false
# The seal's turn, as `_seal` leaves it.
var _seal_turn: float = 0.0


# Sets `motor`'s goal for the puck at `puck` moving at `velocity`, both in the
# net's frame.
func decide(puck: Vector2, velocity: Vector2, motor: KeeperMotor) -> void:
	var meeting: bool = play != null and play.meets
	if meeting:
		puck = play.meet
		velocity = Vector2.ZERO
	_velocity = velocity
	zone = _zone_for(puck)
	var tight: bool = (zone == Zone.FRONT or zone == Zone.SHARP) and play != null and play.theirs \
			and not play.loose and not meeting
	_race_to_post(puck, _at_post_in(puck, velocity), motor)
	var near_post := Vector2(signf(puck.x) * GameRules.NET_HALF_WIDTH, 0.0)
	planted = tight and absf(puck.x) > GameRules.NET_HALF_WIDTH \
			and (puck.distance_to(near_post) <= TIGHT_M + MARGIN_M if planted else _racing)
	# In tight he goes down once he is on the spot he skates to, and stays down
	# while the carrier stays in tight.
	var me := Vector2(motor.x, motor.z)
	kept_down = tight and not planted and puck.length() <= TIGHT_M + (MARGIN_M if kept_down else 0.0) \
			and (kept_down or motor.rest != KeeperRoute.Rest.FEET or me.distance_to(_spot(puck, motor)) <= SEAL_NEAR_M)
	if planted or kept_down:
		_racing = false
		post_side = 0.0
		motor.low_ready.asked = false
		if planted:
			_plant(near_post, signf(puck.x), puck, velocity, motor)
		else:
			_stay_down(puck, velocity, motor)
		return
	if zone != Zone.BELOW and not _racing:
		post_side = 0.0
	motor.low_ready.asked = zone == Zone.FRONT and _cannot_react(puck, meeting, motor)
	if zone == Zone.BELOW or _racing:
		var side: float = post_side if _racing else _post_below(puck, velocity, motor)
		motor.seal(Vector2(side * GameRules.NET_HALF_WIDTH, 0.0), side)
		return
	# His spot moves with the puck: the same spot a look ahead along its
	# motion, which the motor skates him with.
	var spot: Vector2 = _spot(puck, motor)
	var ahead: Vector2 = _spot(puck + velocity * LOOK_AHEAD_S, motor)
	if meeting:
		ahead = spot
	motor.go_to(spot, facing(spot, puck), KeeperRoute.Rest.FEET, (ahead - spot) / LOOK_AHEAD_S, meeting)


# Planted in the butterfly on the post at `post` (on `side`), square to the
# carrier at `puck` moving at `velocity`, his pad's end sealing the post along
# the ice and the other pad laid across the front of the crease, the way round
# him: skated with the seal on his feet and dropped once near it, turned square
# on the way down or after; down, pushed to it again once it has moved on.
func _plant(post: Vector2, side: float, puck: Vector2, velocity: Vector2, motor: KeeperMotor) -> void:
	var ahead: Vector2 = _seal(post, side, puck + velocity * LOOK_AHEAD_S, motor)
	var spot: Vector2 = _seal(post, side, puck, motor)
	var at := Vector2(motor.x, motor.z)
	var near: bool = at.distance_to(spot) <= SEAL_NEAR_M
	if motor.rest == KeeperRoute.Rest.FEET and not near:
		motor.go_to(spot, _seal_turn, KeeperRoute.Rest.FEET, (ahead - spot) / LOOK_AHEAD_S, true)
		return
	motor.go_to(at if near else spot, _seal_turn, KeeperRoute.Rest.DOWN)


# Down with the carrier in tight in front of him: pushed across at his depth
# to the puck's line where the carrier will be when the push lands, square to
# him there; a move under SEAL_NEAR_M he leaves to the rotation, a push being
# a commitment he cannot cut short.
func _stay_down(puck: Vector2, velocity: Vector2, motor: KeeperMotor) -> void:
	var at := Vector2(motor.x, motor.z)
	var depth: float = at.length()
	var to: Vector2 = puck.normalized() * depth
	var lands: Vector2 = puck
	for i: int in SEAL_ROUNDS:
		lands = puck + velocity * motor.slide.time_to(at.distance_to(to))
		# A carrier driving at him stops on him, not past him.
		if lands.y > -depth - GameRules.DEFAULT_STICK_LENGTH_M * 0.5:
			lands = puck
		to = lands.normalized() * depth
	# A spot as near as half a pad's width to the one he is still pushing for,
	# or to where he has stopped, is no new push.
	var pushing: bool = motor.route.rest == KeeperRoute.Rest.DOWN and not motor.is_idle()
	if pushing and to.distance_to(motor.route.spot) <= SEAL_NEAR_M:
		to = motor.route.spot
	elif at.distance_to(to) <= SEAL_NEAR_M:
		to = at
	motor.go_to(to, facing(to, lands), KeeperRoute.Rest.DOWN)


# The spot that seals the post at `post` with his `side` pad, down square to a
# carrier at `puck`; its turn in _seal_turn.
func _seal(post: Vector2, side: float, puck: Vector2, motor: KeeperMotor) -> Vector2:
	_seal_turn = _seal_facing(post, side, puck)
	var spot: Vector2 = post
	for i: int in SEAL_ROUNDS:
		spot = motor.slide.post_seal_spot(post, side, _seal_turn)
		_seal_turn = _seal_facing(spot, side, puck)
	return spot


# Square to the carrier from `at`, turned toward the post on `side` no further
# than a slide back across to the far post along the goal line still goes
# (KeeperSlide.MAX_OFF_LINE_RAD): the wrap's answer.
static func _seal_facing(at: Vector2, side: float, puck: Vector2) -> float:
	var turn: float = facing(at, puck)
	return -side * minf(-side * turn, KeeperSlide.MAX_OFF_LINE_RAD)


# How long a puck at `puck` moving at `velocity` takes to reach the post on its
# side, carried at it from wide of it: heading for the goal line within a
# stick's length outside the post, where a carrier stuffs or wraps it. INF for
# any other.
static func _at_post_in(puck: Vector2, velocity: Vector2) -> float:
	if absf(puck.x) <= GameRules.NET_HALF_WIDTH or velocity.y <= 1e-3 or puck.y >= 0.0:
		return INF
	var arrives: float = -puck.y / velocity.y
	var at_line: float = puck.x + velocity.x * arrives
	var outside: float = absf(at_line) - GameRules.NET_HALF_WIDTH
	if signf(at_line) != signf(puck.x) or outside < 0.0 or outside > GameRules.DEFAULT_STICK_LENGTH_M:
		return INF
	return arrives


# A puck at `puck` that gets to the post on its side in `arrives`
# (`_at_post_in`) is raced there only once it is at a sharp angle or in tight
# (a stick's length from the post): until then the angle line, which brings him
# toward the post as the puck goes wide, is what covers the shot it can still
# take, and going for the post sooner gives the rest of the net away to a
# feint. On the post, standing, he drops into the RVH once the drop-in only
# just beats the puck there; off it with the puck in tight, his fastest way in,
# the butterfly slide across. Sealed for it, he holds it while the puck still
# heads there or is at a sharp angle: a puck that turns back out beats him back
# up.
func _race_to_post(puck: Vector2, arrives: float, motor: KeeperMotor) -> void:
	var was: bool = _racing
	_racing = false
	if zone == Zone.BELOW or zone == Zone.AWAY or absf(puck.x) <= GameRules.NET_HALF_WIDTH:
		return
	var side: float = signf(puck.x)
	var post := Vector2(side * GameRules.NET_HALF_WIDTH, 0.0)
	if was and (arrives < INF or zone == Zone.SHARP):
		_racing = true
	elif arrives < INF:
		var on_post: bool = motor.rest == KeeperRoute.Rest.FEET and Vector2(motor.x, motor.z).distance_to(
				motor.post.overlap_spot(post, side, motor.yaw)) <= KeeperRoute.ON_POST_M
		if on_post:
			_racing = arrives <= motor.post.drop_in_s(motor.yaw)
		elif zone == Zone.SHARP or puck.distance_to(post) <= GameRules.DEFAULT_STICK_LENGTH_M:
			_racing = arrives <= motor.time_to_seal(post, side)
	if _racing:
		post_side = side


# His spot on his feet for the puck at `puck`, in its zone.
func _spot(puck: Vector2, motor: KeeperMotor) -> Vector2:
	if zone == Zone.SHARP:
		var side: float = 1.0 if puck.x >= 0.0 else -1.0
		var post := Vector2(side * GameRules.NET_HALF_WIDTH, 0.0)
		return motor.post.overlap_spot(post, side, motor.post.overlap_facing(post, side, puck))
	var out: Vector2 = puck.normalized() if puck.length() > 1e-4 else Vector2(0.0, -1.0)
	if zone == Zone.AWAY:
		return out * crease_edge(out) * AWAY_DEPTH_SHARE
	# Set for a shot he sees wound up: no retreat for the shooter's approach,
	# only for where he is.
	var winding: bool = play != null and play.winding_up
	var carried: bool = play != null and play.theirs and not play.loose
	var depth: float = depth_for(puck, Vector2.ZERO if winding else _velocity, motor.footwork, carried)
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
# on the floor by the time it could reach the crease, and no further than his
# square shuffle keeps on the angle of one moving across him. A loose puck
# reaches the crease on its own motion; a `carried` one as soon as its
# carrier could skate there, driving from the speed he already has toward it
# (the skaters' stride, AIStrideRamp), so a carrier who stops in tight still
# holds him in rather than drawing him out at him.
static func depth_for(puck: Vector2, velocity: Vector2, skates: KeeperFootwork, carried: bool = false) -> float:
	var out: Vector2 = puck.normalized() if puck.length() > 1e-4 else Vector2(0.0, -1.0)
	var top: float = crease_edge(out)
	var depth: float = top
	var r: float = puck.length()
	var coming: float = -velocity.dot(out)
	var arrives: float = INF
	if carried:
		arrives = AIStrideRamp.time_to_cover(maxf(coming, 0.0), maxf(r - top, 0.0),
				GameRules.DEFAULT_SKATER_MAX_SPEED_M_S, GameRules.DEFAULT_SKATER_THRUST_M_S2)
	elif coming > 0.0:
		arrives = maxf(r - top, 0.0) / coming
	if arrives < INF:
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

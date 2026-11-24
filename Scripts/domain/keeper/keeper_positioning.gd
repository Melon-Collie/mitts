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
#          asks (`depth_for`): a carrier of theirs met no further back than
#          hides both posts from the puck, backed in to that as he comes,
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
# In the zone and on the post at a sharp angle, he sinks into the low ready
# once a shot could reach him sooner than his legs could answer it from the
# ready stance (`_cannot_react`): the low ready covers more of the net than the
# ready stance, nothing off its gear goes on in, and its drop is the shorter
# fall. Standing tall on the post, his body and glove ride over the band behind
# his near pad that a shot along the goal line comes in through.
#
# In the zone, a body on his sightline to the puck from his spot he looks
# round (KeeperScreen): a step across off his angle line, no further than half
# his chest.
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
# carrier from where it puts him.
const SEAL_ROUNDS: int = 4
# How much of an even split between the shot a carrier has now and the one a
# pull across his body gives him the keeper stands off the puck's line for
# (`_hedged`). Measured from 4 m at 0.3: a plain shot saved 83% (88% with
# none), one straight off a drag across 62% (50%); past it both fall.
const HEDGE_SHARE: float = 0.3
# Near the seal, he drops where he is: within half a pad's width of it his pad
# still meets the post. Down, he pushes again only once his spot has moved on
# by as much.
const SEAL_NEAR_M: float = KeeperAnatomy.PAD_WIDTH_M * 0.5

# `closing_share`, measured once from his gear; negative until then.
static var _closing_share: float = -1.0

var zone: int = Zone.AWAY
# The post he holds below the goal line (+1 his blocker side), 0 none yet.
var post_side: float = 0.0
# What he reads of the play, for its receivers and his read's time; none, no
# pass is read.
var play: KeeperPlayRead = null
# The skaters on the ice who could hide the puck from him, net frame (his
# controller's; only where they stand is read); and his look round them.
var bodies := PackedVector3Array()
var screen := KeeperScreen.new()
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
	var comes: float = -velocity.dot(puck.normalized()) if puck.length() > 1e-4 else 0.0
	var down_within: float = down_range(comes, motor.save_move.drop_s * motor.low_ready.fall_share())
	var held: bool = kept_down and (puck.length() <= down_within + MARGIN_M or not _clears_his_hands(puck, me))
	kept_down = tight and not planted and (held or puck.length() <= down_within) \
			and (kept_down or motor.rest != KeeperRoute.Rest.FEET or motor.drops()
					or _covers(me, _spot(_hedged(puck, motor), motor)))
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
	motor.low_ready.asked = (zone == Zone.FRONT or zone == Zone.SHARP) \
			and _cannot_react(puck, meeting, motor)
	if zone == Zone.BELOW or _racing:
		var side: float = post_side if _racing else _post_below(puck, velocity, motor)
		var post := Vector2(side * GameRules.NET_HALF_WIDTH, 0.0)
		if _racing and _skates_onto_post(post, side, puck, motor):
			return
		motor.seal(post, side)
		return
	# His spot moves with the puck: the same spot a look ahead along its
	# motion, which the motor skates him with.
	var spot: Vector2 = _spot(_hedged(puck, motor), motor)
	var ahead: Vector2 = _spot(_hedged(puck + velocity * LOOK_AHEAD_S, motor), motor)
	if meeting:
		ahead = spot
	if zone == Zone.FRONT:
		screen.look(spot, Vector3(puck.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, puck.y), bodies,
				motor.low_ready.asked)
		spot += screen.step
		ahead += screen.step
	motor.go_to(spot, facing(spot, puck), KeeperRoute.Rest.FEET, (ahead - spot) / LOOK_AHEAD_S, meeting)


# How near the net's centre a carrier of theirs coming at it at `coming` takes
# him down: in tight, and as far outside it as the carrier skates in the
# `drop_s` his drop takes, so the butterfly has landed as the carrier comes in
# tight rather than starting there. A carrier standing off it does not.
static func down_range(coming: float, drop_s: float) -> float:
	return TIGHT_M + maxf(coming, 0.0) * drop_s


# Whether a puck at `puck` can be lifted over his hands by the time it gets to
# him at `me`, down. Until it can, standing up covers nothing the butterfly
# does not and shows the low net for as long as getting up takes, so down he
# stays down.
static func _clears_his_hands(puck: Vector2, me: Vector2) -> bool:
	return GameRules.PUCK_COLLISION_HALF_HEIGHT + PlayerAttributes.steepest_loft_tan() * puck.distance_to(me) \
			> KeeperHandsLow.highest()


# Whether he at `me` covers what he would from `spot`: on its line from the
# net's centre, there or further out along it, as he is while a carrier comes
# in faster than he backs in.
static func _covers(me: Vector2, spot: Vector2) -> bool:
	var out: Vector2 = spot.normalized()
	return absf(out.cross(me)) <= SEAL_NEAR_M and me.dot(out) >= spot.length() - SEAL_NEAR_M


# Planted in the butterfly on the post at `post` (on `side`), square to the
# carrier at `puck` moving at `velocity`, his pad's end sealing the post along
# the ice and the other pad laid across the front of the crease, the way round
# him: skated with the seal on his feet and dropped once near it, turned square
# on the way down or after; down, or on his way down from in front, pushed to
# it on his knees.
func _plant(post: Vector2, side: float, puck: Vector2, velocity: Vector2, motor: KeeperMotor) -> void:
	var ahead: Vector2 = _seal(post, side, puck + velocity * LOOK_AHEAD_S, motor)
	var spot: Vector2 = _seal(post, side, puck, motor)
	var at := Vector2(motor.x, motor.z)
	var near: bool = at.distance_to(spot) <= SEAL_NEAR_M
	if motor.rest == KeeperRoute.Rest.FEET and not near and not motor.drops():
		motor.go_to(spot, _seal_turn, KeeperRoute.Rest.FEET, (ahead - spot) / LOOK_AHEAD_S, true)
		return
	if near:
		motor.go_to(at, _seal_turn, KeeperRoute.Rest.DOWN)
	else:
		motor.go_to(spot, _seal_turn, KeeperRoute.Rest.DOWN)


# Down with the carrier in tight in front of him: on the puck's line led on
# by the angle the carrier's body sweeps round the net on the way he has to
# skate (`lands`), square to it, giving ground with him as he comes
# (`_down_spot`); a spot within his knees' reach scooted to and followed as it
# moves, one beyond it pushed for, a push being a commitment he cannot cut
# short. The way is the body's, read from the body: the puck held out to one
# side of a body coming straight at him is not a carrier going by him, and a
# pull across moves his line by no more than it moves the puck.
func _stay_down(puck: Vector2, velocity: Vector2, motor: KeeperMotor) -> void:
	var at := Vector2(motor.x, motor.z)
	var heading: Vector2 = velocity.normalized()
	var body: Vector2 = play.carrier if play.carrier != KeeperPlayRead.NO_CARRIER else puck
	# Read on no further than level with the back of the paint: by there a
	# carrier going by him is the post's.
	var far: float = _committed(velocity.length())
	if heading.y > 1e-3:
		far = minf(far, maxf(-DEPTH_FLOOR_M - body.y, 0.0) / heading.y)
	var lands: Vector2 = body + heading * _short_of_him(body, heading, far, at)
	var led: Vector2 = puck.rotated(angle_difference(body.angle(), lands.angle())) \
			if body.length() > 1e-4 and lands.length() > 1e-4 else puck
	# Sliding back on the speed he dropped with, he gives the ground it carries
	# him over for as long as the carrier could still be coming on at his own
	# speed, not only as far as he has to: an error along the puck's line
	# leaves him on it, where one across it leaves the net.
	var slides: float = _carried_back(puck, motor)
	var friction: float = motor.save_move.pad_friction
	var comes: float = maxf(-velocity.dot(led.normalized()), 0.0) if led.length() > 1e-4 else 0.0
	var to: Vector2 = _down_spot(led, at, maxf(KeeperRoute.KNEE_REACH_M, slides * slides / (2.0 * friction)),
			lands.length() - comes * slides / friction)
	# Still on his feet, a spot further off than his knees reach and his speed
	# slides him he skates to and drops on: quicker than dropping where he is
	# and pushing from his knees.
	var carried: float = motor.moving().length()
	if motor.rest == KeeperRoute.Rest.FEET and not motor.drops() \
			and at.distance_to(to) > KeeperRoute.KNEE_REACH_M + carried * carried / (2.0 * friction):
		motor.go_to(to, facing(to, led), KeeperRoute.Rest.FEET, Vector2.ZERO, true)
		return
	# A spot as near as half a pad's width to the one he is pushing for is no
	# new push.
	if motor.slides() and to.distance_to(motor.route.spot) <= SEAL_NEAR_M:
		to = motor.route.spot
	motor.go_to(to, facing(to, led), KeeperRoute.Rest.DOWN)


# How fast the speed he drops with slides him back along the line of a puck at
# `puck`: what he skates at, asked down, and what of it is left on his pads
# since; nothing once he rests on his knees.
static func _carried_back(puck: Vector2, motor: KeeperMotor) -> float:
	if motor.rest != KeeperRoute.Rest.FEET or puck.length() < 1e-4:
		return 0.0
	return maxf(-motor.moving().dot(puck.normalized()), 0.0)


# His spot down at `at` for a carrier's puck at `puck`: on its line, back from
# the nearest of it to him by `back`, or by as much as a push across to the
# line gives back at the furthest a slide goes off his line, so a carrier going
# wide round him is pushed back to the post with on a diagonal. No further back
# than hides both posts from the puck come as near as `nearest` of the net's
# centre, in tight at the furthest (he dropped outside it to be down there),
# and never further out than he is.
static func _down_spot(puck: Vector2, at: Vector2, back: float, nearest: float) -> Vector2:
	var out: Vector2 = puck.normalized() if puck.length() > 1e-4 else Vector2(0.0, -1.0)
	var deepest: float = minf(DEPTH_FLOOR_M, crease_edge(out))
	var hides: float = clampf(closing_depth(out * clampf(nearest, 0.0, TIGHT_M)), deepest, maxf(at.length(), deepest))
	var pushed: float = absf(at.cross(out)) * tan(KeeperSlide.MAX_OFF_LINE_RAD)
	return out * maxf(hides, at.dot(out) - maxf(back, pushed))


# How far a carrier skating at `speed` has to go: what stopping as hard as a
# skater stops still carries him. Any further is his to choose, and a push,
# which cannot be cut short, is not spent on a choice he has not made.
static func _committed(speed: float) -> float:
	return speed * speed / (2.0 * GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2)


# How far of the `far` a carrier at `puck` has to go along `heading` he is read
# on: all of it where that way goes by him at `at`, and where it runs into him,
# to half a stick short of him. He comes on at him and stops on him, not past
# him, and the ground that takes from him he gives.
static func _short_of_him(puck: Vector2, heading: Vector2, far: float, at: Vector2) -> float:
	var reach: float = GameRules.DEFAULT_STICK_LENGTH_M * 0.5
	var nearest: float = clampf((at - puck).dot(heading), 0.0, far)
	if at.distance_to(puck + heading * nearest) >= reach:
		return far
	return maxf(nearest - reach, 0.0)


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
# just beats the puck there; off it with the puck in tight, his fastest way in
# (`_skates_onto_post` within a glide of it, else the butterfly slide across).
# Sealed for it, he holds it while the puck still heads there or is at a sharp
# angle: a puck that turns back out beats him back up.
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
		if _on_post(post, side, motor):
			_racing = arrives <= motor.post.drop_in_s(motor.yaw)
		elif zone == Zone.SHARP or puck.distance_to(post) <= GameRules.DEFAULT_STICK_LENGTH_M:
			_racing = arrives <= motor.time_to_seal(post, side)
	if _racing:
		post_side = side


# Whether he stands on his edge on the post at `post` (on `side`) as he is
# turned, where KeeperRoute drops him straight into the RVH.
static func _on_post(post: Vector2, side: float, motor: KeeperMotor) -> bool:
	return motor.rest == KeeperRoute.Rest.FEET and Vector2(motor.x, motor.z).distance_to(
			motor.post.overlap_spot(post, side, motor.yaw)) <= KeeperRoute.ON_POST_M


# Racing on his feet for the post at `post` (on `side`) from within a glide of
# its overlap, he skates on onto it, turning square to the puck at `puck` as
# he goes, and seals once on it: a seal goal would stop him where he is first,
# turned as the race found him. Whether he skates.
func _skates_onto_post(post: Vector2, side: float, puck: Vector2, motor: KeeperMotor) -> bool:
	if motor.rest != KeeperRoute.Rest.FEET or _on_post(post, side, motor):
		return false
	var turn: float = motor.post.overlap_facing(post, side, puck)
	var spot: Vector2 = motor.post.overlap_spot(post, side, turn)
	if Vector2(motor.x, motor.z).distance_to(spot) > KeeperRoute.GLIDE_REACH_M:
		return false
	motor.go_to(spot, turn, KeeperRoute.Rest.FEET, Vector2.ZERO, true)
	return true


# The puck his angle line goes through on his feet for one at `puck`: the puck
# itself, unless a carrier of theirs holds it off to one side of his body, not
# wound up to shoot. He can have it as far the other side as fast as a blade
# crosses him, and of that the keeper makes up only what his feet cover after
# his read. Standing half of what he could not make up toward the body would
# leave him as far off the shot that can come now as off the one the pull
# gives; he takes HEDGE_SHARE of that, since at the depth he plays he has
# nothing to spare and every step off the puck's line opens its post.
func _hedged(puck: Vector2, motor: KeeperMotor) -> Vector2:
	if play == null or not play.theirs or play.loose or play.winding_up or play.carrier == KeeperPlayRead.NO_CARRIER \
			or play.carrier.length() < 1e-4 or puck.length() < 1e-4:
		return puck
	var across: Vector2 = play.carrier.normalized().orthogonal()
	var held: float = clampf((puck - play.carrier).dot(across), -KeeperPlayRead.CARRIER_REACH_M, KeeperPlayRead.CARRIER_REACH_M)
	var pull: float = 2.0 * absf(held)
	# What the pull moves his own spot by, on the puck's line where he is.
	var moves: float = pull * Vector2(motor.x, motor.z).length() / puck.length()
	if moves < 1e-4:
		return puck
	var made_up: float = GoaliePushRules.cruise_reach(motor.footwork.shuffle_speed, motor.footwork.accel,
			pull / KeeperPlayRead.BLADE_M_S - play.delay_s)
	return puck - across * held * clampf(1.0 - made_up / moves, 0.0, 1.0) * HEDGE_SHARE


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
# own skating (`skates`), and no further than his square shuffle keeps on the
# angle of one moving across him: for a `carried` one, at the fastest it will
# swing on the way its carrier has to skate (`swing_ahead`).
#
# A loose puck coming at him: no further out than C-cuts from a standstill set
# him on the floor by the time it reaches the crease.
#
# A `carried` one: no further out than hides both posts from it
# (`closing_depth`), since further out covers no more net and leaves him more
# ice to cross when it moves; and backed in ahead of its carrier, leaving the
# top of the crease as late as still gets him, on his C-cuts and still moving,
# onto the closing depth of where the carrier comes in tight (TIGHT_M), where
# he goes down. The carrier comes in as soon as he could skate there, driving
# from the speed he already has toward the net (the skaters' stride,
# AIStrideRamp). Never deeper than the closing depth for a carrier's approach:
# backed onto the floor he shows a shot from the slot both sides of the net.
static func depth_for(puck: Vector2, velocity: Vector2, skates: KeeperFootwork, carried: bool = false) -> float:
	var out: Vector2 = puck.normalized() if puck.length() > 1e-4 else Vector2(0.0, -1.0)
	var top: float = crease_edge(out)
	var depth: float = top
	var r: float = puck.length()
	var coming: float = -velocity.dot(out)
	if carried:
		depth = minf(depth, closing_depth(puck))
		if r > TIGHT_M:
			var tight: float = clampf(closing_depth(out * TIGHT_M), minf(DEPTH_FLOOR_M, top), top)
			var comes_in: float = AIStrideRamp.time_to_cover(maxf(coming, 0.0), r - TIGHT_M,
					GameRules.DEFAULT_SKATER_MAX_SPEED_M_S, GameRules.DEFAULT_SKATER_THRUST_M_S2)
			var backing: float = GoaliePushRules.time_to_cruise(top - tight, skates.c_cut_speed, skates.accel) - comes_in
			depth = minf(depth, maxf(tight, top - GoaliePushRules.cruise_reach(skates.c_cut_speed, skates.accel, backing)))
	elif coming > 0.0:
		var arrives: float = maxf(r - top, 0.0) / coming
		depth = minf(depth, DEPTH_FLOOR_M + GoaliePushRules.set_reach(skates.c_cut_speed, skates.accel, arrives))
	var swing: float = absf(out.x * velocity.y - out.y * velocity.x) / maxf(r, 1e-3)
	if carried:
		swing = maxf(swing, swing_ahead(puck, velocity))
	if swing > 1e-4:
		depth = minf(depth, skates.shuffle_speed / swing)
	return clampf(depth, minf(DEPTH_FLOOR_M, top), top)


# The fastest a carried puck at `puck` moving at `velocity` swings across him
# (rad/s, round the net's centre) on the stretch of its line its carrier has to
# skate (`_committed`): at the nearest that stretch comes to the net. A carrier
# coming across in front from a sharp angle sweeps slowly while wide and fast
# as he passes in front, so a depth set on the swing he has now is one the
# shuffle cannot keep by the time he gets there.
static func swing_ahead(puck: Vector2, velocity: Vector2) -> float:
	var speed: float = velocity.length()
	if speed < 1e-4:
		return 0.0
	var heading: Vector2 = velocity / speed
	var nearest: Vector2 = puck + heading * clampf(-puck.dot(heading), 0.0, _committed(speed))
	return speed * absf(nearest.cross(heading)) / maxf(nearest.length_squared(), 1e-6)


# The furthest back from a carried puck at `puck` he can stand on its line,
# square to it, and still hide both posts from it: the depth at which the
# lines from the puck to the posts pass him just inside his outline's width
# (`closing_share` of the mouth's). From well out to a side the mouth is
# narrower to the puck and it is deeper; negative where the goal line itself
# hides them.
static func closing_depth(puck: Vector2) -> float:
	var r: float = puck.length()
	if r < 1e-4:
		return 0.0
	var out: Vector2 = puck / r
	var half: float = closing_share() * KeeperCoverage.MOUTH_HALF_M
	var depth: float = -INF
	for side: int in 2:
		var post := Vector2((2.0 * side - 1.0) * KeeperCoverage.MOUTH_HALF_M, 0.0)
		var across: float = absf(post.cross(out))
		if across > 1e-4:
			depth = maxf(depth, r - half * (r - post.dot(out)) / across)
	return depth


# The share of a puck's distance he can leave between him and it and still
# hide both posts (KeeperCoverage.closing_share), set in the low ready, the
# stance a carrier in range finds him in.
static func closing_share() -> float:
	if _closing_share < 0.0:
		var pose := KeeperPose.new()
		KeeperPoses.low_ready(pose)
		var skel := KeeperSkeleton.new()
		skel.pose(pose)
		_closing_share = KeeperCoverage.closing_share(skel, TIGHT_M)
	return _closing_share


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


# His state on the wire (KeeperWire); `play` is his controller's, written there,
# and the bodies and the screen are refilled for each read.
func wire(w: KeeperWire) -> void:
	zone = w.s8(zone)
	post_side = w.s16(post_side, KeeperWire.MM)
	_velocity = w.v2_16(_velocity, KeeperWire.SPEED)
	_racing = w.bit(_racing)
	planted = w.bit(planted)
	kept_down = w.bit(kept_down)
	_seal_turn = w.s32(_seal_turn, KeeperWire.ANGLE)

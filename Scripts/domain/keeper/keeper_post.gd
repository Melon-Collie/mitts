class_name KeeperPost
extends RefCounted

# His RVH on a post (KeeperPoses.rvh): into it and out of it, from his feet or
# from the butterfly, and where he is when he is in it. Pure, stepped at the
# tick.
#
#   DROPPING_IN       from his feet, standing on the post: the post knee falls
#                     to the ice as the butterfly's drop does and the pad lays
#                     itself along the goal line, toe to the post, while the
#                     off skate slides out wide on its edge
#   RISING_OUT        the drop reversed: up onto his feet on the post
#   IN_FROM_BUTTERFLY down on the post after a slide: the off leg comes up
#                     onto its skate and the post pad turns onto the goal line
#   OUT_TO_BUTTERFLY  that reversed: down into the butterfly where he is
#   SEALED            in the RVH, the post pad's end on the post
#
# Places are in the stances' frame, as KeeperSlide's: x across, z his depth,
# and `yaw` his turn about the vertical. In the RVH he is square to the goal
# line; the stance turns his trunk to the play itself.

enum State { STANDING, BUTTERFLY, DROPPING_IN, RISING_OUT, IN_FROM_BUTTERFLY, OUT_TO_BUTTERFLY, SEALED }

# The off leg coming up onto its skate as the post pad turns onto the line, and
# going back down.
const IN_FROM_BUTTERFLY_S: float = 0.18
const OUT_TO_BUTTERFLY_S: float = 0.15
# How far the off pad's face tips up as its skate slides out, at most (up per
# unit of the face's own direction).
const PAD_ROLL_UP: float = 0.7

# The post knee's fall from his feet (the butterfly drop's), and the rise back.
var drop_s: float = GoalieSkillProfile.hard().butterfly_drop_s
var rise_s: float = 0.35
# How fast a drop-in swings him square from a turn: his pivot's rate, given by
# the motor that turns him.
var swing_rad_s: float = INF

var x: float = 0.0
var z: float = 0.0
var yaw: float = 0.0
var state: int = State.STANDING
# The post he is on or going to: its side (+1 his blocker side).
var side: float = 1.0

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _yaw_from: float = 0.0
var _clock: float = 0.0
# How long the drop-in under way takes.
var _drop_in_s: float = 0.0

var _ready := KeeperPose.new()
var _low := KeeperPose.new()
var _rvh: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
# Where each stance's solve puts the parts that touch a post, on the side of
# the post at index 0 (glove side) or 1: his outermost reach standing, and the
# post pad's end in the RVH.
var _standing_edge: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sealed_edge: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func _init() -> void:
	KeeperPoses.ready(_ready)
	KeeperPoses.butterfly(_low)
	var skel := KeeperSkeleton.new()
	skel.pose(_ready)
	for i: int in 2:
		var s: float = -1.0 if i == 0 else 1.0
		_standing_edge[i] = KeeperGear.post_contact(skel, s)
	for i: int in 2:
		var s: float = -1.0 if i == 0 else 1.0
		rvh_pose(_rvh[i], s, skel)
		_sealed_edge[i] = KeeperGear.post_pad_contact(skel, s)


# The RVH on `post_side` into `p`, `skel` left posed in it; its glove held in
# the chest's frame as every other stance holds it, so a way in or out blends
# the hand in one frame.
static func rvh_pose(p: KeeperPose, post_side: float, skel: KeeperSkeleton) -> void:
	KeeperPoses.rvh(p, post_side)
	skel.pose(p)
	if not p.glove_from_chest:
		p.glove_hand = skel.xf[KeeperSkeleton.Bone.CHEST].affine_inverse() * p.glove_hand
		p.glove_from_chest = true


# Where he stands with his edge on the post at `post` (x, z) on `post_side`,
# turned `turn` (square by default): where the brain puts him to drop in, or
# turned to a puck at a sharp angle. Turned, his square stance's edge turns
# with him.
func overlap_spot(post: Vector2, post_side: float, turn: float = 0.0) -> Vector2:
	var edge: Vector3 = Basis(Vector3.UP, turn) * _standing_edge[_index(post_side)]
	return _on_post(post, post_side, edge)


# Where he is in the RVH on the post at `post` on `post_side`: the post pad's
# end on its face.
func seal_spot(post: Vector2, post_side: float) -> Vector2:
	return _on_post(post, post_side, _sealed_edge[_index(post_side)])


# The turn that squares him to a puck at `puck` standing on the post at `post`
# on `post_side` (`overlap_spot` at that turn): his edge pivots on the post's
# face, so the turn that puts the puck straight ahead of him from there.
# A puck nearer the post than his edge's reach across him has none; then the
# turn that faces it from the post.
func overlap_facing(post: Vector2, post_side: float, puck: Vector2) -> float:
	var on := Vector2(post.x - post_side * GameRules.NET_POST_RADIUS, post.y)
	var d: Vector2 = puck - on
	var across: float = _standing_edge[_index(post_side)].x
	if d.length() <= absf(across) + 1e-4:
		return atan2(-d.x, -d.y)
	# Across him the puck lies at d.x·cos t − d.y·sin t + edge.x, which is 0
	# where it is straight ahead; the root with the puck ahead of him.
	return wrapf(-acos(-across / d.length()) - atan2(d.y, d.x), -PI, PI)


static func _on_post(post: Vector2, post_side: float, edge: Vector3) -> Vector2:
	return Vector2(post.x - post_side * GameRules.NET_POST_RADIUS - edge.x, post.y - edge.z)


static func _index(post_side: float) -> int:
	return 0 if post_side < 0.0 else 1


# Down into the RVH on the post at `post` on `post_side`, from his feet where he
# stands, swung square onto the seal as the knee falls.
func drop_in(post: Vector2, post_side: float) -> void:
	if state == State.STANDING:
		_drop_in_s = drop_in_s(yaw)
		_go(State.DROPPING_IN, post, post_side)


# How long a drop-in from his feet turned `from_yaw` takes: the knee's fall,
# and the swing square at his pivot's rate as it falls.
func drop_in_s(from_yaw: float) -> float:
	return drop_s + absf(wrapf(from_yaw, -PI, PI)) / swing_rad_s


# Down into the RVH on the post at `post` on `post_side`, from the butterfly
# where he is.
func slide_in(post: Vector2, post_side: float) -> void:
	if state == State.BUTTERFLY:
		_go(State.IN_FROM_BUTTERFLY, post, post_side)


# Up out of the RVH onto his feet, his edge on the post.
func rise_out() -> void:
	if state == State.SEALED:
		_leave(State.RISING_OUT, _standing_edge[_index(side)])


# Out of the RVH down into the butterfly where he is.
func fold_out() -> void:
	if state == State.SEALED:
		_leave(State.OUT_TO_BUTTERFLY, _sealed_edge[_index(side)])


func _go(next: int, post: Vector2, post_side: float) -> void:
	side = post_side
	_from = Vector2(x, z)
	_to = seal_spot(post, post_side)
	_yaw_from = yaw
	_clock = 0.0
	state = next


# Where the rise out of the RVH he is in stands him: his edge on the post.
func risen_spot() -> Vector2:
	return _on_post(_sealed_on(), side, _standing_edge[_index(side)])


# The post he is sealed on, from where he is.
func _sealed_on() -> Vector2:
	var sealed: Vector3 = _sealed_edge[_index(side)]
	return Vector2(x, z) + Vector2(sealed.x + side * GameRules.NET_POST_RADIUS, sealed.z)


func _leave(next: int, edge: Vector3) -> void:
	_from = Vector2(x, z)
	_to = _on_post(_sealed_on(), side, edge) if next == State.RISING_OUT else _from
	_yaw_from = yaw
	_clock = 0.0
	state = next


func _seconds(s: int) -> float:
	match s:
		State.DROPPING_IN:
			return _drop_in_s
		State.RISING_OUT:
			return rise_s
		State.IN_FROM_BUTTERFLY:
			return IN_FROM_BUTTERFLY_S
	return OUT_TO_BUTTERFLY_S


func step(dt: float) -> void:
	if state == State.STANDING or state == State.BUTTERFLY or state == State.SEALED:
		return
	_clock = minf(_clock + dt / _seconds(state), 1.0)
	# The body goes with the legs: falling into the drop, eased otherwise.
	var u: float = _clock * _clock if state == State.DROPPING_IN else smoothstep(0.0, 1.0, _clock)
	var at: Vector2 = _from.lerp(_to, u)
	x = at.x
	z = at.y
	yaw = lerp_angle(_yaw_from, 0.0, u)
	if _clock >= 1.0:
		match state:
			State.DROPPING_IN, State.IN_FROM_BUTTERFLY:
				state = State.SEALED
			State.RISING_OUT:
				state = State.STANDING
			State.OUT_TO_BUTTERFLY:
				state = State.BUTTERFLY


# His pose this tick, in his own frame.
func pose(p: KeeperPose) -> void:
	var i: int = _index(side)
	var rvh: KeeperPose = _rvh[i]
	var post_leg: int = i
	var off_leg: int = 1 - i
	match state:
		State.STANDING:
			p.copy_from(_ready)
		State.BUTTERFLY:
			p.copy_from(_low)
		State.SEALED:
			p.copy_from(rvh)
		State.DROPPING_IN, State.RISING_OUT:
			# Down, a fall; up, a push eased both ways.
			var down: float = _clock * _clock if state == State.DROPPING_IN \
					else 1.0 - smoothstep(0.0, 1.0, _clock)
			KeeperDrop.blend_body(p, _ready, rvh, down)
			KeeperDrop.blend_leg(p.legs[post_leg], _ready.legs[post_leg], KeeperDrop.ready_knee(post_leg),
					rvh.legs[post_leg], down)
			_slide_out(p.legs[off_leg], _ready.legs[off_leg], KeeperDrop.ready_knee(off_leg),
					rvh.legs[off_leg], down)
		State.IN_FROM_BUTTERFLY, State.OUT_TO_BUTTERFLY:
			var up: float = smoothstep(0.0, 1.0, _clock)
			if state == State.OUT_TO_BUTTERFLY:
				up = 1.0 - up
			KeeperDrop.blend_body(p, _low, rvh, up)
			_kneel_along(p.legs[post_leg], _low.legs[post_leg], rvh.legs[post_leg], up)
			KeeperDrop.blend_leg(p.legs[off_leg], rvh.legs[off_leg], rvh.legs[off_leg].knee,
					_low.legs[off_leg], 1.0 - up)


# A standing leg `t` of the way from `from` (its solve's knee at `from_knee`)
# to `to`, its skate on the ice the whole way, sliding on its edge.
static func _slide_out(leg: KeeperPose.Leg, from: KeeperPose.Leg, from_knee: Vector3,
		to: KeeperPose.Leg, t: float) -> void:
	leg.knee_pinned = true
	leg.knee = from_knee.lerp(to.knee, t)
	leg.ankle = from.ankle.lerp(to.ankle, t)
	leg.thigh_front = from.thigh_front.lerp(to.thigh_front, t).normalized()
	# The pad rides up onto its inner edge as the skate goes out, as the push
	# leg's does in the T-push, or its outer corner is driven into the ice.
	var rolled: Vector3 = Vector3.UP * PAD_ROLL_UP * sin(PI * sqrt(t))
	leg.shin_front = (from.shin_front.lerp(to.shin_front, t) + rolled).normalized()
	leg.foot_mode = KeeperPose.FootMode.FLAT
	leg.toe = from.toe.lerp(to.toe, t).normalized()
	leg.flex = 0.0
	leg.along_shin = 0.0


# A kneeling leg `t` of the way from `from` to `to`, its knee and pad on the ice.
static func _kneel_along(leg: KeeperPose.Leg, from: KeeperPose.Leg, to: KeeperPose.Leg, t: float) -> void:
	leg.knee_pinned = true
	leg.knee = from.knee.lerp(to.knee, t)
	leg.ankle = from.ankle.lerp(to.ankle, t)
	leg.thigh_front = from.thigh_front.lerp(to.thigh_front, t).normalized()
	leg.shin_front = from.shin_front.lerp(to.shin_front, t).normalized()
	leg.foot_mode = KeeperPose.FootMode.ALONG_SHIN
	leg.flex = lerpf(from.flex, to.flex, t)
	leg.along_shin = 0.0

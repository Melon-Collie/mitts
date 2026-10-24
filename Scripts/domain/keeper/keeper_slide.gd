class_name KeeperSlide
extends RefCounted

# His butterfly slide: the push leg drives him off its skate while the lead pad
# stays flat on the ice, then folds back down to seal; he rides the pads, and
# the lead skate's edge stops him on his spot. Pure, stepped at the tick. From
# the butterfly the push leg comes up to push; from his feet the lead leg goes
# down to the half butterfly and the push leg never leaves its skate; from the
# RVH the skate on the post pushes him off it and the off leg drops to lead
# (`push_off`). A slide
# goes along his line: to a spot off it, he turns as he loads until his lead
# side faces it, so a slide back to a post is the same slide, turned.
#
#   DROP   from his feet: the lead knee falls to the ice as the butterfly's
#          drop does, the push leg loading on its skate where it stood, so the
#          push starts as the knee lands; he turns to the spot as it falls
#   LOAD   from the butterfly: the push leg's knee comes up off the ice and
#          in, its skate planted out wide on its inside edge
#          (KeeperPoses.butterfly_push); he turns to the spot as it comes
#   OFF_POST from the RVH: the off knee falls to the ice as the lead pad while
#          the post leg's knee comes up off it, its skate on the post, loaded
#          as from the butterfly, so the push starts as the knee lands
#   PUSH   the skate holds its place on the ice while the leg drives him off
#          it, from rest up to the push's speed
#   GLIDE  the push leg folds back down beside the lead pad, sealing the ice,
#          and the pads slide on under their friction
#   STOP   the lead skate, behind its pad, digs its inside edge, and he leans
#          back against it; both pads stay down
#   DOWN   the butterfly, on the spot, once the stop has settled out of him
#   TURN   a rotation (`rotate_to`): loaded as for a slide, the push skate,
#          planted on its inside edge, swivels him on his knees to face where
#          he is turned, the leg folding back down as he comes round
#
# He pushes at the speed asked for, and starts the stop when the brake left
# would only just land him on the spot, so a slide is a push and a stop, not a
# coast. A spot too near for the push to be stopped in gets a softer push; one
# past where friction alone would stop the push is answered with that reach.
# Places are in the stances' frame, as KeeperFootwork's: x across his line (+
# toward his blocker side), z his depth (+ back toward his net), and `yaw` his
# turn about the vertical, as a Node3D's rotation.y; his pose is in his own
# frame, which `yaw` turns.

enum Phase { DOWN, DROP, LOAD, PUSH, GLIDE, STOP, TURN, OFF_POST }
# Where a slide sets out from.
enum From { BUTTERFLY, FEET, POST }

# The push leg rising onto its skate (the old goalie's coil), driving, and
# folding back down; the stop leaving his body once he is at rest.
const LOAD_S: float = KeeperDrop.PUSH_LOAD_S
const PUSH_S: float = 0.12
const FOLD_S: float = 0.15
const SETTLE_S: float = 0.15
# The off knee's fall to the ice out of the RVH: the fold out's.
const OFF_POST_S: float = KeeperPost.OUT_TO_BUTTERFLY_S
# How much of his weight he gets through the lead skate's edge with both knees
# down, against the whole of it in a standing edge stop.
const EDGE_WEIGHT_SHARE: float = 0.3
# How far off his line a slide is taken: turned further to it, he would be
# down with his chest off the shot.
const MAX_OFF_LINE_RAD: float = deg_to_rad(45.0)
# How high the push skate lifts folding down from his feet: higher than the
# drop's, since after a short slide the leg comes in barely stretched and its
# shin pitches the boot's rigid toe into the ice under the falling knee.
const FOLD_LIFT_M: float = 0.10

# The hardest push's speed, and the pads' friction on the ice (the old goalie's
# slide_friction, about μ 0.27).
var push_speed: float = GoalieSkillProfile.hard().slide_push_speed_mps
# The lead knee's fall to the ice from his feet: the butterfly drop's.
var drop_s: float = GoalieSkillProfile.hard().butterfly_drop_s
var friction: float = 2.6
# What the lead skate's edge adds to the pads' friction in the stop: his share
# of a standing edge stop's brake.
var edge_brake: float = EDGE_WEIGHT_SHARE * GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2 \
		* GameRules.GOALIE_EDGE_STOP_DECEL_RATIO

var x: float = 0.0
var z: float = 0.0
var yaw: float = 0.0
var speed: float = 0.0
var phase: int = Phase.DOWN

# The lead side in his own frame (+1 his blocker side), where the slide set out
# from and which way it goes, his turn before it and on it, and how far along
# he has come of the way to the spot.
var _side: float = 1.0
var _origin := Vector2.ZERO
var _heading := Vector2.RIGHT
var _yaw_from: float = 0.0
var _yaw_to: float = 0.0
var _along: float = 0.0
var _target: float = 0.0
# The speed this slide's push builds to, how far through its phase he is, how
# far the push leg is folded back down, and how far into the stop he is and
# how hard a one.
var _peak: float = 0.0
var _from: int = From.BUTTERFLY
var _clock: float = 0.0
var _fold: float = 1.0
var _stop: float = 0.0
var _stop_from_speed: float = 0.0
# Where the push skate was planted, across him in his own frame when the push
# began; and the push leg as it was when its push ended, with the knee its
# solve put it at, to fold from.
var _plant: float = 0.0
var _released := KeeperPose.Leg.new()
var _released_knee := Vector3.ZERO
# Whether the load is for a rotation, and how long its turn takes.
var _rotating: bool = false
var _turn_s: float = 0.0

var _low := KeeperPose.new()
var _ready := KeeperPose.new()
# Loaded to push toward the glove side (index 0) or the blocker side (1), the
# lead pad down: from the butterfly, and from his feet.
var _loaded: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
var _loaded_knee: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _set: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
# The RVH on the glove-side post (index 0) or the blocker-side one (1), and
# loaded to push off the other one toward that side: the loaded butterfly with
# its skate where the RVH has it, on the post.
var _rvh: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
var _off_post: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
var _off_post_knee: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
# Where the lead pad's outer end lies, in his own frame, down in the butterfly.
var _pad_end: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _skel := KeeperSkeleton.new()


func _init() -> void:
	KeeperPoses.butterfly(_low)
	KeeperPoses.ready(_ready)
	_skel.pose(_low)
	_pad_end[0] = KeeperGear.post_pad_contact(_skel, -1.0)
	_pad_end[1] = KeeperGear.post_pad_contact(_skel, 1.0)
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		KeeperPoses.butterfly_push(_loaded[i], side)
		_skel.pose(_loaded[i])
		_loaded_knee[i] = _skel.xf[KeeperSkeleton.SHIN[1 - i]].origin
		KeeperPoses.half_butterfly_loaded(_set[i], side)
		KeeperPost.rvh_pose(_rvh[i], side, _skel)
	for i: int in 2:
		var post_leg: int = 1 - i
		_skel.pose(_rvh[post_leg])
		var on_post: Vector3 = _skel.xf[KeeperSkeleton.FOOT[post_leg]].origin
		_off_post[i].copy_from(_loaded[i])
		# The boot's toe stays on the post, the foot along the shin as the RVH
		# lays it, the knee coming up off the ice over it.
		var push: KeeperPose.Leg = _off_post[i].legs[post_leg]
		push.ankle = on_post
		push.foot_mode = KeeperPose.FootMode.FLAT
		push.along_shin = 1.0
		push.flex = _rvh[post_leg].legs[post_leg].flex
		_skel.pose(_off_post[i])
		_off_post_knee[i] = _skel.xf[KeeperSkeleton.SHIN[post_leg]].origin


# Slide toward `spot` (x, z) from the butterfly, pushing at up to `top` m/s;
# where he will come to rest.
func slide_to(spot: Vector2, top: float = INF) -> Vector2:
	return _start(spot, top, From.BUTTERFLY)


# Slide toward `spot` (x, z) from his feet, by the half butterfly; where he
# will come to rest. He ends in the butterfly.
func slide_from_feet(spot: Vector2, top: float = INF) -> Vector2:
	return _start(spot, top, From.FEET)


# Slide toward `spot` (x, z) off the post on `post_side` (+1 his blocker side)
# from the RVH there, pushing at up to `top` m/s; where he will come to rest.
# Only away from the post: a spot on its side of him he stays for.
func push_off(spot: Vector2, post_side: float, top: float = INF) -> Vector2:
	if (spot - Vector2(x, z)).dot(_across(yaw)) * post_side >= 0.0:
		return Vector2(x, z)
	return _start(spot, top, From.POST)


func _start(spot: Vector2, top: float, from: int) -> Vector2:
	var here := Vector2(x, z)
	if phase != Phase.DOWN or here.distance_to(spot) < 1e-4:
		return here
	var dist: float = here.distance_to(spot)
	_origin = here
	_heading = (spot - here) / dist
	_side = 1.0 if _heading.dot(_across(yaw)) >= 0.0 else -1.0
	_yaw_from = yaw
	_yaw_to = facing(_heading, _side)
	_along = 0.0
	_peak = minf(minf(top, push_speed), _stoppable_peak(dist))
	_target = minf(dist, glide_reach(_peak))
	_from = from
	match from:
		From.FEET:
			phase = Phase.DROP
		From.POST:
			phase = Phase.OFF_POST
		_:
			phase = Phase.LOAD
	_clock = 0.0
	_fold = 0.0
	_stop = 0.0
	return _origin + _heading * _target


# Rotate on his knees from the butterfly to face `turn`: the push skate on
# the side he turns away from drives him round, the pads swinging over the ice
# about him.
func rotate_to(turn: float) -> void:
	var off: float = wrapf(turn - yaw, -PI, PI)
	if phase != Phase.DOWN or absf(off) < 1e-4:
		return
	_rotating = true
	_side = -signf(off)
	_yaw_from = yaw
	_yaw_to = yaw + off
	_turn_s = _turn_time(off)
	_origin = Vector2(x, z)
	_heading = _across(yaw) * _side
	_along = 0.0
	_target = 0.0
	speed = 0.0
	_from = From.BUTTERFLY
	phase = Phase.LOAD
	_clock = 0.0
	_fold = 0.0
	_stop = 0.0


# How fast he swivels on his knees: the push's speed carried by the pads' far
# ends about him.
func turn_rate() -> float:
	return push_speed / Vector2(_pad_end[0].x, _pad_end[0].z).length()


# Seconds a rotation through `off` radians takes from the butterfly, load and
# turn.
func rotate_time(off: float) -> float:
	return LOAD_S + _turn_time(off) if absf(off) >= 1e-4 else 0.0


# The swivel through `off`, no quicker than the push leg folds back down.
func _turn_time(off: float) -> float:
	return maxf(absf(off) / turn_rate(), FOLD_S)


# His own +x (his blocker side) on the ice, turned `turn`.
static func _across(turn: float) -> Vector2:
	return Vector2(cos(turn), -sin(turn))


# The turn that faces his `side` (+1 his blocker side) along `heading`.
static func facing(heading: Vector2, side: float) -> float:
	return atan2(-heading.y * side, heading.x * side)


# Where to slide from `from` so that, down in the butterfly and turned along
# the slide, his lead pad's outer end meets the post at `post` (x, z). The
# pad's end lies a little behind his line, so the line that lands it on the
# post is the one the post lies that far behind; the slide runs along it until
# the end reaches the post's face. Already there, he stays where he is.
func post_spot(post: Vector2, from: Vector2) -> Vector2:
	var to_post: Vector2 = post - from
	var side: float = 1.0 if to_post.dot(_across(yaw)) >= 0.0 else -1.0
	var end: Vector3 = _pad_end[1 if side > 0.0 else 0]
	var behind: float = clampf(end.z / (side * to_post.length()), -1.0, 1.0)
	var heading: Vector2 = Vector2.from_angle(to_post.angle() - asin(behind))
	var out: float = to_post.dot(heading) - end.x * side - GameRules.NET_POST_RADIUS
	return from + heading * maxf(out, 0.0)


# Where he is, down in the butterfly turned `turn`, with his `side` pad's
# outer end (+1 his blocker side) on the face of the post at `post` (x, z).
func post_seal_spot(post: Vector2, side: float, turn: float) -> Vector2:
	var end: Vector3 = _pad_end[1 if side > 0.0 else 0]
	var back := Vector2(sin(turn), cos(turn))
	return post - _across(turn) * (end.x + side * GameRules.NET_POST_RADIUS) - back * end.z


# Down on his spot with the stop settled out of him: in the butterfly.
func is_settled() -> bool:
	return phase == Phase.DOWN and _stop <= 0.0


func _brake() -> float:
	return friction + edge_brake


# The hardest push that can still be stopped `dist` along: its own travel plus
# the brake from it.
func _stoppable_peak(dist: float) -> float:
	var half_push: float = PUSH_S * 0.5
	var b: float = _brake()
	return b * (sqrt(half_push * half_push + 2.0 * dist / b) - half_push)


# How far a push at `peak` carries him with no stop, friction alone: further
# than that no stop is needed, and he cannot get there.
func glide_reach(peak: float) -> float:
	return peak * PUSH_S * 0.5 + peak * peak / (2.0 * friction)


# Seconds from the call until he is at rest `dist` along, pushing at up to
# `top`, within reach, setting out `from` (From).
func time_to(dist: float, top: float = INF, from: int = From.BUTTERFLY) -> float:
	var v0: float = minf(minf(top, push_speed), _stoppable_peak(dist))
	var b: float = _brake()
	var left: float = maxf(dist - v0 * PUSH_S * 0.5, 0.0)
	# The speed the stop starts from: the glide on friction and the stop share
	# what the push left.
	var v1_sq: float = (v0 * v0 / (2.0 * friction) - left) / (1.0 / (2.0 * friction) - 1.0 / (2.0 * b))
	var v1: float = sqrt(clampf(v1_sq, 0.0, v0 * v0))
	return lead_in_s(from) + PUSH_S + (v0 - v1) / friction + v1 / b


# Seconds from the call to the push setting out `from` (From).
func lead_in_s(from: int) -> float:
	match from:
		From.FEET:
			return drop_s
		From.POST:
			return OFF_POST_S
	return LOAD_S


func step(dt: float) -> void:
	if phase == Phase.DOWN or phase == Phase.GLIDE or phase == Phase.STOP:
		_fold = minf(_fold + dt / FOLD_S, 1.0)
	match phase:
		Phase.DOWN:
			_stop = maxf(_stop - dt / SETTLE_S, 0.0)
		Phase.DROP, Phase.LOAD, Phase.OFF_POST:
			_clock += dt / lead_in_s(_from)
			if not _rotating:
				yaw = lerp_angle(_yaw_from, _yaw_to, smoothstep(0.0, 1.0, minf(_clock, 1.0)))
			if _clock >= 1.0 and _rotating:
				phase = Phase.TURN
				_clock = 0.0
				_released.copy_from(_loaded[_lead()].legs[_push_leg()])
				_released_knee = _loaded_knee[_lead()]
			elif _clock >= 1.0:
				phase = Phase.PUSH
				_clock = 0.0
				_plant = _launch().legs[_push_leg()].ankle.x
		Phase.TURN:
			_clock = minf(_clock + dt / maxf(_turn_s, 1e-4), 1.0)
			yaw = lerp_angle(_yaw_from, _yaw_to, smoothstep(0.0, 1.0, _clock))
			_fold = _clock
			if _clock >= 1.0:
				yaw = _yaw_to
				_rotating = false
				phase = Phase.DOWN
		Phase.PUSH:
			var was: float = speed
			_clock = minf(_clock + dt / PUSH_S, 1.0)
			speed = _peak * _clock
			_along += 0.5 * (was + speed) * dt
			if _clock >= 1.0:
				_release()
		Phase.GLIDE, Phase.STOP:
			var left: float = _target - _along
			# The stop starts the tick it would be too late to after this one's.
			if phase == Phase.GLIDE and speed >= sqrt(2.0 * _brake() * maxf(left - speed * dt, 0.0)):
				phase = Phase.STOP
				_stop_from_speed = speed
			var was: float = speed
			if phase == Phase.STOP:
				# The edge digs as hard as it takes to stop on the spot, which
				# from the tick the stop starts is its brake.
				speed = maxf(speed - speed * speed / (2.0 * maxf(left, 1e-6)) * dt, 0.0)
				_stop = 1.0 - speed / maxf(_stop_from_speed, 1e-6)
			else:
				speed = maxf(speed - friction * dt, 0.0)
			_along += 0.5 * (was + speed) * dt
			if _target - _along <= 1e-4 or speed <= 1e-4:
				_along = _target
				speed = 0.0
				if _fold >= 1.0:
					phase = Phase.DOWN
	var at: Vector2 = _origin + _heading * _along
	x = at.x
	z = at.y


func _release() -> void:
	phase = Phase.GLIDE
	var p := KeeperPose.new()
	_pushing_pose(p)
	_released.copy_from(p.legs[_push_leg()])
	_skel.pose(p)
	_released_knee = _skel.xf[KeeperSkeleton.SHIN[_push_leg()]].origin


# The pose he pushes from: the half butterfly from his feet, the loaded
# butterfly from the butterfly, and off the post with its skate on the post.
func _launch() -> KeeperPose:
	match _from:
		From.FEET:
			return _set[_lead()]
		From.POST:
			return _off_post[_lead()]
	return _loaded[_lead()]


func _lead() -> int:
	return 1 if _side > 0.0 else 0


func _push_leg() -> int:
	return 1 - _lead()


# His pose this tick, relative to where he is.
func pose(p: KeeperPose) -> void:
	match phase:
		Phase.DROP:
			# A fall, as the butterfly's drop: eased in, landing at speed.
			var down: float = _clock * _clock
			var launch: KeeperPose = _launch()
			KeeperDrop.blend_body(p, _ready, launch, down)
			KeeperDrop.blend_leg(p.legs[_lead()], _ready.legs[_lead()], KeeperDrop.ready_knee(_lead()),
					launch.legs[_lead()], down)
			var push: KeeperPose.Leg = p.legs[_push_leg()]
			push.copy_from(_ready.legs[_push_leg()])
			push.knee_pole = push.knee_pole.lerp(launch.legs[_push_leg()].knee_pole, down)
			push.shin_front = push.shin_front.lerp(launch.legs[_push_leg()].shin_front, down).normalized()
		Phase.LOAD:
			var up: float = smoothstep(0.0, 1.0, _clock)
			KeeperDrop.blend_body(p, _low, _loaded[_lead()], up)
			p.legs[_lead()].copy_from(_low.legs[_lead()])
			KeeperDrop.swing_leg(p.legs[_push_leg()], _loaded[_lead()].legs[_push_leg()],
					_loaded_knee[_lead()], _low.legs[_push_leg()], 1.0 - up)
		Phase.OFF_POST:
			# The off knee falls as the drop's does; the post leg swings up round
			# its knee onto its skate as the butterfly's push leg loads.
			var down: float = _clock * _clock
			var rvh: KeeperPose = _rvh[_push_leg()]
			var loaded: KeeperPose = _launch()
			KeeperDrop.blend_body(p, rvh, loaded, down)
			KeeperDrop.blend_leg(p.legs[_lead()], rvh.legs[_lead()], rvh.legs[_lead()].knee, loaded.legs[_lead()],
					down)
			_kneel_up(p.legs[_push_leg()], rvh.legs[_push_leg()], loaded.legs[_push_leg()],
					_off_post_knee[_lead()], down)
		Phase.PUSH:
			_pushing_pose(p)
		_:
			var down: float = smoothstep(0.0, 1.0, _fold)
			if down >= 1.0:
				p.copy_from(_low)
			else:
				KeeperDrop.blend_body(p, _launch(), _low, down)
				p.legs[_lead()].copy_from(_low.legs[_lead()])
				# From his feet the leg comes down from standing, as the drop's do;
				# from the butterfly push it swings back round its knee.
				if _from == From.FEET:
					KeeperDrop.blend_leg(p.legs[_push_leg()], _released, _released_knee,
							_low.legs[_push_leg()], down, FOLD_LIFT_M)
				else:
					KeeperDrop.swing_leg(p.legs[_push_leg()], _released, _released_knee, _low.legs[_push_leg()], down)
					# Off the post the foot stays along the shin, as it pushed.
					if _from == From.POST:
						p.legs[_push_leg()].along_shin = 1.0
			# Back against the stop, as far as the speed it stops from asks.
			var stop: float = _stop * clampf(_stop_from_speed / GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S,
					0.0, 1.0)
			p.lumbar_rot.z += _side * KeeperFootwork.STOP_LEAN_RAD * stop


# A kneeling leg (`down`) `t` of the way up onto its planted foot (`up`, its
# solve's knee at `up_knee`): the knee rising off the ice over a foot that
# holds its place.
static func _kneel_up(leg: KeeperPose.Leg, down: KeeperPose.Leg, up: KeeperPose.Leg, up_knee: Vector3,
		t: float) -> void:
	leg.copy_from(up)
	leg.knee_pinned = true
	leg.knee = down.knee.lerp(up_knee, t)
	leg.thigh_front = down.thigh_front.lerp(up.thigh_front, t).normalized()
	leg.shin_front = down.shin_front.lerp(up.shin_front, t).normalized()


# Driving off the planted skate: the pose he pushes from, its skate held where
# it was set down.
func _pushing_pose(p: KeeperPose) -> void:
	p.copy_from(_launch())
	p.legs[_push_leg()].ankle.x = _plant - _side * _along

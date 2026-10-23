class_name KeeperMotor
extends RefCounted

# His moves strung together: where he is on the ice, his turn, and which way
# he rests (on his feet, down in the butterfly, sealed on a post), handed from
# each move to the next so his place, turn and pose run on unbroken. Pure,
# stepped at the tick.
#
# Moves are asked for in order and each starts when the one before it has come
# to rest, settled out of him. One asked for from the wrong rest (a slide on
# his feet, a T-push down) is refused and counted. On his feet he turns by a
# pivot (`face`), his skates turning under him on their edges, and footwork
# goes in his turned frame: a T-push straight to the spot (KeeperFootwork's
# diagonal), a shuffle to where it falls on his line, a C-cut to where it falls
# in depth. Turning first is the brain's, as the coaching orders it: eyes,
# rotation, then the feet.
#
# Or he is given where to be (`go_to`, `seal`), and makes the first move of the
# fastest way there (KeeperRoute) each time he comes to rest, until he is
# there. A new spot or facing under a pivot or footwork under way is taken on
# by it; any other change waits for him to come to rest. Footwork toward a goal
# turns his trunk toward its facing as he goes (`lead`, up to LEAD_MAX_RAD
# ahead of his skates), his skates on their line, and the skates turn under
# him to catch up once he is set on the spot, as the stop
# settles. More footwork, or a pivot, starts as soon as his push leg is back
# under him; a drop, slide or the RVH waits for the stop to settle. The last order
# wins: a goal clears the moves asked for, and a move asked for clears the
# goal.
#
# A low save (`save`, KeeperSaveMove) is the one move that does not wait: it
# cuts whatever is under way where it is, the speed it had carried into the
# save, and holds until `end_save`; then he rests where it leaves him.
#
# Set on his feet he sinks into the low ready when asked (`low_ready`), and
# rises out of it as any move starts; a drop or a low save from it is the
# shorter fall.
#
# Places are in the stances' frame, as the movers': x across, z depth (+ back
# toward his net), `yaw` his turn about the vertical, as a Node3D's rotation.y.

const Rest := KeeperRoute.Rest
const Do := KeeperRoute.Do
enum Mover { NONE, PIVOT, FOOTWORK, DROP, SLIDE, POST, SAVE, GLIDE }

# The pivot: its top turn rate, near the old goalie's (whose 5/s lerp turns him
# through 45° at up to 3.9 rad/s), and how hard his edges start and stop it.
const PIVOT_RATE_RAD_S: float = 4.0
const PIVOT_ACCEL_RAD_S2: float = 40.0
# How far his trunk turns ahead of his skates while footwork carries him; it
# turns as fast as the pivot.
const LEAD_MAX_RAD: float = deg_to_rad(30.0)
# A goal on his feet that moves this fast he skates to as it moves, however
# far (KeeperGlide); a still one when the route plans it.
const MOVING_M_S: float = 0.05

var x: float = 0.0
var z: float = 0.0
# His skates' turn, and his trunk's ahead of it.
var yaw: float = 0.0
var lead: float = 0.0
var rest: int = Rest.FEET
# Moves asked for from a rest they cannot start from.
var refused: int = 0

var footwork := KeeperFootwork.new()
var drop := KeeperDrop.new()
var slide := KeeperSlide.new()
var post := KeeperPost.new()
var route := KeeperRoute.new(footwork, drop, slide, post, PIVOT_RATE_RAD_S, PIVOT_ACCEL_RAD_S2, LEAD_MAX_RAD)
var save_move := KeeperSaveMove.new()
var glide := KeeperGlide.new()
var low_ready := KeeperLowReady.new()

var _queue: Array[_Ask] = []
var _goal: bool = false
var _mover: int = Mover.NONE
# The pivot's target and rate; where a footwork move set out from, and his
# turn on it.
var _face: float = 0.0
var _turn_rate: float = 0.0
var _anchor := Vector2.ZERO
var _anchor_yaw: float = 0.0
# His speed over the last step, and the pose a save cuts in from.
var _velocity := Vector2.ZERO
var _cut := KeeperPose.new()
# How fast the spot he is asked to be on is moving.
var _spot_velocity := Vector2.ZERO
# Seconds since the goal's spot was given.
var _spot_since: float = 0.0
# Whether the goal on his feet is skated to however far it is.
var _skate: bool = false


# One move asked for: what, to where, which side, how fast.
class _Ask:
	extends RefCounted
	var what: int
	var spot: Vector2
	var side: float
	var top: float

	func _init(p_what: int, p_spot: Vector2, p_side: float, p_top: float) -> void:
		what = p_what
		spot = p_spot
		side = p_side
		top = p_top


func _init() -> void:
	post.swing_rad_s = PIVOT_RATE_RAD_S


# Be on his feet at `spot` facing `facing`, or down at `spot` (`on` Rest.DOWN);
# on his feet, the spot moving at `velocity`, or skated to however far it is
# (`skate`: he goes at once, whichever way it lies, turning as he goes, and
# stops on it).
func go_to(spot: Vector2, facing: float, on: int = Rest.FEET, velocity := Vector2.ZERO,
		skate: bool = false) -> void:
	_queue.clear()
	_goal = true
	route.rest = on
	route.spot = spot
	route.facing = facing
	_spot_velocity = velocity if on == Rest.FEET else Vector2.ZERO
	_skate = skate and on == Rest.FEET
	_spot_since = 0.0
	_retarget()


# Be sealed in the RVH on the post at `iron` on `side`.
func seal(iron: Vector2, side: float) -> void:
	_queue.clear()
	_goal = true
	route.rest = Rest.POST
	route.iron = iron
	route.side = side


# A pivot under way turns on to the new facing; footwork under way goes on to
# a new spot on its line, and one set on its last spot pushes again for one
# further along it than he would call there.
func _retarget() -> void:
	if route.rest != Rest.FEET:
		return
	if _mover == Mover.PIVOT:
		_face = route.facing
	elif _mover == Mover.FOOTWORK:
		var local: Vector2 = _turned(route.spot - _anchor, -_anchor_yaw)
		if footwork.off_line(local) > KeeperRoute.ON_LINE_M:
			return
		# Set, his skates may have turned under him since the move began: the
		# next move is planned afresh in their frame.
		if footwork.phase == KeeperFootwork.Phase.SET and (yaw != _anchor_yaw
				or local.distance_to(Vector2(footwork.x, footwork.z)) < KeeperRoute.THERE_M):
			return
		match footwork.move:
			KeeperFootwork.Move.T_PUSH:
				footwork.push_to(local)
			KeeperFootwork.Move.SHUFFLE:
				footwork.shuffle_to(local.x)
			KeeperFootwork.Move.C_CUT:
				footwork.c_cut_to(local.y)


# Turn on his feet to `turn`.
func face(turn: float) -> void:
	_ask(Do.FACE, Vector2.ZERO, turn)


# On his feet, to `spot`, square.
func push_to(spot: Vector2) -> void:
	_ask(Do.T_PUSH, spot)


# On his feet, along his line to where `spot` falls on it.
func shuffle_to(spot: Vector2) -> void:
	_ask(Do.SHUFFLE, spot)


# On his feet, in depth to where `spot` falls behind or ahead of him.
func c_cut_to(spot: Vector2) -> void:
	_ask(Do.C_CUT, spot)


func drop_down() -> void:
	_ask(Do.DROP)


func rise() -> void:
	_ask(Do.RISE)


# Up toward `toward` (+1 his blocker side), the far leg first.
func recover(toward: float) -> void:
	_ask(Do.RECOVER, Vector2.ZERO, toward)


# Down, slide to `spot` pushing at up to `top`.
func slide_to(spot: Vector2, top: float = INF) -> void:
	_ask(Do.SLIDE, spot, 0.0, top)


func slide_from_feet(spot: Vector2, top: float = INF) -> void:
	_ask(Do.SLIDE_FROM_FEET, spot, 0.0, top)


# Into the RVH on the post at `iron` on `side`: dropping in from his feet on
# the overlap, or coming up into it from the butterfly.
func rvh_drop_in(iron: Vector2, side: float) -> void:
	_ask(Do.RVH_DROP_IN, iron, side)


func rvh_slide_in(iron: Vector2, side: float) -> void:
	_ask(Do.RVH_SLIDE_IN, iron, side)


func rvh_rise_out() -> void:
	_ask(Do.RVH_RISE_OUT)


func rvh_fold_out() -> void:
	_ask(Do.RVH_FOLD_OUT)


# Whether a low save can cut in now: from his feet, standing or with footwork
# or a pivot under way; down (`down`), only once he is at rest there.
func can_save(down: bool) -> bool:
	if down:
		return rest == Rest.DOWN and _mover == Mover.NONE
	return rest == Rest.FEET and (_mover == Mover.NONE or _mover == Mover.PIVOT or _mover == Mover.FOOTWORK
			or _mover == Mover.GLIDE)


# The low save `low` to `side`, cutting in now.
func save(low: int, side: float) -> void:
	pose(_cut)
	save_move.fall = low_ready.fall_share()
	low_ready.cut()
	save_move.start(_cut, low, side, Vector2(x, z), _velocity)
	footwork.set_still()
	lead = 0.0
	_queue.clear()
	_mover = Mover.SAVE


# The shot a save was made for is over.
func end_save() -> void:
	if _mover == Mover.SAVE:
		save_move.release()


func _ask(what: int, spot: Vector2 = Vector2.ZERO, side: float = 0.0, top: float = INF) -> void:
	_goal = false
	_queue.append(_Ask.new(what, spot, side, top))


# Every move asked for done and settled, and where he was asked to be (a glide
# there, his legs still settling into the stance, counts).
func is_idle() -> bool:
	var still: bool = _mover == Mover.NONE or (_mover == Mover.GLIDE and _glided_there())
	return still and _queue.is_empty() and (not _goal or _plan() == Do.NONE)


# Gliding, on a spot at rest and square: there, his legs only still settling.
func _glided_there() -> bool:
	return _spot_velocity.length() <= MOVING_M_S and glide.is_on(route.spot, Vector2.ZERO) and lead == 0.0 \
			and absf(wrapf(route.facing - yaw, -PI, PI)) < 1e-5


# The fastest way's time to where he is asked to be, from where he is now and
# at rest; 0 there.
func time_to_goal() -> float:
	return route.plan(Vector2(x, z), yaw, rest, post.side) if _goal else 0.0


# The fastest way's time from here into the RVH on the post at `iron` on
# `side`, whatever he is asked to do.
func time_to_seal(iron: Vector2, side: float) -> float:
	return route.time_to_seal(Vector2(x, z), yaw, rest, post.side, iron, side)


func _plan() -> int:
	route.plan(Vector2(x, z), yaw, rest, post.side)
	return route.first


func step(dt: float) -> void:
	var was := Vector2(x, z)
	_step_mover(dt)
	# Sunk while set on his feet and asked, out of it with any move; a drop or
	# a save goes from where he has sunk to (KeeperDrop.drop_from, `save`).
	low_ready.step(dt, _mover == Mover.NONE and rest == Rest.FEET)
	_velocity = (Vector2(x, z) - was) / maxf(dt, 1e-6)


func _step_mover(dt: float) -> void:
	if _mover == Mover.NONE:
		_start_next()
		if _mover == Mover.NONE and _goal and _plan() != Do.NONE:
			if _glides():
				_start_glide()
			elif not _start(route.first, route.first_spot, route.first_side, INF):
				refused += 1
	match _mover:
		Mover.PIVOT:
			footwork.step(dt)
			_pivot(dt)
		Mover.FOOTWORK:
			footwork.step(dt)
			var at: Vector2 = _anchor + _turned(Vector2(footwork.x, footwork.z), _anchor_yaw)
			x = at.x
			z = at.y
			_lead_on(dt)
			if footwork.phase == KeeperFootwork.Phase.SET and lead == 0.0 \
					and (footwork.is_settled() or (_goal and footwork.is_recovered() and _next_is_footwork())):
				_mover = Mover.NONE
		Mover.DROP:
			drop.step(dt)
			if drop.state == KeeperDrop.State.UP:
				_rest_on(Rest.FEET)
			elif drop.state == KeeperDrop.State.DOWN:
				_rest_on(Rest.DOWN)
		Mover.SLIDE:
			slide.step(dt)
			x = slide.x
			z = slide.z
			yaw = slide.yaw
			if slide.is_settled():
				_rest_on(Rest.DOWN)
		Mover.POST:
			post.step(dt)
			x = post.x
			z = post.z
			yaw = post.yaw
			match post.state:
				KeeperPost.State.SEALED:
					_rest_on(Rest.POST)
				KeeperPost.State.STANDING:
					_rest_on(Rest.FEET)
				KeeperPost.State.BUTTERFLY:
					_rest_on(Rest.DOWN)
		Mover.SAVE:
			save_move.step(dt)
			x = save_move.x
			z = save_move.z
			if save_move.is_done():
				_rest_on(Rest.DOWN if save_move.rests_down() else Rest.FEET)
		Mover.GLIDE:
			_step_glide(dt)


# Whether the goal is one he skates to as it moves: on his feet, standing, near
# him, moving, or one to skate to however far.
func _glides() -> bool:
	return route.rest == Rest.FEET and rest == Rest.FEET \
			and (_skate or _spot_velocity.length() > MOVING_M_S or route.first == Do.GLIDE)


func _start_glide() -> void:
	glide.x = x
	glide.z = z
	glide.velocity = _velocity
	footwork.set_still()
	_mover = Mover.GLIDE


# Skating with the spot, his trunk turned on toward its facing and his skates
# after it; done once he is on a spot at rest, square, his legs settled. A goal
# that is no longer on his feet, or none, he stops for first where he is.
func _step_glide(dt: float) -> void:
	if not _goal or route.rest != Rest.FEET:
		glide.step(dt, Vector2(glide.x, glide.z), Vector2.ZERO, yaw)
		x = glide.x
		z = glide.z
		if glide.velocity == Vector2.ZERO and glide.is_settled():
			_mover = Mover.NONE
		return
	# The spot carried on at its own speed since it was given, so he skates
	# with it rather than past it and back between the brain's looks.
	_spot_since += dt
	glide.step(dt, route.spot + _spot_velocity * _spot_since, _spot_velocity, yaw)
	x = glide.x
	z = glide.z
	var turn: float = PIVOT_RATE_RAD_S * dt
	var body: float = _turned_toward(yaw + lead, route.facing, turn)
	yaw = _turned_toward(yaw, body, turn)
	lead = wrapf(body - yaw, -PI, PI)
	if absf(lead) < 1e-6:
		lead = 0.0
	if _glided_there():
		yaw = route.facing
		if glide.is_settled():
			_mover = Mover.NONE


func _rest_on(r: int) -> void:
	rest = r
	_mover = Mover.NONE


func _start_next() -> void:
	while _mover == Mover.NONE and not _queue.is_empty():
		var ask: _Ask = _queue.pop_front()
		if not _start(ask.what, ask.spot, ask.side, ask.top):
			refused += 1


func _start(what: int, spot: Vector2, side: float, top: float) -> bool:
	match what:
		Do.FACE:
			if rest != Rest.FEET:
				return false
			_face = side
			_turn_rate = 0.0
			_mover = Mover.PIVOT
		Do.T_PUSH, Do.SHUFFLE, Do.C_CUT:
			if rest != Rest.FEET:
				return false
			_anchor = Vector2(x, z)
			_anchor_yaw = yaw
			footwork.x = 0.0
			footwork.z = 0.0
			var local: Vector2 = _turned(spot - _anchor, -yaw)
			match what:
				Do.T_PUSH:
					footwork.push_to(local)
				Do.SHUFFLE:
					footwork.shuffle_to(local.x)
				Do.C_CUT:
					footwork.c_cut_to(local.y)
			_mover = Mover.FOOTWORK
		Do.DROP:
			if rest != Rest.FEET:
				return false
			drop.state = KeeperDrop.State.UP
			drop.down = 0.0
			drop.fall = low_ready.fall_share()
			if low_ready.share > 0.0:
				pose(_cut)
				low_ready.cut()
				drop.drop_from(_cut)
			else:
				drop.drop()
			_mover = Mover.DROP
		Do.RISE, Do.RECOVER:
			if rest != Rest.DOWN:
				return false
			drop.state = KeeperDrop.State.DOWN
			drop.down = 1.0
			if what == Do.RISE:
				drop.rise()
			else:
				drop.recover(side)
			_mover = Mover.DROP
		Do.SLIDE, Do.SLIDE_FROM_FEET:
			if rest != (Rest.DOWN if what == Do.SLIDE else Rest.FEET):
				return false
			slide.x = x
			slide.z = z
			slide.yaw = yaw
			if what == Do.SLIDE:
				slide.slide_to(spot, top)
			else:
				slide.slide_from_feet(spot, top)
			_mover = Mover.SLIDE
		Do.RVH_DROP_IN, Do.RVH_SLIDE_IN:
			if rest != (Rest.FEET if what == Do.RVH_DROP_IN else Rest.DOWN):
				return false
			post.x = x
			post.z = z
			post.yaw = yaw
			if what == Do.RVH_DROP_IN:
				post.state = KeeperPost.State.STANDING
				post.drop_in(spot, side)
			else:
				post.state = KeeperPost.State.BUTTERFLY
				post.slide_in(spot, side)
			_mover = Mover.POST
		Do.RVH_RISE_OUT, Do.RVH_FOLD_OUT:
			if rest != Rest.POST:
				return false
			if what == Do.RVH_RISE_OUT:
				post.rise_out()
			else:
				post.fold_out()
			_mover = Mover.POST
	return true


# Toward the facing asked for at up to PIVOT_RATE_RAD_S, starting and stopping
# on his edges at PIVOT_ACCEL_RAD_S2, so he stops turned exactly there.
# His trunk toward the goal's facing while footwork carries him, no more than
# LEAD_MAX_RAD ahead of his skates; once he is set on the spot, his skates
# turn under him after it.
func _lead_on(dt: float) -> void:
	var facing: float = route.facing if _goal and route.rest == Rest.FEET else yaw + lead
	var body: float = yaw + lead
	var turn: float = PIVOT_RATE_RAD_S * dt
	if footwork.phase == KeeperFootwork.Phase.SET:
		body = _turned_toward(body, facing, turn)
		yaw = _turned_toward(yaw, body, turn)
	else:
		var ahead: float = clampf(wrapf(facing - yaw, -PI, PI), -LEAD_MAX_RAD, LEAD_MAX_RAD)
		body = _turned_toward(body, yaw + ahead, turn)
	lead = wrapf(body - yaw, -PI, PI)
	if absf(lead) < 1e-6:
		lead = 0.0


static func _turned_toward(from: float, to: float, most: float) -> float:
	var left: float = wrapf(to - from, -PI, PI)
	return wrapf(from + signf(left) * minf(most, absf(left)), -PI, PI)


func _next_is_footwork() -> bool:
	var next: int = _plan()
	return next == Do.T_PUSH or next == Do.SHUFFLE or next == Do.C_CUT or next == Do.FACE or next == Do.GLIDE


# His trunk, where it leads, turns on at up to the same rate, never past it.
func _pivot(dt: float) -> void:
	var body: float = yaw + lead
	var left: float = wrapf(_face - yaw, -PI, PI)
	var cap: float = sqrt(2.0 * PIVOT_ACCEL_RAD_S2 * absf(left))
	_turn_rate = minf(minf(_turn_rate + PIVOT_ACCEL_RAD_S2 * dt, PIVOT_RATE_RAD_S), cap)
	var turn: float = signf(left) * minf(_turn_rate * dt, absf(left))
	yaw = wrapf(yaw + turn, -PI, PI)
	var body_left: float = wrapf(_face - body, -PI, PI)
	body += signf(body_left) * minf(PIVOT_RATE_RAD_S * dt, absf(body_left))
	lead = wrapf(body - yaw, -PI, PI)
	if absf(wrapf(_face - yaw, -PI, PI)) < 1e-5 and absf(lead) < 1e-5:
		yaw = _face
		lead = 0.0
		_turn_rate = 0.0
		_mover = Mover.NONE


# His pose this tick, in his skates' frame.
func pose(p: KeeperPose) -> void:
	_pose_mover(p)
	low_ready.lay_over(p, _mover == Mover.NONE and rest == Rest.FEET and footwork.is_settled())
	if lead != 0.0:
		_turn_body(p, lead)


func _pose_mover(p: KeeperPose) -> void:
	match _mover:
		Mover.FOOTWORK:
			footwork.pose(p)
		Mover.DROP:
			drop.pose(p)
		Mover.SLIDE:
			slide.pose(p)
		Mover.POST:
			post.pose(p)
		Mover.SAVE:
			save_move.pose(p)
		Mover.GLIDE:
			glide.pose(p)
		_:
			match rest:
				Rest.FEET:
					footwork.pose(p)
				Rest.DOWN:
					slide.pose(p)
				Rest.POST:
					post.pose(p)


# His trunk turned `turn` ahead of his skates from the waist, about the
# vertical through his hips, the hands and the stick they hold with it. The
# pelvis stays with the legs: turned, it would carry the hips round over skates
# that stay on their line and pitch a pad into the ice.
static func _turn_body(p: KeeperPose, turn: float) -> void:
	var about := Basis(Vector3.UP, turn)
	var hips := Vector3(p.pelvis.x, 0.0, p.pelvis.z)
	p.lumbar_rot.y += turn
	p.blade_center = hips + about * (p.blade_center - hips)
	p.blade_yaw -= turn
	p.blocker_face = about * p.blocker_face
	p.glove_fingers = about * p.glove_fingers
	p.glove_palm = about * p.glove_palm
	p.glove_elbow_pole = about * p.glove_elbow_pole
	p.blocker_elbow_pole = about * p.blocker_elbow_pole
	if not p.glove_from_chest:
		p.glove_hand = hips + about * (p.glove_hand - hips)


# `v` on the ice in his own frame, turned `turn` into the stances' frame.
static func _turned(v: Vector2, turn: float) -> Vector2:
	return Vector2(v.x * cos(turn) + v.y * sin(turn), -v.x * sin(turn) + v.y * cos(turn))

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
# there. A new spot along a pivot or footwork under way takes it over; any
# other change waits for him to come to rest. The last order wins: a goal
# clears the moves asked for, and a move asked for clears the goal.
#
# Places are in the stances' frame, as the movers': x across, z depth (+ back
# toward his net), `yaw` his turn about the vertical, as a Node3D's rotation.y.

const Rest := KeeperRoute.Rest
const Do := KeeperRoute.Do
enum Mover { NONE, PIVOT, FOOTWORK, DROP, SLIDE, POST }

# The pivot: its top turn rate, near the old goalie's (whose 5/s lerp turns him
# through 45° at up to 3.9 rad/s), and how hard his edges start and stop it.
const PIVOT_RATE_RAD_S: float = 4.0
const PIVOT_ACCEL_RAD_S2: float = 40.0

var x: float = 0.0
var z: float = 0.0
var yaw: float = 0.0
var rest: int = Rest.FEET
# Moves asked for from a rest they cannot start from.
var refused: int = 0

var footwork := KeeperFootwork.new()
var drop := KeeperDrop.new()
var slide := KeeperSlide.new()
var post := KeeperPost.new()
var route := KeeperRoute.new(footwork, drop, slide, post, PIVOT_RATE_RAD_S, PIVOT_ACCEL_RAD_S2)

var _queue: Array[_Ask] = []
var _goal: bool = false
var _mover: int = Mover.NONE
# The pivot's target and rate; where a footwork move set out from, and his
# turn on it.
var _face: float = 0.0
var _turn_rate: float = 0.0
var _anchor := Vector2.ZERO
var _anchor_yaw: float = 0.0


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


# Be on his feet at `spot` facing `facing`, or down at `spot` (`on` Rest.DOWN).
func go_to(spot: Vector2, facing: float, on: int = Rest.FEET) -> void:
	_queue.clear()
	_goal = true
	route.rest = on
	route.spot = spot
	route.facing = facing
	_retarget()


# Be sealed in the RVH on the post at `iron` on `side`.
func seal(iron: Vector2, side: float) -> void:
	_queue.clear()
	_goal = true
	route.rest = Rest.POST
	route.iron = iron
	route.side = side


# A pivot under way turns on to the new facing; footwork under way, still
# facing it, goes on to where the new spot falls on its line.
func _retarget() -> void:
	if route.rest != Rest.FEET:
		return
	if _mover == Mover.PIVOT:
		_face = route.facing
	elif _mover == Mover.FOOTWORK and absf(wrapf(route.facing - yaw, -PI, PI)) <= KeeperRoute.FACED_RAD:
		var local: Vector2 = _turned(route.spot - _anchor, -_anchor_yaw)
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


func _ask(what: int, spot: Vector2 = Vector2.ZERO, side: float = 0.0, top: float = INF) -> void:
	_goal = false
	_queue.append(_Ask.new(what, spot, side, top))


# Every move asked for done and settled, and where he was asked to be.
func is_idle() -> bool:
	return _mover == Mover.NONE and _queue.is_empty() and (not _goal or _plan() == Do.NONE)


# The fastest way's time to where he is asked to be, from where he is now and
# at rest; 0 there.
func time_to_goal() -> float:
	return route.plan(Vector2(x, z), yaw, rest, post.side) if _goal else 0.0


func _plan() -> int:
	route.plan(Vector2(x, z), yaw, rest, post.side)
	return route.first


func step(dt: float) -> void:
	if _mover == Mover.NONE:
		_start_next()
		if _mover == Mover.NONE and _goal and _plan() != Do.NONE \
				and not _start(route.first, route.first_spot, route.first_side, INF):
			refused += 1
	match _mover:
		Mover.PIVOT:
			_pivot(dt)
		Mover.FOOTWORK:
			footwork.step(dt)
			var at: Vector2 = _anchor + _turned(Vector2(footwork.x, footwork.z), _anchor_yaw)
			x = at.x
			z = at.y
			if footwork.is_settled():
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
func _pivot(dt: float) -> void:
	var left: float = wrapf(_face - yaw, -PI, PI)
	var cap: float = sqrt(2.0 * PIVOT_ACCEL_RAD_S2 * absf(left))
	_turn_rate = minf(minf(_turn_rate + PIVOT_ACCEL_RAD_S2 * dt, PIVOT_RATE_RAD_S), cap)
	var turn: float = signf(left) * minf(_turn_rate * dt, absf(left))
	yaw = wrapf(yaw + turn, -PI, PI)
	if absf(wrapf(_face - yaw, -PI, PI)) < 1e-5:
		yaw = _face
		_turn_rate = 0.0
		_mover = Mover.NONE


# His pose this tick, in his own frame.
func pose(p: KeeperPose) -> void:
	match _mover:
		Mover.FOOTWORK:
			footwork.pose(p)
		Mover.DROP:
			drop.pose(p)
		Mover.SLIDE:
			slide.pose(p)
		Mover.POST:
			post.pose(p)
		_:
			match rest:
				Rest.FEET:
					footwork.pose(p)
				Rest.DOWN:
					slide.pose(p)
				Rest.POST:
					post.pose(p)


# `v` on the ice in his own frame, turned `turn` into the stances' frame.
static func _turned(v: Vector2, turn: float) -> Vector2:
	return Vector2(v.x * cos(turn) + v.y * sin(turn), -v.x * sin(turn) + v.y * cos(turn))

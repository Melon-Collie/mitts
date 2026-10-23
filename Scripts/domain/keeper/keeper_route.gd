class_name KeeperRoute
extends RefCounted

# Where he is asked to be, and the fastest way there from where he is: the
# way's first move, and how long the whole way takes. The motor makes the move;
# the brain reads the time. Pure: the times are the movers' own models
# (GoaliePushRules for the footwork, the slide's push and stop, the drop's, the
# rise's and the RVH's clocks, the pivot's rate), and the spots theirs (the
# slide's to a post, the RVH's overlap and seal).
#
# The way is planned a move at a time: the motor makes the first move, and once
# he has come to rest from it the way is planned again from there. Every way
# below is timed to rest at its end, the settle a move needs before the next
# can start included.

enum Rest { FEET, DOWN, POST }
enum Do {
	NONE, FACE, T_PUSH, SHUFFLE, C_CUT, DROP, RISE, RECOVER, SLIDE, SLIDE_FROM_FEET,
	RVH_DROP_IN, RVH_SLIDE_IN, RVH_RISE_OUT, RVH_FOLD_OUT,
}

# Within these of his spot and his facing he is there.
const THERE_M: float = 0.01
const FACED_RAD: float = 0.02
# Equal times to a tick's width: the shuffle, square on both skates, is taken
# over a T-push that gets him there no sooner.
const TIE_S: float = 1.0 / 240.0
# The steepest diagonal a way plans, just inside the T-push's own, so float
# rounding never tips its spot past it onto his line.
const _DIAGONAL_TAN: float = 0.99

# Where he is asked to be: resting on `rest`; on his feet at `spot` facing
# `facing`, or down at `spot` (his turn there is the slide's), or sealed on the
# post at `iron` (x, z) on `side` (+1 his blocker side).
var rest: int = Rest.FEET
var spot := Vector2.ZERO
var facing: float = 0.0
var iron := Vector2.ZERO
var side: float = 1.0

# The way's first move: what, to where, and its side (the turn to face, the way
# a recovery goes, the post's side).
var first: int = Do.NONE
var first_spot := Vector2.ZERO
var first_side: float = 0.0

var _footwork: KeeperFootwork
var _drop: KeeperDrop
var _slide: KeeperSlide
var _post: KeeperPost
var _pivot_rate: float
var _pivot_accel: float

var _best: float = INF
# A way's first move, as the way that found it leaves it: one on his feet
# (_on_feet) and one from the butterfly to a post (_down_to_post).
var _step_do: int = Do.NONE
var _step_spot := Vector2.ZERO
var _down_do: int = Do.NONE
var _down_spot := Vector2.ZERO
var _down_side: float = 0.0


func _init(footwork: KeeperFootwork, drop: KeeperDrop, slide: KeeperSlide, post: KeeperPost,
		pivot_rate: float, pivot_accel: float) -> void:
	_footwork = footwork
	_drop = drop
	_slide = slide
	_post = post
	_pivot_rate = pivot_rate
	_pivot_accel = pivot_accel


# The fastest way from `at` turned `turn`, resting on `from` (on a post, the
# one on `post_side`): its time, and its first move in `first`. There already,
# 0 and no move.
func plan(at: Vector2, turn: float, from: int, post_side: float) -> float:
	first = Do.NONE
	first_spot = Vector2.ZERO
	first_side = 0.0
	_best = INF
	match rest:
		Rest.FEET:
			_to_feet(at, turn, from)
		Rest.DOWN:
			_to_down(at, turn, from)
		Rest.POST:
			_to_post(at, turn, from, post_side)
	return _best


func _offer(t: float, what: int, to: Vector2 = Vector2.ZERO, way: float = 0.0) -> void:
	if t < _best:
		_best = t
		first = what
		first_spot = to
		first_side = way


func _to_feet(at: Vector2, turn: float, from: int) -> void:
	var turning: float = pivot_time(wrapf(facing - turn, -PI, PI))
	match from:
		Rest.POST:
			_offer(_post.rise_s + turning + _on_feet(_post.risen_spot(), facing, spot), Do.RVH_RISE_OUT)
		Rest.DOWN:
			var t: float = _drop.rise_s + turning + _on_feet(at, facing, spot)
			var across: float = _local(spot - at, turn).x
			if absf(across) < THERE_M:
				_offer(t, Do.RISE)
			else:
				_offer(t, Do.RECOVER, Vector2.ZERO, signf(across))
		Rest.FEET:
			if absf(wrapf(facing - turn, -PI, PI)) > FACED_RAD:
				_offer(turning + _on_feet(at, facing, spot), Do.FACE, Vector2.ZERO, facing)
			else:
				_offer(_on_feet(at, turn, spot), _step_do, _step_spot)


func _to_down(at: Vector2, turn: float, from: int) -> void:
	var d: float = at.distance_to(spot)
	match from:
		Rest.POST:
			_offer(KeeperPost.OUT_TO_BUTTERFLY_S + _down_to_down(at, turn), Do.RVH_FOLD_OUT)
		Rest.DOWN:
			_offer(_down_to_down(at, turn), _down_do, _down_spot, _down_side)
		Rest.FEET:
			if d < THERE_M:
				_offer(_drop.drop_s, Do.DROP)
				return
			if _slidable(at, turn, spot):
				_offer(_slides_time(d, true), Do.SLIDE_FROM_FEET, spot)
			var t: float = _on_feet(at, turn, spot)
			_offer(t + _drop.drop_s, _step_do, _step_spot)


func _to_post(at: Vector2, turn: float, from: int, post_side: float) -> void:
	match from:
		Rest.POST:
			if post_side == side and at.distance_to(_post.seal_spot(iron, side)) < THERE_M:
				_offer(0.0, Do.NONE)
				return
			_offer(KeeperPost.OUT_TO_BUTTERFLY_S + _down_to_post(at, turn), Do.RVH_FOLD_OUT)
		Rest.DOWN:
			_offer(_down_to_post(at, turn), _down_do, _down_spot, _down_side)
		Rest.FEET:
			var t: float = _dropped_in(at, turn)
			if absf(wrapf(turn, -PI, PI)) > FACED_RAD:
				_offer(t, Do.FACE)
			elif _step_do == Do.NONE:
				_offer(t, Do.RVH_DROP_IN, iron, side)
			else:
				_offer(t, _step_do, _step_spot)
			# Or slid across to the post from his feet and up into it.
			var to: Vector2 = _post_spot(at, turn)
			var d: float = at.distance_to(to)
			if d >= THERE_M and _slidable(at, turn, to):
				var slid: float = _slides_time(d, true) + KeeperPost.IN_FROM_BUTTERFLY_S
				_offer(slid, Do.SLIDE_FROM_FEET, to)


# From the butterfly to the goal's spot, down: slid there, or, where the slide
# is off his line, up, there on his feet and down again. Its time; its first
# move in _down_do, _down_spot and _down_side.
func _down_to_down(at: Vector2, turn: float) -> float:
	_down_do = Do.NONE
	_down_spot = spot
	_down_side = 0.0
	if at.distance_to(spot) < THERE_M:
		return 0.0
	var best: float = INF
	if _slidable(at, turn, spot):
		best = _slides_time(at.distance_to(spot), false)
		_down_do = Do.SLIDE
	var up: float = _drop.rise_s + _on_feet(at, turn, spot) + _drop.drop_s
	if up < best:
		best = up
		var across: float = _local(spot - at, turn).x
		_down_do = Do.RISE if absf(across) < THERE_M else Do.RECOVER
		_down_spot = Vector2.ZERO
		_down_side = signf(across)
	return best


# On his feet into the RVH on the goal's post: turned square, onto the
# overlap, dropped in. Its time; the footwork's first move in _step_do and
# _step_spot.
func _dropped_in(at: Vector2, turn: float) -> float:
	var walk: float = _on_feet(at, 0.0, _post.overlap_spot(iron, side))
	return pivot_time(wrapf(-turn, -PI, PI)) + walk + _post.drop_s


# From the butterfly into the RVH on the goal's post: slid along to the spot
# that lands the pad's end on it, then up into it; or, where that slide is off
# his line, up and onto the overlap to drop in. Its time; its first move in
# _down_do, _down_spot and _down_side.
func _down_to_post(at: Vector2, turn: float) -> float:
	var to: Vector2 = _post_spot(at, turn)
	var d: float = at.distance_to(to)
	_down_spot = iron
	_down_side = side
	if d < THERE_M:
		_down_do = Do.RVH_SLIDE_IN
		return KeeperPost.IN_FROM_BUTTERFLY_S
	var best: float = INF
	if _slidable(at, turn, to):
		best = _slides_time(d, false) + KeeperPost.IN_FROM_BUTTERFLY_S
		_down_do = Do.SLIDE
		_down_spot = to
	var up: float = _drop.rise_s + _dropped_in(at, turn)
	if up < best:
		best = up
		var across: float = _local(_post.overlap_spot(iron, side) - at, turn).x
		_down_do = Do.RISE if absf(across) < THERE_M else Do.RECOVER
		_down_spot = Vector2.ZERO
		_down_side = signf(across)
	return best


# Whether a slide from `at` turned `turn` to `to` is one he takes.
static func _slidable(at: Vector2, turn: float, to: Vector2) -> bool:
	var local: Vector2 = _local(to - at, turn)
	return absf(local.y) <= absf(local.x) * tan(KeeperSlide.MAX_OFF_LINE_RAD) + 1e-6


# The slide's spot to the goal's post from `at` turned `turn`.
func _post_spot(at: Vector2, turn: float) -> Vector2:
	# The slide reads its side from its own turn; the motor sets it on each
	# slide's start, so it is free while he rests.
	_slide.yaw = turn
	return _slide.post_spot(iron, at)


# The fastest footwork from `at` turned `turn` to `to`, square, each move's
# stop settled: its time, its first move in _step_do and _step_spot.
func _on_feet(at: Vector2, turn: float, to: Vector2) -> float:
	_step_spot = to
	var local: Vector2 = _local(to - at, turn)
	var across: float = absf(local.x)
	var deep: float = absf(local.y)
	if local.length() < THERE_M:
		_step_do = Do.NONE
		return 0.0
	var steepest: float = tan(KeeperFootwork.DIAGONAL_MAX_RAD) * _DIAGONAL_TAN
	if deep <= across * tan(KeeperFootwork.DIAGONAL_MAX_RAD):
		var pushed: float = _push_time(local.length())
		if deep < THERE_M and _shuffle_time(across) <= pushed + TIE_S:
			_step_do = Do.SHUFFLE
			return _shuffle_time(across)
		_step_do = Do.T_PUSH
		return pushed
	if across < THERE_M:
		_step_do = Do.C_CUT
		return _c_cut_time(deep)
	# Steeper than a T-push goes: in depth then across, or the steepest
	# diagonal then the rest in depth.
	var depth_first: float = _c_cut_time(deep) + _push_time(across)
	var diagonal := Vector2(local.x, signf(local.y) * across * steepest)
	var diagonal_first: float = _push_time(diagonal.length()) + _c_cut_time(deep - across * steepest)
	if depth_first <= diagonal_first:
		_step_do = Do.C_CUT
		return depth_first
	_step_do = Do.T_PUSH
	_step_spot = at + _world(diagonal, turn)
	return diagonal_first


# Slides one after another to `d` away, each as far as its push carries; the
# first from his feet if `from_feet`. A slide that carries as far as it goes
# coasts to rest; the last, stopped on its spot by the edge, settles.
func _slides_time(d: float, from_feet: bool) -> float:
	var reach: float = _slide.glide_reach(_slide.push_speed)
	var t: float = 0.0
	var feet: bool = from_feet
	while d > reach:
		t += _slide.time_to(reach, INF, feet)
		d -= reach
		feet = false
	return t + _slide.time_to(d, INF, feet) + KeeperSlide.SETTLE_S


func _push_time(d: float) -> float:
	return GoaliePushRules.time_to_set(d, _footwork.t_push_speed, _footwork.accel) + KeeperFootwork.SETTLE_S


func _shuffle_time(d: float) -> float:
	return GoaliePushRules.time_to_set(d, _footwork.shuffle_speed, _footwork.accel) + KeeperFootwork.SETTLE_S


func _c_cut_time(d: float) -> float:
	return GoaliePushRules.time_to_set(d, _footwork.c_cut_speed, _footwork.accel) + KeeperFootwork.SETTLE_S


# Seconds the pivot takes through `turn`: up to its rate on his edges and back
# off it, or as fast as it gets in between on a short one.
func pivot_time(turn: float) -> float:
	var a: float = absf(turn)
	var full: float = _pivot_rate * _pivot_rate / _pivot_accel
	if a <= full:
		return 2.0 * sqrt(a / _pivot_accel)
	return a / _pivot_rate + _pivot_rate / _pivot_accel


# `v` on the ice in the stances' frame, in his own turned `turn`, and back.
static func _local(v: Vector2, turn: float) -> Vector2:
	return Vector2(v.x * cos(turn) - v.y * sin(turn), v.x * sin(turn) + v.y * cos(turn))


static func _world(v: Vector2, turn: float) -> Vector2:
	return Vector2(v.x * cos(turn) + v.y * sin(turn), -v.x * sin(turn) + v.y * cos(turn))

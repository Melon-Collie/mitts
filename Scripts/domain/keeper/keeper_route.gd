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
	RVH_DROP_IN, RVH_SLIDE_IN, RVH_RISE_OUT, RVH_FOLD_OUT, GLIDE, ROTATE, RVH_PUSH_OFF,
}
const FROM := KeeperSlide.From

# Within these of his spot and his facing he is there: a goal that drifts no
# further moves him not at all, rather than in steps of millimetres.
const THERE_M: float = 0.03
const FACED_RAD: float = deg_to_rad(2.0)
# Down, within this of his facing he is turned to it: a smaller turn his hips
# and shoulders make over the pads (KeeperLook's trunk), not a rotation.
const DOWN_FACED_RAD: float = deg_to_rad(10.0)
# How far off the line of footwork under way a new spot may lie and still be
# taken on by it; further, the move ends and the way is planned again.
const ON_LINE_M: float = 0.05
# Equal times to a tick's width: the shuffle, square on both skates, is taken
# over a T-push that gets him there no sooner.
const TIE_S: float = 1.0 / 240.0
# The steepest diagonal a way plans, just inside the T-push's own, so float
# rounding never tips its spot past it onto his line.
const _DIAGONAL_TAN: float = 0.99
# A spot on his feet this near he skates to (KeeperGlide), turning as he goes;
# further, footwork's moves take him.
const GLIDE_REACH_M: float = 1.0
# How near the post's overlap at the turn he stands at he is on the post: near
# enough that the drop into the RVH, which swings him square onto the seal as
# the knee falls, takes him in from there.
const ON_POST_M: float = 0.15

# Where he is asked to be: resting on `rest`; on his feet or down at `spot`
# facing `facing` (down, he rotates on his knees to it), or sealed on the post
# at `iron` (x, z) on `side` (+1 his blocker side).
var rest: int = Rest.FEET
var spot := Vector2.ZERO
var facing: float = 0.0
var iron := Vector2.ZERO
var side: float = 1.0

# The way's first move: what, to where, and its side (the turn to face or to
# rotate to, the way a recovery goes, the post's side).
var first: int = Do.NONE
var first_spot := Vector2.ZERO
var first_side: float = 0.0

var _footwork: KeeperFootwork
var _drop: KeeperDrop
var _slide: KeeperSlide
var _post: KeeperPost
var _pivot_rate: float
var _pivot_accel: float
var _lead_max: float

var _best: float = INF
# A way's first move, as the way that found it leaves it: one on his feet
# (_on_feet) and one from the butterfly to a post (_down_to_post).
var _step_do: int = Do.NONE
var _step_spot := Vector2.ZERO
var _step_legs: int = 0
# How long after that way sets him on its spot his push leg is still coming
# back under him (_hand_off of its last move).
var _step_hand_off: float = 0.0
# Whether the way _on_feet last timed ends in a glide, which no settle follows.
var _glides_last: bool = false
var _way_do: int = Do.NONE
var _way_spot := Vector2.ZERO
var _way_side: float = 0.0
var _down_do: int = Do.NONE
var _down_spot := Vector2.ZERO
var _down_side: float = 0.0


func _init(footwork: KeeperFootwork, drop: KeeperDrop, slide: KeeperSlide, post: KeeperPost,
		pivot_rate: float, pivot_accel: float, lead_max: float) -> void:
	_footwork = footwork
	_drop = drop
	_slide = slide
	_post = post
	_pivot_rate = pivot_rate
	_pivot_accel = pivot_accel
	_lead_max = lead_max


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
			_to_down(at, turn, from, post_side)
		Rest.POST:
			_to_post(at, turn, from, post_side)
	return _best


# The fastest way's time into the RVH on the post at `post_iron` on `post_on`,
# from as `plan` takes it, leaving the goal and its first move as they were.
func time_to_seal(at: Vector2, turn: float, from: int, post_side: float, post_iron: Vector2,
		post_on: float) -> float:
	var was_rest: int = rest
	var was_iron: Vector2 = iron
	var was_side: float = side
	var was_first: int = first
	var was_spot: Vector2 = first_spot
	var was_way: float = first_side
	rest = Rest.POST
	iron = post_iron
	side = post_on
	var t: float = plan(at, turn, from, post_side)
	rest = was_rest
	iron = was_iron
	side = was_side
	first = was_first
	first_spot = was_spot
	first_side = was_way
	return t


func _offer(t: float, what: int, to: Vector2 = Vector2.ZERO, way: float = 0.0) -> void:
	if t < _best:
		_best = t
		first = what
		first_spot = to
		first_side = way


func _to_feet(at: Vector2, turn: float, from: int) -> void:
	match from:
		Rest.POST:
			# Up square onto the overlap.
			_offer(_post.rise_s + _up_to(_post.risen_spot(), 0.0), Do.RVH_RISE_OUT)
		Rest.DOWN:
			var t: float = _drop.rise_s + _up_to(at, turn)
			var across: float = _local(spot - at, turn).x
			if absf(across) < THERE_M:
				_offer(t, Do.RISE)
			else:
				_offer(t, Do.RECOVER, Vector2.ZERO, signf(across))
		Rest.FEET:
			var t: float = _up_to(at, turn)
			if _glide_to(at, turn):
				_offer(t, Do.GLIDE, spot)
			else:
				_offer(t, _way_do, _way_spot, _way_side)


# Whether, on his feet at `at` turned `turn`, he skates to the goal's spot.
func _glide_to(at: Vector2, turn: float) -> bool:
	var d: float = at.distance_to(spot)
	return d <= GLIDE_REACH_M and (d >= THERE_M or absf(wrapf(facing - turn, -PI, PI)) > FACED_RAD)


# On his feet at `at` turned `turn`, the time to the goal's spot and facing:
# skated to within the glide's reach, footwork's moves past it (their first
# move left in _way_do, _way_spot and _way_side).
func _up_to(at: Vector2, turn: float) -> float:
	if _glide_to(at, turn):
		var way: Vector2 = _local(spot - at, turn)
		return glide_time(way.length(), wrapf(facing - turn, -PI, PI), absf(way.y) / maxf(way.length(), 1e-6))
	return _standing(at, turn)


# On his feet at `at` turned `turn`, to the goal's spot and facing. A turn the
# trunk can lead on a single move is made on the way, the skates catching up
# as the stop settles; any other, first, the footwork planned after it. Its
# time; its first move in _way_do, _way_spot and _way_side.
func _standing(at: Vector2, turn: float) -> float:
	var off: float = absf(wrapf(facing - turn, -PI, PI))
	var walk: float = _on_feet(at, turn, spot)
	_way_do = _step_do
	_way_spot = _step_spot
	_way_side = 0.0
	if off <= FACED_RAD:
		return walk if _glides_last else _settled(walk)
	if off <= _lead_max and _step_do != Do.NONE and _step_legs == 1:
		return walk + maxf(KeeperFootwork.SETTLE_S, pivot_time(off))
	walk = _on_feet(at, facing, spot)
	_way_do = Do.FACE
	_way_spot = Vector2.ZERO
	_way_side = facing
	return pivot_time(off) + (walk if _glides_last else _settled(walk))


func _to_down(at: Vector2, turn: float, from: int, post_side: float) -> void:
	var d: float = at.distance_to(spot)
	match from:
		Rest.POST:
			_offer(KeeperPost.OUT_TO_BUTTERFLY_S + _down_to_down(at, turn), Do.RVH_FOLD_OUT)
			if _pushes_off(at, turn, post_side, spot):
				_offer(_slides_time(d, FROM.POST) + _rotate_s(_slide_turn(at, turn, spot)), Do.RVH_PUSH_OFF, spot)
		Rest.DOWN:
			_offer(_down_to_down(at, turn), _down_do, _down_spot, _down_side)
		Rest.FEET:
			if d < THERE_M:
				_offer(_drop.drop_s + _rotate_s(turn), Do.DROP)
				if _pivot_s(turn) > 0.0:
					_offer(_pivot_s(turn) + _drop.drop_s, Do.FACE, Vector2.ZERO, facing)
				return
			if _slidable(at, turn, spot):
				_offer(_slides_time(d, FROM.FEET) + _rotate_s(_slide_turn(at, turn, spot)), Do.SLIDE_FROM_FEET, spot)
			# There on his feet turned before or on the way, and down; or there,
			# then turned on his feet (the pivot taking the stop's settle, once
			# his push leg is back) or on his knees once down.
			var faced: float = _standing(at, turn)
			_offer(faced + _drop.drop_s, _way_do, _way_spot, _way_side)
			var walk: float = _on_feet(at, turn, spot)
			var then: float = _settled(walk) + _rotate_s(turn)
			if _pivot_s(turn) > 0.0:
				then = minf(then, walk + _step_hand_off + _pivot_s(turn))
			_offer(then + _drop.drop_s, _step_do, _step_spot)


func _to_post(at: Vector2, turn: float, from: int, post_side: float) -> void:
	match from:
		Rest.POST:
			if post_side == side and at.distance_to(_post.seal_spot(iron, side)) < THERE_M:
				_offer(0.0, Do.NONE)
				return
			_offer(KeeperPost.OUT_TO_BUTTERFLY_S + _down_to_post(at, turn), Do.RVH_FOLD_OUT)
			# Or pushed off this post across to the other and up into it.
			var across: Vector2 = _post_spot(at, turn)
			if _pushes_off(at, turn, post_side, across):
				_offer(_slides_time(at.distance_to(across), FROM.POST) + KeeperPost.IN_FROM_BUTTERFLY_S,
						Do.RVH_PUSH_OFF, across)
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
			# Or down into it straight from his edge on the post, turned to the
			# puck at a sharp angle; or onto that edge first, still turned to it.
			var turned: Vector2 = _post.overlap_spot(iron, side, turn)
			if at.distance_to(turned) <= ON_POST_M:
				_offer(_post.drop_in_s(turn), Do.RVH_DROP_IN, iron, side)
			else:
				var onto: float = _settled(_on_feet(at, turn, turned)) + _post.drop_in_s(turn)
				_offer(onto, _step_do, _step_spot)
			# Or slid across to the post from his feet and up into it.
			var to: Vector2 = _post_spot(at, turn)
			var d: float = at.distance_to(to)
			if d >= THERE_M and _slidable(at, turn, to):
				var slid: float = _slides_time(d, FROM.FEET) + KeeperPost.IN_FROM_BUTTERFLY_S
				_offer(slid, Do.SLIDE_FROM_FEET, to)


# From the butterfly to the goal's spot and facing, down: slid there and
# rotated on his knees to the facing; rotated first onto the slide's line where
# it is off his own and no further off the facing than a slide goes, slid and
# rotated again; or up, there on his feet and down again. Its time; its first
# move in _down_do, _down_spot and _down_side.
func _down_to_down(at: Vector2, turn: float) -> float:
	_down_do = Do.NONE
	_down_spot = spot
	_down_side = 0.0
	var d: float = at.distance_to(spot)
	if d < THERE_M:
		if absf(wrapf(facing - turn, -PI, PI)) <= DOWN_FACED_RAD:
			return 0.0
		_down_do = Do.ROTATE
		_down_side = facing
		return _rotate_s(turn)
	var best: float = INF
	if _slidable(at, turn, spot):
		best = _slides_time(d, FROM.BUTTERFLY) + _rotate_s(_slide_turn(at, turn, spot))
		_down_do = Do.SLIDE
	var heading: Vector2 = (spot - at) / d
	for lead: float in [-1.0, 1.0]:
		var onto: float = KeeperSlide.facing(heading, lead)
		# Never turned further off the shot than a slide takes him.
		if absf(wrapf(onto - facing, -PI, PI)) > KeeperSlide.MAX_OFF_LINE_RAD:
			continue
		var rotated: float = _slide.rotate_time(wrapf(onto - turn, -PI, PI)) + _slides_time(d, FROM.BUTTERFLY) + _rotate_s(onto)
		if rotated < best:
			best = rotated
			_down_do = Do.ROTATE
			_down_side = onto
	var up: float = _drop.rise_s + minf(_standing(at, turn), _settled(_on_feet(at, turn, spot)) + _rotate_s(turn)) \
			+ _drop.drop_s
	if up < best:
		best = up
		var across: float = _local(spot - at, turn).x
		_down_do = Do.RISE if absf(across) < THERE_M else Do.RECOVER
		_down_spot = Vector2.ZERO
		_down_side = signf(across)
	return best


# Down at the goal's spot turned `turn`, the rotation on his knees to its
# facing; none within DOWN_FACED_RAD of it.
func _rotate_s(turn: float) -> float:
	var off: float = wrapf(facing - turn, -PI, PI)
	return _slide.rotate_time(off) if absf(off) > DOWN_FACED_RAD else 0.0


# On his feet at the goal's spot turned `turn`, the pivot to its facing before
# he drops; none within DOWN_FACED_RAD of it.
func _pivot_s(turn: float) -> float:
	var off: float = wrapf(facing - turn, -PI, PI)
	return pivot_time(off) if absf(off) > DOWN_FACED_RAD else 0.0


# His turn at the end of a slide from `at` turned `turn` to `to`: turned as he
# loads until his lead side faces it.
static func _slide_turn(at: Vector2, turn: float, to: Vector2) -> float:
	var heading: Vector2 = (to - at).normalized()
	return KeeperSlide.facing(heading, 1.0 if heading.dot(Vector2(cos(turn), -sin(turn))) >= 0.0 else -1.0)


# On his feet into the RVH on the goal's post: turned square, onto the
# overlap, dropped in. Its time; the footwork's first move in _step_do and
# _step_spot.
func _dropped_in(at: Vector2, turn: float) -> float:
	var walk: float = _settled(_on_feet(at, 0.0, _post.overlap_spot(iron, side)))
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
		best = _slides_time(d, FROM.BUTTERFLY) + KeeperPost.IN_FROM_BUTTERFLY_S
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


# Whether, in the RVH on the post on `post_side` at `at` turned `turn`, he
# pushes off it to `to`: a slide he takes, away from the post.
static func _pushes_off(at: Vector2, turn: float, post_side: float, to: Vector2) -> bool:
	var local: Vector2 = _local(to - at, turn)
	return local.x * post_side < -THERE_M and _slidable(at, turn, to)


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


# The fastest footwork from `at` turned `turn` to `to`, square, each move
# starting as the last one's push leg is back under him: its time to set on
# the spot, its first move in _step_do and _step_spot.
func _on_feet(at: Vector2, turn: float, to: Vector2) -> float:
	_step_spot = to
	_step_legs = 1
	_step_hand_off = 0.0
	_glides_last = false
	var local: Vector2 = _local(to - at, turn)
	var across: float = absf(local.x)
	var deep: float = absf(local.y)
	if local.length() < THERE_M:
		_step_do = Do.NONE
		_step_legs = 0
		return 0.0
	var steepest: float = tan(KeeperFootwork.DIAGONAL_MAX_RAD) * _DIAGONAL_TAN
	if deep <= across * tan(KeeperFootwork.DIAGONAL_MAX_RAD):
		var pushed: float = _push_time(local.length())
		if deep < THERE_M and _shuffle_time(across) <= pushed + TIE_S:
			_step_do = Do.SHUFFLE
			_step_hand_off = _hand_off(across, _footwork.shuffle_speed, false)
			return _shuffle_time(across)
		_step_do = Do.T_PUSH
		_step_hand_off = _hand_off(local.length(), _footwork.t_push_speed, true)
		return pushed
	if across < THERE_M:
		_step_do = Do.C_CUT
		_step_hand_off = _hand_off(deep, _footwork.c_cut_speed, false)
		return _c_cut_time(deep)
	# Steeper than a T-push goes: in depth then across, or the steepest
	# diagonal then the rest in depth.
	var diagonal := Vector2(local.x, signf(local.y) * across * steepest)
	if deep - across * steepest < THERE_M:
		_step_do = Do.T_PUSH
		_step_spot = at + _world(diagonal, turn)
		_step_hand_off = _hand_off(diagonal.length(), _footwork.t_push_speed, true)
		return _push_time(diagonal.length())
	_step_legs = 2
	var depth_first: float = _c_cut_time(deep) + _hand_off(deep, _footwork.c_cut_speed, false) \
			+ _then(across, _push_time(across), 0.0)
	var diagonal_first: float = _push_time(diagonal.length()) \
			+ _hand_off(diagonal.length(), _footwork.t_push_speed, true) \
			+ _then(deep - across * steepest, _c_cut_time(deep - across * steepest), 1.0)
	if depth_first <= diagonal_first:
		_step_do = Do.C_CUT
		_glides_last = _glides_on(across)
		_step_hand_off = _hand_off(across, _footwork.t_push_speed, true)
		return depth_first
	_step_do = Do.T_PUSH
	_step_spot = at + _world(diagonal, turn)
	_glides_last = _glides_on(deep - across * steepest)
	_step_hand_off = _hand_off(deep - across * steepest, _footwork.c_cut_speed, false)
	return diagonal_first


# A way's second leg, `d` long and `deep` of it in depth: skated, within the
# glide's reach of a goal on his feet, else `footwork`'s time.
func _then(d: float, footwork: float, deep: float) -> float:
	return glide_time(d, 0.0, deep) if _glides_on(d) else footwork


# Whether a second leg `d` long is glided: only to a goal on his feet, the
# glide's own.
func _glides_on(d: float) -> bool:
	return rest == Rest.FEET and d <= GLIDE_REACH_M


# How long after a move of `d` at up to `top` m/s sets him on its spot his push
# leg is still coming back under him, which the next move waits for: its
# recovery from the push's end, less what followed it. A T-push (`glides`)
# ends its push before the glide and the stop; strokes go on to the stop.
func _hand_off(d: float, top: float, glides: bool) -> float:
	if glides:
		var pushed: float = KeeperFootwork.push_peak(d, top, _footwork.accel) / _footwork.accel
		return maxf(pushed + KeeperFootwork.RECOVER_S - KeeperFootwork.push_time(d, top, _footwork.accel), 0.0)
	var ratio: float = GameRules.GOALIE_EDGE_STOP_DECEL_RATIO
	var peak: float = sqrt(2.0 * _footwork.accel * d / (1.0 + 1.0 / ratio))
	if peak >= top:
		peak = top
	return maxf(KeeperFootwork.RECOVER_S - peak / (_footwork.accel * ratio), 0.0)


# Skating `d` to a spot and turning `turn` on the way, from rest: the glide's
# stroke, glide and stop, a T-push's, beside the turn at the pivot's rate; its
# speed held to the C-cuts' in depth, of which `deep` is the way's share. His
# legs settle into the stance after it, but nothing waits for them.
func glide_time(d: float, turn: float, deep: float = 0.0) -> float:
	var top: float = _footwork.t_push_speed
	if deep > 1e-6:
		top = minf(top, _footwork.c_cut_speed / deep)
	return maxf(KeeperFootwork.push_time(d, top, _footwork.accel), absf(turn) / _pivot_rate)


# Footwork's time, with the stop settled out of him at its end.
static func _settled(walk: float) -> float:
	return walk + KeeperFootwork.SETTLE_S if walk > 0.0 else 0.0


# Slides one after another to `d` away, each as far as its push carries; the
# first setting out `from` (KeeperSlide.From). A slide that carries as far as it goes
# coasts to rest; the last stops on its spot by the edge.
func _slides_time(d: float, from: int) -> float:
	var reach: float = _slide.glide_reach(_slide.push_speed)
	var t: float = 0.0
	while d > reach:
		t += _slide.time_to(reach, INF, from)
		d -= reach
		from = KeeperSlide.From.BUTTERFLY
	return t + _slide.time_to(d, INF, from)


func _push_time(d: float) -> float:
	return KeeperFootwork.push_time(d, _footwork.t_push_speed, _footwork.accel)


func _shuffle_time(d: float) -> float:
	return GoaliePushRules.time_to_set(d, _footwork.shuffle_speed, _footwork.accel)


func _c_cut_time(d: float) -> float:
	return GoaliePushRules.time_to_set(d, _footwork.c_cut_speed, _footwork.accel)


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

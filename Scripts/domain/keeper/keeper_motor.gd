class_name KeeperMotor
extends RefCounted

# His moves strung together: where he is on the ice, his turn, and which way
# he rests (on his feet, down in the butterfly, sealed on a post), handed from
# each move to the next so his place, turn and pose run on unbroken. Pure,
# stepped at the tick.
#
# Places are in the stances' frame, as the movers': x across, z depth (+ back
# toward his net), `yaw` his turn about the vertical, as a Node3D's rotation.y.

const Rest := KeeperRoute.Rest
const Do := KeeperRoute.Do
enum Mover { NONE, PIVOT, FOOTWORK, DROP, SLIDE, POST, SAVE, GLIDE, KNEES }

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
# Moves asked for and not yet started, as many as the wire carries: a match
# gives him goals and asks none.
const WIRE_ASKS: int = 2

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
var pad_out := KeeperPadOut.new()
# The share of a drop's time a low save cut in now takes to fall: from his feet
# as far as he has sunk into the low ready; between his feet and the ice, a fall
# from rest over the height he has left (its root), no shorter than the low
# ready's, since a leg the save stands up or kicks out still has to get there.
var fall: float = 1.0

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
# A butterfly dropped into from a glide, let go as it lands (`_drop_carrying`).
var _landing: bool = false
# Frozen where he is and turned as he is (`freeze`), no move started.
var _frozen: bool = false
var _frozen_at := Vector2.ZERO
var _frozen_yaw: float = 0.0


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
# or a pivot under way, or between his feet and the ice (a drop, a rise or a
# recovery under way, or gathering back up after a kick); down (`down`), at
# rest there or gathering into the butterfly after a save.
func can_save(down: bool) -> bool:
	var gathering: bool = _mover == Mover.SAVE and save_move.state == KeeperSaveMove.State.GATHERING
	if down:
		return rest == Rest.DOWN and (_mover == Mover.NONE or _mover == Mover.KNEES) \
				or gathering and save_move.rests_down()
	return rest == Rest.FEET and (_mover == Mover.NONE or _mover == Mover.PIVOT or _mover == Mover.FOOTWORK
			or _mover == Mover.GLIDE) or _mover == Mover.DROP or gathering and not save_move.rests_down()


# The low save `low` to `side`, cutting in now.
func save(low: int, side: float) -> void:
	_landing = false
	pose(_cut)
	save_move.fall = fall
	low_ready.cut()
	pad_out.cut()
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


# A puck he holds, for the whistle: he stops where he is, turned as he is, and
# starts nothing more until `thaw`; the move under way only settles his pose.
func freeze() -> void:
	_frozen = true
	_frozen_at = Vector2(x, z)
	_frozen_yaw = yaw
	_queue.clear()
	_goal = false
	glide.velocity = Vector2.ZERO
	save_move.velocity = Vector2.ZERO


func thaw() -> void:
	_frozen = false


func step(dt: float) -> void:
	var was := Vector2(x, z)
	_step_mover(dt)
	if _frozen:
		x = _frozen_at.x
		z = _frozen_at.y
		yaw = _frozen_yaw
	# Sunk while set on his feet, shuffling or skating with the play and asked, out of it
	# with any other move; a drop or a save goes from where he has sunk to
	# (KeeperDrop.drop_from, `save`). Skating with the play is across his line no
	# faster than he shuffles, in depth at any glide: backing in on a rush he
	# glides back in his stance.
	var with_play: bool = _mover == Mover.GLIDE and absf(glide.velocity.rotated(yaw).x) <= glide.shuffle_speed \
			or _mover == Mover.FOOTWORK and footwork.move == KeeperFootwork.Move.SHUFFLE
	low_ready.step(dt, rest == Rest.FEET and (_mover == Mover.NONE or with_play))
	_velocity = (Vector2(x, z) - was) / maxf(dt, 1e-6)
	fall = maxf(sqrt(1.0 - drop.down), KeeperLowReady.fall_share_at(1.0)) if _mover == Mover.DROP else low_ready.fall_share()
	# What a slide from his feet would fall from, for the route to price it.
	if _mover != Mover.SLIDE:
		slide.fall = low_ready.fall_share()


func _step_mover(dt: float) -> void:
	# A move that needs the leg he has out waits for it to come back under him,
	# and one about to start on the leg asked for keeps it in.
	var gathers: bool = _mover == Mover.NONE and pad_out.share > 0.0 and _next_takes_the_leg(pad_out.side)
	pad_out.step(dt, _pad_free() and not gathers
			and not (_mover == Mover.NONE and pad_out.asked != 0.0 and _next_takes_the_leg(pad_out.asked)))
	if gathers:
		slide.step(dt)
		return
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
			if _landing and _goal:
				save_move.hold_to(route.spot - Vector2(x, z), dt)
			save_move.step(dt)
			x = save_move.x
			z = save_move.z
			if _landing and save_move.is_set() and not _rides_on():
				_landing = false
				save_move.state = KeeperSaveMove.State.NONE
				_rest_on(Rest.DOWN)
			elif save_move.is_done():
				_rest_on(Rest.DOWN if save_move.rests_down() else Rest.FEET)
		Mover.GLIDE:
			_step_glide(dt)
		Mover.KNEES:
			# Toward his goal as it is now, nothing committed: he stops the tick
			# the way there is no longer a scoot.
			slide.step(dt)
			if not _goal or _plan() != Do.KNEE_SHUFFLE:
				_mover = Mover.NONE
			else:
				var scoot: Vector2 = (route.spot - Vector2(x, z)).limit_length(KeeperSlide.KNEE_SHUFFLE_M_S * dt)
				x += scoot.x
				z += scoot.y
		Mover.NONE:
			# Down at rest, the last slide's stop still easing out of him.
			if rest == Rest.DOWN:
				slide.step(dt)


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
	if _goal and route.rest == Rest.DOWN and glide.velocity.length() > MOVING_M_S:
		_drop_carrying()
		return
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


# Down from a glide, its speed carried: into the butterfly as a low save drops
# him, held until he lands in it and for as long after as the slide still
# takes him toward his goal down (`_rides_on`).
func _drop_carrying() -> void:
	save(KeeperSaveMove.Low.BUTTERFLY, 1.0)
	save_move.edges = false
	_landing = true


# Whether the leg his pad is asked out on kneels with nothing else to do: at
# rest on his knees, scooting, or the lead leg of a slide or a rotation from
# the butterfly.
func _pad_free() -> bool:
	if rest != Rest.DOWN or _frozen:
		return false
	return _mover == Mover.NONE or _mover == Mover.KNEES \
			or (_mover == Mover.SLIDE and slide.leads_from_his_knees(pad_out.asked))


# Whether the move he would start next from his knees needs the leg on `side`
# (his own): anything but a scoot, or a slide or a rotation that leg leads.
func _next_takes_the_leg(side: float) -> bool:
	if rest != Rest.DOWN:
		return false
	var what: int = Do.NONE
	var to := Vector2.ZERO
	var turn: float = 0.0
	if not _queue.is_empty():
		what = _queue[0].what
		to = _queue[0].spot
		turn = _queue[0].side
	elif _goal:
		what = _plan()
		to = route.first_spot
		turn = route.first_side
	match what:
		Do.NONE, Do.KNEE_SHUFFLE:
			return false
		Do.SLIDE:
			return _turned(to - Vector2(x, z), -yaw).x * side <= 0.0
		Do.ROTATE:
			return -signf(wrapf(turn - yaw, -PI, PI)) != side
	return true


# Whether a push across on his knees is under way: a slide, which cannot be
# cut short, not a scoot.
func slides() -> bool:
	return _mover == Mover.SLIDE


# Whether he is on his way down as he skated (`_drop_carrying`).
func drops() -> bool:
	return _mover == Mover.SAVE and _landing


# Whether the speed he dropped with is still sliding him.
func carries() -> bool:
	return drops() and save_move.velocity != Vector2.ZERO


# Landed from a glide and still sliding on his pads: whether the slide is
# still his way to his goal down, which lies more along it than across it,
# and still carries him faster than his knees would.
func _rides_on() -> bool:
	if save_move.velocity.length() <= KeeperSlide.KNEE_SHUFFLE_M_S or not _goal or route.rest != Rest.DOWN:
		return false
	var to: Vector2 = route.spot - Vector2(x, z)
	var way: Vector2 = save_move.velocity.normalized()
	return to.dot(way) > absf(to.cross(way))


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
				# Out of the stance he is in, the fall from the low ready the
				# shorter (KeeperDrop.drop_from).
				slide.fall = low_ready.fall_share()
				if low_ready.share > 0.0:
					pose(_cut)
					low_ready.cut()
					slide.slide_from_feet(spot, top, _cut)
				else:
					slide.slide_from_feet(spot, top)
			_mover = Mover.SLIDE
		Do.KNEE_SHUFFLE:
			if rest != Rest.DOWN:
				return false
			_mover = Mover.KNEES
		Do.ROTATE:
			if rest != Rest.DOWN:
				return false
			slide.x = x
			slide.z = z
			slide.yaw = yaw
			slide.rotate_to(side)
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
		Do.RVH_PUSH_OFF:
			if rest != Rest.POST:
				return false
			slide.x = x
			slide.z = z
			slide.yaw = yaw
			slide.push_off(spot, post.side, top)
			if slide.phase == KeeperSlide.Phase.DOWN:
				return false
			_mover = Mover.SLIDE
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
	pad_out.lay_over(p)
	if lead != 0.0:
		KeeperPoses.turn_trunk(p, lead)


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


# `v` on the ice in his own frame, turned `turn` into the stances' frame.
static func _turned(v: Vector2, turn: float) -> Vector2:
	return Vector2(v.x * cos(turn) + v.y * sin(turn), -v.x * sin(turn) + v.y * cos(turn))


# His state on the wire (KeeperWire), his movers' with it; the route's movers
# are these, written once.
func wire(w: KeeperWire) -> void:
	x = w.s16(x, KeeperWire.MM)
	z = w.s16(z, KeeperWire.MM)
	yaw = w.s32(yaw, KeeperWire.ANGLE)
	lead = w.s32(lead, KeeperWire.ANGLE)
	rest = w.s8(rest)
	refused = w.s8(refused)
	footwork.wire(w)
	drop.wire(w)
	slide.wire(w)
	post.wire(w)
	route.wire(w)
	save_move.wire(w)
	glide.wire(w)
	low_ready.wire(w)
	pad_out.wire(w)
	fall = w.s16(fall, KeeperWire.FRACTION)
	_wire_queue(w)
	_goal = w.bit(_goal)
	_mover = w.s8(_mover)
	_face = w.s32(_face, KeeperWire.ANGLE)
	_turn_rate = w.s32(_turn_rate, KeeperWire.ANGLE)
	_anchor = w.v2_16(_anchor, KeeperWire.MM)
	_anchor_yaw = w.s32(_anchor_yaw, KeeperWire.ANGLE)
	_velocity = w.v2_32(_velocity, KeeperWire.SPEED)
	_spot_velocity = w.v2_32(_spot_velocity, KeeperWire.SPEED)
	_spot_since = w.s32(_spot_since, KeeperWire.MS)
	_skate = w.bit(_skate)
	_landing = w.bit(_landing)
	_frozen = w.bit(_frozen)
	_frozen_at = w.v2_16(_frozen_at, KeeperWire.MM)
	_frozen_yaw = w.s32(_frozen_yaw, KeeperWire.ANGLE)


# The queue in WIRE_ASKS slots, the unused ones zero; one past them is dropped.
func _wire_queue(w: KeeperWire) -> void:
	var n: int = w.s8(mini(_queue.size(), WIRE_ASKS))
	if _queue.size() != n:
		_queue.resize(n)
	for i: int in WIRE_ASKS:
		var ask: _Ask = _queue[i] if i < n else null
		if ask == null and i < n:
			ask = _Ask.new(Do.NONE, Vector2.ZERO, 0.0, INF)
			_queue[i] = ask
		var what: int = w.s8(ask.what if ask != null else Do.NONE)
		var spot: Vector2 = w.v2_16(ask.spot if ask != null else Vector2.ZERO, KeeperWire.MM)
		var side: float = w.s32(ask.side if ask != null else 0.0, KeeperWire.ANGLE)
		var top: float = w.s16(ask.top if ask != null else INF, KeeperWire.SPEED)
		if ask != null:
			ask.what = what
			ask.spot = spot
			ask.side = side
			ask.top = top

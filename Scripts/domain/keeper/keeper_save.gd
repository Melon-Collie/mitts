class_name KeeperSave
extends RefCounted

# The save (docs/goalie-rebuild-plan.md §3.4): once he has read a shot
# (KeeperShotRead), which save he makes, and the hand's part of it laid over
# whatever pose the motor gives him.
#
# The save is the one goalies are taught for where the shot passes him, made
# for every shot on net: below his belly button the butterfly, the half
# butterfly for a shot wide of a pad (the other leg left loaded under him), the
# extension for one past the flat pad's reach, the hands leading it (the blade
# to a puck along the ice, else the hand on its side); above it the hands, the glove
# or the blocker on its side, and a shot at the chest trapped with the glove
# over it. Each candidate of that kind — a low half (none, the butterfly, the
# half butterfly, the extension) with a hand half (none, the stick's blade
# along the ice, the glove, the blocker) — is posed, its hand put where the
# believed flight crosses that hand's depth, and the flight tested against
# that pose's own gear boxes; he makes the first, in the taught order, whose
# gear meets the flight and holds it, a leading hand taken unless the legs'
# save alone meets it better (GoalieSaveRules, the puck's own contact:
# what comes off it does not go on into the net past the rest of him), else the
# first that meets it, else the first. Timing does not choose it: he makes the
# save he is taught, and one that cannot get there before the puck is beaten,
# as a goalie dropping late is beaten through the five-hole he opens.
#
# A hand moves once his arms have read the shot, at most its tier's speed
# toward where the flight crosses, and back as fast once the save is over. The
# low half is the motor's (KeeperMotor.save); the hand rides any pose.
#
# Space: the read is in the net frame; everything here in his skeleton's
# authored space (left-catching, KeeperPose's, solved unmirrored), the net
# frame brought into it by where the motor has him and whether he catches
# right.

const Low := KeeperSaveMove.Low
enum Hand { NONE, STICK, GLOVE, BLOCKER }

# The flight is tested as this many straight pieces, from the puck to just past
# the goal line.
const PIECES: int = 8
const PAST_LINE_M: float = 0.1
# A hand this near its target, or its rest, is there.
const THERE_M: float = 0.01
# The taught saves, in the order they are tried: below the belly button at the
# body, wide of a pad, and above it at the chest, to the glove side, to the
# blocker side.
const LOW_AT_BODY: Array[int] = [Low.BUTTERFLY, Low.HALF, Low.EXTENSION]
const LOW_WIDE: Array[int] = [Low.HALF, Low.EXTENSION, Low.BUTTERFLY]
const HANDS_GLOVE_SIDE: Array[int] = [Hand.GLOVE, Hand.BLOCKER]
const HANDS_BLOCKER_SIDE: Array[int] = [Hand.BLOCKER, Hand.GLOVE]
# Every piece of his gear in any pose lies within this of the point this high
# over the ice under him: a piece of flight further off meets none of it.
const GEAR_CENTRE := Vector3(0.0, 0.8, 0.0)
const GEAR_REACH_M: float = 2.5
# The reach a covering glove goes out over the ice, which the trunk folds over
# in the glove's time.
const COVER_LEAN_M: float = 0.8
# A hand aims inside this share of the arm's full length, so the arm still
# bends a little at the save.
const REACH_SHARE: float = 0.97
# Points a hand's reach is tried at along each piece of the flight.
const REACH_SAMPLES: int = 6

var glove_speed_m_s: float = GoalieSkillProfile.hard().glove_react_max_speed_mps
var blocker_speed_m_s: float = GoalieSkillProfile.hard().blocker_react_max_speed_mps
# How long a low save takes to land once his legs move: the drop's, the
# shorter fall from the low ready.
var drop_s: float = GoalieSkillProfile.hard().butterfly_drop_s

# The save under way: its low half and the side it goes to (−1 the glove side),
# its hand and where the hand goes; when its gear covers the flight against
# when the puck gets there (seconds from the choice).
var low: int = Low.NONE
var low_side: float = 0.0
var hand: int = Hand.NONE
var hand_target := Vector3.ZERO
var covers: bool = false
var ready_s: float = 0.0
var impact_s: float = INF
# Whether the motor could cut a low save in when it was chosen (mid-slide or on
# the post it cannot): one chosen without is chosen again once it can.
var lows_open: bool = true

# Whether a hand is out (reaching, held, or on its way back), and where.
var _hand_out: bool = false
var _hand_at := Vector3.ZERO
var _returning: bool = false
# A hand still on its way back from the last save when another went out for
# the next, going on back by itself, and where it is.
var _back: int = Hand.NONE
var _back_at := Vector3.ZERO
var _palm := Vector3.FORWARD
# The glove's fingers sent onto a puck he watches: out ahead laid flat on one
# on the ice, up over one held to his chest.
var _fingers := Vector3.FORWARD
# The glove sent to cover a puck he is watching: it goes without a read, and
# how far he has leaned on over the pads after it (KeeperPoses.cover_lean).
var _watched: bool = false
var _lean: float = 0.0
var _lean_to: float = 0.0

var _skel := KeeperSkeleton.new()
var _rest_skel := KeeperSkeleton.new()
var _try := KeeperPose.new()
var _base := KeeperPose.new()
var _out := SweptDiscOBB.Result.new()
var _scratch := SweptDiscOBB.Result.new()
# The believed flight in his space, PIECES + 1 points, and the seconds to each.
var _path := PackedVector3Array()
var _path_t := PackedFloat32Array()
# The goal line in his space: a point on it at the mouth's centre, the way into
# the net, and the way across it.
var _line_at := Vector3.ZERO
var _into_net := Vector3.BACK
var _across := Vector3.RIGHT
# The piece of gear the last flight tested met, and what came off it.
var _hit_part: int = -1
var _hit_v := Vector3.ZERO
var _contact := GoalieSaveRules.ContactResult.new()
var _rebound := SweptDiscOBB.Result.new()
# Seconds until he has read the shot, at the choice; the share of a drop's
# time the fall into it takes; and how well the best candidate yet meets the
# flight (`_take`).
var _wait: float = 0.0
var _fall: float = 1.0
var _best: int = -1


func _init() -> void:
	_path.resize(PIECES + 1)
	_path_t.resize(PIECES + 1)


func active() -> bool:
	return _hand_out


# Chooses the save against the flight `read` believes, from where `motor` has
# him and the pose it gives him now; `mirrored` for a right-catcher. Lows only
# where the motor can cut one in (KeeperMotor.can_save): on his feet or on the
# way between them and the ice any, down the extension, on a post or mid-slide
# none (a shot from the seal is held in it).
func choose(read: KeeperShotRead, motor: KeeperMotor, mirrored: bool) -> void:
	# A hand already out on this shot (chosen again once he can go down) stays
	# the one he saves with.
	var kept: int = hand if _hand_out and not _returning else -1
	_park()
	_choose(read, motor, mirrored, kept)
	_resume()


func _choose(read: KeeperShotRead, motor: KeeperMotor, mirrored: bool, kept: int) -> void:
	_watched = false
	_believe(read, motor, mirrored)
	motor.pose(_base)
	var side: float = _side_of_flight()
	var stance: KeeperSkeleton = _skel_base()
	# Where the flight passes him, through the plane of his skates.
	var by: Vector3 = _crossing(Vector3.ZERO)
	var low_shot: bool = by.y <= stance.xf[KeeperSkeleton.Bone.PELVIS].origin.y + KeeperAnatomy.NAVEL_ABOVE_HIP_M
	var wide: bool = absf(by.x) > KeeperGear.reach_x(stance, KeeperGear.Part.PAD_G if side < 0.0 else KeeperGear.Part.PAD_B,
			side)
	var on_ice: bool = _path_low_at_blade(stance)
	covers = false
	low = Low.NONE
	low_side = side
	hand = Hand.NONE
	lows_open = true
	ready_s = 0.0
	impact_s = INF
	_wait = maxf(read.read_s() - read.age, 0.0)
	_fall = motor.fall
	_best = -1
	var side_hand: int = Hand.GLOVE if side < 0.0 else Hand.BLOCKER
	if not low_shot:
		var hands: Array[int] = HANDS_GLOVE_SIDE
		if absf(by.x) > 0.5 * KeeperAnatomy.CHEST_WIDTH_M and side > 0.0:
			hands = HANDS_BLOCKER_SIDE
		if kept >= 0:
			hands = [kept]
		for h: int in hands:
			if _take(Low.NONE, side, h):
				return
		return
	var lows: Array[int] = [Low.NONE]
	if motor.can_save(false):
		lows = LOW_WIDE if wide else LOW_AT_BODY
	elif motor.can_save(true):
		lows = [Low.EXTENSION, Low.NONE]
	else:
		lows_open = false
	for l: int in lows:
		if _take(l, side, Hand.NONE):
			break
	# The hands lead it: the blade to a puck along the ice, else the hand on its
	# side, with the legs' save, unless it leaves the flight met less well.
	var with_legs: int = low
	var met: int = _best
	_best = met - 1
	var leads: Array[int] = [side_hand]
	if on_ice:
		leads = [Hand.STICK, side_hand]
	if kept >= 0:
		leads = [kept]
	for h: int in leads:
		if _take(with_legs, side, h):
			return
	if _best < met:
		_best = -1
		_take(with_legs, side, Hand.NONE)


# Poses the candidate `l` with `h` and takes it when the flight meets its gear
# better than the best so far (2 met and held, 1 met, 0 neither); true once one
# meets and holds it.
func _take(l: int, side: float, h: int) -> bool:
	var target: Vector3 = _pose_candidate(l, side, h)
	var hit_s: float = _hit_s(_path)
	var kind: int = 0
	if hit_s < INF:
		kind = 2 if _holds() else 1
	if kind <= _best:
		return false
	_best = kind
	covers = hit_s < INF
	low = l
	hand = h
	hand_target = target
	ready_s = _wait + _hand_travel(h, target) / _speed(h) if h != Hand.NONE else 0.0
	if l != Low.NONE:
		ready_s = maxf(ready_s, _wait + drop_s * (_fall if l != Low.KICK else 1.0))
	impact_s = hit_s if covers else _time_at_depth(_hand_point(h).z if h != Hand.NONE else 0.0)
	return _best == 2


# The hand out goes on back by itself (`_back`) while another goes out; one
# that is out again turns from where it is.
func _park() -> void:
	if not _hand_out:
		return
	_back = hand
	_back_at = _hand_at
	_hand_out = false
	_returning = false


func _resume() -> void:
	if _back == Hand.NONE or _back != hand:
		return
	_hand_out = true
	_hand_at = _back_at
	_back = Hand.NONE


# `h` sent out on its own: another hand out goes on back by itself.
func _send(h: int) -> void:
	if _hand_out and hand != h:
		_park()
	hand = h
	_resume()
	_returning = false


# The hand on its way: still until he has read the shot (`read_in`), then
# toward the target at its speed; back toward where the pose under it holds it
# once released. `base` is that pose.
func step(dt: float, read_in: bool, base: KeeperPose) -> void:
	if _back != Hand.NONE:
		var home: Vector3 = _rest_of(_back, base)
		_back_at = _back_at.move_toward(home, _speed(_back) * dt)
		if _back_at.distance_to(home) < THERE_M:
			_back = Hand.NONE
	# The trunk folds after a covering glove as fast as the glove goes out the
	# cover's reach, and comes back up as it returns.
	var leaning: bool = _watched and _hand_out and not _returning
	_lean = move_toward(_lean, _lean_to if leaning else 0.0, dt * glove_speed_m_s / COVER_LEAN_M)
	if hand == Hand.NONE and not _hand_out:
		return
	if not _hand_out:
		if not read_in and not _watched:
			return
		_hand_out = true
		_hand_at = _rest_of(hand, base)
	var to: Vector3 = _rest_of(hand, base) if _returning else hand_target
	_hand_at = _hand_at.move_toward(to, _speed(hand) * dt)
	if _returning and _hand_at.distance_to(to) < THERE_M:
		_hand_out = false
		_returning = false
		_watched = false
		hand = Hand.NONE


# The glove onto `target` (his space), palm down, to cover a puck, leaned
# `lean` of the way on over his pads (KeeperPoses.cover_lean): at once, since
# he is watching it, and on to a new target as the puck moves.
func cover(target: Vector3, lean: float) -> void:
	_lean_to = lean
	_send(Hand.GLOVE)
	hand_target = target
	_palm = Vector3.DOWN
	_fingers = Vector3.FORWARD
	_watched = true


# The glove over a puck held against his chest at `target` (his space), palm
# in on it and fingers up, at once.
func trap(target: Vector3) -> void:
	_lean_to = 0.0
	_send(Hand.GLOVE)
	hand_target = target
	_palm = Vector3.BACK
	_fingers = Vector3.UP
	_watched = true


# Whether the hand is out on its target.
func hand_there() -> bool:
	return _hand_out and not _returning and _hand_at.distance_to(hand_target) < THERE_M


# The save is over: the puck met him, went by, or stopped coming. The hand goes
# back; the low half is the motor's to get up from.
func release() -> void:
	low = Low.NONE
	if _hand_out:
		_returning = true
	else:
		hand = Hand.NONE


# Lays the hand over `p`, the pose the motor gives him, leaned after it to
# cover.
func overlay(p: KeeperPose) -> void:
	if _lean > 0.0:
		KeeperPoses.cover_lean(p, hand_target, _lean)
	if _back != Hand.NONE:
		_lay_hand(p, _back, _back_at)
	if not _hand_out:
		return
	_lay_hand(p, hand, _hand_at)


func _lay_hand(p: KeeperPose, h: int, at: Vector3) -> void:
	match h:
		Hand.GLOVE:
			p.glove_from_chest = false
			p.glove_hand = at
			p.glove_palm = _palm
			if _watched:
				p.glove_fingers = _fingers
		Hand.BLOCKER:
			p.blocker_reach = true
			p.blocker_grip = at
		Hand.STICK:
			p.blade_center = Vector3(at.x, 0.0, p.blade_center.z)


# The flight he believes, in his authored space, from the puck to just past the
# goal line.
func _believe(read: KeeperShotRead, motor: KeeperMotor, mirrored: bool) -> void:
	var to_line: float = read.time_to_line()
	var speed: float = maxf(read.velocity.length(), 1e-3)
	var end: float = (to_line + PAST_LINE_M / speed) if to_line != INF else 1.0
	var into := Basis(Vector3.UP, motor.yaw).inverse()
	var at := Vector3(motor.x, 0.0, motor.z)
	for i: int in PIECES + 1:
		var t: float = end * float(i) / float(PIECES)
		var p: Vector3 = into * (read.position_in(t) - at)
		if mirrored:
			p.x = -p.x
		_path[i] = p
		_path_t[i] = t
	_line_at = into * -at
	_into_net = into * Vector3.BACK
	_across = into * Vector3.RIGHT
	if mirrored:
		_line_at.x = -_line_at.x
		_into_net.x = -_into_net.x
		_across.x = -_across.x
	_palm = -(_path[PIECES] - _path[0]).normalized()


# The way the flight goes past him: −1 his glove side.
func _side_of_flight() -> float:
	return -1.0 if _path[PIECES].x < 0.0 else 1.0


# Poses `_try` for the candidate and solves `_skel` on it; where its hand goes.
func _pose_candidate(l: int, side: float, h: int) -> Vector3:
	match l:
		Low.NONE:
			_try.copy_from(_base)
		Low.BUTTERFLY:
			KeeperPoses.butterfly(_try)
		Low.HALF:
			KeeperPoses.half_butterfly(_try, side)
		Low.KICK:
			KeeperPoses.kick(_try, side)
		Low.EXTENSION:
			KeeperPoses.butterfly_extension(_try, side)
	_try.blocker_reach = false
	_solve()
	if h == Hand.NONE:
		return Vector3.ZERO
	var target: Vector3 = _reach_target(h)
	_lay_hand(_try, h, target)
	if h == Hand.GLOVE:
		_try.glove_palm = _palm
	_solve()
	return target


# Where the hand goes. The blade goes along the ice under the flight where it
# crosses the blade's depth. A hand goes to the point of the flight its arm
# reaches with the most time to spare once it has read the shot and moved
# there — its gear, glove or board, on the puck — or, with none in reach, to
# the point it comes nearest.
func _reach_target(h: int) -> Vector3:
	if h == Hand.STICK:
		return _target_for(h, _crossing(_hand_point(h)))
	var glove: bool = h == Hand.GLOVE
	var chest: Transform3D = _skel.xf[KeeperSkeleton.Bone.CHEST]
	var shoulder: Vector3 = chest * Vector3((-1.0 if glove else 1.0) * KeeperAnatomy.SHOULDER_HALF_SPACING_M,
			KeeperAnatomy.SHOULDER_ABOVE_CHEST_M, 0.0)
	var arm: float = (KeeperAnatomy.UPPER_ARM_M + KeeperAnatomy.FOREARM_M) * REACH_SHARE
	var hand_at: Vector3 = _skel.xf[KeeperSkeleton.Bone.HAND_G].origin if glove else _skel.grip
	# The gear on the hand, and the wrist the arm reaches, from where the hand
	# is held.
	var gear: Vector3 = _hand_point(h) - hand_at
	var wrist: Vector3 = Vector3.ZERO
	if not glove:
		wrist = _skel.xf[KeeperSkeleton.Bone.FOREARM_B] * Vector3(0.0, -KeeperAnatomy.FOREARM_M, 0.0) - hand_at
	var rest: Vector3 = _rest_of(h, _base)
	var best := Vector3.ZERO
	var best_spare: float = -INF
	var nearest := Vector3.ZERO
	var nearest_over: float = INF
	for i: int in PIECES * REACH_SAMPLES + 1:
		var f: float = float(i) / float(REACH_SAMPLES)
		var k: int = mini(floori(f), PIECES - 1)
		var p: Vector3 = _path[k].lerp(_path[k + 1], f - float(k))
		var t: float = lerpf(_path_t[k], _path_t[k + 1], f - float(k))
		# Its gear stays above the ice: along the ice is the blade's.
		if p.y < KeeperGear.half_extents(KeeperGear.Part.GLOVE if glove else KeeperGear.Part.BLOCKER).y:
			continue
		var target: Vector3 = p - gear
		var over: float = (target + wrist).distance_to(shoulder) - arm
		if over <= 0.0:
			var spare: float = t - (_wait + target.distance_to(rest) / _speed(h))
			if spare > best_spare:
				best_spare = spare
				best = target
		elif over < nearest_over:
			nearest_over = over
			nearest = target
	if best_spare > -INF:
		return best
	return nearest if nearest_over < INF else rest


func _solve() -> void:
	_skel.pose(_try)


# Where on the hand the puck should meet it, as posed now.
func _hand_point(h: int) -> Vector3:
	match h:
		Hand.GLOVE:
			return KeeperGear.box(_skel, KeeperGear.Part.GLOVE).origin
		Hand.BLOCKER:
			return KeeperGear.box(_skel, KeeperGear.Part.BLOCKER).origin
	return KeeperGear.box(_skel, KeeperGear.Part.BLADE).origin


# The hand's target that puts `point` of it where the flight crosses: the
# glove's palm, the blocker's board (the grip is what is placed, the board
# hanging off it as posed), the blade on the ice under it.
func _target_for(h: int, crossing: Vector3) -> Vector3:
	match h:
		Hand.BLOCKER:
			return crossing - (KeeperGear.box(_skel, KeeperGear.Part.BLOCKER).origin - _skel.grip)
		Hand.STICK:
			return Vector3(crossing.x, 0.0, crossing.z)
	return crossing


# The skeleton on the pose the motor gives him now.
func _skel_base() -> KeeperSkeleton:
	_skel.pose(_base)
	return _skel


# Whether the flight is low enough for the blade where it crosses the blade's
# depth.
func _path_low_at_blade(skel: KeeperSkeleton) -> bool:
	var blade: Transform3D = KeeperGear.box(skel, KeeperGear.Part.BLADE)
	var top: float = blade.origin.y + KeeperGear.half_extents(KeeperGear.Part.BLADE).y
	return _crossing(blade.origin).y <= top + GameRules.PUCK_COLLISION_RADIUS


# Seconds until the flight crosses depth `z`.
func _time_at_depth(z: float) -> float:
	for i: int in PIECES:
		var a: float = _path[i].z
		var b: float = _path[i + 1].z
		if (a - z) * (b - z) <= 0.0 and a != b:
			return lerpf(_path_t[i], _path_t[i + 1], (z - a) / (b - a))
	return _path_t[PIECES]


# Where the flight crosses the depth of `point`, or its last point short of it.
func _crossing(point: Vector3) -> Vector3:
	for i: int in PIECES:
		var a: Vector3 = _path[i]
		var b: Vector3 = _path[i + 1]
		if (a.z - point.z) * (b.z - point.z) <= 0.0 and a.z != b.z:
			return a.lerp(b, (point.z - a.z) / (b.z - a.z))
	return _path[PIECES]


# Seconds until the flight along `path` first meets the posed gear, or INF when
# it does not before the goal line.
func _hit_s(path: PackedVector3Array) -> float:
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	_hit_part = -1
	for i: int in PIECES:
		if _off_segment(GEAR_CENTRE, path[i], path[i + 1]) > GEAR_REACH_M + r:
			continue
		_hit_part = KeeperGear.nearest(_skel, path[i], path[i + 1], r, _out, _scratch)
		if _hit_part >= 0:
			_hit_v = (path[i + 1] - path[i]) / maxf(_path_t[i + 1] - _path_t[i], 1e-6)
			return lerpf(_path_t[i], _path_t[i + 1], _out.toi)
	return INF


static func _off_segment(c: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var t: float = clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return c.distance_to(a + ab * t)


# Whether the believed flight, met where `_hit_s` last found it, stays out: what
# comes off the gear goes away from the net, is caught or smothered, or meets
# more of him before it reaches the mouth. Straight on to the goal line, as the
# flight is read.
func _holds() -> bool:
	if _hit_part < 0:
		return true
	GoalieSaveRules.resolve_contact(_hit_v, KeeperGear.save_part(_hit_part), _out.normal, _contact, Vector3.FORWARD)
	if _contact.caught or _contact.trapped:
		return true
	var v: Vector3 = _contact.velocity
	var closing: float = v.dot(_into_net)
	if closing <= 1e-4:
		return true
	var from: Vector3 = _out.point
	var t: float = (_line_at - from).dot(_into_net) / closing
	var at_line: Vector3 = from + v * t
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	var on_mouth: Vector3 = at_line - _line_at
	if absf(on_mouth.dot(_across)) >= GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - r \
			or at_line.y >= GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS - r:
		return true
	var away: Vector3 = from + v.normalized() * (r + 0.01)
	return KeeperGear.nearest(_skel, away, at_line, r, _rebound, _scratch) >= 0


# How far the hand goes from where the pose holds it to `target`.
func _hand_travel(h: int, target: Vector3) -> float:
	return _rest_of(h, _base).distance_to(target)


# Where the pose holds the hand `h`: the glove's palm, the blocker's grip, the
# blade's centre.
func _rest_of(h: int, base: KeeperPose) -> Vector3:
	_rest_skel.pose(base)
	match h:
		Hand.GLOVE:
			return _rest_skel.xf[KeeperSkeleton.Bone.HAND_G].origin
		Hand.BLOCKER:
			return _rest_skel.grip
	return Vector3(base.blade_center.x, 0.0, base.blade_center.z)


func _speed(h: int) -> float:
	return glove_speed_m_s if h == Hand.GLOVE else blocker_speed_m_s

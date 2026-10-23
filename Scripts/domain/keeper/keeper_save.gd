class_name KeeperSave
extends RefCounted

# The save (docs/goalie-rebuild-plan.md §3.4): once he has read a shot
# (KeeperShotRead), which save he makes, and the hand's part of it laid over
# whatever pose the motor gives him.
#
# The save is chosen by his own shape. Each candidate — a low half (none, the
# butterfly, the half butterfly, the kick, the extension, each to the side the
# puck is going) with a hand half (none, the stick's blade along the ice, the
# glove, the blocker) — is posed, its hand put where the believed flight
# crosses that hand's depth, and the flight tested against that pose's own gear
# boxes. Of the saves that cover it in time he makes the least committed; with
# none in time, the one that gets there soonest, and he is beaten. Nothing is
# a rule about heights: a shot at a pad face is a save standing because
# standing covers it soonest, the five-hole a butterfly because nothing less
# does, a high shot the hands because no drop covers it.
#
# A hand moves once his arms have read the shot, at most its tier's speed
# toward where the flight crosses, and back as fast once the save is over. The
# low half is the motor's (KeeperMotor.save); the hand rides any pose under it.
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
# How committed each half is, least first: a hand is cheaper than any drop,
# and of the drops the one that leaves him most on his feet is cheapest.
const LOW_RANK: Array[int] = [0, 3, 2, 1, 4]
const HAND_RANK: Array[int] = [0, 1, 2, 3]
# A hand aims inside this share of the arm's full length, so the arm still
# bends a little at the save.
const REACH_SHARE: float = 0.97
# Points a hand's reach is tried at along each piece of the flight.
const REACH_SAMPLES: int = 6

var glove_speed_m_s: float = GoalieSkillProfile.hard().glove_react_max_speed_mps
var blocker_speed_m_s: float = GoalieSkillProfile.hard().blocker_react_max_speed_mps
# How long a low save takes to land once his legs move: the drop's.
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

# Whether a hand is out (reaching, held, or on its way back), and where.
var _hand_out: bool = false
var _hand_at := Vector3.ZERO
var _returning: bool = false
var _palm := Vector3.FORWARD

var _skel := KeeperSkeleton.new()
var _rest_skel := KeeperSkeleton.new()
var _try := KeeperPose.new()
var _base := KeeperPose.new()
var _out := SweptDiscOBB.Result.new()
var _scratch := SweptDiscOBB.Result.new()
# The believed flight in his space, PIECES + 1 points, and the seconds to each.
var _path := PackedVector3Array()
var _path_t := PackedFloat32Array()
# Seconds until his arms have read the shot, at the choice.
var _arm_wait: float = 0.0


func _init() -> void:
	_path.resize(PIECES + 1)
	_path_t.resize(PIECES + 1)


func active() -> bool:
	return _hand_out


# Chooses the save against the flight `read` believes, from where `motor` has
# him and the pose it gives him now; `mirrored` for a right-catcher. Lows only
# where the motor can cut one in (KeeperMotor.can_save): on his feet any, down
# the extension, on a post or mid-drop or slide none (a shot from the seal is
# held in it).
func choose(read: KeeperShotRead, motor: KeeperMotor, mirrored: bool) -> void:
	_believe(read, motor, mirrored)
	motor.pose(_base)
	var side: float = _side_of_flight()
	var lows: Array[int] = [Low.NONE]
	if motor.can_save(false):
		lows.append_array([Low.KICK, Low.HALF, Low.BUTTERFLY, Low.EXTENSION])
	elif motor.can_save(true):
		lows.append(Low.EXTENSION)
	covers = false
	low = Low.NONE
	low_side = side
	hand = Hand.NONE
	ready_s = 0.0
	impact_s = INF
	var best_in_time: bool = false
	var best_rank: int = 0
	var best_late: float = INF
	var miss_m: float = INF
	var leg_wait: float = maxf(read.leg_delay_s - read.age, 0.0)
	var arm_wait: float = maxf(read.arm_delay_s - read.age, 0.0)
	_arm_wait = arm_wait
	var on_ice: bool = _path_low_at_blade(_skel_base())
	for l: int in lows:
		for h: int in [Hand.NONE, Hand.STICK, Hand.GLOVE, Hand.BLOCKER]:
			# The stick's save is the blade along the ice.
			if h == Hand.STICK and not on_ice:
				continue
			var target: Vector3 = _pose_candidate(l, side, h)
			var travel_s: float = arm_wait + _hand_travel(h, target) / _speed(h) if h != Hand.NONE else 0.0
			var hit_s: float = _hit_s()
			if hit_s == INF:
				# Nothing yet: the hand that gets nearest the flight is the one
				# he goes with anyway.
				if not covers and l == Low.NONE and h != Hand.NONE:
					var point: Vector3 = _hand_point(h)
					var miss: float = point.distance_to(_crossing(point))
					if miss < miss_m:
						miss_m = miss
						hand = h
						hand_target = target
						ready_s = travel_s
						impact_s = _time_at_depth(point.z)
				continue
			var ready: float = travel_s
			if l != Low.NONE:
				ready = maxf(ready, leg_wait + drop_s)
			var rank: int = LOW_RANK[l] * HAND_RANK.size() + HAND_RANK[h]
			var late: float = ready - hit_s
			var better: bool
			if not covers:
				better = true
			elif late <= 0.0:
				better = not best_in_time or rank < best_rank
			else:
				better = not best_in_time and late < best_late
			if not better:
				continue
			best_in_time = late <= 0.0
			best_rank = rank
			best_late = late
			covers = true
			low = l
			hand = h
			hand_target = target
			ready_s = ready
			impact_s = hit_s


# The hand on its way: still until his arms have read the shot, then toward the
# target at its speed; back toward where the pose under it holds it once
# released. `base` is that pose.
func step(dt: float, arms_read: bool, base: KeeperPose) -> void:
	if hand == Hand.NONE and not _hand_out:
		return
	if not _hand_out:
		if not arms_read:
			return
		_hand_out = true
		_hand_at = _rest_of(hand, base)
	var to: Vector3 = _rest_of(hand, base) if _returning else hand_target
	_hand_at = _hand_at.move_toward(to, _speed(hand) * dt)
	if _returning and _hand_at.distance_to(to) < THERE_M:
		_hand_out = false
		_returning = false
		hand = Hand.NONE


# The save is over: the puck met him, went by, or stopped coming. The hand goes
# back; the low half is the motor's to get up from.
func release() -> void:
	low = Low.NONE
	if _hand_out:
		_returning = true
	else:
		hand = Hand.NONE


# Lays the hand over `p`, the pose the motor gives him.
func overlay(p: KeeperPose) -> void:
	if not _hand_out:
		return
	_lay_hand(p, hand, _hand_at)


func _lay_hand(p: KeeperPose, h: int, at: Vector3) -> void:
	match h:
		Hand.GLOVE:
			p.glove_from_chest = false
			p.glove_hand = at
			p.glove_palm = _palm
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
			var spare: float = t - (_arm_wait + target.distance_to(rest) / _speed(h))
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


# Seconds until the flight first meets the posed gear, or INF when it does not
# before the goal line.
func _hit_s() -> float:
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	for i: int in PIECES:
		if KeeperGear.nearest(_skel, _path[i], _path[i + 1], r, _out, _scratch) >= 0:
			return lerpf(_path_t[i], _path_t[i + 1], _out.toi)
	return INF


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

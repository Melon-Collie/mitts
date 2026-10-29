class_name KeeperCover
extends RefCounted

# Covering a loose puck he can reach: down over it, the glove laid flat onto
# it, palm down and fingers out ahead. A puck he can cover (`plan`) is one down
# on the ice (`on_ice`: one in the air, a save's pop-up, he waits out until it
# lands) that, slowing on it, will still be where his glove pins it when the
# glove can land there, slow enough by then for the glove to stop it: from his
# feet once his drop has landed, down at once, and no sooner than the glove
# gets there at its tier speed. Where the glove pins it is his own arm's reach
# in the pose he covers from (the butterfly from his feet, the one he is in
# when down), leaned on over his pads as far as it takes and no further
# (`lean`). Pure, in his authored space as KeeperSave's: left-catching, the net
# frame brought into it by where the motor has him and whether he catches
# right.

# A puck this near the middle of the glove, across the ice, is under it; and
# the glove this near resting on it is down on it.
const PIN_M: float = 0.12
const ON_IT_M: float = 0.03
# The fastest a puck can be going for the glove slapped down on it to stop it
# there: a feel value, a puck dribbling or dying at his feet rather than one
# passing through.
const STOPS_M_S: float = 3.0
# A puck further off than this, across the ice, is nowhere near his reach yet:
# looked at again as it comes.
const LOOK_M: float = 3.0
# Rounds of the guess at when the glove lands, each from where the puck will
# have slid to by the last.
const ROUNDS: int = 3
# The leans tried, least first (KeeperPoses.cover_lean's share).
const LEANS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]

var glove_speed_m_s: float = GoalieSkillProfile.hard().glove_react_max_speed_mps

# Where the hand goes, the glove's middle there on top of the puck, in how long
# it lands there, and how far he leans on over his pads to get it there.
var target := Vector3.ZERO
var glove_at := Vector3.ZERO
var land_s: float = 0.0
var lean: float = 0.0

var _skel := KeeperSkeleton.new()
var _pose := KeeperPose.new()
var _upright := KeeperPose.new()


# Whether he can cover the puck at `puck_at` sliding at `puck_v` (net frame),
# from where `motor` has him; `mirrored` for a right-catcher. Sets `target` and
# `land_s`.
func plan(puck_at: Vector3, puck_v: Vector3, motor: KeeperMotor, mirrored: bool) -> bool:
	var into := Basis(Vector3.UP, motor.yaw).inverse()
	var p: Vector3 = into * (puck_at - Vector3(motor.x, 0.0, motor.z))
	var v: Vector3 = into * puck_v
	if mirrored:
		p.x = -p.x
		v.x = -v.x
	if not on_ice(p, v) or Vector2(p.x, p.z).length() > LOOK_M:
		return false
	var legs: float = _legs_s(motor)
	_base(motor)
	var rest: Vector3 = _skel.xf[KeeperSkeleton.Bone.HAND_G].origin
	land_s = legs
	for i: int in ROUNDS:
		target = _on_glove(slid(p, v, land_s))
		land_s = maxf(legs, rest.distance_to(target) / glove_speed_m_s)
	var on: Vector3 = slid(p, v, land_s)
	if Vector2(v.x, v.z).length() - GameRules.PUCK_ICE_DECEL_M_S2 * land_s > STOPS_M_S:
		return false
	_upright.copy_from(_pose)
	for share: float in LEANS:
		_pose.copy_from(_upright)
		KeeperPoses.cover_lean(_pose, on, share)
		_pose.glove_from_chest = false
		_pose.glove_palm = Vector3.DOWN
		_pose.glove_fingers = Vector3.FORWARD
		# The hand put where the glove's pocket, hanging off it as posed, lies
		# on top of the puck.
		_pose.glove_hand = _on_glove(on)
		_skel.pose(_pose)
		var glove: Transform3D = KeeperGear.box(_skel, KeeperGear.Part.GLOVE)
		_pose.glove_hand += _on_top(on, glove) - glove.origin
		_skel.pose(_pose)
		glove = KeeperGear.box(_skel, KeeperGear.Part.GLOVE)
		glove_at = _on_top(on, glove)
		if Vector2(glove.origin.x - glove_at.x, glove.origin.z - glove_at.z).length() <= PIN_M \
				and absf(glove.origin.y - glove_at.y) <= ON_IT_M:
			target = _pose.glove_hand
			lean = share
			return true
	return false


# Whether a puck at `at` going at `v` is down on the ice and staying there:
# neither off it nor rising off it.
static func on_ice(at: Vector3, v: Vector3) -> bool:
	var rising: float = maxf(v.y, 0.0)
	var apex: float = at.y + rising * rising / (2.0 * GameRules.GRAVITY_M_S2)
	return apex <= KeeperShotRead.ON_ICE_Y + KeeperShotRead.AIRBORNE_M


# Where the middle of the glove `glove` lies resting on top of a puck at `at`.
static func _on_top(at: Vector3, glove: Transform3D) -> Vector3:
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.GLOVE)
	var up: float = absf(glove.basis.x.y) * h.x + absf(glove.basis.y.y) * h.y + absf(glove.basis.z.y) * h.z
	return Vector3(at.x, at.y + GameRules.PUCK_COLLISION_HALF_HEIGHT + up, at.z)


# Seconds until his legs have him down to cover from.
static func _legs_s(motor: KeeperMotor) -> float:
	if motor.save_move.state == KeeperSaveMove.State.GOING:
		return motor.save_move.left_s()
	if motor.rest != KeeperRoute.Rest.FEET or motor.save_move.state != KeeperSaveMove.State.NONE:
		return 0.0
	return motor.save_move.drop_s * motor.low_ready.fall_share()


# The pose he covers from, solved: the butterfly from his feet, the one he is
# in otherwise.
func _base(motor: KeeperMotor) -> void:
	if motor.rest == KeeperRoute.Rest.FEET and motor.save_move.state == KeeperSaveMove.State.NONE:
		KeeperPoses.butterfly(_pose)
	else:
		motor.pose(_pose)
	_skel.pose(_pose)


# The glove's place on the ice over a puck at `at`.
static func _on_glove(at: Vector3) -> Vector3:
	return Vector3(at.x, KeeperGear.half_extents(KeeperGear.Part.GLOVE).y, at.z)


# Where a puck at `at` sliding at `v` on the ice is `t` seconds on, its friction
# slowing it to a stop.
static func slid(at: Vector3, v: Vector3, t: float) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	var speed: float = flat.length()
	if speed < 1e-6:
		return at
	var decel: float = GameRules.PUCK_ICE_DECEL_M_S2
	var moving: float = minf(t, speed / decel)
	return at + flat / speed * (speed * moving - 0.5 * decel * moving * moving)

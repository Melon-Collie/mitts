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
# right. Where he plays a held puck out is in the net's frame.

# A puck this near the middle of the glove, across the ice, is under it; and
# the glove this near resting on it is down on it.
const PIN_M: float = 0.12
const ON_IT_M: float = 0.03
# The fastest a puck can be going for the glove slapped down on it to stop it
# there: a feel value, a puck dribbling or dying at his feet rather than one
# passing through.
const STOPS_M_S: float = 3.0
# A puck this near him across the ice is at his feet: inside what his gear
# sweeps as he moves, his blade's toe held out in front of him (~0.8 m) and a
# little more.
const FEET_M: float = 1.0
# A puck further off than this, across the ice, is nowhere near his reach yet:
# looked at again as it comes.
const LOOK_M: float = 3.0
# Rounds of the guess at when the glove lands, each from where the puck will
# have slid to by the last.
const ROUNDS: int = 3
# A puck nearer his hips than this, across the ice, is under him: the glove
# goes onto it fingers ahead.
const FINGERS_OUT_M: float = 0.2
# The gear he goes down onto the ice with: a puck it lands on as he goes down
# to cover is smothered under it (`under_pads`).
const PADS: Array[int] = [KeeperGear.Part.PAD_G, KeeperGear.Part.PAD_B, KeeperGear.Part.RISE_G,
		KeeperGear.Part.RISE_B, KeeperGear.Part.BOOT_G, KeeperGear.Part.BOOT_B, KeeperGear.Part.SKATE_G,
		KeeperGear.Part.SKATE_B, KeeperGear.Part.THIGH_G, KeeperGear.Part.THIGH_B]
# The leans tried, least first (KeeperPoses.cover_lean's share).
const LEANS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
# Playing a held puck out with no whistle for it: how far out he sets it, and
# how hard he sweeps it on, out of his own reach so he does not cover it again.
const SET_DOWN_OUT_M: float = 0.9
const PLAY_OUT_M_S: float = 6.0
# The way he sweeps it, his own frame: out from his glove side, a little ahead.
const SWEEP_WAY := Vector2(1.0, -0.5)
# The least of the sweep's speed that heads away from his goal line; and the
# least the puck is set down clear in front of it, a puck's width and more.
const AWAY_SHARE: float = 0.45
const CLEAR_OF_LINE_M: float = 0.2

var glove_speed_m_s: float = GoalieSkillProfile.hard().glove_react_max_speed_mps

# Where the hand goes, the glove's middle there on top of the puck, in how long
# it lands there, and how far he leans on over his pads to get it there.
var target := Vector3.ZERO
var glove_at := Vector3.ZERO
var land_s: float = 0.0
var lean: float = 0.0
# Where the puck lies when the glove lands, his space, which he leans toward;
# and the way the glove's fingers point, out along the ice toward it.
var toward := Vector3.ZERO
var fingers := Vector3.FORWARD

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
		_pose.glove_fingers = _fingers_toward(on)
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
			toward = on
			fingers = _pose.glove_fingers
			return true
	return false


# Whether a loose puck at `at` sliding at `v` (net frame) lies at his feet as
# `motor` has him: down on the ice, slow enough for the glove to stop, and
# inside what his gear sweeps.
static func at_feet(at: Vector3, v: Vector3, motor: KeeperMotor) -> bool:
	return on_ice(at, v) and Vector2(v.x, v.z).length() <= STOPS_M_S \
			and Vector2(at.x - motor.x, at.z - motor.z).length() <= FEET_M


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


# The pose he covers from, solved: the butterfly from his feet, the stance a
# drop under way lands him in, the one he is in otherwise.
func _base(motor: KeeperMotor) -> void:
	if motor.rest == KeeperRoute.Rest.FEET and motor.save_move.state == KeeperSaveMove.State.NONE:
		KeeperPoses.butterfly(_pose)
	elif motor.save_move.state == KeeperSaveMove.State.GOING:
		motor.save_move.landing(_pose)
	else:
		motor.pose(_pose)
	_skel.pose(_pose)


# Whether a puck at `at` (his skeleton's space) lies under or against his pads
# on the ice as `skel` has him: inside a box grown by the puck's radius, as the
# puck's own contact test meets it (GoalieContactDetector).
static func under_pads(skel: KeeperSkeleton, at: Vector3) -> bool:
	for part: int in PADS:
		var mine: Vector3 = KeeperGear.box(skel, part).affine_inverse() * at
		var h: Vector3 = KeeperGear.half_extents(part) + Vector3.ONE * GameRules.PUCK_COLLISION_RADIUS
		if absf(mine.x) < h.x and absf(mine.y) < h.y and absf(mine.z) < h.z:
			return true
	return false


# The glove's fingers out along the ice toward a puck at `at`, from his hips;
# ahead for one under him.
static func _fingers_toward(at: Vector3) -> Vector3:
	var out := Vector3(at.x, 0.0, at.z)
	return out.normalized() if out.length() > FINGERS_OUT_M else Vector3.FORWARD


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


# The way he sweeps a held puck out, net frame (x across, y back into the net):
# out from his glove side (`glove_side` −1 for his left, a left-catcher's) as
# he is turned (`yaw`, a Node3D's rotation.y), turned forward as far as it
# takes for at least AWAY_SHARE of it to head away from his goal line, so a
# keeper turned to the corner or the boards never sweeps it at his own net.
static func play_out_way(yaw: float, glove_side: float) -> Vector2:
	var local := Vector2(SWEEP_WAY.x * glove_side, SWEEP_WAY.y)
	var way: Vector2 = Vector2(local.x * cos(yaw) + local.y * sin(yaw),
			-local.x * sin(yaw) + local.y * cos(yaw)).normalized()
	if way.y <= -AWAY_SHARE:
		return way
	var across: float = sqrt(1.0 - AWAY_SHARE * AWAY_SHARE)
	return Vector2(across if way.x >= 0.0 else -across, -AWAY_SHARE)


# Where he sets it down, net frame, from where he stands (`me`): SET_DOWN_OUT_M
# along the way he sweeps it, never less than CLEAR_OF_LINE_M in front of his
# goal line, however deep in his crease or below the line he holds it.
static func set_down_at(me: Vector2, way: Vector2) -> Vector2:
	var at: Vector2 = me + way * SET_DOWN_OUT_M
	return Vector2(at.x, minf(at.y, -CLEAR_OF_LINE_M))

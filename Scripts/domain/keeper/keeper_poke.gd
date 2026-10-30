class_name KeeperPoke
extends RefCounted

# The poke check: the stick jabbed out along the ice at a puck an opposing
# carrier drives at him with, to knock it off his blade. He pokes only at a
# carrier driving at him (closing on him on a line that passes within his
# reach; one skating across or stopped he plays with his body), and only when
# his read says it lands: the puck as he reads it (KeeperPlayRead, his read
# late, carried on along the carrier's skating) is where his blade can lie on
# the ice by the time it gets there, thrust at his blocker speed from where the
# pose he is in holds it; it is out in front of its carrier, nearer him than
# the carrier's body by more than the body's own radius (a puck inside the
# body, or held to the side or behind it, has skates between); and it is in
# front of his goal line. Under way, the blade is sent
# on after the puck as he reads it (`track`), so a carrier skating on does not
# outrun it; a pull or a deke after his read beats it. Pure, in his authored
# space as KeeperSave's: left-catching, the net frame brought into it by where
# the motor has him and whether he catches right.

# How far from him, across the ice, past which no aim of his stick lies on it
# (test_keeper_poke.gd holds it), so a puck further off is not tried; and how
# near, inside which the puck is at his feet and the blade already on it.
const REACH_M: float = 2.0
const NEAR_M: float = 0.4
# Driving at him: closing on him at least this fast. A feel number: a carrier
# gliding in to set up is not one he jabs at.
const DRIVING_M_S: float = 2.0
# Rounds of the guess at when the blade gets there, each from where the puck
# will have gone by the last, the blade's centre sent off the puck by what the
# last aim sent it; and the aims, each from the rounds' answer.
const ROUNDS: int = 6
const AIMS: int = 2
# The stick pivots on its heel to the hand and slides through the grip, so the
# blade does not land where its centre is sent: rounds of sending it on by what
# it missed by, until it lies on the puck (within the puck's radius) and on the
# ice (its lowest edge within ON_ICE_M of it). Swung about the heel the blade
# moves further than its centre is sent, so each round sends it AIM_GAIN of
# the miss.
const AIM_ROUNDS: int = 5
const AIM_GAIN: float = 0.7
const ON_PUCK_M: float = GameRules.PUCK_COLLISION_RADIUS
const ON_ICE_M: float = 0.01

# Where the blade's centre is sent (his space, on the ice), and in how long it
# gets there.
var target := Vector3.ZERO
var reach_s: float = 0.0

# His body as the last aim solved it, the blade where it sent it.
var skel := KeeperSkeleton.new()

var _pose := KeeperPose.new()


# Whether a poke at a puck read at `puck`, moving with its carrier at `motion`,
# the carrier's body read at `carrier` (all net frame, x across, y back into
# the net) of radius `body_r`, lands, from where `motor` has him; `mirrored`
# for a right-catcher; the blade thrust at `speed_m_s`. Sets `target` and
# `reach_s`.
func plan(puck: Vector2, motion: Vector2, carrier: Vector2, body_r: float, motor: KeeperMotor, mirrored: bool,
		speed_m_s: float) -> bool:
	var to_me: Vector2 = Vector2(motor.x, motor.z) - carrier
	if motion.dot(to_me.normalized()) < DRIVING_M_S or absf(motion.normalized().cross(to_me)) > REACH_M:
		return false
	motor.pose(_pose)
	return _lands(puck, motion, carrier, body_r, motor, mirrored, speed_m_s,
			Vector3(_pose.blade_center.x, 0.0, _pose.blade_center.z))


# A poke under way, the blade at `blade` (his space): sent on after the puck as
# he now reads it (as `plan`'s), from where the blade is; false once it would
# no longer land.
func track(puck: Vector2, motion: Vector2, carrier: Vector2, body_r: float, motor: KeeperMotor, mirrored: bool,
		speed_m_s: float, blade: Vector3) -> bool:
	motor.pose(_pose)
	return _lands(puck, motion, carrier, body_r, motor, mirrored, speed_m_s, blade)


func _lands(puck: Vector2, motion: Vector2, carrier: Vector2, body_r: float, motor: KeeperMotor, mirrored: bool,
		speed_m_s: float, from: Vector3) -> bool:
	var at: Vector2 = puck
	var want := Vector3.ZERO
	var off := Vector3.ZERO
	reach_s = 0.0
	for _aimed: int in AIMS:
		for _i: int in ROUNDS:
			at = puck + motion * reach_s
			want = in_his_space(at, motor, mirrored)
			reach_s = from.distance_to(want + off) / speed_m_s
		var out: float = Vector2(want.x, want.z).length()
		if out < NEAR_M or out > REACH_M or want.z >= 0.0 or not aim(want):
			return false
		off = target - want
		reach_s = from.distance_to(target) / speed_m_s
	var me := Vector2(motor.x, motor.z)
	return at.y < -GameRules.PUCK_COLLISION_RADIUS \
			and me.distance_to(at) + body_r < me.distance_to(carrier + motion * reach_s)


# Sends the blade's centre so the blade lies on `want` (his space, on the ice)
# in the pose last planned from, the blade turned to `yaw` (KeeperPose's
# blade_yaw) if given; whether it does, flat on the ice. Leaves `target` where
# it sends it.
func aim(want: Vector3, yaw: float = NAN) -> bool:
	if not is_nan(yaw):
		_pose.blade_yaw = yaw
	target = want
	for _i: int in AIM_ROUNDS:
		_pose.blade_center = target
		skel.pose(_pose)
		var got: Transform3D = KeeperGear.box(skel, KeeperGear.Part.BLADE)
		var miss := Vector3(want.x - got.origin.x, 0.0, want.z - got.origin.z)
		if miss.length() <= ON_PUCK_M:
			return lowest(got, KeeperGear.half_extents(KeeperGear.Part.BLADE)) <= ON_ICE_M
		target += miss * AIM_GAIN
	return false


# The motor's pose for `aim` to send the blade from, for a caller with no plan;
# where it holds the blade, and turned how.
func pose_from(motor: KeeperMotor) -> void:
	motor.pose(_pose)


func rest_blade() -> Vector3:
	return Vector3(_pose.blade_center.x, 0.0, _pose.blade_center.z)


func rest_yaw() -> float:
	return _pose.blade_yaw


# The lowest point of a box at `xf` of half extents `h`.
static func lowest(xf: Transform3D, h: Vector3) -> float:
	return xf.origin.y - absf(xf.basis.x.y) * h.x - absf(xf.basis.y.y) * h.y - absf(xf.basis.z.y) * h.z


# A net-frame point on the ice in his space.
static func in_his_space(at: Vector2, motor: KeeperMotor, mirrored: bool) -> Vector3:
	var p: Vector3 = Basis(Vector3.UP, motor.yaw).inverse() * Vector3(at.x - motor.x, 0.0, at.y - motor.z)
	if mirrored:
		p.x = -p.x
	return p

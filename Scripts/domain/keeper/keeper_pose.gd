class_name KeeperPose
extends RefCounted

# Everything that places the keeper's body, as targets rather than joint angles:
# where the pelvis is, how the trunk bends, where each knee, ankle and hand go,
# where the stick's blade sits. KeeperSkeleton solves the joints from it. Keeper
# space throughout (KeeperAnatomy), authored for a left-catching keeper.
#
# A pose is a value: KeeperPoses fills one, the skeleton reads it, and nothing
# else holds a reference to it.

enum FootMode {
	FLAT,        # sole on the ice, toe along `toe`
	ALONG_SHIN,  # foot turned with the shin, `flex` past a right angle (kneeling)
}


class Leg extends RefCounted:
	var ankle: Vector3 = Vector3.ZERO
	# When pinned the knee is placed toward `knee`; otherwise the two-bone solve
	# puts it on the side `knee_pole` names.
	var knee_pinned: bool = false
	var knee: Vector3 = Vector3.ZERO
	var knee_pole: Vector3 = Vector3(0.0, 0.0, -1.0)
	# Which way the front of the thigh and of the shin (the pad's face) point.
	var thigh_front: Vector3 = Vector3(0.0, 0.0, -1.0)
	var shin_front: Vector3 = Vector3(0.0, 0.0, -1.0)
	var foot_mode: int = FootMode.FLAT
	var toe: Vector3 = Vector3(0.0, 0.0, -1.0)
	var flex: float = 0.0
	# A FLAT foot this far (0 to 1) of the way turned to lie along the shin, by
	# `flex`: a foot coming off the ice into the butterfly, or back onto it.
	var along_shin: float = 0.0

	func copy_from(o: Leg) -> void:
		ankle = o.ankle
		knee_pinned = o.knee_pinned
		knee = o.knee
		knee_pole = o.knee_pole
		thigh_front = o.thigh_front
		shin_front = o.shin_front
		foot_mode = o.foot_mode
		toe = o.toe
		flex = o.flex
		along_shin = o.along_shin


var pelvis: Vector3 = Vector3(0.0, KeeperAnatomy.HIP_HEIGHT_M + KeeperAnatomy.SKATE_LIFT_M, 0.0)
# Euler angles, radians, YXZ (yaw outermost): pelvis in keeper space, each
# trunk bone relative to the one below it.
var pelvis_rot: Vector3 = Vector3.ZERO
var lumbar_rot: Vector3 = Vector3.ZERO
var chest_rot: Vector3 = Vector3.ZERO
var neck_rot: Vector3 = Vector3.ZERO
var head_rot: Vector3 = Vector3.ZERO

# Index 0 is the glove-side leg (−X), 1 the blocker side.
var legs: Array[Leg] = [Leg.new(), Leg.new()]

# The catching hand: where the palm's centre goes, which way the fingers point
# and which way the pocket opens. With `glove_from_chest` the position is in
# the chest's frame, so the hand holds its place on the body as the trunk drops
# and leans; the fingers and pocket stay in keeper space, open to the shooter.
var glove_hand: Vector3 = Vector3(-0.35, 1.0, -0.35)
var glove_from_chest: bool = false
var glove_fingers: Vector3 = Vector3(-0.2, 1.0, 0.0)
var glove_palm: Vector3 = Vector3(0.0, 0.0, -1.0)
# Where each elbow tends to point when the arm is solved.
var glove_elbow_pole: Vector3 = Vector3(-0.6, -1.0, 0.3)
var blocker_elbow_pole: Vector3 = Vector3(0.6, -1.0, 0.3)

# The stick: the blade flat on the ice, its centre at `blade_center`, its toe
# turned `blade_yaw` from the glove side (+ turns the toe forward), and the paddle
# tilted `stick_tilt` back toward him about the blade's length. The lie fixes the
# rest, and the blocker hand is where the rigid stick puts the grip, in the
# arm's reach; past it the stick comes to the hand (KeeperSkeleton).
var blade_center: Vector3 = Vector3(0.0, 0.0, -0.45)
var blade_yaw: float = 0.0
var stick_tilt: float = 0.35
# Which way the blocker's board faces.
var blocker_face: Vector3 = Vector3(0.25, 0.0, -1.0)
# With `blocker_reach`, the blocker hand goes to `blocker_grip` (as far as the
# arm reaches toward it) and brings the stick with it, instead of holding the
# stick where the blade puts it: a blocker save.
var blocker_reach: bool = false
var blocker_grip: Vector3 = Vector3.ZERO


# `t` of the way from `a` to `b` (two poses a tick or a snapshot apart). A
# target whose meaning a flag sets (the knee pinned or poled, the foot's mode,
# the glove's frame, the blocker reaching) goes with its flag, from the nearer
# of the two, rather than blending across two meanings. This pose is neither
# `a` nor `b`.
func blend(a: KeeperPose, b: KeeperPose, t: float) -> void:
	var near: KeeperPose = a if t < 0.5 else b
	pelvis = a.pelvis.lerp(b.pelvis, t)
	pelvis_rot = _angles(a.pelvis_rot, b.pelvis_rot, t)
	lumbar_rot = _angles(a.lumbar_rot, b.lumbar_rot, t)
	chest_rot = _angles(a.chest_rot, b.chest_rot, t)
	neck_rot = _angles(a.neck_rot, b.neck_rot, t)
	head_rot = _angles(a.head_rot, b.head_rot, t)
	for i: int in 2:
		var la: Leg = a.legs[i]
		var lb: Leg = b.legs[i]
		var leg: Leg = legs[i]
		leg.ankle = la.ankle.lerp(lb.ankle, t)
		leg.knee_pinned = near.legs[i].knee_pinned
		leg.knee = la.knee.lerp(lb.knee, t) if la.knee_pinned == lb.knee_pinned else near.legs[i].knee
		leg.knee_pole = la.knee_pole.lerp(lb.knee_pole, t)
		leg.thigh_front = la.thigh_front.lerp(lb.thigh_front, t)
		leg.shin_front = la.shin_front.lerp(lb.shin_front, t)
		leg.foot_mode = near.legs[i].foot_mode
		leg.toe = la.toe.lerp(lb.toe, t)
		leg.flex = lerpf(la.flex, lb.flex, t) if la.foot_mode == lb.foot_mode else near.legs[i].flex
		leg.along_shin = lerpf(la.along_shin, lb.along_shin, t)
	glove_from_chest = near.glove_from_chest
	glove_hand = a.glove_hand.lerp(b.glove_hand, t) if a.glove_from_chest == b.glove_from_chest \
			else near.glove_hand
	glove_fingers = a.glove_fingers.lerp(b.glove_fingers, t)
	glove_palm = a.glove_palm.lerp(b.glove_palm, t)
	glove_elbow_pole = a.glove_elbow_pole.lerp(b.glove_elbow_pole, t)
	blocker_elbow_pole = a.blocker_elbow_pole.lerp(b.blocker_elbow_pole, t)
	blade_center = a.blade_center.lerp(b.blade_center, t)
	blade_yaw = lerp_angle(a.blade_yaw, b.blade_yaw, t)
	stick_tilt = lerpf(a.stick_tilt, b.stick_tilt, t)
	blocker_face = a.blocker_face.lerp(b.blocker_face, t)
	blocker_reach = near.blocker_reach
	blocker_grip = a.blocker_grip.lerp(b.blocker_grip, t) if a.blocker_reach == b.blocker_reach \
			else near.blocker_grip


static func _angles(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(lerp_angle(a.x, b.x, t), lerp_angle(a.y, b.y, t), lerp_angle(a.z, b.z, t))


func copy_from(o: KeeperPose) -> void:
	pelvis = o.pelvis
	pelvis_rot = o.pelvis_rot
	lumbar_rot = o.lumbar_rot
	chest_rot = o.chest_rot
	neck_rot = o.neck_rot
	head_rot = o.head_rot
	for i: int in 2:
		legs[i].copy_from(o.legs[i])
	glove_hand = o.glove_hand
	glove_from_chest = o.glove_from_chest
	glove_fingers = o.glove_fingers
	glove_palm = o.glove_palm
	glove_elbow_pole = o.glove_elbow_pole
	blocker_elbow_pole = o.blocker_elbow_pole
	blade_center = o.blade_center
	blade_yaw = o.blade_yaw
	stick_tilt = o.stick_tilt
	blocker_face = o.blocker_face
	blocker_reach = o.blocker_reach
	blocker_grip = o.blocker_grip

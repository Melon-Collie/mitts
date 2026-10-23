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

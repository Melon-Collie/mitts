class_name ArmAnatomyBody
extends RefCounted

# A skater's trunk, arms and stick as ArmAnatomy measures them: plain numbers
# read once off a built body (SkaterAnatomyCapture), never written after.
#
# Frames: the SPINE frame is the trunk's, its origin the pivot the trunk folds
# and twists about (the hips' joint), +X the skater's right, +Y up, -Z ahead.

# The shoulder joints' centres on the trunk at rest, SPINE frame.
var top_shoulder := Vector3.ZERO
var bottom_shoulder := Vector3.ZERO
# Segment lengths (m), the share of their sum an arm is drawn reaching at most
# (Skater.arm_working_extension), and how far the shoulder girdle carries the
# joint toward a hand past that (Skater.shoulder_reach_m).
var upper_len: float = 0.33
var fore_len: float = 0.33
var working_extension: float = 0.97
var girdle_slack: float = 0.06
# The jersey's section (TorsoSection) and where it sits on the trunk.
var torso_in_spine := Transform3D.IDENTITY
var torso_profile: Array[Vector2] = []
var torso_sway: Array[float] = []
var torso_xz_scale := Vector2.ONE
# How far a sleeve's surface stands off its bone, and how much of it may lie
# against the jersey (SkaterArmPoses.STEER_CONTACT_M); the fist's half depth.
var sleeve_radius: float = 0.08
var sleeve_contact: float = 0.03
var hand_radius: float = 0.04
# The stick: the top hand's centre to the blade's heel (m), how close below it
# and how far down the shaft the bottom hand may hold, the angles the shaft
# crosses each palm at (SkaterArmPoses.glove_basis), and the top fist's roll
# round the shaft with the blade's face square (ArmAnatomy.grip_frame).
var stick_length: float = 1.5
var spacing_min: float = 0.1
var spacing_max: float = 1.0
var top_grip_angle: float = deg_to_rad(65.0)
var bottom_grip_angle: float = deg_to_rad(80.0)
var top_roll_square: float = 0.0
# The top hand is the left for a right shot.
var left_shot: bool = false


func arm_reach() -> float:
	return (upper_len + fore_len) * working_extension

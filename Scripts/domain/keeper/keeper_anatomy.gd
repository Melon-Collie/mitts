class_name KeeperAnatomy
extends RefCounted

# The keeper's body and gear, in metres. One build: 6'4" (1.93 m) barefoot.
# Segment lengths and joint heights are standard fractions of stature
# (Drillis & Contini), so the frame is a person's rather than a tuned one;
# gear sizes are the NHL equipment limits where the rule book sets one.
#
# Keeper space: +Y up, −Z toward the shooter, −X the glove side of a
# left-catching keeper (KeeperSkeleton mirrors a right-catcher).

const STATURE_M: float = 1.93

# ── Heights barefoot, as fractions of stature ────────────────────────────────
const _ANKLE_H: float = 0.039
const _KNEE_H: float = 0.285
const _HIP_H: float = 0.530
const _SHOULDER_H: float = 0.818
const _CHIN_H: float = 0.870

const THIGH_M: float = (_HIP_H - _KNEE_H) * STATURE_M
const SHIN_M: float = (_KNEE_H - _ANKLE_H) * STATURE_M
const ANKLE_HEIGHT_M: float = _ANKLE_H * STATURE_M
const HIP_HEIGHT_M: float = _HIP_H * STATURE_M
const UPPER_ARM_M: float = 0.186 * STATURE_M
const FOREARM_M: float = 0.146 * STATURE_M
const FOOT_LENGTH_M: float = 0.152 * STATURE_M
# The heel sits behind the ankle joint by this much of the foot.
const HEEL_BEHIND_ANKLE_M: float = 0.045

# Hip joint centres either side of the pelvis origin, and shoulder joint centres
# either side of the trunk (biacromial breadth 0.259 H, less the deltoid).
const HIP_HALF_SPACING_M: float = 0.09
const SHOULDER_HALF_SPACING_M: float = 0.21

# The trunk chain, each bone's origin above its parent's, upright.
const LUMBAR_ABOVE_PELVIS_M: float = 0.06 * STATURE_M
const CHEST_ABOVE_LUMBAR_M: float = 0.095 * STATURE_M
const SHOULDER_ABOVE_CHEST_M: float = (_SHOULDER_H - _HIP_H) * STATURE_M \
		- LUMBAR_ABOVE_PELVIS_M - CHEST_ABOVE_LUMBAR_M
const NECK_ABOVE_CHEST_M: float = SHOULDER_ABOVE_CHEST_M + 0.01 * STATURE_M
const HEAD_ABOVE_NECK_M: float = (_CHIN_H - _SHOULDER_H - 0.01) * STATURE_M
const SKULL_TOP_ABOVE_HEAD_M: float = (1.0 - _CHIN_H) * STATURE_M

# ── Skates ───────────────────────────────────────────────────────────────────
# A goalie skate's sole sits this far above the ice on its holder and runner —
# lower than a player's, which is the point of the cowling.
const SKATE_LIFT_M: float = 0.065
const ANKLE_ON_SKATES_M: float = ANKLE_HEIGHT_M + SKATE_LIFT_M
const SKATE_HALF_WIDTH_M: float = 0.045

# ── Leg pads (NHL: 11 in wide; the thigh rise above the knee is capped) ──────
const PAD_WIDTH_M: float = 0.2794
const PAD_DEPTH_M: float = 0.20
# The pad's boot runs down over the skate's toe, below the ankle, to just above
# the ice; the knee stack stands just past the knee, and the thigh rise carries
# the pad on past it along the shin. The rise is stiff: it only bends back onto
# the thigh at the break above the knee, by at most PAD_BREAK_MAX_RAD.
const PAD_BELOW_ANKLE_M: float = 0.05
const PAD_ABOVE_KNEE_M: float = 0.05
const PAD_LENGTH_M: float = SHIN_M + PAD_BELOW_ANKLE_M + PAD_ABOVE_KNEE_M
# NHL: the pad may stand above the knee's centre by at most 45% of the knee to
# the top of the pelvis. That reach is 0.27 of stature (20 in on the league's
# 6'2" average), and the pad is built to the limit.
const KNEE_TO_PELVIS_TOP_M: float = 0.27 * STATURE_M
const PAD_TOP_ABOVE_KNEE_M: float = 0.45 * KNEE_TO_PELVIS_TOP_M
# The rise starts just under the knee stack's top, so the two overlap.
const PAD_RISE_ROOT_ABOVE_KNEE_M: float = PAD_ABOVE_KNEE_M - 0.01
const PAD_THIGH_RISE_M: float = PAD_TOP_ABOVE_KNEE_M - PAD_RISE_ROOT_ABOVE_KNEE_M
const PAD_BREAK_MAX_RAD: float = deg_to_rad(30.0)
# The pad's toe, its stiff boot over the skate, is built turned up from the
# pad by the ready stance's angle between shin and skate, as a real pad's is
# for its keeper's stance: in it the toe lies along the skate.
const PAD_TOE_ANGLE_RAD: float = deg_to_rad(25.0)
# The pad's face stands proud of the shin bone by this much: the leg sits in the
# channel at the back.
const PAD_FORWARD_OF_SHIN_M: float = 0.05

# ── Upper body gear ──────────────────────────────────────────────────────────
const CHEST_WIDTH_M: float = 0.56
const CHEST_DEPTH_M: float = 0.28
const PANTS_WIDTH_M: float = 0.48
# The pants' thigh guard over the thigh: the rule caps it at 10 in across the
# front of the leg; front to back it is the thigh plus its padding.
const THIGH_PAD_WIDTH_M: float = 0.254
const THIGH_PAD_DEPTH_M: float = 0.24
const ARM_PAD_WIDTH_M: float = 0.16
# Catching glove: the rule caps the perimeter at 45 in and the cuff at 8 in.
const GLOVE_WIDTH_M: float = 0.25
const GLOVE_HEIGHT_M: float = 0.32
const GLOVE_DEPTH_M: float = 0.13
# Blocker board: 8 in × 15 in.
const BLOCKER_WIDTH_M: float = 0.2032
const BLOCKER_HEIGHT_M: float = 0.381
const BLOCKER_DEPTH_M: float = 0.05
const BLOCKER_FACE_OFF_GRIP_M: float = 0.07
# The board stands upright on the back of the hand, its centre this far above
# the grip: the stick leaves it low, by the bottom corner.
const BLOCKER_ABOVE_GRIP_M: float = 0.12
# The gloved fist round the grip, the back of the hand against the board (in
# the hand's frame: the grip at the origin, −Z the board's face).
const BLOCKER_FIST_HALF := Vector3(0.055, 0.055, 0.05)
const BLOCKER_FIST_CENTER := Vector3(0.0, 0.0,
		BLOCKER_DEPTH_M * 0.5 - BLOCKER_FACE_OFF_GRIP_M + BLOCKER_FIST_HALF.z)
# The wrist, where the forearm goes into the glove: a palm's length (8 cm) up
# and back from the stick in the fist, toward the elbow.
const BLOCKER_WRIST := BLOCKER_FIST_CENTER + Vector3(-0.02, 0.07, 0.03)

# ── Stick (NHL: blade 3.5 in high, 15.5 in long; paddle 3.5 in × 26 in) ─────
const BLADE_LENGTH_M: float = 0.394
const BLADE_HEIGHT_M: float = 0.0889
const BLADE_THICKNESS_M: float = 0.02
# The paddle's top, measured up the stick from the heel as the rule measures
# it; the paddle itself rises from above the blade's heel, not from the ice.
const PADDLE_LENGTH_M: float = 0.66
const PADDLE_ROOT_ABOVE_HEEL_M: float = 0.045
const PADDLE_WIDTH_M: float = 0.0889
const PADDLE_THICKNESS_M: float = 0.025
# A senior goalie stick, heel to the end of the shaft: 59–60 in (goalie sticks
# run 56–63 in). The shaft is what the paddle leaves of it, a long handle above
# the blocker hand that it slides up to poke-check or play the puck.
const STICK_LENGTH_M: float = 60.0 * 0.0254
const SHAFT_LENGTH_M: float = STICK_LENGTH_M - PADDLE_LENGTH_M
const SHAFT_WIDTH_M: float = 0.03
# The blocker hand grips the shaft just above the paddle.
const GRIP_ALONG_STICK_M: float = PADDLE_LENGTH_M + 0.10
# Angle between paddle and blade in the plane of the blade's face — the lie.
const PADDLE_TO_BLADE_DEG: float = 117.0

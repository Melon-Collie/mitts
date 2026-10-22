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
# the ice; the knee stack stands just past the knee. The thigh rise above it is
# strapped to the thigh and follows the thigh, so a butterfly stands it up over
# the knees rather than laying it along the ice.
const PAD_BELOW_ANKLE_M: float = 0.05
const PAD_ABOVE_KNEE_M: float = 0.05
const PAD_LENGTH_M: float = SHIN_M + PAD_BELOW_ANKLE_M + PAD_ABOVE_KNEE_M
const PAD_THIGH_RISE_M: float = 0.22
# The pad's face stands proud of the shin bone by this much: the leg sits in the
# channel at the back.
const PAD_FORWARD_OF_SHIN_M: float = 0.05

# ── Upper body gear ──────────────────────────────────────────────────────────
const CHEST_WIDTH_M: float = 0.56
const CHEST_DEPTH_M: float = 0.28
const PANTS_WIDTH_M: float = 0.48
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

# ── Stick (NHL: blade 3.5 in high, 15.5 in long; paddle 3.5 in × 26 in) ─────
const BLADE_LENGTH_M: float = 0.394
const BLADE_HEIGHT_M: float = 0.0889
const BLADE_THICKNESS_M: float = 0.02
const PADDLE_LENGTH_M: float = 0.66
const PADDLE_WIDTH_M: float = 0.0889
const PADDLE_THICKNESS_M: float = 0.025
const SHAFT_LENGTH_M: float = 0.62
const SHAFT_WIDTH_M: float = 0.03
# The blocker hand grips the shaft just above the paddle.
const GRIP_ALONG_STICK_M: float = PADDLE_LENGTH_M + 0.10
# Angle between paddle and blade in the plane of the blade's face — the lie.
const PADDLE_TO_BLADE_DEG: float = 117.0

class_name KeeperLook
extends RefCounted

# His eyes on the puck: his face turned to follow it wherever it is, laid over
# whatever stance the motor and the save give him, so through a save he
# watches it into the gear that stops it (USA Hockey: "watch the puck into the
# equipment making the save"). The neck takes the turn, the head the nod. A
# puck behind him, a shot gone by him or one around the back of the net, he
# looks back at over his shoulder: past what the neck turns, the trunk turns
# the rest, on the side he is already turned to when it is dead behind him. It
# turns no faster than a head turns and no further than a neck and trunk do;
# past that, his eyes are left to it. Pure, stepped at the tick.
#
# His authored space throughout (KeeperPose's), the puck brought into it by
# the caller.

# A fast head turn's speed, about 570°/s.
const TURN_RAD_S: float = 10.0
# How far the face turns from the chest's straight ahead: the neck's rotation,
# and its flexion down and extension up.
const YAW_MAX_RAD: float = deg_to_rad(75.0)
# How far the trunk turns on the hips for a look back over the shoulder.
const TRUNK_MAX_RAD: float = deg_to_rad(45.0)
# A puck this near dead behind him he keeps looking for over the shoulder he
# is already turned to.
const BEHIND_HOLD_RAD: float = deg_to_rad(20.0)
const PITCH_DOWN_MAX_RAD: float = deg_to_rad(60.0)
const PITCH_UP_MAX_RAD: float = deg_to_rad(40.0)

# How far his face is turned and nodded off where the stance holds it.
var yaw: float = 0.0
var pitch: float = 0.0
# How far his trunk is turned on his hips to look back.
var trunk: float = 0.0


func reset() -> void:
	yaw = 0.0
	pitch = 0.0
	trunk = 0.0


# Turns his face in `p` toward `at` by as much as `dt` allows.
func step(dt: float, p: KeeperPose, at: Vector3) -> void:
	var pelvis := Basis.from_euler(p.pelvis_rot)
	var lumbar: Basis = pelvis * Basis.from_euler(p.lumbar_rot)
	var chest: Basis = lumbar * Basis.from_euler(p.chest_rot)
	var eyes: Vector3 = p.pelvis + pelvis * Vector3(0.0, KeeperAnatomy.LUMBAR_ABOVE_PELVIS_M, 0.0) \
			+ lumbar * Vector3(0.0, KeeperAnatomy.CHEST_ABOVE_LUMBAR_M, 0.0) \
			+ chest * Vector3(0.0, KeeperAnatomy.NECK_ABOVE_CHEST_M + KeeperAnatomy.HEAD_ABOVE_NECK_M, 0.0)
	var d: Vector3 = chest.inverse() * (at - eyes)
	var around: float = atan2(-d.x, -d.z)
	var turned: float = yaw + trunk
	if absf(around) > PI - BEHIND_HOLD_RAD and absf(turned) > 1e-3 and signf(around) != signf(turned):
		around = signf(turned) * (TAU - absf(around))
	around = clampf(around, -YAW_MAX_RAD - TRUNK_MAX_RAD, YAW_MAX_RAD + TRUNK_MAX_RAD)
	var want_trunk: float = signf(around) * maxf(absf(around) - YAW_MAX_RAD, 0.0)
	var want_pitch: float = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PITCH_DOWN_MAX_RAD, PITCH_UP_MAX_RAD)
	# Where the stance holds the face, in the chest's frame.
	var face: Vector3 = Basis.from_euler(p.neck_rot) * Basis.from_euler(p.head_rot) * Vector3.FORWARD
	var to := Vector3(around - want_trunk - atan2(-face.x, -face.z), want_pitch - asin(clampf(face.y, -1.0, 1.0)),
			want_trunk)
	var now := Vector3(yaw, pitch, trunk).move_toward(to, TURN_RAD_S * dt)
	yaw = now.x
	pitch = now.y
	trunk = now.z
	p.chest_rot.y += trunk
	p.neck_rot.y += yaw
	p.head_rot.x += pitch

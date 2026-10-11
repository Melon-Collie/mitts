class_name LegIK
extends RefCounted

# A skater's leg as the rig poses it, solved both ways: from the joints to where
# the ankle lands (place) and from where the ankle should land back to the joints
# (solve). The leg hangs from its hip pivot along −Y, thigh then shin, the knee
# folding about the hip's X; the hip turns by Godot's YXZ euler (yaw outermost,
# then pitch, then roll), the knee fold is negative folding the shin back (+Z).
# The ankle is the shin's end — not the boot's centre, which sits ahead of it, so
# that two folds near straight never reach the same point.
#
# Metres in the hip pivot's parent frame, measured from the pivot; radians.
# Scalars rather than Vector3 throughout: Vector3 is single precision, and near a
# straight knee the fold is the square root of the reach error.


class Leg extends RefCounted:
	var pitch: float = 0.0
	var yaw: float = 0.0
	var roll: float = 0.0
	var knee: float = 0.0
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.0


# The ankle the leg's joints put it at.
static func place(leg: Leg, thigh: float, shin: float) -> void:
	var vy: float = -thigh - shin * cos(leg.knee)
	var vz: float = -shin * sin(leg.knee)
	# Roll, then pitch, then yaw, each about the frame's own axis.
	var x: float = -vy * sin(leg.roll)
	var y: float = vy * cos(leg.roll)
	var cp: float = cos(leg.pitch)
	var sp: float = sin(leg.pitch)
	var y2: float = y * cp - vz * sp
	var z2: float = y * sp + vz * cp
	leg.x = x * cos(leg.yaw) + z2 * sin(leg.yaw)
	leg.y = y2
	leg.z = -x * sin(leg.yaw) + z2 * cos(leg.yaw)


# The joints that put the ankle at (leg.x, leg.y, leg.z) with the leg turned to
# leg.yaw. Out of reach, the leg points at the target as far as it goes: straight
# when too far, folded shut when too near. Roll stays inside ±90°, which is
# every leg the gait poses; the fold is the only one that reaches the point.
static func solve(leg: Leg, thigh: float, shin: float) -> void:
	var cw: float = cos(leg.yaw)
	var sw: float = sin(leg.yaw)
	var qx: float = leg.x * cw - leg.z * sw
	var qy: float = leg.y
	var qz: float = leg.x * sw + leg.z * cw
	var d: float = sqrt(qx * qx + qy * qy + qz * qz)
	var c: float = (d * d - thigh * thigh - shin * shin) / (2.0 * thigh * shin)
	leg.knee = -acos(clampf(c, -1.0, 1.0))
	var vy: float = -thigh - shin * cos(leg.knee)
	var vz: float = -shin * sin(leg.knee)
	if d < 1e-9:
		leg.pitch = 0.0
		leg.roll = 0.0
		return
	# The target's direction at the reach this fold gives.
	var reach: float = sqrt(vy * vy + vz * vz) / d
	qx *= reach
	qy *= reach
	qz *= reach
	leg.roll = asin(clampf(qx / maxf(-vy, 1e-9), -1.0, 1.0)) if vy < 0.0 else 0.0
	leg.pitch = wrapf(atan2(qz, qy) - atan2(vz, vy * cos(leg.roll)), -PI, PI)

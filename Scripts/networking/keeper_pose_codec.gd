class_name KeeperPoseCodec
extends RefCounted

# A KeeperPose on the wire: every target the skeleton solves from, quantized,
# so a client or a replay rebuilds the body the host saved with. Keeper space
# throughout, as the pose is.

# Positions at a millimetre, angles at π/32767, directions per component at a
# hundredth (each ≤ 1.27, under a degree off for a unit vector, magnitude kept),
# the leg and stick scalars at 1e-4.
const POSITION_SCALE: float = 1000.0
const ANGLE_SCALE: float = 32767.0 / PI
const DIRECTION_SCALE: float = 100.0
const SCALAR_SCALE: float = 10000.0

# 8 positions and 5 angle triples at 6 B, 13 directions at 3 B, 6 scalars at
# 2 B, and a byte of flags.
const SIZE: int = 8 * 6 + 5 * 6 + 13 * 3 + 6 * 2 + 1

const _KNEE_PINNED_0: int = 1
const _KNEE_PINNED_1: int = 2
const _GLOVE_FROM_CHEST: int = 4
const _BLOCKER_REACH: int = 8
const _ALONG_SHIN_0: int = 16
const _ALONG_SHIN_1: int = 32


# Writes `p` into `b` at `o`, which has SIZE bytes there.
static func write(p: KeeperPose, b: PackedByteArray, o: int) -> void:
	o = _position(b, o, p.pelvis)
	o = _angles(b, o, p.pelvis_rot)
	o = _angles(b, o, p.lumbar_rot)
	o = _angles(b, o, p.chest_rot)
	o = _angles(b, o, p.neck_rot)
	o = _angles(b, o, p.head_rot)
	var flags: int = 0
	for i: int in 2:
		var leg: KeeperPose.Leg = p.legs[i]
		o = _position(b, o, leg.ankle)
		o = _position(b, o, leg.knee)
		o = _direction(b, o, leg.knee_pole)
		o = _direction(b, o, leg.thigh_front)
		o = _direction(b, o, leg.shin_front)
		o = _direction(b, o, leg.toe)
		o = _scalar(b, o, leg.flex)
		o = _scalar(b, o, leg.along_shin)
		if leg.knee_pinned:
			flags |= _KNEE_PINNED_0 if i == 0 else _KNEE_PINNED_1
		if leg.foot_mode == KeeperPose.FootMode.ALONG_SHIN:
			flags |= _ALONG_SHIN_0 if i == 0 else _ALONG_SHIN_1
	o = _position(b, o, p.glove_hand)
	o = _direction(b, o, p.glove_fingers)
	o = _direction(b, o, p.glove_palm)
	o = _direction(b, o, p.glove_elbow_pole)
	o = _direction(b, o, p.blocker_elbow_pole)
	o = _position(b, o, p.blade_center)
	o = _scalar(b, o, wrapf(p.blade_yaw, -PI, PI))
	o = _scalar(b, o, p.stick_tilt)
	o = _direction(b, o, p.blocker_face)
	o = _position(b, o, p.blocker_grip)
	if p.glove_from_chest:
		flags |= _GLOVE_FROM_CHEST
	if p.blocker_reach:
		flags |= _BLOCKER_REACH
	b.encode_u8(o, flags)


# Fills `p` from the SIZE bytes of `b` at `o`.
static func read(b: PackedByteArray, o: int, p: KeeperPose) -> void:
	p.pelvis = _read_position(b, o)
	o += 6
	p.pelvis_rot = _read_angles(b, o)
	p.lumbar_rot = _read_angles(b, o + 6)
	p.chest_rot = _read_angles(b, o + 12)
	p.neck_rot = _read_angles(b, o + 18)
	p.head_rot = _read_angles(b, o + 24)
	o += 30
	for i: int in 2:
		var leg: KeeperPose.Leg = p.legs[i]
		leg.ankle = _read_position(b, o)
		leg.knee = _read_position(b, o + 6)
		leg.knee_pole = _read_direction(b, o + 12)
		leg.thigh_front = _read_direction(b, o + 15)
		leg.shin_front = _read_direction(b, o + 18)
		leg.toe = _read_direction(b, o + 21)
		leg.flex = _read_scalar(b, o + 24)
		leg.along_shin = _read_scalar(b, o + 26)
		o += 28
	p.glove_hand = _read_position(b, o)
	p.glove_fingers = _read_direction(b, o + 6)
	p.glove_palm = _read_direction(b, o + 9)
	p.glove_elbow_pole = _read_direction(b, o + 12)
	p.blocker_elbow_pole = _read_direction(b, o + 15)
	p.blade_center = _read_position(b, o + 18)
	p.blade_yaw = _read_scalar(b, o + 24)
	p.stick_tilt = _read_scalar(b, o + 26)
	p.blocker_face = _read_direction(b, o + 28)
	p.blocker_grip = _read_position(b, o + 31)
	var flags: int = b.decode_u8(o + 37)
	p.legs[0].knee_pinned = flags & _KNEE_PINNED_0 != 0
	p.legs[1].knee_pinned = flags & _KNEE_PINNED_1 != 0
	p.legs[0].foot_mode = KeeperPose.FootMode.ALONG_SHIN if flags & _ALONG_SHIN_0 != 0 else KeeperPose.FootMode.FLAT
	p.legs[1].foot_mode = KeeperPose.FootMode.ALONG_SHIN if flags & _ALONG_SHIN_1 != 0 else KeeperPose.FootMode.FLAT
	p.glove_from_chest = flags & _GLOVE_FROM_CHEST != 0
	p.blocker_reach = flags & _BLOCKER_REACH != 0


static func _s16(v: float) -> int:
	return clampi(roundi(v), -32768, 32767)


static func _s8(v: float) -> int:
	return clampi(roundi(v), -128, 127)


static func _position(b: PackedByteArray, o: int, v: Vector3) -> int:
	b.encode_s16(o, _s16(v.x * POSITION_SCALE))
	b.encode_s16(o + 2, _s16(v.y * POSITION_SCALE))
	b.encode_s16(o + 4, _s16(v.z * POSITION_SCALE))
	return o + 6


static func _angles(b: PackedByteArray, o: int, v: Vector3) -> int:
	b.encode_s16(o, _s16(wrapf(v.x, -PI, PI) * ANGLE_SCALE))
	b.encode_s16(o + 2, _s16(wrapf(v.y, -PI, PI) * ANGLE_SCALE))
	b.encode_s16(o + 4, _s16(wrapf(v.z, -PI, PI) * ANGLE_SCALE))
	return o + 6


static func _direction(b: PackedByteArray, o: int, v: Vector3) -> int:
	b.encode_s8(o, _s8(v.x * DIRECTION_SCALE))
	b.encode_s8(o + 1, _s8(v.y * DIRECTION_SCALE))
	b.encode_s8(o + 2, _s8(v.z * DIRECTION_SCALE))
	return o + 3


static func _scalar(b: PackedByteArray, o: int, v: float) -> int:
	b.encode_s16(o, _s16(v * SCALAR_SCALE))
	return o + 2


static func _read_position(b: PackedByteArray, o: int) -> Vector3:
	return Vector3(b.decode_s16(o), b.decode_s16(o + 2), b.decode_s16(o + 4)) / POSITION_SCALE


static func _read_angles(b: PackedByteArray, o: int) -> Vector3:
	return Vector3(b.decode_s16(o), b.decode_s16(o + 2), b.decode_s16(o + 4)) / ANGLE_SCALE


static func _read_direction(b: PackedByteArray, o: int) -> Vector3:
	return Vector3(b.decode_s8(o), b.decode_s8(o + 1), b.decode_s8(o + 2)) / DIRECTION_SCALE


static func _read_scalar(b: PackedByteArray, o: int) -> float:
	return b.decode_s16(o) / SCALAR_SCALE

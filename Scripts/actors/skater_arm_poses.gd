class_name SkaterArmPoses
extends RefCounted

# The arm's part poses as pure functions of where its joints are: the skater's
# arm rig and the display figures (LockerMannequin) pose the same bones with
# them. Every pose is basis·scale at a position — scaled_local throughout, since
# the plain scaled() is S·basis and puts the size on the wrong axes once a part
# tilts.


# An arm segment's bone from joint `a` to joint `b`: the prism's long axis (its
# Z) along the span at the span's length, X/Y the segment's `thickness`. The
# up vector only has to avoid colinearity: the prism is rotationally symmetric
# about its long axis.
static func segment_pose(a: Vector3, b: Vector3, thickness: Vector3) -> Transform3D:
	var span: Vector3 = b - a
	var length: float = span.length()
	var dir: Vector3 = span / length
	var bone_scale: Vector3 = thickness
	bone_scale.z = length
	return Transform3D(Basis.looking_at(dir, up_for_look_at(dir)).scaled_local(bone_scale),
			(a + b) * 0.5)


# How far the elbow turns off the pole's bend, about the shoulder→hand line
# (radians, signed): of the circle the two bone lengths allow, the turn toward
# `outward` that keeps the arm out of the torso, as little as that takes — none
# where the pole's elbow already clears, the whole turn to `outward` where even
# that intrudes. The turn is the root of the arm's depth into the torso,
# bracketed by bisection and placed in its last bracket by the depth's line, so
# it is a continuous function of the pose. `torso` is the TORSO bone's pose, in
# the space the joints are in. turned_elbow places the elbow it names.
#
# What it measures is the elbow's pad and the middle of each segment (past the
# armhole, which is skinned into the torso), each allowed STEER_CONTACT_M of
# overlap: a sleeve lying against the ribs is an arm at rest, not a clip. The
# forearm's last stretch to the hand is not measured — the hand is where it is,
# and no elbow moves it.
const STEER_CONTACT_M: float = 0.03
const _STEER_BISECTIONS: int = 6

static func steer_turn(shoulder: Vector3, hand: Vector3, upper_len: float,
		forearm_len: float, pole: Vector3, outward: Vector3, torso: Transform3D) -> float:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	if d < 0.0001:
		return 0.0
	var axis: Vector3 = d_vec / d
	var h: float = _elbow_offset(d, upper_len, forearm_len)
	var foot: Vector3 = shoulder + axis * _elbow_foot(d, upper_len, forearm_len)
	var bend: Vector3 = TwoBoneIK.bend_direction(shoulder, hand, pole)
	var to_torso: Transform3D = torso.affine_inverse()
	var unit: float = torso.basis.get_scale().x
	var depth_lo: float = _arm_depth(shoulder, foot + bend * h, hand, to_torso, unit)
	if depth_lo <= 0.0:
		return 0.0
	var out: Vector3 = outward - axis * outward.dot(axis)
	if out.length_squared() < 0.000001 or h < 0.0001:
		return 0.0
	var full: float = bend.signed_angle_to(out.normalized(), axis)
	var depth_hi: float = _arm_depth(shoulder, foot + bend.rotated(axis, full) * h, hand,
			to_torso, unit)
	if depth_hi > 0.0:
		return full
	var lo: float = 0.0
	var hi: float = 1.0
	for _i: int in _STEER_BISECTIONS:
		var mid: float = (lo + hi) * 0.5
		var depth: float = _arm_depth(shoulder, foot + bend.rotated(axis, full * mid) * h,
				hand, to_torso, unit)
		if depth > 0.0:
			lo = mid
			depth_lo = depth
		else:
			hi = mid
			depth_hi = depth
	return full * lerpf(lo, hi, depth_lo / (depth_lo - depth_hi))


# The elbow `turn` radians off the pole's bend about the shoulder→hand line
# (TwoBoneIK.solve_elbow's at 0).
static func turned_elbow(shoulder: Vector3, hand: Vector3, upper_len: float,
		forearm_len: float, pole: Vector3, turn: float) -> Vector3:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	if d < 0.0001:
		return shoulder
	var axis: Vector3 = d_vec / d
	return shoulder + axis * _elbow_foot(d, upper_len, forearm_len) \
			+ TwoBoneIK.bend_direction(shoulder, hand, pole).rotated(axis, turn) \
			* _elbow_offset(d, upper_len, forearm_len)


# Where along the shoulder→hand line the elbow's circle is centred, and its
# radius, as TwoBoneIK.solve_elbow places them.
static func _elbow_foot(d: float, upper_len: float, forearm_len: float) -> float:
	var span: float = clampf(d, absf(upper_len - forearm_len), upper_len + forearm_len)
	return (upper_len * upper_len - forearm_len * forearm_len + span * span) / (2.0 * span)


static func _elbow_offset(d: float, upper_len: float, forearm_len: float) -> float:
	var foot: float = _elbow_foot(d, upper_len, forearm_len)
	return sqrt(maxf(upper_len * upper_len - foot * foot, 0.0))


# How far the arm with its elbow at `elbow` sinks into the torso past contact
# (m) at the deepest of the points steer_turn measures; negative, by the
# narrowest margin, when it clears.
static func _arm_depth(shoulder: Vector3, elbow: Vector3, hand: Vector3,
		to_torso: Transform3D, unit: float) -> float:
	return maxf(_depth(elbow, to_torso, unit), maxf(_depth((shoulder + elbow) * 0.5,
			to_torso, unit), _depth(elbow.lerp(hand, 0.4), to_torso, unit)))


static func _depth(p: Vector3, to_torso: Transform3D, unit: float) -> float:
	return SkaterMeshBuilder.SLEEVE_RADIUS_M - STEER_CONTACT_M \
			- SkaterMeshBuilder.torso_clearance(to_torso * p) * unit


# The ELBOW bone: its Y out of the bend, the way the IK pushed the elbow, its X
# along the arm, so its Z is the elbow's hinge.
static func elbow_pose(shoulder: Vector3, elbow: Vector3, hand: Vector3, pole: Vector3,
		thickness: Vector3) -> Transform3D:
	var out: Vector3 = TwoBoneIK.bend_direction(shoulder, hand, pole)
	var along: Vector3 = (hand - shoulder).normalized()
	var basis := Basis(along, out, along.cross(out)) if out != Vector3.ZERO else Basis.IDENTITY
	return Transform3D(basis.scaled_local(thickness), elbow)


# The fist at `hand` on a forearm from `elbow`: glove_basis, scaled.
static func glove_pose(elbow: Vector3, hand: Vector3, shaft: Vector3, grip_angle: float,
		ulnar_max: float, radial_max: float, thickness: Vector3) -> Transform3D:
	return Transform3D(glove_basis((hand - elbow).normalized(), shaft, grip_angle, ulnar_max,
			radial_max).scaled_local(thickness), hand)


# The fist on a forearm pointing `forearm_dir`, holding a shaft running
# `shaft` toward the blade (ZERO off the stick). Its long (local Y) axis runs
# wrist → fingers and its knuckle roll across local X, +X the thumb's side.
# Off the stick it lines up with the forearm, rolled from world up like the
# cuff. On it the hand holds the stick like a sword: the shaft crosses the palm
# at `grip_angle` to the hand's long axis and leaves past the thumb toward the
# blade, and the wrist deviates in the plane of the forearm and the shaft to
# keep it there — toward the thumb up to `radial_max` as the shaft opens past
# the grip, toward the little finger up to `ulnar_max` as it closes. Past either
# the wrist stops and the shaft slips off the grip by the rest.
static func glove_basis(forearm_dir: Vector3, shaft: Vector3, grip_angle: float,
		ulnar_max: float, radial_max: float) -> Basis:
	var straight := Basis.looking_at(forearm_dir, up_for_look_at(forearm_dir)) \
			* Basis(Vector3.RIGHT, PI * 0.5)
	if shaft == Vector3.ZERO:
		return straight
	var across: Vector3 = forearm_dir - shaft * forearm_dir.dot(shaft)
	if across.length_squared() < 0.000001:
		return straight
	across = across.normalized()
	var opening: float = forearm_dir.angle_to(shaft)
	var held: float = opening - clampf(opening - grip_angle, -ulnar_max, radial_max)
	var hand_axis: Vector3 = shaft * cos(held) + across * sin(held)
	var thumb: Vector3 = (shaft - hand_axis * shaft.dot(hand_axis)).normalized()
	return Basis(thumb, -hand_axis, thumb.cross(-hand_axis))


# Glove cuff ring from `hand` back toward `elbow`, its near end `wrist_offset`
# up the forearm from the fist and extending back by its mesh height. The ring's
# long axis is local Y: looking_at puts -Z on the bone, and the post-multiplied
# X(+90°) twist maps local Y onto it. The cuff's radius is non-uniform on a unit
# mesh, so the scale composed the other way lands it on the wrong mesh axes and
# renders metre-wide fins at the wrist.
static func cuff_pose(elbow: Vector3, hand: Vector3, thickness: Vector3,
		wrist_offset: float) -> Transform3D:
	var bone_dir: Vector3 = hand - elbow
	var dir: Vector3 = bone_dir / bone_dir.length()
	var center: Vector3 = hand - dir * (SkaterMeshBuilder.CUFF_HEIGHT_M * 0.5 + wrist_offset)
	var basis := Basis.looking_at(dir, up_for_look_at(dir)) * Basis(Vector3.RIGHT, PI * 0.5)
	return Transform3D(basis.scaled_local(thickness), center)


# An up vector safely non-colinear with `direction`. Falls back to
# Vector3.FORWARD when `direction` is near-vertical so look_at() doesn't warn
# about colinear basis vectors. Cylindrical meshes (arm bones, cuffs, the stick
# knob) are rotationally symmetric around their long axis, so the choice of up
# only matters for the warning — not for the rendered geometry.
static func up_for_look_at(direction: Vector3) -> Vector3:
	if absf(direction.normalized().y) > 0.99:
		return Vector3.FORWARD
	return Vector3.UP

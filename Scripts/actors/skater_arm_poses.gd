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


# The ELBOW bone: its Y out of the bend, the way the IK pushed the elbow, its X
# along the arm, so its Z is the elbow's hinge.
static func elbow_pose(shoulder: Vector3, elbow: Vector3, hand: Vector3, pole: Vector3,
		thickness: Vector3) -> Transform3D:
	var out: Vector3 = TwoBoneIK.bend_direction(shoulder, hand, pole)
	var along: Vector3 = (hand - shoulder).normalized()
	var basis := Basis(along, out, along.cross(out)) if out != Vector3.ZERO else Basis.IDENTITY
	return Transform3D(basis.scaled_local(thickness), elbow)


# The fist at `hand` on a forearm from `elbow`: glove_basis, scaled.
static func glove_pose(elbow: Vector3, hand: Vector3, grip: Vector3, max_bend: float,
		thickness: Vector3) -> Transform3D:
	return Transform3D(glove_basis((hand - elbow).normalized(), grip, max_bend)
			.scaled_local(thickness), hand)


# The fist on a forearm pointing `forearm_dir`. Its long (local Y) axis runs
# wrist → fingers and its knuckle roll across local X. Off the stick (`grip`
# ZERO) it lines up with the forearm, rolled from world up like the cuff. On it,
# the knuckle roll lies along the shaft, its +X (the thumb's end) toward the
# blade — `grip` points butt→tip — and the hand turns toward square across it, bending at the wrist by up to `max_bend` radians: the wrist breaks as the
# stick swings against the forearm. `grip`'s length is how firmly the hand holds
# (SkaterStickRig.grip_axis): the fist turns from the one to the other with it.
static func glove_basis(forearm_dir: Vector3, grip: Vector3, max_bend: float) -> Basis:
	var straight := Basis.looking_at(forearm_dir, up_for_look_at(forearm_dir)) \
			* Basis(Vector3.RIGHT, PI * 0.5)
	var hold: float = minf(grip.length(), 1.0)
	if hold < 0.0001:
		return straight
	var shaft: Vector3 = grip / grip.length()
	var across: float = forearm_dir.dot(shaft)
	var square: Vector3 = forearm_dir - shaft * across
	if square.length_squared() < 0.0001:
		return straight
	square = square.normalized()
	var hand_axis: Vector3 = forearm_dir
	var hinge: Vector3 = forearm_dir.cross(square)
	if hinge.length_squared() > 1e-8:
		hand_axis = forearm_dir.rotated(hinge.normalized(),
				minf(asin(clampf(absf(across), 0.0, 1.0)), max_bend))
	var knuckles: Vector3 = shaft - hand_axis * shaft.dot(hand_axis)
	if knuckles.length_squared() < 0.0001:
		return straight
	knuckles = knuckles.normalized()
	var held := Basis(knuckles, -hand_axis, knuckles.cross(-hand_axis))
	if hold >= 1.0:
		return held
	return Basis(straight.get_rotation_quaternion().slerp(held.get_rotation_quaternion(), hold))


# Where the wrist of a fist at `grip` sits: `hand_len` back from it along the
# hand, which lies along the forearm the whole arm would reach the fist along
# (`forearm_len` + `hand_len`, toward `pole`), turned toward square across the
# shaft by up to `max_bend` (glove_basis; `shaft` ZERO off the stick). The
# drawn forearm is the rest of the arm, solved to the wrist, so the bend shows
# at the wrist rather than as a fist turned about its own middle. That forearm
# lies a few degrees off the line the bend was taken from, so the hand is bent
# once more off the forearm it gets.
static func place_wrist(shoulder: Vector3, grip: Vector3, shaft: Vector3, upper_len: float,
		forearm_len: float, hand_len: float, pole: Vector3, max_bend: float) -> Vector3:
	var reach_elbow: Vector3 = TwoBoneIK.solve_elbow(shoulder, grip, upper_len,
			forearm_len + hand_len, pole)
	var line: Vector3 = grip - reach_elbow
	if line.length_squared() < 1e-8:
		return grip
	var wrist: Vector3 = grip + glove_basis(line.normalized(), shaft, max_bend).y.normalized() \
			* hand_len
	var fore: Vector3 = wrist - TwoBoneIK.solve_elbow(shoulder, wrist, upper_len, forearm_len,
			pole)
	if fore.length_squared() < 1e-8:
		return wrist
	return grip + glove_basis(fore.normalized(), shaft, max_bend).y.normalized() * hand_len


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

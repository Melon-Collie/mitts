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


# The elbow's swivel: of the circle round the shoulder→hand line the two bone
# lengths allow, the bend (unit, square to that line, the way the elbow points)
# whose arm costs least (swivel_cost). Sampled all round the circle from the
# rest pole's bend, then the least sample's bracket narrowed by golden section
# — the minimum usually sits on the jersey's contact, a kink no parabola through
# the coarse samples places — and the last three points' parabola placed in
# what is left, so the bend follows its minimum continuously as the pose moves
# rather than in steps of the search's last interval.
#
# A rest bend that breaks no limit is taken without the search
# (SWIVEL_FREE_OFF_AXIS).
#
# `held` is the bend chosen last frame (ZERO with no history). It weighs only in
# choosing which sample's bracket to search, so the elbow stays in the minimum
# it is in when two tie rather than flipping between them; the search inside the
# bracket leaves it out, and the samples are laid from the rest pole rather than
# from `held`, so a still pose gives the same bend frame after frame and the
# rebuild gate rests.
#
# `outward` and `back` are the spine's directions (outward on this arm's side)
# in the joints' space; `shaft` the stick's direction at this hand toward the
# blade, ZERO off the stick; `wrist` the grip angle and the wrist's ulnar and
# radial range; `torso` the TORSO bone's pose. elbow_on_circle places the elbow.
const SWIVEL_SAMPLES: int = 12
const SWIVEL_GOLDEN_STEPS: int = 8
const _GOLDEN: float = 0.6180339887
# Where the rest pole's own bend breaks no limit it is the answer outright —
# every other term is zero there and the rest's is least — as long as the pole
# points this far off the arm (sin), so that the bend it names is well defined.
const SWIVEL_FREE_OFF_AXIS: float = 0.1
const SWIVEL_FREE_DOT: float = sqrt(1.0 - SWIVEL_FREE_OFF_AXIS * SWIVEL_FREE_OFF_AXIS)

static func swivel_bend(shoulder: Vector3, hand: Vector3, upper_len: float,
		forearm_len: float, rest: Vector3, held: Vector3, outward: Vector3,
		back: Vector3, torso: Transform3D, shaft: Vector3, wrist: Vector3) -> Vector3:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	if d < 0.0001:
		return Vector3.ZERO
	var axis: Vector3 = d_vec / d
	var h: float = _elbow_offset(d, upper_len, forearm_len)
	var foot: Vector3 = shoulder + axis * _elbow_foot(d, upper_len, forearm_len)
	var hold: Vector3 = held - axis * held.dot(axis)
	hold = hold.normalized() if hold.length_squared() > 0.000001 else Vector3.ZERO
	var ref: Vector3 = TwoBoneIK.bend_direction(shoulder, hand, rest)
	var to_torso: Transform3D = torso.affine_inverse()
	var unit: float = torso.basis.get_scale().x
	var rest_n: Vector3 = rest.normalized()
	var rest_cost: float = SWIVEL_REST * (1.0 - ref.dot(rest_n))
	if swivel_cost(shoulder, foot + ref * h, hand, ref, upper_len, rest_n, Vector3.ZERO,
			outward, back, to_torso, unit, shaft, wrist) <= rest_cost \
			and absf(rest_n.dot(axis)) <= SWIVEL_FREE_DOT:
		return ref
	var step: float = TAU / SWIVEL_SAMPLES
	var best: int = 0
	var best_cost: float = INF
	for k: int in SWIVEL_SAMPLES:
		var bend: Vector3 = ref.rotated(axis, step * k)
		var cost: float = swivel_cost(shoulder, foot + bend * h, hand, bend, upper_len, rest_n,
				hold, outward, back, to_torso, unit, shaft, wrist)
		if cost < best_cost:
			best_cost = cost
			best = k
	var a: float = step * (best - 1)
	var b: float = step * (best + 1)
	var c: float = b - _GOLDEN * (b - a)
	var e: float = a + _GOLDEN * (b - a)
	var bend_c: Vector3 = ref.rotated(axis, c)
	var bend_e: Vector3 = ref.rotated(axis, e)
	var cost_c: float = swivel_cost(shoulder, foot + bend_c * h, hand, bend_c, upper_len, rest_n,
			Vector3.ZERO, outward, back, to_torso, unit, shaft, wrist)
	var cost_e: float = swivel_cost(shoulder, foot + bend_e * h, hand, bend_e, upper_len, rest_n,
			Vector3.ZERO, outward, back, to_torso, unit, shaft, wrist)
	for _i: int in SWIVEL_GOLDEN_STEPS:
		if cost_c < cost_e:
			b = e
			e = c
			cost_e = cost_c
			c = b - _GOLDEN * (b - a)
			bend_c = ref.rotated(axis, c)
			cost_c = swivel_cost(shoulder, foot + bend_c * h, hand, bend_c, upper_len, rest_n,
					Vector3.ZERO, outward, back, to_torso, unit, shaft, wrist)
		else:
			a = c
			c = e
			cost_c = cost_e
			e = a + _GOLDEN * (b - a)
			bend_e = ref.rotated(axis, e)
			cost_e = swivel_cost(shoulder, foot + bend_e * h, hand, bend_e, upper_len, rest_n,
					Vector3.ZERO, outward, back, to_torso, unit, shaft, wrist)
	var m: float = (a + b) * 0.5
	var bend_m: Vector3 = ref.rotated(axis, m)
	var cost_m: float = swivel_cost(shoulder, foot + bend_m * h, hand, bend_m, upper_len, rest_n,
			Vector3.ZERO, outward, back, to_torso, unit, shaft, wrist)
	return ref.rotated(axis, _parabola_floor(c, cost_c, m, cost_m, e, cost_e))


# Where the parabola through three points (x ascending) bottoms out, kept
# between the outer two; the middle one where the three are not a bowl.
static func _parabola_floor(x0: float, y0: float, x1: float, y1: float, x2: float,
		y2: float) -> float:
	var d0: float = (y1 - y0) / (x1 - x0)
	var d1: float = (y2 - y1) / (x2 - x1)
	var curve: float = (d1 - d0) / (x2 - x0)
	if curve <= 0.0:
		return x1
	return clampf((x0 + x1) * 0.5 - d0 / (2.0 * curve), x0, x2)


# The elbow whose bend off the shoulder→hand line is `bend` (swivel_bend's).
static func elbow_on_circle(shoulder: Vector3, hand: Vector3, upper_len: float,
		forearm_len: float, bend: Vector3) -> Vector3:
	var d_vec: Vector3 = hand - shoulder
	var d: float = d_vec.length()
	if d < 0.0001:
		return shoulder
	return shoulder + d_vec / d * _elbow_foot(d, upper_len, forearm_len) \
			+ bend * _elbow_offset(d, upper_len, forearm_len)


# What an elbow at `elbow` costs the arm, each term in the units of a radian of
# the joint it names:
#   the jersey   how far the sleeve sinks past contact, SWIVEL_TORSO per metre —
#                first, so an elbow that can clear the body does;
#   the rest     how far the bend points off the rest pole (1 − cos), the
#                shoulder's least effort — the elbow hangs down and out. Over
#                the circle it varies only by the pole's share square to the
#                arm, so it fades rather than flips as the arm comes round to
#                the pole;
#   the shoulder how far the upper arm reaches behind the chest past
#                SWIVEL_EXTENSION_MAX (its extension), and any reach behind it
#                toward the spine, which a shoulder cannot make with the hand in
#                front;
#   the wrist    how far the shaft sits past the wrist's deviation (`wrist`:
#                grip angle, ulnar and radial range), where the glove would slip;
#   the hold     how far the bend has left `hold` (1 − cos), ZERO for none.
const SWIVEL_TORSO: float = 200.0
const SWIVEL_REST: float = 1.0
const SWIVEL_SHOULDER: float = 10.0
const SWIVEL_EXTENSION_MAX: float = deg_to_rad(45.0)
const SWIVEL_WRIST: float = 4.0
const SWIVEL_HOLD: float = 1.0

static func swivel_cost(shoulder: Vector3, elbow: Vector3, hand: Vector3, bend: Vector3,
		upper_len: float, rest_n: Vector3, hold: Vector3, outward: Vector3, back: Vector3,
		to_torso: Transform3D, unit: float, shaft: Vector3, wrist: Vector3) -> float:
	var cost: float = SWIVEL_TORSO * maxf(_arm_depth(shoulder, elbow, hand, to_torso, unit), 0.0)
	cost += SWIVEL_REST * (1.0 - bend.dot(rest_n))
	var upper: Vector3 = (elbow - shoulder) / upper_len
	var behind: float = upper.dot(back)
	cost += SWIVEL_SHOULDER * (maxf(asin(clampf(behind, -1.0, 1.0)) - SWIVEL_EXTENSION_MAX, 0.0)
			+ maxf(behind, 0.0) * maxf(-upper.dot(outward), 0.0))
	if shaft != Vector3.ZERO:
		var fore: Vector3 = hand - elbow
		if fore.length_squared() > 0.000001:
			var deviation: float = fore.angle_to(shaft) - wrist.x
			cost += SWIVEL_WRIST * (maxf(deviation - wrist.z, 0.0) + maxf(-wrist.y - deviation, 0.0))
	if hold != Vector3.ZERO:
		cost += SWIVEL_HOLD * (1.0 - bend.dot(hold))
	return cost


# Where along the shoulder→hand line the elbow's circle is centred, and its
# radius, as TwoBoneIK.solve_elbow places them.
static func _elbow_foot(d: float, upper_len: float, forearm_len: float) -> float:
	var span: float = clampf(d, absf(upper_len - forearm_len), upper_len + forearm_len)
	return (upper_len * upper_len - forearm_len * forearm_len + span * span) / (2.0 * span)


static func _elbow_offset(d: float, upper_len: float, forearm_len: float) -> float:
	var foot: float = _elbow_foot(d, upper_len, forearm_len)
	return sqrt(maxf(upper_len * upper_len - foot * foot, 0.0))


# How far the arm with its elbow at `elbow` sinks into the torso past contact
# (m) at the deepest of the elbow, the upper arm SWIVEL_UPPER_SAMPLE of the way
# down to it and the forearm 40% of the way to the hand, each allowed
# SWIVEL_CONTACT_M of overlap: a sleeve lying against the ribs is an arm at
# rest, not a clip. The upper arm's half by the armpit lies against the
# jersey's side even hanging, where the skin blends the two, and the forearm's
# last stretch is where the hand is, which no elbow moves. Negative, by the
# narrowest margin, when it clears.
const SWIVEL_CONTACT_M: float = 0.03
const SWIVEL_UPPER_SAMPLE: float = 0.75

static func _arm_depth(shoulder: Vector3, elbow: Vector3, hand: Vector3,
		to_torso: Transform3D, unit: float) -> float:
	return maxf(_depth(elbow, to_torso, unit), maxf(_depth(shoulder.lerp(elbow,
			SWIVEL_UPPER_SAMPLE), to_torso, unit), _depth(elbow.lerp(hand, 0.4), to_torso, unit)))


static func _depth(p: Vector3, to_torso: Transform3D, unit: float) -> float:
	return SkaterMeshBuilder.SLEEVE_RADIUS_M - SWIVEL_CONTACT_M \
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
		ulnar_max: float, radial_max: float, thickness: Vector3,
		roll: float = 0.0) -> Transform3D:
	return Transform3D(glove_basis((hand - elbow).normalized(), shaft, grip_angle, ulnar_max,
			radial_max, roll).scaled_local(thickness), hand)


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
#
# `roll` turns the fist round the shaft off that (grip_roll): the wrist's
# flexion, which carries the hand's long axis out of the forearm and shaft's
# plane while the shaft stays across the palm at the same angle.
static func glove_basis(forearm_dir: Vector3, shaft: Vector3, grip_angle: float,
		ulnar_max: float, radial_max: float, roll: float = 0.0) -> Basis:
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
	if roll != 0.0:
		hand_axis = hand_axis.rotated(shaft, roll)
		thumb = thumb.rotated(shaft, roll)
	return Basis(thumb, -hand_axis, thumb.cross(-hand_axis))


# How far the fist on the shaft rolls round it off glove_basis's grip (radians,
# about `shaft`), so the forearm holding it need not twist further than
# `twist_max` off its neutral (`neutral`, neutral_thumb): held in the forearm and
# shaft's plane, a shaft running down and away from a forearm across the body
# leaves the thumb turned half round from where the forearm can put it. The
# wrist's flexion rolls the hand, as far as `flex_max` of its long axis out of
# that plane, and no further than brings the twist inside its range. `way`
# (±1) is the way it rolls: always the same one for a hand, since choosing
# the way that untwists sooner turns the fist over the shaft where the two
# tie; 0 chooses it anyway.
const _ROLL_BISECTIONS: int = 8

static func grip_roll(forearm_dir: Vector3, shaft: Vector3, grip_angle: float,
		ulnar_max: float, radial_max: float, neutral: Vector3, twist_max: float,
		flex_max: float, way: float = 0.0) -> float:
	if shaft == Vector3.ZERO or neutral == Vector3.ZERO:
		return 0.0
	var base: Basis = glove_basis(forearm_dir, shaft, grip_angle, ulnar_max, radial_max)
	var thumb: Vector3 = base.x
	var twist: float = forearm_twist(forearm_dir, thumb, neutral)
	if twist <= twist_max:
		return 0.0
	var off_plane: float = sin((-base.y).angle_to(shaft))
	var reach: float = PI * 0.5 if off_plane <= sin(flex_max) \
			else asin(sin(flex_max) / off_plane)
	if way == 0.0:
		way = 1.0 if forearm_twist(forearm_dir, thumb.rotated(shaft, reach), neutral) \
				<= forearm_twist(forearm_dir, thumb.rotated(shaft, -reach), neutral) else -1.0
	var at_reach: float = forearm_twist(forearm_dir, thumb.rotated(shaft, way * reach), neutral)
	if at_reach > twist_max:
		return way * reach
	var lo: float = 0.0
	var hi: float = reach
	var twist_hi: float = at_reach
	for _i: int in _ROLL_BISECTIONS:
		var mid: float = (lo + hi) * 0.5
		var t: float = forearm_twist(forearm_dir, thumb.rotated(shaft, way * mid), neutral)
		if t > twist_max:
			lo = mid
			twist = t
		else:
			hi = mid
			twist_hi = t
	return way * lerpf(lo, hi, (twist - twist_max) / maxf(twist - twist_hi, 0.000001))


# The way (grip_roll's `way`) a top fist rolls to turn its knuckles forward,
# for a left shot (whose top hand is his right) or a right one.
static func knuckles_forward(left_shot: bool) -> float:
	return -1.0 if left_shot else 1.0


# How far (radians) the forearm pointing `forearm_dir` turns a thumb off its
# neutral, about the forearm.
static func forearm_twist(forearm_dir: Vector3, thumb: Vector3, neutral: Vector3) -> float:
	var across: Vector3 = thumb - forearm_dir * thumb.dot(forearm_dir)
	if across.length_squared() < 0.000001:
		return 0.0
	return across.angle_to(neutral)


# Where a forearm from `elbow` to `hand` points its thumb untwisted, the arm
# from `shoulder`: away from the elbow's point, square to the forearm — an arm
# bent in front of the chest holds its thumb up. ZERO for an arm too straight
# to have a point.
static func neutral_thumb(shoulder: Vector3, elbow: Vector3, hand: Vector3) -> Vector3:
	var line: Vector3 = hand - shoulder
	var fore: Vector3 = hand - elbow
	if line.length_squared() < 0.000001 or fore.length_squared() < 0.000001:
		return Vector3.ZERO
	line = line.normalized()
	fore = fore.normalized()
	var bend: Vector3 = (elbow - shoulder) - line * (elbow - shoulder).dot(line)
	var away: Vector3 = -(bend - fore * bend.dot(fore))
	return away.normalized() if away.length_squared() > 0.000001 else Vector3.ZERO


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

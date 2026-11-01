class_name ArmAnatomy
extends RefCounted

# Whether a human arm can hold a hand where a stick puts it, and how: the
# shoulder's three rotations, the elbow's bend, the forearm's twist and the
# wrist's two angles, each inside its clinical range, the arm out of the
# jersey. docs/arm-anatomy-plan.md §3.
#
# Angles are measured in the arm's own side of the trunk, mirrored so both
# arms read as a right arm: +X out to that side, +Y up, -Z ahead. At zero the
# arm hangs, the elbow bends straight ahead and the palm faces in, thumb up.

# Clinical active ranges, adult (AAOS), radians.
const SHOULDER_EXTENSION_MAX: float = deg_to_rad(50.0)
const SHOULDER_ELEVATION_MAX: float = deg_to_rad(180.0)
const SHOULDER_ADDUCTION_MAX: float = deg_to_rad(40.0)
const SHOULDER_HORIZONTAL_ADDUCTION_MAX: float = deg_to_rad(130.0)
const SHOULDER_INTERNAL_MAX: float = deg_to_rad(70.0)
const SHOULDER_EXTERNAL_MAX: float = deg_to_rad(90.0)
const ELBOW_FLEXION_MAX: float = deg_to_rad(145.0)
const PRONATION_MAX: float = deg_to_rad(80.0)
const SUPINATION_MAX: float = deg_to_rad(85.0)
const WRIST_FLEXION_MAX: float = deg_to_rad(80.0)
const WRIST_EXTENSION_MAX: float = deg_to_rad(70.0)
const WRIST_RADIAL_MAX: float = deg_to_rad(20.0)
const WRIST_ULNAR_MAX: float = deg_to_rad(30.0)

# The limit a pose is held to, or the one it breaks.
enum Limit {
	NONE,
	REACH,
	SHOULDER_ELEVATION,
	SHOULDER_INTERNAL,
	SHOULDER_EXTERNAL,
	ELBOW_FLEXION,
	PRONATION,
	SUPINATION,
	WRIST_FLEXION,
	WRIST_EXTENSION,
	WRIST_RADIAL,
	WRIST_ULNAR,
	ARM_IN_TORSO,
	HAND_IN_TORSO,
}

# How far the elbow's bend is from rest in the comfort cost: a hand held in front
# of the body is held with the elbow bent, not straight.
const ELBOW_COMFORT: float = deg_to_rad(80.0)
# A metre of reach or depth weighs as this many radians of joint past its range.
const METRE_AS_RADIANS: float = 5.0
# How much worse a pose past a range is than any comfortable one, per radian:
# the swivel search follows the violation down to the feasible poses.
const VIOLATION_WEIGHT: float = 100.0
# Where down the upper arm its depth in the jersey is measured, of its length:
# its top half rides under the shoulder pad, which the skin joins into the
# torso, so only its lower part can be in the chest.
const UPPER_ARM_SAMPLE: float = 0.75
const _SWIVEL_SAMPLES: int = 16
const _SWIVEL_REFINES: int = 8
const _ROLL_STEP: float = deg_to_rad(30.0)
const _ROLL_NEIGHBOURS: int = 3


# One arm's pose and how it sits against its ranges.
class ArmPose:
	var root := Vector3.ZERO
	var elbow := Vector3.ZERO
	var hand := Vector3.ZERO
	var swivel: float = 0.0
	var roll: float = 0.0
	# The shoulder: how far the arm is raised off hanging, toward which side
	# (0 out to the side, +PI/2 ahead, PI across the body, -PI/2 behind), and its
	# turn about its own length (+ internal).
	var elevation: float = 0.0
	var plane: float = 0.0
	var axial: float = 0.0
	var elbow_flexion: float = 0.0
	# The forearm's twist (+ pronation) and the wrist (+ palmar flexion, + ulnar).
	var pronation: float = 0.0
	var wrist_flexion: float = 0.0
	var wrist_deviation: float = 0.0
	var torso_depth: float = 0.0
	var hand_depth: float = 0.0
	var reach_over: float = 0.0
	var cost: float = 0.0
	# The worst excess past a range (radians, or METRE_AS_RADIANS per metre); 0
	# when the pose holds.
	var violation: float = 0.0
	var binding: Limit = Limit.NONE
	# Of a pose that holds, the range it is nearest (radians to spare).
	var margin: float = INF
	var nearest: Limit = Limit.NONE

	func feasible() -> bool:
		return violation <= 0.0

	func copy_from(o: ArmPose) -> void:
		root = o.root
		elbow = o.elbow
		hand = o.hand
		swivel = o.swivel
		roll = o.roll
		elevation = o.elevation
		plane = o.plane
		axial = o.axial
		elbow_flexion = o.elbow_flexion
		pronation = o.pronation
		wrist_flexion = o.wrist_flexion
		wrist_deviation = o.wrist_deviation
		torso_depth = o.torso_depth
		hand_depth = o.hand_depth
		reach_over = o.reach_over
		cost = o.cost
		violation = o.violation
		binding = o.binding
		margin = o.margin
		nearest = o.nearest


# Everything an arm is solved against: its side, where the trunk has its
# shoulder and the jersey, and the hand on the shaft. World frame throughout.
class ArmSetup:
	var body: ArmAnatomyBody
	# +1 for an arm on the trunk's +X side.
	var side: float = 1.0
	var shoulder := Vector3.ZERO
	# The trunk's axes (+X right, +Y up, +Z back).
	var thorax := Basis.IDENTITY
	var torso := Transform3D.IDENTITY
	var hand := Vector3.ZERO
	# Along the shaft toward the blade, and the angle it crosses this palm at.
	var shaft := Vector3.FORWARD
	var grip_angle: float = 0.0
	# The hand's roll round the shaft (grip_frame), from the roll whose palm
	# faces down the shaft's side toward `roll_up`, is held in [roll_lo,
	# roll_hi], or chosen freely when roll_free.
	var roll_up := Vector3.UP
	var roll_free: bool = true
	var roll_lo: float = 0.0
	var roll_hi: float = 0.0


# The shoulder's raise past which a hand at `plane` cannot go: forward and out
# to the side all the way up; behind, extension's range; across the body, the
# horizontal adduction at shoulder height and adduction's lower down. Linear
# between those clinical points.
static func elevation_max(plane: float) -> float:
	var p: float = wrapf(plane, -PI, PI)
	if p < -PI * 0.5:
		return lerpf(SHOULDER_ADDUCTION_MAX, SHOULDER_EXTENSION_MAX, (p + PI) / (PI * 0.5))
	if p < 0.0:
		return lerpf(SHOULDER_EXTENSION_MAX, SHOULDER_ELEVATION_MAX, (p + PI * 0.5) / (PI * 0.5))
	if p < PI * 0.5:
		return SHOULDER_ELEVATION_MAX
	if p < SHOULDER_HORIZONTAL_ADDUCTION_MAX:
		return lerpf(SHOULDER_ELEVATION_MAX, PI * 0.5,
				(p - PI * 0.5) / (SHOULDER_HORIZONTAL_ADDUCTION_MAX - PI * 0.5))
	return lerpf(PI * 0.5, SHOULDER_ADDUCTION_MAX,
			(p - SHOULDER_HORIZONTAL_ADDUCTION_MAX) / (PI - SHOULDER_HORIZONTAL_ADDUCTION_MAX))


# The hand gripping a shaft running `shaft` (toward the blade) across its palm
# at `grip_angle` to its long axis, leaving past the thumb, rolled `roll` round
# the shaft from the roll whose palm faces down the shaft's side toward `up`:
# the hand's long axis (wrist to knuckles) in .y, its thumb's side in .x, the
# palm in .z, all for a right hand. A left hand is its mirror image, which the
# side frame (see the header) turns into a right one.
static func grip_frame(shaft: Vector3, grip_angle: float, roll: float,
		up: Vector3 = Vector3.UP) -> Basis:
	var across: Vector3 = up - shaft * up.dot(shaft)
	if across.length_squared() < 0.000001:
		across = Vector3.BACK - shaft * shaft.z
	across = across.normalized().rotated(shaft, roll)
	var axis: Vector3 = shaft * cos(grip_angle) + across * sin(grip_angle)
	var thumb: Vector3 = shaft * sin(grip_angle) - across * cos(grip_angle)
	return Basis(thumb, axis, thumb.cross(axis))


# The joint angles, depths and reach of an arm from `setup.shoulder` (before the
# girdle's give) to its hand, the elbow at `swivel` round the line between them
# and the hand rolled `roll` on the shaft, into `out`, with its comfort cost and
# how far it breaks a range.
static func evaluate(setup: ArmSetup, swivel: float, roll: float, out: ArmPose) -> void:
	var body: ArmAnatomyBody = setup.body
	var hand: Vector3 = setup.hand
	var root: Vector3 = TwoBoneIK.reach_root(setup.shoulder, hand, body.arm_reach(),
			body.girdle_slack)
	var span_v: Vector3 = hand - root
	var span: float = span_v.length()
	out.root = root
	out.hand = hand
	out.swivel = swivel
	out.roll = roll
	out.reach_over = maxf(span - (body.upper_len + body.fore_len), 0.0)
	var axis: Vector3 = span_v / span if span > 0.000001 else -setup.thorax.y
	var bend: Vector3 = _bend_direction(axis, setup.thorax, swivel)
	var foot: float = _elbow_foot(span, body.upper_len, body.fore_len)
	var radius: float = sqrt(maxf(body.upper_len * body.upper_len - foot * foot, 0.0))
	out.elbow = root + axis * foot + bend * radius
	_angles(setup, out, bend.cross(axis), roll)
	_depths(setup, out)
	_score(out)


# The best pose of an arm in `setup`: the elbow round its circle and the hand
# round the shaft, the one nearest rest of those that hold, else the one that
# breaks its ranges least. The swivel is searched with the hand laid along the
# forearm, then the roll about that, then each once more about the other.
static func solve(setup: ArmSetup, out: ArmPose, scratch: ArmPose) -> void:
	var best_swivel: float = 0.0
	var best: float = INF
	for i: int in _SWIVEL_SAMPLES:
		var swivel: float = TAU * float(i) / float(_SWIVEL_SAMPLES)
		evaluate(setup, swivel, 0.0, scratch)
		var score: float = _score_at(setup, swivel, _clamp_roll(setup,
				_aligned_roll(setup, scratch)), scratch)
		if score < best:
			best = score
			best_swivel = swivel
	evaluate(setup, best_swivel, 0.0, scratch)
	var roll: float = _roll_search(setup, best_swivel, _aligned_roll(setup, scratch), scratch)
	var swivel_end: float = _golden(setup, true, best_swivel, TAU / float(_SWIVEL_SAMPLES),
			roll, scratch)
	roll = _golden(setup, false, roll, _ROLL_STEP, swivel_end, scratch)
	evaluate(setup, swivel_end, roll, out)


# The roll round the shaft that lays the hand's long axis nearest the forearm
# holding it at `pose`: grip_frame's `across` turned onto the forearm's way
# across the shaft. The wrist is the arm's narrowest range and the forearm's
# twist one of its widest, so this is where a roll search starts.
static func _aligned_roll(setup: ArmSetup, pose: ArmPose) -> float:
	var shaft: Vector3 = _side(setup, setup.shaft).normalized()
	var up: Vector3 = _side(setup, setup.roll_up)
	var ref: Vector3 = up - shaft * up.dot(shaft)
	if ref.length_squared() < 0.000001:
		ref = Vector3.BACK - shaft * shaft.z
	var fore: Vector3 = _side(setup, pose.hand - pose.elbow)
	var want: Vector3 = fore - shaft * fore.dot(shaft)
	if want.length_squared() < 0.000001:
		return 0.0
	return ref.normalized().signed_angle_to(want.normalized(), shaft) * setup.side


# The setup's range holds the roll (the nearer end when outside it).
static func _clamp_roll(setup: ArmSetup, roll: float) -> float:
	if setup.roll_free:
		return roll
	var mid: float = (setup.roll_lo + setup.roll_hi) * 0.5
	var r: float = mid + angle_difference(mid, roll)
	if r >= setup.roll_lo and r <= setup.roll_hi:
		return r
	return setup.roll_lo if absf(angle_difference(r, setup.roll_lo)) \
			< absf(angle_difference(r, setup.roll_hi)) else setup.roll_hi


# The best roll at `swivel` among `centre` and its neighbours either way, the
# hand's least-turned roll (_trace_roll) with them.
static func _roll_search(setup: ArmSetup, swivel: float, centre: float, out: ArmPose) -> float:
	var best_roll: float = _clamp_roll(setup, centre)
	var best: float = _score_at(setup, swivel, best_roll, out)
	var trace: float = _clamp_roll(setup, _trace_roll(setup, out))
	var score: float = _score_at(setup, swivel, trace, out)
	if score < best:
		best = score
		best_roll = trace
	for k: int in range(-_ROLL_NEIGHBOURS, _ROLL_NEIGHBOURS + 1):
		if k == 0:
			continue
		var roll: float = _clamp_roll(setup, centre + _ROLL_STEP * float(k))
		score = _score_at(setup, swivel, roll, out)
		if score < best:
			best = score
			best_roll = roll
	return best_roll


static func _score_at(setup: ArmSetup, swivel: float, roll: float, out: ArmPose) -> float:
	evaluate(setup, swivel, roll, out)
	return out.cost + VIOLATION_WEIGHT * out.violation


# Golden-section search of the swivel (`on_swivel`) or the roll within `half`
# of `x`, the other held at `held`; the better of what it finds and `x`.
static func _golden(setup: ArmSetup, on_swivel: bool, x: float, half: float, held: float,
		scratch: ArmPose) -> float:
	var lo: float = x - half
	var hi: float = x + half
	var g: float = 0.6180339887
	var x1: float = hi - g * (hi - lo)
	var x2: float = lo + g * (hi - lo)
	var f1: float = _score_pair(setup, on_swivel, x1, held, scratch)
	var f2: float = _score_pair(setup, on_swivel, x2, held, scratch)
	for _i: int in _SWIVEL_REFINES:
		if f1 < f2:
			hi = x2
			x2 = x1
			f2 = f1
			x1 = hi - g * (hi - lo)
			f1 = _score_pair(setup, on_swivel, x1, held, scratch)
		else:
			lo = x1
			x1 = x2
			f1 = f2
			x2 = lo + g * (hi - lo)
			f2 = _score_pair(setup, on_swivel, x2, held, scratch)
	var found: float = x1 if f1 < f2 else x2
	return found if minf(f1, f2) < _score_pair(setup, on_swivel, x, held, scratch) else x


static func _score_pair(setup: ArmSetup, on_swivel: bool, x: float, held: float,
		out: ArmPose) -> float:
	if on_swivel:
		return _score_at(setup, x, held, out)
	return _score_at(setup, held, _clamp_roll(setup, x), out)


# An arm posed elsewhere (the rig's drawn one) read against the ranges: its
# root, elbow and hand as given, the hand's thumb side `thumb` and its long axis
# `axis` (wrist to knuckles), world frame.
static func measure(setup: ArmSetup, root: Vector3, elbow: Vector3, thumb: Vector3,
		axis: Vector3, out: ArmPose) -> void:
	out.root = root
	out.elbow = elbow
	out.hand = setup.hand
	out.reach_over = maxf(setup.hand.distance_to(root) - (setup.body.upper_len
			+ setup.body.fore_len), 0.0)
	var u: Vector3 = (elbow - root).normalized()
	var w: Vector3 = (setup.hand - elbow).normalized()
	var hinge: Vector3 = u.cross(w)
	if hinge.length_squared() < 0.0000001:
		hinge = _bend_direction(u, setup.thorax, 0.0).cross(u)
	var th: Vector3 = _side(setup, thumb).normalized()
	var a: Vector3 = _side(setup, axis).normalized()
	_angles_with(setup, out, hinge, Basis(th, a, th.cross(a)))
	_depths(setup, out)
	_score(out)


# The roll round the shaft that turns the hand least off where the forearm
# holding it at `pose` puts a hand at rest: the trace of the rotation between
# them is A + B cos(roll) + C sin(roll), maximal at atan2(C, B).
static func _trace_roll(setup: ArmSetup, pose: ArmPose) -> float:
	var rest: Basis = _forearm_rest(setup, pose)
	var t0: float = _trace(rest, _hand_frame(setup, 0.0))
	var t1: float = _trace(rest, _hand_frame(setup, PI * 0.5))
	var t2: float = _trace(rest, _hand_frame(setup, PI))
	var a: float = (t0 + t2) * 0.5
	var b: float = (t0 - t2) * 0.5
	var c: float = t1 - a
	return atan2(c, b)


static func _trace(m: Basis, n: Basis) -> float:
	return m.x.dot(n.x) + m.y.dot(n.y) + m.z.dot(n.z)


# Into the arm's mirrored side frame (see the file header).
static func _side(setup: ArmSetup, v: Vector3) -> Vector3:
	return Vector3(setup.side * setup.thorax.x.dot(v), setup.thorax.y.dot(v),
			setup.thorax.z.dot(v))


# The hand on the shaft in the arm's side frame, a right hand there.
static func _hand_frame(setup: ArmSetup, roll: float) -> Basis:
	var shaft: Vector3 = _side(setup, setup.shaft)
	return grip_frame(shaft.normalized(), setup.grip_angle, roll * setup.side,
			_side(setup, setup.roll_up))


# Where the forearm at `pose` holds a hand untwisted and the wrist straight, in
# the side frame: its long axis down the forearm, the thumb square to the elbow's
# hinge, the palm in.
static func _forearm_rest(setup: ArmSetup, pose: ArmPose) -> Basis:
	var fore: Vector3 = _side(setup, pose.hand - pose.elbow)
	var upper: Vector3 = _side(setup, pose.elbow - pose.root)
	var w: Vector3 = fore.normalized() if fore.length_squared() > 0.000001 \
			else _side(setup, -setup.thorax.y)
	var hinge: Vector3 = upper.cross(fore)
	if hinge.length_squared() < 0.0000001:
		var line: Vector3 = (pose.hand - pose.root).normalized()
		hinge = _side(setup, _bend_direction(line, setup.thorax, pose.swivel)).cross(w)
	hinge = hinge.normalized()
	var thumb: Vector3 = hinge.cross(w).normalized()
	return Basis(thumb, w, thumb.cross(w))


static func _angles(setup: ArmSetup, out: ArmPose, hinge_world: Vector3, roll: float) -> void:
	_angles_with(setup, out, hinge_world, _hand_frame(setup, roll))


# `hand` is the hand's frame in the side frame (grip_frame's layout).
static func _angles_with(setup: ArmSetup, out: ArmPose, hinge_world: Vector3,
		hand: Basis) -> void:
	var u: Vector3 = _side(setup, out.elbow - out.root)
	u = u.normalized() if u.length_squared() > 0.000001 else Vector3.DOWN
	out.elevation = acos(clampf(-u.y, -1.0, 1.0))
	out.plane = atan2(-u.z, u.x)
	# The upper arm's turn about itself: its hinge against where the arm swung
	# straight up from hanging carries the hanging arm's (out to the side).
	var hinge: Vector3 = _side(setup, hinge_world) * setup.side
	hinge = (hinge - u * hinge.dot(u)).normalized()
	var swing := Quaternion(Vector3.DOWN, u) if u.y < 0.9999 else Quaternion(Vector3.RIGHT, PI)
	var ref: Vector3 = swing * Vector3.RIGHT
	out.axial = -atan2(u.dot(ref.cross(hinge)), ref.dot(hinge))
	var w: Vector3 = _side(setup, out.hand - out.elbow).normalized()
	out.elbow_flexion = acos(clampf(u.dot(w), -1.0, 1.0))
	var rest: Basis = _forearm_rest(setup, out)
	var held: Basis = rest.transposed() * hand
	var euler: Vector3 = held.get_euler(EULER_ORDER_YXZ)
	out.pronation = -euler.y
	out.wrist_flexion = euler.x
	out.wrist_deviation = euler.z


# How deep the sleeve and the fist sit in the jersey, past what they may.
static func _depths(setup: ArmSetup, out: ArmPose) -> void:
	var body: ArmAnatomyBody = setup.body
	var to_torso: Transform3D = setup.torso.affine_inverse()
	var unit: float = setup.torso.basis.get_scale().x
	var allowed: float = body.sleeve_radius - body.sleeve_contact
	var elbow: float = _clearance(body, to_torso * out.elbow)
	var upper: float = _clearance(body, to_torso * out.root.lerp(out.elbow, UPPER_ARM_SAMPLE))
	var fore: float = _clearance(body, to_torso * out.elbow.lerp(out.hand, 0.4))
	out.torso_depth = allowed - minf(elbow, minf(upper, fore)) * unit
	out.hand_depth = body.hand_radius - _clearance(body, to_torso * out.hand) * unit


static func _clearance(body: ArmAnatomyBody, p: Vector3) -> float:
	return TorsoSection.clearance(p, body.torso_profile, body.torso_sway, body.torso_xz_scale)


static func _score(out: ArmPose) -> void:
	out.violation = 0.0
	out.binding = Limit.NONE
	out.margin = INF
	out.nearest = Limit.NONE
	_hold(out, Limit.REACH, out.reach_over * METRE_AS_RADIANS, 0.0)
	_hold(out, Limit.SHOULDER_ELEVATION, out.elevation, elevation_max(out.plane))
	_hold(out, Limit.SHOULDER_INTERNAL, out.axial, SHOULDER_INTERNAL_MAX)
	_hold(out, Limit.SHOULDER_EXTERNAL, -out.axial, SHOULDER_EXTERNAL_MAX)
	_hold(out, Limit.ELBOW_FLEXION, out.elbow_flexion, ELBOW_FLEXION_MAX)
	_hold(out, Limit.PRONATION, out.pronation, PRONATION_MAX)
	_hold(out, Limit.SUPINATION, -out.pronation, SUPINATION_MAX)
	_hold(out, Limit.WRIST_FLEXION, out.wrist_flexion, WRIST_FLEXION_MAX)
	_hold(out, Limit.WRIST_EXTENSION, -out.wrist_flexion, WRIST_EXTENSION_MAX)
	_hold(out, Limit.WRIST_ULNAR, out.wrist_deviation, WRIST_ULNAR_MAX)
	_hold(out, Limit.WRIST_RADIAL, -out.wrist_deviation, WRIST_RADIAL_MAX)
	_hold(out, Limit.ARM_IN_TORSO, out.torso_depth * METRE_AS_RADIANS, 0.0)
	_hold(out, Limit.HAND_IN_TORSO, out.hand_depth * METRE_AS_RADIANS, 0.0)
	var c: float = 0.0
	c += _sq(out.elevation / SHOULDER_ELEVATION_MAX)
	c += _sq(out.axial / (SHOULDER_INTERNAL_MAX if out.axial > 0.0 else SHOULDER_EXTERNAL_MAX))
	c += _sq((out.elbow_flexion - ELBOW_COMFORT) / ELBOW_FLEXION_MAX)
	c += _sq(out.pronation / (PRONATION_MAX if out.pronation > 0.0 else SUPINATION_MAX))
	c += _sq(out.wrist_flexion
			/ (WRIST_FLEXION_MAX if out.wrist_flexion > 0.0 else WRIST_EXTENSION_MAX))
	c += _sq(out.wrist_deviation
			/ (WRIST_ULNAR_MAX if out.wrist_deviation > 0.0 else WRIST_RADIAL_MAX))
	out.cost = c


# `value` against its `limit`: the worst excess so far is the binding one, the
# smallest room of a pose that holds is its nearest.
static func _hold(out: ArmPose, limit: Limit, value: float, ceiling: float) -> void:
	var over: float = value - ceiling
	if over > out.violation:
		out.violation = over
		out.binding = limit
	if -over < out.margin:
		out.margin = -over
		out.nearest = limit


static func _sq(x: float) -> float:
	return x * x


# The elbow's way off the shoulder-hand line `axis` at `swivel` radians round it
# from straight down the trunk (world frame).
static func _bend_direction(axis: Vector3, thorax: Basis, swivel: float) -> Vector3:
	var down: Vector3 = -thorax.y - axis * (-thorax.y).dot(axis)
	if down.length_squared() < 0.000001:
		down = -thorax.z - axis * (-thorax.z).dot(axis)
	return down.normalized().rotated(axis, swivel)


static func _elbow_foot(d: float, upper_len: float, forearm_len: float) -> float:
	var span: float = clampf(d, maxf(absf(upper_len - forearm_len), 0.0001),
			upper_len + forearm_len)
	return (upper_len * upper_len - forearm_len * forearm_len + span * span) / (2.0 * span)

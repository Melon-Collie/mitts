class_name SkaterHoldModel
extends RefCounted

# Whether a body can hold the stick where gameplay put it: the top hand at
# `hand`, the blade's heel at `blade`, both in UpperBody's frame, against the
# trunk as the tick has it (Body, filled by SkaterIKCoordinator.fill_hold_body).
# Each limit is reported as how far past it the pose is, metres; zero is held.
# The arms are the ones the rig draws (TwoBoneIK.reach_root, the elbow's swivel,
# SkaterArmPoses), and the jersey is SkaterMeshBuilder's, so what is measured is
# what would be drawn. docs/held-hands-plan.md §5–§6.


class Body:
	# Each in UpperBody's frame. Index 0 the top arm, 1 the bottom.
	var shoulders := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var rest_poles := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var outward := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var back := Vector3.BACK
	# The TORSO bone's pose: the jersey's section is in its frame.
	var torso := Transform3D.IDENTITY
	var upper_len: float = 0.33
	var forearm_len: float = 0.33
	# The arm's working length, and how far the girdle gives past it.
	var reach: float = 0.64
	var slack: float = 0.06
	var elbow_flex_max: float = deg_to_rad(145.0)
	# (grip angle, ulnar, radial) per hand, as SkaterArmPoses.swivel_bend takes it.
	var wrists := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var fist_radius: float = 0.07
	# The knob past the top hand, and its radius.
	var knob_extend: float = SkaterStickRig.SHAFT_BUTT_EXTEND_M
	var knob_radius: float = 0.035
	# The bottom hand's grip (BottomHandIK.reachable_grip): no nearer the top
	# hand than `spacing` (m), preferring `grip` (fraction of the shaft from the
	# top hand).
	var spacing: float = 0.12
	var grip: float = 0.25


# One arm holding the shaft at a point: its reach past full length and its
# sleeve in the jersey past contact at its best elbow (m), the glove's slip off
# its grip there (radians, reported, not a limit), and that elbow.
class ArmHold:
	var reach_past: float = 0.0
	var sleeve: float = 0.0
	var slip: float = 0.0
	var elbow := Vector3.ZERO


class Report:
	var fist: float = 0.0
	# The top hand nearer its own shoulder than the elbow's flexion allows.
	var fold: float = 0.0
	var knob: float = 0.0
	var shaft: float = 0.0
	var top := ArmHold.new()
	# The bottom arm where it holds the shaft, the fraction of the shaft from the
	# top hand that is, and the place; its reach is how far that place lies past
	# the arm's reach with the girdle's give.
	var bottom := ArmHold.new()
	var bottom_grip: float = 0.0
	var bottom_hand := Vector3.ZERO

	# Metres past every limit, summed: zero is a pose a body holds.
	func total() -> float:
		return fist + fold + knob + shaft + top.reach_past + top.sleeve \
				+ bottom.reach_past + bottom.sleeve

	# The limit furthest past, by name, or "" when held.
	func binding() -> String:
		var names: Array[String] = ["fist", "fold", "knob", "shaft", "reach", "sleeve",
				"b.reach", "b.sleeve"]
		var values: Array[float] = [fist, fold, knob, shaft, top.reach_past, top.sleeve,
				bottom.reach_past, bottom.sleeve]
		var worst: int = -1
		for i: int in values.size():
			if values[i] > 0.0 and (worst < 0 or values[i] > values[worst]):
				worst = i
		return "" if worst < 0 else names[worst]


# The shaft is measured from the top glove down this far toward the blade:
# below it the shaft is past the jersey's hem.
const SHAFT_SAMPLES: int = 8
const SHAFT_FROM: float = 0.12
const SHAFT_TO: float = 0.6
const SHAFT_RADIUS_M: float = 0.015


static func evaluate(body: Body, hand: Vector3, blade: Vector3, out: Report) -> void:
	var to_torso: Transform3D = body.torso.affine_inverse()
	var unit: float = body.torso.basis.get_scale().x
	var span: Vector3 = blade - hand
	var length: float = span.length()
	var shaft: Vector3 = span / length if length > 0.0001 else Vector3.DOWN
	var contact: float = SkaterArmPoses.SWIVEL_CONTACT_M

	out.fist = maxf(body.fist_radius - contact - _clearance(hand, to_torso, unit), 0.0)
	out.knob = maxf(body.knob_radius - contact
			- _clearance(hand - shaft * body.knob_extend, to_torso, unit), 0.0)
	out.shaft = 0.0
	for k: int in SHAFT_SAMPLES:
		var t: float = lerpf(SHAFT_FROM, SHAFT_TO, float(k) / (SHAFT_SAMPLES - 1))
		out.shaft = maxf(out.shaft, SHAFT_RADIUS_M - contact
				- _clearance(hand + span * t, to_torso, unit))

	var top: Vector3 = body.shoulders[0]
	var folded: float = sqrt(body.upper_len * body.upper_len
			+ body.forearm_len * body.forearm_len
			- 2.0 * body.upper_len * body.forearm_len * cos(PI - body.elbow_flex_max))
	out.fold = maxf(folded - top.distance_to(hand), 0.0)
	_arm(body, 0, hand, shaft, to_torso, unit, out.top)

	# The bottom hand where the drawing puts it (SkaterIKCoordinator.
	# update_bottom_hand): the preferred grip, slid up the shaft as far as its arm
	# needs, no nearer the top hand than a glove's width.
	var bottom: int = 1
	var grip: Vector2 = BottomHandIK.reachable_grip(body.shoulders[bottom], hand, blade,
			body.grip, body.reach + body.slack, body.spacing)
	out.bottom_grip = grip.x
	out.bottom_hand = hand + span * grip.x
	_arm(body, bottom, out.bottom_hand, shaft, to_torso, unit, out.bottom)
	out.bottom.reach_past = grip.y


# One arm reaching `hand` on the shaft running `shaft`, into `out`.
static func _arm(body: Body, arm: int, hand: Vector3, shaft: Vector3, to_torso: Transform3D,
		unit: float, out: ArmHold) -> void:
	var root: Vector3 = TwoBoneIK.reach_root(body.shoulders[arm], hand, body.reach, body.slack)
	out.reach_past = maxf(root.distance_to(hand) - body.upper_len - body.forearm_len, 0.0)
	var wrist: Vector3 = body.wrists[arm]
	var bend: Vector3 = SkaterArmPoses.swivel_bend(root, hand, body.upper_len, body.forearm_len,
			body.rest_poles[arm], Vector3.ZERO, body.outward[arm], body.back, body.torso, shaft,
			wrist)
	out.elbow = SkaterArmPoses.elbow_on_circle(root, hand, body.upper_len, body.forearm_len, bend)
	out.sleeve = maxf(SkaterArmPoses._arm_depth(root, out.elbow, hand, to_torso, unit), 0.0)
	out.slip = 0.0
	var fore: Vector3 = hand - out.elbow
	if fore.length_squared() > 0.000001:
		var deviation: float = fore.angle_to(shaft) - wrist.x
		out.slip = maxf(deviation - wrist.z, 0.0) + maxf(-wrist.y - deviation, 0.0)


static func _clearance(p: Vector3, to_torso: Transform3D, unit: float) -> float:
	return SkaterMeshBuilder.torso_clearance(to_torso * p) * unit


# The held hand: `anchor` moved over the sphere the rigid stick allows round
# `blade` by the least that holds it, in a fixed number of steps from the
# anchor, so it is a function of its inputs alone. Each step moves the hand by
# every limit it breaks, each along the way out of it, as far as it is past —
# the fist, the knob and a point of the shaft out of the jersey along its
# normal (a shaft point moving 1/(1−t) of the hand, the blade the pivot), the
# hand off its own shoulder or toward it for the top arm's fold and reach, the
# hand out of the jersey with the elbow sunk in it, and the shaft toward the
# bottom shoulder with the bottom arm short or sunk — and back onto the
# sphere, its lie held within PROJECT_LIE_DEG of the anchor's. A move is as
# large as how far past its
# limit the pose is, so the correction grows from nothing where a limit starts
# to bind and the hand is the anchor wherever it holds. It steps until a step
# moves the hand less than PROJECT_SETTLED_M, at most PROJECT_STEPS times: a
# partial solve of a long move lands wherever its last step left it, which
# differs tick to tick, where the settled one moves with its inputs.
const PROJECT_STEPS: int = 24
const PROJECT_SETTLED_M: float = 0.0005
const PROJECT_LIE_DEG: float = 15.0
const _NORMAL_STEP_M: float = 0.01


static func project(body: Body, anchor: Vector3, blade: Vector3, scratch: Report) -> Vector3:
	var span: Vector3 = anchor - blade
	var length: float = span.length()
	if length < 0.0001:
		return anchor
	var lie0: float = asin(clampf(span.y / length, -1.0, 1.0))
	var to_torso: Transform3D = body.torso.affine_inverse()
	var unit: float = body.torso.basis.get_scale().x
	var hand: Vector3 = anchor
	for _i: int in PROJECT_STEPS:
		evaluate(body, hand, blade, scratch)
		if scratch.total() <= 0.0:
			break
		var push: Vector3 = _push(body, hand, blade, scratch, to_torso, unit)
		var next: Vector3 = _on_sphere(blade, hand + push, length, lie0)
		if not next.is_finite():
			return anchor
		var moved: float = next.distance_to(hand)
		hand = next
		if moved < PROJECT_SETTLED_M:
			break
	return hand


static func _push(body: Body, hand: Vector3, blade: Vector3, held: Report,
		to_torso: Transform3D, unit: float) -> Vector3:
	var span: Vector3 = blade - hand
	var shaft: Vector3 = span.normalized()
	var push := Vector3.ZERO
	if held.fist > 0.0:
		push += _out_of_jersey(hand, to_torso, unit) * held.fist
	if held.knob > 0.0:
		push += _out_of_jersey(hand - shaft * body.knob_extend, to_torso, unit) * held.knob
	if held.shaft > 0.0:
		var contact: float = SkaterArmPoses.SWIVEL_CONTACT_M
		var worst: float = 0.0
		var at: float = SHAFT_FROM
		for k: int in SHAFT_SAMPLES:
			var t: float = lerpf(SHAFT_FROM, SHAFT_TO, float(k) / (SHAFT_SAMPLES - 1))
			var depth: float = SHAFT_RADIUS_M - contact - _clearance(hand + span * t, to_torso, unit)
			if depth > worst:
				worst = depth
				at = t
		push += _out_of_jersey(hand + span * at, to_torso, unit) * (worst / (1.0 - at))
	var off_shoulder: Vector3 = (hand - body.shoulders[0]).normalized()
	push += off_shoulder * (held.fold - held.top.reach_past)
	if held.top.sleeve > 0.0:
		push += _out_of_jersey(held.top.elbow, to_torso, unit) * held.top.sleeve
	var lever: float = maxf(1.0 - held.bottom_grip, 0.2)
	if held.bottom.reach_past > 0.0:
		push += (body.shoulders[1] - held.bottom_hand).normalized() \
				* (held.bottom.reach_past / lever)
	if held.bottom.sleeve > 0.0:
		push += _out_of_jersey(held.bottom.elbow, to_torso, unit) * (held.bottom.sleeve / lever)
	return push


# The way out of the jersey at `p`: its clearance's gradient, by central
# differences. The clearance is infinite above the collar, so it is capped
# first, or a point at the collar differences infinity with itself.
const _CLEARANCE_CAP_M: float = 1.0

static func _out_of_jersey(p: Vector3, to_torso: Transform3D, unit: float) -> Vector3:
	var e: float = _NORMAL_STEP_M
	var g := Vector3(
			_capped(p + Vector3(e, 0.0, 0.0), to_torso, unit)
					- _capped(p - Vector3(e, 0.0, 0.0), to_torso, unit),
			_capped(p + Vector3(0.0, e, 0.0), to_torso, unit)
					- _capped(p - Vector3(0.0, e, 0.0), to_torso, unit),
			_capped(p + Vector3(0.0, 0.0, e), to_torso, unit)
					- _capped(p - Vector3(0.0, 0.0, e), to_torso, unit))
	return g.normalized() if g.length_squared() > 0.0 else Vector3.ZERO


static func _capped(p: Vector3, to_torso: Transform3D, unit: float) -> float:
	return minf(_clearance(p, to_torso, unit), _CLEARANCE_CAP_M)


# `p` put back on the sphere of `length` round `blade`, its lie held within
# PROJECT_LIE_DEG of `lie0`.
static func _on_sphere(blade: Vector3, p: Vector3, length: float, lie0: float) -> Vector3:
	var dir: Vector3 = p - blade
	var flat := Vector2(dir.x, dir.z)
	if flat.length_squared() < 0.000001:
		return blade + dir.normalized() * length
	var lie: float = clampf(atan2(dir.y, flat.length()), lie0 - deg_to_rad(PROJECT_LIE_DEG),
			lie0 + deg_to_rad(PROJECT_LIE_DEG))
	flat = flat.normalized() * cos(lie)
	return blade + Vector3(flat.x, sin(lie), flat.y) * length


# The best hands on the sphere a rigid stick allows round the blade's heel, by
# brute force over rings about `hand` (the anchor), each SEARCH_MOVES_M from it
# across the sphere: the reference a projection is measured against, and what an
# instrument maps with. Only stick lies within SEARCH_LIE_DEG of the anchor's
# are tried, so the hand swings round rather than lifting the blade onto its
# heel or toe.
class Search:
	# The least total any hand reached, and that hand.
	var best_total: float = INF
	var best_hand := Vector3.ZERO
	# The nearest hand the body holds outright (total under HELD_M), if any.
	var held_found: bool = false
	var held_hand := Vector3.ZERO

const SEARCH_MOVES_M: Array[float] = [0.02, 0.04, 0.06, 0.08, 0.1, 0.13, 0.16, 0.2, 0.25,
		0.3, 0.4, 0.5]
const SEARCH_AZIMUTHS: int = 16
const SEARCH_LIE_DEG: float = 15.0
const HELD_M: float = 0.002


static func search(body: Body, hand: Vector3, blade: Vector3, scratch: Report,
		out: Search) -> void:
	out.best_total = INF
	out.held_found = false
	var span: Vector3 = hand - blade
	var length: float = span.length()
	if length < 0.0001:
		return
	var dir0: Vector3 = span / length
	var lie0: float = asin(clampf(dir0.y, -1.0, 1.0))
	var t1: Vector3 = dir0.cross(Vector3.UP)
	if t1.length_squared() < 0.000001:
		t1 = Vector3.RIGHT
	t1 = t1.normalized()
	var t2: Vector3 = dir0.cross(t1)
	evaluate(body, hand, blade, scratch)
	out.best_total = scratch.total()
	out.best_hand = hand
	if out.best_total < HELD_M:
		out.held_found = true
		out.held_hand = hand
		return
	for move: float in SEARCH_MOVES_M:
		# A chord of `move` across the sphere.
		var r: float = 2.0 * asin(minf(move / (2.0 * length), 1.0))
		for k: int in SEARCH_AZIMUTHS:
			var phi: float = TAU * k / SEARCH_AZIMUTHS
			var dir: Vector3 = dir0 * cos(r) + (t1 * cos(phi) + t2 * sin(phi)) * sin(r)
			if absf(asin(clampf(dir.y, -1.0, 1.0)) - lie0) > deg_to_rad(SEARCH_LIE_DEG):
				continue
			var h: Vector3 = blade + dir * length
			evaluate(body, h, blade, scratch)
			var total: float = scratch.total()
			if total < out.best_total:
				out.best_total = total
				out.best_hand = h
			if total < HELD_M and not out.held_found:
				out.held_found = true
				out.held_hand = h
		if out.held_found:
			return

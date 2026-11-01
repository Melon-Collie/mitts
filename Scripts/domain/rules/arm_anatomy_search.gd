class_name ArmAnatomySearch
extends RefCounted

# Whether a body can hold a blade on the ice at a point, and how: of every
# trunk twist, every way the rigid stick can stand from that blade, every face
# tilt of it and every place down it the bottom hand can hold, the pose whose
# two arms (ArmAnatomy) hold it nearest rest, the stick out of the body. Or, if
# none holds, the one that breaks a range least and the range it breaks.
# docs/arm-anatomy-plan.md §3.2.
#
# The HIPS frame throughout: its origin the pivot the trunk folds and twists
# about, +X the skater's right, +Y up, -Z the way the hips face. The search
# runs off the hot path (an instrument, and in time once per build).

# Thoracolumbar ranges with the pelvis held (AAOS), radians.
const TRUNK_TWIST_MAX: float = deg_to_rad(45.0)
const TRUNK_FLEXION_MAX: float = deg_to_rad(80.0)
const TRUNK_SIDE_MAX: float = deg_to_rad(35.0)
# How far the stick may turn about its own length off a square face: the
# blade's face opens and closes this far and still plays the puck. Provisional,
# for review against the map (the stick's, not the body's).
const FACE_TILT_MAX: float = deg_to_rad(40.0)
# The shaft's half thickness (m), held out of the jersey.
const SHAFT_RADIUS: float = 0.015
const _SHAFT_SAMPLES: int = 12

# The coarse grid the search starts from, then refines about its best.
const _TWISTS: int = 5
const _ELEVATIONS: Array[float] = [15.0, 25.0, 35.0, 45.0, 55.0, 65.0, 75.0]
const _AZIMUTHS: int = 16
const _SPACING_STEPS: int = 2
const _SPACING_STEP_M: float = 0.1
const _REFINE_LEVELS: int = 3
const _SEEDS: int = 3
# The leans each seed is tried at before refining (forward, toward +X; deg):
# reaching out, a body leans into it.
const _LEAN_SEEDS: Array[Vector2] = [Vector2(15.0, 0.0), Vector2(30.0, 0.0),
		Vector2(15.0, 15.0), Vector2(15.0, -15.0)]
const _LEAN_STEP: float = deg_to_rad(10.0)
# The crouches each seed is tried at, as shares of the trunk's crouch_max, and
# the refinement's first step in it (m).
const _CROUCH_SEEDS: Array[float] = [0.5, 1.0]
const _CROUCH_STEP_M: float = 0.06
# A crouch's comfort cost runs from none to as much as a joint at its range's
# end over this (m): a hockey stance's whole sit.
const CROUCH_COMFORT_M: float = 0.3
# How much further a hand reaches with the trunk leaned into it (m): the
# reach test's allowance for the leans the search tries.
const _LEAN_REACH_M: float = 0.3

enum Limit { NONE, TRUNK_TWIST, TRUNK_FLEXION, TRUNK_SIDE, SHAFT_IN_TORSO, TECHNIQUE }


# The trunk as the frame holds it: tipped toward the body's acceleration
# (`tilt`, the balance lean's share the trunk keeps), folded forward about the
# hips, leaned on past that, and bent to the side (radians; + forward, + toward
# +X), then the chest's own turn on that about the same pivot (the rig's trunk
# texture: the carry's fold over the stick), which carries the shoulders and
# the jersey.
class TrunkState:
	# How far the search may sink the hips toward the ice on the knees (m): a
	# standing carrier's stance, which the stride owns once he skates.
	var crouch_max: float = 0.0
	var tilt := Basis.IDENTITY
	var fold: float = 0.0
	var pitch: float = 0.0
	var side: float = 0.0
	var chest := Basis.IDENTITY


# A whole pose: the trunk's twist, the stick standing from the blade (its angle
# to the ice and its heading, hand to blade), its face's tilt off square, the
# bottom hand's place down it, both arms, and how it scores.
class Pose:
	var twist: float = 0.0
	# The chest leaned on past the trunk's own (radians; forward, toward +X), and
	# the hips sunk on the knees past the trunk's own (m).
	var lean := Vector2.ZERO
	var crouch: float = 0.0
	var lie: float = 0.0
	var heading: float = 0.0
	var face_tilt: float = 0.0
	var spacing: float = 0.0
	var top := ArmAnatomy.ArmPose.new()
	var bottom := ArmAnatomy.ArmPose.new()
	var shaft_depth: float = 0.0
	var technique := ArmTechnique.Verdict.new()
	var cost: float = INF
	var violation: float = INF
	# Which arm (0 top, 1 bottom, -1 neither) breaks a range, and the range: the
	# arm's ArmAnatomy.Limit, else this file's Limit, else technique's
	# (`technique.binding`, when `trunk_binding` is TECHNIQUE).
	var binding_arm: int = -1
	var arm_binding: ArmAnatomy.Limit = ArmAnatomy.Limit.NONE
	var trunk_binding: Limit = Limit.NONE

	func feasible() -> bool:
		return violation <= 0.0

	func score() -> float:
		return cost + ArmAnatomy.VIOLATION_WEIGHT * violation

	func copy_from(o: Pose) -> void:
		twist = o.twist
		lean = o.lean
		crouch = o.crouch
		lie = o.lie
		heading = o.heading
		face_tilt = o.face_tilt
		spacing = o.spacing
		top.copy_from(o.top)
		bottom.copy_from(o.bottom)
		shaft_depth = o.shaft_depth
		technique.violation = o.technique.violation
		technique.binding = o.technique.binding
		cost = o.cost
		violation = o.violation
		binding_arm = o.binding_arm
		arm_binding = o.arm_binding
		trunk_binding = o.trunk_binding


# Hold every pose to how players carry too (ArmTechnique), not anatomy alone.
var technique: bool = false
var _body: ArmAnatomyBody
var _hold := ArmTechnique.Hold.new()
var _top := ArmAnatomy.ArmSetup.new()
var _bottom := ArmAnatomy.ArmSetup.new()
var _scratch := ArmAnatomy.ArmPose.new()
var _trial := Pose.new()
var _seeded := Pose.new()
# The lean _try poses the chest at, and the trunk it last scored.
var _lean := Vector2.ZERO
var _crouch: float = 0.0
var _trunk_now := TrunkState.new()
var _seeds: Array[Vector4] = []


func _init(body: ArmAnatomyBody) -> void:
	_body = body
	for s: ArmAnatomy.ArmSetup in [_top, _bottom]:
		s.body = body
	_top.side = signf(body.top_shoulder.x)
	_bottom.side = signf(body.bottom_shoulder.x)
	_top.grip_angle = body.top_grip_angle
	_bottom.grip_angle = body.bottom_grip_angle
	_top.roll_free = false
	_bottom.roll_free = true


# The chest's frame in the hips' at `twist`, as SkaterSpineRig and the trunk
# texture build it: the tilt, the fold about the hips, then the twist, then the
# lean and the side bend, then the chest's own turn with `lean` (forward,
# toward +X) laid on it, as the carry lays it on the trunk texture.
static func spine_basis(trunk: TrunkState, twist: float, lean: Vector2 = Vector2.ZERO) -> Basis:
	var chest: Basis = trunk.chest
	if lean != Vector2.ZERO:
		chest = Basis.from_euler(chest.get_euler() + Vector3(-lean.x, 0.0, -lean.y))
	return trunk.tilt * Basis(Vector3.RIGHT, -trunk.fold) * Basis(Vector3.UP, twist) \
			* Basis.from_euler(Vector3(-trunk.pitch, 0.0, -trunk.side)) * chest


# The best pose holding the blade's heel at `heel` (hips frame, on the ice).
func solve(trunk: TrunkState, heel: Vector3, out: Pose) -> void:
	out.cost = INF
	out.violation = INF
	_lean = Vector2.ZERO
	_crouch = 0.0
	_seeds.clear()
	var twist_step: float = 2.0 * TRUNK_TWIST_MAX / float(_TWISTS - 1)
	for i: int in _TWISTS:
		var twist: float = -TRUNK_TWIST_MAX + twist_step * float(i)
		for elevation: float in _ELEVATIONS:
			for j: int in _AZIMUTHS:
				var heading: float = TAU * float(j) / float(_AZIMUTHS)
				if not _in_reach(trunk, heel, twist, deg_to_rad(elevation), heading):
					continue
				var score: float = _try(trunk, heel, twist, deg_to_rad(elevation), heading,
						-1.0, out)
				_keep_seed(Vector4(score, twist, deg_to_rad(elevation), heading))
	if out.cost == INF:
		_fail_reach(trunk, heel, out)
		return
	# The best few of the grid each refined: the best one alone settles in its
	# own basin, often not the deepest.
	for seed_at: Vector4 in _seeds:
		hold(trunk, heel, seed_at.y, seed_at.z, seed_at.w, -1.0, _seeded)
		for lean_deg: Vector2 in _LEAN_SEEDS:
			_lean = lean_deg * (PI / 180.0)
			for crouch_share: float in [0.0] + _CROUCH_SEEDS if trunk.crouch_max > 0.0 else [0.0]:
				_crouch = trunk.crouch_max * crouch_share
				_try(trunk, heel, seed_at.y, seed_at.z, seed_at.w, -1.0, _seeded)
		_crouch = _seeded.crouch
		var steps := Vector3(twist_step, deg_to_rad(10.0), TAU / float(_AZIMUTHS))
		var lean_step: float = _LEAN_STEP
		var crouch_step: float = _CROUCH_STEP_M
		for _level: int in _REFINE_LEVELS:
			steps *= 0.5
			lean_step *= 0.5
			crouch_step *= 0.5
			_refine(trunk, heel, steps, lean_step, crouch_step, _seeded)
		if _seeded.score() < out.score():
			out.copy_from(_seeded)


# Holds the grid's _SEEDS best stick poses, (score, twist, lie, heading).
func _keep_seed(at: Vector4) -> void:
	if _seeds.size() < _SEEDS:
		_seeds.append(at)
	else:
		var worst: int = 0
		for k: int in _seeds.size():
			if _seeds[k].x > _seeds[worst].x:
				worst = k
		if at.x >= _seeds[worst].x:
			return
		_seeds[worst] = at


# The pose of a given trunk twist and stick (out.twist, .lie, .heading,
# .spacing) with only the arms' own freedoms solved: how a body holds the pose
# gameplay chose. `spacing` < 0 searches the bottom hand's place too.
func hold(trunk: TrunkState, heel: Vector3, twist: float, lie: float, heading: float,
		spacing: float, out: Pose, lean: Vector2 = Vector2.ZERO, crouch: float = 0.0) -> void:
	out.cost = INF
	out.violation = INF
	_lean = lean
	_crouch = crouch
	_try(trunk, heel, twist, lie, heading, spacing, out)


# Where the top hand is for a stick standing at `lie` and `heading` (hand to
# blade) on the heel at `heel`, and the shaft's way toward the blade.
func top_hand(heel: Vector3, lie: float, heading: float) -> Vector3:
	return heel - _shaft(lie, heading) * _body.stick_length


static func _shaft(lie: float, heading: float) -> Vector3:
	return Vector3(sin(heading) * cos(lie), -sin(lie), -cos(heading) * cos(lie))


func _in_reach(trunk: TrunkState, heel: Vector3, twist: float, lie: float,
		heading: float) -> bool:
	var spine: Basis = spine_basis(trunk, twist)
	var hand: Vector3 = top_hand(heel, lie, heading)
	var most: float = _body.upper_len + _body.fore_len + _body.girdle_slack + 0.05 \
			+ _LEAN_REACH_M
	if hand.distance_to(spine * _body.top_shoulder) > most:
		return false
	var shaft: Vector3 = _shaft(lie, heading)
	var near: Vector3 = Geometry3D.get_closest_point_to_segment(spine * _body.bottom_shoulder,
			hand + shaft * _body.spacing_min, hand + shaft * _spacing_max())
	return near.distance_to(spine * _body.bottom_shoulder) <= most


# Scores one stick pose into `_trial`, keeps it in `best` if it beats it, and
# returns its score.
func _try(trunk: TrunkState, heel: Vector3, twist: float, lie: float, heading: float,
		spacing: float, best: Pose) -> float:
	var t: Pose = _trial
	var spine := Transform3D(spine_basis(trunk, twist, _lean), Vector3.ZERO)
	_trunk_now = trunk
	t.lean = _lean
	t.crouch = _crouch
	# The hips sunk on the knees: the blade, on the ice, rises toward them.
	heel.y += _crouch
	var shaft: Vector3 = _shaft(lie, heading)
	var hand: Vector3 = heel - shaft * _body.stick_length
	t.twist = twist
	t.lie = lie
	t.heading = heading
	for s: ArmAnatomy.ArmSetup in [_top, _bottom]:
		s.thorax = spine.basis
		s.torso = spine * _body.torso_in_spine
		s.shaft = shaft
		s.roll_up = Vector3.UP
	_top.shoulder = spine * _body.top_shoulder
	_bottom.shoulder = spine * _body.bottom_shoulder
	_top.hand = hand
	_top.roll_lo = _body.top_roll_square - FACE_TILT_MAX
	_top.roll_hi = _body.top_roll_square + FACE_TILT_MAX
	ArmAnatomy.solve(_top, t.top, _scratch)
	t.face_tilt = t.top.roll - _body.top_roll_square
	_hold_bottom(hand, shaft, spacing, t)
	t.shaft_depth = _shaft_depth(_top.torso, hand, heel)
	t.technique.violation = 0.0
	t.technique.binding = ArmTechnique.Limit.NONE
	if technique:
		_hold.top_hand = hand
		_hold.shaft = shaft
		_hold.spacing = t.spacing
		_hold.heel = heel
		_hold.blade_dir = Vector3(shaft.x, 0.0, shaft.z).normalized()
		_hold.top_shoulder = _top.shoulder
		_hold.torso = _top.torso
		ArmTechnique.assess(_body, _hold, t.technique)
	_total(t)
	if t.score() < best.score():
		best.copy_from(t)
	return t.score()


# The bottom hand where it holds best down the shaft from `hand`, or at
# `spacing` when that is given.
func _hold_bottom(hand: Vector3, shaft: Vector3, spacing: float, t: Pose) -> void:
	if spacing >= 0.0:
		t.spacing = spacing
		_bottom.hand = hand + shaft * spacing
		ArmAnatomy.solve(_bottom, t.bottom, _scratch)
		return
	# From the place on the shaft nearest the bottom shoulder, either way.
	var nearest: float = clampf((_bottom.shoulder - hand).dot(shaft), _body.spacing_min,
			_spacing_max())
	var best_score: float = INF
	var best_spacing: float = nearest
	for k: int in range(-_SPACING_STEPS, _SPACING_STEPS + 1):
		var d: float = clampf(nearest + _SPACING_STEP_M * float(k), _body.spacing_min,
				_spacing_max())
		_bottom.hand = hand + shaft * d
		ArmAnatomy.solve(_bottom, _scratch, t.bottom)
		var score: float = _scratch.cost + ArmAnatomy.VIOLATION_WEIGHT * _scratch.violation
		if score < best_score:
			best_score = score
			best_spacing = d
	t.spacing = best_spacing
	_bottom.hand = hand + shaft * best_spacing
	ArmAnatomy.solve(_bottom, t.bottom, _scratch)


# How deep the shaft sits in the jersey past its thickness (m), deepest point.
func _shaft_depth(torso: Transform3D, hand: Vector3, heel: Vector3) -> float:
	var to_torso: Transform3D = torso.affine_inverse()
	var unit: float = torso.basis.get_scale().x
	var deepest: float = -INF
	for k: int in _SHAFT_SAMPLES:
		var p: Vector3 = hand.lerp(heel, float(k + 1) / float(_SHAFT_SAMPLES + 1))
		var clear: float = TorsoSection.clearance(to_torso * p, _body.torso_profile,
				_body.torso_sway, _body.torso_xz_scale) * unit
		deepest = maxf(deepest, SHAFT_RADIUS - clear)
	return deepest


func _total(t: Pose) -> void:
	t.cost = t.top.cost + t.bottom.cost + _sq(t.twist / TRUNK_TWIST_MAX) \
			+ _sq(t.lean.x / TRUNK_FLEXION_MAX) + _sq(t.lean.y / TRUNK_SIDE_MAX) \
			+ _sq(t.crouch / CROUCH_COMFORT_M)
	t.violation = 0.0
	t.binding_arm = -1
	t.arm_binding = ArmAnatomy.Limit.NONE
	t.trunk_binding = Limit.NONE
	if t.top.violation > t.violation:
		t.violation = t.top.violation
		t.binding_arm = 0
		t.arm_binding = t.top.binding
	if t.bottom.violation > t.violation:
		t.violation = t.bottom.violation
		t.binding_arm = 1
		t.arm_binding = t.bottom.binding
	var twist_over: float = absf(t.twist) - TRUNK_TWIST_MAX
	if twist_over > t.violation:
		t.violation = twist_over
		t.binding_arm = -1
		t.arm_binding = ArmAnatomy.Limit.NONE
		t.trunk_binding = Limit.TRUNK_TWIST
	# The whole trunk's bend against its ranges: the fold, the lean and the
	# chest's own turn (forward), the side bend and the chest's roll.
	var chest: Vector3 = _trunk_now.chest.get_euler()
	var flexion_over: float = _trunk_now.fold + _trunk_now.pitch - chest.x + t.lean.x \
			- TRUNK_FLEXION_MAX
	if flexion_over > t.violation:
		t.violation = flexion_over
		t.binding_arm = -1
		t.arm_binding = ArmAnatomy.Limit.NONE
		t.trunk_binding = Limit.TRUNK_FLEXION
	var side_over: float = absf(_trunk_now.side - chest.z + t.lean.y) - TRUNK_SIDE_MAX
	if side_over > t.violation:
		t.violation = side_over
		t.binding_arm = -1
		t.arm_binding = ArmAnatomy.Limit.NONE
		t.trunk_binding = Limit.TRUNK_SIDE
	var shaft_over: float = t.shaft_depth * ArmAnatomy.METRE_AS_RADIANS
	if shaft_over > t.violation:
		t.violation = shaft_over
		t.binding_arm = -1
		t.arm_binding = ArmAnatomy.Limit.NONE
		t.trunk_binding = Limit.SHAFT_IN_TORSO
	if t.technique.violation > t.violation:
		t.violation = t.technique.violation
		t.binding_arm = -1
		t.arm_binding = ArmAnatomy.Limit.NONE
		t.trunk_binding = Limit.TECHNIQUE


# Coordinate descent about the best pose so far, each of the twist, the lie and
# the heading stepped both ways by `steps`, and the lean's two by `lean_step`.
func _refine(trunk: TrunkState, heel: Vector3, steps: Vector3, lean_step: float,
		crouch_step: float, best: Pose) -> void:
	var twist: float = best.twist
	var lie: float = best.lie
	var heading: float = best.heading
	var lean: Vector2 = best.lean
	var crouch: float = best.crouch
	for axis: int in 6:
		if axis == 5 and trunk.crouch_max <= 0.0:
			continue
		for sgn: float in [-1.0, 1.0]:
			var tw: float = twist + (steps.x * sgn if axis == 0 else 0.0)
			var li: float = lie + (steps.y * sgn if axis == 1 else 0.0)
			var he: float = heading + (steps.z * sgn if axis == 2 else 0.0)
			_lean = lean + Vector2(lean_step * sgn if axis == 3 else 0.0,
					lean_step * sgn if axis == 4 else 0.0)
			_crouch = crouch + (crouch_step * sgn if axis == 5 else 0.0)
			if absf(tw) > TRUNK_TWIST_MAX or li <= 0.0 or li >= PI * 0.5 or _lean.x < 0.0 \
					or _crouch < 0.0 or _crouch > trunk.crouch_max:
				continue
			_try(trunk, heel, tw, li, he, -1.0, best)
	_lean = best.lean
	_crouch = best.crouch


# No stick pose puts the top hand in reach: the nearest one, scored, so it
# names what binds.
func _fail_reach(trunk: TrunkState, heel: Vector3, out: Pose) -> void:
	var nearest: float = INF
	var at := Vector3.ZERO
	_lean = Vector2.ZERO
	_crouch = 0.0
	for elevation: float in _ELEVATIONS:
		for j: int in _AZIMUTHS:
			var heading: float = TAU * float(j) / float(_AZIMUTHS)
			var d: float = top_hand(heel, deg_to_rad(elevation), heading).distance_to(
					spine_basis(trunk, 0.0) * _body.top_shoulder)
			if d < nearest:
				nearest = d
				at = Vector3(0.0, deg_to_rad(elevation), heading)
	_try(trunk, heel, at.x, at.y, at.z, -1.0, out)


# How far down the shaft the bottom hand may hold: as far as a body reaches, or
# with technique, no wider apart than its rule.
func _spacing_max() -> float:
	if not technique:
		return _body.spacing_max
	return minf(_body.spacing_max, _body.top_shoulder.distance_to(_body.bottom_shoulder)
			* ArmTechnique.HANDS_APART_SHOULDERS)


static func _sq(x: float) -> float:
	return x * x

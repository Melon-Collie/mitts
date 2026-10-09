class_name SkaterLegRig
extends RefCounted

# The lower-body skeleton and the gait written onto it.
#
# Both legs are one skinned mesh on the body skeleton, fourteen bones in the
# chain Hips → Leg → Shin (see SkaterMeshBuilder.LegBone). Bone indices here are
# LegBone values; the skeleton holds them past the upper bones, at _OFFSET. Twelve of the bones
# carry geometry; the four pivots exist to be rotated by the gait
# (SkaterSkatingCoordinator).
#
# Pose = basis · scale, at position, each part stored separately: `_basis` is the
# authored rest rotation (constant for the twelve geometry bones; the four pivots
# are rewritten by set_swing), `_scale` and `_pos` are the sizing seam's.
#
# Also the source of the ice VFX's two reads — where a skate is being DRAWN and
# how hard its edge is loaded — because both are properties of this skeleton and
# of nothing else.

const _OFFSET: int = SkaterBodySkeleton.LEG_BONE_OFFSET
# Ice height in the skater's own frame: the origin rides FACEOFF_SPAWN_HEIGHT
# above it (Y-axis locked), so this holds wherever the skater stands — a preview
# placed off the rink included — and the height attribute's scaling about the
# ice plane keeps it a fixed point.
const _ICE_IN_BODY := -GameRules.FACEOFF_SPAWN_HEIGHT
const _RUNNER_TOE := Vector3(0.0, SkaterMeshBuilder.RUNNER_TOE_Y, SkaterMeshBuilder.BLADE_ICE_Z)
const _RUNNER_HEEL := Vector3(0.0, SkaterMeshBuilder.RUNNER_HEEL_Y, SkaterMeshBuilder.BLADE_ICE_Z)
# Per side, index 0 = left: the chain the second-foot plant re-poses.
const _LEG_BONES: Array[int] = [SkaterMeshBuilder.LegBone.LEG_L, SkaterMeshBuilder.LegBone.LEG_R]
const _SHIN_BONES: Array[int] = [SkaterMeshBuilder.LegBone.SHIN_L, SkaterMeshBuilder.LegBone.SHIN_R]
const _FOOT_BONES: Array[int] = [SkaterMeshBuilder.LegBone.FOOT_L, SkaterMeshBuilder.LegBone.FOOT_R]
# Below this a planted runner already meets the support blade, metres.
const _PLANT_SLACK_M: float = 0.0005
# The deepest knee fold the support leg may sit to, radians — past a right
# angle, short of the thigh meeting the calf.
const _PLANT_FOLD_LIMIT_RAD: float = 2.2
# The plant's first knee step, radians. The runner's lowest point is a tip of a
# blade that tilts with the shin (the ankle is rigid outside the held poses), so
# height is not monotone in the knee; the solve walks out from the gait pose in
# steps that start this small rather than sampling the whole range.
const _PLANT_STEP_RAD: float = 0.05
# Steps the walk may take: doubling from _PLANT_STEP_RAD, enough to cross the
# whole knee range.
const _PLANT_WALK_STEPS: int = 7
# How fast the plant's knee change may move, radians per second. The right
# answer itself jumps — the support hands from one foot to the other as a
# stop's hips turn across, and a reaching leg finds the ice past the hump its
# blade's tilt makes — so the correction eases rather than popping a leg. Well
# above the stroke's own knee speeds (the stride's thigh peaks near 2 rad/s), so
# it binds only on those jumps.
const _PLANT_RATE_RAD_S: float = 8.0

var _skater: Skater
var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _basis: Array[Basis] = []
var _scale: PackedVector3Array = PackedVector3Array()
var _pos: PackedVector3Array = PackedVector3Array()
# The scene's authored shin euler, kept so the knee write can preserve its Y/Z
# the way a node's `rotation.x = v` did. Index 0 = left, 1 = right.
var _shin_base_euler: PackedVector3Array = PackedVector3Array()
# True while the skate bones carry an ankle angle, so set_ankle_flatten knows it
# still owes one write to put them back (see there).
var _ankles_posed: bool = false
# The ankle weights the gait last asked for (set_ankle_flatten).
var _ankle_l: float = 0.0
var _ankle_r: float = 0.0
# The bounds of a skate's two assemblies, in their bones' frames: the boot
# (shell, holder, runner) on FOOT, the cuff on SKATE.
var _skate_boxes: Array[AABB] = []
# Untouched baselines the sizing seam multiplies against, captured off the scene
# subtree before it is freed.
var _base_scale: PackedVector3Array = PackedVector3Array()
var _base_pos: PackedVector3Array = PackedVector3Array()

# Last gait-authored leg pose (hip pivot euler (pitch, yaw, roll) + knee fold
# per leg), cached so the knockdown sprawl can compose ON TOP of whatever the
# gait wrote this frame instead of guessing it: the gait's own crumple blend
# keeps easing underneath the overlay through the get-up, so the handoff back
# to the live stride stays continuous at both ends.
var _gait_leg_l: Vector3 = Vector3.ZERO
var _gait_leg_r: Vector3 = Vector3.ZERO
var _gait_knee_l: float = 0.0
var _gait_knee_r: float = 0.0

# Per-blade edge load [0, 1], published by the gait each pose pass (push
# extension, carve under-push, hockey-stop scrape): the ice VFX scale mark
# intensity by it, so a loaded edge bites visibly harder than a glide.
var _edge_load_l: float = 0.0
var _edge_load_r: float = 0.0

# Bumped on every leg bone write, so a reader that solves against the legs
# (the spine's contact seat) can tell its cached answer went stale. The seat's
# own writes do not bump it: they are a function of what it already tracks.
var pose_version: int = 0

# How much the gait holds each foot on the ice rather than leaving it where the
# joints put it, 0..1 (set_contact). Index 0 = left.
var _plant := PackedFloat32Array([1.0, 1.0])
# The render time the plant's correction may move by before the next seat, s;
# spent by the first seat after set_contact, INF to snap.
var _plant_dt: float = INF
# The correction the plant is easing, per side, radians of knee from the gait.
var _plant_eased := PackedFloat32Array([0.0, 0.0])
# True from the knockdown sprawl's write until the gait's next one: the sprawl
# owns the legs, and the seat must not re-pose them under it.
var _sprawled: bool = false
# The knee extension the seat last wrote per side, and the pose_version it wrote
# over, so an unchanged answer costs no bone writes.
var _seat_ext := PackedFloat32Array([0.0, 0.0])
var _seat_version: int = -1
# _plant_feet's answer, per side.
var _plant_ext := PackedFloat32Array([0.0, 0.0])
# The fore-aft compensation GaitPose.solve_knees counter-pitches a knee change
# by — shin over leg, from this rig's own segment offsets.
var _shin_frac: float = 0.0


func setup(skater: Skater) -> void:
	_skater = skater


# Reads the leg segment offsets out of the scene's LowerBody subtree, seeds the
# body skeleton's leg bones from them, then frees the subtree.
#
# Reading the scene rather than hard-coding the offsets keeps Scenes/Skater.tscn
# the place leg proportions are authored — the nodes are still what you edit to
# move a knee, they just stop existing at runtime. Hard-coding them here would
# fork the numbers into two files that no test compares.
func build(skeleton: Skeleton3D) -> void:
	var count: int = SkaterMeshBuilder.LEG_BONE_COUNT
	var lower_body: Node3D = _skater.lower_body
	_basis.resize(count)
	_scale.resize(count)
	_pos.resize(count)
	_base_scale.resize(count)
	_base_pos.resize(count)
	_shin_base_euler.resize(2)

	_skeleton = skeleton
	for bone: int in count:
		var node: Node3D = lower_body.get_node(
				SkaterMeshBuilder.LEG_BONE_NODE[bone]) as Node3D
		var xform: Transform3D = node.transform
		var part_scale: Vector3 = xform.basis.get_scale()
		_basis[bone] = xform.basis.orthonormalized()
		_scale[bone] = part_scale
		_pos[bone] = xform.origin
		_base_scale[bone] = part_scale
		_base_pos[bone] = xform.origin
	_shin_base_euler[0] = _basis[SkaterMeshBuilder.LegBone.SHIN_L].get_euler()
	var thigh_len: float = -_base_pos[SkaterMeshBuilder.LegBone.SHIN_L].y
	var shin_len: float = -_base_pos[SkaterMeshBuilder.LegBone.FOOT_L].y
	_shin_frac = shin_len / (thigh_len + shin_len)
	_shin_base_euler[1] = _basis[SkaterMeshBuilder.LegBone.SHIN_R].get_euler()

	for bone: int in count:
		_repose_bone(bone)
	# Freed only after every offset is read — the whole point of the subtree.
	# free() rather than queue_free(): a deferred free renders the scene's
	# placeholder primitives through the real legs for the frame it waits. Safe
	# here — these are plain children whose _ready has run, and nothing is
	# iterating the subtree.
	lower_body.get_node("LegL").free()
	lower_body.get_node("LegR").free()

	_skate_boxes = [SkaterMeshBuilder.shared_boot_assembly().get_aabb(),
			SkaterMeshBuilder.shared_skate_assembly().get_aabb()]
	_mesh = MeshInstance3D.new()
	_mesh.name = "LegMesh"
	_mesh.mesh = SkaterMeshBuilder.shared_leg_skin_mesh()
	_mesh.skin = SkaterMeshBuilder.shared_leg_skin()
	_mesh.skeleton = NodePath("..")
	_skeleton.add_child(_mesh)


func _repose_bone(bone: int) -> void:
	pose_version += 1
	_skeleton.set_bone_pose(_OFFSET + bone, Transform3D(
			_basis[bone].scaled_local(_scale[bone]), _pos[bone]))


# ── Gait ─────────────────────────────────────────────────────────────────────

# Hip pitch/roll and knee bend, straight onto the four pivot bones. All radians:
# pitch = fore/aft swing (local X) and roll = side-to-side splay (local Z) of the
# whole leg about the hip; knee = flex of the lower leg (local X) about the knee.
#
# The pivots carry no scale and their authored rotation is overwritten outright,
# so the pose is the gait's basis over the sizing seam's position. The knee write
# owns X only — `_shin_base_euler` carries the scene's authored Y/Z into the
# composed basis.
func set_swing(left_pitch: float, left_roll: float, left_knee: float,
		right_pitch: float, right_roll: float, right_knee: float,
		left_yaw: float = 0.0, right_yaw: float = 0.0) -> void:
	var base_l: Vector3 = _shin_base_euler[0]
	var base_r: Vector3 = _shin_base_euler[1]
	_gait_leg_l = Vector3(left_pitch, left_yaw, left_roll)
	_gait_leg_r = Vector3(right_pitch, right_yaw, right_roll)
	_gait_knee_l = left_knee
	_gait_knee_r = right_knee
	_sprawled = false
	# Yaw rides the hip pivot's free Y slot: YXZ euler order puts it outermost,
	# so the leg externally rotates about vertical and the shin + boot carry it
	# — the mohawk open hip. Defaults keep the pre-yaw callers unchanged.
	_pose_pivot(SkaterMeshBuilder.LegBone.LEG_L,
			Vector3(left_pitch, left_yaw, left_roll))
	_pose_pivot(SkaterMeshBuilder.LegBone.SHIN_L,
			Vector3(left_knee, base_l.y, base_l.z))
	_pose_pivot(SkaterMeshBuilder.LegBone.LEG_R,
			Vector3(right_pitch, right_yaw, right_roll))
	_pose_pivot(SkaterMeshBuilder.LegBone.SHIN_R,
			Vector3(right_knee, base_r.y, base_r.z))


# Knockdown leg sprawl: re-poses the leg pivots as the cached gait pose plus the
# sprawl overlay, which arrives already eased (SkaterController
# ._apply_knockdown_fall calls this after the gait and the tilt, only while a
# skater is down). `weight` is the down pose's share, which the ankles hold by.
func apply_knockdown_overlay(pose: KnockdownFallRules.SprawlPose,
		weight: float) -> void:
	if weight <= 0.001:
		return
	_sprawled = true
	var base_l: Vector3 = _shin_base_euler[0]
	var base_r: Vector3 = _shin_base_euler[1]
	var leg_l: Vector3 = _gait_leg_l + Vector3(pose.l_pitch, 0.0, pose.l_roll)
	var leg_r: Vector3 = _gait_leg_r + Vector3(pose.r_pitch, 0.0, pose.r_roll)
	var knee_l: float = _gait_knee_l + pose.l_knee
	var knee_r: float = _gait_knee_r + pose.r_knee
	_pose_pivot(SkaterMeshBuilder.LegBone.LEG_L, leg_l)
	_pose_pivot(SkaterMeshBuilder.LegBone.SHIN_L, Vector3(knee_l, base_l.y, base_l.z))
	_pose_pivot(SkaterMeshBuilder.LegBone.LEG_R, leg_r)
	_pose_pivot(SkaterMeshBuilder.LegBone.SHIN_R, Vector3(knee_r, base_r.y, base_r.z))
	# The ankles give the buckle back as they do any deep sit: a shin folded
	# back by it otherwise drives the toe into the ice.
	_pose_foot(SkaterMeshBuilder.LegBone.FOOT_L, leg_l, knee_l, base_l,
			lerpf(_ankle_l, 1.0, weight))
	_pose_foot(SkaterMeshBuilder.LegBone.FOOT_R, leg_r, knee_r, base_r,
			lerpf(_ankle_r, 1.0, weight))
	_ankles_posed = true
	_rest_on_ice(SkaterMeshBuilder.LegBone.LEG_L, SkaterMeshBuilder.LegBone.FOOT_L,
			SkaterMeshBuilder.LegBone.SKATE_L)
	_rest_on_ice(SkaterMeshBuilder.LegBone.LEG_R, SkaterMeshBuilder.LegBone.FOOT_R,
			SkaterMeshBuilder.LegBone.SKATE_R)


# The ice holds a downed leg up. Tipping the body puts the skates wherever the
# hips carry them — under the ice on the side it falls toward, and wherever the
# sprawl flings them — so a leg whose skate ends up below swings about its hip,
# toward up, until the skate rests on the ice: the leg the body tips over stays
# planted, and a leg lying on the ice lies on it. Reads the MeshRoot tilt the
# fall wrote this frame (Skater.set_knockdown_fall runs first). A few passes,
# because the swing can hand the lowest point to another corner of the skate.
# Works in MeshRoot's parent frame, the skater's own, where the ice is flat at
# −global_position.y.
func _rest_on_ice(leg: int, foot: int, skate: int) -> void:
	var to_body: Transform3D = _skater.mesh_root.transform * _skeleton.transform
	var ice: float = -_skater.global_position.y
	for _pass: int in 4:
		var hip: Vector3 = to_body * _skeleton.get_bone_global_pose(_OFFSET + leg).origin
		var low: Vector3 = _lowest_corner(to_body, foot, skate)
		var sink: float = ice - low.y
		if sink <= 0.0:
			return
		var r: Vector3 = low - hip
		var r_h := Vector2(r.x, r.z)
		var reach: float = r.length()
		if r_h.length() < 0.01 or reach < 0.01:
			return
		# Swing r in the vertical plane through it until it is `sink` higher:
		# its height is reach·sin(φ + β), β its current elevation.
		var beta: float = atan2(r.y, r_h.length())
		var phi: float = asin(clampf((r.y + sink) / reach, -1.0, 1.0)) - beta
		var axis_body: Vector3 = r.cross(Vector3.UP).normalized()
		var axis: Vector3 = (to_body.basis * _skeleton.get_bone_global_pose(
				_skeleton.get_bone_parent(_OFFSET + leg)).basis).inverse() * axis_body
		var pose: Transform3D = _skeleton.get_bone_pose(_OFFSET + leg)
		pose_version += 1
		_skeleton.set_bone_pose(_OFFSET + leg, Transform3D(
				Basis(axis.normalized(), phi) * pose.basis, pose.origin))


# The lowest corner of a skate's two boxes — the boot on `foot`, the cuff on
# `skate` — in `to_body`'s space. Corners rather than vertices: a downed skater
# runs this every frame, and a corner only ever errs high.
func _lowest_corner(to_body: Transform3D, foot: int, skate: int) -> Vector3:
	var lowest := Vector3(0.0, INF, 0.0)
	for i: int in 2:
		var part: Transform3D = to_body * _skeleton.get_bone_global_pose(
				_OFFSET + (foot if i == 0 else skate))
		var box: AABB = _skate_boxes[i]
		for corner: int in 8:
			var p: Vector3 = part * box.get_endpoint(corner)
			if p.y < lowest.y:
				lowest = p
	return lowest


func _pose_pivot(bone: int, euler: Vector3) -> void:
	pose_version += 1
	_skeleton.set_bone_pose(_OFFSET + bone, Transform3D(Basis.from_euler(euler), _pos[bone]))


# Levels a skate against everything the leg above it did: `weight` of the hip's
# splay and the knee's fold unwound at the ankle, that leg's yaw kept. The boot
# hangs off the end of the shin and inherits the whole chain, so a leg rolled far
# out of vertical — the shot block's extended leg — swings its blade up onto an
# edge and clear of the ice, and a shin folded far back — the faceoff centre's
# deep sit — stands it on its heel. A real ankle gives that back, which is what
# lets a player hold either pose on a flat blade.
#
# Stated as a weight rather than two angles because two angles cannot undo this
# chain: the splay is taken at the hip, ahead of a knee fold that can pass 90°,
# so by the time it reaches the boot it is no longer a roll about anything the
# ankle owns. The give-back is the chain's own rotation inverted, which is exact
# at any depth — and needs nothing passed in, since set_swing just wrote it.
#
# Unlike the pivots this bone carries an authored rotation and the sizing seam's
# scale, so the give-back composes onto the rest basis rather than replacing it.
# Skipped while both ankles are square (and once more to settle back), so the
# common case adds no writes to the render-rate rig pass.
func set_ankle_flatten(left: float, right: float) -> void:
	_ankle_l = left
	_ankle_r = right
	var square: bool = is_zero_approx(left) and is_zero_approx(right)
	if square and not _ankles_posed:
		return
	_ankles_posed = not square
	_pose_foot(SkaterMeshBuilder.LegBone.FOOT_L, _gait_leg_l, _gait_knee_l,
			_shin_base_euler[0], left)
	_pose_foot(SkaterMeshBuilder.LegBone.FOOT_R, _gait_leg_r, _gait_knee_r,
			_shin_base_euler[1], right)


func _pose_foot(bone: int, leg: Vector3, knee: float, shin_base: Vector3,
		weight: float) -> void:
	pose_version += 1
	_skeleton.set_bone_pose(_OFFSET + bone, _foot_pose(bone, leg, knee, shin_base, weight))


func _foot_pose(bone: int, leg: Vector3, knee: float, shin_base: Vector3,
		weight: float) -> Transform3D:
	if weight <= 0.0:
		return Transform3D(_basis[bone].scaled_local(_scale[bone]), _pos[bone])
	# What the chain did to this boot, and what it would have done carrying the
	# leg's yaw alone. Their difference, in the boot's own frame, is the ankle's
	# give-back; the slerp eases it in from square.
	var shin: Basis = Basis.from_euler(Vector3(knee, shin_base.y, shin_base.z))
	var posed: Basis = Basis.from_euler(leg) * shin
	var level: Basis = Basis.from_euler(Vector3(0.0, leg.y, 0.0)) \
			* Basis.from_euler(Vector3(0.0, shin_base.y, shin_base.z))
	var give_back: Basis = (posed.inverse() * level).orthonormalized()
	var basis: Basis = Basis.IDENTITY.slerp(give_back, weight) * _basis[bone]
	return Transform3D(basis.scaled_local(_scale[bone]), _pos[bone])


# ── Ice contact ──────────────────────────────────────────────────────────────

# The gait's ask of each foot (_plant), and the render time since its last ask,
# read by the next seat; INF snaps the correction (a reset or a teleport).
func set_contact(plant_l: float, plant_r: float, dt: float) -> void:
	_plant[0] = plant_l
	_plant[1] = plant_r
	_plant_dt = dt


# Stands the legs on the ice for the HIPS bone at `hips` (its parent is the
# skeleton root), and returns the skeleton-space translation of the hips that
# seats the lower runner on it. The gait poses joints, not feet, and the crouch
# it pays as a drop covers the stance alone — the push's extension, the splay,
# the stagger, the tucks and the lean each move the blades too — so the body is
# placed from where the blades actually are.
#
# Both feet first (_plant_feet): the higher runner's knee is re-solved (the
# thigh counter-pitched as GaitPose.solve_knees does, so the foot keeps its
# fore-aft place) until it meets the lower one, by the gait's plant weight —
# the two-footed stances, not the stride, whose push and recovery are the
# stroke's own. Neither leg's re-solve moves the hips, so this is independent of
# where they end up, and the seat after it is exact in one step.
#
# Reads only local bone poses, so it never forces the skeleton's global pose
# update mid-frame.
func seat_on_ice(hips: Transform3D) -> Vector3:
	var to_body: Transform3D = _skater.mesh_root.transform * _skeleton.transform
	var hips_body: Transform3D = to_body * hips
	var ground: float
	if _sprawled:
		ground = minf(_runner_low(hips_body, 0), _runner_low(hips_body, 1))
	else:
		_plant_feet(hips_body)
		var reach: float = _PLANT_RATE_RAD_S * _plant_dt
		_plant_dt = 0.0
		for side: int in 2:
			_plant_eased[side] = move_toward(_plant_eased[side], _plant_ext[side], reach)
			_write_seat(side, _plant_eased[side])
		_seat_version = pose_version
		ground = minf(_chain_low(hips_body, 0, _plant_eased[0]),
				_chain_low(hips_body, 1, _plant_eased[1]))
	return to_body.basis.inverse() * Vector3(0.0, _ICE_IN_BODY - ground, 0.0)


# Fills _plant_ext with each leg's knee extension from the gait pose. The lower
# runner
# is the support; the other is brought down to it, and where it cannot reach
# that far, the support folds to meet it — a skater sits deeper on the back leg
# to get a braced front blade onto the ice.
func _plant_feet(hips_body: Transform3D) -> void:
	_plant_ext[0] = 0.0
	_plant_ext[1] = 0.0
	var h_l: float = _chain_low(hips_body, 0, 0.0)
	var h_r: float = _chain_low(hips_body, 1, 0.0)
	var sup: int = 0 if h_l <= h_r else 1
	var other: int = 1 - sup
	var h_sup: float = minf(h_l, h_r)
	var h_other: float = maxf(h_l, h_r)
	if _plant[other] <= 0.0 or h_other - h_sup <= _PLANT_SLACK_M:
		return
	var e_other: float = _solve_knee(hips_body, other, h_sup, h_other, 1.0)
	var reached: float = _chain_low(hips_body, other, e_other)
	var e_sup: float = 0.0
	if reached - h_sup > _PLANT_SLACK_M:
		e_sup = _solve_knee(hips_body, sup, reached, h_sup, -1.0)
	_plant_ext[other] = e_other * _plant[other]
	_plant_ext[sup] = e_sup * _plant[sup]


# The knee change from the gait pose, in direction `dir` (+1 extends, −1
# folds), that puts this side's runner at `target` (`h_start` is its height at
# the gait's own knee): the crossing NEAREST the gait pose, because the gait
# pose moves smoothly and so does that root, where a farther one can appear and
# vanish between frames and pop the leg. Walks out in steps that double, to the
# first crossing (then refines the bracket) or the end of the knee's range
# (then the closest point it passed, interpolated). It does not stop at the
# first step that does worse: the blade's tilt dips the height before the
# leg's length takes over.
func _solve_knee(hips_body: Transform3D, side: int, target: float, h_start: float,
		dir: float) -> float:
	var knee: float = _gait_knee_l if side == 0 else _gait_knee_r
	var bound: float = maxf(-knee, 0.0) if dir > 0.0 \
			else minf(-_PLANT_FOLD_LIMIT_RAD - knee, 0.0)
	var best_e: float = 0.0
	var best_err: float = absf(h_start - target)
	var best_i: int = 0
	var es := PackedFloat32Array([0.0])
	var hs := PackedFloat32Array([h_start])
	var step: float = _PLANT_STEP_RAD
	var e: float = 0.0
	while e != bound and es.size() < _PLANT_WALK_STEPS:
		e = clampf(e + dir * step, minf(bound, 0.0), maxf(bound, 0.0))
		var h: float = _chain_low(hips_body, side, e)
		var prev_e: float = es[es.size() - 1]
		var prev_h: float = hs[hs.size() - 1]
		if (prev_h - target) * (h - target) <= 0.0:
			return _refine(hips_body, side, target, prev_e, prev_h, e, h)
		es.append(e)
		hs.append(h)
		if absf(h - target) < best_err:
			best_err = absf(h - target)
			best_e = e
			best_i = es.size() - 1
		step *= 2.0
	if best_i <= 0 or best_i >= es.size() - 1:
		return best_e
	# Placing the closest point on the walk's own lattice would hop the knee a
	# step at a time as the pose moves, so it is interpolated.
	return _extremum(hips_body, side, target, es[best_i - 1], hs[best_i - 1],
			best_e, hs[best_i], es[best_i + 1], hs[best_i + 1])


# The knee nearest `target` between a and c, given b closer than both: the
# vertex of the parabola through the three, if it does better than b.
func _extremum(hips_body: Transform3D, side: int, target: float, a: float, h_a: float,
		b: float, h_b: float, c: float, h_c: float) -> float:
	var den: float = (b - a) * (h_b - h_c) - (b - c) * (h_b - h_a)
	if is_zero_approx(den):
		return b
	var v: float = b - 0.5 * ((b - a) * (b - a) * (h_b - h_c)
			- (b - c) * (b - c) * (h_b - h_a)) / den
	v = clampf(v, minf(a, c), maxf(a, c))
	var h_v: float = _chain_low(hips_body, side, v)
	return v if absf(h_v - target) < absf(h_b - target) else b


# Secant steps inside a bracket [a, b] around `target`, kept bracketed.
func _refine(hips_body: Transform3D, side: int, target: float,
		a: float, h_a: float, b: float, h_b: float) -> float:
	for _step: int in 4:
		if is_equal_approx(h_a, h_b):
			break
		var e: float = a + (target - h_a) * (b - a) / (h_b - h_a)
		var h: float = _chain_low(hips_body, side, e)
		if absf(h - target) < _PLANT_SLACK_M:
			return e
		if (h_a - target) * (h - target) <= 0.0:
			b = e
			h_b = h
		else:
			a = e
			h_a = h
	return b if absf(h_b - target) < absf(h_a - target) else a


# The gait's leg on `side` with its knee extended by `ext` and the thigh
# counter-pitched, as hip-local FOOT, from the cached gait pose.
func _chain(side: int, ext: float) -> Transform3D:
	var leg: Vector3 = (_gait_leg_l if side == 0 else _gait_leg_r) \
			- Vector3(ext * _shin_frac, 0.0, 0.0)
	var knee: float = (_gait_knee_l if side == 0 else _gait_knee_r) + ext
	var base: Vector3 = _shin_base_euler[side]
	var shin_bone: int = _SHIN_BONES[side]
	return Transform3D(Basis.from_euler(leg), _pos[_LEG_BONES[side]]) \
			* Transform3D(Basis.from_euler(Vector3(knee, base.y, base.z)), _pos[shin_bone]) \
			* _foot_pose(_FOOT_BONES[side], leg, knee, base, _ankle_l if side == 0 else _ankle_r)


func _chain_low(hips_body: Transform3D, side: int, ext: float) -> float:
	var boot: Transform3D = hips_body * _chain(side, ext)
	return minf((boot * _RUNNER_TOE).y, (boot * _RUNNER_HEEL).y)


# The lowest runner point as the bones stand, for a pose the seat did not make.
func _runner_low(hips_body: Transform3D, side: int) -> float:
	var boot: Transform3D = hips_body * _skeleton.get_bone_pose(_OFFSET + _LEG_BONES[side]) \
			* _skeleton.get_bone_pose(_OFFSET + _SHIN_BONES[side]) \
			* _skeleton.get_bone_pose(_OFFSET + _FOOT_BONES[side])
	return minf((boot * _RUNNER_TOE).y, (boot * _RUNNER_HEEL).y)


# Poses one leg at the gait's pose extended by `ext`. A gait write since the last
# seat left the bones at ext 0; otherwise they hold the last seat's.
func _write_seat(side: int, ext: float) -> void:
	var held: float = 0.0 if pose_version != _seat_version else _seat_ext[side]
	_seat_ext[side] = ext
	if ext == held:
		return
	var leg: Vector3 = (_gait_leg_l if side == 0 else _gait_leg_r) \
			- Vector3(ext * _shin_frac, 0.0, 0.0)
	var knee: float = (_gait_knee_l if side == 0 else _gait_knee_r) + ext
	var base: Vector3 = _shin_base_euler[side]
	var leg_bone: int = _LEG_BONES[side]
	var shin_bone: int = _SHIN_BONES[side]
	var foot_bone: int = _FOOT_BONES[side]
	_skeleton.set_bone_pose(_OFFSET + leg_bone,
			Transform3D(Basis.from_euler(leg), _pos[leg_bone]))
	_skeleton.set_bone_pose(_OFFSET + shin_bone,
			Transform3D(Basis.from_euler(Vector3(knee, base.y, base.z)), _pos[shin_bone]))
	_skeleton.set_bone_pose(_OFFSET + foot_bone,
			_foot_pose(foot_bone, leg, knee, base, _ankle_l if side == 0 else _ankle_r))


# ── Ice VFX seams ────────────────────────────────────────────────────────────

func set_edge_loads(left: float, right: float) -> void:
	_edge_load_l = left
	_edge_load_r = right


func edge_load(left: bool) -> float:
	return _edge_load_l if left else _edge_load_r


# World position of a FOOT bone, composed through everything the gait wrote —
# lower-body yaw (alignment / pivot / stop), stride pitch, the mohawk yaw — so
# ice marks made from here follow the SKATES, not the torso. Falls back to the
# old body-center offset until the rig is built.
#
# The transform half is read INTERPOLATED, the bone pose half as-is: the body
# renders between tick poses, while the bone pose is whatever the render-rate
# gait wrote this frame. Composing the two gives the drawn body carrying the
# drawn foot; a plain global_transform read lays every stroke up to a tick of
# travel ahead of the skate that cut it.
func mark_position(left: bool) -> Vector3:
	if _skeleton == null:
		var t: Transform3D = _skater.get_global_transform_interpolated()
		return t.origin + t.basis.x * (-0.12 if left else 0.12)
	var bone: int = SkaterMeshBuilder.LegBone.FOOT_L if left \
			else SkaterMeshBuilder.LegBone.FOOT_R
	return (_skeleton.get_global_transform_interpolated()
			* _skeleton.get_bone_global_pose(_OFFSET + bone)).origin


# ── Sizing seam ──────────────────────────────────────────────────────────────
# Scale and position are applied in separate passes by
# SkaterAppearanceCoordinator (a part can take one, the other, or both), so each
# setter writes its own component and recomposes. Attribute-apply rate, not per
# frame.
func set_bone_scale(bone: int, part_scale: Vector3) -> void:
	_scale[bone] = part_scale
	_repose_bone(bone)


func set_bone_position(bone: int, pos: Vector3) -> void:
	_pos[bone] = pos
	_repose_bone(bone)


# Read seams for the gait tests: the rotation the gait wrote and the position the
# sizing seam wrote. The euler round-trips exactly for the four pivots, whose
# basis is built from one (set_swing).
func bone_euler(bone: int) -> Vector3:
	return _skeleton.get_bone_pose(_OFFSET + bone).basis.get_euler()


func bone_position(bone: int) -> Vector3:
	return _skeleton.get_bone_pose(_OFFSET + bone).origin


func bone_base_scale(bone: int) -> Vector3:
	return _base_scale[bone]


func bone_base_position(bone: int) -> Vector3:
	return _base_pos[bone]


func surface_material(surface: int) -> StandardMaterial3D:
	return SkaterMeshBuilder.surface_override(_mesh, surface)


func set_surface_material(surface: int, mat: Material) -> void:
	_mesh.set_surface_override_material(surface, mat)

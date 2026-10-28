extends GutTest

# With the elbow down, the shoulder's outline seen from behind runs from the
# neck down over the shoulder and on down the arm (SkaterMeshBuilder._sleeve).
# It must not rise into a peak and fall away again — a tent over the joint,
# which a sleeve ring above the pivot makes when the arm turns it up past the
# torso's shoulder line. A raised arm stands up out of that outline by rights,
# so only arms whose elbow is below the shoulder are read.

const UpperBone = SkaterMeshBuilder.UpperBone
const UpperSurface = SkaterMeshBuilder.UpperSurface
const CASES: int = 120
const SEED: int = 0x54454E54  # "TENT"
const _SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
# A peak smaller than this is a facet's own kink, not a tent.
const _PEAK_TOLERANCE_M: float = 0.005
# The outline is read this far either side of the shoulder's pivot, across.
const _WINDOW_M: float = 0.12
const _BIN_M: float = 0.005
# How far under the shoulder's pivot the elbow must be for its arm to be read.
const _ELBOW_DOWN_M: float = 0.10
# Per side (left, right): the cap bone and the sleeve's surfaces near the joint.
const _SIDES: Array = [
	[UpperBone.SHOULDER_L, [UpperSurface.SHOULDER_L, UpperSurface.TOP_UPPER_ARM]],
	[UpperBone.SHOULDER_R, [UpperSurface.SHOULDER_R, UpperSurface.BOTTOM_UPPER_ARM]],
]
# The elbow bones per side, either way round the handedness puts the arms.
const _ELBOWS: Array[int] = [UpperBone.TOP_ELBOW, UpperBone.BOTTOM_ELBOW]

var _rng := RandomNumberGenerator.new()


func test_the_shoulder_has_no_peak() -> void:
	_rng.seed = SEED
	var sk: Skater = _SKATER_SCENE.instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	sk.set_process(false)
	sk.set_physics_process(false)
	var rig: SkaterArmRig = sk._arms
	var top: Vector3 = sk.top_hand.position
	var bottom: Vector3 = sk.bottom_hand.position
	var mesh: ArrayMesh = SkaterMeshBuilder.shared_upper_skin_mesh()
	var paths: Array[bool] = [false]
	if ClassDB.class_exists(&"NativeArmRig"):
		paths.append(true)
	var worst: float = 0.0
	var worst_case: String = ""
	var read: int = 0
	for i: int in CASES:
		sk.set_top_hand_position(top + Vector3(_rng.randf_range(-0.6, 0.6),
				_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6)))
		sk.set_bottom_hand_position(bottom + Vector3(_rng.randf_range(-0.6, 0.6),
				_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6)))
		sk.update_stick_mesh()
		sk._spine.update()
		for native: bool in paths:
			rig.native_enabled = native
			rig.update_top_arm()
			rig.update_bottom_arm()
			for side_i: int in 2:
				if not _elbow_down(rig, side_i):
					continue
				read += 1
				var peak: float = _peak(rig, mesh, side_i)
				if peak > worst:
					worst = peak
					worst_case = "case %d side %d %s" % [i, side_i,
							"native" if native else "gdscript"]
	gut.p("shoulder outline: worst peak %.4f m (%s) over %d arms" % [worst, worst_case, read])
	assert_gt(read, CASES / 2, "enough arms hang to read")
	assert_lt(worst, _PEAK_TOLERANCE_M, "the shoulder rises into a tent: %s" % worst_case)


# Whether the side's elbow, whichever arm is on that side, is well under its
# shoulder's pivot.
func _elbow_down(rig: SkaterArmRig, side_i: int) -> bool:
	var body: Skeleton3D = rig._skeleton
	var spine_inv: Transform3D = body.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE) \
			.affine_inverse()
	var pivot: Vector3 = spine_inv * body.get_bone_global_pose(_SIDES[side_i][0]).origin
	for elbow_bone: int in _ELBOWS:
		var elbow: Vector3 = spine_inv * body.get_bone_global_pose(elbow_bone).origin
		if signf(elbow.x) == signf(pivot.x):
			return elbow.y < pivot.y - _ELBOW_DOWN_M
	return false


# The largest prominence of a peak inside the outline's window: how far it
# stands above the higher of the lowest points either side of it.
func _peak(rig: SkaterArmRig, mesh: ArrayMesh, side_i: int) -> float:
	var outline: PackedFloat32Array = _outline(rig, mesh, side_i)
	var worst: float = 0.0
	for b: int in range(1, outline.size() - 1):
		if is_inf(outline[b]):
			continue
		var left: float = INF
		for a: int in b:
			left = minf(left, outline[a])
		var right: float = INF
		for c: int in range(b + 1, outline.size()):
			right = minf(right, outline[c])
		if is_inf(left) or is_inf(right):
			continue
		worst = maxf(worst, outline[b] - maxf(left, right))
	return worst


# The highest point of the torso and the side's sleeve near the joint, per bin
# across (outward from the spine), in the spine's frame; −INF where empty.
func _outline(rig: SkaterArmRig, mesh: ArrayMesh, side_i: int) -> PackedFloat32Array:
	var body: Skeleton3D = rig._skeleton
	var skin: Skin = rig._mesh.skin
	var spine_inv: Transform3D = body.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE) \
			.affine_inverse()
	var side: float = -1.0 if side_i == 0 else 1.0
	var pivot: Vector3 = spine_inv * body.get_bone_global_pose(_SIDES[side_i][0]).origin
	var bins: int = int(2.0 * _WINDOW_M / _BIN_M)
	var outline := PackedFloat32Array()
	outline.resize(bins)
	outline.fill(-INF)
	var binds: Array[Transform3D] = []
	for b: int in skin.get_bind_count():
		binds.append(spine_inv * body.get_bone_global_pose(skin.get_bind_bone(b))
				* skin.get_bind_pose(b))
	var surfaces: Array = [UpperSurface.TORSO]
	surfaces.append_array(_SIDES[side_i][1])
	for surface: int in surfaces:
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var posed := PackedVector3Array()
		posed.resize(verts.size())
		for v: int in verts.size():
			var p := Vector3.ZERO
			for j: int in 4:
				var w: float = weights[v * 4 + j]
				if w > 0.0:
					p += (binds[bones[v * 4 + j]] * verts[v]) * w
			posed[v] = p
		# A face's outline is its edges', and an edge's highest point within a bin
		# is at one end of the piece of it the bin holds.
		for t: int in range(0, verts.size(), 3):
			for e: int in 3:
				var a := Vector2((posed[t + e].x - pivot.x) * side + _WINDOW_M,
						posed[t + e].y) / Vector2(_BIN_M, 1.0)
				var b := Vector2((posed[t + (e + 1) % 3].x - pivot.x) * side + _WINDOW_M,
						posed[t + (e + 1) % 3].y) / Vector2(_BIN_M, 1.0)
				if a.x > b.x:
					var swap: Vector2 = a
					a = b
					b = swap
				for bin: int in range(maxi(int(floorf(a.x)), 0), mini(int(floorf(b.x)), bins - 1) + 1):
					for x: float in [clampf(float(bin), a.x, b.x), clampf(float(bin + 1), a.x, b.x)]:
						var f: float = 0.0 if b.x - a.x < 1e-9 else (x - a.x) / (b.x - a.x)
						outline[bin] = maxf(outline[bin], lerpf(a.y, b.y, f))
	for b: int in bins:
		if outline[b] == -INF:
			outline[b] = INF
	return outline

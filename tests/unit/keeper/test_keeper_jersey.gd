extends GutTest

# The keeper's jersey is one connected skin (KeeperJerseyMesh) on his body rig:
# every corner at a place carries that place's one set of weights, so no seam
# between the body and a sleeve can open under any pose; the sleeves grow out
# of the body; skinned in every taught stance it stays on the save boxes it
# draws over (the chest's and the arms', into the gloves), so what he looks like
# is still what he saves with; its tail's paint runs on from the body's at the
# hem; and a right-catcher wears exactly the left-catcher's reflection.

# How far a skinned vertex may stand off the boxes: the sleeve's cloth over a
# bend, where a blended ring rides between two boxes.
const OFF_BOXES_M: float = 0.02
const _BOXES: Array[int] = [
	KeeperGear.Part.CHEST, KeeperGear.Part.UPPER_ARM_G, KeeperGear.Part.FOREARM_G,
	KeeperGear.Part.UPPER_ARM_B, KeeperGear.Part.FOREARM_B, KeeperGear.Part.GLOVE,
	KeeperGear.Part.BLOCKER,
]

var _keeper: Keeper = null


func before_each() -> void:
	_keeper = Keeper.new()
	add_child_autofree(_keeper)


func _stances() -> Array:
	var out: Array = [
		["upright", func(p: KeeperPose) -> void: KeeperPoses.upright(p)],
		["ready", func(p: KeeperPose) -> void: KeeperPoses.ready(p)],
		["low_ready", func(p: KeeperPose) -> void: KeeperPoses.low_ready(p)],
		["butterfly", func(p: KeeperPose) -> void: KeeperPoses.butterfly(p)],
	]
	for side: float in [-1.0, 1.0]:
		out.append(["half_butterfly %+d" % side,
				func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, side)])
		out.append(["extension %+d" % side,
				func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, side)])
		out.append(["kick %+d" % side, func(p: KeeperPose) -> void: KeeperPoses.kick(p, side)])
		out.append(["rvh %+d" % side, func(p: KeeperPose) -> void: KeeperPoses.rvh(p, side)])
	return out


func _pose(stance: Callable, mirrored: bool) -> void:
	var p := KeeperPose.new()
	stance.call(p)
	_keeper.skeleton.mirrored = mirrored
	_keeper.apply_pose(p)
	_keeper.draw_now()


func _rig() -> KeeperBodyRig:
	return _keeper.find_child("BodyRig", true, false) as KeeperBodyRig


func _is_jersey(zone: float) -> bool:
	var z: int = roundi(zone)
	return z == KeeperJerseyMesh.ZONE_TORSO or z == KeeperJerseyMesh.ZONE_SLEEVE


# The jersey's corners where the skin puts them, his space.
func _skinned() -> PackedVector3Array:
	var rig: KeeperBodyRig = _rig()
	var mi: MeshInstance3D = rig.body_mesh()
	var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var binds: Array[Transform3D] = []
	for i: int in mi.skin.get_bind_count():
		binds.append(rig.get_bone_global_pose(mi.skin.get_bind_bone(i)) * mi.skin.get_bind_pose(i))
	var out := PackedVector3Array()
	for v: int in verts.size():
		if not _is_jersey(zones[v].x):
			continue
		var p := Vector3.ZERO
		for k: int in 4:
			var w: float = weights[v * 4 + k]
			if w > 0.0:
				p += (binds[bones[v * 4 + k]] * verts[v]) * w
		out.append(p)
	return out


func test_every_corner_at_a_place_rides_its_bones_alike() -> void:
	var arrays: Array = KeeperJerseyMesh.shared_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var seen: Dictionary = {}
	var zones_at: Dictionary = {}
	for v: int in verts.size():
		var key: Vector3i = Vector3i((verts[v] * 1e5).round())
		var ride: Array = []
		for k: int in 4:
			if weights[v * 4 + k] > 0.0:
				ride.append([bones[v * 4 + k], snappedf(weights[v * 4 + k], 1e-5)])
		if seen.has(key):
			if seen[key] != ride:
				fail_test("the corners at %s ride %s and %s" % [verts[v], seen[key], ride])
				return
		else:
			seen[key] = ride
		var at: Dictionary = zones_at.get_or_add(key, {})
		at[roundi(zones[v].x)] = true
	var shared: int = 0
	for at: Dictionary in zones_at.values():
		if at.has(KeeperJerseyMesh.ZONE_TORSO) and at.has(KeeperJerseyMesh.ZONE_SLEEVE):
			shared += 1
	assert_eq(shared, 2 * SkaterConnectedMesh.LIMB_SIDES,
			"each sleeve grows out of the body round its whole armhole")


func test_it_stays_on_his_save_boxes_in_every_stance() -> void:
	for mirrored: bool in [false, true]:
		for stance: Array in _stances():
			_pose(stance[1], mirrored)
			var worst: float = 0.0
			for p: Vector3 in _skinned():
				var off: float = INF
				for part: int in _BOXES:
					off = minf(off, _off_box(p, KeeperGear.box(_keeper.skeleton, part),
							KeeperGear.half_extents(part)))
				worst = maxf(worst, off)
			assert_lt(worst, OFF_BOXES_M, "%s%s: furthest off his boxes" % [
					stance[0], " (right-catcher)" if mirrored else ""])


func test_a_right_catcher_wears_its_reflection() -> void:
	for stance: Array in _stances():
		_pose(stance[1], false)
		var left: Dictionary = {}
		for p: Vector3 in _skinned():
			left[Vector3i((p * 1e3).round())] = p
		_pose(stance[1], true)
		var worst: float = 0.0
		for p: Vector3 in _skinned():
			var r := Vector3(-p.x, p.y, p.z)
			var key := Vector3i((r * 1e3).round())
			var best: float = INF
			for dx: int in range(-1, 2):
				for dy: int in range(-1, 2):
					for dz: int in range(-1, 2):
						var near: Variant = left.get(key + Vector3i(dx, dy, dz))
						if near != null:
							best = minf(best, (near as Vector3).distance_to(r))
			worst = maxf(worst, best)
		assert_lt(worst, 1e-4, "%s: each right-catcher corner the reflection of a left-catcher one" % stance[0])


# The seam's corners (where the body and a sleeve meet) in the jersey's own
# mesh, bind space, as indices into `_skinned`'s order.
func _seam() -> PackedInt32Array:
	var arrays: Array = KeeperJerseyMesh.shared_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var in_body: Dictionary = {}
	for v: int in verts.size():
		if roundi(zones[v].x) == KeeperJerseyMesh.ZONE_TORSO:
			in_body[Vector3i((verts[v] * 1e5).round())] = true
	var out := PackedInt32Array()
	for v: int in verts.size():
		if roundi(zones[v].x) == KeeperJerseyMesh.ZONE_SLEEVE \
				and in_body.has(Vector3i((verts[v] * 1e5).round())):
			out.append(v)
	return out


func test_the_armhole_is_no_wider_than_the_chests_side() -> void:
	# Past the side's corners the body's faces beside the seam lie folded under
	# it, and turn inside out as soon as the arm lifts.
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	var side: float = 0.0
	for ring: int in range(KeeperJerseyMesh._ARMHOLE_TOP, KeeperJerseyMesh._ARMHOLE_TOP + 3):
		var pts: PackedVector3Array = KeeperGearMeshes.jersey_ring(h,
				KeeperGearMeshes.JERSEY_STATIONS - 1 - ring, KeeperJerseyMesh.TORSO_PER_EDGE)
		for c: int in [-KeeperJerseyMesh._ARMHOLE_HALF_WIDTH, KeeperJerseyMesh._ARMHOLE_HALF_WIDTH]:
			side = maxf(side, absf(pts[KeeperJerseyMesh._ARMHOLE_COLUMN[1] + c].z))
	var verts: PackedVector3Array = KeeperJerseyMesh.shared_mesh().surface_get_arrays(0) \
			[Mesh.ARRAY_VERTEX]
	var seam: PackedInt32Array = _seam()
	assert_gt(seam.size(), 0)
	for v: int in seam:
		assert_lte(absf(verts[v].z), side + 1e-3, "the seam's corner at %s" % verts[v])


func test_a_raised_arm_leaves_the_armpit_on_the_chest() -> void:
	# The sleeve under the arm hangs from the chest (SleeveHang), so both arms
	# thrown up draw it out from the flank; riding the shoulder instead, the
	# armhole's bottom swings up with the arm.
	var verts: PackedVector3Array = KeeperJerseyMesh.shared_mesh().surface_get_arrays(0) \
			[Mesh.ARRAY_VERTEX]
	var armpits: Array[int] = [-1, -1]
	for v: int in _seam():
		var side: int = 0 if verts[v].x < 0.0 else 1
		if armpits[side] < 0 or verts[v].y < verts[armpits[side]].y:
			armpits[side] = v
	var in_chest: Array[PackedVector3Array] = []
	for raised: bool in [false, true]:
		_pose(func(p: KeeperPose) -> void:
			KeeperPoses.ready(p)
			if raised:
				p.glove_from_chest = false
				p.glove_hand = Vector3(-0.55, 1.80, -0.15)
				p.blocker_reach = true
				p.blocker_grip = Vector3(0.55, 1.80, -0.15), false)
		var to_chest: Transform3D = KeeperGear.box(_keeper.skeleton, KeeperGear.Part.CHEST) \
				.affine_inverse()
		var skinned: PackedVector3Array = _skinned()
		in_chest.append(PackedVector3Array([to_chest * skinned[armpits[0]],
				to_chest * skinned[armpits[1]]]))
	for side: int in 2:
		assert_almost_eq(in_chest[1][side], in_chest[0][side], Vector3.ONE * 0.005,
				"side %d: the armpit, in the chest's frame" % side)


# The tail (KeeperJerseyTail) hangs from the body's hem and wears the same
# decal: where a corner of its top row and one of the body's hem stand at one
# place, both carry one UV, so the kit's bands and the hem's peaks run on
# across the join.
func test_the_tails_paint_runs_on_from_the_hem() -> void:
	_pose(func(p: KeeperPose) -> void: KeeperPoses.ready(p), false)
	var hem_y: float = -KeeperGear.half_extents(KeeperGear.Part.CHEST).y
	var body: Array = KeeperJerseyMesh.shared_mesh().surface_get_arrays(0)
	var body_verts: PackedVector3Array = body[Mesh.ARRAY_VERTEX]
	var body_uvs: PackedVector2Array = body[Mesh.ARRAY_TEX_UV]
	var at_hem: Dictionary = {}
	for v: int in body_verts.size():
		if absf(body_verts[v].y - hem_y) < 1e-5:
			at_hem[Vector3i((body_verts[v] * 1e4).round())] = body_uvs[v]
	var tail: KeeperJerseyTail = _keeper.find_child("JerseyTail", true, false) as KeeperJerseyTail
	var arrays: Array = tail.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var met: int = 0
	for v: int in verts.size():
		var key := Vector3i((verts[v] * 1e4).round())
		if not at_hem.has(key):
			continue
		met += 1
		var uv: Vector2 = at_hem[key]
		assert_almost_eq(wrapf(uvs[v].x - uv.x, -0.5, 0.5), 0.0, 1e-4, "U at %s" % verts[v])
		assert_almost_eq(uvs[v].y, uv.y, 1e-4, "V at %s" % verts[v])
	assert_gt(met, 8, "the tail's top row meets the hem all round")


func test_no_sleeve_samples_its_paint_across_the_wrap() -> void:
	# On V = 0 itself the repeating texture filters the cuff's color into the
	# sleeve's top (SleeveDecal.TOP_V).
	var arrays: Array = KeeperJerseyMesh.shared_mesh().surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var top_v: float = INF
	for v: int in uvs.size():
		if roundi(zones[v].x) == KeeperJerseyMesh.ZONE_SLEEVE:
			top_v = minf(top_v, uvs[v].y)
	assert_gte(top_v, SleeveDecal.TOP_V, "the sleeves' top a texel inside their paint")


# How far `p` lies outside the box (its centre and axes `box`, half sizes `h`).
static func _off_box(p: Vector3, box: Transform3D, h: Vector3) -> float:
	var local: Vector3 = box.affine_inverse() * p
	var out := Vector3(maxf(absf(local.x) - h.x, 0.0), maxf(absf(local.y) - h.y, 0.0),
			maxf(absf(local.z) - h.z, 0.0))
	return out.length()

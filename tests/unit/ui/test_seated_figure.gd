extends GutTest

# A LockerMannequin seated for the lobby bench: thighs flat on the seat, which
# is the figure's origin, feet and stick blade down on one floor, and both
# hands still on the shaft inside their arms' reach.

var _figure: LockerMannequin = null


func _seat(attrs: PlayerAttributes) -> void:
	_figure = LockerMannequin.new()
	_figure.seated = true
	add_child_autofree(_figure)
	_figure.apply(attrs, GearStyleConfig.new(), StickTapeConfig.from_code(
			StickTapeConfig.DEFAULT_CODE), TeamColorRegistry.get_colors(0, 0),
			SkinToneRegistry.DEFAULT_INDEX, false)


func _kit() -> FigureKit:
	return _figure.get("_kit") as FigureKit


# One bone's pose in the figure's own frame.
func _bone(bone: int) -> Transform3D:
	var rig: Node3D = _figure.get("_rig") as Node3D
	return rig.transform * _kit().skeleton.get_bone_global_pose(bone)


func _leg(bone: int) -> Transform3D:
	return _bone(SkaterBodySkeleton.LEG_BONE_OFFSET + bone)


# The lowest point of the skin's pants, skinned as drawn, in the figure's frame.
func _pants_bottom() -> float:
	var skeleton: Skeleton3D = _kit().skeleton
	var skin: Skin = SkaterConnectedMesh.shared_skin()
	var xforms: Array[Transform3D] = []
	for i: int in skin.get_bind_count():
		xforms.append(skeleton.get_bone_global_pose(skin.get_bind_bone(i)) * skin.get_bind_pose(i))
	var arrays: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE) \
			.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var pants: Array[int] = [SkaterMeshBuilder.LegSurface.THIGH_L,
			SkaterMeshBuilder.LegSurface.THIGH_R]
	var rig: Transform3D = (_figure.get("_rig") as Node3D).transform
	var lowest: float = INF
	for v: int in verts.size():
		if not pants.has(roundi(zones[v].x)):
			continue
		var p := Vector3.ZERO
		for k: int in 4:
			if weights[v * 4 + k] > 0.0:
				p += (xforms[bones[v * 4 + k]] * verts[v]) * weights[v * 4 + k]
		lowest = minf(lowest, (rig * p).y)
	return lowest


func _builds() -> Array[PlayerAttributes]:
	return [PlayerAttributes.neutral(),
		PlayerAttributes.new(PlayerAttributes.HEIGHT_MIN, 170, 1, 1, 1, 1),
		PlayerAttributes.new(PlayerAttributes.HEIGHT_MAX, 260, 1, 1, 1, 2)]


func test_the_thighs_lie_flat_on_the_seat() -> void:
	for attrs: PlayerAttributes in _builds():
		_seat(attrs)
		for thigh_bone: int in [SkaterMeshBuilder.LegBone.THIGH_L, SkaterMeshBuilder.LegBone.THIGH_R]:
			var thigh: Basis = _leg(thigh_bone).basis
			assert_almost_eq(thigh.y.normalized().y, 0.0, 0.001, "the thigh lies flat")
			# The thigh's +Y runs up the leg to the hip, which sits behind the knee.
			assert_gt(thigh.y.z, 0.0, "hip at the back, knee forward")
		assert_almost_eq(_pants_bottom(), 0.0, 0.01, "the pants rest on the seat at the origin")


func test_the_feet_and_the_blade_share_one_floor() -> void:
	var runner := Vector3(0.0, 0.0, SkaterMeshBuilder.BLADE_ICE_Z)
	for attrs: PlayerAttributes in _builds():
		_seat(attrs)
		var left: Vector3 = _leg(SkaterMeshBuilder.LegBone.FOOT_L) * runner
		var right: Vector3 = _leg(SkaterMeshBuilder.LegBone.FOOT_R) * runner
		var floor_y: float = left.y
		assert_lt(floor_y, -0.3, "the feet hang well below the seat")
		assert_almost_eq(right.y, floor_y, 0.001)
		assert_lt(left.z, _bone(SkaterMeshBuilder.UpperBone.TORSO).origin.z,
				"the feet are out in front of the body")
		assert_lt(_leg(SkaterMeshBuilder.LegBone.KNEE_L).origin.y, 0.2, "knees at seat height")
		var stick: Node3D = _figure.get("_stick_root") as Node3D
		var rig: Node3D = _figure.get("_rig") as Node3D
		var heel_y: float = (rig.transform * stick.transform).origin.y
		assert_almost_eq(heel_y, floor_y + 0.042, 0.02, "the blade stands on the floor")


func test_both_hands_hold_the_shaft_within_reach() -> void:
	var arms: Array[Array] = [
		[SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM, SkaterMeshBuilder.UpperBone.TOP_FOREARM,
				SkaterMeshBuilder.UpperBone.TOP_HAND],
		[SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM, SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM,
				SkaterMeshBuilder.UpperBone.BOTTOM_HAND]]
	for attrs: PlayerAttributes in _builds():
		_seat(attrs)
		for i: int in 2:
			var upper: Transform3D = _bone(arms[i][0])
			# The arm bones are prisms from +Z (the near joint) to −Z.
			var shoulder: Vector3 = upper * Vector3(0.0, 0.0, 0.5)
			var reach: float = upper.basis.z.length() + _bone(arms[i][1]).basis.z.length()
			assert_lte(shoulder.distance_to(_bone(arms[i][2]).origin), reach + 0.001,
					"hand %d is inside its arm's reach" % i)

extends GutTest

# The locker's mannequin and the lobby's bench figures are not the skinned rig,
# so their jersey tail is draped once per pose and baked (FigureKit.drape,
# SkaterHemFlaps.baked_torso). Standing and seated — thighs flat through where
# the jersey's front hangs — no vertex of the tail's cloth is inside a thigh, as
# the figure's own thigh parts place it, where the undraped torso would be. The
# bottom cap's centre is not cloth: it closes the tube at the crotch, inside the
# pants, between thighs that overlap there.

# The thigh as its part carries it: the hip pivot sits this far above the part's
# own origin, and the capsule runs down from it (SkaterMeshBuilder's numbers).
const _HIP_IN_THIGH: float = 0.13
const _CLIP_M: float = 0.006


func _figure(seated: bool) -> LockerMannequin:
	var figure := LockerMannequin.new()
	figure.seated = seated
	add_child_autofree(figure)
	figure.apply(PlayerAttributes.neutral(), GearStyleConfig.new(),
			StickTapeConfig.from_code(StickTapeConfig.DEFAULT_CODE),
			TeamColorRegistry.get_colors(0, 0), SkinToneRegistry.DEFAULT_INDEX, false)
	return figure


# The deepest any of `torso`'s cloth vertices (those on a tail column's bone)
# reaches into a thigh.
func _worst(figure: LockerMannequin, torso: ArrayMesh) -> float:
	var at: Transform3D = (figure.get("_torso") as MeshInstance3D).transform
	var thighs: Array = figure.get("_thighs") as Array
	var verts: PackedVector3Array = torso.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = SkaterMeshBuilder.shared_upper_skin_mesh().surface_get_arrays(
			SkaterMeshBuilder.UpperSurface.TORSO)[Mesh.ARRAY_BONES]
	var worst: float = 0.0
	for thigh_node: MeshInstance3D in thighs:
		var thigh: Transform3D = thigh_node.transform
		var a: Vector3 = thigh * Vector3(0.0, _HIP_IN_THIGH, 0.0)
		var b: Vector3 = thigh * Vector3(0.0,
				_HIP_IN_THIGH - SkaterMeshBuilder.THIGH_CAPSULE_LENGTH_M, 0.0)
		var r: float = SkaterMeshBuilder.THIGH_CAPSULE_RADIUS_M * thigh.basis.x.length()
		for v: int in verts.size():
			if bones[v * 4] < SkaterMeshBuilder.UPPER_COLUMN_BIND_BASE:
				continue
			var p: Vector3 = at * verts[v]
			var t: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			worst = maxf(worst, r - p.distance_to(a + (b - a) * t))
	return worst


func test_a_standing_figure_drapes_over_its_legs() -> void:
	var figure: LockerMannequin = _figure(false)
	var torso: ArrayMesh = (figure.get("_torso") as MeshInstance3D).mesh as ArrayMesh
	assert_lt(_worst(figure, torso), _CLIP_M)


func test_a_seated_figure_drapes_over_its_lap() -> void:
	var figure: LockerMannequin = _figure(true)
	var torso: ArrayMesh = (figure.get("_torso") as MeshInstance3D).mesh as ArrayMesh
	assert_gt(_worst(figure, SkaterMeshBuilder.shared_torso()), 0.03,
			"the thighs lie through the undraped jersey")
	assert_lt(_worst(figure, torso), _CLIP_M)

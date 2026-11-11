extends GutTest

# The player screen's mannequin and the lobby's bench figures wear the rink's
# jersey tail (SkaterHemFlaps), settled once posed. Standing and seated —
# thighs flat through where the jersey's front hangs — no point of the tail's
# cloth is inside a thigh or the pants, as the rink's colliders place them off
# the figure's own bones (SkaterHemColliders).

const _CLIP_M: float = 0.006


func _figure(seated: bool) -> LockerMannequin:
	var figure := LockerMannequin.new()
	figure.seated = seated
	add_child_autofree(figure)
	figure.apply(PlayerAttributes.neutral(), GearStyleConfig.new(),
			StickTapeConfig.from_code(StickTapeConfig.DEFAULT_CODE),
			TeamColorRegistry.get_colors(0, 0), SkinToneRegistry.DEFAULT_INDEX, false)
	return figure


# The deepest any of the figure's tail points reaches into what it drapes over.
func _worst(figure: LockerMannequin) -> float:
	var kit: FigureKit = figure.get("_kit") as FigureKit
	var colliders := SkaterHemColliders.new()
	colliders.update(kit.skeleton)
	var worst: float = 0.0
	for p: Vector3 in kit.hem.hem_points():
		worst = maxf(worst, colliders.depth(p))
	return worst


func test_a_standing_figure_drapes_over_its_legs() -> void:
	assert_lt(_worst(_figure(false)), _CLIP_M)


func test_a_seated_figure_drapes_over_its_lap() -> void:
	assert_lt(_worst(_figure(true)), _CLIP_M)


# The tail is hung, not left at the skeleton's origin: every point of it below
# the torso's origin and within the jersey's length of it.
func test_the_tail_hangs_from_the_belt() -> void:
	var kit: FigureKit = _figure(false).get("_kit") as FigureKit
	var torso: float = kit.skeleton.get_bone_global_pose(SkaterBodySkeleton.TAIL_BONE).origin.y
	var points: PackedVector3Array = kit.hem.hem_points()
	assert_gt(points.size(), 0)
	for p: Vector3 in points:
		assert_lt(p.y, torso, "the tail hangs below the torso's origin")
		assert_gt(p.y, torso - 0.5, "and from the belt, not the ice")

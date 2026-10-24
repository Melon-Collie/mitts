extends GutTest

# The jersey's tail below the belt (SkaterHemFlaps) on a real skater: it hangs
# out of the thighs and pants it drapes over, swings back when the skater
# accelerates and comes to rest when he stops, keeps time off camera without
# writing bones, and holds a tucked corner where the waistband has it; and the
# lathe's tail stations are the cloth's (HemFlaps and its port fix them).

const _DT: float = 1.0 / 60.0


func _skater(tuck: int = GearModelRegistry.TUCK_NONE) -> Skater:
	var skater: Skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var gear := GearStyleConfig.new()
	gear.jersey_tuck = tuck
	skater.set_gear_style(gear)
	return skater


func _rig(skater: Skater) -> Skeleton3D:
	return skater.mesh_root.get_node("BodyRig") as Skeleton3D


func _steps(skater: Skater, n: int, on_camera: bool = true) -> void:
	for i: int in n:
		skater._arms.update_hem(_DT, on_camera)


# Mean of the hem points of the columns behind the body (+Z) — the back of the
# sweater, which hangs free; the front rests against the thighs.
func _hem_centre(flaps: SkaterHemFlaps) -> Vector3:
	var points: PackedVector3Array = flaps.hem_points()
	var sum := Vector3.ZERO
	var n: int = 0
	for k: int in flaps.columns:
		if flaps.rest[SkaterHemFlaps.HEM][k].z > 0.05:
			sum += points[k * SkaterHemFlaps.POINTS_PER_COLUMN + 1]
			n += 1
	return sum / float(n)


# Settled at rest with a thigh lifted into the hem, the flaps hang outside every
# collider (to within the fabric margin the solver keeps).
func test_the_flaps_stay_out_of_the_legs_and_pants() -> void:
	var skater: Skater = _skater()
	var rig: Skeleton3D = _rig(skater)
	var leg: int = SkaterBodySkeleton.LEG_BONE_OFFSET + SkaterMeshBuilder.LegBone.LEG_L
	var hip: Transform3D = rig.get_bone_pose(leg)
	rig.set_bone_pose(leg, Transform3D(Basis(Vector3.RIGHT, -1.3), hip.origin))
	var flaps: SkaterHemFlaps = skater._arms._hem
	_steps(skater, 120)
	flaps.colliders().update(rig)
	var tail: Transform3D = rig.get_bone_global_pose(SkaterBodySkeleton.TAIL_BONE)
	var hung: float = 0.0
	for k: int in flaps.columns:
		for station: int in [SkaterHemFlaps.BEND, SkaterHemFlaps.HEM]:
			hung = maxf(hung, flaps.colliders().depth(tail * flaps.rest[station][k]))
	assert_gt(hung, 0.02, "the raised thigh is in the rest drape's way")
	var worst: float = 0.0
	for p: Vector3 in flaps.hem_points():
		worst = maxf(worst, flaps.colliders().depth(p))
	assert_lt(worst, 0.005, "the hem is pushed out of the raised thigh")


# Accelerating along the skater's forward (−Z) leans him forward and throws the
# back of the hem back (+Z is the back); once he stops accelerating it comes
# back to rest.
func test_a_start_throws_the_hem_back_and_it_settles() -> void:
	var skater: Skater = _skater()
	var flaps: SkaterHemFlaps = skater._arms._hem
	_steps(skater, 60)
	var rest: Vector3 = _hem_centre(flaps)
	var forward: Vector3 = skater.upper_body.global_basis * Vector3.FORWARD
	skater.set_balance_tilt(Vector2(forward.x, forward.z) * deg_to_rad(15.0))
	_steps(skater, 30)
	assert_gt(_hem_centre(flaps).z - rest.z, 0.005, "the hem swings back behind its rest")
	skater.set_balance_tilt(Vector2.ZERO)
	_steps(skater, 300)
	assert_almost_eq(_hem_centre(flaps), rest, Vector3.ONE * 2e-3, "and comes back to rest")


# Off camera the drape keeps time but the bones are not written.
func test_off_camera_the_bones_are_left_alone() -> void:
	var skater: Skater = _skater()
	var rig: Skeleton3D = _rig(skater)
	var bone: int = SkaterBodySkeleton.column_bone(0, 1)
	_steps(skater, 10, false)
	assert_eq(rig.get_bone_pose(bone), Transform3D.IDENTITY)
	assert_false(skater._arms._hem.hem_points().is_empty(), "the drape still ran")
	_steps(skater, 1, true)
	assert_ne(rig.get_bone_pose(bone), Transform3D.IDENTITY, "and drawn, it is written")


# A fully tucked tail is held at its tucked rest, inside the pants, whatever
# the skater does.
func test_a_full_tuck_holds_still() -> void:
	var skater: Skater = _skater(GearModelRegistry.TUCK_FULL)
	var flaps: SkaterHemFlaps = skater._arms._hem
	_steps(skater, 30)
	var held: Vector3 = _hem_centre(flaps)
	var forward: Vector3 = skater.upper_body.global_basis * Vector3.FORWARD
	skater.set_balance_tilt(Vector2(forward.x, forward.z) * deg_to_rad(15.0))
	_steps(skater, 30)
	assert_almost_eq(_hem_centre(flaps), held, Vector3.ONE * 1e-4)


func test_the_lathe_tail_stations_are_the_cloths() -> void:
	var belt: int = SkaterMeshBuilder.TORSO_BELT_STATION
	assert_eq(SkaterMeshBuilder.TORSO_HEM_STATION - belt + 1, HemFlaps.STATIONS)
	assert_eq(SkaterMeshBuilder.TORSO_BEND_STATION - belt, HemFlaps.BEND)
	assert_eq(SkaterMeshBuilder.TORSO_HEM_STATION - belt, HemFlaps.HEM)

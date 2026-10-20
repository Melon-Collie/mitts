extends GutTest

# The draping hem sims (HemSimMode) are prototypes compared side by side by
# tools/hem_compare.gd; what is held here is that each one builds on a real
# skater and steps, and that the flaps — the one that collides on its own —
# keep the tail out of the pants and thighs it hangs over.

const _DT: float = 1.0 / 60.0


func _skater(mode: int, tuck: int = GearModelRegistry.TUCK_NONE) -> Skater:
	var skater: Skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	skater.hem_sim_mode = mode
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var gear := GearStyleConfig.new()
	gear.jersey_tuck = tuck
	skater.set_gear_style(gear)
	return skater


func test_every_mode_builds_and_steps() -> void:
	for mode: int in HemSimMode.NAMES.size():
		var skater: Skater = _skater(mode)
		for i: int in 10:
			skater._arms.update_hem(_DT, true)
		var upper: MeshInstance3D = skater.mesh_root.get_node("BodyRig/UpperMesh") as MeshInstance3D
		assert_eq(upper.mesh.get_surface_count(), SkaterMeshBuilder.UPPER_SURFACE_COUNT,
				"%s wears a full upper mesh" % HemSimMode.NAMES[mode])
		assert_eq(skater._arms._hem_sim == null, mode == HemSimMode.SWAY,
				"%s has a sim exactly when it drapes" % HemSimMode.NAMES[mode])


# Settled at rest with the thighs splayed into the hem, the flaps hang outside
# every collider (to within the fabric margin the solver keeps).
func test_the_flaps_stay_out_of_the_legs_and_pants() -> void:
	var skater: Skater = _skater(HemSimMode.FLAPS)
	var rig: Skeleton3D = skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var leg: int = SkaterBodySkeleton.LEG_BONE_OFFSET + SkaterMeshBuilder.LegBone.LEG_L
	var hip: Transform3D = rig.get_bone_pose(leg)
	rig.set_bone_pose(leg, Transform3D(Basis(Vector3.RIGHT, -1.3), hip.origin))
	var sim: SkaterHemSim = skater._arms._hem_sim
	for i: int in 120:
		skater._arms.update_hem(_DT, true)
	sim.colliders().update(rig)
	var tail: Transform3D = rig.get_bone_global_pose(SkaterBodySkeleton.TAIL_BONE)
	var hung: float = 0.0
	for k: int in sim.columns:
		for station: int in [SkaterHemSim.BEND, SkaterHemSim.HEM]:
			hung = maxf(hung, sim.colliders().depth(tail * sim.rest[station][k]))
	assert_gt(hung, 0.02, "the raised thigh is in the rest drape's way")
	var worst: float = 0.0
	for p: Vector3 in sim.hem_points():
		worst = maxf(worst, sim.colliders().depth(p))
	assert_lt(worst, 0.005, "the hem is pushed out of the raised thigh")

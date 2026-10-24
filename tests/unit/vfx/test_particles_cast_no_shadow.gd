extends GutTest

# Every effect's particles stay out of the shadow maps. A particle node casts by
# default, and a GPUParticles3D draws its whole `amount` every pass whether the
# particles are alive or not, so the skaters' blade trails alone put ~2.4 M
# triangles a frame through the eight shadowed arena lights for dots lying on
# the ice.


func _particles(n: Node, out: Array[GeometryInstance3D]) -> void:
	if n is GPUParticles3D or n is CPUParticles3D:
		out.append(n as GeometryInstance3D)
	for c: Node in n.get_children():
		_particles(c, out)


func _assert_none_cast(vfx: Node3D) -> void:
	add_child_autofree(vfx)
	vfx.set_process(false)
	var found: Array[GeometryInstance3D] = []
	_particles(vfx, found)
	assert_gt(found.size(), 0, "%s builds particles" % vfx.get_script().get_global_name())
	for p: GeometryInstance3D in found:
		assert_eq(p.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s/%s casts no shadow" % [vfx.get_script().get_global_name(), p.name])


func test_skater_vfx() -> void:
	_assert_none_cast(SkaterVFX.new())


func test_puck_vfx() -> void:
	_assert_none_cast(PuckVFX.new())


func test_blade_spray_vfx() -> void:
	_assert_none_cast(BladeSprayVFX.new())


func test_goal_vfx() -> void:
	_assert_none_cast(GoalVFX.new())

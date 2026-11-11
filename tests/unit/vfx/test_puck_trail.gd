extends GutTest

# The puck trail is a chain of dots dropped every TRAIL_SPACING along the
# puck's path. It reads as one scrape only while neighbouring dots overlap.


func _trail_dot(vfx: PuckVFX) -> CylinderMesh:
	var particles: GPUParticles3D = vfx.get_node("TrailParticles") as GPUParticles3D
	return particles.draw_pass_1 as CylinderMesh


func test_neighbouring_dots_overlap() -> void:
	var vfx: PuckVFX = PuckVFX.new()
	add_child_autofree(vfx)
	vfx.set_process(false)
	var dot: CylinderMesh = _trail_dot(vfx)
	assert_lt(PuckVFX.TRAIL_SPACING, dot.top_radius * 2.0,
			"spacing %.3f m leaves a gap between %.3f m dots"
			% [PuckVFX.TRAIL_SPACING, dot.top_radius * 2.0])


func test_the_pool_holds_a_full_trail_at_max_speed() -> void:
	var dots_needed: float = (
			PuckVFX.TRAIL_MAX_SPEED * PuckVFX.TRAIL_LIFETIME / PuckVFX.TRAIL_SPACING)
	assert_gte(float(PuckVFX.TRAIL_AMOUNT), dots_needed)


func test_max_speed_covers_the_hardest_slapper() -> void:
	# The strongest build's slapper, ~48 m/s against the neutral 40.
	assert_gt(PuckVFX.TRAIL_MAX_SPEED, GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S * 1.2)

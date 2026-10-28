extends GutTest

# The knee is the sock carried up into the pant leg, over the shin guard's cap,
# so both painters — the rink's SkaterUniformCoordinator and the display figures'
# FigureKit — dress it in the sock's base, solid. Solid works only because every
# kit's sock top is that base; a stripe running off the top would seam there.

const _SCENE: String = "res://Scenes/Skater.tscn"
# Pomegranate away: burgundy pants over cream socks, so the two can't be confused.
const _SLOT: int = 0
const _AWAY: int = 1


func _kit() -> Dictionary:
	return TeamColorRegistry.get_colors(_SLOT, _AWAY)


func test_the_kit_tells_pants_from_socks() -> void:
	var uniform: Dictionary = _kit().uniform
	assert_ne(uniform.pants.base, uniform.socks.base,
			"the fixture must tell a pants-colored knee from a sock-colored one")


func test_the_rink_paints_the_knee_as_sock() -> void:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	skater.set_uniform(_kit())
	var paint: BodyZonePaint = skater.get("_paint") as BodyZonePaint
	for surface: int in [SkaterMeshBuilder.LegSurface.KNEE_L,
			SkaterMeshBuilder.LegSurface.KNEE_R]:
		assert_eq(paint.zone(surface).albedo_color, _kit().uniform.socks.base,
				"knee surface %d" % surface)


func test_the_figure_paints_the_knee_as_sock() -> void:
	var rig := Node3D.new()
	add_child_autofree(rig)
	var kit := FigureKit.new()
	kit.build(rig, rig)
	kit.dress(_kit(), GearStyleConfig.new(), StickTapeConfig.new(),
			SkinToneRegistry.DEFAULT_INDEX, "", 0)
	for i: int in 2:
		var mat: StandardMaterial3D = kit.knees[i].get_surface_override_material(0) \
				as StandardMaterial3D
		assert_eq(mat.albedo_color, _kit().uniform.socks.base, "knee %d" % i)


func test_every_sock_top_is_its_base() -> void:
	for slot: int in TeamColorRegistry.get_all_slots():
		for side: int in 2:
			var socks: Dictionary = TeamColorRegistry.get_colors(slot, side).uniform.socks
			var top: Color = UniformPaint.h_stripes(socks.base, socks.stripes) \
					.get_image().get_pixel(0, 0)
			assert_eq(top, socks.base, "%s %s: the sock's top meets the knee" % [
					TeamColorRegistry.get_preset_name(slot), "away" if side else "home"])

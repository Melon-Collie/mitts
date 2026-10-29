extends GutTest

# SkaterShadows — the player's shadow setting reaches every part of the figure
# that casts, on skaters already on the ice as well as new ones.


func before_each() -> void:
	SkaterShadows.set_enabled(true)


func after_each() -> void:
	SkaterShadows.set_enabled(true)


func _skater() -> Skater:
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.set_process(false)
	sk.set_physics_process(false)
	return sk


func _casters(sk: Skater) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = [sk.stick_mesh]
	out.append(sk.mesh_root.get_node("BodyRig/Body") as GeometryInstance3D)
	return out


func _assert_casting(sk: Skater, cast: GeometryInstance3D.ShadowCastingSetting,
		why: String) -> void:
	for part: GeometryInstance3D in _casters(sk):
		assert_eq(part.cast_shadow, cast, "%s: %s" % [part.name, why])


func test_the_body_and_the_stick_cast() -> void:
	_assert_casting(_skater(), GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "on by default")


func test_a_ghost_casts_no_shadow() -> void:
	var sk: Skater = _skater()
	sk.set_ghost(true)
	_assert_casting(sk, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "translucent")
	sk.set_ghost(false)
	_assert_casting(sk, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "back again")


func test_the_setting_reaches_skaters_already_on_the_ice() -> void:
	var sk: Skater = _skater()
	SkaterShadows.set_enabled(false)
	_assert_casting(sk, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "switched off")
	SkaterShadows.set_enabled(true)
	_assert_casting(sk, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "switched on")

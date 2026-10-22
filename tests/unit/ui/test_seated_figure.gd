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


func _parts(part_name: String) -> Array:
	return _figure.get(part_name) as Array


# Bounds of a part in the figure's own frame.
func _bounds(mi: MeshInstance3D) -> AABB:
	var rig: Node3D = _figure.get("_rig") as Node3D
	return rig.transform * mi.transform * mi.get_aabb()


func _builds() -> Array[PlayerAttributes]:
	return [PlayerAttributes.neutral(),
		PlayerAttributes.new(PlayerAttributes.HEIGHT_MIN, 170, 1, 1, 1, 1),
		PlayerAttributes.new(PlayerAttributes.HEIGHT_MAX, 260, 1, 1, 1, 2)]


func test_the_thighs_lie_flat_on_the_seat() -> void:
	for attrs: PlayerAttributes in _builds():
		_seat(attrs)
		for thigh: MeshInstance3D in _parts("_thighs"):
			assert_almost_eq(thigh.transform.basis.y.normalized().y, 0.0, 0.001,
					"the thigh lies flat")
			# The thigh's +Y runs up the leg to the hip, which sits behind the knee.
			assert_gt(thigh.transform.basis.y.z, 0.0, "hip at the back, knee forward")
			assert_almost_eq(_bounds(thigh).position.y, 0.0, 0.001,
					"the thighs rest on the seat at the origin")


func test_the_feet_and_the_blade_share_one_floor() -> void:
	for attrs: PlayerAttributes in _builds():
		_seat(attrs)
		var boots: Array = _parts("_boots")
		var floor_y: float = _bounds(boots[0]).position.y
		assert_lt(floor_y, -0.3, "the feet hang well below the seat")
		assert_almost_eq(_bounds(boots[1]).position.y, floor_y, 0.001)
		var knees: Array = _parts("_knees")
		assert_lt(_bounds(boots[0]).get_center().z, _bounds(_figure.get("_torso")).get_center().z,
				"the feet are out in front of the body")
		assert_lt(_bounds(knees[0]).get_center().y, 0.2, "knees at seat height")
		var stick: Node3D = _figure.get("_stick_root") as Node3D
		var rig: Node3D = _figure.get("_rig") as Node3D
		var heel_y: float = (rig.transform * stick.transform).origin.y
		assert_almost_eq(heel_y, floor_y + 0.042, 0.02, "the blade stands on the floor")


func test_both_hands_hold_the_shaft_within_reach() -> void:
	for attrs: PlayerAttributes in _builds():
		_seat(attrs)
		for i: int in 2:
			var upper_arm: MeshInstance3D = _parts("_upper_arms")[i]
			var hand: MeshInstance3D = _parts("_hands")[i]
			var shoulder: Vector3 = upper_arm.position + upper_arm.transform.basis.y * 0.5
			var reach: float = upper_arm.transform.basis.y.length() \
					+ (_parts("_forearms")[i] as MeshInstance3D).transform.basis.y.length()
			assert_lte(shoulder.distance_to(hand.position), reach + 0.001,
					"hand %d is inside its arm's reach" % i)

extends GutTest

# A shot caught on his chest (KeeperChestTrap): only at the logo, between where
# his arm pads lie on the protector and in the middle of its height, on its
# face; and only when a hand gets onto it before the foam's rebound carries it
# out of the glove's pocket, so a softer shot, or a hand nearer, is held where
# a harder one comes off him.

var _skel := KeeperSkeleton.new()


func before_each() -> void:
	var p := KeeperPose.new()
	KeeperPoses.ready(p)
	_skel.pose(p)


# A point on the protector's face, `across` and `up` from its centre in its own
# frame, `out` off it.
func _on_face(across: float, up: float, out: float = 0.0) -> Vector3:
	var chest: Transform3D = KeeperGear.box(_skel, KeeperGear.Part.CHEST)
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	return chest * Vector3(across, up, -h.z - out)


func test_the_logo_is_the_middle_of_his_chest_between_his_arms() -> void:
	var h: Vector3 = KeeperGear.half_extents(KeeperGear.Part.CHEST)
	var inside: float = h.x - KeeperAnatomy.ARM_PAD_WIDTH_M
	assert_true(KeeperChestTrap.at_logo(_skel, _on_face(0.0, 0.0)), "dead centre")
	assert_true(KeeperChestTrap.at_logo(_skel, _on_face(inside - 0.01, 0.0)), "just inside his arm")
	assert_false(KeeperChestTrap.at_logo(_skel, _on_face(inside + 0.01, 0.0)), "under his arm")
	assert_false(KeeperChestTrap.at_logo(_skel, _on_face(0.0, 0.5 * h.y + 0.01)), "up at the shoulders")
	assert_false(KeeperChestTrap.at_logo(_skel, _on_face(0.0, -0.5 * h.y - 0.01)), "down at the belt")
	var chest: Transform3D = KeeperGear.box(_skel, KeeperGear.Part.CHEST)
	assert_false(KeeperChestTrap.at_logo(_skel, chest * Vector3(0.0, 0.0, h.z)), "his back")


func test_he_holds_it_when_a_hand_gets_there_before_it_comes_off_him() -> void:
	var cor: float = GoalieSaveRules.MATERIALS[GoalieSaveRules.SavePart.CHEST * GoalieSaveRules.MAT_STRIDE
			+ GoalieSaveRules.MAT_COR_SCALE]
	var reach_s: float = 0.07
	var limit: float = KeeperChestTrap.POCKET_M / (cor * reach_s)
	assert_true(KeeperChestTrap.closes_on(limit * 0.95, reach_s), "just soft enough")
	assert_false(KeeperChestTrap.closes_on(limit * 1.05, reach_s), "just too hard")
	assert_true(KeeperChestTrap.closes_on(limit * 3.0, reach_s / 4.0), "harder, with a hand nearer")
	assert_true(KeeperChestTrap.closes_on(40.0, 0.0), "a hand already over it")

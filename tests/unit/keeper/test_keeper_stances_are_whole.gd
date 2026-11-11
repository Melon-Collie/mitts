extends GutTest

# Every taught stance (KeeperPoses) writes the whole of what the skeleton
# solves from: written over a pose left anywhere else (another stance, a
# cover's lean, a foot turned along its shin, the hands sent out), it solves to
# the same body as written over a fresh pose. A field a stance leaves alone
# carries over whatever came before, and his gear changes with his history.

const SIDES: Array[float] = [-1.0, 1.0]


func test_every_stance_solves_the_same_whatever_came_before() -> void:
	for stance: Array in _stances():
		var fresh := KeeperPose.new()
		(stance[1] as Callable).call(fresh)
		var dirty: KeeperPose = _dirty()
		(stance[1] as Callable).call(dirty)
		var a := KeeperSkeleton.new()
		var b := KeeperSkeleton.new()
		a.pose(fresh)
		b.pose(dirty)
		for bone: int in KeeperSkeleton.BONE_COUNT:
			assert_true(a.xf[bone].is_equal_approx(b.xf[bone]), "%s: %s" % [stance[0],
					KeeperSkeleton.Bone.keys()[bone]])
		for part: int in KeeperGear.PART_COUNT:
			assert_true(KeeperGear.box(a, part).is_equal_approx(KeeperGear.box(b, part)), "%s: %s" % [stance[0],
					KeeperGear.Part.keys()[part]])


func _stances() -> Array:
	var out: Array = [["upright", KeeperPoses.upright], ["ready", KeeperPoses.ready],
			["low_ready", KeeperPoses.low_ready], ["butterfly", KeeperPoses.butterfly]]
	for side: float in SIDES:
		out.append(["butterfly_push %+.0f" % side, KeeperPoses.butterfly_push.bind(side)])
		out.append(["half_butterfly_loaded %+.0f" % side, KeeperPoses.half_butterfly_loaded.bind(side)])
		out.append(["half_butterfly %+.0f" % side, KeeperPoses.half_butterfly.bind(side)])
		out.append(["butterfly_extension %+.0f" % side, KeeperPoses.butterfly_extension.bind(side)])
		out.append(["kick %+.0f" % side, KeeperPoses.kick.bind(side)])
		out.append(["rvh %+.0f" % side, KeeperPoses.rvh.bind(side)])
	return out


# A pose left by something else: the butterfly with its feet turned along the
# shins and flexed, leaned over to cover a puck behind him, the hands out.
func _dirty() -> KeeperPose:
	var p := KeeperPose.new()
	KeeperPoses.butterfly(p)
	for leg: KeeperPose.Leg in p.legs:
		leg.foot_mode = KeeperPose.FootMode.FLAT
		leg.along_shin = 0.6
		leg.flex = 0.7
	KeeperPoses.cover_lean(p, Vector3(-0.5, 0.0, 0.3), 1.0)
	p.neck_rot = Vector3(0.3, 0.4, 0.0)
	p.head_rot = Vector3(0.2, -0.3, 0.0)
	p.glove_hand = Vector3(-0.6, 0.2, 0.4)
	p.glove_from_chest = true
	p.glove_palm = Vector3.DOWN
	p.blocker_reach = true
	p.blocker_grip = Vector3(0.4, 0.3, -0.5)
	return p

extends GutTest

# KeeperGear.boxes, the seat's one pass over every part, against box() part by
# part: the same transform to the bit in every taught stance, either hand, so
# seating him through it cannot move a save box or a shot-field cell.

var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func _stances() -> Array[Callable]:
	return [
		func(p: KeeperPose) -> void: KeeperPoses.upright(p),
		func(p: KeeperPose) -> void: KeeperPoses.ready(p),
		func(p: KeeperPose) -> void: KeeperPoses.low_ready(p),
		func(p: KeeperPose) -> void: KeeperPoses.butterfly(p),
		func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, -1.0),
		func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, 1.0),
		func(p: KeeperPose) -> void: KeeperPoses.butterfly_push(p, -1.0),
		func(p: KeeperPose) -> void: KeeperPoses.butterfly_push(p, 1.0),
		func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, -1.0),
		func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, 1.0),
		func(p: KeeperPose) -> void: KeeperPoses.kick(p, -1.0),
		func(p: KeeperPose) -> void: KeeperPoses.kick(p, 1.0),
		func(p: KeeperPose) -> void: KeeperPoses.rvh(p, -1.0),
		func(p: KeeperPose) -> void: KeeperPoses.rvh(p, 1.0),
	]


func test_every_box_is_the_one_box_gives() -> void:
	var out: Array[Transform3D] = []
	out.resize(KeeperGear.PART_COUNT)
	var settled: int = 0
	for mirrored: bool in [false, true]:
		_skel.mirrored = mirrored
		for i: int in _stances().size():
			_stances()[i].call(_pose)
			_skel.pose(_pose)
			KeeperGear.boxes(_skel, out)
			for part: int in KeeperGear.PART_COUNT:
				assert_eq(out[part], KeeperGear.box(_skel, part),
						"stance %d part %d%s" % [i, part, " mirrored" if mirrored else ""])
			if KeeperGear._pad_settle(_skel, 0) != Vector3.ZERO or KeeperGear._pad_settle(_skel, 1) != Vector3.ZERO:
				settled += 1
	assert_gt(settled, 0, "some stance settles a pad, so the shared settle is exercised")

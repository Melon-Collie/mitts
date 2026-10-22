extends GutTest

# Every hole a flat puck fits through in the shape he shows a shot straight on
# (KeeperSeams) is one of his stance's intended windows: the openings the
# stance itself makes, which the stick and the play cover. Any other hole fails
# here, so the next change of puck, pad or pose cannot open one silently.
#
# A window is a region of the mouth (x across from its centre, y up from the
# ice, metres), a little larger than the opening it allows.

var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func _stances() -> Array:
	return [
		["ready", func(p: KeeperPose) -> void: KeeperPoses.ready(p), {
			"five-hole above the blade": Rect2(-0.14, 0.06, 0.25, 0.34),
		}],
		["butterfly", func(p: KeeperPose) -> void: KeeperPoses.butterfly(p), {}],
		["half L", func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, -1.0), {
			"between the down pad and the standing one": Rect2(-0.04, 0.06, 0.25, 0.42),
		}],
		["half R", func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, 1.0), {
			"between the down pad and the standing one": Rect2(-0.23, 0.06, 0.27, 0.42),
		}],
		["extension L", func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, -1.0), {}],
		["extension R", func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, 1.0), {}],
		["kick L", func(p: KeeperPose) -> void: KeeperPoses.kick(p, -1.0), {
			"five-hole the kick opens": Rect2(-0.41, 0.06, 0.44, 0.53),
		}],
		["kick R", func(p: KeeperPose) -> void: KeeperPoses.kick(p, 1.0), {
			"five-hole the kick opens": Rect2(0.0, 0.06, 0.38, 0.50),
		}],
		["rvh L", func(p: KeeperPose) -> void: KeeperPoses.rvh(p, -1.0), {
			"along the ice under the off pad": Rect2(0.24, 0.0, 0.36, 0.22),
		}],
		["rvh R", func(p: KeeperPose) -> void: KeeperPoses.rvh(p, 1.0), {
			"along the ice under the off pad": Rect2(-0.60, 0.0, 0.36, 0.22),
		}],
	]


func test_every_seam_is_an_intended_window() -> void:
	for stance: Array in _stances():
		(stance[1] as Callable).call(_pose)
		_skel.pose(_pose)
		var windows: Dictionary = stance[2]
		for seam: Rect2 in KeeperSeams.find(_skel):
			var intended: bool = false
			for rect: Rect2 in windows.values():
				intended = intended or rect.encloses(seam)
			assert_true(intended, "%s: a hole a puck fits through at x %.2f..%.2f, y %.2f..%.2f"
					% [stance[0], seam.position.x, seam.end.x, seam.position.y, seam.end.y])


# A right-catcher's holes are the left-catcher's reflected: the windows hold
# for him with x turned over.
func test_a_right_catcher_has_the_seams_reflected() -> void:
	var right := KeeperSkeleton.new()
	right.mirrored = true
	for stance: Array in _stances():
		(stance[1] as Callable).call(_pose)
		_skel.pose(_pose)
		right.pose(_pose)
		var left_seams: Array[Rect2] = KeeperSeams.find(_skel)
		var right_seams: Array[Rect2] = KeeperSeams.find(right)
		assert_eq(right_seams.size(), left_seams.size(), "%s" % stance[0])
		for seam: Rect2 in left_seams:
			var reflected := Rect2(-seam.end.x, seam.position.y, seam.size.x, seam.size.y)
			var found: bool = false
			for r: Rect2 in right_seams:
				found = found or (r.position.distance_to(reflected.position) < 0.015
						and r.size.distance_to(reflected.size) < 0.015)
			assert_true(found, "%s: the hole at x %.2f..%.2f reflected"
					% [stance[0], seam.position.x, seam.end.x])


# The stance the windows guard keeps them: a window that shuts is good news,
# but the five-hole the ready stance opens is the reference that the finder
# still sees a hole when there is one.
func test_the_ready_five_hole_is_seen() -> void:
	KeeperPoses.ready(_pose)
	_skel.pose(_pose)
	assert_eq(KeeperSeams.find(_skel).size(), 1)


# Seams are holes in him, not the net round him: in the ready stance the
# mouth's bottom corners, by each post on the ice, are open net.
func test_the_open_net_is_not_a_seam() -> void:
	KeeperPoses.ready(_pose)
	_skel.pose(_pose)
	var cells: PackedByteArray = KeeperSeams.classify(_skel)
	var nx: int = KeeperSeams.columns(KeeperSeams.STEP_M)
	var row: int = 3
	assert_eq(cells[row * nx + 2], KeeperSeams.Cell.OPEN)
	assert_eq(cells[row * nx + nx - 3], KeeperSeams.Cell.OPEN)

class_name KeeperReach
extends RefCounted

# Reaching for a puck a carrier has wide of him, before it is shot: down, the
# pad on the puck's side driven out along the ice (the butterfly extension,
# laid over what his legs are doing by KeeperPadOut) when that shows the puck
# less of the low net than the butterfly he is in.
# The extension seals the ice out toward the post and opens it under the
# extended thigh, so neither is the better shape everywhere: the shots the puck
# has along the ice and up to his pads' height, from where he reads it, are
# counted against each as it would lie where he is, and the one that lets
# fewer by is the one he takes. Pure; the shapes are solved once.

# The lines a puck fits along, one a puck's width from the next across the
# mouth, at each of these heights: on the ice, half a pad up and at the height
# of a pad lying on it.
const LANE_M: float = 2.0 * GameRules.PUCK_COLLISION_RADIUS
const HEIGHTS_M: Array[float] = [GameRules.PUCK_COLLISION_HALF_HEIGHT, KeeperAnatomy.PAD_WIDTH_M * 0.5,
		KeeperAnatomy.PAD_WIDTH_M]
# How many more lines the extension has to shut than the butterfly before he
# reaches: a puck's width of the mouth at every height. Out, he holds it while
# it shuts no fewer.
const WORTH_LINES: int = 3

# The gear, in the order a low line is tried against it: the pieces that lie
# along the ice first, since the first one met ends the line.
const TRIED: Array[int] = [
	KeeperGear.Part.PAD_G, KeeperGear.Part.PAD_B, KeeperGear.Part.BOOT_G, KeeperGear.Part.BOOT_B,
	KeeperGear.Part.RISE_G, KeeperGear.Part.RISE_B, KeeperGear.Part.SKATE_G, KeeperGear.Part.SKATE_B,
	KeeperGear.Part.BLADE, KeeperGear.Part.PADDLE, KeeperGear.Part.THIGH_G, KeeperGear.Part.THIGH_B,
	KeeperGear.Part.PANTS, KeeperGear.Part.GLOVE, KeeperGear.Part.BLOCKER, KeeperGear.Part.FOREARM_G,
	KeeperGear.Part.FOREARM_B, KeeperGear.Part.CHEST, KeeperGear.Part.UPPER_ARM_G, KeeperGear.Part.UPPER_ARM_B,
	KeeperGear.Part.SHAFT, KeeperGear.Part.MASK,
]


# A shape he could be in, as its gear's boxes in his own frame, in TRIED's
# order.
class Shape extends RefCounted:
	var boxes: Array[Transform3D] = []
	var halves := PackedVector3Array()
	# Everything a puck's edge could meet of it: a line clear of this is clear
	# of every piece.
	var bounds := AABB()

	func take(skel: KeeperSkeleton) -> void:
		boxes.clear()
		halves.clear()
		for part: int in TRIED:
			var box: Transform3D = KeeperGear.box(skel, part)
			var half: Vector3 = KeeperGear.half_extents(part)
			boxes.append(box)
			halves.append(half)
			for corner: int in 8:
				var at: Vector3 = box * Vector3(half.x * (1 if corner & 1 else -1), half.y * (1 if corner & 2 else -1),
						half.z * (1 if corner & 4 else -1))
				bounds = AABB(at, Vector3.ZERO) if boxes.size() == 1 and corner == 0 else bounds.expand(at)
		bounds = bounds.grow(GameRules.PUCK_COLLISION_RADIUS)


var _down := Shape.new()
# Extended toward keeper space's −x (index 0) and +x (1).
var _out: Array[Shape] = [Shape.new(), Shape.new()]
# Where the butterfly's pads end along the ice, toward keeper space's −x and
# +x, and how far back of him they lie, his own frame.
var _pads_to: Array[float] = [0.0, 0.0]
var _pads_back: float = 0.0
var _built_mirrored: int = -1
var _hit := SweptDiscOBB.Result.new()


# The side of keeper space (+1 his +x) he reaches a pad out to for the puck at
# `puck` (net frame, x and z), down where `motor` has him; 0 none. `reaching`
# is the side he already reaches to.
func plan(puck: Vector2, motor: KeeperMotor, mirrored: bool, reaching: float) -> float:
	_build(mirrored)
	var here := Vector3(motor.x, 0.0, motor.z)
	var into_his: Basis = Basis(Vector3.UP, motor.yaw).inverse()
	var from: Vector3 = into_his * (Vector3(puck.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, puck.y) - here)
	if reaching == 0.0 and _pads_span_the_posts(from, here, into_his):
		return 0.0
	var side: float = 1.0 if from.x >= 0.0 else -1.0
	var stays: int = _open(_down, from, here, into_his, puck)
	if stays == 0:
		return 0.0
	var reaches: int = _open(_out[1 if side > 0.0 else 0], from, here, into_his, puck)
	if reaching == side:
		return side if reaches <= stays else 0.0
	return side if reaches + WORTH_LINES <= stays else 0.0


# Whether the lines from the puck (`from`, in his frame) to both posts cross
# where his butterfly's pads lie inside their ends: the ice shut post to post,
# and nothing to count.
func _pads_span_the_posts(from: Vector3, here: Vector3, into_his: Basis) -> bool:
	for post: int in 2:
		var to: Vector3 = into_his * (Vector3((2.0 * post - 1.0) * KeeperCoverage.MOUTH_HALF_M, 0.0, 0.0) - here)
		if absf(to.z - from.z) < 1e-4:
			return false
		var along: float = (_pads_back - from.z) / (to.z - from.z)
		if along <= 0.0 or along >= 1.0:
			return false
		var across: float = from.x + (to.x - from.x) * along
		if across < -_pads_to[0] or across > _pads_to[1]:
			return false
	return true


# How many of the lines from the puck (`from`, in his frame) into the mouth,
# no higher than a shot from there is lifted, get by `shape`.
func _open(shape: Shape, from: Vector3, here: Vector3, into_his: Basis, puck: Vector2) -> int:
	var lift: float = PlayerAttributes.steepest_loft_tan()
	var open: int = 0
	var x: float = -KeeperCoverage.MOUTH_HALF_M
	while x <= KeeperCoverage.MOUTH_HALF_M + 1e-6:
		var reach: float = GameRules.PUCK_COLLISION_HALF_HEIGHT + lift * Vector2(x - puck.x, -puck.y).length()
		for y: float in HEIGHTS_M:
			if y > reach:
				break
			var to: Vector3 = into_his * (Vector3(x, y, 0.0) - here)
			var met: bool = false
			if not shape.bounds.intersects_segment(from, to):
				open += 1
				continue
			for i: int in shape.boxes.size():
				if SweptDiscOBB.contact(from, to, GameRules.PUCK_COLLISION_RADIUS, shape.boxes[i], shape.halves[i], _hit):
					met = true
					break
			if not met:
				open += 1
		x += LANE_M
	return open


func _build(mirrored: bool) -> void:
	if _built_mirrored == int(mirrored):
		return
	_built_mirrored = int(mirrored)
	var pose := KeeperPose.new()
	var skel := KeeperSkeleton.new()
	skel.mirrored = mirrored
	KeeperPoses.butterfly(pose)
	skel.pose(pose)
	_down.take(skel)
	var glove_side: Vector3 = KeeperGear.post_pad_contact(skel, -1.0)
	var blocker_side: Vector3 = KeeperGear.post_pad_contact(skel, 1.0)
	_pads_to[0] = -glove_side.x
	_pads_to[1] = blocker_side.x
	_pads_back = 0.5 * (glove_side.z + blocker_side.z)
	for i: int in 2:
		KeeperPoses.butterfly_extension(pose, own_side(-1.0 if i == 0 else 1.0, mirrored))
		skel.pose(pose)
		_out[i].take(skel)


# His own side (−1 the glove's, as a stance takes it) for a side of keeper
# space.
static func own_side(side: float, mirrored: bool) -> float:
	return -side if mirrored else side

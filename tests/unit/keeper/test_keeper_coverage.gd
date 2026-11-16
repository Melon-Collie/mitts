extends GutTest

# How much of the net each stance covers as the puck sees it (KeeperCoverage):
# straight on with him on the goal line, and from the dot line with him at the
# B depth. The numbers are a snapshot (snapshots/keeper_coverage.txt), so a
# change to his body or a stance reads as a reviewed delta; the orderings that
# are physical necessities are asserted.

const Snapshot := preload("res://tests/snapshot.gd")
const STEP_M: float = 0.04
const B_DEPTH_M: float = 1.3
const DOT_LINE_M: float = GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z
const CLOSING_FROM_M: float = KeeperPositioning.TIGHT_M

var _pose := KeeperPose.new()
var _skel := KeeperSkeleton.new()


func _stances() -> Array:
	return [
		["ready", func(p: KeeperPose) -> void: KeeperPoses.ready(p)],
		["low_ready", func(p: KeeperPose) -> void: KeeperPoses.low_ready(p)],
		["butterfly", func(p: KeeperPose) -> void: KeeperPoses.butterfly(p)],
		["half_butterfly", func(p: KeeperPose) -> void: KeeperPoses.half_butterfly(p, -1.0)],
		["extension", func(p: KeeperPose) -> void: KeeperPoses.butterfly_extension(p, -1.0)],
	]


func _straight_on() -> float:
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	var half_w: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - r
	var top: float = GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS - r
	var covered: int = 0
	var total: int = 0
	var x: float = -half_w
	while x <= half_w + 1e-6:
		var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
		while y <= top + 1e-6:
			total += 1
			if KeeperGear.nearest(_skel, Vector3(x, y, -3.0), Vector3(x, y, 1.0), r,
					out, scratch) >= 0:
				covered += 1
			y += STEP_M
		x += STEP_M
	return float(covered) / float(total)


func _from_the_dot_line() -> float:
	return KeeperCoverage.fraction(_skel,
			Vector3(0.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, B_DEPTH_M - DOT_LINE_M),
			B_DEPTH_M, 0.0, STEP_M)


func test_keeper_coverage_snapshot() -> void:
	var snap := Snapshot.new("res://tests/unit/keeper/snapshots/keeper_coverage.txt")
	for stance: Array in _stances():
		(stance[1] as Callable).call(_pose)
		_skel.pose(_pose)
		snap.record("%s straight_on" % stance[0], _straight_on())
		snap.record("%s dot_line_at_b" % stance[0], _from_the_dot_line())
		snap.record("%s closing_share" % stance[0], KeeperCoverage.closing_share(_skel, CLOSING_FROM_M))
	snap.verify(self)


# Challenging cuts the angle: from the dot line he covers more of the net at
# the B depth than standing on the goal line covers of it straight on.
func test_depth_covers_more_than_the_goal_line() -> void:
	for stance: Array in _stances():
		(stance[1] as Callable).call(_pose)
		_skel.pose(_pose)
		assert_gt(_from_the_dot_line(), _straight_on(), "%s" % stance[0])


# The lines from a puck `from_m` straight out to each post, ice to bar: how
# many get by him `depth` out.
func _lines_by_him(from_m: float, depth: float) -> int:
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var release := Vector3(0.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, depth - from_m)
	var top: float = GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
	var by: int = 0
	var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
	while y <= top:
		for side: float in [-1.0, 1.0]:
			if KeeperGear.nearest(_skel, release, Vector3(side * KeeperCoverage.MOUTH_HALF_M, y, depth),
					GameRules.PUCK_COLLISION_RADIUS, out, scratch) < 0:
				by += 1
		y += KeeperCoverage.CLOSING_STEP_M
	return by


# The closing share is where his outline stops hiding the posts: with that
# share of the puck's distance left between them nothing gets by him inside
# either post, a little further back something does; and a wider shape (the low
# ready's against the ready stance's) hides them from further back.
func test_the_closing_share_is_where_the_posts_come_into_view() -> void:
	var shares: Dictionary = {}
	for stance: Array in _stances().slice(0, 3):
		(stance[1] as Callable).call(_pose)
		_skel.pose(_pose)
		var share: float = KeeperCoverage.closing_share(_skel, CLOSING_FROM_M)
		shares[stance[0]] = share
		assert_between(share, 0.05, 0.95, "%s: somewhere in front of the goal line" % stance[0])
		assert_eq(_lines_by_him(CLOSING_FROM_M, CLOSING_FROM_M * (1.0 - share)), 0, "%s: hidden at it" % stance[0])
		assert_gt(_lines_by_him(CLOSING_FROM_M, CLOSING_FROM_M * (1.0 - share - 0.02)), 0,
				"%s: in view past it" % stance[0])
	assert_gt(shares["low_ready"], shares["ready"], "the low ready hides them from further back than the ready stance")


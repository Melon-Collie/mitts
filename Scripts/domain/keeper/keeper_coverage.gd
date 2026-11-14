class_name KeeperCoverage
extends RefCounted

# How much of the goal mouth his body covers as the puck sees it: shots from
# `release` at a grid of points across the mouth, each a straight line the swept
# disc of the puck's real radius follows, counted covered when it meets any
# piece of gear before the goal line. Keeper space in (the release and the goal
# line are where they are relative to him), so the same body answers for any
# spot on the ice.
#
# Straight lines from a fixed release: no gravity, no reaction. It measures the
# shape he presents, which is the planner's currency and the seam check's.

const STEP_M: float = 0.02
# Half the mouth a puck fits through, inside the iron.
const MOUTH_HALF_M: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
# closing_share's search: the share to within a part in 2^CLOSING_ROUNDS, a
# line to each post every CLOSING_STEP_M up it.
const CLOSING_ROUNDS: int = 8
const CLOSING_STEP_M: float = 0.04


# Fraction of the mouth covered, 0..1. The mouth is post to post and ice to bar,
# inside the iron, at `goal_line_z` in keeper space with its centre at `goal_x`.
static func fraction(skel: KeeperSkeleton, release: Vector3, goal_line_z: float,
		goal_x: float = 0.0, step: float = STEP_M) -> float:
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	var top: float = GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS - r
	var covered: int = 0
	var total: int = 0
	var x: float = -MOUTH_HALF_M
	while x <= MOUTH_HALF_M + 1e-6:
		var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
		while y <= top + 1e-6:
			total += 1
			var target := Vector3(goal_x + x, y, goal_line_z)
			if KeeperGear.nearest(skel, release, target, r, out, scratch) >= 0:
				covered += 1
			y += step
		x += step
	return float(covered) / float(maxi(total, 1))


# The most of a puck's distance to the net's centre he can leave between him
# and it, as a share of that distance, and still hide both posts from it, ice
# to bar: straight on from `from_m` out, square to it. Further back than that
# a shot gets by him inside a post without his moving.
static func closing_share(skel: KeeperSkeleton, from_m: float) -> float:
	var hidden: float = 0.0
	var open: float = 1.0
	for i: int in CLOSING_ROUNDS:
		var share: float = 0.5 * (hidden + open)
		if _hides_the_posts(skel, from_m, from_m * (1.0 - share)):
			hidden = share
		else:
			open = share
	return hidden


# Whether no shot from `from_m` out in front of the net's centre gets by him,
# `depth` out from his goal line, just inside either post.
static func _hides_the_posts(skel: KeeperSkeleton, from_m: float, depth: float) -> bool:
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	var top: float = GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS - r
	var release := Vector3(0.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, depth - from_m)
	var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
	while y <= top + 1e-6:
		for side: float in [-1.0, 1.0]:
			if KeeperGear.nearest(skel, release, Vector3(side * MOUTH_HALF_M, y, depth), r, out, scratch) < 0:
				return false
		y += CLOSING_STEP_M
	return true

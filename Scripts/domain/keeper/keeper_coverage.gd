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


# Fraction of the mouth covered, 0..1. The mouth is post to post and ice to bar,
# inside the iron, at `goal_line_z` in keeper space with its centre at `goal_x`.
static func fraction(skel: KeeperSkeleton, release: Vector3, goal_line_z: float,
		goal_x: float = 0.0, step: float = STEP_M) -> float:
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
			var target := Vector3(goal_x + x, y, goal_line_z)
			if KeeperGear.nearest(skel, release, target, r, out, scratch) >= 0:
				covered += 1
			y += step
		x += step
	return float(covered) / float(maxi(total, 1))

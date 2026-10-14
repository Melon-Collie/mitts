extends GutTest

# Shot-opportunity audit: how much of a broad grid of offensive-zone looks a
# bot has a committable direct shot from, split by the goalie state that
# produced the look. The fractions are the snapshot,
# snapshots/shot_opportunity.txt; the assertions are the orderings any honest
# keeper model keeps — the states team play creates (a keeper caught off his
# square, a keeper down) concede more than a set, squared one.
#
# Grid: shooters across the OZ fan (lateral x ±6, range 3–14 m), no defenders
# (the lane/pressure terms are audited elsewhere) — pure keeper-vs-shooter.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/shot_opportunity.txt"
const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
# "Committable" and "strong" bars for THIS audit's hole-geometry scores.
# Deliberately NOT AIRoleCarrier.SHOT_MIN_VALUE: that gate is denominated in the
# seam's NHL-calibrated currency and this file scores with
# AIActionScoring.score_shoot, which saturates at 1.0 — the two numbers are not
# comparable.
const FIRE_FLOOR: float = 0.02
const STRONG_LOOK: float = 0.3

var _shooters: Array[Vector3] = []


func before_each() -> void:
	_shooters.clear()
	for x: float in [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]:
		for dist: float in [3.0, 5.0, 7.0, 9.0, 11.0, 14.0]:
			var z: float = NET.z + dist
			# Keep the sample inside the zone fan (skip degenerate sharp
			# angles tighter than the goal line buffer allows).
			if absf(x) < dist * 1.2:
				_shooters.append(Vector3(x, 0.0, z))


# Goalie squared to `target` at `depth` out from the net centre.
func _squared_at(target: Vector3, depth: float) -> Vector3:
	var dir: Vector3 = target - NET
	dir.y = 0.0
	return NET + dir.normalized() * depth


# Fraction of the shooter grid whose direct shot clears the fire floor, for a
# goalie-state generator. `strong_out` (optional 1-element array) receives the
# fraction clearing STRONG_LOOK (a genuine chance, not a floor-scraper).
func _committable_fraction(state: Callable, strong_out: Array = []) -> float:
	var committable: int = 0
	var strong: int = 0
	var none: Array[Vector3] = []
	for shooter: Vector3 in _shooters:
		var args: Array = state.call(shooter)  # [goalie_pos, unsettled, five_gap, down]
		var s: float = AIActionScoring.score_shoot(
				shooter, NET, args[0], GameRules.NET_HALF_WIDTH, none, 33.0,
				args[1], [], args[2], args[3])
		if s > FIRE_FLOOR:
			committable += 1
		if s > STRONG_LOOK:
			strong += 1
	if not strong_out.is_empty():
		strong_out[0] = float(strong) / float(_shooters.size())
	return float(committable) / float(_shooters.size())


func test_shot_opportunity_distribution() -> void:
	# SET + SQUARED at challenge depth.
	var set_strong: Array = [0.0]
	var set_frac: float = _committable_fraction(func(sh: Vector3) -> Array:
		return [_squared_at(sh, 1.3), 0.0, -1.0, false],
		set_strong)

	# DISPLACED: keeper still square to a spot 3 m lateral of the shooter (the
	# stale square a cross-seam catch / lateral cut leaves behind).
	var displaced_strong: Array = [0.0]
	var displaced_frac: float = _committable_fraction(func(sh: Vector3) -> Array:
		var stale := Vector3(sh.x + (3.0 if sh.x <= 0.0 else -3.0), 0.0, sh.z)
		return [_squared_at(stale, 1.3), 1.0, -1.0, false],
		displaced_strong)

	# DOWN: butterflied keeper, squared, mid-slide leak on the pads.
	var down_strong: Array = [0.0]
	var down_frac: float = _committable_fraction(func(sh: Vector3) -> Array:
		return [_squared_at(sh, 1.0), 0.0,
				GoalieBehaviorRules.five_hole_gap_m(true, 0.12), true],
		down_strong)

	# DEEP: keeper holding passive depth (0.6 m — on his line), squared.
	var deep_frac: float = _committable_fraction(func(sh: Vector3) -> Array:
		return [_squared_at(sh, 0.6), 0.0, -1.0, false])

	assert_gt(displaced_frac, set_frac,
			"a keeper caught 3 m off his square concedes more looks than a set one")
	assert_gt(down_frac, set_frac,
			"a down keeper concedes more looks than a set, standing one")

	var snap := Snapshot.new(SNAPSHOT_PATH)
	snap.record("shooter looks in the grid", _shooters.size())
	snap.record("set and squared 1.3 m out, committable share", set_frac)
	snap.record("set and squared 1.3 m out, strong share", set_strong[0])
	snap.record("displaced 3 m off his square, committable share", displaced_frac)
	snap.record("displaced 3 m off his square, strong share", displaced_strong[0])
	snap.record("down and leaking, committable share", down_frac)
	snap.record("down and leaking, strong share", down_strong[0])
	snap.record("deep 0.6 m on his line, committable share", deep_frac)
	snap.verify(self)

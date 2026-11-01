extends GutTest

# docs/arm-anatomy-plan.md §11: the tick takes a skater's hips square to his
# FACING (SkaterSpineRig.shoulder_in_frame), the drawn hips turn toward his
# TRAVEL, and with the hips on the travel the spine's twist budget is measured
# from it. How far apart do the two get in play? Bots on bots in the duel
# harness, 3v3 and 5v5 from a loose puck at centre, every skater moving past
# MOVING_M_S each tick: the angle between his facing and his velocity, which
# bounds how far the drawn hips sit off the ones the tick assumes. The gait turns
# them at most SkaterController.hip_align_max_deg toward it, so that cap of the
# gap is printed too: how far they can actually sit off.
#
# An instrument: prints percentiles and asserts nothing (tests/CLAUDE.md).

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECONDS: float = 60.0
const MOVING_M_S: float = 2.0
# The spine's thoracolumbar twist (ArmAnatomySearch.TRUNK_TWIST_MAX), the
# budget a gap past it would eat into on its own.
const BUDGET_DEG: float = 45.0


func test_the_facing_against_the_travel() -> void:
	var probe := SkaterController.new()
	var cap: float = probe.hip_align_max_deg
	probe.free()
	for size: int in [3, 5]:
		var duel: RefCounted = Duel.new()
		_roster(duel, size)
		duel.start(-1, Vector3.ZERO)
		var all: PackedFloat32Array = []
		var carrying: PackedFloat32Array = []
		var steps: int = int(SECONDS / DT)
		for _t: int in steps:
			duel.step()
			for s: RefCounted in duel.skaters:
				var v := Vector2(s.vel.x, s.vel.z)
				if v.length() < MOVING_M_S:
					continue
				var gap: float = absf(rad_to_deg(v.angle_to(s.facing)))
				all.append(gap)
				if duel.carrier_id == s.peer_id:
					carrying.append(gap)
		gut.p("%dv%d, %.0f s:" % [size, size, SECONDS])
		gut.p("  every moving skater: %s" % _spread(all))
		gut.p("  carrying:            %s" % _spread(carrying))
		gut.p("  hips' turn, capped at %.0f°: every %s | carrying %s" % [cap, _capped(all, cap),
				_capped(carrying, cap)])
	assert_true(true)


func _roster(duel: RefCounted, size: int) -> void:
	var xs: Array[float] = [0.0, -6.0, 6.0, -3.0, 3.0]
	var zs: Array[float] = [6.0, 10.0, 10.0, 15.0, 15.0]
	var positions := {}
	for i: int in size:
		duel.add_skater(100 + i, 0, Vector3(xs[i], 0.0, zs[i]))
		duel.add_skater(200 + i, 1, Vector3(xs[i], 0.0, -zs[i]))
		positions[100 + i] = i
		positions[200 + i] = i
	if size == 5:
		duel.team_size = 5
		duel.positions = positions


func _spread(gaps: PackedFloat32Array) -> String:
	if gaps.is_empty():
		return "no samples"
	var sorted: PackedFloat32Array = gaps.duplicate()
	sorted.sort()
	var over: int = 0
	for g: float in sorted:
		if g > BUDGET_DEG:
			over += 1
	return "%d samples | p50 %.0f° p75 %.0f° p90 %.0f° p99 %.0f° max %.0f° | past %.0f° %.1f%%" % [
			sorted.size(), _at(sorted, 0.5), _at(sorted, 0.75), _at(sorted, 0.9), _at(sorted, 0.99),
			sorted[sorted.size() - 1], BUDGET_DEG, 100.0 * float(over) / float(sorted.size())]


func _capped(gaps: PackedFloat32Array, cap: float) -> String:
	var at_cap: int = 0
	var sum: float = 0.0
	for g: float in gaps:
		sum += minf(g, cap)
		if g >= cap:
			at_cap += 1
	return "mean %.0f°, at the cap %.0f%%" % [sum / maxf(float(gaps.size()), 1.0),
			100.0 * float(at_cap) / maxf(float(gaps.size()), 1.0)]


func _at(sorted: PackedFloat32Array, q: float) -> float:
	return sorted[clampi(int(q * float(sorted.size())), 0, sorted.size() - 1)]

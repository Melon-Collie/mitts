extends GutTest

# ── Somebody stays back while we cycle ───────────────────────────────────────
# Our team holds the puck low in the offensive zone; an opponent leaves his zone
# at speed toward our net. Nobody is coached to MARK that man — he is the other
# team's gamble, and they are a body short in their own zone for it. What is
# coached is the structure that makes the gamble cheap: a "help" player high in
# 3v3 (the 1-1-1), F3 and the points in 5v5, and the last layer counting numbers
# ("how many opponents are in front of them and if any are behind them") and
# backing off when one gets behind it. See docs/transition-defense-plan.md §13.
#
# So the read is not "was he covered" but "if the puck turned over now, is any
# of our bodies still goal-side of him": the best of our skaters' margin on the
# breaker, along the rink, 1.0 / 1.5 / 2.0 s after he goes. The carrier is
# scripted and cannot lose the puck, so possession never flips and every second
# of the run measures the shape, not a scramble. The breaker skates on the real
# stride ramp (script_skates), so the race is the one the bots actually run.
#
# Reference readings — best-body margin 2 s after the break, mean of 12 starts,
# and how many of the 12 end with nobody goal-side of him:
#
#                                          3v3                5v5
#   "behind" by position, SUPPORT blind   -11.4 m  12/12      -1.8 m  9/12
#   "behind" as a race, SUPPORT counts     -2.9 m  12/12      +0.1 m  6/12
#
# 3v3 is still beaten at 2 s: the help player stands ~2.7 m goal-side of a
# high-slot breaker and both start flat on the same ramp, so the race is close to
# even and his reaction decides it.

# Bars sit between the two rows, so either mode sliding back fails.
const MAX_3V3_MEAN_DEFICIT_M: float = 6.0
const MIN_5V5_MEAN_MARGIN_M: float = -1.0
const MAX_5V5_BEATEN: int = 7

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SETTLE_S: float = 2.5
const AFTER_S: float = 2.0
const MARKS_S: Array[float] = [1.0, 1.5, 2.0]
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z   # team 0 defends +Z


# Best-body margins on the breaker at MARKS_S. `five` builds the 5v5 shape
# (two forwards low, F3, two points), otherwise 3v3 (carrier + two bots).
func _run(five: bool, breaker_x: float, breaker_z: float,
		breaker_speed: float) -> Array[float]:
	var duel := Duel.new()
	# Us (team 0, attacking -Z): a scripted carrier cycling the right-wall corner.
	duel.add_scripted_attacker(1, 0, [Vector3(9.0, 0.0, -18.0),
			Vector3(10.0, 0.0, -23.0), Vector3(6.0, 0.0, -24.5),
			Vector3(10.0, 0.0, -23.0)] as Array[Vector3], 2.5)
	var ours: Array[int] = [2, 3]
	if five:
		duel.team_size = 5
		duel.positions = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4,
				10: 0, 11: 1, 12: 2, 13: 3, 14: 4}
		duel.add_skater(2, 0, Vector3(-6.0, 0.0, -20.0), BotSkillProfile.hard())
		duel.add_skater(3, 0, Vector3(0.5, 0.0, -16.0), BotSkillProfile.hard())
		duel.add_skater(4, 0, Vector3(6.0, 0.0, -9.0), BotSkillProfile.hard())
		duel.add_skater(5, 0, Vector3(-6.0, 0.0, -9.0), BotSkillProfile.hard())
		ours = [2, 3, 4, 5]
	else:
		duel.add_skater(2, 0, Vector3(-6.0, 0.0, -9.0), BotSkillProfile.hard())
		duel.add_skater(3, 0, Vector3(2.0, 0.0, -12.0), BotSkillProfile.hard())
	# Them (team 1): a checker on our carrier, and the breaker, parked until he
	# goes. 5v5 adds three more in their own zone.
	duel.add_scripted_attacker(10, 1, [Vector3(8.0, 0.0, -19.0),
			Vector3(8.5, 0.0, -22.0)] as Array[Vector3], 2.0)
	duel.add_scripted_attacker(11, 1,
			[Vector3(breaker_x, 0.0, breaker_z)] as Array[Vector3], 1.0)
	if five:
		duel.add_scripted_attacker(12, 1, [Vector3(-3.0, 0.0, -22.0)] as Array[Vector3], 1.0)
		duel.add_scripted_attacker(13, 1, [Vector3(2.0, 0.0, -24.0)] as Array[Vector3], 1.0)
		duel.add_scripted_attacker(14, 1, [Vector3(-6.0, 0.0, -18.0)] as Array[Vector3], 1.0)
	duel.start(1)

	var settle: int = int(SETTLE_S / DT)
	var margins: Array[float] = []
	for t: int in int((SETTLE_S + AFTER_S) / DT) + 1:
		if t == settle:
			var br: Object = duel._skater(11)
			br.script_path = [Vector3(breaker_x, 0.0, breaker_z),
					Vector3(breaker_x, 0.0, OUR_NET_Z - 2.0)] as Array[Vector3]
			br.script_idx = 1
			br.script_speed = breaker_speed
			br.script_skates = true
		duel.step()
		var since: float = float(t - settle) * DT
		for mark: float in MARKS_S:
			if absf(since - mark) < DT * 0.5:
				var best: float = -INF
				for pid: int in ours:
					best = maxf(best,
							duel._skater(pid).pos.z - duel._skater(11).pos.z)
				margins.append(best)
	return margins


# Sweeps both breaker depths (their low slot, their high slot), three lanes and
# two paces. Returns [mean margin at each mark..., beaten-at-the-last-mark count].
func _sweep(five: bool, label: String) -> Array[float]:
	var sums: Array[float] = [0.0, 0.0, 0.0]
	var beaten: int = 0
	var n: int = 0
	for speed: float in [6.0, 8.0]:
		for bz: float in [-20.0, -13.0]:
			var row: String = "  %s breaker %.0f m/s from z%+.0f :" % [label, speed, bz]
			for bx: float in [-6.0, 0.0, 6.0]:
				var m: Array[float] = _run(five, bx, bz, speed)
				n += 1
				for i: int in m.size():
					sums[i] += m[i]
				if m[m.size() - 1] < 0.0:
					beaten += 1
				row += "  x%+.0f %+5.1f/%+5.1f/%+5.1f" % [bx, m[0], m[1], m[2]]
			gut.p(row)
	var out: Array[float] = []
	for s: float in sums:
		out.append(s / float(n))
	out.append(float(beaten))
	gut.p("  → %s mean best-body margin at 1.0/1.5/2.0 s: %+.1f / %+.1f / %+.1f m | beaten at 2 s: %d/%d"
			% [label, out[0], out[1], out[2], beaten, n])
	return out


func test_3v3_keeps_a_body_back_while_we_cycle() -> void:
	var r: Array[float] = _sweep(false, "3v3")
	assert_gt(r[2], -MAX_3V3_MEAN_DEFICIT_M,
			"3v3: the help player is not getting back on a breaking man")


func test_5v5_keeps_a_body_back_while_we_cycle() -> void:
	var r: Array[float] = _sweep(true, "5v5")
	assert_gt(r[2], MIN_5V5_MEAN_MARGIN_M,
			"5v5: the back layer is not getting back on a breaking man")
	assert_lte(int(r[3]), MAX_5V5_BEATEN,
			"5v5: too many breaks end with nobody goal-side of him")

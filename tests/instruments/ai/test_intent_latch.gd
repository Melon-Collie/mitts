extends "res://tests/instruments/ai/test_pass_carry_calibration.gd"

# How often does the carrier change his mind while the agent holds his fire
# intent? From the moment the carrier commits to a shot, a pass, a rim or a
# dump-in, the agent latches it through the pre-aim (skater_agent_state_machine
# .gd:_state_carry) and stops reading the carrier's intent until the press. The
# carrier keeps re-deciding meanwhile. Every latch episode, for every carrier on
# either side, over the O-zone starts at the real keeper, the neutral-zone
# entries, the stacked line and the breakouts, is logged against the carrier's
# fresh reads tick by tick: the latched action's own score (its hysteresis bonus
# taken off), the best of the others, whether the latched action fell below its
# giveaway bar or was gone, how long the pre-aim ran and how it ended. Summed by
# how far the best other read beat the latched one at its widest.

const DumpIn := preload("res://tests/instruments/ai/test_dump_in_drill.gd")
const KINDS: Array[String] = ["shot", "pass", "rim", "dump", "carry"]

var _episodes: Array = []
# Per carrier peer: the episode he is in, or none.
var _open: Dictionary = {}


func test_report_pass_and_carry_calibration() -> void:
	pending("the calibration is test_pass_carry_calibration.gd's own")


func test_intent_latch() -> void:
	for start: Array in Ozone.new()._starts():
		var vels: Array = [Vector3.ZERO] + start[3]
		for combo: int in 2 * vels.size() * 2:
			var m := Vector3(1.0 if combo % 2 == 0 else -1.0, 1.0, 1.0)
			var vel: Vector3 = vels[(combo >> 1) % vels.size()] * m
			var tight: bool = combo >= 2 * vels.size()
			_watch(_setup(start[0] * m, vel, start[1] * m, start[2] * m, tight), 12.0)
	for n_def: int in [2, 3]:
		for x: float in [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]:
			for v: float in [1.0, 3.0, 5.0, 7.0]:
				_watch(_entry(x, v, n_def), 8.0)
	var stacked: Object = DumpIn.new()
	for x: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for v: float in [5.0, 6.5, 8.0]:
			for gap: float in [0.0, 1.0, 2.0]:
				_watch(stacked._stacked(x, v, gap), 8.0)
	stacked.free()
	for cx: float in [-8.0, -3.0, 0.0, 4.0, 9.0]:
		for cz: float in [20.0, 24.0]:
			for f1_gap: float in [4.0, 7.0]:
				var carrier := Vector3(cx, 0, cz)
				_watch(_breakout(carrier, carrier + Vector3(-signf(cx + 0.1), 0, -f1_gap),
						Vector3(-cx * 0.5, 0, 12.0)), 8.0)
	_report()
	assert_true(true)


func _watch(duel: Object, secs: float) -> void:
	_open.clear()
	for i: int in int(secs / Duel.DT):
		duel.step()
		var c: int = duel.carrier()
		# A carrier who no longer has the puck ends his episode.
		for pid: int in _open.keys():
			if pid != c:
				_close(pid, "lost the puck")
		if c == -1:
			continue
		var sm: Object = duel._skater(c).agent
		if sm == null:
			continue
		var latched: bool = sm._state == SkaterAgentStateMachine.State.CARRY \
				and sm._intended_action != SkaterAgentStateMachine.State.CARRY
		if not latched:
			if _open.has(c):
				_close(c, "pressed" if sm._state != SkaterAgentStateMachine.State.CARRY
						else "dropped")
			continue
		var kind: int = _latched_kind(sm)
		if not _open.has(c):
			_open[c] = {"kind": kind, "ticks": 0, "ratio": 0.0, "alt": -1, "alt_v": 0.0,
					"own_v": 0.0, "gone": false, "flipped": false, "first": _raw(sm._carrier)[kind],
					"none": false, "beaten": 0.0, "beaten_by": -1, "beaten_own": 0.0, "beaten_alt": 0.0,
					"beaten_at": 0.0}
		var e: Dictionary = _open[c]
		e["ticks"] += 1
		var raw: Array[float] = _raw(sm._carrier)
		var own: float = raw[kind]
		var bar: float = AIRoleCarrier.SHOT_MIN_VALUE if kind == 0 else AIRoleCarrier.PASS_MIN_VALUE
		if own <= bar:
			e["gone"] = true
		# Gone outright: the search no longer offers it (a dump or a pass it found
		# none of, a shot from behind the line or out of the zone).
		if own <= 0.0:
			e["none"] = true
		if _carrier_kind(sm._carrier) != kind:
			e["flipped"] = true
		for k: int in KINDS.size():
			if k == kind or (kind in [1, 2] and k in [1, 2]):
				continue
			var r: float = raw[k] / own if own > 0.0 else (INF if raw[k] > 0.0 else 0.0)
			if r > e["ratio"]:
				e["ratio"] = r
				e["alt"] = k
				e["alt_v"] = raw[k]
				e["own_v"] = own
			# Beaten while it is still on: the widest ratio with the latched action
			# alive, and how far into the pre-aim.
			if own > 0.0 and r > e["beaten"]:
				e["beaten"] = r
				e["beaten_by"] = k
				e["beaten_own"] = own
				e["beaten_alt"] = raw[k]
				e["beaten_at"] = e["ticks"] * Duel.DT


func _close(pid: int, how: String) -> void:
	var e: Dictionary = _open[pid]
	e["how"] = how
	_episodes.append(e)
	_open.erase(pid)


# The action the agent holds: a shot, or on the pass press a dump-in (a dump to
# the ice), a rim (a dump to a receiver) or a pass.
static func _latched_kind(sm: Object) -> int:
	if sm._intended_action == SkaterAgentStateMachine.State.SHOOT_PRESSED:
		return 0
	if sm._dump_target.is_finite():
		return 3 if sm._pass_target_peer_id == -1 else 2
	return 1


# What the carrier's compete currently intends, in KINDS' order.
static func _carrier_kind(carrier: AIRoleCarrier) -> int:
	match carrier.intended_action:
		AIRoleCarrier.INTENT_SHOOT:
			return 0
		AIRoleCarrier.INTENT_PASS:
			return 1
		AIRoleCarrier.INTENT_DUMP:
			return 3 if carrier._dumping_in else 2
	return 4


# The carrier's fresh reads in KINDS' order, the hysteresis bonus his compete puts
# on the action he intends taken off (a rim's is the pass's score).
static func _raw(carrier: AIRoleCarrier) -> Array[float]:
	var bonus: float = 1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC
	var shot: float = carrier.debug_shoot_score
	var feed: float = carrier.debug_pass_score
	var ck: int = _carrier_kind(carrier)
	if ck == 0 and shot > 0.0:
		shot /= bonus
	if ck in [1, 2] and feed > 0.0:
		feed /= bonus
	return [shot, feed, feed, carrier._phase_dump_score, carrier.debug_carry_score]


func _report() -> void:
	gut.p("latch episodes: %d" % _episodes.size())
	gut.p("  per latched action: episodes, pre-aim median and max (s), gone outright, and beaten")
	gut.p("  while still on by the best other read at its widest:")
	gut.p("     latched   n   pre-aim med/max   gone   <1.15  1.15-1.5  1.5-2  2-3   >=3")
	for k: int in 4:
		var rows: Array = _episodes.filter(func(e: Dictionary) -> bool: return e["kind"] == k)
		if rows.is_empty():
			continue
		var bins: Array[int] = [0, 0, 0, 0, 0]
		var gone: int = 0
		var ticks: Array[int] = []
		for e: Dictionary in rows:
			var r: float = e["beaten"]
			var b: int = 0 if r < 1.15 else (1 if r < 1.5 else (2 if r < 2.0 else (3 if r < 3.0 else 4)))
			bins[b] += 1
			gone += 1 if e["none"] else 0
			ticks.append(e["ticks"])
		ticks.sort()
		gut.p("     %-6s %4d    %4.2f / %4.2f      %4d   %4d   %5d     %4d  %4d  %4d" % [
				KINDS[k], rows.size(), ticks[ticks.size() / 2] * Duel.DT, ticks[-1] * Duel.DT, gone,
				bins[0], bins[1], bins[2], bins[3], bins[4]])
	gut.p("  every episode beaten by 1.5x or more while still on, or gone outright:")
	gut.p("     latched  committed  beaten: own  by     alt    ratio  at (s)   gone   pre-aim (s)  ended")
	for e: Dictionary in _episodes:
		if e["beaten"] >= 1.5 or e["none"]:
			gut.p("     %-6s   %7.3f      %7.3f  %-5s %6.3f  %5.2f  %5.2f    %-4s   %5.2f        %s" % [
					KINDS[e["kind"]], e["first"], e["beaten_own"],
					KINDS[e["beaten_by"]] if e["beaten_by"] >= 0 else "-", e["beaten_alt"],
					minf(e["beaten"], 99.0), e["beaten_at"], "yes" if e["none"] else "",
					e["ticks"] * Duel.DT, e["how"]])

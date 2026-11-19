extends GutTest

# Do the two 5v5 zone wingers swap labels in D-zone coverage, and what does it
# cost? Each fixture runs twice on the real decision stack (the duel harness):
# as shipped, where only a zone D keeps his label while his man needs it
# (TeamBrain._keep_the_labels_men_need), and with that rule extended to the
# ZONE_W_STRONG / ZONE_W_WEAK pair (WingerKeepBrain below, this file only).
#
# Per fixture and rule, over the ticks the defence is in its D-zone shape:
#   W swaps — the two winger bodies exchanging ZONE_W_STRONG and ZONE_W_WEAK
#     between brain ticks, split by whether the brain's strong side flipped
#     the same tick (the labels mirror with it, and that swap is the shape
#     working). D swaps — the same for the D pair, for context.
#   After each swap the strong side did not cause, until the next one or
#     WINDOW_S: each winger's lateral travel |Δx| from where he swapped, the
#     share of those swaps where the two crossed each other (their x order
#     reversed), and the ticks with an in-zone man nobody has / a man two
#     defenders have.
#   Whole run — men nobody has per tick and the share of ticks a man is
#     double-covered, read off each defender's own lock as
#     test_zone_coverage_shape.gd reads them.
# Under the table, per run: the unattended ticks by man, and one line per swap
# (who, where, the strong side, each body's man before -> after, and for a
# swap without a flip where the two stood when its window closed).
#
# Asserts nothing: it is read by a person deciding whether the winger pair
# keeps its labels too. The low cycle's attack is bots, so its two rows are
# two rollouts rather than one possession defended two ways; every other
# attack is scripted.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const NET_Z: float = -GameRules.GOAL_LINE_Z   # team 1 defends -Z
const WINDOW_S: float = 1.5
const ZONE_SLOTS: Array[int] = [
	AIRoleSlots.Slot.ZONE_D_STRONG, AIRoleSlots.Slot.ZONE_D_WEAK,
	AIRoleSlots.Slot.ZONE_C, AIRoleSlots.Slot.ZONE_W_STRONG,
	AIRoleSlots.Slot.ZONE_W_WEAK,
]
# Low pair, slot, points (test_zone_coverage_shape.gd's seats).
const SEATS_5V5: Array[int] = [3, 4, 0, 1, 2]


# The shipped brain plus the D rule extended to the winger pair.
class WingerKeepBrain extends TeamBrain:
	func _keep_the_labels_men_need(snapshot: WorldSnapshot) -> void:
		super(snapshot)
		if state != AIPossessionState.State.DZONE or snapshot == null \
				or snapshot.puck_state == null:
			return
		var pressure_slot: int = AIZoneCoverage.pressure_slot(self, _strong_x, _own_goal_z,
				snapshot.puck_state.position)
		for pid: int in threat_assignments:
			var label: int = slot_assignments.get(pid, AIRoleSlots.Slot.NONE)
			var partner: int = AIRoleSlots.Slot.NONE
			if label == AIRoleSlots.Slot.ZONE_W_STRONG:
				partner = AIRoleSlots.Slot.ZONE_W_WEAK
			elif label == AIRoleSlots.Slot.ZONE_W_WEAK:
				partner = AIRoleSlots.Slot.ZONE_W_STRONG
			var man: SkaterNetworkState = snapshot.skater_states.get(threat_assignments[pid])
			if partner == AIRoleSlots.Slot.NONE or man == null:
				continue
			if _may_be_handed(label, pressure_slot, man.position,
					AIZoneCoverage.AREA_RELEASE_MARGIN_M) \
					and not _may_be_handed(partner, pressure_slot, man.position,
							AIZoneCoverage.AREA_RELEASE_MARGIN_M):
				_kept_zone_labels[pid] = label


class Fixture:
	var label: String
	# Each attacker: a spawn (a bot) or [path, speed] (scripted).
	var attackers: Array
	var defenders: Array[Vector3]
	var seats: Array[int]
	var secs: float

	static func make(p_label: String, p_attackers: Array, p_defenders: Array[Vector3],
			p_seats: Array[int] = SEATS_5V5, p_secs: float = 4.0) -> Fixture:
		var f := Fixture.new()
		f.label = p_label
		f.attackers = p_attackers
		f.defenders = p_defenders
		f.seats = p_seats
		f.secs = p_secs
		return f


class Tally:
	var dzone_ticks: int = 0
	var w_swaps: int = 0
	var w_flip_swaps: int = 0
	var d_swaps: int = 0
	var travel_sum: float = 0.0
	var travel_n: int = 0
	var travel_max: float = 0.0
	var crossed: int = 0
	var window_ticks: int = 0
	var window_uncovered: int = 0
	var window_doubled: int = 0
	var uncovered_sum: int = 0
	var doubled_ticks: int = 0
	# Unattended ticks by attacker peer id.
	var uncovered_by_man: Dictionary = {}
	# One line per swap, printed under the table.
	var events: Array[String] = []


# One open after-swap window: the two wingers, where they stood, when it ends,
# and its line in Tally.events.
class SwapWindow:
	var a: int
	var b: int
	var ax: float
	var bx: float
	var end_tick: int
	var event: int


func _at(x: float, depth: float) -> Vector3:
	return Vector3(x, 0.0, NET_Z + depth)


func _path(points: Array, speed: float) -> Array:
	var p: Array[Vector3] = []
	for pt: Vector2 in points:
		p.append(_at(pt.x, pt.y))
	return [p, speed]


func _fixtures() -> Array[Fixture]:
	var low_cycle_d: Array[Vector3] = [_at(4.0, 4.65), _at(-2.0, 2.15), _at(0.0, 7.65),
			_at(7.0, 13.65), _at(-7.0, 13.65)]
	var point_d: Array[Vector3] = [_at(1.0, 3.65), _at(-1.5, 2.15), _at(0.5, 7.15),
			_at(6.0, 12.65), _at(-6.0, 12.15)]
	var pk_seats: Array[int] = [3, 4, 0, 1]
	var pk_d: Array[Vector3] = [_at(2.0, 3.0), _at(-2.0, 3.0), _at(1.0, 7.0), _at(6.0, 11.0)]
	var pk_posts: Array = [
		_path([Vector2(6.0, 14.0), Vector2(10.0, 8.0), Vector2(9.0, 2.0), Vector2(10.0, 8.0)], 4.0),
		_path([Vector2(-1.5, 2.65)], 0.0), _path([Vector2(0.5, 7.0)], 0.0),
		_path([Vector2(-9.0, 8.0)], 0.0), _path([Vector2(-6.0, 14.0)], 0.0)]
	var pk_d_off_seats: Array[int] = [4, 0, 1, 2]
	return [
		# test_zone_coverage_shape.gd's three.
		Fixture.make("low cycle (bots)",
				[_at(9.0, 4.65), _at(-1.5, 2.65), _at(0.5, 6.65), _at(6.0, 12.65),
				 _at(-6.0, 12.65)], low_cycle_d),
		Fixture.make("point shot", [
				_path([Vector2(5.0, 11.65), Vector2(1.5, 11.15)], 2.0),
				_path([Vector2(-0.5, 2.15), Vector2(0.5, 2.65)], 1.0),
				_path([Vector2(2.5, 5.65), Vector2(0.5, 6.15)], 1.5),
				_path([Vector2(-8.0, 8.65), Vector2(-7.0, 6.15)], 1.5),
				_path([Vector2(-5.0, 11.65), Vector2(-3.0, 11.15)], 1.5)], point_d),
		Fixture.make("crossing cutter", [
				_path([Vector2(9.0, 5.65), Vector2(8.5, 3.15)], 1.5),
				_path([Vector2(-7.0, 7.65), Vector2(-1.0, 6.15), Vector2(4.0, 7.15),
						Vector2(-1.0, 6.15)], 3.0),
				_path([Vector2(-1.0, 2.65), Vector2(0.0, 2.15)], 1.0),
				_path([Vector2(6.0, 12.65), Vector2(4.0, 12.15)], 1.5),
				_path([Vector2(-6.0, 12.65), Vector2(-4.0, 12.15)], 1.5)],
				[_at(4.0, 4.65), _at(-1.5, 2.15), _at(0.0, 7.65), _at(7.0, 13.15),
				 _at(-7.0, 13.15)]),
		# The carrier walks the line across and the other point man the other
		# way: the strong side flips mid-possession.
		Fixture.make("point to point", [
				_path([Vector2(5.0, 11.65), Vector2(-5.0, 11.15)], 3.0),
				_path([Vector2(-0.5, 2.15), Vector2(0.5, 2.65)], 1.0),
				_path([Vector2(-5.0, 11.65), Vector2(5.0, 12.15)], 3.0),
				_path([Vector2(9.0, 7.0), Vector2(8.5, 7.5)], 0.5),
				_path([Vector2(-9.0, 7.0), Vector2(-8.5, 7.5)], 0.5)], point_d),
		# The carrier walks up the strong wall from the corner while the strong
		# point drops down it: the cycle.
		Fixture.make("wall cycle", [
				_path([Vector2(9.0, 1.0), Vector2(8.5, 10.0)], 2.5),
				_path([Vector2(-0.5, 2.15), Vector2(0.5, 2.65)], 1.0),
				_path([Vector2(6.0, 12.0), Vector2(8.5, 5.0)], 2.5),
				_path([Vector2(0.5, 6.65), Vector2(-0.5, 6.15)], 1.0),
				_path([Vector2(-6.0, 12.0), Vector2(-4.0, 11.5)], 1.0)], low_cycle_d),
		# The weak point drops down the weak wall as the weak half-wall man goes
		# up to the point: a rotation on the wingers' side of the ice.
		Fixture.make("weak rotation", [
				_path([Vector2(5.0, 11.65), Vector2(3.0, 11.15)], 1.0),
				_path([Vector2(-0.5, 2.15), Vector2(0.5, 2.65)], 1.0),
				_path([Vector2(1.5, 6.15), Vector2(0.5, 6.65)], 1.0),
				_path([Vector2(-5.0, 11.65), Vector2(-9.0, 6.0)], 2.5),
				_path([Vector2(-9.0, 6.0), Vector2(-5.0, 11.65)], 2.5)], point_d),
		# test_penalty_kill_shape.gd's kill: the wedge and one has one winger.
		Fixture.make("PK, a forward off", pk_posts, pk_d, pk_seats, 12.0),
		Fixture.make("PK, a D off", pk_posts, pk_d, pk_d_off_seats, 12.0),
	]


func _run(f: Fixture, extended: bool) -> Tally:
	var duel := Duel.new()
	duel.team_size = 5
	for i: int in f.attackers.size():
		if f.attackers[i] is Array:
			var path: Array[Vector3] = []
			path.assign(f.attackers[i][0])
			duel.add_scripted_attacker(1 + i, 0, path, f.attackers[i][1])
		else:
			duel.add_skater(1 + i, 0, f.attackers[i], BotSkillProfile.hard())
		duel.positions[1 + i] = i
	for i: int in f.defenders.size():
		duel.add_skater(50 + i, 1, f.defenders[i], BotSkillProfile.hard())
		duel.positions[50 + i] = f.seats[i]
	duel.start(1)
	if extended:
		_swap_in_winger_keep_brain(duel)

	var r := Tally.new()
	var brain: TeamBrain = duel.brains[1]
	var prev_slots: Dictionary = {}
	var prev_men: Dictionary = {}
	var prev_strong: float = brain.strong_x()
	var windows: Array[SwapWindow] = []
	var window_ticks: int = int(WINDOW_S / DT)
	for t: int in int(f.secs / DT):
		duel.step()
		var snap: WorldSnapshot = duel._build_snapshot()
		if snap.puck_state == null or brain.state != AIPossessionState.State.DZONE:
			prev_slots.clear()
			_close_all(duel, windows, r)
			continue
		r.dzone_ticks += 1
		var flipped: bool = brain.strong_x() != prev_strong
		prev_strong = brain.strong_x()
		if not prev_slots.is_empty():
			var d_pair: Array[int] = _pair_swapped(prev_slots, brain.slot_assignments,
					AIRoleSlots.Slot.ZONE_D_STRONG, AIRoleSlots.Slot.ZONE_D_WEAK)
			if not d_pair.is_empty():
				r.d_swaps += 1
				r.events.append(_event("D", t, d_pair, flipped, duel, brain, prev_men))
			var w_pair: Array[int] = _pair_swapped(prev_slots, brain.slot_assignments,
					AIRoleSlots.Slot.ZONE_W_STRONG, AIRoleSlots.Slot.ZONE_W_WEAK)
			if not w_pair.is_empty():
				r.events.append(_event("W", t, w_pair, flipped, duel, brain, prev_men))
				if flipped:
					r.w_flip_swaps += 1
				else:
					r.w_swaps += 1
					_close_all(duel, windows, r)
					var w := SwapWindow.new()
					w.a = w_pair[0]
					w.b = w_pair[1]
					w.ax = duel.skater_pos(w.a).x
					w.bx = duel.skater_pos(w.b).x
					w.end_tick = t + window_ticks
					w.event = r.events.size() - 1
					windows.append(w)
		prev_slots = brain.slot_assignments.duplicate()
		prev_men = brain.threat_assignments.duplicate()

		var open: bool = not windows.is_empty()
		var uncovered: int = _uncovered(duel, brain, snap, r)
		var doubled: bool = _doubled(duel, brain)
		r.uncovered_sum += uncovered
		if doubled:
			r.doubled_ticks += 1
		if open:
			r.window_ticks += 1
			if uncovered > 0:
				r.window_uncovered += 1
			if doubled:
				r.window_doubled += 1
			if t >= windows[0].end_tick:
				_close_all(duel, windows, r)
	_close_all(duel, windows, r)
	return r


# Rebuilds team 1's brain as a WingerKeepBrain and re-seats its agents on it,
# as Duel.start seats them.
func _swap_in_winger_keep_brain(duel: Duel) -> void:
	var brain := WingerKeepBrain.new(1, duel.team_map, duel.caps_by_peer, duel.team_size,
			duel.positions)
	duel.brains[1] = brain
	var caps: AISkaterCaps = Duel.match_caps()
	for s: Duel.SimSkater in duel.skaters:
		if s.team_id != 1 or s.agent == null:
			continue
		s.agent = Duel.Agent.new()
		s.agent.setup(s.peer_id, s.team_id, brain, duel.team_map, caps.is_left_handed,
				duel.caps_by_peer)
		s.agent.apply_capabilities(caps)
		if s.profile != null:
			s.agent.apply_profile(s.profile)


# The two bodies that exchanged `slot_a` and `slot_b` since `before`, or [].
func _pair_swapped(before: Dictionary, now: Dictionary, slot_a: int, slot_b: int) -> Array[int]:
	var swapped: Array[int] = []
	var had_a: int = -1
	var had_b: int = -1
	for pid: int in before:
		if before[pid] == slot_a:
			had_a = pid
		elif before[pid] == slot_b:
			had_b = pid
	if had_a == -1 or had_b == -1:
		return swapped
	if now.get(had_a, -1) == slot_b and now.get(had_b, -1) == slot_a:
		swapped.append(had_a)
		swapped.append(had_b)
	return swapped


func _close_all(duel: Duel, windows: Array[SwapWindow], r: Tally) -> void:
	for w: SwapWindow in windows:
		var ax: float = duel.skater_pos(w.a).x
		var bx: float = duel.skater_pos(w.b).x
		for travel: float in [absf(ax - w.ax), absf(bx - w.bx)]:
			r.travel_sum += travel
			r.travel_n += 1
			r.travel_max = maxf(r.travel_max, travel)
		var crossed: bool = signf(w.ax - w.bx) != signf(ax - bx)
		if crossed:
			r.crossed += 1
		r.events[w.event] += " -> x %.1f / %.1f%s" % [ax, bx, " CROSSED" if crossed else ""]
	windows.clear()


# A swap's line: when, who, where each stood, the strong side, and each body's
# man before -> after.
func _event(kind: String, t: int, pair: Array[int], flipped: bool, duel: Duel,
		brain: TeamBrain, prev_men: Dictionary) -> String:
	return "%s swap t=%.2fs %d<->%d at x %.1f / %.1f, strong %+.0f%s, men %d->%d / %d->%d" % [
			kind, t * DT, pair[0], pair[1], duel.skater_pos(pair[0]).x,
			duel.skater_pos(pair[1]).x, brain.strong_x(), " (flip)" if flipped else "",
			prev_men.get(pair[0], -1), brain.threat_assignments.get(pair[0], -1),
			prev_men.get(pair[1], -1), brain.threat_assignments.get(pair[1], -1)]


# In-zone attackers other than the carrier whom no zone defender has locked.
func _uncovered(duel: Duel, brain: TeamBrain, snap: WorldSnapshot, r: Tally) -> int:
	var covered: Dictionary = {}
	for pid: int in brain.slot_assignments:
		if not ZONE_SLOTS.has(brain.slot_assignments[pid]):
			continue
		var agent: Object = duel._skater(pid).agent
		if agent != null and agent._prev_locked_man_pid != -1:
			covered[agent._prev_locked_man_pid] = true
	var n: int = 0
	for opp: int in snap.skater_states:
		if duel.team_map.get(opp, -1) == 1 or opp == snap.puck_state.carrier_peer_id:
			continue
		if snap.skater_states[opp].position.z >= -GameRules.BLUE_LINE_Z:
			continue
		if not covered.has(opp):
			n += 1
			r.uncovered_by_man[opp] = int(r.uncovered_by_man.get(opp, 0)) + 1
	return n


func _doubled(duel: Duel, brain: TeamBrain) -> bool:
	var seen: Dictionary = {}
	for pid: int in brain.slot_assignments:
		if not ZONE_SLOTS.has(brain.slot_assignments[pid]):
			continue
		var agent: Object = duel._skater(pid).agent
		var man: int = agent._prev_locked_man_pid if agent != null else -1
		if man == -1:
			continue
		if seen.has(man):
			return true
		seen[man] = true
	return false


func test_winger_label_swaps() -> void:
	gut.p("  ── 5v5 zone winger label swaps: as shipped vs the D rule extended to the wingers ──")
	gut.p("  W swaps: without / with a strong-side flip. After each swap without a flip, until"
			+ " the next or %.1f s: winger |dx| mean/max, swaps where they crossed, ticks in"
			% WINDOW_S + " the window with a man nobody has / a man two have.")
	gut.p("  %-18s %-8s %5s | %-9s %3s | %-11s %-7s %-14s | %-9s %-7s"
			% ["fixture", "rule", "dzone", "W swaps", "D", "|dx| m", "crossed",
			"window unc/dbl", "unc/tick", "dbl %"])
	var details: Array[String] = []
	for f: Fixture in _fixtures():
		for extended: bool in [false, true]:
			var r: Tally = _run(f, extended)
			var rule: String = "extended" if extended else "shipped"
			details.append("  %s, %s: unattended ticks by man %s" % [f.label, rule,
					str(r.uncovered_by_man)])
			for e: String in r.events:
				details.append("    " + e)
			var n: float = float(maxi(r.dzone_ticks, 1))
			var travel: String = "-" if r.travel_n == 0 else "%.1f/%.1f" % [
					r.travel_sum / r.travel_n, r.travel_max]
			gut.p("  %-18s %-8s %5d | %3d / %-3d %3d | %-11s %-7s %3d/%-3d of %-4d | %-9.2f %-7.1f"
					% [f.label, rule, r.dzone_ticks,
					r.w_swaps, r.w_flip_swaps, r.d_swaps, travel,
					"%d/%d" % [r.crossed, r.w_swaps], r.window_uncovered, r.window_doubled,
					r.window_ticks, r.uncovered_sum / n, 100.0 * r.doubled_ticks / n])
	for line: String in details:
		gut.p(line)
	assert_true(true)

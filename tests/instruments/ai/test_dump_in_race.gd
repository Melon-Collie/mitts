extends "res://tests/instruments/ai/test_nz_entry_drill.gd"

# Is the dump-in's race honest? The entry drill's starts (test_nz_entry_drill.gd)
# and the stacked line's (test_dump_in_drill.gd), real bots in the duel harness.
# Every dump-in our carrier commits to is logged with what AICarrierDumpSearch
# priced at the commit (its debug latch: the odds we play it first, each side's
# time to it, where each side meets it), what he had besides (the dump's value
# against his best carry and best pass then), and what happened: who touched it
# first, where and when. Summed by the odds priced: how many, how many we won
# back, and how dire the carry was.

const DumpIn := preload("res://tests/instruments/ai/test_dump_in_drill.gd")
const FOLLOW_S: float = 6.0

var _rows: Array = []


func test_neutral_zone_entries() -> void:
	pending("the entry sweep is test_nz_entry_drill.gd's own")


func test_dump_in_races() -> void:
	var runs: int = 0
	for n_def: int in [2, 3]:
		for x: float in [-11.0, -9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0, 11.0]:
			for v: float in [1.0, 3.0, 5.0, 7.0]:
				_follow(_setup(x, v, n_def), "3v%d/x%+.0f/v%.0f" % [n_def, x, v])
				runs += 1
	var stacked: Object = DumpIn.new()
	for x: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for v: float in [5.0, 6.5, 8.0]:
			for gap: float in [0.0, 1.0, 2.0]:
				_follow(stacked._stacked(x, v, gap), "stack/x%+.0f/v%.1f/g%.0f" % [x, v, gap])
				runs += 1
	stacked.free()
	gut.p("dumps: %d of %d starts" % [_rows.size(), runs])
	gut.p("  start             p     t ours  t theirs  priced meet ours / theirs      pace     at commit: dump  carry   pass   first played")
	for r: Array in _rows:
		gut.p("  %-17s %4.2f  %5.2f   %5.2f    (%5.1f,%5.1f) / (%5.1f,%5.1f)   %4.1f     %6.3f  %6.3f  %6.3f   %s" % r)
	gut.p("  by priced odds:  n  priced  won  | carry at commit: median, share below 0")
	for band: Array in [[0.0, 0.2], [0.2, 0.4], [0.4, 0.6], [0.6, 1.01]]:
		var n: int = 0
		var p_sum: float = 0.0
		var won: int = 0
		var carries: Array[float] = []
		for r: Array in _rows:
			if r[1] < band[0] or r[1] >= band[1]:
				continue
			n += 1
			p_sum += r[1]
			carries.append(r[10])
			if str(r[12]).begins_with("ours"):
				won += 1
		if n == 0:
			continue
		carries.sort()
		var below: int = 0
		for c: float in carries:
			if c < 0.0:
				below += 1
		gut.p("    %.1f-%.1f      %3d   %4.2f  %3d  | %6.3f, %d of %d" % [band[0], minf(band[1], 1.0), n,
				p_sum / n, won, carries[carries.size() / 2], below, n])
	assert_true(true)


# Runs one start until our carrier dumps it in, then follows the dump until
# somebody plays it or FOLLOW_S has passed.
func _follow(duel: Object, label: String) -> void:
	var commit: Array = []
	for i: int in int(SECS / Duel.DT):
		var before: int = duel.releases.size()
		duel.step()
		var c: int = duel.carrier()
		if c != -1 and duel.team_map[c] == 0:
			var sm: Object = duel._skater(c).agent
			var carrier: AIRoleCarrier = sm._carrier
			# The first tick he is committed to the dump-in, by the compete or already
			# pressing it (the press clears the intent the tick it starts): its race,
			# and what he had besides then.
			var pressing: bool = sm._state == SkaterAgentStateMachine.State.PASS_PRESSED \
					and sm._dump_target.is_finite() and sm._pass_target_peer_id == -1
			if pressing or (carrier.intended_action == AIRoleCarrier.INTENT_DUMP
					and carrier._dumping_in):
				if commit.is_empty():
					var dump: AICarrierDumpSearch = carrier._dump
					commit = [dump.debug_race, dump.best_meet, dump.debug_meet_theirs,
							dump.best_dir, dump.best_pace, dump.debug_origin, dump.best_score,
							carrier.debug_carry_score, carrier.debug_pass_score]
			else:
				commit = []
		if duel.releases.size() > before and not commit.is_empty() \
				and int(duel.releases[-1]["team"]) == 0:
			_track(duel, label, commit)
			return
		if c != -1 and (duel.team_map[c] == 1 or duel.puck_pos.z < _line()):
			return


func _track(duel: Object, label: String, commit: Array) -> void:
	var race: Vector4 = commit[0]
	var played: String = "nobody in %.0f s" % FOLLOW_S
	for i: int in int(FOLLOW_S / Duel.DT):
		duel.step()
		var c: int = duel.carrier()
		if c != -1:
			played = "%s %d at %.2f s, (%.1f,%.1f)" % ["ours" if duel.team_map[c] == 0 else "theirs",
					c, (i + 1) * Duel.DT, duel.puck_pos.x, duel.puck_pos.z]
			break
	var mo: Vector3 = commit[1]
	var mt: Vector3 = commit[2]
	_rows.append([label, race.x, race.y, race.z,
			mo.x if mo.is_finite() else 0.0, mo.z if mo.is_finite() else 0.0,
			mt.x if mt.is_finite() else 0.0, mt.z if mt.is_finite() else 0.0,
			float(commit[4]), float(commit[6]), float(commit[7]), float(commit[8]), played])

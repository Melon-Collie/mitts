extends "res://tests/instruments/ai/test_nz_entry_drill.gd"

# Is the dump-in's race honest? The entry drill's starts (test_nz_entry_drill.gd)
# and the stacked line's (test_dump_in_drill.gd), real bots in the duel harness.
# Every dump-in our carrier commits to is logged with what AICarrierDumpSearch
# priced at the commit (its debug latch: the odds we play it first, each side's
# time to it, where each side meets it) against what happened: the puck's path
# against the walk it was priced on, who touched it first, where and when, and
# how near our priced retriever and their soonest man came. A chipped dump's
# start is marked ^.

const DumpIn := preload("res://tests/instruments/ai/test_dump_in_drill.gd")
const FOLLOW_S: float = 6.0

var _rows: Array = []


func test_neutral_zone_entries() -> void:
	pending("the entry sweep is test_nz_entry_drill.gd's own")


func test_dump_in_races() -> void:
	for n_def: int in [2, 3]:
		for x: float in [0.0, 3.0, 5.0, -6.0, -9.0]:
			for v: float in [1.0, 3.0, 5.0]:
				_follow(_setup(x, v, n_def), "3v%d/x%+.0f/v%.0f" % [n_def, x, v])
	var stacked: Object = DumpIn.new()
	for x: float in [0.0, 4.0, -6.0]:
		for v: float in [6.0, 8.0]:
			for gap: float in [0.0, 2.0]:
				_follow(stacked._stacked(x, v, gap), "stack/x%+.0f/v%.0f/g%.0f" % [x, v, gap])
	stacked.free()
	gut.p("dumps: %d" % _rows.size())
	gut.p("  start            p     t ours  t theirs (keeper)  priced meet ours / theirs      pace priced/thrown  off walk 1 s  first played")
	var won: int = 0
	var p_sum: float = 0.0
	for r: Array in _rows:
		gut.p("  %-16s %4.2f  %5.2f   %5.2f (%5.2f)      (%5.1f,%5.1f) / (%5.1f,%5.1f)   %4.1f / %4.1f         %4.2f        %s" % r)
		p_sum += r[1]
		if str(r[12]).begins_with("ours"):
			won += 1
	if not _rows.is_empty():
		gut.p("  priced %.2f on average, won %d of %d" % [p_sum / _rows.size(), won, _rows.size()])
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
			var s: Object = duel._skater(c)
			var sm: Object = s.agent
			if sm._state == SkaterAgentStateMachine.State.PASS_PRESSED \
					and sm._dump_target.is_finite() and sm._pass_target_peer_id == -1:
				if commit.is_empty():
					var dump: AICarrierDumpSearch = sm._carrier._dump
					commit = [dump.debug_race, dump.best_meet, dump.debug_meet_theirs,
							dump.best_dir, dump.best_pace, dump.debug_origin, dump.best_lofted]
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
	var walk_p: Vector3 = AICarrierDumpSearch._launch_pos(commit[5], commit[6])
	var walk_v: Vector3 = AICarrierDumpSearch._launch_vel(commit[3], float(commit[4]), commit[6])
	var thrown: float = Vector2(duel.puck_vel.x, duel.puck_vel.z).length()
	var off_1s: float = -1.0
	var played: String = "nobody in %.0f s" % FOLLOW_S
	for i: int in int(FOLLOW_S / Duel.DT):
		var stepped: Transform3D = AITrajectory.step_puck_3d(walk_p, walk_v, Duel.DT)
		walk_p = stepped.origin
		walk_v = stepped.basis.x
		duel.step()
		if i + 1 == int(1.0 / Duel.DT):
			off_1s = Vector2(duel.puck_pos.x - walk_p.x, duel.puck_pos.z - walk_p.z).length()
		var c: int = duel.carrier()
		if c != -1:
			played = "%s %d at %.2f s, (%.1f,%.1f)" % ["ours" if duel.team_map[c] == 0 else "theirs",
					c, (i + 1) * Duel.DT, duel.puck_pos.x, duel.puck_pos.z]
			break
	var mo: Vector3 = commit[1]
	var mt: Vector3 = commit[2]
	_rows.append([label + ("^" if commit[6] else ""), race.x, race.y, race.z, race.w,
			mo.x if mo.is_finite() else 0.0, mo.z if mo.is_finite() else 0.0,
			mt.x if mt.is_finite() else 0.0, mt.z if mt.is_finite() else 0.0,
			float(commit[4]), thrown, off_1s, played])

extends "res://tests/instruments/ai/test_strip_odds_by_horizon.gd"

# The one-chance interception read (docs/strip-interception-plan.md), exported
# for fitting by tools/strip_interception_fit.py: for each saved run
# (MITTS_HORIZON_RUNS) whether the puck was lost, and for each defender his best
# spare time on the carrier's planned path — over its samples, the puck's time
# there less the time his stick takes to get within his blade's reach of it,
# read from the run's start on his arrival clock — and when that point comes.
# The planned path is <runs>.planned when it exists (the interceptor's dry runs),
# else the puck's path as recorded, which stops at a loss. Also the strips the
# current strip odds expect along it. Writes .preview/strip_interception/runs.csv.
# Reports only.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const OUT_DIR: String = "res://.preview/strip_interception"


func test_strip_odds_by_horizon() -> void:
	pass


func test_export_interception() -> void:
	var path: String = OS.get_environment("MITTS_HORIZON_RUNS")
	if path.is_empty():
		gut.p("set MITTS_HORIZON_RUNS to a saved run file")
		assert_true(true)
		return
	var caps: AISkaterCaps = Duel.match_caps()
	var runs: Array[Run] = _load_saved(path)
	var planned: Array = _load_planned(path + ".planned")
	gut.p("%d runs, planned paths %s" % [runs.size(),
			"from the dry runs" if planned.size() == runs.size() else "as recorded"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open(OUT_DIR + "/runs.csv", FileAccess.WRITE)
	f.store_line("run,family,lost,lost_at,s1,t1,s2,t2,current")
	for ri: int in runs.size():
		var r: Run = runs[ri]
		var pts: Array[Vector3] = r.points
		if planned.size() == runs.size():
			pts = planned[ri]
		var times: Array[float] = []
		for k: int in pts.size():
			times.append((k + 1) * 0.1)
		var cols := PackedStringArray()
		for i: int in 2:
			if i >= r.defenders.size():
				cols.append_array(["", ""])
				continue
			var best: float = -INF
			var best_t: float = 0.0
			for k: int in pts.size():
				var spare: float = times[k] - _stick_arrival(r.defenders[i], r.vels[i], pts[k], caps)
				if spare > best:
					best = spare
					best_t = times[k]
			cols.append_array([str(best), str(best_t)])
		var current: float = AIStripOdds.path_strips(pts[0], pts.slice(1), times.slice(1),
				r.defenders, r.vels)
		f.store_line("%d,%s,%d,%.3f,%s,%s,%s,%s,%.6f" % [ri, r.family, 1 if r.lost_at >= 0.0 else 0,
				r.lost_at, cols[0], cols[1], cols[2], cols[3], current])
	gut.p("wrote %s/runs.csv" % OUT_DIR)
	assert_true(true)


func _load_planned(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	while f != null and not f.eof_reached():
		var parts: PackedStringArray = f.get_line().split(" ", false)
		if parts.is_empty():
			continue
		var pts: Array[Vector3] = []
		for k: int in range(0, parts.size(), 2):
			pts.append(Vector3(float(parts[k]), 0, float(parts[k + 1])))
		out.append(pts)
	return out


# When his stick can first be within his blade's reach of `point`, on his
# arrival clock from where he is and how he is moving.
func _stick_arrival(pos: Vector3, vel: Vector3, point: Vector3, caps: AISkaterCaps) -> float:
	var to := Vector3(point.x - pos.x, 0.0, point.z - pos.z)
	var d: float = to.length()
	if d <= caps.max_blade_reach:
		return 0.0
	return AIArrival.time_to_arrive_caps(pos, pos + to * ((d - caps.max_blade_reach) / d), vel,
			caps)

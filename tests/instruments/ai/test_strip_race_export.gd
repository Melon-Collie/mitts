extends "res://tests/instruments/ai/test_strip_odds_by_horizon.gd"

# The race-margin read of the strip, exported for fitting by tools/strip_race_fit.py:
# for every 0.1 s stretch of each saved run (MITTS_HORIZON_RUNS) the time it
# took, whether the puck stood, whether it was lost in it, the strips the
# current strip odds expect in it, and each defender's race margin to it — how
# much sooner than the puck, read from the run's start, his momentum-honest
# arrival clock gets his stick within the strip radius of the puck's spot
# (positive: he could be there first). Writes .preview/strip_race/stretches.csv.
# Reports only.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const OUT_DIR: String = "res://.preview/strip_race"


func test_strip_odds_by_horizon() -> void:
	pass


func test_export_race_margins() -> void:
	var path: String = OS.get_environment("MITTS_HORIZON_RUNS")
	if path.is_empty():
		gut.p("set MITTS_HORIZON_RUNS to a saved run file")
		assert_true(true)
		return
	var caps: AISkaterCaps = Duel.match_caps()
	var runs: Array[Run] = _load_saved(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open(OUT_DIR + "/stretches.csv", FileAccess.WRITE)
	f.store_line("run,family,t,dt,stand,lost,watched_to,current,m1,m2")
	var rows: int = 0
	for ri: int in runs.size():
		var r: Run = runs[ri]
		for k: int in range(1, r.points.size()):
			var t: float = r.times[k]
			var dt: float = t - r.times[k - 1]
			var pace: float = Vector2(r.points[k].x - r.points[k - 1].x,
					r.points[k].z - r.points[k - 1].z).length() / dt
			var lost: bool = r.lost_at >= 0.0 and t >= r.lost_at - 1e-4
			var margins := PackedStringArray()
			for i: int in 2:
				margins.append(str(t - _stick_arrival(r.defenders[i], r.vels[i], r.points[k], caps))
						if i < r.defenders.size() else "")
			f.store_line("%d,%s,%.3f,%.3f,%d,%d,%.3f,%.6f,%s,%s" % [ri, r.family, t, dt,
					1 if pace < AIStripOdds.STANDING_PUCK_M_S else 0, 1 if lost else 0,
					r.watched_to, AIStripOdds.stretch_strips(r.points[k - 1], r.points[k], dt, t,
							r.defenders, r.vels), margins[0], margins[1]])
			rows += 1
			if lost:
				break
	gut.p("wrote %d stretches of %d runs to %s/stretches.csv" % [rows, runs.size(), OUT_DIR])
	assert_true(true)


# When his stick can first be within the strip radius of `point`, on his arrival
# clock from where he is and how he is moving.
func _stick_arrival(pos: Vector3, vel: Vector3, point: Vector3, caps: AISkaterCaps) -> float:
	var to := Vector3(point.x - pos.x, 0.0, point.z - pos.z)
	var d: float = to.length()
	if d <= AIStripOdds.STRIP_RADIUS_M:
		return 0.0
	return AIArrival.time_to_arrive_caps(pos, pos + to * ((d - AIStripOdds.STRIP_RADIUS_M) / d),
			vel, caps)

extends GutTest

# The strip odds (AIStripOdds) by how far ahead they read, against our defending
# bots. Two checks, each binned by the time from the read (the run's start):
#
#   losses   the strips the model expects in each band of time, against the
#            losses that happened in it (the truth gate's data, and a saved run
#            file when given);
#   coverage the odds the model gives that a defender is within the strip
#            radius of the puck at each sample, against how often he really was
#            (a saved run file with defender tracks, from
#            test_defender_race_truth.gd's MITTS_RACE_SAVE).
#
# MITTS_HORIZON_RUNS names the saved run file. Reports only.

const TRUTH_PATH: String = "res://tests/unit/ai/data/strip_odds_truth.txt"
const BANDS: Array[float] = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.01]
# A defender read as standing at the start: slower than this.
const STANDING_M_S: float = 1.0


class Run:
	var family: String = ""
	var lost_at: float = -1.0
	var watched_to: float = 0.0
	var defenders: Array[Vector3] = []
	var vels: Array[Vector3] = []
	var points: Array[Vector3] = []
	var times: Array[float] = []
	var tracks: Array = []   # per defender, Array[Vector3] per sample; empty when untracked


func test_strip_odds_by_horizon() -> void:
	var truth: Array[Run] = _load_truth()
	gut.p("truth gate data: %d runs" % truth.size())
	_losses_by_band(truth, "all")
	var path: String = OS.get_environment("MITTS_HORIZON_RUNS")
	if path.is_empty():
		gut.p("no MITTS_HORIZON_RUNS: coverage needs defender tracks")
		assert_true(true)
		return
	var saved: Array[Run] = _load_saved(path)
	gut.p("saved runs: %d from %s" % [saved.size(), path])
	_losses_by_band(saved, "all")
	var families: Array[String] = []
	for r: Run in saved:
		if not r.family in families:
			families.append(r.family)
	for fam: String in families:
		_losses_by_band(saved.filter(func(r: Run) -> bool: return r.family == fam), fam)
	_coverage_by_band(saved, "every defender", func(_v: Vector3, _d: float) -> bool: return true)
	_coverage_by_band(saved, "standing at the start",
			func(v: Vector3, _d: float) -> bool: return Vector2(v.x, v.z).length() < STANDING_M_S)
	_coverage_by_band(saved, "standing, 6 m or more from the puck",
			func(v: Vector3, d: float) -> bool:
				return Vector2(v.x, v.z).length() < STANDING_M_S and d >= 6.0)
	_coverage_by_band(saved, "moving at the start",
			func(v: Vector3, _d: float) -> bool: return Vector2(v.x, v.z).length() >= STANDING_M_S)
	_coverage_reliability(saved)
	_closing(saved)
	assert_true(true)


# Expected strips accrued in each band while the run was still in play, against
# the losses in it.
func _losses_by_band(runs: Array, label: String) -> void:
	var n: int = BANDS.size() - 1
	var expected: Array[float] = []
	var lost: Array[float] = []
	var exposure: Array[float] = []
	expected.resize(n)
	lost.resize(n)
	exposure.resize(n)
	expected.fill(0.0)
	lost.fill(0.0)
	exposure.fill(0.0)
	for r: Run in runs:
		for k: int in range(1, r.points.size()):
			var t: float = r.times[k]
			var b: int = _band(t)
			expected[b] += AIStripOdds.stretch_strips(r.points[k - 1], r.points[k],
					t - r.times[k - 1], t, r.defenders, r.vels)
			exposure[b] += t - r.times[k - 1]
		if r.lost_at >= 0.0:
			lost[_band(r.lost_at)] += 1.0
	var line: String = "losses, %s (%d runs):" % [label, runs.size()]
	var tot_e: float = 0.0
	var tot_l: float = 0.0
	for b: int in n:
		line += "  %.1f-%.1f s %d/%.1f" % [BANDS[b], minf(BANDS[b + 1], 3.0), int(lost[b]),
				expected[b]]
		tot_e += expected[b]
		tot_l += lost[b]
	gut.p(line + "   total %d/%.1f (lost/expected)" % [int(tot_l), tot_e])


# Mean predicted odds a defender is within the strip radius of the puck, against
# the share of samples he was, per band, over defender-samples `keep` admits
# (his start velocity, his start distance from the puck's start).
func _coverage_by_band(runs: Array, label: String, keep: Callable) -> void:
	var n: int = BANDS.size() - 1
	var pred: Array[float] = []
	var seen: Array[float] = []
	var count: Array[float] = []
	pred.resize(n)
	seen.resize(n)
	count.resize(n)
	pred.fill(0.0)
	seen.fill(0.0)
	count.fill(0.0)
	for r: Run in runs:
		if r.tracks.is_empty():
			continue
		for i: int in r.defenders.size():
			var d0: float = Vector2(r.defenders[i].x - r.points[0].x,
					r.defenders[i].z - r.points[0].z).length()
			if not keep.call(r.vels[i], d0):
				continue
			for k: int in r.points.size():
				var t: float = r.times[k]
				var b: int = _band(t)
				pred[b] += AIStripOdds.odds_within(r.defenders[i], r.vels[i], null, r.points[k], t)
				var at: Vector3 = r.tracks[i][k]
				seen[b] += 1.0 if Vector2(at.x - r.points[k].x, at.z - r.points[k].z).length() \
						<= AIStripOdds.STRIP_RADIUS_M else 0.0
				count[b] += 1.0
	var line: String = "coverage, %s:" % label
	for b: int in n:
		if count[b] > 0.0:
			line += "  %.1f-%.1f s %.2f vs %.2f (%d)" % [BANDS[b], minf(BANDS[b + 1], 3.0),
					pred[b] / count[b], seen[b] / count[b], int(count[b])]
	gut.p(line + "   (predicted vs seen, samples)")


# Within the early and late halves of the horizon, defender-samples grouped by
# the odds the model gave, against how often he was there.
func _coverage_reliability(runs: Array) -> void:
	var edges: Array[float] = [0.0, 0.05, 0.15, 0.3, 0.5, 0.7, 0.9, 1.01]
	for half: Array in [[0.0, 1.0], [1.0, 2.0], [2.0, 3.01]]:
		var n: int = edges.size() - 1
		var pred: Array[float] = []
		var seen: Array[float] = []
		var count: Array[float] = []
		pred.resize(n)
		seen.resize(n)
		count.resize(n)
		pred.fill(0.0)
		seen.fill(0.0)
		count.fill(0.0)
		for r: Run in runs:
			if r.tracks.is_empty():
				continue
			for i: int in r.defenders.size():
				for k: int in r.points.size():
					var t: float = r.times[k]
					if t < half[0] or t >= half[1]:
						continue
					var p: float = AIStripOdds.odds_within(r.defenders[i], r.vels[i], null,
							r.points[k], t)
					var e: int = 0
					while e < n - 1 and p >= edges[e + 1]:
						e += 1
					var at: Vector3 = r.tracks[i][k]
					pred[e] += p
					seen[e] += 1.0 if Vector2(at.x - r.points[k].x, at.z - r.points[k].z) \
							.length() <= AIStripOdds.STRIP_RADIUS_M else 0.0
					count[e] += 1.0
		var line: String = "reliability %.0f-%.0f s:" % [half[0], minf(half[1], 3.0)]
		for e: int in n:
			if count[e] > 0.0:
				line += "  %.2f→%.2f (%d)" % [pred[e] / count[e], seen[e] / count[e],
						int(count[e])]
		gut.p(line + "   (predicted → seen, samples)")


# How far each defender really was from the puck by band (median), and how
# often one within the strip radius at a sample still is half a second on.
func _closing(runs: Array) -> void:
	var n: int = BANDS.size() - 1
	var dists: Array = []
	for b: int in n:
		dists.append([])
	var on: float = 0.0
	var stayed: float = 0.0
	for r: Run in runs:
		if r.tracks.is_empty():
			continue
		for i: int in r.defenders.size():
			for k: int in r.points.size():
				var at: Vector3 = r.tracks[i][k]
				var d: float = Vector2(at.x - r.points[k].x, at.z - r.points[k].z).length()
				dists[_band(r.times[k])].append(d)
				var later: int = k + 5
				if d <= AIStripOdds.STRIP_RADIUS_M and later < r.points.size():
					var at2: Vector3 = r.tracks[i][later]
					on += 1.0
					stayed += 1.0 if Vector2(at2.x - r.points[later].x,
							at2.z - r.points[later].z).length() <= AIStripOdds.STRIP_RADIUS_M \
							else 0.0
	var line: String = "defender to puck, median m:"
	for b: int in n:
		var ds: Array = dists[b]
		ds.sort()
		if not ds.is_empty():
			line += "  %.1f-%.1f s %.1f" % [BANDS[b], minf(BANDS[b + 1], 3.0), ds[ds.size() / 2]]
	gut.p(line)
	gut.p("within %.1f m at a sample: still within half a second on %.2f (%d)" % [
			AIStripOdds.STRIP_RADIUS_M, stayed / maxf(on, 1.0), int(on)])


func _band(t: float) -> int:
	for b: int in BANDS.size() - 1:
		if t < BANDS[b + 1]:
			return b
	return BANDS.size() - 2


func _load_truth() -> Array[Run]:
	var out: Array[Run] = []
	var f := FileAccess.open(TRUTH_PATH, FileAccess.READ)
	while f != null and not f.eof_reached():
		var line: String = f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var t: PackedStringArray = line.split("\t")
		var run := Run.new()
		run.family = t[0]
		run.lost_at = float(t[1])
		run.watched_to = float(t[2])
		var nd: int = int(t[3])
		for i: int in nd:
			var b: int = 4 + i * 4
			run.defenders.append(Vector3(float(t[b]), 0, float(t[b + 1])))
			run.vels.append(Vector3(float(t[b + 2]), 0, float(t[b + 3])))
		for k: int in range(4 + nd * 4, t.size(), 3):
			run.times.append(float(t[k]))
			run.points.append(Vector3(float(t[k + 1]), 0, float(t[k + 2])))
		out.append(run)
	return out


# test_defender_race_truth.gd's _save format; bot carrier runs are left out (a
# release ends them without a loss, and their paths were chosen around the defence).
func _load_saved(path: String) -> Array[Run]:
	var out: Array[Run] = []
	var f := FileAccess.open(path, FileAccess.READ)
	while f != null and not f.eof_reached():
		var parts: PackedStringArray = f.get_line().split(" ", false)
		if parts.size() < 5 or parts[0].begins_with("bot"):
			continue
		var run := Run.new()
		run.family = parts[0]
		run.lost_at = float(parts[1])
		run.watched_to = float(parts[2])
		var nd: int = int(parts[4])
		var tracked: bool = parts[5] == "T"
		var head: int = 6 if tracked else 5
		for i: int in nd:
			var b: int = head + i * 4
			run.defenders.append(Vector3(float(parts[b]), 0, float(parts[b + 1])))
			run.vels.append(Vector3(float(parts[b + 2]), 0, float(parts[b + 3])))
			if tracked:
				var tj: Array[Vector3] = []
				run.tracks.append(tj)
		var stride: int = 4 + (2 * nd if tracked else 0)
		for k: int in range(head + nd * 4, parts.size(), stride):
			run.times.append(float(parts[k]))
			run.points.append(Vector3(float(parts[k + 1]), 0, float(parts[k + 2])))
			if tracked:
				for i: int in nd:
					run.tracks[i].append(Vector3(float(parts[k + 4 + 2 * i]), 0,
							float(parts[k + 5 + 2 * i])))
		out.append(run)
	return out

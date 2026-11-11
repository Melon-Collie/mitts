extends GutTest

# ── How much of the goalie's open set the shot field's aim sweep misses ───────
# (docs/shot-field-resolution-plan.md, step 1.) The field fires 24 aims per loft
# post to post. Bisecting each change between a goal and anything else sharpens
# the gaps the sweep sees, but a gap that falls between two saves is not seen at
# all. This measures how much odds that costs: per cell it fires a 93-aim sweep
# (every fourth aim is the field's 24) with its edges bisected to ~5 mm as the
# reference, and prices three readings of the same keeper at the field's
# reference scatter, each at the field's 24 candidate aims:
#
#   bands  — the 24-aim sweep as AIShotOdds reads it today
#   edges  — the 24-aim sweep with its goal edges bisected (the plan's step 2)
#   ref    — the 93-aim sweep with its edges bisected
#
# `edges` against `ref` is what step 2 would still miss; `hidden` is the goal
# width in `ref` that no interval in `edges` overlaps.
#
#   MITTS_RES_SHARD=i MITTS_RES_SHARDS=n   measure every n-th cell from i
#   MITTS_RES_MERGE=1                      print the table and summary

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Edges := preload("res://tests/unit/ai/open_set_edges.gd")

const SHARD_PATH: String = "user://open_set_resolution_%d.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DENSE_POINTS: int = 93
const COARSE_EVERY: int = 4
const DENSE_REFINE_STEPS: int = 2
# Release spots (x, metres out): the dots, the slot, in tight, wide, the point
# row of the field; off the field's grid on purpose.
const SPOT_X: Array[float] = [-8.0, -6.7, -4.0, 0.0, 2.5]
const SPOT_FWD: Array[float] = [0.6, 2.5, 4.5, 6.1, 9.5, 15.0]
# The decoy cell's carrier, this far across toward the middle.
const DECOY_ACROSS_M: float = 3.0

var _s: RefCounted = null


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	var puck: Node = load("res://Scenes/Puck.tscn").instantiate()
	var shooter: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	var ctrl := KeeperController.new()
	add_child_autofree(goalie)
	add_child_autofree(puck)
	add_child_autofree(shooter)
	add_child_autofree(ctrl)
	_s = Stager.new(goalie, puck, ctrl, shooter)


# [x, fwd, kind]: SET and DECOY at every spot.
func _cells() -> Array:
	var out: Array = []
	for fwd: float in SPOT_FWD:
		for x: float in SPOT_X:
			out.append([x, fwd, "SET"])
			out.append([x, fwd, "DECOY"])
	return out


func _stage_for(cell: Array) -> Callable:
	var spot := Vector3(cell[0], 0.0, GOAL_Z + float(cell[1]))
	if cell[2] == "DECOY":
		var inward: float = -signf(spot.x) if absf(spot.x) > 0.1 else 1.0
		var decoy := Vector3(spot.x + inward * DECOY_ACROSS_M, 0.0, spot.z)
		return func() -> Vector3: return _s.stage_decoy(spot, decoy)
	return func() -> Vector3: return _s.stage_set(spot)


# One loft's readings: [bands, edges, ref, hidden width (m), shots fired].
func _loft(stage: Callable, loft: int, sigma: float) -> Array:
	var memo: Dictionary = {}
	var shots: Array[int] = [0]
	var shoot: Callable = func(aim: float) -> String:
		if not memo.has(aim):
			var at: Vector3 = stage.call()
			memo[aim] = Stager.OUTCOME_CHARS[_s.release(at, false, false,
					Vector3(aim, 0.0, GOAL_Z), loft)]
			shots[0] += 1
		return memo[aim]
	var dense: String = ""
	for i: int in DENSE_POINTS:
		dense += shoot.call(Edges.aim_x(i, DENSE_POINTS))
	var coarse: String = ""
	for i: int in range(0, DENSE_POINTS, COARSE_EVERY):
		coarse += dense[i]
	var ref: PackedFloat32Array = Edges.refine(dense, shoot, DENSE_REFINE_STEPS)
	var edges: PackedFloat32Array = Edges.refine(coarse, shoot)
	var n: int = coarse.length()
	var best: Array[float] = [0.0, 0.0, 0.0]
	for i: int in n:
		var aim: float = Edges.aim_x(i, n)
		best[0] = maxf(best[0], _band_odds(coarse, i, sigma))
		best[1] = maxf(best[1], AIShotOdds.interval_odds(edges, aim, sigma))
		best[2] = maxf(best[2], AIShotOdds.interval_odds(ref, aim, sigma))
	return [best[0], best[1], best[2], _unseen_width(ref, edges), shots[0], coarse, dense]


# Aim `i`'s odds with each aim of `sweep` standing for its whole band, the end
# bands stopping at the posts: how the field read a sweep before it had edges.
static func _band_odds(sweep: String, i: int, sigma: float) -> float:
	var n: int = sweep.length()
	var reach: float = AIShotOdds.post_reach()
	var step: float = 2.0 * reach / float(n - 1)
	var bands := PackedFloat32Array()
	for j: int in n:
		if sweep[j] == "G":
			var x: float = Edges.aim_x(j, n)
			bands.append(maxf(x - 0.5 * step, -reach))
			bands.append(minf(x + 0.5 * step, reach))
	return AIShotOdds.interval_odds(bands, Edges.aim_x(i, n), sigma)


# The width of `ref`'s intervals that overlap none of `seen`'s.
static func _unseen_width(ref: PackedFloat32Array, seen: PackedFloat32Array) -> float:
	var w: float = 0.0
	for k: int in range(0, ref.size(), 2):
		var overlapped: bool = false
		for m: int in range(0, seen.size(), 2):
			if ref[k] < seen[m + 1] and seen[m] < ref[k + 1]:
				overlapped = true
		if not overlapped:
			w += ref[k + 1] - ref[k]
	return w


func _row(index: int, cell: Array) -> String:
	var stage: Callable = _stage_for(cell)
	var release: Vector3 = stage.call()
	var sigma: float = AIShotOdds.REFERENCE_SPREAD_RAD \
			* maxf(Vector2(release.x, release.z - GOAL_Z).length(), 0.5)
	var odds: Array[float] = [0.0, 0.0, 0.0]
	var hidden: float = 0.0
	var shots: int = 0
	var sweeps: PackedStringArray = []
	for loft: int in Stager.LOFTS:
		var r: Array = _loft(stage, loft, sigma)
		for k: int in 3:
			odds[k] = maxf(odds[k], r[k])
		hidden += r[3]
		shots += r[4]
		sweeps.append(r[6])
	return "%d\t%.1f\t%.1f\t%s\t%.4f\t%.4f\t%.4f\t%.4f\t%d\t%s" % [index, cell[0], cell[1],
			cell[2], odds[0], odds[1], odds[2], hidden, shots, "|".join(sweeps)]


func test_measure_a_shard() -> void:
	var shards: int = int(OS.get_environment("MITTS_RES_SHARDS"))
	if shards <= 0:
		pending("set MITTS_RES_SHARD / MITTS_RES_SHARDS")
		return
	var shard: int = int(OS.get_environment("MITTS_RES_SHARD"))
	var cells: Array = _cells()
	var lines: PackedStringArray = []
	for i: int in cells.size():
		if i % shards == shard:
			lines.append(_row(i, cells[i]))
			gut.p(lines[-1].get_slice("\t", 0) + " done")
	var f := FileAccess.open(SHARD_PATH % shard, FileAccess.WRITE)
	assert_not_null(f, "can write shard %d" % shard)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()


func test_print_the_table() -> void:
	if OS.get_environment("MITTS_RES_MERGE") != "1":
		pending("set MITTS_RES_MERGE=1 and MITTS_RES_SHARDS")
		return
	var shards: int = int(OS.get_environment("MITTS_RES_SHARDS"))
	var rows: Array[PackedStringArray] = []
	for shard: int in shards:
		for line: String in FileAccess.get_file_as_string(SHARD_PATH % shard).split("\n"):
			if not line.is_empty():
				rows.append(line.split("\t"))
	rows.sort_custom(func(a: PackedStringArray, b: PackedStringArray) -> bool:
		return int(a[0]) < int(b[0]))
	gut.p("   x    out  cell    bands   edges     ref  hidden(cm)  shots")
	var err_bands: float = 0.0
	var err_edges: float = 0.0
	var worst_edges: float = 0.0
	var hidden_cells: int = 0
	var shots: int = 0
	for r: PackedStringArray in rows:
		var bands: float = float(r[4])
		var edges: float = float(r[5])
		var ref: float = float(r[6])
		var hidden: float = float(r[7])
		gut.p("%5s %5s  %-6s %6.3f  %6.3f  %6.3f  %8.1f  %5s" % [r[1], r[2], r[3], bands,
				edges, ref, hidden * 100.0, r[8]])
		err_bands += absf(bands - ref)
		err_edges += absf(edges - ref)
		worst_edges = maxf(worst_edges, absf(edges - ref))
		if hidden > 0.0:
			hidden_cells += 1
		shots += int(r[8])
	var n: float = maxf(float(rows.size()), 1.0)
	gut.p("cells %d, shots %d" % [rows.size(), shots])
	gut.p("mean |bands - ref| %.4f   mean |edges - ref| %.4f   worst |edges - ref| %.4f"
			% [err_bands / n, err_edges / n, worst_edges])
	gut.p("cells with a goal gap the 24-aim sweep never saw: %d" % hidden_cells)
	assert_eq(rows.size(), _cells().size(), "every cell was measured")

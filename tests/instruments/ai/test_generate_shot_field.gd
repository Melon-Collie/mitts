extends GutTest

# ── The SHOT FIELD generator (docs/shot-currency-plan.md, step 2) ────────────
# Measures the live goalie's open set over the field AIShotOdds reads, and
# writes it as Scripts/domain/ai/generated/shot_field_data.gd. Run it through
# .claude/hooks/generate-shot-field.sh, which shards the cells over processes
# and then merges; never hand-edit the output. Re-run when the goalie changes —
# test_shot_field_is_current.gd says when.
#
# Per release spot: SET (settled, square, charged release); a deke onto the spot
# from either side; feeds from passers across at several distances and paces,
# each one-timed (O) and caught-then-charged (K); and DECOY, the keeper set on a
# carrier elsewhere — across, in tight, far out — before a charged release from
# the spot: out of position laterally or in depth. Every cell records the
# keeper's read before the feed left and at decision time, and the open set
# (FLAT / LOW / HIGH × the stager's aims). Reads are stored raw; AIShotOdds
# derives its features from them, so a feature change needs no re-measurement.
#
#   MITTS_FIELD_SHARD=i MITTS_FIELD_SHARDS=n   measure every n-th cell from i
#   MITTS_FIELD_MERGE=1                        merge the shards into the data file

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Fingerprint := preload("res://tests/unit/ai/shot_field_fingerprint.gd")

const OUT_PATH: String = "res://Scripts/domain/ai/generated/shot_field_data.gd"
const SHARD_PATH: String = "user://shot_field_shard_%d.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
# Lateral and metres-out release grid, in the frame of the net at GOAL_Z.
# Densest near the net, where the goalie's open set changes fastest. The first
# row is on the goal line's doorstep, where he seals the post at a sharp angle.
const SPOT_X: Array[float] = [-8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0]
const SPOT_FWD: Array[float] = [0.6, 1.5, 2.5, 3.5, 4.5, 6.0, 7.5, 9.5, 12.0, 15.0]
const DEKE_ACROSS_M: float = 2.0
# Signed lateral offsets of the passer from the receiver, and feed paces.
const FEED_OFFSETS_M: Array[float] = [-6.0, -3.5, -1.5, 1.5, 3.5, 6.0]
const FEED_SPEEDS_M_S: Array[float] = [12.0, 20.0]
# A passer or deke start past this is off the ice.
const MAX_ABS_X_M: float = 11.0
# Decoy carriers: lateral offsets from the spot, and distances from the net
# along the spot's own bearing (in tight leaves him deep, far out leaves him
# challenging). A range decoy nearer the spot than DECOY_MIN_SHIFT_M is the SET.
const DECOY_ACROSS_M: Array[float] = [-6.0, -3.0, 3.0, 6.0]
const DECOY_RANGES_M: Array[float] = [2.0, 15.0]
const DECOY_MIN_SHIFT_M: float = 1.5

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


# Every cell, in a fixed order: [spot_x, spot_fwd, kind, mode, passer_x,
# feed_speed]. kind is SET / DEKE / FEED / DECOY; mode C (charged), O (one-timer)
# or K (caught, then charged); passer_x is the deke's start for a deke and the
# decoy's x for a decoy, whose metres out ride in feed_speed's column.
func _cells() -> Array:
	var out: Array = []
	for fwd: float in SPOT_FWD:
		for x: float in SPOT_X:
			out.append([x, fwd, "SET", "C", x, 0.0])
			for side: float in [-1.0, 1.0]:
				var from: float = x + side * DEKE_ACROSS_M
				if absf(from) <= MAX_ABS_X_M:
					out.append([x, fwd, "DEKE", "C", from, 0.0])
			for off: float in FEED_OFFSETS_M:
				if absf(x + off) > MAX_ABS_X_M:
					continue
				for speed: float in FEED_SPEEDS_M_S:
					for mode: String in ["O", "K"]:
						out.append([x, fwd, "FEED", mode, x + off, speed])
			for across: float in DECOY_ACROSS_M:
				if absf(x + across) <= MAX_ABS_X_M:
					out.append([x, fwd, "DECOY", "C", x + across, fwd])
			var spot_range: float = Vector2(x, fwd).length()
			for r: float in DECOY_RANGES_M:
				if absf(r - spot_range) >= DECOY_MIN_SHIFT_M:
					var at: Vector2 = Vector2(x, fwd) * (r / spot_range)
					out.append([x, fwd, "DECOY", "C", at.x, at.y])
	return out


func _stage_for(cell: Array) -> Callable:
	var spot := Vector3(cell[0], 0.0, GOAL_Z + cell[1])
	match cell[2]:
		"DEKE":
			var across: float = spot.x - float(cell[4])
			return func() -> Vector3: return _s.stage_deke(spot, across)
		"FEED":
			var passer := Vector3(cell[4], 0.0, spot.z)
			var speed: float = cell[5]
			return func() -> Vector3: return _s.stage_feed(spot, passer, speed)
		"DECOY":
			var decoy := Vector3(cell[4], 0.0, GOAL_Z + float(cell[5]))
			return func() -> Vector3: return _s.stage_decoy(spot, decoy)
	return func() -> Vector3: return _s.stage_set(spot)


func _row(index: int, cell: Array) -> String:
	var stage: Callable = _stage_for(cell)
	var release: Vector3 = stage.call()
	var decision: GoalieNetworkState = _s.read()
	var pre: GoalieNetworkState = _s.pre_feed_read if cell[2] == "FEED" else decision
	var pre_fields: String = Stager.read_fields(pre)
	var decision_fields: String = Stager.read_fields(decision)
	var patterns: PackedStringArray = _s.open_set(stage, cell[3] == "O", cell[3] == "K")
	return "%d\t%.2f\t%.2f\t%s\t%s\t%.2f\t%.2f\t%.3f\t%.3f\t%s\t%s\t%s\t%s\t%s" % [
			index, cell[0], cell[1], cell[2], cell[3], cell[4], cell[5],
			release.x, release.z - GOAL_Z, pre_fields, decision_fields,
			patterns[0], patterns[1], patterns[2]]


func test_measure_a_shard() -> void:
	var shards: int = int(OS.get_environment("MITTS_FIELD_SHARDS"))
	if shards <= 0:
		pending("set MITTS_FIELD_SHARD / MITTS_FIELD_SHARDS (generate-shot-field.sh)")
		return
	var shard: int = int(OS.get_environment("MITTS_FIELD_SHARD"))
	var cells: Array = _cells()
	var lines: PackedStringArray = []
	for i: int in cells.size():
		if i % shards == shard:
			lines.append(_row(i, cells[i]))
	var f := FileAccess.open(SHARD_PATH % shard, FileAccess.WRITE)
	assert_not_null(f, "can write shard %d" % shard)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	gut.p("shard %d/%d: %d cells" % [shard, shards, lines.size()])


func test_merge_the_shards() -> void:
	if OS.get_environment("MITTS_FIELD_MERGE") != "1":
		pending("set MITTS_FIELD_MERGE=1 (generate-shot-field.sh)")
		return
	var shards: int = int(OS.get_environment("MITTS_FIELD_SHARDS"))
	var rows: Array[String] = []
	rows.resize(_cells().size())
	for shard: int in shards:
		for line: String in FileAccess.get_file_as_string(SHARD_PATH % shard).split("\n"):
			if not line.is_empty():
				rows[int(line.get_slice("\t", 0))] = line
	for i: int in rows.size():
		assert_false(rows[i].is_empty(), "cell %d was measured" % i)
	var out: PackedStringArray = [
		"class_name AIShotFieldData",
		"",
		"# GENERATED by tests/instruments/ai/test_generate_shot_field.gd through",
		"# .claude/hooks/generate-shot-field.sh — never hand-edit. The live goalie's",
		"# open set per cell, read by AIShotOdds. Row columns: index, spot x, spot",
		"# metres out, kind, mode, passer x (a deke's start, a decoy's x), feed pace",
		"# (a decoy's metres out), release x, release metres",
		"# out, the 7-field read before the feed, the 7-field read at decision",
		"# (shot_odds_stager.gd read_fields), then FLAT / LOW / HIGH outcomes.",
		"",
		"const FINGERPRINT: String = \"%s\"" % Fingerprint.compute(),
		"const SPOT_X: Array[float] = %s" % str(SPOT_X),
		"const SPOT_FWD: Array[float] = %s" % str(SPOT_FWD),
		"const AIM_POINTS: int = %d" % Stager.AIM_POINTS,
		"const ROWS: Array[String] = [",
	]
	for r: String in rows:
		out.append("\t\"%s\"," % r.c_escape())
	out.append("]")
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	assert_not_null(f, "can write %s" % OUT_PATH)
	if f != null:
		f.store_string("\n".join(out) + "\n")
		f.close()
	gut.p("merged %d cells into %s" % [rows.size(), OUT_PATH])

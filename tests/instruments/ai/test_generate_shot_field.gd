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
# the spot: out of position laterally or in depth; and, in close, WRAP, the
# keeper sealed in the RVH on a carrier behind the net who carries it round the
# post on his side to the spot before a charged release. Every cell records the
# keeper's read before the feed left and at decision time, and the open set
# (FLAT / LOW / HIGH × the stager's aims, then each loft's goal intervals with
# their edges bisected). Reads are stored raw; AIShotOdds
# derives its features from them, so a feature change needs no re-measurement.
#
#   MITTS_FIELD_SHARD=i MITTS_FIELD_SHARDS=n   measure every n-th cell from i
#   MITTS_FIELD_MERGE=1                        merge the shards into the data file

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Fingerprint := preload("res://tests/unit/ai/shot_field_fingerprint.gd")

const OUT_PATH: String = "res://Scripts/domain/ai/generated/shot_field_data.gd"
const SHARD_PATH: String = "user://shot_field_shard_%d.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
# Lateral and metres-out release grid, in the frame of the net at GOAL_Z, out
# to the boards and the blue line's far edge (19.51 m), so a release on the ice
# in the zone reads measured spots. Densest near the net, where the goalie's
# open set changes fastest. The first row is on the goal line's doorstep, where
# he seals the post at a sharp angle. A spot whose carrier would stand in the
# boards measures nothing.
const SPOT_X: Array[float] = [-12.0, -10.0, -8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0,
		10.0, 12.0]
const SPOT_FWD: Array[float] = [0.6, 1.5, 2.5, 3.5, 4.5, 6.0, 7.5, 9.5, 12.0, 15.0, 17.5, 19.5]
const DEKE_ACROSS_M: float = 2.0
# Signed lateral offsets of the passer from the receiver, and feed paces. At a
# sharp angle what the keeper concedes to a one-timer jumps with a metre of feed
# or a few m/s of pace (whether his push beats the shot turns on when he
# commits), so the samples are dense enough for the kernel to average over
# several of them: a feed is priced at what feeds like it concede.
const FEED_OFFSETS_M: Array[float] = [-6.0, -4.5, -3.5, -2.5, -1.5, 1.5, 2.5, 3.5, 4.5, 6.0]
const FEED_SPEEDS_M_S: Array[float] = [12.0, 16.0, 20.0]
# Decoy carriers: lateral offsets from the spot, out to a cross-ice play's (a
# keeper pulled further than the field samples reads as the nearest cell, set on
# the shot), and distances from the net along the spot's own bearing (in tight
# leaves him deep, far out leaves him challenging). A range decoy nearer the spot
# than DECOY_MIN_SHIFT_M is the SET.
const DECOY_ACROSS_M: Array[float] = [-12.0, -9.0, -6.0, -3.0, 3.0, 6.0, 9.0, 12.0]
const DECOY_RANGES_M: Array[float] = [2.0, 15.0]
const DECOY_MIN_SHIFT_M: float = 1.5
# Wraps: spots this close in, the carrier behind the net this far across and
# this far behind the goal line, where he seals the post on his side; from the
# side of the spot, or either side for a spot between the posts (round one post
# to past the other is a carry across the crease, which the SET cells hold).
const WRAP_MAX_FWD_M: float = 3.5
const WRAP_BEHIND_X_M: float = 1.2
const WRAP_BEHIND_M: float = 1.6

var _s: RefCounted = null
var _body_radius: float = 0.0


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
	_body_radius = shooter.collision_radius()


# Every cell, in a fixed order: [spot_x, spot_fwd, kind, mode, passer_x,
# feed_speed]. kind is SET / DEKE / FEED / DECOY / WRAP; mode C (charged), O
# (one-timer) or K (caught, then charged); passer_x is the deke's start for a
# deke and the decoy's or the wrap carrier's x for those, whose metres out ride
# in feed_speed's column (a wrap's negative: behind the goal line).
func _cells() -> Array:
	var out: Array = []
	for fwd: float in SPOT_FWD:
		for x: float in SPOT_X:
			if not _on_ice(x, fwd):
				continue
			out.append([x, fwd, "SET", "C", x, 0.0])
			for side: float in [-1.0, 1.0]:
				var from: float = x + side * DEKE_ACROSS_M
				if _on_ice(from, fwd + Stager.DEKE_FORWARD_M_S * Stager.DEKE_S):
					out.append([x, fwd, "DEKE", "C", from, 0.0])
			for off: float in FEED_OFFSETS_M:
				if not _on_ice(x + off, fwd):
					continue
				for speed: float in FEED_SPEEDS_M_S:
					for mode: String in ["O", "K"]:
						out.append([x, fwd, "FEED", mode, x + off, speed])
			for across: float in DECOY_ACROSS_M:
				if _on_ice(x + across, fwd):
					out.append([x, fwd, "DECOY", "C", x + across, fwd])
			var spot_range: float = Vector2(x, fwd).length()
			for r: float in DECOY_RANGES_M:
				var at: Vector2 = Vector2(x, fwd) * (r / spot_range)
				if absf(r - spot_range) >= DECOY_MIN_SHIFT_M and _on_ice(at.x, at.y):
					out.append([x, fwd, "DECOY", "C", at.x, at.y])
			if fwd <= WRAP_MAX_FWD_M:
				for side: float in [-1.0, 1.0]:
					if side * x > -GameRules.NET_HALF_WIDTH:
						out.append([x, fwd, "WRAP", "C", side * WRAP_BEHIND_X_M, -WRAP_BEHIND_M])
	return out


# Whether a skater at `x`, `fwd` metres out from the goal line stands clear of
# the boards.
func _on_ice(x: float, fwd: float) -> bool:
	var at := Vector2(x, GOAL_Z + fwd)
	return GameRules.clamp_to_rink_inner(at, _body_radius).distance_to(at) < 1e-4


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
		"WRAP":
			var behind := Vector3(cell[4], 0.0, GOAL_Z + float(cell[5]))
			return func() -> Vector3: return _s.stage_wrap(spot, behind)
	return func() -> Vector3: return _s.stage_set(spot)


func _row(index: int, cell: Array) -> String:
	var stage: Callable = _stage_for(cell)
	var release: Vector3 = stage.call()
	var decision: GoalieNetworkState = _s.read()
	var pre: GoalieNetworkState = _s.pre_feed_read if cell[2] == "FEED" else decision
	var pre_fields: String = Stager.read_fields(pre)
	var decision_fields: String = Stager.read_fields(decision)
	var patterns: PackedStringArray = _s.open_set(stage, cell[3] == "O", cell[3] == "K")
	return "%d\t%.2f\t%.2f\t%s\t%s\t%.2f\t%.2f\t%.3f\t%.3f\t%s\t%s\t%s" % [
			index, cell[0], cell[1], cell[2], cell[3], cell[4], cell[5],
			release.x, release.z - GOAL_Z, pre_fields, decision_fields, "\t".join(patterns)]


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
		"# metres out, kind, mode, passer x (a deke's start, a decoy's or a wrap's",
		"# x), feed pace (a decoy's or a wrap's metres out), release x, release",
		"# metres out, the 7-field read before the feed, the 7-field read at decision",
		"# (shot_odds_stager.gd read_fields), then FLAT / LOW / HIGH outcomes at",
		"# AIM_POINTS aims post to post, then FLAT / LOW / HIGH goal intervals",
		"# (open_set_edges.gd: millimetres across the net, edges bisected).",
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

extends GutTest

# ── The SCREEN FIELD generator (docs/bot-net-front-offense-plan.md, step 2b) ──
# What a body in front of the live goalie does to a shot: from each release
# spot, a keeper settled square on the carrier with a second skater standing at
# a station on or beside the release's line to the net (or, the baseline, out of
# the play), and a charged wrister at each loft and aim post to post, the keeper
# restored before each (shot_odds_stager.gd). He reads a screened release late
# and looks round the body (KeeperScreen), from every skater he sees. Each cell
# is a row: the station and how many of its shots scored. Written as
# Scripts/domain/ai/generated/screen_field_data.gd by
# .claude/hooks/generate-screen-field.sh; re-run when the goalie changes
# (test_screen_field_is_current.gd says when). Never hand-edit the output.
#
#   MITTS_SCREEN_SHARD=i MITTS_SCREEN_SHARDS=n   measure every n-th cell from i
#   MITTS_SCREEN_MERGE=1                         merge the shards

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Edges := preload("res://tests/unit/ai/open_set_edges.gd")
const Fingerprint := preload("res://tests/unit/ai/screen_field_fingerprint.gd")
const SkaterScene := preload("res://Scenes/Skater.tscn")

const OUT_PATH: String = "res://Scripts/domain/ai/generated/screen_field_data.gd"
const SHARD_PATH: String = "user://screen_field_shard_%d.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
# Where screened shots come from: the slot's top, the circles, the points.
const SPOT_X: Array[float] = [-8.0, -4.0, 0.0, 4.0, 8.0]
const SPOT_FWD: Array[float] = [6.0, 9.5, 15.0, 19.5]
# A station: this far from the centre of the goal along the release's line to
# it, and this far off the line (positive to the shooter's left).
const STATION_ALONG_M: Array[float] = [1.5, 2.5, 3.5, 5.0]
const STATION_ACROSS_M: Array[float] = [-0.8, -0.4, 0.0, 0.4, 0.8]
const AIM_POINTS: int = 8
# The baseline's screener: out of the play, at centre ice.
const OUT_OF_PLAY := Vector3(0.0, 0.0, 0.0)

var _s: RefCounted = null
var _screener: Skater = null
var _body_radius: float = 0.0


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	var puck: Node = load("res://Scenes/Puck.tscn").instantiate()
	var shooter: Skater = SkaterScene.instantiate() as Skater
	_screener = SkaterScene.instantiate() as Skater
	var ctrl := KeeperController.new()
	for n: Node in [goalie, puck, shooter, _screener, ctrl]:
		add_child_autofree(n)
	_screener.set_physics_process(false)
	_screener.set_process(false)
	_s = Stager.new(goalie, puck, ctrl, shooter)
	var screener: Skater = _screener
	ctrl.set_skater_getter(func() -> Array: return [shooter, screener])
	_body_radius = shooter.collision_radius()


# Every cell, in a fixed order: [spot_x, spot_fwd, along (-1: the baseline), across].
func _cells() -> Array:
	var out: Array = []
	for fwd: float in SPOT_FWD:
		for x: float in SPOT_X:
			var at := Vector2(x, GOAL_Z + fwd)
			if GameRules.clamp_to_rink_inner(at, _body_radius).distance_to(at) > 1e-4:
				continue
			out.append([x, fwd, -1.0, 0.0])
			for along: float in STATION_ALONG_M:
				for across: float in STATION_ACROSS_M:
					out.append([x, fwd, along, across])
	return out


# Where a cell's screener stands.
static func station(spot: Vector3, along: float, across: float) -> Vector3:
	if along < 0.0:
		return OUT_OF_PLAY
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var dir: Vector3 = (spot - goal).normalized()
	var left := Vector3(-dir.z, 0.0, dir.x)
	return goal + dir * along + left * across


func _row(index: int, cell: Array) -> String:
	var spot := Vector3(cell[0], 0.0, GOAL_Z + cell[1])
	_screener.global_position = station(spot, cell[2], cell[3])
	var at: Vector3 = _s.stage_set(spot)
	_s._capture_staged()
	var goals: int = 0
	var shots: int = 0
	for loft: int in Stager.LOFTS:
		for i: int in AIM_POINTS:
			_s._restore_staged()
			if _s.release(at, false, false, Vector3(Edges.aim_x(i, AIM_POINTS), 0.0, GOAL_Z),
					loft) == _s._h.GOAL:
				goals += 1
			shots += 1
	return "%d\t%.2f\t%.2f\t%.2f\t%.2f\t%d\t%d" % [index, cell[0], cell[1], cell[2], cell[3],
			goals, shots]


func test_measure_a_shard() -> void:
	var shards: int = int(OS.get_environment("MITTS_SCREEN_SHARDS"))
	if shards <= 0:
		pending("set MITTS_SCREEN_SHARD / MITTS_SCREEN_SHARDS (generate-screen-field.sh)")
		return
	var shard: int = int(OS.get_environment("MITTS_SCREEN_SHARD"))
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
	if OS.get_environment("MITTS_SCREEN_MERGE") != "1":
		pending("set MITTS_SCREEN_MERGE=1 (generate-screen-field.sh)")
		return
	var shards: int = int(OS.get_environment("MITTS_SCREEN_SHARDS"))
	var rows: Array[String] = []
	rows.resize(_cells().size())
	for shard: int in shards:
		for line: String in FileAccess.get_file_as_string(SHARD_PATH % shard).split("\n"):
			if not line.is_empty():
				rows[int(line.get_slice("\t", 0))] = line
	for i: int in rows.size():
		assert_false(rows[i].is_empty(), "cell %d was measured" % i)
	var out: PackedStringArray = [
		"class_name AIScreenFieldData",
		"",
		"# GENERATED by tests/instruments/ai/test_generate_screen_field.gd through",
		"# .claude/hooks/generate-screen-field.sh — never hand-edit. What a body in",
		"# front of the live goalie does to a charged wrister at a keeper settled",
		"# square on the carrier. Row columns: index, spot x, spot metres out, the",
		"# screener's distance from the goal's centre along the release's line to it",
		"# (-1: the baseline, nobody in front), his distance off the line (positive",
		"# to the shooter's left), goals, shots (3 lofts x AIM_POINTS aims).",
		"",
		"const FINGERPRINT: String = \"%s\"" % Fingerprint.compute(),
		"const SPOT_X: Array[float] = %s" % str(SPOT_X),
		"const SPOT_FWD: Array[float] = %s" % str(SPOT_FWD),
		"const STATION_ALONG_M: Array[float] = %s" % str(STATION_ALONG_M),
		"const STATION_ACROSS_M: Array[float] = %s" % str(STATION_ACROSS_M),
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

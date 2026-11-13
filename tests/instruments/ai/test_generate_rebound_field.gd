extends GutTest

# ── The REBOUND FIELD generator (docs/bot-net-front-offense-plan.md, step 2a) ──
# What the live goalie's save does with a shot: from each release spot, a
# keeper settled square on the carrier, a charged wrister at each loft and aim
# post to post, played out for REBOUND_TRACK_S through the real save loop
# (rebound_shot_harness.gd). Each shot is a row: the outcome, and for a live
# rebound the puck and the keeper every SAMPLE_TICKS from the first contact.
# Written as Scripts/domain/ai/generated/rebound_field_data.gd. Run it through
# .claude/hooks/generate-rebound-field.sh; re-run when the goalie changes
# (test_rebound_field_is_current.gd says when). Never hand-edit the output.
#
#   MITTS_REBOUND_SHARD=i MITTS_REBOUND_SHARDS=n   measure every n-th shot from i
#   MITTS_REBOUND_MERGE=1                          merge the shards, print a summary

const Harness := preload("res://tests/unit/ai/rebound_shot_harness.gd")
const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Edges := preload("res://tests/unit/ai/open_set_edges.gd")
const Fingerprint := preload("res://tests/unit/ai/rebound_field_fingerprint.gd")

const OUT_PATH: String = "res://Scripts/domain/ai/generated/rebound_field_data.gd"
const SHARD_PATH: String = "user://rebound_field_shard_%d.txt"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
# A coarse grid over where shots come from: the slot, the circles, the points.
const SPOT_X: Array[float] = [-8.0, -4.0, 0.0, 4.0, 8.0]
const SPOT_FWD: Array[float] = [3.5, 6.0, 9.5, 15.0, 19.5]
const AIM_POINTS: int = 8
# Outcome codes: G a goal on first contact; W wide or off the post untouched;
# C caught or held (the play stops); S saved, a live rebound; R saved, and the
# rebound went in.
const GOAL: String = "G"
const MISSED: String = "W"
const COVERED: String = "C"
const LIVE: String = "S"
const REBOUND_GOAL: String = "R"
# Far enough that the harness never stops tracking a rebound for leaving the
# danger area: it runs until the puck rests or REBOUND_TRACK_S is out.
const TRACK_EVERYWHERE_M: float = 1000.0

var _h: RefCounted = null
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
	_h = Harness.new()
	_h.setup(goalie, puck, ctrl, shooter)
	_h.danger_radius_m = TRACK_EVERYWHERE_M
	_body_radius = shooter.collision_radius()


# Every shot, in a fixed order: [spot_x, spot_fwd, loft, aim_x].
func _shots() -> Array:
	var out: Array = []
	for fwd: float in SPOT_FWD:
		for x: float in SPOT_X:
			var at := Vector2(x, GOAL_Z + fwd)
			if GameRules.clamp_to_rink_inner(at, _body_radius).distance_to(at) > 1e-4:
				continue
			for loft: int in Stager.LOFTS:
				for i: int in AIM_POINTS:
					out.append([x, fwd, loft, Edges.aim_x(i, AIM_POINTS)])
	return out


func _row(index: int, shot: Array) -> String:
	var spot := Vector3(shot[0], 0.0, GOAL_Z + shot[1])
	var aim := Vector3(shot[3], 0.0, GOAL_Z)
	var loft: int = shot[2]
	# The keeper set on a carrier skated in from up the ice (Stager._settle_on),
	# then the charge he reads.
	_h.approach_and_settle(spot, spot - Vector3(0.0, 0.0, signf(GOAL_Z) * Stager.APPROACH_M),
			Stager.APPROACH_M_S)
	_h.hold_windup_at(spot, aim, loft, Stager.SHOT_SPEED, Stager.CHARGE_TICKS)
	var verdict: int = _h.fire_release_tracking_rebound(spot, aim, loft, Stager.SHOT_SPEED)
	var code: String = LIVE
	if _h.last_part == -1:
		code = GOAL if verdict == _h.GOAL else MISSED
	elif _h.rebound_goal:
		code = REBOUND_GOAL
	elif _h.rebound_caught or _h.rebound_held:
		code = COVERED
	var samples: PackedStringArray = []
	if code == LIVE or code == REBOUND_GOAL:
		for k: int in _h.sample_pos.size():
			var p: Vector3 = _h.sample_pos[k]
			var v: Vector3 = _h.sample_vel[k]
			var gs: GoalieNetworkState = _h.sample_keeper[k]
			samples.append("%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d" % [p.x, p.z - GOAL_Z, p.y,
					v.x, v.z * -signf(GOAL_Z), gs.position_x, gs.position_z - GOAL_Z,
					gs.state_enum])
	return "%d\t%.2f\t%.2f\t%d\t%.3f\t%s\t%d\t%s" % [index, shot[0], shot[1], loft, shot[3],
			code, _h.last_part, ";".join(samples)]


func test_measure_a_shard() -> void:
	var shards: int = int(OS.get_environment("MITTS_REBOUND_SHARDS"))
	if shards <= 0:
		pending("set MITTS_REBOUND_SHARD / MITTS_REBOUND_SHARDS (generate-rebound-field.sh)")
		return
	var shard: int = int(OS.get_environment("MITTS_REBOUND_SHARD"))
	var shots: Array = _shots()
	var lines: PackedStringArray = []
	for i: int in shots.size():
		if i % shards == shard:
			lines.append(_row(i, shots[i]))
	var f := FileAccess.open(SHARD_PATH % shard, FileAccess.WRITE)
	assert_not_null(f, "can write shard %d" % shard)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	gut.p("shard %d/%d: %d shots" % [shard, shards, lines.size()])


func test_merge_the_shards() -> void:
	if OS.get_environment("MITTS_REBOUND_MERGE") != "1":
		pending("set MITTS_REBOUND_MERGE=1 (generate-rebound-field.sh)")
		return
	var shards: int = int(OS.get_environment("MITTS_REBOUND_SHARDS"))
	var rows: Array[String] = []
	rows.resize(_shots().size())
	for shard: int in shards:
		for line: String in FileAccess.get_file_as_string(SHARD_PATH % shard).split("\n"):
			if not line.is_empty():
				rows[int(line.get_slice("\t", 0))] = line
	for i: int in rows.size():
		assert_false(rows[i].is_empty(), "shot %d was measured" % i)
	var out: PackedStringArray = [
		"class_name AIReboundFieldData",
		"",
		"# GENERATED by tests/instruments/ai/test_generate_rebound_field.gd through",
		"# .claude/hooks/generate-rebound-field.sh — never hand-edit. What the live",
		"# goalie's save does with a charged wrister from a keeper set square on the",
		"# carrier. Row columns: index, spot x, spot metres out, loft, aim x, outcome",
		"# (G goal, W missed untouched, C caught or held, S saved and live, R saved",
		"# and the rebound in), the first SavePart touched (-1: none), then for S and",
		"# R the rebound every SAMPLE_S from the first contact, ';'-separated: puck x,",
		"# metres out, height, vx, v_out (its velocity away from the goal line),",
		"# keeper x, keeper metres out, keeper state_enum.",
		"",
		"const FINGERPRINT: String = \"%s\"" % Fingerprint.compute(),
		"const SAMPLE_S: float = %.4f" % (Harness.SAMPLE_TICKS * Harness.DT),
		"const SPOT_X: Array[float] = %s" % str(SPOT_X),
		"const SPOT_FWD: Array[float] = %s" % str(SPOT_FWD),
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
	gut.p("merged %d shots into %s" % [rows.size(), OUT_PATH])

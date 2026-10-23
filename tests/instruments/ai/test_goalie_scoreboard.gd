extends GutTest

# ── THE GOALIE SCOREBOARD ─────────────────────────────────────────────────────
# One table that says how good the goalie is, per difficulty tier, against
# SCRIPTED shooters only — the bots are not in it, so a change to how they
# play cannot move it (docs/goalie-rebuild-plan.md §5, Phase 0). Every row is a
# count of goals out of a fixed set of shots; lower is a better goalie.
#
#   sweep.*   perfect aim across the mouth (13 aims × FLAT/LOW/HIGH, 70 mph)
#             from a fixed spot at a set keeper — cold (the puck appears in
#             flight), held (a 0.25 s wind-up, then an honest release) or
#             sighted (a 0.75 s wind-up: long enough to be read and primed)
#   play.*    the moves that beat a goalie by moving him first: a rush shot off
#             the drive, the breakaway cutback and walkaround, a deke then
#             elevate, a pass out to a one-timer, a put-back of his own rebound
#             (shots: every first shot × the fan; only playable rebounds fire)
#   cover.*   the share of the mouth his body covers straight-on, per stance,
#             tested with the puck's real radius
#
# Either goalie runs it, through the same harness and rows: the old one
# (`test_report_the_old_goalie`, data/goalie_scoreboard.txt) and the rebuilt
# keeper (`test_report_the_keeper`, data/keeper_scoreboard.txt), whose rows
# print beside the old goalie's. Select one with -gunit_test_name. Run with
# MITTS_WRITE_SCOREBOARD=1 to rewrite the run goalie's file; without it every
# row prints beside the recorded value, so a change reads as a delta. There are
# no targets yet: the file records where a goalie stands.
#
# Every trial starts from a full reset, so a row does not depend on what ran
# before it (tests/CLAUDE.md → Determinism).

const Harness := preload("res://tests/unit/ai/human_wraparound_harness.gd")
const OUT_PATH: String = "res://tests/instruments/ai/data/goalie_scoreboard.txt"
const KEEPER_OUT_PATH: String = "res://tests/instruments/ai/data/keeper_scoreboard.txt"
const WRITE_ENV: String = "MITTS_WRITE_SCOREBOARD"
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const MAX_AIM: float = GameRules.NET_HALF_WIDTH \
		- GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
const SWEEP_AIMS: int = 13
const FAN_AIMS: int = 7
const SHOT_M_S: float = 70.0 * 0.44704
const HOLD_TICKS: int = 30
const SIGHTED_TICKS: int = 90
const SETTLE_MAX_TICKS: int = 400
const LOFTS: Array[int] = [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW,
		ShotMechanics.ELEVATION_HIGH]
const TIERS: Array[int] = [GoalieSkillProfile.Difficulty.EASY,
		GoalieSkillProfile.Difficulty.NORMAL, GoalieSkillProfile.Difficulty.HARD]

# Spots a human can stand on: the high slot between the end-zone dots, the
# doorstep, the faceoff dot itself (the classic angle shot), and the point.
const DOT_LINE := Vector3(0.0, 0.0, GOAL_Z + GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z)
const SLOT := Vector3(0.0, 0.0, GOAL_Z + 3.0)
const FACEOFF_DOT := Vector3(GameRules.END_ZONE_FACEOFF_DOT_X, 0.0,
		GOAL_Z + GameRules.GOAL_LINE_Z - GameRules.ICING_FACEOFF_DOT_Z)
const POINT := Vector3(-8.0, 0.0, GOAL_Z + 18.0)

# Pass-outs: from behind the net and the corner to a receiver loaded for a
# one-timer in the slot.
const PASSES: Array = [
	[Vector3(1.6, 0.0, GOAL_Z - 1.2), Vector3(0.3, 0.0, GOAL_Z + 5.0)],
	[Vector3(1.6, 0.0, GOAL_Z - 1.2), Vector3(-1.5, 0.0, GOAL_Z + 4.5)],
	[Vector3(4.0, 0.0, GOAL_Z + 0.3), Vector3(0.0, 0.0, GOAL_Z + 5.5)],
]
const PASS_M_S: float = GameRules.DEFAULT_QUICK_PASS_POWER_M_S
const ONE_TIMER_M_S: float = 30.0
# How far past the slot's edge a rebound the harness stopped following may lie
# and still be the shooter's: one tick of the slowest playable rebound.
const PUT_BACK_EDGE_M: float = 0.1

# Stances the coverage rows pose, each from the pose builder's own inputs; the
# keeper's from his own taught stances (he has no VH).
const COVER_STANCES: Array = [
	["ready", GoalieStateMachine.State.READY],
	["butterfly", GoalieStateMachine.State.BUTTERFLY],
	["half_butterfly", GoalieStateMachine.State.HALF_BUTTERFLY_LEFT],
	["rvh", GoalieStateMachine.State.RVH_LEFT],
	["vh", GoalieStateMachine.State.VH_LEFT],
]
const KEEPER_COVER_STANCES: Array[String] = ["ready", "butterfly", "half_butterfly", "rvh"]

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null
var _put_back_tries: int = 0
var _keeper: bool = false


func _build(keeper: bool) -> void:
	_keeper = keeper
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new() if keeper else GoalieController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)


func test_report_the_old_goalie() -> void:
	_build(false)
	_report(_score(), OUT_PATH, "")


func test_report_the_keeper() -> void:
	_build(true)
	_report(_score(), KEEPER_OUT_PATH, OUT_PATH)


func _score() -> Array[String]:
	var rows: Array[String] = []
	var totals: Array[int] = [0, 0, 0]
	for key: String in _row_keys():
		var cells: Array[String] = []
		for ti: int in TIERS.size():
			var tier: int = TIERS[ti]
			var goals: int = _measure(key, tier)
			cells.append(str(goals))
			if not key.begins_with("cover."):
				totals[ti] += goals
		rows.append("%s\t%s\t%d" % [key, "\t".join(cells), _shots(key)])
	rows.append("total\t%d\t%d\t%d\t%d" % [totals[0], totals[1], totals[2], _total_shots()])
	return rows


func _row_keys() -> Array[String]:
	var keys: Array[String] = [
		"sweep.dot_line.cold", "sweep.dot_line.held", "sweep.dot_line.sighted", "sweep.slot.cold",
		"sweep.faceoff_dot.cold", "sweep.faceoff_dot.held", "sweep.point.cold",
		"play.rush_shot", "play.breakaway_cutback", "play.breakaway_walkaround",
		"play.deke_elevate", "play.pass_out_one_timer", "play.put_back",
	]
	if _keeper:
		for stance: String in KEEPER_COVER_STANCES:
			keys.append("cover." + stance)
	else:
		for st: Array in COVER_STANCES:
			keys.append("cover." + String(st[0]))
	return keys


func _shots(key: String) -> int:
	if key.begins_with("sweep."):
		return SWEEP_AIMS * LOFTS.size()
	if key.begins_with("cover."):
		return 100
	match key:
		"play.deke_elevate":
			return 2 * FAN_AIMS
		"play.pass_out_one_timer":
			return PASSES.size() * 2 * FAN_AIMS
		"play.put_back":
			return _put_back_firsts().size() * FAN_AIMS
	return FAN_AIMS


func _total_shots() -> int:
	var n: int = 0
	for key: String in _row_keys():
		if not key.begins_with("cover."):
			n += _shots(key)
	return n


func _measure(key: String, tier: int) -> int:
	match key:
		"sweep.dot_line.cold":
			return _sweep(tier, DOT_LINE, false)
		"sweep.dot_line.held":
			return _sweep(tier, DOT_LINE, true)
		"sweep.dot_line.sighted":
			return _sweep(tier, DOT_LINE, true, SIGHTED_TICKS)
		"sweep.slot.cold":
			return _sweep(tier, SLOT, false)
		"sweep.faceoff_dot.cold":
			return _sweep(tier, FACEOFF_DOT, false)
		"sweep.faceoff_dot.held":
			return _sweep(tier, FACEOFF_DOT, true)
		"sweep.point.cold":
			return _sweep(tier, POINT, false)
		"play.rush_shot":
			return _rush_shot(tier)
		"play.breakaway_cutback":
			return _breakaway(tier, 1.0)
		"play.breakaway_walkaround":
			return _breakaway(tier, -1.0)
		"play.deke_elevate":
			return _deke_elevate(tier)
		"play.pass_out_one_timer":
			return _pass_out(tier)
		"play.put_back":
			_put_back_tries = 0
			var g: int = _put_back(tier)
			gut.p("    play.put_back on %s: %d of %d first-shot rebounds were playable"
					% [GoalieSkillProfile.Difficulty.keys()[tier], roundi(float(_put_back_tries) / float(FAN_AIMS)),
					_put_back_firsts().size()])
			return g
	# cover.* — percent of the mouth covered, not goals; the tier does not
	# change the body.
	if _keeper:
		return roundi(100.0 * _keeper_coverage(key.trim_prefix("cover.")))
	for s: Array in COVER_STANCES:
		if key == "cover." + String(s[0]):
			return roundi(100.0 * _coverage(s[1]))
	return -1


# A fresh keeper on the tier's profile. `apply_skill_profile` rebuilds the cached
# rule configs, so it goes on before anything reads them.
func _reset(tier: int) -> void:
	_ctrl.apply_skill_profile(GoalieSkillProfile.for_difficulty(tier))
	_ctrl.reset_to_crease()


# Settled on a carrier standing at `spot`. The harness calls a goalie settled
# once his lateral x and depth stop moving, which the keeper's turn on the spot
# before he skates satisfies; so he is ticked on until his motor is at rest.
func _settle_ready(spot: Vector3) -> void:
	_h.settle_ready(spot)
	if not _keeper:
		return
	var keeper := _ctrl as KeeperController
	for _i: int in SETTLE_MAX_TICKS:
		if keeper.motor.is_idle():
			return
		_puck.global_position = spot
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(DT)


func _aim(i: int, n: int) -> Vector3:
	return Vector3(lerpf(-MAX_AIM, MAX_AIM, float(i) / float(n - 1)), 0.0, GOAL_Z)


# ── Sweeps ──────────────────────────────────────────────────────────────────
func _sweep(tier: int, spot: Vector3, held: bool, hold_ticks: int = HOLD_TICKS) -> int:
	var goals: int = 0
	for loft: int in LOFTS:
		for ai: int in SWEEP_AIMS:
			var aim: Vector3 = _aim(ai, SWEEP_AIMS)
			_reset(tier)
			_settle_ready(spot)
			var o: int
			if held:
				_h.hold_windup_at(spot, aim, loft, SHOT_M_S, hold_ticks)
				o = _h.fire_release_at(spot, aim, loft, SHOT_M_S, 0.0)
			else:
				o = _h.fire_at(spot, aim, loft, SHOT_M_S, 0.0)
			if o == Harness.GOAL:
				goals += 1
	return goals


# ── Plays ───────────────────────────────────────────────────────────────────
# A shot off the drive, centre lane, released 5 m out: what challenge depth
# exists to cut the angle on.
func _rush_shot(tier: int) -> int:
	var goals: int = 0
	for ai: int in FAN_AIMS:
		_reset(tier)
		_settle_ready(Vector3(0.0, 0.0, GOAL_Z + 14.0))
		_h.begin_trial()
		_h.bait_commit(0.0, 14.0, 5.0, 6.0)
		var spot := Vector3(0.0, 0.0, GOAL_Z + 5.0)
		if _h.fire_release_at(spot, _aim(ai, FAN_AIMS), ShotMechanics.ELEVATION_LOW,
				28.0, 0.0) == Harness.GOAL:
			goals += 1
	return goals


# Drive at him, pull the puck across to commit him, then come back across
# (`side` +1, the cutback) or carry on round him (−1, the walkaround). Same bait
# and release as test_goalie_breakaway_ladder.
func _breakaway(tier: int, side: float) -> int:
	var goals: int = 0
	for ai: int in FAN_AIMS:
		_reset(tier)
		_settle_ready(Vector3(0.0, 0.0, GOAL_Z + 9.0))
		_h.begin_trial()
		_h.bait_commit(0.0, 9.0, 0.9, 5.0, 1.1, 0.25, 3.5)
		var rel: Vector3 = _h.wrap_to(side * 1.35, 0.70, 4.0)
		if _h.fire_release_at(rel, _aim(ai, FAN_AIMS), ShotMechanics.ELEVATION_FLAT,
				18.0, 0.0) == Harness.GOAL:
			goals += 1
	return goals


# From 5 m, a quick lateral move each way, then lift it: the shot that beats a
# goalie who goes down on the move.
func _deke_elevate(tier: int) -> int:
	var goals: int = 0
	for side: float in [-1.0, 1.0]:
		for ai: int in FAN_AIMS:
			_reset(tier)
			var start := Vector3(0.0, 0.0, GOAL_Z + 5.0)
			_settle_ready(start)
			var rel: Vector3 = _h.deke_across(side * 1.2, 0.35, 2.0)
			if _h.fire_at(rel, _aim(ai, FAN_AIMS), ShotMechanics.ELEVATION_HIGH,
					25.0, 0.0) == Harness.GOAL:
				goals += 1
	return goals


# A pass from behind the net or the corner, taken as a one-timer in the slot.
func _pass_out(tier: int) -> int:
	var goals: int = 0
	for p: Array in PASSES:
		var passer: Vector3 = p[0]
		var receiver: Vector3 = p[1]
		for loft: int in [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_HIGH]:
			for ai: int in FAN_AIMS:
				_reset(tier)
				_feed(passer, receiver)
				if _h.fire_at(receiver, _aim(ai, FAN_AIMS), loft, ONE_TIMER_M_S,
						0.0) == Harness.GOAL:
					goals += 1
	return goals


# The goalie sets on the passer, then the puck travels to a receiver loaded for
# the one-timer, who shoots on arrival.
func _feed(passer: Vector3, receiver: Vector3) -> void:
	_settle_ready(passer)
	_puck.clear_carrier()
	_shooter.global_position = receiver
	_shooter.velocity = Vector3.ZERO
	_shooter.current_shot_state = SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK
	var vel: Vector3 = (receiver - passer).normalized() * PASS_M_S
	var ticks: int = int(passer.distance_to(receiver) / PASS_M_S / DT)
	var pos: Vector3 = passer
	for _i: int in ticks:
		pos += vel * DT
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)


# First shots whose rebounds are tried as put-backs: low shots from the slot
# and the off-angle, where a real rebound lands.
func _put_back_firsts() -> Array:
	var out: Array = []
	for spot: Vector3 in [Vector3(0.0, 0.0, GOAL_Z + 5.0), Vector3(2.0, 0.0, GOAL_Z + 4.5)]:
		for loft: int in [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW]:
			for ai: int in 3:
				out.append([spot, loft, _aim(ai * 3, FAN_AIMS)])
	return out


# Fire the first shot; if it leaves a live rebound in the danger area, a shooter
# on that spot fires the fan straight away. Counts put-back goals (a first shot
# that scores is a sweep row's business, not this one's).
func _put_back(tier: int) -> int:
	var goals: int = 0
	for first: Array in _put_back_firsts():
		for ai: int in FAN_AIMS:
			_reset(tier)
			_settle_ready(first[0])
			var o: int = _h.fire_tracking_rebound(first[0], first[2], first[1], 25.0, 0.0)
			if o != Harness.SAVE or _h.rebound_goal or _h.rebound_caught \
					or _h.rebound_held or _h.rebound_swept:
				continue
			# The harness follows a rebound until it comes to rest in the slot or
			# leaves it; either way a skater waiting there can play it if it is
			# slow enough to take.
			var at: Vector3 = _h.rebound_pos
			if Vector2(at.x, at.z - GOAL_Z).length() > _h.danger_radius_m + PUT_BACK_EDGE_M \
					or _h.rebound_speed > Harness.PLAYABLE_SPEED_M_S:
				continue
			at.y = 0.0
			_put_back_tries += 1
			if _h.fire_at(at, _aim(ai, FAN_AIMS), ShotMechanics.ELEVATION_LOW,
					20.0, 0.0) == Harness.GOAL:
				goals += 1
	return goals


# ── Coverage ────────────────────────────────────────────────────────────────
# Share of the mouth (a 1 cm grid, post to post, ice to bar) a puck fired
# straight down the goal line's normal meets his body, with the goalie posed
# at rest in `state` on the goal line. A grid cell counts as covered when the
# puck's swept disc touches any part — the same test the save loop runs.
func _coverage(state: int) -> float:
	var b := GoalieBodyConfigBuilder.new()
	var inp := GoalieBodyConfigBuilder.Inputs.new()
	inp.state = state
	inp.direction_sign = -1
	inp.puck_position = Vector3(0.0, GameRules.PUCK_COLLISION_HALF_HEIGHT, -0.6)
	var g: Goalie = _goalie as Goalie
	g.global_position = Vector3.ZERO
	g.rotation = Vector3.ZERO
	var c: GoalieBodyConfig = b.build(inp)
	for _k: int in 3:
		g.apply_body_config(c, 1.0)
	var scratch := SweptDiscOBB.Result.new()
	var contact := GoalieContactDetector.Contact.new()
	var goalies: Array = [g]
	var covered: int = 0
	var total: int = 0
	var half_w: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS
	var x: float = -half_w
	while x <= half_w:
		var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
		while y <= GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS:
			total += 1
			if GoalieContactDetector.nearest(goalies, Vector3(x, y, -3.0),
					Vector3(x, y, 1.0), GameRules.PUCK_COLLISION_RADIUS, scratch, contact):
				covered += 1
			y += 0.01
		x += 0.01
	return float(covered) / float(maxi(total, 1))


# The keeper's share of the mouth straight on, posed at rest in `stance` on
# the goal line: the old goalie's grid and test, against his gear.
func _keeper_coverage(stance: String) -> float:
	var pose := KeeperPose.new()
	match stance:
		"ready":
			KeeperPoses.ready(pose)
		"butterfly":
			KeeperPoses.butterfly(pose)
		"half_butterfly":
			KeeperPoses.half_butterfly(pose, -1.0)
		"rvh":
			KeeperPoses.rvh(pose, -1.0)
	var skel := KeeperSkeleton.new()
	skel.pose(pose)
	var out := SweptDiscOBB.Result.new()
	var scratch := SweptDiscOBB.Result.new()
	var covered: int = 0
	var total: int = 0
	var half_w: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS
	var x: float = -half_w
	while x <= half_w:
		var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
		while y <= GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS:
			total += 1
			if KeeperGear.nearest(skel, Vector3(x, y, -3.0), Vector3(x, y, 1.0),
					GameRules.PUCK_COLLISION_RADIUS, out, scratch) >= 0:
				covered += 1
			y += 0.01
		x += 0.01
	return float(covered) / float(maxi(total, 1))


# ── Output ──────────────────────────────────────────────────────────────────
# The rows beside what `path` recorded, and beside the old goalie's (`beside`)
# when this is the keeper; written over `path` on request.
func _report(rows: Array[String], path: String, beside: String) -> void:
	var header: String = "row\tEASY\tNORMAL\tHARD\tshots"
	var recorded: Dictionary = _read_recorded(path)
	var old: Dictionary = _read_recorded(beside) if not beside.is_empty() else {}
	gut.p("%s SCOREBOARD — goals conceded per tier (cover.* is %% of the mouth)"
			% ("KEEPER" if _keeper else "GOALIE"))
	gut.p(header + ("\t| recorded EASY/NORMAL/HARD" if not recorded.is_empty() else "")
			+ ("\t| old goalie" if not old.is_empty() else ""))
	for r: String in rows:
		var key: String = r.get_slice("\t", 0)
		var was: String = ""
		if recorded.has(key):
			was = "\t| " + String(recorded[key])
		if old.has(key):
			was += "\t| old " + String(old[key])
		gut.p(r + was)
	if OS.get_environment(WRITE_ENV) == "1":
		var f := FileAccess.open(path, FileAccess.WRITE)
		assert_not_null(f, "can write %s" % path)
		if f != null:
			f.store_string("\n".join(PackedStringArray([
				"# %s scoreboard — written by tests/instruments/ai/test_goalie_scoreboard.gd"
						% ("Keeper" if _keeper else "Goalie"),
				"# with %s=1; never hand-edit. Goals conceded per tier (cover.*: %% of mouth)." % WRITE_ENV,
				header,
			] + rows)) + "\n")
			gut.p("written: %s" % path)
	assert_true(true, "report")


func _read_recorded(path: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	while f != null and not f.eof_reached():
		var line: String = f.get_line()
		if line.is_empty() or line.begins_with("#") or line.begins_with("row\t"):
			continue
		var parts: PackedStringArray = line.split("\t")
		if parts.size() >= 4:
			out[parts[0]] = "%s/%s/%s" % [parts[1], parts[2], parts[3]]
	return out

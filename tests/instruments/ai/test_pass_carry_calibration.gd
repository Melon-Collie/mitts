extends GutTest

# Are the carrier's pass and carry reads honest? Real bots in the duel harness,
# from the O-zone possession instrument's starts (test_ozone_possession.gd, at
# the real keeper), the neutral-zone entry drill's and the breakout drill's. Every pass a bot of either side releases is logged with the
# completion its search priced (AICarrierPassSearch.debug_kept: not poked at the
# release × the lane × no execution miss × kept on reception) and what happened:
# kept (his side holds it RECEPTION_HOLD_S after first touching it, or the man
# who took it released it on inside that hold), lost (their man first, or theirs
# within the hold), or loose (nobody has it within LOOSE_AFTER_S: left out). Every CARRY_SAMPLE_S a carrier skating a carry is
# logged with AICarrySpace.carry_safety from the puck to his chosen carry spot
# over his time to it (the carry search's own read, escape gate on), and whether
# he still had it then: kept, lost, or released (he passed or shot first: left
# out). A dump-in releases through the pass press with no receiver and is left
# out. Prints reliability tables: priced against realised, per band; each
# interception against the pass as it left (_intercept_row); each pass's line as
# priced, as aimed and as thrown, per outcome (_exec_row); and each rim against
# the path walk it was priced on (_trace_rims).

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const Ozone := preload("res://tests/instruments/ai/test_ozone_possession.gd")
const SECS: float = 12.0
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const KEEPER_SETTLE_S: float = 1.5
const RECEPTION_HOLD_S: float = 0.5
const LOOSE_AFTER_S: float = 2.0
const CARRY_SAMPLE_S: float = 0.5
const CARRY_WINDOW_MAX_S: float = 1.5
const BANDS: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8, 0.95, 1.0001]

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController
# Per event: [priced, outcome (1 kept, 0 lost), team, extra].
var _passes: Array = []
var _carries: Array = []
var _how: Dictionary = {}
# Per interception (_intercept_row): the priced lane, the interceptor's block on
# the line thrown and on the line priced, the turn between them, the priced
# length, where he stood off and along the thrown line, how soon he took it, the
# puck's pace, the thrown length, and how long before the release the carrier
# last chose.
var _intercepts: Array = []
# Per interception (_receiver_row): the catch the passer priced against the man
# who took it, where he stood at the release.
var _receiver_rows: Array = []
# Per pass (_lead_start): the receiver against the lead his passer priced.
var _leads: Array = []
# Which drill the current run belongs to, for the lead table.
var _family: String = "ozone"
# Per carrier, the tick he committed to his pending pass and his own view then:
# [tick, opponents at the release (his projection), their velocities, caps,
# blades at the release, the priced spot, the priced lane].
var _commit: Dictionary = {}
var _commit_rows: Array = []
# Per carrier, his latest pass reading and the tick and view it was read in.
var _searched: Dictionary = {}
# Per saucer: [priced pace, thrown pace, priced over-the-blades from, to (m),
# flown in the harness (m), pass length (m), tick].
var _saucers: Array = []
# Per pass with a seen commit, its _exec_row and how it went.
var _exec: Array = []
# Per rim in flight: [receiver, predicted puck (AITrajectory's walk), its
# velocity, ticks flown, gaps to the walk at 0.5/1.0/1.5 s, closest the receiver's
# blade came, outcome, launch pace, the rim's priced pace, the latch's pace, the
# receiver as logged / searched / the agent's, ticks he spent chasing it]; done
# rims move to _rim_done.
var _rims: Array = []
var _rim_done: Array = []


func before_all() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child(n)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_ctrl.setup(_goalie, _puck, GOAL_Z, true)


func after_all() -> void:
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		n.queue_free()


# test_ozone_possession's setup, at this file's keeper.
func _setup(carrier: Vector3, vel: Vector3, mate_a: Vector3, mate_b: Vector3,
		tight: bool) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	duel.add_skater(101, 0, carrier, null, vel)
	duel.add_skater(102, 0, mate_a)
	duel.add_skater(103, 0, mate_b)
	var side: float = signf(carrier.x) if absf(carrier.x) > 0.5 else 1.0
	if tight:
		duel.add_skater(201, 1, Vector3(side * 3.5, 0, -22.5))
		duel.add_skater(202, 1, Vector3(-side * 1.0, 0, -23.0))
		duel.add_skater(203, 1, Vector3(side * 1.5, 0, -15.0))
	else:
		duel.add_skater(201, 1, Vector3(side * 5.5, 0, -21.5))
		duel.add_skater(202, 1, Vector3(0.0, 0, -24.0))
		duel.add_skater(203, 1, Vector3(side * 0.5, 0, -13.0))
	duel.start(101)
	_ctrl.reset_to_crease()
	_shooter.global_position = carrier
	_puck.set_carrier(_shooter)
	_puck.global_position = carrier
	for _i: int in int(KEEPER_SETTLE_S / Duel.DT):
		_ctrl._physics_process(Duel.DT)
	duel.goalie_provider = func(team_id: int, puck_pos: Vector3) -> Variant:
		if team_id != 1:
			return null
		_shooter.global_position = puck_pos
		_puck.global_position = puck_pos
		_ctrl._physics_process(Duel.DT)
		return _goalie.global_position
	return duel


func _team_of(duel: Object, pid: int) -> int:
	return int(duel.team_map.get(pid, -1))


func _sim(duel: Object, pid: int) -> Object:
	for s: Object in duel.skaters:
		if s.peer_id == pid:
			return s
	return null


# The carry read the carrier would make from the puck to his chosen spot now.
func _carry_read(duel: Object, s: Object) -> Array:
	var carrier: AIRoleCarrier = s.agent._carrier
	var to: Vector3 = carrier.debug_carry_pos
	if not to.is_finite() or to == Vector3.ZERO:
		return []
	var t: float = AIArrival.time_to_arrive(duel.puck_pos, to, s.vel)
	if t <= 0.0:
		return []
	var opps: Array[Vector3] = []
	var vels: Array[Vector3] = []
	for o: Object in duel.skaters:
		if o.team_id != s.team_id:
			opps.append(o.pos)
			vels.append(o.vel)
	return [AICarrySpace.carry_safety(duel.puck_pos, to, t, opps, vels, [], true),
			minf(t, CARRY_WINDOW_MAX_S)]


# The pass as it left: its release point and velocity, its receiver where he
# stood, and the other side's bodies, blades and motion then.
func _release_view(duel: Object, rec: Dictionary) -> Dictionary:
	var opps: Array = []
	for o: Object in duel.skaters:
		if o.team_id != int(rec["team"]):
			opps.append([o.peer_id, o.pos, o.vel, o.blade])
	var receiver: Object = _sim(duel, int(rec["pass_peer"]))
	return {"from": duel.puck_pos, "vel": duel.puck_vel,
			"to": receiver.pos if receiver != null else duel.puck_pos, "opps": opps}


# An interception, read against the pass as it left: where the interceptor stood
# off its line and along it, how soon he took it, and the block lane_clear's
# accurate read gives him alone on the line from the release to the receiver.
func _intercept_row(view: Dictionary, interceptor: int, ticks_after: int,
		rec: Dictionary) -> Array:
	var priced_lane: float = float(rec["pass_lane"])
	var from: Vector3 = view["from"]
	var v: Vector3 = view["vel"]
	v.y = 0.0
	var speed: float = v.length()
	var dir: Vector3 = v / speed if speed > 0.01 else Vector3.FORWARD
	var length: float = maxf(Vector2(view["to"].x - from.x, view["to"].z - from.z).length(), 1.0)
	for o: Array in view["opps"]:
		if o[0] != interceptor:
			continue
		var rel: Vector3 = o[1] - from
		var along: float = rel.x * dir.x + rel.z * dir.z
		var off: float = absf(rel.x * dir.z - rel.z * dir.x)
		var opps: Array[Vector3] = [o[1]]
		var vels: Array[Vector3] = [o[2]]
		var blades: Array[Vector3] = [o[3]]
		var block: float = 1.0 - AIPuckLane.lane_clear(from, from + dir * length, opps,
				speed, vels, [], true, blades)
		# The line it priced, with everyone where they stood at the release.
		var spot: Vector3 = rec["pass_spot"]
		var priced_dir: Vector3 = spot - from
		priced_dir.y = 0.0
		var turn: float = rad_to_deg(dir.angle_to(priced_dir)) if priced_dir.length() > 0.01 \
				else 0.0
		var priced_block: float = 1.0 - AIPuckLane.lane_clear(from, spot, opps, speed, vels, [],
				true, blades)
		return [priced_lane, block, priced_block, turn, priced_dir.length(), off,
				along / length, ticks_after * Duel.DT, speed, length,
				int(rec.get("since_pick_ticks", -1)) * Duel.DT]
	return []


# Remembers each carrier's own view the tick he commits to a pass (his agent
# enters PASS_PRESSED; the carrier's intent is cleared that same tick).
func _watch_commit(duel: Object, c: int, tick: int) -> void:
	if c == -1:
		return
	var s: Object = _sim(duel, c)
	if s == null or s.agent == null or s.agent._carrier == null:
		return
	var carrier: AIRoleCarrier = s.agent._carrier
	# Each new pass reading: the carrier's view as its search saw it.
	var reading: Array = [carrier._pass.debug_completion, carrier._pass.debug_spot]
	if _searched.get(c, [[]])[0] != reading:
		var fs: AICarrierField = carrier._field
		_searched[c] = [reading, tick, fs.opponents_release.duplicate()]
	if s.agent._state != SkaterAgentStateMachine.State.PASS_PRESSED:
		_commit.erase(c)
		return
	if _commit.has(c):
		return
	var f: AICarrierField = carrier._field
	_commit[c] = [tick, f.opponents_release.duplicate(), f.opponent_vels.duplicate(),
			f.opponent_caps.duplicate(), f.opponent_blades_release.duplicate(),
			carrier._pass.debug_spot, carrier._pass.debug_completion.y,
			Vector3(carrier._pass.debug_origin_pace.x, 0.0, carrier._pass.debug_origin_pace.z),
			carrier._pass.debug_origin_pace.w, _searched.get(c, [[], -1, []]),
			carrier._pass.best_is_saucer, s.agent._dump_target.is_finite(),
			carrier._pass.best_rim_pace, carrier._pass.best_peer, s.agent._pass_target_peer_id,
			_receiver_state(duel, s.agent._pass_target_peer_id),
			s.agent._accel_by_peer.get(s.agent._pass_target_peer_id, Vector3.ZERO)]


# The receiver `pid`'s body at this tick: [position, velocity], or [] if none.
func _receiver_state(duel: Object, pid: int) -> Array:
	var r: Object = _sim(duel, pid)
	return [r.pos, r.vel] if r != null else []


# An interception against the passer's own view at his commit: his priced lane,
# that lane recomputed from his view (it should be the same), the commit to the
# release, and where he had the interceptor at the release against where he was.
func _commit_row(view: Dictionary, commit: Array, interceptor: int, release_tick: int) -> Array:
	if commit.is_empty():
		return []
	var spot: Vector3 = commit[5]
	var from: Vector3 = commit[7]
	var speed: float = Vector2(view["vel"].x, view["vel"].z).length()
	var opps: Array[Vector3] = []
	opps.assign(commit[1])
	var vels: Array[Vector3] = []
	vels.assign(commit[2])
	var blades: Array[Vector3] = []
	blades.assign(commit[4])
	var lane_mine: float = AIPuckLane.lane_clear(from, spot, opps, speed, vels, commit[3],
			true, blades)
	var miss_m: float = -1.0
	var blade_miss_m: float = -1.0
	var k: int = 0
	for o: Array in view["opps"]:
		if o[0] == interceptor and k < opps.size():
			miss_m = Vector2(o[1].x - opps[k].x, o[1].z - opps[k].z).length()
			blade_miss_m = Vector2(o[3].x - blades[k].x, o[3].z - blades[k].z).length()
		k += 1
	var priced_speed: float = float(commit[8])
	var lane_priced_pace: float = AIPuckLane.lane_clear(from, spot, opps, priced_speed, vels,
			commit[3], true, blades)
	# How long before the commit his search read this pass, and how far the
	# interceptor's projected spot moved between that read and the commit.
	var searched: Array = commit[9]
	var search_age: float = (int(commit[0]) - int(searched[1])) * Duel.DT \
			if int(searched[1]) >= 0 else -1.0
	var drift_m: float = -1.0
	k = 0
	for o: Array in view["opps"]:
		if o[0] == interceptor and k < opps.size() and k < searched[2].size():
			drift_m = Vector2(opps[k].x - searched[2][k].x, opps[k].z - searched[2][k].z).length()
		k += 1
	var saucer_mine: float = AIPuckLane.lane_clear_saucer(from, spot, opps, priced_speed, vels,
			commit[3])
	# The interceptor alone on the priced line: his body on the landed stretch (the
	# saucer's read), his body on the whole line, and his stick where he holds it.
	var parts: String = ""
	var j: int = 0
	for o: Array in view["opps"]:
		if o[0] == interceptor and j < opps.size():
			var line_len: float = from.distance_to(spot)
			var dir: Vector3 = (spot - from) / line_len
			var vy: float = AIPuckLane.saucer_launch_vy(priced_speed)
			var root: float = sqrt(maxf(0.0, vy * vy
					- 2.0 * GameRules.GRAVITY_M_S2 * GameRules.PUCK_AIRBORNE_HEIGHT_M))
			var t_down: float = (vy + root) / GameRules.GRAVITY_M_S2
			var flown: float = priced_speed * t_down
			var landed_len: float = line_len - flown
			var landed_speed: float = landed_len / AIPuckLane._friction_traverse_time(landed_len,
					priced_speed) if landed_len > 0.01 else priced_speed
			var caps_j: AISkaterCaps = commit[3][j]
			var reach: float = AILaneReach.defender_reach(caps_j)
			var vmax: float = caps_j.max_speed if caps_j != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
			var acc: float = caps_j.max_accel if caps_j != null else GameRules.DEFAULT_SKATER_THRUST_M_S2
			var read_len: float = line_len - AIPuckLane.LANE_RECEIVER_REACH_M
			var hold: float = caps_j.max_blade_reach if caps_j != null \
					else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
			var delay: float = AIPuckLane.lane_read_delay(from, opps[j], hold)
			var landed: float = AILaneReach.block(from.x, from.z, dir.x, dir.z, read_len,
					landed_speed, opps[j].x, opps[j].z, vels[j].x, vels[j].z, reach, vmax, acc,
					delay, flown, t_down).x
			var eff: float = line_len / AIPuckLane._friction_traverse_time(line_len, priced_speed)
			var whole: float = AILaneReach.block(from.x, from.z, dir.x, dir.z, read_len, eff,
					opps[j].x, opps[j].z, vels[j].x, vels[j].z, reach, vmax, acc,
					delay).x
			var stick: float = AIPuckLane._blade_block(from.x, from.z, dir.x, dir.z, read_len, eff,
					blades[j].x, blades[j].z, opps[j].x, opps[j].z, vels[j].x, vels[j].z,
					hold, AIPuckLane.LANE_LATERAL_FRACTION * vmax,
					caps_j.blade_speed if caps_j != null else AISkaterCaps.LEAGUE_BLADE_SPEED_M_S,
					delay, delay).x
			parts = "  his body landed %.2f, body whole line %.2f, stick %.2f; reach %.2f, lands at %.1f m" \
					% [landed, whole, stick, reach, flown]
		j += 1
	var flat_no_sticks: float = AIPuckLane.lane_clear(from, spot, opps, priced_speed, vels,
			commit[3], true)
	return [float(commit[6]), lane_mine, lane_priced_pace, priced_speed, speed,
			(release_tick - int(commit[0])) * Duel.DT, miss_m, blade_miss_m, search_age, drift_m,
			("saucer %.2f, flat without sticks %.2f" % [saucer_mine, flat_no_sticks]) + parts
			if commit[10] else "flat"]


# A pass as it left, against what was priced at the commit: the priced line
# (commit origin to spot) and pace, the line the agent locked at the release (its
# lead re-solved through the windup, the committed scatter, from the blade) and
# the puck's flight, the lateral miss of each at the priced spot's distance.
func _exec_row(duel: Object, rec: Dictionary, commit: Array) -> Dictionary:
	if commit.is_empty():
		return {}
	var s: Object = _sim(duel, int(rec["peer"]))
	var puck: Vector3 = rec["pass_puck"]
	var spot: Vector3 = commit[5]
	var origin: Vector3 = commit[7]
	var priced: Vector3 = Vector3(spot.x - origin.x, 0.0, spot.z - origin.z)
	var aimed: Vector3 = s.agent._pass_aim_dir_locked
	var thrown: Vector3 = Vector3(duel.puck_vel.x, 0.0, duel.puck_vel.z)
	var dist: float = priced.length()
	var from_puck: Vector3 = Vector3(spot.x - puck.x, 0.0, spot.z - puck.z)
	return {"len": dist, "origin_off": Vector2(puck.x - origin.x, puck.z - origin.z).length(),
		"aim_turn": rad_to_deg(priced.angle_to(aimed)),
		"throw_turn": rad_to_deg(aimed.angle_to(thrown)),
		"miss_aimed": _off_line(from_puck, aimed),
		"miss_thrown": _off_line(from_puck, thrown),
		"scatter": rad_to_deg(absf(s.agent._committed_aim_error_rad)),
		"pace_priced": float(commit[8]), "pace_thrown": thrown.length(),
		"saucer": bool(commit[10]), "rim": bool(commit[11]), "kept": float(rec["pass_kept"]),
		"commit_s": (int(rec["tick"]) - int(commit[0])) * Duel.DT,
		"reception": float(rec["pass_reception"]), "lane": float(rec["pass_lane"])}


# How far `p` (relative to the line's start) sits off the line along `dir`.
static func _off_line(p: Vector3, dir: Vector3) -> float:
	var d: Vector3 = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	return absf(p.x * d.z - p.z * d.x)


func _log_exec(row: Dictionary, how: String) -> void:
	if row.is_empty():
		return
	row["how"] = how
	_exec.append(row)


# Per outcome: the passes, their mean priced completion, and the medians of each
# execution term.
func _report_exec() -> void:
	gut.p("  execution, per outcome (medians):")
	gut.p("     outcome              n   priced  len   origin  aim turn  throw turn  miss aimed  miss thrown  scatter  pace priced/thrown  commit (s)  lane  reception")
	var outcomes: Array = ["kept", "kept, another mate", "lost on the catch", "intercepted", "loose"]
	var keys: Array[String] = []
	for how: String in outcomes:
		keys.append(how)
	for how: String in outcomes:
		keys.append("rim: " + how)
	for key: String in keys:
		var rim: bool = key.begins_with("rim: ")
		var how: String = key.trim_prefix("rim: ")
		var rows: Array = _exec.filter(func(r: Dictionary) -> bool:
				return r["how"] == how and r["rim"] == rim)
		if rows.is_empty():
			continue
		var kept: float = 0.0
		for r: Dictionary in rows:
			kept += r["kept"]
		gut.p("     %-18s %4d   %4.2f   %4.1f  %4.2f    %5.1f     %5.1f       %4.2f        %4.2f       %4.1f    %4.1f / %4.1f        %4.2f        %4.2f  %4.2f" % [
				key, rows.size(), kept / rows.size(), _median(rows, "len"),
				_median(rows, "origin_off"), _median(rows, "aim_turn"),
				_median(rows, "throw_turn"), _median(rows, "miss_aimed"),
				_median(rows, "miss_thrown"), _median(rows, "scatter"),
				_median(rows, "pace_priced"), _median(rows, "pace_thrown"),
				_median(rows, "commit_s"), _median(rows, "lane"), _median(rows, "reception")])
	gut.p("  every pass missing its priced spot by over a metre as thrown:")
	gut.p("     outcome              len   aim turn  throw turn  miss aimed  miss thrown  scatter  pace priced/thrown  saucer")
	for r: Dictionary in _exec:
		if r["miss_thrown"] > 1.0:
			gut.p("     %-18s %4.1f  %5.1f     %5.1f       %4.2f        %4.2f       %4.1f    %4.1f / %4.1f        %s" % [
					r["how"], r["len"], r["aim_turn"], r["throw_turn"], r["miss_aimed"],
					r["miss_thrown"], r["scatter"], r["pace_priced"], r["pace_thrown"],
					"rim" if r["rim"] else ("yes" if r["saucer"] else "")])


static func _median(rows: Array, key: String) -> float:
	var v: Array[float] = []
	for r: Dictionary in rows:
		v.append(float(r[key]))
	v.sort()
	return v[v.size() / 2]


# Each rim in flight a tick on: the walk the rim search priced it on, stepped
# alongside the harness puck, and the receiver's blade against it, until somebody
# plays it or it has slid LOOSE_AFTER_S.
func _trace_rims(duel: Object, c: int, c_team: int) -> void:
	for r: Array in _rims:
		var stepped: Transform3D = AITrajectory.step_puck(r[1], r[2], Duel.DT)
		r[1] = stepped.origin
		r[2] = stepped.basis.x
		r[3] += 1
		var gap: float = Vector2(duel.puck_pos.x - r[1].x, duel.puck_pos.z - r[1].z).length()
		for k: int in 3:
			if r[3] == int((k + 1) * 0.5 / Duel.DT):
				r[4][k] = gap
		var receiver: Object = _sim(duel, int(r[0]))
		if receiver != null:
			r[5] = minf(r[5], Vector2(duel.puck_pos.x - receiver.blade.x,
					duel.puck_pos.z - receiver.blade.z).length())
			if receiver.agent != null \
					and receiver.agent._state == SkaterAgentStateMachine.State.CHASE_PUCK:
				r[11] += 1
		if c != -1:
			r[6] = ("receiver" if c == r[0] else ("mate" if c_team == _team_of(duel, r[0])
					else "theirs")) + " at %.2f s" % (r[3] * Duel.DT)
		elif r[3] > int(LOOSE_AFTER_S / Duel.DT):
			r[6] = "loose, at %.1f m/s" % Vector2(duel.puck_vel.x, duel.puck_vel.z).length()
	for r: Array in _rims:
		if r[6] != "":
			_rim_done.append(r)
	_rims = _rims.filter(func(r: Array) -> bool: return r[6] == "")


func _report_rims() -> void:
	gut.p("  rims: %d" % _rim_done.size())
	gut.p("     pace (thrown / rim priced / latch)  off the priced walk at 0.5 / 1.0 / 1.5 s (m)   receiver's blade closest (m)   he chased (s)   receiver (logged/search/agent)   first played")
	for r: Array in _rim_done:
		gut.p("     %4.1f / %4.1f / %4.1f                %5.2f / %5.2f / %5.2f                        %5.2f                          %4.2f            %-16s   %s"
				% [r[7], r[8], r[9], r[4][0], r[4][1], r[4][2], r[5], r[11] * Duel.DT, r[10], r[6]])


# A saucer as it left: the airborne stretch the harness flies (its launch
# loft, from the load-capped pace), against the one lane_clear_saucer priced
# from the priced pace (over the blades from t_over to t_down).
func _saucer_flight(duel: Object, commit: Array, tick: int) -> void:
	var speed: float = Vector2(duel.puck_vel.x, duel.puck_vel.z).length()
	var priced: float = float(commit[8])
	var vy: float = AIPuckLane.saucer_launch_vy(priced)
	var root: float = sqrt(maxf(0.0,
			vy * vy - 2.0 * GameRules.GRAVITY_M_S2 * GameRules.PUCK_AIRBORNE_HEIGHT_M))
	var t_over: float = (vy - root) / GameRules.GRAVITY_M_S2
	var t_down: float = (vy + root) / GameRules.GRAVITY_M_S2
	_saucers.append([priced, speed, priced * t_over, priced * t_down,
			duel.airborne_ticks * Duel.DT * speed,
			commit[5].distance_to(commit[7]), tick])


func _run(duel: Object, zone_ends: bool = true, secs: float = SECS) -> void:
	var open_passes: Array = []   # [record index, release tick, team, first touch tick, holder team]
	var open_carries: Array = []  # [priced, team, peer, until tick, possession tick]
	var ticks: int = int(secs / Duel.DT)
	var sample_every: int = int(CARRY_SAMPLE_S / Duel.DT)
	for i: int in ticks:
		var before: int = duel.releases.size()
		var touches_before: int = duel.deflects + duel.bobbles + duel.contests
		var bobbles_before: int = duel.bobbles
		var deflects_before: int = duel.deflects
		duel.step()
		var c: int = duel.carrier()
		var c_team: int = _team_of(duel, c) if c != -1 else -1
		_watch_commit(duel, c, i)
		if duel.releases.size() > before:
			var rec: Dictionary = duel.releases[-1]
			var decision: String = str(rec.get("decision", ""))
			# A pass: to a mate of his, on a release that is not a shot. A dump-in
			# releases through the pass press too, with no receiver in the agent: it
			# is a race, not a pass, and is left out.
			var to: int = int(rec.get("pass_peer", -1))
			var commit: Array = _commit.get(int(rec["peer"]), [])
			var dump_in: bool = commit.size() > 14 and int(commit[14]) == -1
			if dump_in:
				_how["dump-in, left out"] = int(_how.get("dump-in, left out", 0)) + 1
			if not dump_in and not decision in ["SHOOT", "ONE_TIMER"] \
					and to > 0 and _team_of(duel, to) == int(rec["team"]) \
					and float(rec.get("pass_kept", -1.0)) >= 0.0:
				if commit.size() > 11 and commit[11]:
					_rims.append([to, Vector3(rec["pass_puck"].x, 0.0, rec["pass_puck"].z),
							Vector3(duel.puck_vel.x, 0.0, duel.puck_vel.z), 0, [-1.0, -1.0, -1.0], INF,
							"", Vector2(duel.puck_vel.x, duel.puck_vel.z).length(), commit[12],
							commit[8], "%d/%d/%d" % [to, commit[13], commit[14]], 0])
				open_passes.append([rec, i, int(rec["team"]), -1, -1, -1,
						_release_view(duel, rec), commit, _exec_row(duel, rec, commit),
						{"min_d": INF, "touch": "", "speed_at": 0.0, "rcv_at": Vector3.INF,
								"state": "", "lead": _lead_start(duel, rec, i, commit)}])
				if commit.size() > 10 and commit[10]:
					_saucer_flight(duel, commit, i)
			# A carrier who released leaves his open carry samples.
			for oc: Array in open_carries:
				if oc[2] == int(rec["peer"]):
					oc[3] = -1
		_trace_rims(duel, c, c_team)
		# Passes: the first side to touch it, then whether it holds through the catch.
		for op: Array in open_passes:
			_lead_sample(duel, op[9]["lead"], i)
			if op[3] == -1:
				# The receiver's blade on the puck while it is in flight to him.
				var rs: Object = _sim(duel, int(op[0]["pass_peer"]))
				if rs != null:
					var bd: float = Vector2(rs.blade.x - duel.puck_pos.x,
							rs.blade.z - duel.puck_pos.z).length()
					if bd < op[9]["min_d"]:
						op[9]["min_d"] = bd
						op[9]["rcv_at"] = rs.pos
						op[9]["state"] = SkaterAgentStateMachine.State.keys()[rs.agent._state] \
								if rs.agent != null else "?"
						op[9]["speed_at"] = Vector2(duel.puck_vel.x - rs.vel.x,
								duel.puck_vel.z - rs.vel.z).length()
					if op[9]["touch"] == "" and duel.deflects + duel.bobbles + duel.contests \
							> touches_before and bd < 1.0:
						op[9]["touch"] = "bobbled" if duel.bobbles > bobbles_before \
								else ("deflected" if duel.deflects > deflects_before
										else "contested")
				if c != -1:
					op[3] = i
					op[4] = c_team
					op[5] = c
					if c_team != op[2]:
						var row: Array = _intercept_row(op[6], c, i - op[1], op[0])
						if not row.is_empty():
							_intercepts.append(row)
							_commit_rows.append(_commit_row(op[6], op[7], c, op[1]))
							var rr: Array = _receiver_row(duel, op[6], op[0], c, i - op[1])
							if not rr.is_empty():
								var led: Vector3 = op[0].get("pass_spot", Vector3.INF)
								var at: Vector3 = op[9]["rcv_at"]
								rr.append_array([op[9]["min_d"], op[9]["speed_at"],
										op[9]["touch"] if op[9]["touch"] != "" else "-",
										Vector2(at.x - led.x, at.z - led.z).length()
												if at.is_finite() and led.is_finite() else -1.0,
										op[9]["state"]])
							_receiver_rows.append(rr)
				elif i - op[1] > int(LOOSE_AFTER_S / Duel.DT):
					op[3] = -2   # loose: left out
					_how["loose"] = int(_how.get("loose", 0)) + 1
					_log_exec(op[8], "loose")
					_lead_close(op[9]["lead"], "loose")
			elif op[3] >= 0 and i - op[3] == int(RECEPTION_HOLD_S / Duel.DT):
				var kept: bool = op[4] == op[2] and c_team == op[2]
				# Released on by the man who took it (a one-timer, a quick shot or
				# pass) before the hold is up: he had it.
				if not kept and op[4] == op[2] and c == -1:
					for k: int in range(duel.releases.size() - 1, -1, -1):
						var later: Dictionary = duel.releases[k]
						if int(later["tick"]) < duel.ticks - (i - op[3]):
							break
						if int(later["peer"]) == op[5]:
							kept = true
							_how["moved on in the hold"] = int(_how.get("moved on in the hold", 0)) + 1
							break
				_passes.append([float(op[0]["pass_kept"]), 1 if kept else 0, op[2], op[0]])
				var how: String = "kept" if kept else ("intercepted" if op[4] != op[2]
						else "lost on the catch")
				if kept and op[5] != int(op[0]["pass_peer"]):
					how = "kept, another mate"
				_how[how] = int(_how.get(how, 0)) + 1
				_log_exec(op[8], how)
				_lead_close(op[9]["lead"], how)
				op[3] = -3
		open_passes = open_passes.filter(func(op: Array) -> bool: return op[3] > -2)
		# Carries: sample, then score at the window's end.
		for oc: Array in open_carries:
			if oc[3] == -1:
				continue
			if c != oc[2] and c != -1:
				_carries.append([oc[0], 1 if c_team == oc[1] else 0, oc[1]])
				oc[3] = -1
			elif i >= oc[3]:
				_carries.append([oc[0], 1 if c == oc[2] else 0, oc[1]])
				oc[3] = -1
		open_carries = open_carries.filter(func(oc: Array) -> bool: return oc[3] != -1)
		if c != -1 and i % sample_every == 0:
			var s: Object = _sim(duel, c)
			if s != null and s.agent != null and s.agent._carrier != null \
					and s.agent._carrier.intended_action == AIRoleCarrier.INTENT_CARRY:
				var read: Array = _carry_read(duel, s)
				if not read.is_empty():
					open_carries.append([read[0], c_team, c, i + int(read[1] / Duel.DT)])
		if not duel.releases.is_empty() and duel.releases.size() > before:
			var last: Dictionary = duel.releases[-1]
			if str(last.get("decision", "")) in ["SHOOT", "ONE_TIMER"]:
				return
		if zone_ends and absf(duel.puck_pos.z) < GameRules.BLUE_LINE_Z and c == -1 \
				and open_passes.is_empty():
			return


func _table(label: String, events: Array) -> void:
	gut.p("  %s: %d" % [label, events.size()])
	gut.p("     priced band     n   priced  realised")
	for b: int in BANDS.size() - 1:
		var n: int = 0
		var p: float = 0.0
		var k: int = 0
		for e: Array in events:
			if e[0] >= BANDS[b] and e[0] < BANDS[b + 1]:
				n += 1
				p += e[0]
				k += e[1]
		if n > 0:
			gut.p("     %.2f-%.2f  %5d   %5.2f   %5.2f" % [BANDS[b], minf(BANDS[b + 1], 1.0), n,
					p / n, float(k) / n])
	var tp: float = 0.0
	var tk: int = 0
	for e: Array in events:
		tp += e[0]
		tk += e[1]
	if not events.is_empty():
		gut.p("     all        %5d   %5.2f   %5.2f" % [events.size(), tp / events.size(),
				float(tk) / events.size()])


func test_report_pass_and_carry_calibration() -> void:
	for start: Array in Ozone.new()._starts():
		var vels: Array = [Vector3.ZERO] + start[3]
		for combo: int in 2 * vels.size() * 2:
			var m := Vector3(1.0 if combo % 2 == 0 else -1.0, 1.0, 1.0)
			var vel: Vector3 = vels[(combo >> 1) % vels.size()] * m
			var tight: bool = combo >= 2 * vels.size()
			_run(_setup(start[0] * m, vel, start[1] * m, start[2] * m, tight))
	var ozone: int = _passes.size()
	_family = "entry"
	# test_nz_entry_drill's entries and test_breakout_drill's breakouts.
	for n_def: int in [2, 3]:
		for x: float in [0.0, 3.0, 5.0, -6.0, -9.0]:
			for v: float in [1.0, 3.0, 5.0]:
				_run(_entry(x, v, n_def), false, 8.0)
	var entries: int = _passes.size() - ozone
	_family = "breakout"
	for cx: float in [-8.0, -3.0, 0.0, 4.0, 9.0]:
		for cz: float in [20.0, 24.0]:
			for f1_gap: float in [4.0, 7.0]:
				var carrier := Vector3(cx, 0, cz)
				_run(_breakout(carrier, carrier + Vector3(-signf(cx + 0.1), 0, -f1_gap),
						Vector3(-cx * 0.5, 0, 12.0)), false, 8.0)
	gut.p("passes: %d from the O-zone starts, %d from entries, %d from breakouts"
			% [ozone, entries, _passes.size() - ozone - entries])
	_table("passes, both sides", _passes)
	gut.p("  how they went: %s" % str(_how))
	# Each loss mode's survival against the losses it explains.
	var mode_rows: Array = []
	for e: Array in _passes:
		var rec: Dictionary = e[3]
		mode_rows.append([float(rec["pass_release_clean"]) * float(rec["pass_lane"])
				* (1.0 - float(rec["pass_miss"])), e[1]])
	_table("passes, the flight alone (release × lane × no miss)", mode_rows)
	_table("carries, both sides", _carries)
	_report_intercepts()
	_report_receiver_end()
	_report_leads()
	_report_exec()
	_report_rims()
	gut.p("  saucers: %d" % _saucers.size())
	gut.p("     priced m/s  thrown m/s  priced over the blades (m)  flown (m)  pass (m)")
	for r: Array in _saucers:
		gut.p("     %5.1f       %5.1f       %4.1f to %4.1f                %4.1f       %4.1f"
				% [r[0], r[1], r[2], r[3], r[4], r[5]])
	assert_true(true)


# The catch an interception beat, as the passer's reception read prices it: the
# man who took it where he stood at the release, and his reach on the catch spot
# when the puck gets there (AICarrySpace.reach_clearance, the passer's
# catch_safety) committed for the read's short window and for the whole flight;
# how far his body and blade stood from the spot, and where along the line he
# took it.
func _receiver_row(duel: Object, view: Dictionary, rec: Dictionary, interceptor: int,
		ticks_after: int) -> Array:
	var spot: Vector3 = rec.get("pass_spot", Vector3.INF)
	if not spot.is_finite():
		return []
	var from: Vector3 = view["from"]
	var v: Vector3 = view["vel"]
	v.y = 0.0
	var speed: float = maxf(v.length(), 1.0)
	var dist: float = Vector2(spot.x - from.x, spot.z - from.z).length()
	var flight: float = AIPuckLane._friction_traverse_time(dist, speed)
	var receiver: Object = _sim(duel, int(rec["pass_peer"]))
	var r_vel: Vector3 = receiver.vel if receiver != null else Vector3.ZERO
	var settle: float = AIFeedReception.receiver_settle_s(
			AIFeedReception.arrival_closing_speed(from, spot, speed, r_vel))
	var caps: Array = [Duel.match_caps()]
	var pick: Vector3 = duel.puck_pos
	var dir: Vector3 = (spot - from) / maxf(dist, 0.01)
	var pick_along: float = ((pick.x - from.x) * dir.x + (pick.z - from.z) * dir.z) / maxf(dist, 0.01)
	for o: Array in view["opps"]:
		if o[0] != interceptor:
			continue
		var p: Vector3 = o[1]
		var pv: Vector3 = o[2]
		var b: Vector3 = o[3]
		var opps: Array[Vector3] = [p]
		var vels: Array[Vector3] = [pv]
		var short: float = AICarrySpace.reach_clearance(spot, flight + settle, opps, vels, caps,
				AICarrySpace.EVADE_HORIZON_S + settle)
		var whole: float = AICarrySpace.reach_clearance(spot, flight + settle, opps, vels, caps)
		return [float(rec.get("pass_reception", -1.0)),
				AICarrySpace.clearance_to_safety(short), AICarrySpace.clearance_to_safety(whole),
				short, whole, Vector2(p.x - spot.x, p.z - spot.z).length(),
				Vector2(b.x - spot.x, b.z - spot.z).length(), pv.length(),
				flight, settle, pick_along, ticks_after * Duel.DT]
	return []


# The receiver against the lead his passer priced: where he stood and how he
# moved at the release, the spot he was led to, and the puck's flight there
# (friction-true, at its launch pace off the blade).
func _lead_start(duel: Object, rec: Dictionary, tick: int, commit: Array) -> Dictionary:
	var spot: Vector3 = rec.get("pass_spot", Vector3.INF)
	var rs: Object = _sim(duel, int(rec.get("pass_peer", -1)))
	if rs == null or not spot.is_finite():
		return {}
	var from: Vector3 = duel.puck_pos
	var speed: float = maxf(Vector2(duel.puck_vel.x, duel.puck_vel.z).length(), 1.0)
	var flight: float = AIPuckLane._friction_traverse_time(
			Vector2(spot.x - from.x, spot.z - from.z).length(), speed)
	var at_commit: Array = commit[15] if commit.size() > 15 else []
	var since: float = (tick - int(commit[0])) * Duel.DT if not commit.is_empty() else 0.0
	return {"peer": rs.peer_id, "pos": rs.pos, "vel": rs.vel, "spot": spot,
			"flight": flight, "end_tick": tick + maxi(roundi(flight / Duel.DT), 1),
			"at": Vector3.INF, "vel_at": Vector3.ZERO, "states": {}, "how": "",
			"c_pos": at_commit[0] if not at_commit.is_empty() else Vector3.INF,
			"c_vel": at_commit[1] if not at_commit.is_empty() else Vector3.ZERO,
			"since": since,
			"kind": "rim" if commit.size() > 11 and commit[11] else (
					"saucer" if commit.size() > 10 and commit[10] else "flat"),
			"lead_cv": _lead_from_commit(commit),
			"lead_acc": _accel_lead_from_commit(commit),
			"family": _family}


# The passer's lead at his commit, re-solved from the receiver's body there at the
# pace he priced, released a windup on (no pull).
func _lead_from_commit(commit: Array) -> Vector3:
	if commit.size() < 17 or commit[15].is_empty():
		return Vector3.INF
	var st := SkaterNetworkState.new()
	st.position = commit[15][0]
	st.velocity = commit[15][1]
	return AIPassLead.lead(commit[7], st, maxf(commit[8], 1.0),
			AICarrierPassSearch.PASS_LEAD_MAX_S, AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S)[0]


# The lead from the commit as it would be extrapolating the acceleration the
# passer's agent read off the receiver (along his travel, capped at his thrust and
# top speed): the read the lead does not take, set beside where he went.
func _accel_lead_from_commit(commit: Array) -> Vector3:
	if commit.size() < 17 or commit[15].is_empty():
		return Vector3.INF
	var caps: AISkaterCaps = Duel.match_caps()
	var pos: Vector3 = commit[15][0]
	var vel: Vector3 = commit[15][1]
	var a: Vector3 = commit[16]
	var speed: float = Vector2(vel.x, vel.z).length()
	if speed > 0.5:
		var dir: Vector3 = vel / speed
		a = dir * a.dot(dir)
	if a.length() > caps.max_accel:
		a = a.normalized() * caps.max_accel
	var cap: float = maxf(speed, caps.max_speed)
	var release_s: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	var body: Vector3 = AITrajectory.predict_at(pos, vel, release_s, 6, a, cap)
	var v: Vector3 = vel + a * release_s
	if Vector2(v.x, v.z).length() > cap:
		v *= cap / Vector2(v.x, v.z).length()
	var from: Vector3 = commit[7]
	var eff: float = AIPassLead.effective_flight_speed(maxf(commit[8], 1.0), from.distance_to(body))
	var t: float = AITrajectory.intercept_time(from, body, v, a, eff,
			AICarrierPassSearch.PASS_LEAD_MAX_S, 6, cap)
	return AITrajectory.predict_at(body, v, t, 6, a, cap)


# Each tick of the flight: what the receiver's agent is doing, and at the flight's
# end where he is.
func _lead_sample(duel: Object, l: Dictionary, tick: int) -> void:
	if l.is_empty() or l["at"].is_finite():
		return
	var rs: Object = _sim(duel, l["peer"])
	if rs == null:
		return
	if rs.agent != null:
		var st: String = SkaterAgentStateMachine.State.keys()[rs.agent._state]
		l["states"][st] = int(l["states"].get(st, 0)) + 1
	if tick >= l["end_tick"]:
		l["at"] = rs.pos
		l["vel_at"] = rs.vel


func _lead_close(l: Dictionary, how: String) -> void:
	if l.is_empty() or l["how"] != "":
		return
	l["how"] = how
	_leads.append(l)


func _report_leads() -> void:
	gut.p("  the receiver against his lead, when the puck gets there:")
	gut.p("     outcome              n   off the lead  constant velocity   speed at release  speed change  turned    mostly doing   | from the commit: velocity change  constant velocity  commit to")
	gut.p("                              (m, median)   would be off (m)    (m/s)             (m/s)         (deg)                 | to the release (m/s)               would be off (m)   release (s)")
	var by: Dictionary = {}
	for l: Dictionary in _leads:
		if not l["at"].is_finite():
			continue
		by.get_or_add("%s %s" % [l["kind"], l["how"]], []).append(l)
		by.get_or_add("~%s, %s" % [l["family"], "kept" if l["how"].begins_with("kept") else "not"],
				[]).append(l)
	var keys: Array = by.keys()
	keys.sort()
	for how: String in keys:
		var rows: Array = by[how]
		var off: Array[float] = []
		var cv: Array[float] = []
		var spd: Array[float] = []
		var dspd: Array[float] = []
		var turn: Array[float] = []
		var states: Dictionary = {}
		var at_acc: Array[float] = []
		var at_cv: Array[float] = []
		var spot_cv: Array[float] = []
		var c_dv: Array[float] = []
		var c_cv: Array[float] = []
		var since: Array[float] = []
		for l: Dictionary in rows:
			if l["lead_cv"].is_finite():
				spot_cv.append(Vector2(l["spot"].x - l["lead_cv"].x, l["spot"].z - l["lead_cv"].z).length())
				at_cv.append(Vector2(l["at"].x - l["lead_cv"].x, l["at"].z - l["lead_cv"].z).length())
				if l["lead_acc"].is_finite():
					at_acc.append(Vector2(l["at"].x - l["lead_acc"].x, l["at"].z - l["lead_acc"].z).length())
			if l["c_pos"].is_finite():
				var cvc: Vector3 = l["c_pos"] + l["c_vel"] * (l["since"] + l["flight"])
				c_cv.append(Vector2(cvc.x - l["spot"].x, cvc.z - l["spot"].z).length())
				c_dv.append(Vector2(l["vel"].x - l["c_vel"].x, l["vel"].z - l["c_vel"].z).length())
				since.append(l["since"])
			var at: Vector3 = l["at"]
			var spot: Vector3 = l["spot"]
			var v0: Vector3 = l["vel"]
			var v1: Vector3 = l["vel_at"]
			var cv_at: Vector3 = l["pos"] + v0 * l["flight"]
			off.append(Vector2(at.x - spot.x, at.z - spot.z).length())
			cv.append(Vector2(cv_at.x - spot.x, cv_at.z - spot.z).length())
			spd.append(Vector2(v0.x, v0.z).length())
			dspd.append(Vector2(v1.x, v1.z).length() - Vector2(v0.x, v0.z).length())
			turn.append(rad_to_deg(Vector2(v0.x, v0.z).angle_to(Vector2(v1.x, v1.z)))
					if Vector2(v0.x, v0.z).length() > 0.5 and Vector2(v1.x, v1.z).length() > 0.5
					else 0.0)
			for st: String in l["states"]:
				states[st] = int(states.get(st, 0)) + int(l["states"][st])
		var top: String = ""
		var best: int = 0
		for st: String in states:
			if states[st] > best:
				best = states[st]
				top = st
		gut.p("     %-18s %3d   %5.2f          %5.2f               %4.1f              %+5.1f         %5.0f    %-14s |  %4.1f                             %5.2f              %4.2f" % [
				how, rows.size(), _med(off), _med(cv), _med(spd), _med(dspd),
				_med(turn.map(func(x: float) -> float: return absf(x))), top,
				_med(c_dv), _med(c_cv), _med(since)])
		gut.p("         the spot against his lead re-solved at the commit %.2f m; where he got to, off that lead %.2f m, off the lead on his read acceleration %.2f m" % [
				_med(spot_cv), _med(at_cv), _med(at_acc)])


static func _med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


func _report_receiver_end() -> void:
	gut.p("  the catch each interception beat:")
	gut.p("     priced   catch safety,       clearance (m),   his body  his blade  his    flight  settle  taken at  after  | receiver's blade: closest  rel m/s  touched  | receiver off his lead (m), doing")
	gut.p("     reception  short / whole     short / whole    to spot   to spot    m/s    (s)     (s)     the line  (s)    |                   (m)")
	var short_safe: int = 0
	var late: int = 0
	for r: Array in _receiver_rows:
		if r.is_empty():
			continue
		gut.p("     %4.2f       %4.2f / %4.2f       %5.2f / %5.2f    %4.1f      %4.1f       %4.1f   %4.2f    %4.2f    %4.2f      %4.2f   |  %5.2f    %5.1f    %-8s |  %4.1f  %s" % r)
		if r[10] >= 0.7:
			late += 1
			if r[1] >= 0.8:
				short_safe += 1
	gut.p("     %d taken in the last 30%% of the line; of those, %d the short window priced safe (>= 0.8)"
			% [late, short_safe])


func _report_intercepts() -> void:
	gut.p("  interceptions: %d" % _intercepts.size())
	gut.p("     priced  block on  block on the  turn   priced  off   along  after  puck  length  chose")
	gut.p("     lane    its line  priced line   (deg)  length  (m)          (s)    m/s           (s) ago")
	var unblocked: int = 0
	var block_sum: float = 0.0
	for r: Array in _intercepts:
		gut.p("     %4.2f    %4.2f      %4.2f         %5.1f  %5.1f   %4.1f  %4.2f   %4.2f   %4.1f  %5.1f   %4.2f" % r)
		block_sum += r[1]
		if r[1] < 0.2:
			unblocked += 1
	if not _intercepts.is_empty():
		gut.p("     mean block %.2f; %d of %d read as nearly no threat (< 0.2)"
				% [block_sum / _intercepts.size(), unblocked, _intercepts.size()])
	gut.p("  the passer's own view at his commit, per interception:")
	gut.p("     priced  at the thrown  at the priced  priced  thrown  commit to    interceptor  his blade  search before  he moved")
	gut.p("     lane    pace           pace           m/s     m/s     release (s)  off (m)      off (m)    commit (s)     since (m)")
	for r: Array in _commit_rows:
		if r.is_empty():
			gut.p("     (no commit seen)")
		else:
			gut.p("     %4.2f    %4.2f           %4.2f           %4.1f    %4.1f    %4.2f         %4.2f         %4.2f       %5.2f          %4.2f   %s" % r)


# test_nz_entry_drill's setup: the carrier deep in his own half with two
# wingers, two defenders up at their line, and with `n_def` 3 a backchecker.
func _entry(carrier_x: float, speed: float, n_def: int) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	duel.add_skater(101, 0, Vector3(carrier_x, 0, 12.0), null, Vector3(0, 0, -speed))
	duel.add_skater(102, 0, Vector3(7.0 if carrier_x <= 0.0 else -7.0, 0, 10.0), null,
			Vector3(0, 0, -speed))
	duel.add_skater(103, 0, Vector3(-carrier_x * 0.3, 0, 16.0), null, Vector3(0, 0, -speed * 0.5))
	duel.add_skater(201, 1, Vector3(-3.0, 0, -8.5), null, Vector3.ZERO)
	duel.add_skater(202, 1, Vector3(3.0, 0, -8.5), null, Vector3.ZERO)
	if n_def >= 3:
		duel.add_skater(203, 1, Vector3(carrier_x * 0.5, 0, 6.0), null, Vector3(0, 0, -3.0))
	duel.start(101)
	return duel


# test_breakout_drill's setup: the carrier low in his own end, a forechecker on
# him and another high.
func _breakout(carrier: Vector3, f1: Vector3, f2: Vector3) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	duel.add_skater(101, 0, carrier)
	duel.add_skater(102, 0, Vector3(10.0, 0, 16.0))
	duel.add_skater(103, 0, Vector3(-10.0, 0, 14.0))
	duel.add_skater(201, 1, f1, null, (carrier - f1).normalized() * 4.0)
	duel.add_skater(202, 1, f2, null, Vector3(0, 0, 2.0))
	duel.start(101)
	for peer: int in [201, 202]:
		var s: Object = duel._skater(peer)
		s.blade = s.pos + (carrier - s.pos).limit_length(Duel.BLADE_REACH)
		s.prev_blade = s.blade
	return duel

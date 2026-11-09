extends GutTest

# Five Hard bots set up in their zone against five Hard defenders in zone
# coverage, on the duel harness, against the real keeper: how a 5v5 possession
# that starts low in the zone ends (a shot, a turnover, the puck out), how long
# it lasts, how often the puck moves, and — at every shot — what the carrier
# priced the shot at against the best pass he saw, beside what the shot field's
# set read says the keeper concedes from there. test_ozone_possession.gd's 3v3
# sweep, in 5v5, with the compete's two sides logged.
# Team 0 attacks -Z. Not modelled: offside, rebounds (a possession ends at its
# first shot), board pins (the harness's).

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const SECS: float = 12.0
const DOTS_OUT_M: float = 6.1
const SLOT_NEAR_M: float = 1.5
const SLOT_FAR_M: float = 10.0
const SLOT_HALF_WIDTH_M: float = 4.5
const POINT_OUT_M: float = 15.0
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const KEEPER_SETTLE_S: float = 1.5
const OURS: Array[int] = [101, 102, 103, 104, 105]
const THEIRS: Array[int] = [201, 202, 203, 204, 205]

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController
# The keeper as the bots read him: his whole replicated state (stance, facing,
# velocity), or only his position as the harness's default keeper.
var _keeper_state: GoalieNetworkState = GoalieNetworkState.new()
var _full_keeper: bool = true


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


static func _out(p: Vector3) -> float:
	return p.z + GameRules.GOAL_LINE_Z


static func _in_slot(p: Vector3) -> bool:
	var out: float = _out(p)
	return out >= SLOT_NEAR_M and out <= SLOT_FAR_M and absf(p.x) <= SLOT_HALF_WIDTH_M


static func _shot_kind(p: Vector3) -> String:
	if _in_slot(p):
		return "slot"
	if _out(p) >= POINT_OUT_M:
		return "point"
	if _out(p) < DOTS_OUT_M and absf(p.x) > SLOT_HALF_WIDTH_M:
		return "angle"
	return "other"


static func _is_shot(rec: Dictionary) -> bool:
	return rec.get("decision", "") in ["SHOOT", "ONE_TIMER"]


# One possession: { end, t, low_s, passes, shots: [shot records] }. A shot
# record: its kind, release spot, the carrier's priced shot, best pass (and the
# receiver's spot), carry, and the set read at the release.
func _run(duel: Object) -> Dictionary:
	var r: Dictionary = {"end": "timeout", "t": SECS, "low_s": 0.0, "passes": 0, "shot": {}}
	var passing: bool = false
	var last_pass: Dictionary = {}
	var last_pass_t: float = 0.0
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	for i: int in int(SECS / Duel.DT):
		var before: int = duel.releases.size()
		duel.step()
		var t: float = (i + 1) * Duel.DT
		var released: Dictionary = {}
		if duel.releases.size() > before and int(duel.releases[-1]["team"]) == 0:
			released = duel.releases[-1]
		var c: int = duel.carrier()
		var ours: bool = c != -1 and duel.team_map[c] == 0
		if ours:
			passing = false
		if ours and _out(duel.puck_pos) <= DOTS_OUT_M:
			r["low_s"] += Duel.DT
		if not released.is_empty():
			if _is_shot(released):
				var at: Vector3 = released["pos"]
				var s: Dictionary = {"kind": _shot_kind(at), "pos": at,
						"decision": released["decision"],
						"set": AIShotValue.set_keeper(at, goal),
						"pass": float(released.get("pass_score", 0.0)),
						"carry": float(released.get("carry_score", 0.0)),
						"shot": 0.0, "pass_to": Vector3.INF}
				var agent: SkaterAgentStateMachine = null
				for sk: Object in duel.skaters:
					if sk.peer_id == int(released["peer"]):
						agent = sk.agent
				var puck: Vector3 = released.get("pass_puck", at)
				var keeper: Vector3 = _goalie.global_position
				keeper.y = 0.0
				s["puck"] = puck
				s["keeper"] = keeper
				s["keeper_vx"] = _keeper_state.velocity_x
				s["stance"] = AIShotOdds.stance_of(_keeper_state, goal)
				s["live"] = AIShotValue.now(puck, goal, keeper, _keeper_state.velocity_x,
						s["stance"], _keeper_state.rotation_y, AIShotOdds.History.CARRIED)
				s["set_puck"] = AIShotValue.set_keeper(puck, goal)
				var mates: String = ""
				for pid: int in OURS:
					if pid == int(released["peer"]):
						continue
					var mp: Vector3 = duel.skater_pos(pid)
					if _out(mp) > POINT_OUT_M:
						continue
					mates += " (%4.1f,%4.1f) feed %.2f set %.2f" % [mp.x, _out(mp),
							AIShotValue.feed(puck, mp, 16.0, goal, keeper, true),
							AIShotValue.set_keeper(mp, goal)]
				s["mates"] = mates
				if agent != null and agent._carrier != null:
					s["shot"] = agent._carrier.debug_shoot_score
					s["history"] = agent._carrier._shot_history()
					var pp: int = int(released.get("pass_peer", 0))
					if pp > 0:
						s["pass_to"] = duel.skater_pos(pp)
				r["end"] = "shot"
				r["t"] = t
				r["shot"] = s
				return r
			r["passes"] += 1
			passing = true
			last_pass = released
			last_pass_t = t
		if c != -1 and duel.team_map[c] == 1:
			r["end"] = "picked" if passing else "stripped"
			r["t"] = t
			if passing and not last_pass.is_empty():
				var from: Vector3 = last_pass.get("pass_puck", last_pass["pos"])
				var to: Vector3 = last_pass.get("pass_spot", Vector3.INF)
				var who: Vector3 = duel.skater_pos(c)
				var off: float = -1.0
				if to.is_finite():
					var d: Vector3 = (to - from)
					d.y = 0.0
					d = d.normalized()
					off = absf((who.x - from.x) * d.z - (who.z - from.z) * d.x)
				r["pick"] = "priced lane %.2f kept %.2f (clean %.2f miss %.2f catch %.2f) | %s -> %s | picked %.2f s after by a man %.1f m off its line, at (%.1f, %.1f out)" % [
						float(last_pass.get("pass_lane", -1.0)), float(last_pass.get("pass_kept", -1.0)),
						float(last_pass.get("pass_release_clean", -1.0)),
						float(last_pass.get("pass_miss", -1.0)),
						float(last_pass.get("pass_reception", -1.0)),
						"(%.1f, %.1f out)" % [from.x, _out(from)],
						"(%.1f, %.1f out)" % [to.x, _out(to)] if to.is_finite() else "?",
						t - last_pass_t, off, who.x, _out(who)]
			return r
		if duel.puck_pos.z > -GameRules.BLUE_LINE_Z:
			r["end"] = "out-ours" if passing else ("out-carried" if ours else "cleared")
			r["t"] = t
			return r
	return r


# Our carrier low (`carrier`, skating at `vel`), two forwards at `fa` and `fb`,
# both D on the points; their five in zone coverage, tight (the strong D already
# on the carrier) or home.
func _setup(carrier: Vector3, vel: Vector3, fa: Vector3, fb: Vector3, tight: bool) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 5
	for k: int in 5:
		duel.positions[OURS[k]] = k
		duel.positions[THEIRS[k]] = k
	var side: float = signf(carrier.x) if absf(carrier.x) > 0.5 else 1.0
	var point_z: float = -(GameRules.BLUE_LINE_Z + 2.0)
	var hard: BotSkillProfile = BotSkillProfile.hard()
	duel.add_skater(OURS[0], 0, carrier, hard, vel)
	duel.add_skater(OURS[1], 0, fa, hard)
	duel.add_skater(OURS[2], 0, fb, hard)
	duel.add_skater(OURS[3], 0, Vector3(side * 6.5, 0, point_z), hard)
	duel.add_skater(OURS[4], 0, Vector3(-side * 6.0, 0, point_z), hard)
	# Their F1-F3 then their D pair.
	var strong_d := Vector3(side * 5.5, 0, -21.5)
	if tight:
		strong_d = carrier + (Vector3(0, 0, -21.0) - carrier).normalized() * 2.0
	duel.add_skater(THEIRS[0], 1, Vector3(side * 1.5, 0, -19.5), hard)
	duel.add_skater(THEIRS[1], 1, Vector3(side * 7.0, 0, -12.5), hard)
	duel.add_skater(THEIRS[2], 1, Vector3(-side * 5.0, 0, -13.5), hard)
	duel.add_skater(THEIRS[3], 1, strong_d, hard)
	duel.add_skater(THEIRS[4], 1, Vector3(-side * 1.0, 0, -24.0), hard)
	duel.start(OURS[0])
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
		_keeper_state = GoalieNetworkState.new()
		_ctrl.fill_state(_keeper_state)
		return _keeper_state if _full_keeper else _goalie.global_position
	return duel


# Starts (carrier, forward a, forward b, carrier velocities), each run as given
# and mirrored, standing and skating each way, the defence tight and home: the
# half-wall low, the corner, behind the net, below the circle off the wall.
func _starts() -> Array:
	return [
		[Vector3(-11.0, 0, -20.0), Vector3(0.5, 0, -23.0), Vector3(5.5, 0, -19.0),
				[Vector3(0, 0, -4.0), Vector3(0, 0, 4.0)]],
		[Vector3(-10.0, 0, -24.5), Vector3(-1.0, 0, -22.5), Vector3(1.0, 0, -15.0),
				[Vector3(0, 0, 4.0), Vector3(4.0, 0, -2.0)]],
		[Vector3(-1.5, 0, -28.3), Vector3(3.5, 0, -24.0), Vector3(-2.0, 0, -18.0),
				[Vector3(-4.0, 0, 0), Vector3(-2.0, 0, 3.5)]],
		[Vector3(-8.0, 0, -22.0), Vector3(4.0, 0, -24.5), Vector3(1.0, 0, -14.5),
				[Vector3(4.0, 0, 1.0), Vector3(-4.0, 0, 1.0)]],
	]


func _sweep(label: String) -> void:
	var ends: Dictionary = {}
	var kinds: Dictionary = {}
	var low_s: float = 0.0
	var t_all: float = 0.0
	var t_shot: float = 0.0
	var passes: int = 0
	var runs: int = 0
	var shots: Array[Dictionary] = []
	var picks: Array[String] = []
	var row: String = "   "
	for start: Array in _starts():
		var vels: Array = [Vector3.ZERO] + start[3]
		for combo: int in 2 * vels.size() * 2:
			var m := Vector3(1.0 if combo % 2 == 0 else -1.0, 1.0, 1.0)
			var vel: Vector3 = vels[(combo >> 1) % vels.size()] * m
			var tight: bool = combo >= 2 * vels.size()
			var r: Dictionary = _run(_setup(start[0] * m, vel, start[1] * m, start[2] * m, tight))
			runs += 1
			row += " %s@%.1f/p%d" % [str(r["end"]).left(4), r["t"], r["passes"]]
			ends[r["end"]] = int(ends.get(r["end"], 0)) + 1
			passes += r["passes"]
			low_s += r["low_s"]
			t_all += r["t"]
			if r.has("pick"):
				picks.append(r["pick"])
			if r["end"] == "shot":
				var s: Dictionary = r["shot"]
				shots.append(s)
				kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
				t_shot += r["t"]
	gut.p(row)
	gut.p("%s | ends %s | shots %s, mean %.1f s in | possession %.1f s | passes %d over %d runs | below the dots %.1f s" % [
			label, str(ends), str(kinds), t_shot / maxf(shots.size(), 1), t_all / runs,
			passes, runs, low_s / runs])
	gut.p("    shot (x, out)      kind   priced   set    pass  carry  pass-to (x, out)")
	var over: float = 0.0
	var pass_near: int = 0
	for s: Dictionary in shots:
		var p: Vector3 = s["pos"]
		var to: Vector3 = s["pass_to"]
		over += float(s["shot"]) - float(s["set"])
		if float(s["pass"]) >= 0.5 * float(s["shot"]) and float(s["pass"]) > 0.0:
			pass_near += 1
		gut.p("    (%5.1f, %4.1f)   %-6s %6.3f  %6.3f  %6.3f %6.3f  %s" % [p.x, _out(p), s["kind"],
				s["shot"], s["set"], s["pass"], s["carry"],
				"(%5.1f, %4.1f)" % [to.x, _out(to)] if to.is_finite() else "-"])
		var pk: Vector3 = s["puck"]
		var kp: Vector3 = s["keeper"]
		gut.p("        puck (%5.1f, %4.1f) live %.3f set %.3f hist %d | keeper (%5.2f, %4.2f) vx %5.2f st %d |%s" % [
				pk.x, _out(pk), s["live"], s["set_puck"], int(s.get("history", -1)),
				kp.x, _out(kp), s["keeper_vx"], s["stance"], s["mates"]])
	gut.p("    mean priced - set: %+.3f over %d shots; a pass within half the shot's price on %d" % [
			over / maxf(shots.size(), 1), shots.size(), pass_near])
	gut.p("    passes picked off:")
	for line: String in picks:
		gut.p("        " + line)


func test_ozone_possession_5v5() -> void:
	_sweep("5v5 hard  ")
	assert_true(true)

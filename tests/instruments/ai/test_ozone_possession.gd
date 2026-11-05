extends GutTest

# Three real bots holding the puck low in their zone against three set
# defenders, on the duel harness (docs/possession-floor-plan.md, step 5): how
# long a possession that starts below the dots stays there, how it ends (a shot,
# a turnover, the puck out of the zone), where its shot comes from, and how long
# a carrier holds the puck in the slot before he shoots, passes or loses it. Run
# as the field stands and with point shots worth nothing (point_odds_off.gd).
# Team 0 attacks -Z, at the real keeper (KeeperController, fed the puck as a
# carried one, as test_advantage_scenarios.gd does): a keeper who does not
# square to the puck turns every sharp angle into an open net. Not modelled:
# offside, real boards; a possession ends at its first shot (no rebounds).

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const PointOff := preload("res://tests/instruments/ai/point_odds_off.gd")
const SECS: float = 12.0
# Below the dots: deeper than the zone's faceoff dots, 20 ft off the goal line.
const DOTS_OUT_M: float = 6.1
# The slot: between 1.5 and 10 m out, inside 4.5 m of the middle.
const SLOT_NEAR_M: float = 1.5
const SLOT_FAR_M: float = 10.0
const SLOT_HALF_WIDTH_M: float = 4.5
# The point: 15 m or more out (the blue line is 19.4 m).
const POINT_OUT_M: float = 15.0
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const KEEPER_SETTLE_S: float = 1.5

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController


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


# Metres out from their goal line (negative behind it).
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
	return "other"


# The release record's intent is already cleared when it is logged; its decision
# label says what was fired.
static func _is_shot(rec: Dictionary) -> bool:
	return rec.get("decision", "") in ["SHOOT", "ONE_TIMER"]


# One possession: { end, t, low_s, passes, shot (kind or ""), holds: [[s, end]] }.
# Ends: "shot", "picked" (their man takes a pass of ours), "stripped" (he takes
# it off ours, or the loose puck after), the puck out of the zone ("out-ours": a
# pass of ours went out; "out-carried"; "cleared": theirs or a loose puck after a
# strip), "timeout".
func _run(duel: Object) -> Dictionary:
	var r: Dictionary = {"end": "timeout", "t": SECS, "low_s": 0.0, "passes": 0, "shot": "",
			"holds": []}
	var hold_peer: int = -1
	var hold_s: float = 0.0
	var passing: bool = false
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
		var in_slot: bool = ours and _in_slot(duel.puck_pos)
		# A slot hold ends when its carrier no longer has the puck there.
		if hold_peer != -1 and (not in_slot or c != hold_peer):
			var how: String = "left"
			if not released.is_empty():
				how = "shot" if _is_shot(released) else "pass"
			elif c != -1 and duel.team_map[c] == 1:
				how = "lost"
			elif c == -1:
				how = "loose"
			r["holds"].append([hold_s, how])
			hold_peer = -1
		if in_slot:
			if hold_peer == -1:
				hold_peer = c
				hold_s = 0.0
			hold_s += Duel.DT
		if ours and _out(duel.puck_pos) <= DOTS_OUT_M:
			r["low_s"] += Duel.DT
		if not released.is_empty():
			if _is_shot(released):
				r["end"] = "shot"
				r["t"] = t
				r["shot"] = _shot_kind(released["pos"])
				return r
			r["passes"] += 1
			passing = true
		if c != -1 and duel.team_map[c] == 1:
			r["end"] = "picked" if passing else "stripped"
			r["t"] = t
			return r
		if duel.puck_pos.z > -GameRules.BLUE_LINE_Z:
			r["end"] = "out-ours" if passing else ("out-carried" if ours else "cleared")
			r["t"] = t
			return r
	if hold_peer != -1:
		r["holds"].append([hold_s, "timeout"])
	return r


# The puck carrier low (`carrier`, skating at `vel`), a mate at `mate_a` and one
# at `mate_b`; their three set in front of their net, tight (`tight`: the
# strong side's man already toward the puck) or home (net front, low strong
# side, high slot).
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
	# The keeper has tracked the puck down low: settled on it before the play.
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


# Starts, each run as given and mirrored, the carrier standing or skating each of
# two ways: in the corner (up the wall, behind the net), behind the net (round
# it, out front), low on the half-wall (up it, down it), and below the circle
# with the puck worked off the wall (to the middle, to the wall).
func _starts() -> Array:
	return [
		[Vector3(-10.0, 0, -24.5), Vector3(-11.5, 0, -15.0), Vector3(4.0, 0, -16.0),
				[Vector3(0, 0, 4.0), Vector3(4.0, 0, -2.0)]],
		[Vector3(-1.5, 0, -28.3), Vector3(-8.0, 0, -20.0), Vector3(5.0, 0, -14.0),
				[Vector3(-4.0, 0, 0), Vector3(-2.0, 0, 3.5)]],
		[Vector3(-12.0, 0, -20.0), Vector3(-9.0, 0, -25.0), Vector3(2.0, 0, -11.0),
				[Vector3(0, 0, 4.0), Vector3(0, 0, -4.0)]],
		[Vector3(-8.0, 0, -22.0), Vector3(0.0, 0, -9.5), Vector3(9.0, 0, -18.0),
				[Vector3(4.0, 0, 1.0), Vector3(-4.0, 0, 1.0)]],
	]


func _sweep(label: String) -> void:
	var ends: Dictionary = {}
	var shots: Dictionary = {}
	var low_s: float = 0.0
	var low_runs: int = 0
	var low_shots: int = 0
	var t_shot: float = 0.0
	var passes: int = 0
	var hold_s: Array[float] = []
	var hold_ends: Dictionary = {}
	var runs: int = 0
	var row: String = "   "
	for start: Array in _starts():
		var vels: Array = [Vector3.ZERO] + start[3]
		for combo: int in 2 * vels.size() * 2:
			var m := Vector3(1.0 if combo % 2 == 0 else -1.0, 1.0, 1.0)
			var vel: Vector3 = vels[(combo >> 1) % vels.size()] * m
			var tight: bool = combo >= 2 * vels.size()
			var r: Dictionary = _run(_setup(start[0] * m, vel, start[1] * m, start[2] * m, tight))
			runs += 1
			row += " %s@%.1f/p%d%s" % [str(r["end"]).left(4), r["t"], r["passes"],
					"/" + str(r["shot"]) if r["shot"] != "" else ""]
			ends[r["end"]] = int(ends.get(r["end"], 0)) + 1
			passes += r["passes"]
			low_s += r["low_s"]
			if r["low_s"] > 0.0:
				low_runs += 1
				if r["end"] == "shot":
					low_shots += 1
			if r["end"] == "shot":
				shots[r["shot"]] = int(shots.get(r["shot"], 0)) + 1
				t_shot += r["t"]
			for h: Array in r["holds"]:
				hold_s.append(h[0])
				hold_ends[h[1]] = int(hold_ends.get(h[1], 0)) + 1
	hold_s.sort()
	gut.p(row)
	var n_shots: int = int(ends.get("shot", 0))
	gut.p("%s | ends %s | shots %s, mean %.1f s in | passes %d over %d runs" % [label, str(ends),
			str(shots), t_shot / maxf(n_shots, 1), passes, runs])
	gut.p("    below the dots: %.1f s a possession, %d of %d ending in a shot" % [
			low_s / maxf(low_runs, 1), low_shots, low_runs])
	gut.p("    slot holds: %d, median %.2f s, max %.2f s, ended %s" % [hold_s.size(),
			hold_s[hold_s.size() / 2] if not hold_s.is_empty() else 0.0,
			hold_s[-1] if not hold_s.is_empty() else 0.0, str(hold_ends)])


func test_ozone_possession() -> void:
	_sweep("as is     ")
	PointOff.apply()
	_sweep("point off ")
	PointOff.restore()
	assert_true(true)

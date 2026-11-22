extends GutTest

# ── Where a bot releases a breakaway, against the keeper (#943) ───────────────
# The breakaway_finish fixtures (a real bot carrier against the real keeper,
# who reads the drive), three ways:
#   test_report_breakaway_releases — one breakaway traced: the carrier's depth
#     off the goal line and pace, the keeper's spot and the gap to him, the
#     carrier's own shoot-now and carry scores, and any poke check;
#   test_report_release_by_tier — per tier and case, where the shot left, where
#     he committed to it, and the seconds between (what the priced lookahead,
#     AIBotMechanics.shot_lookahead_s, stands for);
#   test_report_release_spread_by_tier — over six seeds of the hands' draws, how
#     far out the releases come and how many land inside the keeper's cliff
#     (test_breakaway_release_truth.gd measures where that is).
# The duel neither collides the carrier with the keeper nor lets a poke strip
# him, so these read where the release came, not whether the keeper got there.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const CARRIER := 1
const CHASER := 201
const WINDOW_S: float = 4.0
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const TRACE_EVERY: int = 6
const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6]

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: KeeperController
# The carrier's peer id, which seeds his hands' draws (the release hold).
var _carrier: int = CARRIER


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_ctrl.setup(_goalie, _puck, -GameRules.GOAL_LINE_Z, true)
	_carrier = CARRIER


# [label, start, velocity, chaser offset (INF none)]: test_breakaway_finish's.
static func _cases() -> Array:
	return [
		["clean", Vector3(0, 0, -1), Vector3(0, 0, -8.5), Vector3.INF],
		["chased", Vector3(0, 0, -1), Vector3(0, 0, -8.5), Vector3(0.5, 0, 3.0)],
		["wing", Vector3(6, 0, -3), Vector3(-1, 0, -8.5), Vector3(-1, 0, 4.0)],
		["slow", Vector3(-2, 0, -GameRules.GOAL_LINE_Z + 19.0), Vector3(0, 0, -5.0),
				Vector3(0, 0, 5.0)],
	]


static func _tiers() -> Array:
	return [["hard", BotSkillProfile.hard()], ["normal", BotSkillProfile.normal()],
			["easy", BotSkillProfile.easy()]]


func _gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# One breakaway; `trace` prints it. Returns {off, gap, decision, commit_off,
# lag_s, press_s}: the release's distance off the goal line and from the keeper,
# and where and how long before it he committed to the shot and pressed.
func _run(c: Array, profile: BotSkillProfile, trace: bool) -> Dictionary:
	_ctrl.reset_to_crease()
	var duel := Duel.new()
	duel.add_skater(_carrier, 0, c[1], profile, c[2])
	if c[3].is_finite():
		duel.add_skater(CHASER, 1, c[1] + c[3], null, c[2])
	duel.start(_carrier)
	_shooter.global_position = c[1]
	_puck.set_carrier(_shooter)
	duel.goalie_provider = func(team_id: int, puck_pos: Vector3) -> Variant:
		if team_id != 1:
			return null
		_shooter.global_position = puck_pos
		# The keeper reads the carrier's velocity for the rush backflow: left at
		# zero he never sees a drive and holds the top of his crease.
		_shooter.velocity = duel._skater(_carrier).vel
		_puck.global_position = puck_pos
		_ctrl._physics_process(DT)
		return _goalie.global_position
	if trace:
		gut.p("  ── %s ──" % c[0])
	var commit_tick: int = -1
	var commit_off: float = NAN
	var press_tick: int = -1
	var poked: bool = false
	for t: int in int(WINDOW_S / DT):
		var before: int = duel.releases.size()
		duel.step()
		var s: Object = duel._skater(_carrier)
		var keeper: Vector3 = _goalie.global_position
		if trace and _ctrl._poking and not poked:
			poked = true
			gut.p("      t%3d POKE: carrier %.1f m off the line, %.1f m from the keeper"
					% [t, s.pos.z - GOAL_Z, _gap(s.pos, keeper)])
		var pressed: bool = s.agent._state == SkaterAgentStateMachine.State.SHOOT_PRESSED
		if commit_tick == -1 and (pressed
				or s.agent._carrier.intended_action == AIRoleCarrier.INTENT_SHOOT):
			commit_tick = t
			commit_off = s.pos.z - GOAL_Z
		if press_tick == -1 and pressed:
			press_tick = t
		var released: bool = duel.releases.size() > before
		if trace and (released or t % TRACE_EVERY == 0):
			var car: AIRoleCarrier = s.agent._carrier
			gut.p("      t%3d%s carrier (%.1f, %.1f off) %.1f m/s | keeper (%.1f, %.1f off) gap %.2f | shoot %.3f carry %.3f"
					% [t, " RELEASE" if released else "", s.pos.x, s.pos.z - GOAL_Z,
					Vector2(s.vel.x, s.vel.z).length(), keeper.x, keeper.z - GOAL_Z,
					_gap(s.pos, keeper), car.debug_shoot_score, car.debug_carry_score])
		if released:
			return {"off": s.pos.z - GOAL_Z, "gap": _gap(s.pos, keeper),
					"decision": str(duel.releases[-1].get("decision", "")),
					"commit_off": commit_off,
					"lag_s": (t - commit_tick) * DT if commit_tick != -1 else NAN,
					"press_s": (t - press_tick) * DT if press_tick != -1 else NAN}
		if duel.carrier_id != _carrier:
			break
	return {"off": NAN, "gap": NAN, "decision": "NONE", "commit_off": NAN, "lag_s": NAN,
			"press_s": NAN}


func test_report_breakaway_releases() -> void:
	for c: Array in _cases():
		_run(c, null, true)
	assert_true(true)


func test_report_release_by_tier() -> void:
	var lines: PackedStringArray = [
		"tier    case   | release off line, gap to keeper | committed at, s to the release (pressed)"]
	for tier: Array in _tiers():
		lines.append("  %s prices %.3f s" % [tier[0],
				AIBotMechanics.shot_lookahead_s(tier[1].shot_timing_error_s)])
		for c: Array in _cases():
			var r: Dictionary = _run(c, tier[1], false)
			lines.append("%-7s %-6s | %5.2f m, %5.2f m (%s) | %5.2f m, %.3f s (%.3f s)"
					% [tier[0], c[0], r["off"], r["gap"], r["decision"], r["commit_off"],
					r["lag_s"], r["press_s"]])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func test_report_release_spread_by_tier() -> void:
	var lines: PackedStringArray = [
		"tier   | shots | off the line: min  mean | inside 2.5 m | inside 2.0 m"]
	for tier: Array in _tiers():
		var offs: Array[float] = []
		for seed_id: int in SEEDS:
			_carrier = seed_id
			for c: Array in _cases():
				var r: Dictionary = _run(c, tier[1], false)
				if r["decision"] == "SHOOT":
					offs.append(r["off"])
		var sum: float = 0.0
		var lo: float = INF
		var in25: int = 0
		var in20: int = 0
		for o: float in offs:
			sum += o
			lo = minf(lo, o)
			in25 += 1 if o < 2.5 else 0
			in20 += 1 if o < 2.0 else 0
		var n: int = maxi(offs.size(), 1)
		lines.append("%-6s | %5d | %17.2f %5.2f | %11d%% | %11d%%" % [tier[0], offs.size(), lo,
				sum / n, roundi(100.0 * in25 / n), roundi(100.0 * in20 / n)])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)

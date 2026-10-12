extends GutTest

# ── Offensive-zone possession harness (report-only; NOT in the default suite) ─
# Phase A of docs/possession-value-plan.md: measures `r`, the xG a controlled
# offensive-zone possession produces per second, on the real decision stack
# (the duel harness's 120 Hz movement + agents + brains), for 3v3 and 5v5 at
# Hard and Normal. Also the plan's scorecard rows a sim can honestly produce.
#
# One EPISODE per trial (AIOzPossessionTracker): from our carrier establishing
# the zone to the first shot, turnover, exit, or LIMIT_S. Stopping at the first
# shot is deliberate, not a shortcut. The duel harness has no net and no keeper
# behavior, so a released shot slides on to the end boards and nothing after it
# resembles real play; the rate only needs the exposure up to the shot.
#
# What this CANNOT measure: P_lose, retention after a shot. No harness models a
# save, a freeze, or a rebound race followed by the next possession. That number
# comes from logged play (shot_events.next_control).
#
# xG is the shooter's own seam value at release (the carrier's raw shoot-now
# score, before hysteresis and ping bias) — the currency the shot bar will be
# compared in, not the logged `expected_goals` column.
#
# Run explicitly:
#   bash .claude/hooks/run-gut.sh -gdir=res://benchmarks "-gselect=oz_possession"

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const LIMIT_S: float = 15.0
const JITTERS: int = 12
const JITTER_M: float = 1.0
const GOAL_Z: float = -GameRules.GOAL_LINE_Z    # team 0 attacks -Z
const ATTACK: int = 0
# The value of r today's SHOT_MIN_VALUE implies at safety 0.95 (plan §3.2) —
# printed beside the measurement as the gate's comparison, not asserted.
const IMPLIED_R: float = 0.024

# Rosters: [peer, team, x, z, vx, vz]. Team 0 attacks -Z; the carrier is named
# per scenario. 5v5 positions follow peer order C/LW/RW/LD/RD.
const SCENARIOS_5V5: Dictionary = {
	"entry": {"carrier": 10002, "skaters": [
		[10001, 0, 0.0, -3.0, 0.0, -6.0], [10002, 0, -8.0, -6.5, 0.0, -7.0],
		[10003, 0, 8.0, -5.0, 0.0, -6.0], [10004, 0, -4.0, 2.0, 0.0, -4.0],
		[10005, 0, 4.0, 2.0, 0.0, -4.0],
		[10011, 1, 0.0, -2.0, 0.0, -6.0], [10012, 1, -7.0, -1.0, 0.0, -6.0],
		[10013, 1, 7.0, -1.0, 0.0, -6.0], [10014, 1, -4.0, -12.0, 0.0, -3.0],
		[10015, 1, 4.0, -12.0, 0.0, -3.0]]},
	"cycle": {"carrier": 10003, "skaters": [
		[10001, 0, 2.0, -18.0, 0.0, 0.0], [10002, 0, -6.0, -17.0, 0.0, 0.0],
		[10003, 0, 10.0, -22.0, 0.0, 1.5], [10004, 0, -6.0, -9.0, 0.0, 0.0],
		[10005, 0, 6.0, -9.0, 0.0, 0.0],
		[10011, 1, 3.0, -20.0, 0.0, 0.0], [10012, 1, -7.0, -12.0, 0.0, 0.0],
		[10013, 1, 7.0, -12.0, 0.0, 0.0], [10014, 1, -3.0, -23.0, 0.0, 0.0],
		[10015, 1, 7.0, -23.0, 0.0, 0.0]]},
	"point": {"carrier": 10005, "skaters": [
		[10001, 0, 0.0, -20.0, 0.0, 0.0], [10002, 0, -7.0, -19.0, 0.0, 0.0],
		[10003, 0, 8.0, -18.0, 0.0, 0.0], [10004, 0, -6.0, -10.5, 0.0, 0.0],
		[10005, 0, 6.0, -10.5, -2.0, 0.0],
		[10011, 1, 0.0, -18.0, 0.0, 0.0], [10012, 1, -6.0, -12.0, 0.0, 0.0],
		[10013, 1, 6.0, -11.0, 0.0, 0.0], [10014, 1, -3.0, -22.0, 0.0, 0.0],
		[10015, 1, 4.0, -22.0, 0.0, 0.0]]},
}
const SCENARIOS_3V3: Dictionary = {
	"entry": {"carrier": 10001, "skaters": [
		[10001, 0, -6.0, -6.5, 0.0, -7.0], [10002, 0, 5.0, -5.0, 0.0, -6.0],
		[10003, 0, 0.0, 0.0, 0.0, -4.0],
		[10011, 1, 0.0, -14.0, 0.0, -3.0], [10012, 1, -6.0, -10.0, 0.0, -3.0],
		[10013, 1, 6.0, -3.0, 0.0, -6.0]]},
	"cycle": {"carrier": 10001, "skaters": [
		[10001, 0, 10.0, -22.0, 0.0, 1.5], [10002, 0, -3.0, -18.0, 0.0, 0.0],
		[10003, 0, 0.0, -10.0, 0.0, 0.0],
		[10011, 1, 6.0, -22.0, 0.0, 0.0], [10012, 1, -2.0, -20.0, 0.0, 0.0],
		[10013, 1, 0.0, -13.0, 0.0, 0.0]]},
	"high": {"carrier": 10003, "skaters": [
		[10001, 0, -6.0, -20.0, 0.0, 0.0], [10002, 0, 5.0, -19.0, 0.0, 0.0],
		[10003, 0, 4.0, -10.0, -2.0, 0.0],
		[10011, 1, 0.0, -19.0, 0.0, 0.0], [10012, 1, -5.0, -15.0, 0.0, 0.0],
		[10013, 1, 5.0, -15.0, 0.0, 0.0]]},
}

var _report: Array[String] = []


func _profile(tier: String) -> BotSkillProfile:
	return BotSkillProfile.hard() if tier == "hard" else BotSkillProfile.normal()


func _jit(trial: int, salt: int) -> float:
	return (PlayerRules.stagger01(trial, salt) * 2.0 - 1.0) * JITTER_M


# One trial: stage the scenario (mirrored, jittered) and step until the
# tracker closes the trial's episode or LIMIT_S runs out. Returns false when
# the carrier never established the zone.
func _run_trial(tracker: AIOzPossessionTracker, size: int, tier: String,
		spec: Dictionary, mirror: float, trial: int) -> bool:
	var duel: RefCounted = Duel.new()
	for row: Array in spec["skaters"]:
		var peer: int = row[0]
		var pos := Vector3((row[2] + _jit(trial, peer)) * mirror, 0.0,
				row[3] + _jit(trial, peer + 7))
		var vel := Vector3(row[4] * mirror, 0.0, row[5])
		duel.add_skater(peer, row[1], pos, _profile(tier), vel)
	if size == 5:
		duel.team_size = 5
		duel.positions = {10001: 0, 10002: 1, 10003: 2, 10004: 3, 10005: 4,
				10011: 0, 10012: 1, 10013: 2, 10014: 3, 10015: 4}
	duel.start(spec["carrier"])
	var before: int = tracker.total(ATTACK)
	var seen_releases: int = 0
	for _i: int in int(LIMIT_S / Duel.DT):
		var release_puck: Vector3 = duel.puck_pos
		duel.step()
		while seen_releases < duel.releases.size():
			var rec: Dictionary = duel.releases[seen_releases]
			seen_releases += 1
			# The record's `intent` has already been reset to CARRY by the release
			# tick; the press state's decision label is what names a shot.
			if int(rec["team"]) == ATTACK \
					and String(rec.get("decision", "")) == "SHOOT":
				tracker.note_shot(ATTACK, _release_xg(duel, int(rec["peer"])),
						release_puck, GOAL_Z,
						_net_front_man(duel, int(rec["peer"])))
		var carrier_team: int = -1 if duel.carrier_id == -1 \
				else int(duel.team_map[duel.carrier_id])
		tracker.tick(ATTACK, GOAL_Z, duel.puck_pos, carrier_team, Duel.DT)
		if tracker.total(ATTACK) > before:
			return true
	tracker.close_on_stoppage()
	return tracker.total(ATTACK) > before


# The shooter's raw seam value at its last pick.
func _release_xg(duel: RefCounted, peer: int) -> float:
	for s: RefCounted in duel.skaters:
		if s.peer_id == peer and s.agent != null and s.agent._carrier != null:
			return maxf(s.agent._carrier._phase_shoot_score, 0.0)
	return 0.0


func _net_front_man(duel: RefCounted, shooter: int) -> bool:
	for s: RefCounted in duel.skaters:
		if s.team_id == ATTACK and s.peer_id != shooter \
				and AIOzPossessionTracker.is_net_front(s.pos, GOAL_Z):
			return true
	return false


func _run_row(size: int, tier: String) -> void:
	var scenarios: Dictionary = SCENARIOS_5V5 if size == 5 else SCENARIOS_3V3
	var row := AIOzPossessionTracker.new()
	var trials: int = 0
	var unestablished: int = 0
	var per_scenario: Array[String] = []
	for name: String in scenarios:
		var xg0: float = row.xg_sum(ATTACK)
		var s0: float = row.seconds(ATTACK)
		var shots0: int = row.count(ATTACK, AIOzPossessionTracker.Outcome.SHOT)
		for mirror: float in [1.0, -1.0]:
			for j: int in JITTERS:
				var trial: int = j * 2 + (0 if mirror > 0.0 else 1)
				trials += 1
				if not _run_trial(row, size, tier, scenarios[name], mirror, trial):
					unestablished += 1
		var ds: float = row.seconds(ATTACK) - s0
		per_scenario.append("%s r=%.4f (%d shots / %.0fs)" % [name,
				(row.xg_sum(ATTACK) - xg0) / ds if ds > 0.0 else 0.0,
				row.count(ATTACK, AIOzPossessionTracker.Outcome.SHOT) - shots0, ds])
	var label: String = "%dv%d %s" % [size, size, tier]
	var n: int = row.total(ATTACK)
	_report.append("  %-11s trials %d (never established %d) | episodes %d, mean %.1fs" % [
			label, trials, unestablished, n,
			row.seconds(ATTACK) / float(n) if n > 0 else 0.0])
	var parts: Array[String] = []
	for outcome: int in AIOzPossessionTracker.OUTCOME_COUNT:
		parts.append("%s %d" % [AIOzPossessionTracker.outcome_name(outcome),
				row.count(ATTACK, outcome)])
	_report.append("      ends: " + ", ".join(parts)
			+ "  (stoppage = trial limit)")
	_report.append("      r = %.4f xG/s  (%.3f xG over %.1fs)   xG/shot %.3f   xG/episode %.4f" % [
			row.xg_rate(ATTACK), row.xg_sum(ATTACK), row.seconds(ATTACK),
			row.mean_xg_per_shot(ATTACK),
			row.xg_sum(ATTACK) / float(n) if n > 0 else 0.0])
	_report.append("      long-range shots: net-front %d (%.3f xG), clear %d (%.3f xG); stray %d" % [
			row.long_range_shots(ATTACK, true), row.long_range_xg(ATTACK, true),
			row.long_range_shots(ATTACK, false), row.long_range_xg(ATTACK, false),
			row.stray_shots(ATTACK)])
	_report.append("      by scenario: " + "; ".join(per_scenario))


func test_oz_possession_rate() -> void:
	_report.clear()
	var wall_t0: int = Time.get_ticks_msec()
	for size: int in [3, 5]:
		for tier: String in ["hard", "normal"]:
			_run_row(size, tier)
	gut.p("")
	gut.p("=== OZ possession harness (one episode per trial, %.0fs limit, %d jitters x 2 mirrors) ===" % [
			LIMIT_S, JITTERS])
	gut.p("  implied by today's SHOT_MIN_VALUE at safety 0.95: r ≈ %.3f xG/s" % IMPLIED_R)
	for line: String in _report:
		gut.p(line)
	gut.p("  wall: %.1fs" % [(Time.get_ticks_msec() - wall_t0) / 1000.0])
	assert_eq(_report.size(), 4 * 5, "every row reported")

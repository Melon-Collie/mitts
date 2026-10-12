class_name AIOzPossessionTracker
extends RefCounted

# Offensive-zone possession tally — the measurement instrument of
# docs/possession-value-plan.md. Its two headlines are the possession model's
# inputs: `xg_rate`, the xG controlled offensive-zone possession produces per
# second (`r`), and `loss_rate`, how fast that possession is lost (`h`). Sampled
# by the OZ harness and, behind the F6 overlay, by live play. A debug
# instrument: nothing reads it back into a decision.
#
# ── An EPISODE is one stretch of CONTROLLED possession in the zone ───────────
# Starts when OUR carrier has the puck ESTABLISHED in the attacking zone (past
# the blue line by ESTABLISH_DEPTH_M, the same arming margin the breakout tracker
# uses). Loose-puck time inside the episode — a pass in flight, a bobble — still
# counts as ours until something below ends it.
#
# Ends on the first of:
#   SHOT      — we released a shot (note_shot). A shot ends the controlled
#               stretch whatever happens next: what comes back after it is
#               retention (the plan's P_lose), measured from logged play, not
#               here. A re-established carry after the shot arms a new episode.
#   TURNOVER  — an opponent carries it while it is still in the zone
#   EXIT      — the puck left the zone
#   STOPPAGE  — a whistle, a goal, or the end of a harness trial
#
# Ending at the shot is what keeps `xg_rate` honest: the exposure is time spent
# holding the puck, and the events are the shots taken from it, so the rate does
# not depend on how often the puck comes back afterwards.
#
# Hot path when sampled live: `tick` runs per team per physics tick. Fixed-size
# packed storage, no allocation.

const TEAM_COUNT: int = 2

enum Outcome { SHOT, TURNOVER, EXIT, STOPPAGE }
const OUTCOME_COUNT: int = 4

const ESTABLISH_DEPTH_M: float = 2.0

# Counts per (team, outcome), team-major.
var _counts: PackedInt32Array = PackedInt32Array()
var _seconds: PackedFloat64Array = PackedFloat64Array()
var _xg: PackedFloat64Array = PackedFloat64Array()
# Shots from beyond the tops of the circles, split by whether a teammate stood in
# the net-front box at release: [team * 2 + (1 if net-front else 0)].
var _long_shots: PackedInt32Array = PackedInt32Array()
var _long_xg: PackedFloat64Array = PackedFloat64Array()
# Shots noted with no episode open — released before the puck was established
# in the zone. Counted so nothing disappears silently.
var _stray_shots: PackedInt32Array = PackedInt32Array()

var _active: PackedInt32Array = PackedInt32Array()
var _elapsed: PackedFloat64Array = PackedFloat64Array()


func _init() -> void:
	reset()


func reset() -> void:
	_counts.resize(TEAM_COUNT * OUTCOME_COUNT)
	_counts.fill(0)
	_seconds.resize(TEAM_COUNT)
	_seconds.fill(0.0)
	_xg.resize(TEAM_COUNT)
	_xg.fill(0.0)
	_long_shots.resize(TEAM_COUNT * 2)
	_long_shots.fill(0)
	_long_xg.resize(TEAM_COUNT * 2)
	_long_xg.fill(0.0)
	_stray_shots.resize(TEAM_COUNT)
	_stray_shots.fill(0)
	_active.resize(TEAM_COUNT)
	_active.fill(0)
	_elapsed.resize(TEAM_COUNT)
	_elapsed.fill(0.0)


# Depth of `pos` into the zone attacked at `attacking_goal_z` (±GOAL_LINE_Z),
# measured from centre ice: past BLUE_LINE_Z is in the zone.
static func zone_depth(pos: Vector3, attacking_goal_z: float) -> float:
	return signf(attacking_goal_z) * pos.z


# Released from beyond the tops of the circles — the range the current shot bar
# is written to ban for a clean look.
static func is_long_range(release: Vector3, attacking_goal_z: float) -> bool:
	return absf(attacking_goal_z) - zone_depth(release, attacking_goal_z) \
			>= AIZoneCoverage.HOUSE_TOP_DEPTH_M


# Inside the net-front box of the net at `attacking_goal_z` — the same box
# AIZoneCoverage assigns to its net-front defender.
static func is_net_front(pos: Vector3, attacking_goal_z: float) -> bool:
	var d: float = absf(attacking_goal_z) - zone_depth(pos, attacking_goal_z)
	return d >= 0.0 and d < AIZoneCoverage.NET_FRONT_DEPTH_M \
			and absf(pos.x) <= AIZoneCoverage.NET_FRONT_HALF_WIDTH_M


# One live-play sample for `team_id` as the ATTACKING team.
#   `carrier_team` — team_id of the carrier, or -1 when the puck is loose
func tick(team_id: int, attacking_goal_z: float, puck_pos: Vector3,
		carrier_team: int, dt: float) -> void:
	if team_id < 0 or team_id >= TEAM_COUNT or dt <= 0.0:
		return
	var depth: float = zone_depth(puck_pos, attacking_goal_z)
	if _active[team_id] == 0:
		if carrier_team == team_id \
				and depth > GameRules.BLUE_LINE_Z + ESTABLISH_DEPTH_M:
			_active[team_id] = 1
			_elapsed[team_id] = 0.0
		return
	_elapsed[team_id] += dt
	if depth < GameRules.BLUE_LINE_Z:
		_close(team_id, Outcome.EXIT)
		return
	if carrier_team != -1 and carrier_team != team_id:
		_close(team_id, Outcome.TURNOVER)


# `team_id` released a shot worth `xg` from `release`. `net_front_man` is
# whether a teammate stood in the net-front box at the release.
func note_shot(team_id: int, xg: float, release: Vector3,
		attacking_goal_z: float, net_front_man: bool) -> void:
	if team_id < 0 or team_id >= TEAM_COUNT:
		return
	if _active[team_id] == 0:
		_stray_shots[team_id] += 1
		return
	_xg[team_id] += xg
	if is_long_range(release, attacking_goal_z):
		var i: int = team_id * 2 + (1 if net_front_man else 0)
		_long_shots[i] += 1
		_long_xg[i] += xg
	_close(team_id, Outcome.SHOT)


func close_on_stoppage() -> void:
	for team_id: int in TEAM_COUNT:
		if _active[team_id] == 1:
			_close(team_id, Outcome.STOPPAGE)


func _close(team_id: int, outcome: int) -> void:
	_counts[team_id * OUTCOME_COUNT + outcome] += 1
	_seconds[team_id] += _elapsed[team_id]
	_active[team_id] = 0
	_elapsed[team_id] = 0.0


func is_active(team_id: int) -> bool:
	return team_id >= 0 and team_id < TEAM_COUNT and _active[team_id] == 1


func count(team_id: int, outcome: int) -> int:
	if team_id < 0 or team_id >= TEAM_COUNT:
		return 0
	if outcome < 0 or outcome >= OUTCOME_COUNT:
		return 0
	return _counts[team_id * OUTCOME_COUNT + outcome]


# Completed episodes for this team.
func total(team_id: int) -> int:
	var n: int = 0
	for outcome: int in OUTCOME_COUNT:
		n += count(team_id, outcome)
	return n


func seconds(team_id: int) -> float:
	if team_id < 0 or team_id >= TEAM_COUNT:
		return 0.0
	return _seconds[team_id]


func xg_sum(team_id: int) -> float:
	if team_id < 0 or team_id >= TEAM_COUNT:
		return 0.0
	return _xg[team_id]


# xG per second of controlled zone possession — the plan's `r`.
func xg_rate(team_id: int) -> float:
	var s: float = seconds(team_id)
	return xg_sum(team_id) / s if s > 0.0 else 0.0


# Episodes that ended by losing the zone (a turnover or an exit) per second of
# controlled possession — the possession's realized loss hazard `h`. A shot is
# not a loss here: what follows it is P_lose, measured separately.
func loss_rate(team_id: int) -> float:
	var s: float = seconds(team_id)
	if s <= 0.0:
		return 0.0
	return float(count(team_id, Outcome.TURNOVER) + count(team_id, Outcome.EXIT)) / s


func mean_xg_per_shot(team_id: int) -> float:
	var n: int = count(team_id, Outcome.SHOT)
	return xg_sum(team_id) / float(n) if n > 0 else 0.0


func long_range_shots(team_id: int, net_front_man: bool) -> int:
	if team_id < 0 or team_id >= TEAM_COUNT:
		return 0
	return _long_shots[team_id * 2 + (1 if net_front_man else 0)]


func long_range_xg(team_id: int, net_front_man: bool) -> float:
	if team_id < 0 or team_id >= TEAM_COUNT:
		return 0.0
	return _long_xg[team_id * 2 + (1 if net_front_man else 0)]


func stray_shots(team_id: int) -> int:
	if team_id < 0 or team_id >= TEAM_COUNT:
		return 0
	return _stray_shots[team_id]


static func outcome_name(outcome: int) -> String:
	match outcome:
		Outcome.SHOT:
			return "shot"
		Outcome.TURNOVER:
			return "turnover"
		Outcome.EXIT:
			return "exit"
		Outcome.STOPPAGE:
			return "stoppage"
		_:
			return "?"


# JSON-able snapshot. `mode_label` records which configuration produced it.
func to_dict(mode_label: String) -> Dictionary:
	var out: Dictionary = {"mode": mode_label}
	for team_id: int in TEAM_COUNT:
		var outcomes: Dictionary = {}
		for outcome: int in OUTCOME_COUNT:
			outcomes[outcome_name(outcome)] = count(team_id, outcome)
		out["team_%d" % team_id] = {
			"episodes": total(team_id),
			"seconds": seconds(team_id),
			"xg": xg_sum(team_id),
			"xg_per_s": xg_rate(team_id),
			"loss_per_s": loss_rate(team_id),
			"xg_per_shot": mean_xg_per_shot(team_id),
			"long_shots_net_front": long_range_shots(team_id, true),
			"long_shots_clear": long_range_shots(team_id, false),
			"stray_shots": stray_shots(team_id),
			"outcomes": outcomes,
		}
	return out

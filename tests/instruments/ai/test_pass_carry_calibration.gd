extends GutTest

# Are the carrier's pass and carry reads honest? Real bots in the duel harness,
# from the O-zone possession instrument's starts (test_ozone_possession.gd), at
# the real keeper. Every pass a bot of either side releases is logged with the
# completion its search priced (AICarrierPassSearch.debug_kept: not poked at the
# release × the lane × no execution miss × kept on reception) and what happened:
# kept (his side holds it RECEPTION_HOLD_S after first touching it), lost (their
# man first, or theirs within the hold), or loose (nobody has it within
# LOOSE_AFTER_S: left out). Every CARRY_SAMPLE_S a carrier skating a carry is
# logged with AICarrySpace.carry_safety from the puck to his chosen carry spot
# over his time to it (the carry search's own read, escape gate on), and whether
# he still had it then: kept, lost, or released (he passed or shot first: left
# out). Prints reliability tables: priced against realised, per band.

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


func _run(duel: Object) -> void:
	var open_passes: Array = []   # [record index, release tick, team, first touch tick, holder team]
	var open_carries: Array = []  # [priced, team, peer, until tick, possession tick]
	var ticks: int = int(SECS / Duel.DT)
	var sample_every: int = int(CARRY_SAMPLE_S / Duel.DT)
	for i: int in ticks:
		var before: int = duel.releases.size()
		duel.step()
		var c: int = duel.carrier()
		var c_team: int = _team_of(duel, c) if c != -1 else -1
		if duel.releases.size() > before:
			var rec: Dictionary = duel.releases[-1]
			var decision: String = str(rec.get("decision", ""))
			# A pass: to a mate of his, on a release that is not a shot or a dump (the
			# release log's decision label is cleared for a pass by then).
			var to: int = int(rec.get("pass_peer", -1))
			if not (decision in ["SHOOT", "ONE_TIMER"] or decision.begins_with("DUMP")) \
					and to > 0 and _team_of(duel, to) == int(rec["team"]) \
					and float(rec.get("pass_kept", -1.0)) >= 0.0:
				open_passes.append([rec, i, int(rec["team"]), -1, -1, -1])
			# A carrier who released leaves his open carry samples.
			for oc: Array in open_carries:
				if oc[2] == int(rec["peer"]):
					oc[3] = -1
		# Passes: the first side to touch it, then whether it holds through the catch.
		for op: Array in open_passes:
			if op[3] == -1:
				if c != -1:
					op[3] = i
					op[4] = c_team
					op[5] = c
				elif i - op[1] > int(LOOSE_AFTER_S / Duel.DT):
					op[3] = -2   # loose: left out
					_how["loose"] = int(_how.get("loose", 0)) + 1
			elif op[3] >= 0 and i - op[3] == int(RECEPTION_HOLD_S / Duel.DT):
				var kept: bool = op[4] == op[2] and c_team == op[2]
				_passes.append([float(op[0]["pass_kept"]), 1 if kept else 0, op[2], op[0]])
				var how: String = "kept" if kept else ("intercepted" if op[4] != op[2]
						else "lost on the catch")
				if kept and op[5] != int(op[0]["pass_peer"]):
					how = "kept, another mate"
				_how[how] = int(_how.get(how, 0)) + 1
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
		if absf(duel.puck_pos.z) < GameRules.BLUE_LINE_Z and c == -1 and open_passes.is_empty():
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
	assert_true(true)

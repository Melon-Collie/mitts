extends GutTest

# The passes real bots fire in play, and how they are taken: every team-0 pass
# and rim (every release but a shot or a one-timer) in the breakout and neutral-zone drills' stagings (test_breakout_drill.gd,
# test_nz_entry_drill.gd) on the duel harness. Per release: the pace it left the
# blade at, whether it flew, the receiver the carrier priced it to, and its first
# touch — whose (the receiver, another teammate, an opponent, nobody), what it did
# (caught, bobbled, deflected, contested, blocked) and the puck's closing speed in
# that skater's frame — and whether team 0 still had the puck a second later.
# Prints the paces fired and the receivers' takes by closing speed, beside the
# odds the bots price a catch at (AIFeedReception.receiver_bobble_prob). Reports
# only.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const Breakout := preload("res://tests/instruments/ai/test_breakout_drill.gd")
const NzEntry := preload("res://tests/instruments/ai/test_nz_entry_drill.gd")
const SECS: float = 8.0
const KEEP_S: float = 1.0
const WATCH_S: float = 3.0

var _passes: Array[Dictionary] = []
var _decisions: Dictionary = {}


func test_pass_pace_in_play() -> void:
	var breakout: Object = Breakout.new()
	for cx: float in [-8.0, -3.0, 0.0, 4.0, 9.0]:
		for cz: float in [20.0, 24.0]:
			for f1_gap: float in [4.0, 7.0]:
				var carrier := Vector3(cx, 0, cz)
				var f1 := carrier + Vector3(-signf(cx + 0.1), 0, -f1_gap)
				_play(breakout._setup(carrier, f1, Vector3(-cx * 0.5, 0, 12.0)))
	breakout.free()
	var nz: Object = NzEntry.new()
	for n_def: int in [2, 3]:
		for x: float in [0.0, 3.0, 5.0, -6.0, -9.0]:
			for v: float in [1.0, 3.0, 5.0]:
				_play(nz._setup(x, v, n_def))
	nz.free()
	_report()
	assert_true(true)


# Steps a staged drill, following every team-0 release to its first touch.
func _play(duel: Object) -> void:
	var open: Dictionary = {}
	for i: int in int(SECS / Duel.DT):
		var before := Vector4(duel.bobbles, duel.deflects, duel.contests, duel.body_blocks)
		var vel_before: Dictionary = {}
		for s: Object in duel.skaters:
			vel_before[s.peer_id] = s.vel
		var puck_vel: Vector3 = duel.puck_vel
		var touched: int = duel.touched_by
		var n_rel: int = duel.releases.size()
		duel.step()
		if duel.releases.size() > n_rel:
			var rec: Dictionary = duel.releases[-1]
			if not open.is_empty():
				_close(open, duel)
			open = {}
			var decision: String = str(rec.get("decision", ""))
			_decisions[decision] = int(_decisions.get(decision, 0)) + 1
			if duel.team_map[int(rec["peer"])] == 0 and duel.carrier() == -1 \
					and not decision.begins_with("SHOOT") and not decision.begins_with("ONE_TIMER"):
				open = {"tick": duel.ticks, "passer": int(rec["peer"]),
						"to": int(rec.get("pass_peer", -1)),
						"pace": Vector2(duel.puck_vel.x, duel.puck_vel.z).length(),
						"air": duel.airborne_ticks > 0, "who": "none", "kind": "none",
						"closing": -1.0}
			continue
		if open.is_empty():
			continue
		if open["who"] == "none" and duel.touched_by != touched and duel.touched_by != -1 \
				and duel.touched_by != open["passer"]:
			var p: int = duel.touched_by
			var v: Vector3 = vel_before[p]
			open["closing"] = Vector2(puck_vel.x - v.x, puck_vel.z - v.z).length()
			open["who"] = "receiver" if p == open["to"] \
					else ("teammate" if duel.team_map[p] == 0 else "opponent")
			open["kind"] = "catch" if duel.carrier() == p \
					else "bobble" if duel.bobbles > before.x \
					else "deflect" if duel.deflects > before.y \
					else "contest" if duel.contests > before.z \
					else "block" if duel.body_blocks > before.w else "other"
		var age: float = (duel.ticks - int(open["tick"])) * Duel.DT
		if (open["who"] != "none" and age >= KEEP_S) or age >= WATCH_S:
			_close(open, duel)
			open = {}
	if not open.is_empty():
		_close(open, duel)


func _close(rel: Dictionary, duel: Object) -> void:
	var c: int = duel.carrier()
	rel["kept"] = c != -1 and duel.team_map[c] == 0
	_passes.append(rel)


func _report() -> void:
	gut.p("decisions at release: %s" % str(_decisions))
	gut.p("%d team-0 passes and rims" % _passes.size())
	var paces: Dictionary = {}
	var whos: Dictionary = {}
	for p: Dictionary in _passes:
		var k: String = "%s %2d-%2d m/s" % ["lofted" if p["air"] else "flat  ",
				int(p["pace"] / 4.0) * 4, int(p["pace"] / 4.0) * 4 + 4]
		paces[k] = int(paces.get(k, 0)) + 1
		var w: String = "%s %s" % [p["who"], p["kind"]]
		whos[w] = int(whos.get(w, 0)) + 1
	gut.p("paces fired:")
	var keys: Array = paces.keys()
	keys.sort()
	for k: String in keys:
		gut.p("  %s: %d" % [k, paces[k]])
	gut.p("first touches:")
	keys = whos.keys()
	keys.sort()
	for k: String in keys:
		gut.p("  %-22s %d" % [k, whos[k]])
	gut.p("the receiver's take, by closing speed in his frame (priced bobble odds):")
	for lo: int in range(0, 32, 2):
		var n: int = 0
		var caught: int = 0
		var bobbled: int = 0
		var deflected: int = 0
		var kept: int = 0
		for p: Dictionary in _passes:
			if p["who"] != "receiver" or p["closing"] < lo or p["closing"] >= lo + 2:
				continue
			n += 1
			caught += 1 if p["kind"] == "catch" else 0
			bobbled += 1 if p["kind"] == "bobble" else 0
			deflected += 1 if p["kind"] == "deflect" else 0
			kept += 1 if p["kept"] else 0
		if n > 0:
			gut.p("  %2d-%2d m/s: %3d | caught %3d bobbled %3d deflected %3d | kept %3d | priced %.2f"
					% [lo, lo + 2, n, caught, bobbled, deflected, kept,
					AIFeedReception.receiver_bobble_prob(lo + 1.0)])

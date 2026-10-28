extends GutTest

# Bots on bots have no "correct" outcome in general, so these stage a KNOWN
# advantage and assert the side holding it cashes it in: a rusher with a step on
# his backchecker shoots, an open back-door man gets the feed and the one-timer,
# a pressured carrier finds the open man ahead, a 2-on-1 ends in a shot, and two
# defenders back against one rusher concede nothing from the slot.
#
# Real bot agents in the duel harness against the real keeper (KeeperController
# on Goalie.tscn, ticked off the puck), as test_breakaway_finish does. Team 0
# attacks -Z.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
# The home plate a defence must keep a lone rusher out of: the slot, out to the
# hash marks' depth and the posts' width plus a stride.
const SLOT_DEPTH_M: float = 10.0
const SLOT_HALF_WIDTH_M: float = 4.0

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_ctrl.setup(_goalie, _puck, GOAL_Z, true)


class Play:
	# Every release, in order: {t, peer, team, shot, pass_peer, pos}.
	var releases: Array[Dictionary] = []
	# Who held the puck, in order, each with the time he took it: {t, peer}.
	var holders: Array[Dictionary] = []
	var lost_at: float = INF

	func first_shot(team: int) -> Dictionary:
		for r: Dictionary in releases:
			if r["shot"] and r["team"] == team:
				return r
		return {}

	func describe() -> String:
		var parts: PackedStringArray = []
		for r: Dictionary in releases:
			parts.append("%.2f %d %s at %.1f m" % [r["t"], r["peer"],
					"shot" if r["shot"] else "pass->%d" % r["pass_peer"], net_dist(r["pos"])])
		for h: Dictionary in holders:
			parts.append("%.2f has %d" % [h["t"], h["peer"]])
		return ", ".join(parts)

	static func net_dist(pos: Vector3) -> float:
		return Vector2(pos.x, pos.z + GameRules.GOAL_LINE_Z).length()


# rows: [peer, team, pos, vel]. Plays until team 0 shoots, team 1 takes the
# puck, or `secs` run out.
func _play(rows: Array, carrier: int, secs: float) -> Play:
	var duel := Duel.new()
	for r: Array in rows:
		duel.add_skater(r[0], r[1], r[2], null, r[3])
	duel.start(carrier)
	_ctrl.reset_to_crease()
	_shooter.global_position = rows[0][2]
	_puck.set_carrier(_shooter)
	duel.goalie_provider = func(team_id: int, puck_pos: Vector3) -> Variant:
		if team_id != 1:
			return null
		_shooter.global_position = puck_pos
		_puck.global_position = puck_pos
		_ctrl._physics_process(DT)
		return _goalie.global_position
	var out := Play.new()
	var held: int = carrier
	for t: int in int(secs / DT):
		var before: int = duel.releases.size()
		duel.step()
		if duel.releases.size() > before:
			var r: Dictionary = duel.releases[-1]
			var decision: String = r.get("decision", "")
			var shot: bool = decision == "SHOOT" or decision == "ONE_TIMER"
			out.releases.append({"t": t * DT, "peer": r["peer"], "team": r["team"],
					"shot": shot, "pass_peer": r.get("pass_peer", -1), "pos": r["pos"]})
			if shot and r["team"] == 0:
				return out
		if duel.carrier_id > 0 and duel.carrier_id != held:
			out.holders.append({"t": t * DT, "peer": duel.carrier_id})
			if duel.team_map[duel.carrier_id] == 1:
				out.lost_at = t * DT
				return out
		if duel.carrier_id > 0:
			held = duel.carrier_id
	return out


func test_a_step_on_the_backchecker_ends_in_a_shot() -> void:
	# [x, z, backchecker's lateral offset]: he trails by 2.5 m at the same pace.
	for c: Array in [[0.0, -6.0, 0.8], [7.0, -8.0, -0.8], [-7.0, -8.0, 0.8],
			[3.0, 2.0, -0.8], [-2.0, -10.0, 0.8]]:
		var start := Vector3(c[0], 0.0, c[1])
		var vel := Vector3(-start.x * 0.08, 0.0, -8.0)
		var p: Play = _play([[1, 0, start, vel],
				[201, 1, start + Vector3(c[2], 0.0, 2.5), vel]], 1, 4.0)
		var label := "step from (%.0f, %.0f)" % [start.x, start.z]
		gut.p("%s: %s" % [label, p.describe()])
		var shot: Dictionary = p.first_shot(0)
		assert_false(shot.is_empty(), "%s: the rusher gets a shot off" % label)
		assert_eq(p.lost_at, INF, "%s: and keeps the puck to it" % label)
		if not shot.is_empty():
			assert_lt(Play.net_dist(shot["pos"]), 8.0, "%s: from in tight" % label)


func test_an_open_back_door_gets_the_feed_and_the_one_timer() -> void:
	# The carrier below the dot has beaten his man outside; his mate is alone at
	# the far post. Both D2 spots leave the back door open.
	for d1: Vector3 in [Vector3(10, 0, GOAL_Z + 7), Vector3(8, 0, GOAL_Z + 8)]:
		for d2: Vector3 in [Vector3(-3, 0, GOAL_Z + 12), Vector3(4, 0, GOAL_Z + 9)]:
			for carry_vel: Vector3 in [Vector3(-2, 0, 0), Vector3(-3, 0, -2)]:
				var p: Play = _play([[1, 0, Vector3(7, 0, GOAL_Z + 4), carry_vel],
						[2, 0, Vector3(-2.5, 0, GOAL_Z + 2.2), Vector3.ZERO],
						[201, 1, d1, Vector3(-2, 0, 0)],
						[202, 1, d2, Vector3.ZERO]], 1, 3.0)
				var label := "back door, D1 %s, D2 %s, carry %s" % [d1, d2, carry_vel]
				gut.p("%s: %s" % [label, p.describe()])
				assert_true(not p.releases.is_empty() and not p.releases[0]["shot"]
						and p.releases[0]["pass_peer"] == 2 and p.releases[0]["t"] < 0.5,
						"%s: the carrier feeds the back door at once" % label)
				var shot: Dictionary = p.first_shot(0)
				assert_true(not shot.is_empty() and shot["peer"] == 2
						and Play.net_dist(shot["pos"]) < 5.0,
						"%s: and the back-door man shoots it from the post" % label)
				assert_eq(p.lost_at, INF, "%s: without a turnover" % label)


func test_a_pressured_carrier_finds_the_open_man_ahead() -> void:
	# Leaving his own blue line with a forechecker closing from his left, a mate
	# skating up the ice to his right and the far defender deep.
	for mate: Vector3 in [Vector3(5, 0, -4), Vector3(8, 0, -2), Vector3(2, 0, -6)]:
		for fc: Vector3 in [Vector3(-5, 0, 3), Vector3(-4, 0, 2)]:
			var p: Play = _play([[1, 0, Vector3(-3, 0, 6), Vector3(0, 0, -4)],
					[2, 0, mate, Vector3(0, 0, -6)],
					[201, 1, fc, Vector3(2, 0, 3)],
					[202, 1, Vector3(0, 0, -18), Vector3(0, 0, -2)]], 1, 3.0)
			var label := "outlet to %s, forechecker from %s" % [mate, fc]
			gut.p("%s: %s" % [label, p.describe()])
			assert_true(not p.releases.is_empty() and not p.releases[0]["shot"]
					and p.releases[0]["t"] < 0.5
					and (p.holders.is_empty() or p.holders[0]["t"] > p.releases[0]["t"]),
					"%s: the carrier moves it before the forechecker gets there" % label)


func test_a_two_on_one_ends_in_a_shot() -> void:
	for z: float in [-8.0, -12.0]:
		for d_x: float in [0.0, 1.5]:
			var p: Play = _play([[1, 0, Vector3(-4, 0, z), Vector3(0, 0, -7)],
					[2, 0, Vector3(4, 0, z), Vector3(0, 0, -7)],
					[201, 1, Vector3(d_x, 0, z - 7), Vector3(0, 0, -3)]], 1, 5.0)
			var label := "2-on-1 from z %.0f, D at x %.1f" % [z, d_x]
			gut.p("%s: %s" % [label, p.describe()])
			var shot: Dictionary = p.first_shot(0)
			assert_false(shot.is_empty(), "%s: the rush ends in a shot" % label)
			assert_eq(p.lost_at, INF, "%s: without a turnover" % label)
			if not shot.is_empty():
				assert_lt(Play.net_dist(shot["pos"]), 12.0, "%s: from inside the circles" % label)


func test_two_defenders_back_concede_no_slot_shot_to_one_rusher() -> void:
	for x: float in [-4.0, 0.0, 4.0]:
		for z: float in [-2.0, -8.0]:
			var p: Play = _play([[1, 0, Vector3(x, 0, z), Vector3(0, 0, -7)],
					[201, 1, Vector3(-2.5, 0, z - 10), Vector3(0, 0, -3)],
					[202, 1, Vector3(2.5, 0, z - 10), Vector3(0, 0, -3)]], 1, 5.0)
			var label := "1-on-2 from (%.0f, %.0f)" % [x, z]
			gut.p("%s: %s" % [label, p.describe()])
			var shot: Dictionary = p.first_shot(0)
			assert_true(shot.is_empty() or Play.net_dist(shot["pos"]) > SLOT_DEPTH_M
					or absf(shot["pos"].x) > SLOT_HALF_WIDTH_M,
					"%s: no shot from the slot" % label)

extends GutTest

# A breakaway ends in a shot, skated in facing the net.
#
# A real bot carrier against the real keeper (KeeperController on Goalie.tscn,
# ticked off the bot's puck), alone or with a backchecker on his tail, from the
# red line and the blue line. Each run must release a shot inside the window,
# never lose the puck, and never turn to skate backward or pull up on the way in:
# a carry that cannot price a drive at the net brakes in the slot or cuts back
# toward it facing up the ice, and stands there.
#
# And the shot leaves before he is on the keeper: the live keeper gives up most
# of the net to a release 2.5–3 m off his line and little inside 2 m
# (tests/instruments/ai/test_breakaway_release_truth.gd), so across tiers and
# seeds few releases may come inside 2 m — test_the_shot_leaves_before_the_keeper.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const CARRIER := 1
const CHASER := 201
const WINDOW_S: float = 4.0

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
	_ctrl.setup(_goalie, _puck, -GameRules.GOAL_LINE_Z, true)
	_ctrl.reset_to_crease()


# Skates one breakaway; returns {shot, lost, backward_ticks, min_speed, release,
# start_speed}. `carrier` is his peer id, which seeds his hands' draws.
func _breakaway(start: Vector3, vel: Vector3, chaser_offset: Vector3,
		profile: BotSkillProfile = null, carrier: int = CARRIER) -> Dictionary:
	_ctrl.reset_to_crease()
	var duel := Duel.new()
	duel.add_skater(carrier, 0, start, profile, vel)
	if chaser_offset.is_finite():
		duel.add_skater(CHASER, 1, start + chaser_offset, null, vel)
	duel.start(carrier)
	_shooter.global_position = start
	_puck.set_carrier(_shooter)
	duel.goalie_provider = func(team_id: int, puck_pos: Vector3) -> Variant:
		if team_id != 1:
			return null
		_shooter.global_position = puck_pos
		# His drive is what the keeper retreats off: left at rest, he holds the
		# top of his crease and the carrier skates onto him.
		_shooter.velocity = duel._skater(carrier).vel
		_puck.global_position = puck_pos
		_ctrl._physics_process(DT)
		return _goalie.global_position
	var out := {"shot": false, "lost": false, "backward_ticks": 0, "release": Vector3.INF,
			"min_speed": INF, "start_speed": vel.length()}
	for _t: int in int(WINDOW_S / DT):
		var before: int = duel.releases.size()
		duel.step()
		var s: Object = duel._skater(carrier)
		if duel.releases.size() > before:
			out["shot"] = duel.releases[-1].get("decision", "") == "SHOOT"
			out["release"] = s.pos
			return out
		if duel.carrier_id != carrier:
			out["lost"] = true
			return out
		var v := Vector2(s.vel.x, s.vel.z)
		out["min_speed"] = minf(out["min_speed"], v.length())
		if v.length() > 1.0 and v.normalized().dot(s.facing) < -0.3:
			out["backward_ticks"] += 1
	return out


func _assert_finished(label: String, r: Dictionary) -> void:
	gut.p("%s: shot %s, lost %s, backward %d ticks, slowest %.1f m/s, release %s" % [
			label, r["shot"], r["lost"], r["backward_ticks"], r["min_speed"], r["release"]])
	assert_false(r["lost"], "%s: the carrier keeps the puck to the shot" % label)
	assert_true(r["shot"], "%s: the breakaway ends in a shot inside %.0f s" % [label, WINDOW_S])
	assert_eq(r["backward_ticks"], 0, "%s: he never turns to skate backward" % label)
	assert_gt(r["min_speed"], 0.5 * r["start_speed"],
			"%s: he drives in rather than pulling up in the slot" % label)


func test_a_clean_breakaway_from_the_red_line() -> void:
	_assert_finished("clean", _breakaway(Vector3(0, 0, -1), Vector3(0, 0, -8.5), Vector3.INF))


func test_a_breakaway_with_a_backchecker_on_his_tail() -> void:
	_assert_finished("chased", _breakaway(Vector3(0, 0, -1), Vector3(0, 0, -8.5),
			Vector3(0.5, 0, 3.0)))


func test_a_breakaway_down_the_wing_with_a_backchecker() -> void:
	_assert_finished("wing", _breakaway(Vector3(6, 0, -3), Vector3(-1, 0, -8.5),
			Vector3(-1, 0, 4.0)))


func test_a_slow_breakaway_from_the_blue_line() -> void:
	_assert_finished("slow", _breakaway(Vector3(-2, 0, -GameRules.GOAL_LINE_Z + 19.0),
			Vector3(0, 0, -5.0), Vector3(0, 0, 5.0)))


# Share of breakaways released inside this far off the goal line, where the live
# keeper closes the net (measured best-aim odds 0.40 at 2 m against 1.0 at
# 2.5–3 m).
const CLIFF_M: float = 2.0
# Measured across the four breakaways and six seeds: Normal 0/24 (7/24 before
# the hands' hold was priced, #943), Easy 8/24 (19/24 before).
const NORMAL_INSIDE_CEILING: float = 0.1
const EASY_INSIDE_CEILING: float = 0.5


func test_the_shot_leaves_before_the_keeper() -> void:
	for tier: Array in [["normal", BotSkillProfile.normal(), NORMAL_INSIDE_CEILING],
			["easy", BotSkillProfile.easy(), EASY_INSIDE_CEILING]]:
		var shots: int = 0
		var inside: int = 0
		for seed_id: int in [1, 2, 3, 4, 5, 6]:
			for c: Array in [
				[Vector3(0, 0, -1), Vector3(0, 0, -8.5), Vector3.INF],
				[Vector3(0, 0, -1), Vector3(0, 0, -8.5), Vector3(0.5, 0, 3.0)],
				[Vector3(6, 0, -3), Vector3(-1, 0, -8.5), Vector3(-1, 0, 4.0)],
				[Vector3(-2, 0, -GameRules.GOAL_LINE_Z + 19.0), Vector3(0, 0, -5.0),
						Vector3(0, 0, 5.0)],
			]:
				var r: Dictionary = _breakaway(c[0], c[1], c[2], tier[1], seed_id)
				if not r["shot"]:
					continue
				shots += 1
				if r["release"].z + GameRules.GOAL_LINE_Z < CLIFF_M:
					inside += 1
		gut.p("%s: %d of %d breakaway shots released inside %.1f m" % [tier[0], inside,
				shots, CLIFF_M])
		assert_gt(shots, 18, "%s: the breakaways end in shots" % tier[0])
		assert_lt(float(inside) / maxi(shots, 1), tier[2],
				"%s: the shot leaves before he is on the keeper" % tier[0])

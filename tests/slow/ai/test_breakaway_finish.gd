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
# And the shot leaves where he meant it to. Hard's hands let go where he
# decides; a lower tier's hold lets go later, and at breakaway pace that is
# further in. Its compete prices the shot over that hold, so across seeds few
# of its releases may come a metre or more nearer the net than Hard's do on the
# same breakaway — test_the_shot_leaves_before_the_keeper.

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


# How much nearer the net than Hard lets go a release counts as carried in on
# the keeper by the hands' hold.
const CARRIED_IN_M: float = 1.0
# Measured across the four breakaways and six seeds: Normal 0/24, each mean
# release further out than Hard's; Easy 6/24, on the two breakaways nobody is
# chasing.
const NORMAL_CARRIED_IN_CEILING: float = 0.1
const EASY_CARRIED_IN_CEILING: float = 0.5
const _SEEDS: Array[int] = [1, 2, 3, 4, 5, 6]


# Start, velocity and chaser offset of each breakaway the tiers are held over.
func _starts() -> Array:
	return [
		[Vector3(0, 0, -1), Vector3(0, 0, -8.5), Vector3.INF],
		[Vector3(0, 0, -1), Vector3(0, 0, -8.5), Vector3(0.5, 0, 3.0)],
		[Vector3(6, 0, -3), Vector3(-1, 0, -8.5), Vector3(-1, 0, 4.0)],
		[Vector3(-2, 0, -GameRules.GOAL_LINE_Z + 19.0), Vector3(0, 0, -5.0), Vector3(0, 0, 5.0)],
	]


# How far off the goal line each of `profile`'s breakaways from start `c` is
# released, a seed each; a run that ends without a shot is left out.
func _releases(c: Array, profile: BotSkillProfile) -> Array[float]:
	var out: Array[float] = []
	for seed_id: int in _SEEDS:
		var r: Dictionary = _breakaway(c[0], c[1], c[2], profile, seed_id)
		if r["shot"]:
			out.append(r["release"].z + GameRules.GOAL_LINE_Z)
	return out


func test_the_shot_leaves_before_the_keeper() -> void:
	var meant: Array[float] = []
	for c: Array in _starts():
		var hard: Array[float] = _releases(c, BotSkillProfile.hard())
		assert_eq(hard.size(), _SEEDS.size(), "hard: every breakaway ends in a shot")
		var sum: float = 0.0
		for out: float in hard:
			sum += out
		meant.append(sum / maxi(hard.size(), 1))
	gut.p("hard lets go %s m off the goal line" % [meant])
	for tier: Array in [["normal", BotSkillProfile.normal(), NORMAL_CARRIED_IN_CEILING],
			["easy", BotSkillProfile.easy(), EASY_CARRIED_IN_CEILING]]:
		var shots: int = 0
		var carried_in: int = 0
		var starts: Array = _starts()
		for i: int in starts.size():
			for out: float in _releases(starts[i], tier[1]):
				shots += 1
				if out < meant[i] - CARRIED_IN_M:
					carried_in += 1
		gut.p("%s: %d of %d breakaway shots released %.1f m or more inside hard's" % [tier[0],
				carried_in, shots, CARRIED_IN_M])
		assert_gt(shots, 18, "%s: the breakaways end in shots" % tier[0])
		assert_lt(float(carried_in) / maxi(shots, 1), tier[2],
				"%s: the shot leaves before he is on the keeper" % tier[0])

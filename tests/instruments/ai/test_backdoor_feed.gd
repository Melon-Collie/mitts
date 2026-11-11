extends GutTest

# One play, read closely: our carrier on their right faceoff dot with the puck, a
# teammate at the left side of their net, one defender placed round them, the
# real keeper in the net. For each defender spot, what the carrier prices the
# shot and the feed across at (and the feed's completion terms), what he does in
# the next few seconds, and the raw shot-field odds of the two plays with no
# defender in them. Team 0 attacks -Z, so their right dot is +x.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const SECS: float = 3.0
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const CARRIER: int = 101
const MATE: int = 102
const DEFENDER: int = 201
const KEEPER_SETTLE_S: float = 1.5

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController
var _keeper_state: GoalieNetworkState = GoalieNetworkState.new()
var _lane_why: String = ""


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


# A spot `out` metres out from their goal line, `x` across.
static func _at(x: float, out: float) -> Vector3:
	return Vector3(x, 0.0, GOAL_Z + out)


static func _out(p: Vector3) -> float:
	return p.z - GOAL_Z


func _setup(carrier: Vector3, mate: Vector3, defender: Vector3) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	var hard: BotSkillProfile = BotSkillProfile.hard()
	duel.add_skater(CARRIER, 0, carrier, hard)
	duel.add_skater(MATE, 0, mate, hard)
	if defender.is_finite():
		duel.add_skater(DEFENDER, 1, defender, hard)
	duel.start(CARRIER)
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
		return _keeper_state
	return duel


func _agent(duel: Object, peer: int) -> SkaterAgentStateMachine:
	for s: Object in duel.skaters:
		if s.peer_id == peer:
			return s.agent
	return null


# Each defender's body and blade block on a flat feed from the carrier's pass
# puck at `origin` to `to` at 18 m/s, read as AIPuckLane.lane_clear's accurate read does.
func _why(c: AIRoleCarrier, origin: Vector3, to: Vector3) -> String:
	var f: AICarrierField = c._field
	var speed: float = 18.0
	var ll: float = origin.distance_to(to)
	var d: Vector3 = (to - origin) / ll
	var eff: float = ll / AIPuckLane._friction_traverse_time(ll, speed)
	var rl: float = maxf(ll - AIPuckLane.LANE_RECEIVER_REACH_M, 0.0)
	var out: String = ""
	for i: int in f.opponents_release.size():
		var p: Vector3 = f.opponents_release[i]
		var v: Vector3 = f.opponent_vels[i]
		var caps: AISkaterCaps = f.opponent_caps[i]
		var body: Vector2 = AILaneReach.block(origin.x, origin.z, d.x, d.z, rl, eff, p.x, p.z,
				v.x, v.z, AILaneReach.defender_reach(caps), caps.max_speed, caps.max_accel,
				AIPuckLane.LANE_REACTION_DELAY_S)
		var b: Vector3 = f.opponent_blades_release[i]
		var blade: Vector2 = AIPuckLane._blade_block(origin.x, origin.z, d.x, d.z, rl, eff,
				b.x, b.z, p.x, p.z, v.x, v.z, caps.max_blade_reach,
				AIPuckLane.LANE_LATERAL_FRACTION * caps.max_speed, caps.blade_speed)
		var off: float = absf((p.x - origin.x) * d.z - (p.z - origin.z) * d.x)
		var boff: float = absf((b.x - origin.x) * d.z - (b.z - origin.z) * d.x)
		out += ("\n      defender at release (%.1f, %.1f out) vel (%.1f, %.1f) %.2f m off the line,"
				+ " body block %.2f at %.1f m | blade %.2f m off, block %.2f | reach %.2f, flight %.2f s") % [
				p.x, _out(p), v.x, v.z, off, body.x, body.y, boff, blade.x,
				AILaneReach.defender_reach(caps), ll / eff]
	return out


# The carrier's read on his first decision, then what he does.
func _play(label: String, defender: Vector3) -> void:
	var carrier: Vector3 = _at(GameRules.END_ZONE_FACEOFF_DOT_X, 6.1)
	var mate: Vector3 = _at(-1.8, 1.2)
	var duel: Object = _setup(carrier, mate, defender)
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var first: String = ""
	var outcome: String = "held"
	for i: int in int(SECS / Duel.DT):
		var before: int = duel.releases.size()
		duel.step()
		var agent: SkaterAgentStateMachine = _agent(duel, CARRIER)
		if first == "" and agent != null and agent._carrier != null and i >= 3:
			var c: AIRoleCarrier = agent._carrier
			var read: Vector4 = c._pass.debug_completion
			var keeper := Vector3(_keeper_state.position_x, 0.0, _keeper_state.position_z)
			var shot_raw: float = AIShotValue.now(duel.puck_pos, goal, keeper,
					_keeper_state.velocity_x, AIShotOdds.stance_of(_keeper_state, goal),
					_keeper_state.rotation_y, AIShotOdds.History.CARRIED)
			var mate_pos: Vector3 = duel.skater_pos(MATE)
			var feed_raw: float = AIShotValue.feed(duel.puck_pos, mate_pos, 16.0, goal, keeper,
					true)
			_lane_why = _why(c, duel.puck_pos, duel.skater_pos(MATE))
			first = ("shoot %.3f (raw %.3f) | pass %.3f (raw one-timer %.3f): clean %.2f lane %.2f miss %.2f kept-on-catch %.2f | carry %.3f | mate ready %s"
					% [c.debug_shoot_score, shot_raw, c.debug_pass_score, feed_raw,
					read.x, read.y, read.z, read.w, c.debug_carry_score,
					str(c._pass != null and agent._current_strategy != null
							and agent._current_strategy.is_one_timer_ready(MATE))])
		if duel.releases.size() > before and int(duel.releases[-1]["team"]) == 0:
			var rec: Dictionary = duel.releases[-1]
			outcome = ("" if outcome == "held" else outcome + ", ") + "%s by %s at %.2f s" % [
					rec.get("decision", "?"), "carrier" if int(rec["peer"]) == CARRIER else "mate",
					(i + 1) * Duel.DT]
			if int(rec["peer"]) == CARRIER and rec.get("decision", "") != "SHOOT":
				continue
			break
		var c2: int = duel.carrier()
		if c2 != -1 and duel.team_map[c2] == 1:
			outcome += " / lost at %.2f s" % ((i + 1) * Duel.DT)
			break
	if _lane_why != "":
		gut.p(_lane_why.substr(1))
	_lane_why = ""
	var where: String = "none" if not defender.is_finite() \
			else "(%5.1f, %4.1f out)" % [defender.x, _out(defender)]
	gut.p("  %-18s defender %s" % [label, where])
	gut.p("      first read: %s" % first)
	gut.p("      then: %s" % outcome)


# The defender at the feed's midpoint, `off` metres off its line: toward their
# goal line (negative) or up the slot (positive).
func _off_lane(off: float) -> Vector3:
	var a: Vector3 = _at(GameRules.END_ZONE_FACEOFF_DOT_X, 6.1)
	var b: Vector3 = _at(-1.8, 1.2)
	var n := Vector3(-(b - a).z, 0.0, (b - a).x).normalized()
	if _out(a + n) < _out(a):
		n = -n
	return (a + b) * 0.5 + n * off


func test_defender_off_the_feed_line() -> void:
	for off: float in [-3.0, -2.0, -1.5, -1.0, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0]:
		_play("lane %+.1f m" % off, _off_lane(off))
	assert_true(true)


# What really happens to the feed across: released from the carrier's puck at
# `speed` toward the mate's blade on the third tick, the defender `off` metres
# off its line (as _off_lane), both of them live Hard bots. Who touches it first.
func _forced(off: float, speed: float) -> String:
	var duel: Object = _setup(_at(GameRules.END_ZONE_FACEOFF_DOT_X, 6.1), _at(-1.8, 1.2),
			_off_lane(off))
	for _i: int in 3:
		duel.step()
	var mate_blade: Vector3 = Vector3.INF
	var def_blade: Vector3 = Vector3.INF
	for sk: Object in duel.skaters:
		if sk.peer_id == MATE:
			mate_blade = sk.blade
		if sk.peer_id == DEFENDER:
			def_blade = sk.blade
	var dir: Vector3 = mate_blade - duel.puck_pos
	dir.y = 0.0
	dir = dir.normalized()
	var d_off: float = absf((def_blade.x - duel.puck_pos.x) * dir.z
			- (def_blade.z - duel.puck_pos.z) * dir.x)
	var model: String = _model_reads(duel, duel.puck_pos, mate_blade, speed)
	duel.carrier_id = -1
	duel.loose_released_by = CARRIER
	duel._release_grace[CARRIER] = duel.ticks + Duel.RELEASE_GRACE_TICKS
	duel.puck_vel = dir * speed
	var touches: int = 0
	for i: int in int(1.5 / Duel.DT):
		var before: int = duel.releases.size()
		var t0: int = duel.deflects + duel.bobbles + duel.contests
		duel.step()
		var t: String = "%.2f s" % ((i + 1) * Duel.DT)
		var c: int = duel.carrier()
		if c == DEFENDER:
			return "PICKED off (%s) | blade %.2f m off" % [t, d_off] + model
		if duel.releases.size() > before:
			return "one-timed (%s) | blade %.2f m off" % [t, d_off] + model
		if c == MATE:
			return "caught (%s) | blade %.2f m off" % [t, d_off] + model
		if duel.deflects + duel.bobbles + duel.contests > t0:
			touches += 1
			var near: String = "defender" if def_blade.is_finite() \
					and duel.puck_pos.distance_to(_blade_of(duel, DEFENDER)) \
					< duel.puck_pos.distance_to(_blade_of(duel, MATE)) else "mate"
			return "touched by the %s (%s) | blade %.2f m off" % [near, t, d_off] + model
	return "nobody (%d) | blade %.2f m off" % [touches, d_off] + model


# The accurate lane read's two halves for the defender as he stands at the
# release, on a flat feed from `origin` to `to` at `speed`: as priced (his read
# starting at the release) and as it would read were he moving on the windup.
func _model_reads(duel: Object, origin: Vector3, to: Vector3, speed: float) -> String:
	var sk: Object = null
	for o: Object in duel.skaters:
		if o.peer_id == DEFENDER:
			sk = o
	var caps: AISkaterCaps = Duel.match_caps()
	var ll: float = origin.distance_to(to)
	var d: Vector3 = (to - origin) / ll
	var eff: float = ll / AIPuckLane._friction_traverse_time(ll, speed)
	var rl: float = maxf(ll - AIPuckLane.LANE_RECEIVER_REACH_M, 0.0)
	var out: String = " | model"
	for delay: float in [AIPuckLane.LANE_REACTION_DELAY_S - AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S,
			AIPuckLane.LANE_REACTION_DELAY_S]:
		var body: float = AILaneReach.block(origin.x, origin.z, d.x, d.z, rl, eff, sk.pos.x,
				sk.pos.z, sk.vel.x, sk.vel.z, AILaneReach.defender_reach(caps), caps.max_speed,
				caps.max_accel, delay).x
		var blade: float = AIPuckLane._blade_block(origin.x, origin.z, d.x, d.z, rl, eff,
				sk.blade.x, sk.blade.z, sk.pos.x, sk.pos.z, sk.vel.x, sk.vel.z,
				caps.max_blade_reach, AIPuckLane.LANE_LATERAL_FRACTION * caps.max_speed,
				caps.blade_speed, delay).x
		out += " %s: lane %.2f (body %.2f blade %.2f)" % ["windup" if delay < 0.0 else "release",
				(1.0 - body) * (1.0 - blade), body, blade]
	return out


func _blade_of(duel: Object, peer: int) -> Vector3:
	for sk: Object in duel.skaters:
		if sk.peer_id == peer:
			return sk.blade
	return Vector3.INF


func test_forced_feed_across() -> void:
	for off: float in [-2.0, -1.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
		for speed: float in [14.0, 18.0, 22.0]:
			gut.p("  lane %+.1f m, %.0f m/s: %s" % [off, speed, _forced(off, speed)])
	assert_true(true)


func test_backdoor_feed() -> void:
	_play("no defender", Vector3.INF)
	_play("in the slot", _at(1.0, 4.0))
	_play("on the mate", _at(-1.2, 2.2))
	_play("mate's back", _at(-2.6, 0.6))
	_play("in the lane", _at(2.5, 3.6))
	_play("on the carrier", _at(5.2, 4.8))
	_play("high slot", _at(0.5, 9.0))
	_play("net-front", _at(-0.3, 2.0))
	assert_true(true)

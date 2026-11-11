extends GutTest

# test_advantage_scenarios' 2-on-1 from z -8, D at x 1.5, traced tick by tick
# from the carrier's side: his compete (the shot, the best pass and to whom, the
# carry) and his intent, the pass read's parts (release clean, lane, the miss,
# the reception), and where the lone D's stick is against the lane to the mate:
# how far it lies off the lane now, and how far down it from the puck. Real bot
# agents in the duel harness against the real keeper, staged as that test is.
# Team 0 attacks -Z.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const CARRIER := 1
const MATE := 2
const D := 201
const EVERY_TICKS: int = 3
const INTENTS: Dictionary = {0: "carry", 1: "SHOOT", 3: "PASS", 5: "dump"}

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


func _trace(z: float, d_x: float, secs: float) -> void:
	var duel := Duel.new()
	duel.add_skater(CARRIER, 0, Vector3(-4, 0, z), null, Vector3(0, 0, -7))
	duel.add_skater(MATE, 0, Vector3(4, 0, z), null, Vector3(0, 0, -7))
	duel.add_skater(D, 1, Vector3(d_x, 0, z - 7), null, Vector3(0, 0, -3))
	duel.start(CARRIER)
	_ctrl.reset_to_crease()
	_shooter.global_position = Vector3(-4, 0, z)
	_puck.set_carrier(_shooter)
	duel.goalie_provider = func(team_id: int, puck_pos: Vector3) -> Variant:
		if team_id != 1:
			return null
		_shooter.global_position = puck_pos
		_puck.global_position = puck_pos
		_ctrl._physics_process(DT)
		return _goalie.global_position
	gut.p("    t  carrier(x,z)  net m | shoot  pass(->)  carry | intent | clean lane  miss recv | D(x,z)  D-stick off-lane along | stick-puck | D vel | read-stick off-lane")
	for t: int in int(secs / DT):
		var before: int = duel.releases.size()
		duel.step()
		if duel.releases.size() > before:
			var r: Dictionary = duel.releases[-1]
			gut.p("   >>> %.2f release by %d: %s  pass_peer %s  pass_kept %s" % [t * DT, r["peer"],
					r.get("decision", ""), str(r.get("pass_peer", -1)),
					str(r.get("pass_kept", -1.0))])
		if duel.carrier_id != CARRIER:
			gut.p("   >>> %.2f carrier is now %d" % [t * DT, duel.carrier_id])
			if duel.carrier_id == D or duel.carrier_id == -1 and t * DT > 2.5:
				return
			if duel.carrier_id != -1:
				return
			continue
		if t % EVERY_TICKS != 0:
			continue
		var c: Object = duel._skater(CARRIER)
		var m: Object = duel._skater(MATE)
		var dd: Object = duel._skater(D)
		var carrier: AIRoleCarrier = c.agent._carrier
		var completion: Vector4 = carrier._pass.debug_completion
		var lane: Vector3 = m.pos - duel.puck_pos
		lane.y = 0.0
		var lane_len: float = maxf(lane.length(), 1e-4)
		var u: Vector3 = lane / lane_len
		var rel: Vector3 = dd.blade - duel.puck_pos
		rel.y = 0.0
		var along: float = rel.dot(u)
		var off: float = (rel - u * along).length()
		# Where the carrier's pass read holds the D's stick at the release
		# (AICarrierField.opponent_blades_release), off the same lane.
		var read_off: float = -1.0
		for i: int in carrier._field.opponents.size():
			if carrier._field.opponents[i].distance_to(dd.pos) < 0.05:
				var rb: Vector3 = carrier._field.opponent_blades_release[i] - duel.puck_pos
				rb.y = 0.0
				read_off = (rb - u * rb.dot(u)).length()
		# The read's own lane (the puck to the spot the best pass is led to) and the
		# D's blade on it, as the read holds it: off that lane, along it, and the
		# blade term's block.
		var spot: Vector3 = carrier._pass.debug_spot
		var probe: String = ""
		if spot.is_finite():
			var lane2: Vector3 = spot - duel.puck_pos
			lane2.y = 0.0
			var l2: float = lane2.length()
			var u2: Vector3 = lane2 / maxf(l2, 1e-4)
			var rb2: Vector3 = dd.blade - duel.puck_pos
			rb2.y = 0.0
			var read_len: float = maxf(l2 - AIPuckLane.LANE_RECEIVER_REACH_M, 0.0)
			var caps: AISkaterCaps = duel.caps_by_peer.get(D)
			var blk: Vector2 = AIPuckLane._blade_block(duel.puck_pos.x, duel.puck_pos.z,
					u2.x, u2.z, read_len, 14.0, dd.blade.x, dd.blade.z, dd.pos.x, dd.pos.z,
					dd.vel.x, dd.vel.z, caps.max_blade_reach, AIPuckLane.LANE_LATERAL_FRACTION * caps.max_speed,
					caps.blade_speed)
			probe = " | read lane %.1f m (read to %.1f) stick off %.2f along %.1f -> blade block %.2f" % [
					l2, read_len, (rb2 - u2 * rb2.dot(u2)).length(), rb2.dot(u2), blk.x]
		gut.p(("%5.2f %5.1f %5.1f %5.1f | %5.3f %5.3f(%d) %5.3f | %-6s | %4.2f %4.2f %4.2f %4.2f | %5.1f %5.1f  %5.2f %5.1f/%4.1f | %4.2f | %4.1f %4.1f | %5.2f" % [
				t * DT, c.pos.x, c.pos.z, Vector2(c.pos.x, c.pos.z - GOAL_Z).length(),
				carrier.debug_shoot_score, carrier.debug_pass_score, carrier.debug_pass_peer_id,
				carrier.debug_carry_score, INTENTS.get(carrier.intended_action, "?"),
				completion.x, completion.y, completion.z, completion.w,
				dd.pos.x, dd.pos.z, off, along, lane_len, dd.blade.distance_to(duel.puck_pos),
				dd.vel.x, dd.vel.z, read_off]) + probe)


func test_trace_two_on_one_z8_d15() -> void:
	_trace(-8.0, 1.5, 2.5)
	assert_true(true)


func test_trace_two_on_one_z8_d0() -> void:
	# The start beside it, lost the same way (#928), to read against.
	_trace(-8.0, 0.0, 2.0)
	assert_true(true)

extends GutTest

# Where does a defender's stick take a puck carried past him?
#
# A real bot carrier is held to a straight line past a standing defender at a
# set miss distance (body to body, across the line), at a set pace; everything
# else about the carry is the agent's own — its cursor, so its shielding. The
# defender is a poker: feet planted, blade sent at the puck as he saw it
# REACTION_S ago, at his reach (the duel harness's ring) and blade speed. The
# harness's swept poke decides the strip. Swept across miss distance, the side
# he stands on (the carrier's forehand or backhand) and pace, at the reach of a
# standing body and of a skating one, beside what AICarrySpace's crossing band
# prices for the same pass.
#
# Read it for the miss distance where the puck stops being taken, per side: the
# band's edges and its protect shift are claims about exactly that.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const CARRIER := 1
const POKER := 201
const REACTION_S: float = 0.15
const START_Z: float = 7.0
const DEFENDER_Z: float = 0.0
const PAST_Z: float = -3.0
const MISSES: Array[float] = [0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.2]
const PACES: Array[float] = [4.0, 6.0, 8.0]
# Standing and skating reach ahead (TopHandIK.full_reach; the Oct 19 level-frame
# solve measured 1.79 m standing, 2.32 m skating).
const REACHES: Array[float] = [1.8, 2.33]

# Where the carried puck sat across the line, off the body, as the carrier came
# level with the defender in the last _cross (+X: the poker's side when he
# stands at +X).
var last_offset: float = 0.0
var closest_dz: float = INF


# 1 kept past him, 0 stripped, -1 neither (released or never reached him).
# `leads`: he carries his sighting on by its velocity over his reaction, as a
# poker reading the carry does; without it he swipes where it was.
func _cross(miss: float, side: float, pace: float, reach: float, leads: bool) -> int:
	var duel := Duel.new()
	duel.add_skater(CARRIER, 0, Vector3(0, 0, START_Z), null, Vector3(0, 0, -pace))
	duel.add_skater(POKER, 1, Vector3(side * miss, 0, DEFENDER_Z))
	duel.start(CARRIER)
	var carrier: Object = duel._skater(CARRIER)
	closest_dz = INF
	carrier.input_override = func(s: Object) -> void:
		s.input.move_vector = Vector2(0, -1)
		s.input.brake = false
		s.input.shoot_pressed = false
		s.input.shoot_held = false
		s.input.slap_pressed = false
		s.input.slap_held = false
		s.input.quick_pass_pressed = false
	var poker: Object = duel._skater(POKER)
	poker.blade_reach = reach
	poker.facing = Vector2(0, 1)
	var seen: Array[Vector3] = []
	var seen_vel: Array[Vector3] = []
	var lag: int = roundi(REACTION_S / DT)
	poker.input_override = func(s: Object) -> void:
		seen.append(duel.puck_pos)
		seen_vel.append(duel.puck_vel)
		var k: int = maxi(seen.size() - 1 - lag, 0)
		s.input.move_vector = Vector2.ZERO
		s.input.brake = true
		s.input.mouse_world_pos = seen[k] + (seen_vel[k] * REACTION_S if leads else Vector3.ZERO)
	for _t: int in int(4.0 / DT):
		duel.step()
		poker.vel = Vector3.ZERO
		poker.pos = Vector3(side * miss, 0, DEFENDER_Z)
		if absf(carrier.pos.z - DEFENDER_Z) < absf(closest_dz):
			closest_dz = carrier.pos.z - DEFENDER_Z
			last_offset = duel.puck_pos.x - carrier.pos.x
		if duel.carrier_id != CARRIER:
			return 0 if duel.strips > 0 else -1
		if carrier.pos.z < PAST_Z:
			return 1
	return -1


# The band's keep for the same pass: the carried puck's straight line past a
# standing man at this miss, at the league body's span.
func _model(miss: float, side: float, pace: float) -> float:
	var opps: Array[Vector3] = [Vector3(side * miss, 0, DEFENDER_Z)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var caps: Array = [Duel.match_caps()]
	var from := Vector3(0, 0, START_Z - AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M)
	var to := Vector3(0, 0, PAST_Z - AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M)
	return AICarrySpace.carry_crossing_keep(from, to, (START_Z - PAST_Z) / pace,
			opps, vels, caps)


func test_report_the_crossing_band() -> void:
	var lefty: bool = Duel.match_caps().is_left_handed
	gut.p("carrier %s-handed; blade span %.2f, full reach %.2f; poker reaction %.2f s" % [
			"left" if lefty else "right", Duel.match_caps().blade_span,
			Duel.match_caps().max_blade_reach, REACTION_S])
	for leads: bool in [false, true]:
		gut.p("── poker %s" % ("leading the carry" if leads else "swiping where he saw it"))
		for reach: float in REACHES:
			_report(reach, leads, lefty)
	gut.p("misses: %s" % [MISSES])
	assert_true(true)


func test_report_the_edge_finely() -> void:
	var fore: float = FacingRules.forehand_sign(Duel.match_caps().is_left_handed)
	for reach: float in REACHES:
		for side_name: String in ["forehand", "backhand"]:
			var side: float = fore if side_name == "forehand" else -fore
			var row := "reach %.2f %-8s 6 m/s, leading |" % [reach, side_name]
			for i: int in 16:
				var miss: float = reach - 0.6 + 0.1 * i
				var r: int = _cross(miss, side, 6.0, reach, true)
				row += " %.1f:%s(%+.2f)" % [miss, "k" if r == 1 else ("L" if r == 0 else "-"), last_offset * side]
			gut.p(row)
	assert_true(true)


func _report(reach: float, leads: bool, lefty: bool) -> void:
	var fore: float = FacingRules.forehand_sign(lefty)
	for side_name: String in ["forehand", "backhand"]:
		# +X is the right of a skater facing -Z.
		var side: float = fore if side_name == "forehand" else -fore
		for pace: float in PACES:
			var row := "reach %.2f  %-8s %.0f m/s |" % [reach, side_name, pace]
			var model_row := "                   model |"
			for miss: float in MISSES:
				var r: int = _cross(miss, side, pace, reach, leads)
				row += " %4s" % ("keep" if r == 1 else ("LOST" if r == 0 else "--"))
				model_row += " %4.2f" % _model(miss, side, pace)
			gut.p(row)
			if reach == REACHES[REACHES.size() - 1] and leads:
				gut.p(model_row)

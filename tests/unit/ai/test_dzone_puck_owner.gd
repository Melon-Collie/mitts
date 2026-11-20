extends GutTest

# The puck's owner in our zone goes to the man who has it, wherever he takes it.
# Three set defenders against a scripted carrier who stands with it and can be
# stripped (tests/instruments/ai/test_dzone_pressure.gd sweeps the whole zone,
# each tier and both team sizes).
#
# Team 1 defends -Z.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const CARRIER := 1
const SECS: float = 5.0
# A defender who never came this near the carrier did not play him
# (test_one_on_one_to_the_crease.gd's bound): two sticks past body contact.
const UNPLAYED_STICKS: float = 2.0


# The carrier standing at `at` with a mate at the point and one at the net
# front, three defenders of `profile` set in their zone.
func _stand(at: Vector3, profile: BotSkillProfile, shields: bool = false) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	duel.add_scripted_attacker(CARRIER, 0, [at, at] as Array[Vector3], 0.0)
	duel._skater(CARRIER).script_strippable = true
	duel._skater(CARRIER).script_shields = shields
	var mates: Array[Vector3] = [Vector3(6.0, 0, -11.0), Vector3(3.0, 0, -22.0)]
	for i: int in mates.size():
		duel.add_scripted_attacker(2 + i, 0, [mates[i], mates[i]] as Array[Vector3], 0.0)
	var defenders: Array[Vector3] = [Vector3(-3.0, 0, -20.0), Vector3(1.5, 0, -23.0),
			Vector3(1.0, 0, -14.0)]
	for i: int in defenders.size():
		duel.add_skater(50 + i, 1, defenders[i], profile)
		duel._skater(50 + i).facing = Vector2(0.0, 1.0)
	duel.start(CARRIER)
	return duel


# The nearest any defender's body comes to the carrier over the run, which ends
# when he loses the puck.
func _closest_m(duel: Object) -> float:
	var closest: float = INF
	for _t: int in int(SECS / DT):
		duel.step()
		var car: Vector3 = duel._skater(CARRIER).pos
		for s: Object in duel.skaters:
			if s.team_id == 1:
				closest = minf(closest, s.pos.distance_to(car))
		if duel.carrier_id != CARRIER:
			break
	return closest


func test_a_carrier_behind_our_net_is_played() -> void:
	var duel: Object = _stand(Vector3(-1.5, 0, -GameRules.GOAL_LINE_Z - GameRules.NET_DEPTH - 1.2),
			BotSkillProfile.hard())
	var closest: float = _closest_m(duel)
	assert_lte(closest,
			2.0 * duel._match_body.radius + UNPLAYED_STICKS * GameRules.DEFAULT_STICK_LENGTH_M,
			"nobody came nearer him than %.1f m" % closest)


func test_a_carrier_who_turns_the_puck_away_draws_his_man_in() -> void:
	# On the half-wall. Facing our net with the puck out in front he is held at
	# the gap; with his body between it and the nearest defender the gap is to
	# the puck, a carry's reach nearer him.
	var half_wall := Vector3(-11.0, 0, -17.0)
	var open_m: float = _closest_m(_stand(half_wall, BotSkillProfile.normal()))
	var shielded_m: float = _closest_m(_stand(half_wall, BotSkillProfile.normal(), true))
	assert_lt(shielded_m, open_m - 0.3,
			"held %.2f m off an open puck and %.2f m off a shielded one" % [open_m, shielded_m])

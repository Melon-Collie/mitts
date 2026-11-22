extends GutTest

# The puck's owner in our zone goes to the man who has it and plays the puck,
# wherever he takes it. Three set defenders against a scripted carrier who can
# be stripped (tests/instruments/ai/test_dzone_pressure.gd sweeps the whole
# zone, each tier and both team sizes; each test here is one of its starts that
# the owner left alone for the whole run).
#
# Team 1 defends -Z.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const CARRIER := 1
const SECS: float = 5.0
# A defender who never came this near the carrier did not play him
# (test_one_on_one_to_the_crease.gd's bound): two sticks past body contact.
const UNPLAYED_STICKS: float = 2.0
const HALF_WALL := Vector3(-11.0, 0, -17.0)


# The carrier skating `path` at `speed` (one point: standing on it) with a mate
# at the point and one at the net front, three defenders of `profile` set in
# their zone. `shields`: he keeps his body between the puck and the nearest of
# them; else he faces our net with it out in front of him.
func _stage(path: Array[Vector3], speed: float, profile: BotSkillProfile,
		shields: bool = false) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 3
	if path.size() == 1:
		path.append(path[0])
	duel.add_scripted_attacker(CARRIER, 0, path, speed)
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
	var behind_net := Vector3(-1.5, 0, -GameRules.GOAL_LINE_Z - GameRules.NET_DEPTH - 1.2)
	var duel: Object = _stage([behind_net], 0.0, BotSkillProfile.hard())
	var closest: float = _closest_m(duel)
	assert_lte(closest,
			2.0 * duel._match_body.radius + UNPLAYED_STICKS * GameRules.DEFAULT_STICK_LENGTH_M,
			"nobody came nearer him than %.1f m" % closest)


func test_a_carrier_shielding_the_puck_up_the_wall_is_taken_off_it() -> void:
	# Skating the half-wall at an easy pace with his body between the puck and
	# his man: followed a metre off, at less than his own pace, he kept it.
	var duel: Object = _stage([Vector3(-11.0, 0, -14.0), Vector3(-11.0, 0, -21.0)], 3.0,
			BotSkillProfile.hard(), true)
	var closest: float = _closest_m(duel)
	assert_ne(duel.carrier_id, CARRIER,
			"he kept the puck %.0f s; nobody came nearer than %.1f m" % [SECS, closest])


func test_a_puck_held_out_in_front_of_him_is_taken() -> void:
	# Standing on the half-wall, facing our net, the puck a blade's length out in
	# front and nothing protecting it. On the tier that concedes a standoff: held
	# to his body, its stand left the blade short of the puck for as long as he
	# stood there.
	var duel: Object = _stage([HALF_WALL], 0.0, BotSkillProfile.normal())
	_closest_m(duel)
	assert_ne(duel.carrier_id, CARRIER,
			"he stood there %.0f s with the puck out in front of him and kept it" % SECS)

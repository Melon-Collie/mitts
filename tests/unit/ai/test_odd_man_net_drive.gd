extends GutTest

# A 3-on-2 against the back pair, the rest of the defence caught up the ice so
# the zone coverage is not home to take anybody: the carrier down the wall, a
# man driving the middle to the net front, a third wide on the far side. The
# back line's man on the driver goes in with him.
#
# Team 1 defends -Z.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const GL: float = GameRules.GOAL_LINE_Z
const CARRIER := 1
const DRIVER := 2
const SECS: float = 6.0
# The driver is at the net front once he is this far off our goal line.
const NET_FRONT_DEPTH_M: float = 2.0


func _stage(team_size: int, driver_speed: float) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = team_size
	duel.add_scripted_attacker(CARRIER, 0,
			[Vector3(9.0, 0, 4.0), Vector3(10.0, 0, -21.0)] as Array[Vector3], 6.5)
	duel.add_scripted_attacker(DRIVER, 0,
			[Vector3(0.0, 0, 6.0), Vector3(0.0, 0, -GL + 1.6)] as Array[Vector3], driver_speed)
	duel.add_scripted_attacker(3, 0,
			[Vector3(-7.0, 0, 6.0), Vector3(-6.0, 0, -20.0)] as Array[Vector3], 7.5)
	var back_pair: Array[Vector3] = [Vector3(4.0, 0, -9.5), Vector3(-2.0, 0, -9.5)]
	var caught_up_ice: Array[Vector3] = [Vector3(1.0, 0, 22.0)]
	if team_size == 5:
		caught_up_ice.append_array([Vector3(6.0, 0, 24.0), Vector3(-6.0, 0, 24.0)])
		for x: float in [6.0, -6.0]:
			duel.add_scripted_attacker(duel.skaters.size() + 1, 0,
					[Vector3(x, 0, 16.0), Vector3(x, 0, 0.0)] as Array[Vector3], 5.0)
	# Forwards first: a 5v5 seat's position is its index.
	var defenders: Array[Vector3] = caught_up_ice + back_pair if team_size == 5 \
			else back_pair + caught_up_ice
	for i: int in defenders.size():
		duel.add_skater(50 + i, 1, defenders[i], BotSkillProfile.hard())
		if team_size == 5:
			duel.positions[50 + i] = i
		duel._skater(50 + i).facing = Vector2(0.0, 1.0)
	duel.start(CARRIER)
	return duel


# Between the house gate and the net front, of the driver's nearest defender:
# x the farthest he is from him, y the furthest up the driver's line to our net
# he falls behind him. INF when the driver never gets there.
func _worst_on_the_driver(duel: Object) -> Vector2:
	var our_net := Vector3(0.0, 0.0, -GL)
	var worst := Vector2(0.0, -INF)
	for _t: int in int(SECS / DT):
		duel.step()
		var man: Vector3 = duel._skater(DRIVER).pos
		var depth: float = man.z + GL
		if depth > AIZoneCoverage.HOUSE_TOP_DEPTH_M:
			continue
		var nearest: Vector3 = Vector3.INF
		for s: Object in duel.skaters:
			if s.team_id == 1 and (not nearest.is_finite()
					or s.pos.distance_to(man) < nearest.distance_to(man)):
				nearest = s.pos
		worst.x = maxf(worst.x, nearest.distance_to(man))
		worst.y = maxf(worst.y, (man - nearest).dot((our_net - man).normalized()))
		if depth <= NET_FRONT_DEPTH_M:
			return worst
	return Vector2.INF


func test_the_man_driving_the_net_is_ridden_in() -> void:
	# From the house gate to the net front, some defender's stick can reach him
	# on every tick. A cover held out at the gate lets him go the last ten
	# metres alone.
	var duel: Object = _stage(3, 8.0)
	var reach_in: float = duel.match_caps().max_blade_reach + GameRules.POKE_RADIUS_M
	var farthest: float = _worst_on_the_driver(duel).x
	assert_lt(farthest, reach_in,
			"inside the house gate his nearest defender was %.2f m off him" % farthest)


func test_the_d_on_him_keeps_him_when_the_rush_becomes_zone_coverage() -> void:
	# 5v5, the forwards whose ice the high slot is still outside our line. The
	# D riding the driver in stays his man through the change of shape: handed
	# a man by his own area alone, he leaves him for the wide one.
	var duel: Object = _stage(5, 6.5)
	var reach_in: float = duel.match_caps().max_blade_reach + GameRules.POKE_RADIUS_M
	var farthest: float = _worst_on_the_driver(duel).x
	assert_lt(farthest, reach_in,
			"inside the house gate his nearest defender was %.2f m off him" % farthest)


func test_the_d_on_a_fast_driver_does_not_cross_in_front_of_him() -> void:
	# 5v5, the D a stride to the driver's weak side and the cover stand on his
	# strong side, toward the feed. Crossing to it while he builds his retreat,
	# he is behind the driver from the hash marks in.
	var behind: float = _worst_on_the_driver(_stage(5, 8.0)).y
	assert_lt(behind, AIDefensiveVerbs.COVER_GOAL_SIDE_TOLERANCE_M,
			"inside the house gate his nearest defender fell %.2f m behind him" % behind)

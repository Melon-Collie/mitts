extends GutTest

# AIDefencePairing: who of a defence rides which attacker in a possession read.

const GOAL := Vector3(0, 0, -26.65)


func _pair(defenders: Array[Vector3], attackers: Array[Vector3],
		holder: Vector3) -> AIDefencePairing:
	var vels: Array[Vector3] = []
	for _d: Vector3 in defenders:
		vels.append(Vector3.ZERO)
	var avels: Array[Vector3] = []
	for _a: Vector3 in attackers:
		avels.append(Vector3.ZERO)
	var p := AIDefencePairing.new()
	p.pair(GOAL, defenders, vels, [], attackers, avels, holder)
	return p


func test_a_lone_defender_plays_the_holder() -> void:
	var p := _pair([Vector3(0, 0, -12)], [Vector3(6, 0, -2)], Vector3(0, 0, 0))
	assert_false(p.rides(0), "the one defender is on the puck, not the winger")


func test_a_three_on_two_leaves_one_man_open() -> void:
	var p := _pair([Vector3(-3, 0, -12), Vector3(3, 0, -12)],
			[Vector3(-7, 0, -2), Vector3(7, 0, -2)], Vector3(0, 0, 0))
	var riding: int = int(p.rides(0)) + int(p.rides(1))
	assert_eq(riding, 1, "one defender plays the puck, one takes a winger")


func test_even_numbers_cover_every_man() -> void:
	var p := _pair([Vector3(-6, 0, -12), Vector3(0, 0, -14), Vector3(6, 0, -12)],
			[Vector3(-7, 0, -2), Vector3(7, 0, -2)], Vector3(0, 0, 0))
	assert_false(p.rides(1), "the middle man, nearest the holder's line, plays the puck")
	assert_eq(p.ride[0], 0, "the left defender takes the left winger")
	assert_eq(p.ride[2], 1, "the right defender takes the right winger")


func test_a_trailer_behind_the_puck_draws_nobody() -> void:
	var p := _pair([Vector3(-3, 0, -12), Vector3(3, 0, -12)],
			[Vector3(0, 0, 6)], Vector3(0, 0, 0))
	assert_false(p.rides(0) or p.rides(1), "a man behind the puck is nobody's to ride")


func test_nobody_holding_pairs_every_man() -> void:
	var p := _pair([Vector3(-3, 0, -12), Vector3(3, 0, -12)],
			[Vector3(-4, 0, -6), Vector3(4, 0, 6)], Vector3.INF)
	assert_true(p.rides(0) and p.rides(1), "a loose puck leaves every man to cover")


func test_the_pairing_follows_places_not_list_order() -> void:
	var a: Array[Vector3] = [Vector3(-7, 0, -2), Vector3(7, 0, -2)]
	var p1 := _pair([Vector3(-3, 0, -12), Vector3(3, 0, -12)], a, Vector3(0, 0, 0))
	var p2 := _pair([Vector3(3, 0, -12), Vector3(-3, 0, -12)], a, Vector3(0, 0, 0))
	assert_eq(p1.ride[0], p2.ride[1], "the left defender's job does not move with the order")
	assert_eq(p1.ride[1], p2.ride[0], "nor the right one's")


func test_a_rider_ends_goal_side_of_his_man() -> void:
	var p := _pair([Vector3(-6, 0, -12), Vector3(0, 0, -14), Vector3(6, 0, -12)],
			[Vector3(-7, 0, -2), Vector3(7, 0, -2)], Vector3(0, 0, 0))
	var at: Vector3 = p.ride_at(0, 4.0)
	assert_lt(at.z, -2.0, "goal-side of the winger he rides")
	assert_lt(at.distance_to(Vector3(-7, 0, -2)), AIBotMechanics.BLADE_REACH_M + 0.01,
			"within a stick of him")

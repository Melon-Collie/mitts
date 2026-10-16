extends GutTest

# AIPossessionValue — what the puck at a spot is worth to the side attacking a
# net, in the shot field's odds: the shot or a drive in the zone, the best entry
# outside it, each raced against the defence.

const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)

var _none: Array[Vector3] = []


func _read(defenders: Array[Vector3], goal: Vector3 = GOAL) -> AIPossessionValue:
	var v := AIPossessionValue.new()
	var vels: Array[Vector3] = []
	for _d: Vector3 in defenders:
		vels.append(Vector3.ZERO)
	v.fill(goal, defenders, vels, [])
	return v


func test_in_the_zone_it_is_at_least_the_shot() -> void:
	var v: AIPossessionValue = _read(_none)
	for spot: Vector3 in [Vector3(0, 0, -18), Vector3(-6, 0, -20), Vector3(8, 0, -12)]:
		assert_gte(v.at(spot), AIActionScoring.score_shoot_value(spot, GOAL, Vector3.INF, _none)
				- 1e-6, "%s" % spot)


func test_a_defender_on_the_drive_takes_it() -> void:
	# From the corner the shot is nothing: the spot is worth its drive in.
	var corner := Vector3(-10.0, 0.0, -22.0)
	var open: float = _read(_none).at(corner)
	assert_gt(open, 0.0, "an open drive from the corner is worth something")
	var home: Array[Vector3] = [Vector3(-4.5, 0.0, -24.4)]
	assert_lt(_read(home).at(corner), open, "a defender home first takes it away")


func test_closer_to_the_zone_is_worth_more() -> void:
	var v: AIPossessionValue = _read(_none)
	var prev: float = 0.0
	for z: float in [20.0, 10.0, 0.0, -5.0]:
		var here: float = v.at(Vector3(0.0, 0.0, z))
		assert_gt(here, prev, "the middle at z %.0f" % z)
		prev = here


func test_a_defender_who_gets_to_the_entries_first_shuts_them() -> void:
	var spot := Vector3(0.0, 0.0, 5.0)
	var open: float = _read(_none).at(spot)
	var line: Array[Vector3] = [Vector3(-10.0, 0, -9.0), Vector3(0.0, 0, -9.0), Vector3(10.0, 0, -9.0)]
	assert_lt(_read(line).at(spot), open * 0.5, "a defence standing up at its line")


func test_later_is_worth_less() -> void:
	var v: AIPossessionValue = _read(_none)
	var spot := Vector3(4.0, 0.0, -16.0)
	assert_lt(v.at(spot, 1.0), v.at(spot))


func test_both_ends_read_alike() -> void:
	var d: Array[Vector3] = [Vector3(3.0, 0, -10.0), Vector3(-5.0, 0, -18.0)]
	var mirrored: Array[Vector3] = [Vector3(-3.0, 0, 10.0), Vector3(5.0, 0, 18.0)]
	var ours: AIPossessionValue = _read(d)
	var theirs: AIPossessionValue = _read(mirrored, -GOAL)
	for spot: Vector3 in [Vector3(-8, 0, -20), Vector3(2, 0, 4), Vector3(9, 0, 15)]:
		assert_almost_eq(theirs.at(Vector3(-spot.x, 0.0, -spot.z)), ours.at(spot), 1e-4,
				"%s" % spot)

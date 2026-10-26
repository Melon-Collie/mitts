extends GutTest

# AIRimPass — the rim's path half: which launches are rims, where each goes,
# and who reaches it first. Team 0 defends +Z.

const OUR_GOAL_Z: float = 26.65
const PACE: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
var NONE: Array[Vector3] = []
var NO_CAPS: Array[AISkaterCaps] = []


func _build(from: Vector3, opps: Array[Vector3] = []) -> int:
	var vels: Array[Vector3] = []
	for _o: Vector3 in opps:
		vels.append(Vector3.ZERO)
	return AIRimPass.build(from, PACE, OUR_GOAL_Z, opps, vels, NO_CAPS)


func test_no_rims_from_centre_ice() -> void:
	assert_eq(_build(Vector3(0.0, 0.0, 0.0)), 0, "nowhere near the boards")


func test_a_corner_rim_runs_up_the_wall() -> void:
	# From behind our own net, out toward the strong corner: some launch must
	# come round the corner and run up the boards past the hash marks.
	var n: int = _build(Vector3(3.0, 0.0, 28.0))
	assert_gt(n, 0)
	var up_the_wall: bool = false
	for k: int in n:
		var path: Array[Vector3] = AIRimPass.paths[k]
		for p: Vector3 in path:
			if absf(p.x) > 10.5 and p.z < 18.0:
				up_the_wall = true
	assert_true(up_the_wall, "a rim is carried up the side wall by the boards")


func test_no_rim_leg_runs_through_a_net() -> void:
	var n: int = _build(Vector3(-2.0, 0.0, 28.5))
	for k: int in n:
		var path: Array[Vector3] = AIRimPass.paths[k]
		var prev: Vector3 = AIRimPass.origin
		for p: Vector3 in path:
			assert_false(AINetObstacle.pass_lane_blocked_by_net(prev, p),
					"launch %d crosses the cage" % k)
			prev = p


func test_a_defender_on_the_wall_wins_the_race() -> void:
	var from := Vector3(3.0, 0.0, 28.0)
	var clear: int = _build(from)
	var clear_t: Array[float] = []
	for k: int in clear:
		clear_t.append(AIRimPass.opp_time(k))
	var on_wall: Array[Vector3] = [Vector3(12.0, 0.0, 20.0)]
	var n: int = _build(from, on_wall)
	assert_eq(n, clear)
	var beaten: int = 0
	for k: int in n:
		assert_eq(clear_t[k], INF, "nobody races an empty rink")
		if AIRimPass.opp_time(k) < INF:
			beaten += 1
	assert_gt(beaten, 0, "the man on the wall reaches the rims up it")


func test_a_receiver_up_the_wall_meets_the_rim() -> void:
	var n: int = _build(Vector3(3.0, 0.0, 28.0))
	var best_t: float = INF
	for k: int in n:
		best_t = minf(best_t, AIRimPass.meet_time(k, Vector3(11.5, 0.0, 14.0),
				Vector3.ZERO, null))
	assert_lt(best_t, INF, "the half-wall winger can meet a rim")


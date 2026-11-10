extends GutTest

# AIStickPathRead: where the pressurer's blade goes so the carried puck has to
# come through it. World XZ; the defender at the origin unless a test says not.

const REACH: float = 2.0
const BLADE_SPEED: float = 8.0


func test_a_puck_in_reach_under_the_blade_is_played_where_it_is() -> void:
	var puck := Vector3(1.0, 0.0, 0.5)
	var p: Vector3 = AIStickPathRead.path_point(Vector3.ZERO, Vector3.ZERO, puck,
			puck, Vector3.ZERO, REACH, BLADE_SPEED)
	assert_almost_eq(p.distance_to(puck), 0.0, 1e-4)


func test_a_carrier_skating_past_is_met_ahead_of_the_puck() -> void:
	# He crosses in front of me at 6 m/s, the puck a metre outside my reach.
	var puck := Vector3(-3.0, 0.0, 1.5)
	var vel := Vector3(6.0, 0.0, 0.0)
	var p: Vector3 = AIStickPathRead.path_point(Vector3.ZERO, Vector3.ZERO,
			Vector3(0.0, 0.0, 1.0), puck, vel, REACH, BLADE_SPEED)
	assert_true(p.is_finite(), "his path comes into my reach")
	assert_gt(p.x, puck.x, "the blade goes down his path, ahead of the puck")
	assert_lte(Vector2(p.x, p.z).length(), REACH + 1e-3, "inside my reach when he gets there")
	# The puck gets there no sooner than the blade does.
	var t_puck: float = (p.x - puck.x) / vel.x
	var t_blade: float = (p - Vector3(0.0, 0.0, 1.0)).length() / BLADE_SPEED
	assert_lte(t_blade - GameRules.POKE_RADIUS_M / BLADE_SPEED, t_puck + AIStickPathRead.PATH_STEP_S)


func test_a_slower_blade_meets_the_path_further_down_it() -> void:
	var puck := Vector3(-3.0, 0.0, 1.5)
	var vel := Vector3(6.0, 0.0, 0.0)
	var blade := Vector3(0.0, 0.0, -1.5)
	var fast: Vector3 = AIStickPathRead.path_point(Vector3.ZERO, Vector3.ZERO, blade, puck,
			vel, REACH, BLADE_SPEED)
	var slow: Vector3 = AIStickPathRead.path_point(Vector3.ZERO, Vector3.ZERO, blade, puck,
			vel, REACH, BLADE_SPEED * 0.5)
	assert_true(fast.is_finite() and slow.is_finite())
	assert_gte(slow.x, fast.x)


func test_a_path_that_never_comes_into_reach_is_not_played() -> void:
	var p: Vector3 = AIStickPathRead.path_point(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
			Vector3(-5.0, 0.0, 4.0), Vector3(6.0, 0.0, 0.0), REACH, BLADE_SPEED)
	assert_false(p.is_finite())


func test_a_carrier_skating_away_is_not_played() -> void:
	var p: Vector3 = AIStickPathRead.path_point(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
			Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 6.0), REACH, BLADE_SPEED)
	assert_false(p.is_finite())


func test_our_own_skating_brings_the_path_into_reach() -> void:
	# Standing still the path stays out of reach; skating at it, it comes in.
	var puck := Vector3(-4.0, 0.0, 3.2)
	var vel := Vector3(5.0, 0.0, 0.0)
	assert_false(AIStickPathRead.path_point(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, puck,
			vel, REACH, BLADE_SPEED).is_finite())
	assert_true(AIStickPathRead.path_point(Vector3.ZERO, Vector3(0.0, 0.0, 3.0), Vector3.ZERO,
			puck, vel, REACH, BLADE_SPEED).is_finite())


func test_backing_in_the_blade_is_held_out_in_front() -> void:
	# A carrier driving at me while I back in at most of his pace: the blade is
	# held up the ice of my body, toward him, where my skating brings it onto
	# his path as the puck gets there, never on the ice I am leaving.
	var puck := Vector3(0.0, 0.0, 3.4)
	var p: Vector3 = AIStickPathRead.path_point(Vector3.ZERO, Vector3(0.0, 0.0, -7.0),
			Vector3(0.5, 0.0, 0.5), puck, Vector3(0.0, 0.0, -9.0), REACH, BLADE_SPEED)
	assert_true(p.is_finite())
	assert_gt(p.z, 1.0, "out in front of me, toward the puck")
	assert_lte(Vector2(p.x, p.z).length(), REACH + 1e-3, "inside my reach now")


func test_the_lane_is_his_line_to_our_net_where_it_reaches_me() -> void:
	# He is up the ice of me, our net behind me: the lane point is the edge of my
	# reach on his line, the side nearer him.
	var net := Vector3(0.0, 0.0, -10.0)
	var puck := Vector3(1.0, 0.0, 6.0)
	var me := Vector3(0.5, 0.0, 0.0)
	var q: Vector3 = AIStickPathRead.lane_point(me, puck, net, REACH)
	assert_true(q.is_finite())
	assert_almost_eq(Vector2(q.x - me.x, q.z - me.z).length(), REACH, 1e-3, "at the edge of my reach")
	assert_gt(q.z, me.z, "on his side of me")
	var along: float = (q - puck).cross(net - puck).length()
	assert_almost_eq(along, 0.0, 1e-3, "on his line to our net")


func test_a_line_that_passes_out_of_reach_has_no_lane() -> void:
	var q: Vector3 = AIStickPathRead.lane_point(Vector3(6.0, 0.0, 0.0), Vector3(0.0, 0.0, 8.0),
			Vector3(0.0, 0.0, -10.0), REACH)
	assert_false(q.is_finite())


func test_a_target_past_the_reach_edge_is_held_on_it() -> void:
	var cfg := FacingRules.Config.new()
	var facing := Vector2(0.0, 1.0)
	var behind := Vector3(0.0, 0.0, -2.0)
	var held: Vector3 = AIStickPathRead.within_reach_edges(Vector3.ZERO, behind, facing, cfg,
			false)
	var angle: float = absf(facing.angle_to(Vector2(held.x, held.z)))
	assert_almost_eq(angle, cfg.forehand_edge_rad, 1e-3, "turned back to the edge")
	assert_almost_eq(Vector2(held.x, held.z).length(), 2.0, 1e-4, "at the same distance")
	var beside := Vector3(2.0, 0.0, 0.0)
	assert_eq(AIStickPathRead.within_reach_edges(Vector3.ZERO, beside, facing, cfg, false), beside,
			"inside the edges it is left alone")

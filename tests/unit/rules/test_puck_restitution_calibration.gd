extends GutTest

# Holds every puck bounce to the measurements PuckRestitution is built from:
#   Haché, The Physics of Hockey — dropped on concrete, a frozen puck rebounds to
#     ~12% of its drop height and a room-temperature one to ~27%.
#   Anderson / Bigford & Smith (WSU 2008; J. ASTM Int. 6(7), 2009) — air cannon
#     into a rigid plate at 55–85 mph: freezing cuts COR by 32%, and COR falls
#     with impact speed.
#   US8696478 (kickplate patent) — a board returning 30–40% of the puck's impact
#     speed is what high-level hockey wants.
# A surface may absorb more than a rigid wall; nothing may return more.

const HACHE_FROZEN_HEIGHT_RATIO: float = 0.12
const HACHE_WARM_HEIGHT_RATIO: float = 0.27
const WSU_FREEZING_COR_LOSS: float = 0.32
const WSU_SLOWEST_M_S: float = 24.6   # 55 mph
const WSU_FASTEST_M_S: float = 38.0   # 85 mph
const PATENT_BAND_LOW: float = 0.30
const PATENT_BAND_HIGH: float = 0.40
const DROP_SPEED_M_S: float = 4.43    # √(2·9.8·1 m)

const SPEEDS: Array[float] = [1.0, 3.0, 6.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 45.0]


func test_a_frozen_drop_bounces_as_high_as_haches() -> void:
	var e: float = PuckRestitution.rigid_wall(DROP_SPEED_M_S)
	assert_almost_eq(e * e, HACHE_FROZEN_HEIGHT_RATIO, 0.01,
			"bounce height ratio is COR²")


func test_freezing_costs_what_wsu_measured() -> void:
	# A second road to the slow anchor: Haché's warm drop, frozen per WSU.
	var warm: float = sqrt(HACHE_WARM_HEIGHT_RATIO)
	var frozen: float = PuckRestitution.rigid_wall(DROP_SPEED_M_S)
	assert_almost_eq(1.0 - frozen / warm, WSU_FREEZING_COR_LOSS, 0.03)


func test_cor_falls_with_impact_speed() -> void:
	var prev: float = INF
	for v: float in SPEEDS:
		var e: float = PuckRestitution.rigid_wall(v)
		assert_true(e <= prev, "COR at %.0f m/s does not rise" % v)
		prev = e
	assert_lt(PuckRestitution.rigid_wall(WSU_FASTEST_M_S),
			PuckRestitution.rigid_wall(WSU_SLOWEST_M_S) + 0.0001)


func test_shot_speed_cor_sits_at_the_frozen_plateau() -> void:
	for v: float in [WSU_SLOWEST_M_S, 30.0, WSU_FASTEST_M_S]:
		var e: float = PuckRestitution.rigid_wall(v)
		assert_between(e, 0.26, 0.29, "frozen COR at %.1f m/s" % v)


func test_a_square_board_hit_rebounds_at_the_rigid_wall_cor() -> void:
	var dt: float = 1.0 / 120.0
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	for v: float in SPEEDS:
		var pos := Vector3(GameRules.INNER_HALF_WIDTH - r - 0.001,
				AITrajectory.PUCK_REST_HEIGHT_M, 0.0)
		var out: Transform3D = AITrajectory.step_puck(pos, Vector3(v, 0.0, 0.0), dt)
		# Ice friction takes its decel·dt off the rebound in the same step.
		var expected: float = -v * PuckRestitution.rigid_wall(v) \
				+ GameRules.PUCK_ICE_DECEL_M_S2 * dt
		assert_almost_eq(out.basis.x.x, expected, 0.001, "square hit at %.0f m/s" % v)


func test_the_boards_return_what_the_kickplate_patent_asks() -> void:
	# The patent's band is a design target, so hold the rink to it where a rink
	# is designed for it — passes, rims, dump-ins — and never above it.
	for v: float in SPEEDS:
		var e: float = GameRules.PUCK_BOARD_COR_SCALE * PuckRestitution.rigid_wall(v)
		assert_true(e <= PATENT_BAND_HIGH, "no livelier than the band at %.0f m/s" % v)
		if v <= 20.0:
			assert_true(e >= PATENT_BAND_LOW, "no deader than the band at %.0f m/s" % v)


func test_the_post_rebounds_like_a_rigid_wall() -> void:
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	for v: float in [5.0, 15.0, 25.0, 35.0]:
		var pos := Vector3(GameRules.NET_HALF_WIDTH, 0.0175, GameRules.GOAL_LINE_Z - 0.09)
		var res := PuckGeometryCollision.Result.new()
		assert_true(PuckGeometryCollision.resolve_posts(pos, Vector3(0.0, 0.0, v), r, res))
		assert_almost_eq(res.velocity.z, -v * PuckRestitution.rigid_wall(v), 0.001,
				"post at %.0f m/s" % v)


func test_no_goalie_surface_is_livelier_than_a_rigid_wall() -> void:
	var face := Vector3(0.0, 0.0, 1.0)
	for part: int in GoalieSaveRules.SavePart.size():
		for v: float in SPEEDS:
			var out: Vector3 = GoalieSaveRules.rebound_velocity(
					Vector3(0.0, 0.0, -v), part, face)
			assert_true(out.length() <= v * PuckRestitution.rigid_wall(v) + 0.0001,
					"part %d at %.0f m/s" % [part, v])

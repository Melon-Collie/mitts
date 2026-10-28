extends GutTest

# AIActionScoring is pure-function. Tests cover the obvious geometric
# cases and the boundary conditions on shot geometry / pressure / lane.

const NET_HW: float = 0.915
# Goal at +Z for these tests; shooter shoots toward +Z, goalie sits in front.
const GOAL := Vector3(0.0, 0.0, 26.65)


func test_shoot_score_falls_off_with_pressure() -> void:
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var clear: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, [])
	# Defender one stick from the RELEASE POINT (the puck a carry-handle
	# toward the net): his blade genuinely contests the windup
	# (release_contest_clean). Off the shot lane laterally so lane_clear
	# stays ~1.0 — this tests release duress in isolation.
	var nearby_opp: Array[Vector3] = [Vector3(1.2, 0.0, 22.4)]
	var pressured: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, nearby_opp)
	assert_lt(pressured, clear, "a blade within reach of the release contests the shot")


func test_shoot_score_ignores_defender_beyond_blade_reach() -> void:
	# The old density curve penalized any body within 4 m of the shooter's
	# forward cone. Physically, a defender ~3 m away cannot touch a ~135 ms
	# release — only a blade that can reach the puck during the windup
	# contests it. He's also kept off the shot lane so lane_clear is 1.0.
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var clear: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, [])
	var watcher: Array[Vector3] = [Vector3(2.8, 0.0, 22.5)]
	var watched: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, watcher)
	assert_almost_eq(watched, clear, 0.001,
			"a body near-but-out-of-reach does not contest the release")


func test_shoot_score_reduced_by_mid_lane_defender() -> void:
	# Defender mid-segment with reaction time blocks the shot. New
	# lane physics: defender's t along the segment matters — a
	# defender right next to the shooter (low t) doesn't have time
	# to position their stick into a 30 m/s puck path. Use a longer
	# shot so the mid-lane defender lands well past the reaction
	# threshold.
	var shooter := Vector3(0.0, 0.0, 15.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var clear: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, [])
	# Defender at z=20, 5 m from shooter along an ~11 m segment —
	# t ≈ 0.43, time_to_defender ≈ 0.16 s > LANE_REACTION_DELAY_S
	# (0.08), so they have time to position their stick.
	var blocker: Array[Vector3] = [Vector3(-0.1, 0.0, 20.0)]
	var blocked: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, blocker)
	assert_gt(clear, 0.0)
	assert_lt(blocked, clear, "defender in shot lane with reaction time should reduce shoot score")


func test_shot_lane_defender_reach_scales_with_build() -> void:
	# A defender partially in the shot lane. A longer-reach, faster
	# defender blocks more of a shot; a short, slow one blocks less. Empty caps sits
	# at the league default between them. (Goalie offset so the open-net aim runs to
	# a predictable side that the defender contests.)
	var shooter := Vector3(0, 0, 15)
	var goalie := Vector3(1.0, 0, 26)
	var off_lane: Array[Vector3] = [Vector3(0.9, 0, 20)]
	var league: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, off_lane)
	var big := AISkaterCaps.new()
	big.stick_reach = 1.7
	big.max_speed = 12.0
	var vs_big: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, off_lane, 0.0, AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, [big])
	var small := AISkaterCaps.new()
	small.stick_reach = 1.0
	small.max_speed = 6.0
	var vs_small: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, off_lane, 0.0, AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, [small])
	assert_lt(vs_big, league, "a longer-reach, faster defender blocks more of the shot")
	assert_gt(vs_small, league, "a shorter, slower defender blocks less")


func test_shoot_blocked_by_close_on_line_defender() -> void:
	# Lane physics: a defender 2 m in front of the shooter, dead on the
	# shot line, is a shot-blocker — the puck's path runs straight through
	# the space their stick already occupies, so it blocks even on a fast
	# slapper. (The old reaction-window model wrongly let the puck "blow
	# past" an unreacting low-t defender; the reachability model doesn't —
	# they don't need to react, they're already there.)
	var shooter := Vector3(0.0, 0.0, 15.0)
	var aim := Vector3(0.0, 0.0, 26.65)
	var slapper := GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S
	var clear: float = AIPuckLane.lane_clear(shooter, aim, [], slapper)
	var close_blocker: Array[Vector3] = [Vector3(-0.1, 0.0, 17.0)]
	var blocked: float = AIPuckLane.lane_clear(shooter, aim, close_blocker, slapper)
	assert_almost_eq(clear, 1.0, 0.0001, "sanity: the empty lane is clear")
	assert_lt(blocked, 0.1, "a defender dead on the close shot line blocks the shot")


func test_shoot_score_unaffected_by_defender_off_lane() -> void:
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var clear: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, [])
	# Defender to the far side, outside both pressure radius and shot lane.
	var off_lane: Array[Vector3] = [Vector3(8.0, 0.0, 24.0)]
	var s: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, off_lane)
	assert_almost_eq(s, clear, 0.001)


func test_pass_score_zero_when_lane_blocked() -> void:
	var shooter := Vector3(0.0, 0.0, 10.0)
	var receiver := Vector3(0.0, 0.0, 22.0)  # close to goal, would normally score
	var goalie := Vector3(0.5, 0.0, 26.0)
	var blocker: Array[Vector3] = [Vector3(0.0, 0.0, 16.0)]  # right on the line
	var s: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, blocker)
	assert_eq(s, 0.0, "opponent on the pass line should zero the score")


func test_pass_lane_only_counts_opponents_between_endpoints() -> void:
	var shooter := Vector3(0.0, 0.0, 10.0)
	var receiver := Vector3(0.0, 0.0, 22.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	# Opponent BEHIND the shooter (z=5, before z=10) — shouldn't block
	var behind: Array[Vector3] = [Vector3(0.0, 0.0, 5.0)]
	var s: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, behind)
	assert_gt(s, 0.0, "opponent behind the shooter shouldn't block the lane")


func test_shoot_score_zero_from_behind_goal_line() -> void:
	# GOAL.z = +26.65; shooter past it (z=27) is behind the net.
	var shooter := Vector3(0.0, 0.0, 27.0)
	var goalie := Vector3(0.0, 0.0, 26.0)
	var s: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, [])
	assert_eq(s, 0.0, "shot from behind goal line should score 0")


func test_shoot_score_zero_from_behind_net_off_center() -> void:
	# The bug that had bots firing from behind the net: an OFF-CENTER
	# behind-the-line shooter used to be clamped to a phantom point-blank release
	# beside the goalie (release_ahead_of_goalie) and scored a wide-open net
	# (danger 1.0). Behind the line is behind the line — always 0, and the
	# release clamp must not move a behind-the-line release at all.
	var goalie := Vector3(0.0, 0.0, 25.9)
	for x: float in [1.5, 3.0]:
		var shooter := Vector3(x, 0.0, 27.5)
		assert_eq(AIActionScoring.score_shoot_value(shooter, GOAL, goalie, []), 0.0,
				"behind-the-net shot at x=%.1f must score 0" % x)
		assert_eq(AIGoalieModel.release_ahead_of_goalie(shooter, GOAL, goalie), shooter,
				"a behind-the-line release is not clamped into a phantom in-front spot")


func test_pass_score_zero_to_receiver_behind_goal_line() -> void:
	var shooter := Vector3(0.0, 0.0, 20.0)
	var receiver := Vector3(0.0, 0.0, 28.0)  # past attacking goal line
	var goalie := Vector3(0.0, 0.0, 26.0)
	var s: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, [])
	assert_eq(s, 0.0, "pass to receiver behind goal line should score 0")


func test_pass_score_falls_off_with_receiver_pressure() -> void:
	var shooter := Vector3(0.0, 0.0, 10.0)
	var receiver := Vector3(0.0, 0.0, 22.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var clear: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, [])
	# Defender 2 m past the receiver (toward the attacking goal) and
	# 0.5 m off-axis — inside the receiver's forward pressure cone but
	# past the shooter→receiver segment so lane_clear isn't triggered.
	var checker: Array[Vector3] = [Vector3(0.5, 0.0, 24.0)]
	var pressured: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, checker)
	assert_lt(pressured, clear)


# Pressure cube-falloff sanity checks. The directional formula zeros
# opponents behind and beside the play, so shoot/pass scoring no
# longer counts defenders who can't realistically disrupt the action.

func test_shoot_pressure_ignores_defender_behind_shooter() -> void:
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 25.4)
	var clean: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, [])
	# Defender 2 m behind shooter (between shooter and own net).
	var behind: Array[Vector3] = [Vector3(0.5, 0.0, 19.0)]
	var pressured: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, behind)
	assert_almost_eq(pressured, clean, 0.001,
			"defender behind the shooter should not pressure the shot")


func test_shoot_pressure_ignores_perpendicular_defender() -> void:
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 25.4)
	var clean: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, [])
	# Defender 2 m sideways at the same depth — directly perpendicular
	# to the shooter→goal axis. Cube weight = 0 (dot = 0).
	var perp: Array[Vector3] = [Vector3(2.0, 0.0, 21.0)]
	var pressured: float = AIActionScoring.score_shoot_value(shooter, GOAL, goalie, perp)
	assert_almost_eq(pressured, clean, 0.001,
			"perpendicular defender should not pressure the shot")


func test_pass_trailing_defender_pressures_reception_but_not_the_lane() -> void:
	# A defender just GOAL-side of the receiver: their closest approach to
	# the puck is only AFTER it reaches the receiver, so they're trailing
	# the play and the lane model skips them (no in-flight interception).
	# They DO pressure the reception, though — so the pass value drops via
	# the receiver's shot score, not via the lane. This pins the clean
	# separation the rework draws between in-flight interception (lane) and
	# pressure at reception (receiver value).
	var shooter := Vector3(0.0, 0.0, 10.0)
	var receiver := Vector3(0.0, 0.0, 20.5)
	var goalie := Vector3(0.0, 0.0, 25.4)
	var trailing: Array[Vector3] = [Vector3(1.0, 0.0, 22.0)]
	# Lane itself stays clear — the defender is past the receiver.
	var lane: float = AIPuckLane.lane_clear(
			shooter, receiver, trailing, AIPuckLane.PASS_SPEED_M_S)
	assert_almost_eq(lane, 1.0, 0.0001, "a defender past the receiver isn't a lane interceptor")
	var clean: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, [])
	var pressured: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, trailing)
	assert_lt(pressured, clean, "a defender on the receiver still pressures the reception")


# pass_lane_blocked_by_net coverage. Nets are at z = ±GameRules.GOAL_LINE_Z
# extending out by GameRules.NET_DEPTH; opening half-width NET_HW.

func test_net_blocker_oz_corner_to_corner_through_back_of_net() -> void:
	# Bot in attacking-zone right corner just inside the net depth,
	# teammate mirrored on the left. Pass goes through the net rect.
	var from := Vector3(5.0, 0.0, 27.0)   # inside net z-range
	var to := Vector3(-5.0, 0.0, 27.0)
	assert_true(AINetObstacle.pass_lane_blocked_by_net(from, to),
			"corner-to-corner pass through the back of the net should be blocked")


func test_net_blocker_dz_pass_across_goal_mouth() -> void:
	# Pass crossing in front of the goal at the goal-line z. Just clipping
	# the front face of the net rect.
	var from := Vector3(3.0, 0.0, 28.0)   # behind own net
	var to := Vector3(-3.0, 0.0, 25.0)    # front of own net
	assert_true(AINetObstacle.pass_lane_blocked_by_net(from, to),
			"pass crossing the goal mouth at goal-line z should be blocked by the net")


func test_net_blocker_clean_slot_pass_not_blocked() -> void:
	# Pass through the slot (well in front of the goal line). Both
	# endpoints in front of GOAL_LINE_Z, segment never enters either rect.
	var from := Vector3(5.0, 0.0, 18.0)
	var to := Vector3(-5.0, 0.0, 18.0)
	assert_false(AINetObstacle.pass_lane_blocked_by_net(from, to),
			"slot-line pass nowhere near the net should not be blocked")


func test_net_blocker_low_to_high_pass_not_blocked() -> void:
	# OZ low-to-high: from near the goal line up to the blue line.
	# Segment never enters the rect because x stays inside one corner
	# but z exits the rect cleanly toward NZ.
	var from := Vector3(5.0, 0.0, 25.5)   # in front of goal line, off to side
	var to := Vector3(0.0, 0.0, 12.0)
	assert_false(AINetObstacle.pass_lane_blocked_by_net(from, to),
			"low-to-high OZ pass should not be blocked by the attacking net")


func test_net_blocker_covers_the_outer_frame_not_just_the_posts() -> void:
	# The physical net is WIDER than the goal mouth: the back-frame trapezoid
	# spans NET_BACK_HALF_WIDTH (1.02) and the puck's own radius clanks the
	# frame before its center reaches it. A behind-the-net feed threading just
	# outside the 0.915 post line but inside the frame+puck envelope used to
	# read "clear" and ring off the outside of the cage.
	var graze_x: float = GameRules.NET_HALF_WIDTH + 0.05   # 0.965 — outside posts
	var from := Vector3(graze_x, 0.0, 28.2)                # behind the net
	var to := Vector3(graze_x, 0.0, 20.0)                  # up the slot, same x
	assert_true(AINetObstacle.pass_lane_blocked_by_net(from, to),
			"a lane through the outer frame band is blocked, not just the post span")
	# Clearly wide of frame + puck radius stays clear.
	var wide_x: float = GameRules.NET_BACK_HALF_WIDTH + GameRules.PUCK_COLLISION_RADIUS + 0.05
	assert_false(AINetObstacle.pass_lane_blocked_by_net(
			Vector3(wide_x, 0.0, 28.2), Vector3(wide_x, 0.0, 20.0)),
			"a lane genuinely wide of the physical frame is clear")


func test_score_pass_zero_when_segment_crosses_net() -> void:
	var shooter := Vector3(5.0, 0.0, 27.0)
	var receiver := Vector3(-5.0, 0.0, 27.0)
	var goalie := Vector3(0.0, 0.0, -25.0)
	# Far-side goal so receiver isn't past attacking goal line.
	var attacking_goal := Vector3(0.0, 0.0, -26.65)
	var s: float = AIActionScoring.score_pass_value(shooter, receiver, attacking_goal, goalie, [])
	assert_almost_eq(s, 0.0, 0.001,
			"score_pass returns zero when the segment crosses a net rect")


# pass_crosses_own_slot — own-DZ slot danger filter.

func test_own_slot_pass_blocked_team0() -> void:
	# Cross-crease slot pass for team 0 (own goal at +z=26.65). Segment
	# at z=22 (slot depth) crossing x=0 → blocked.
	var from := Vector3(3.0, 0.0, 22.0)
	var to := Vector3(-3.0, 0.0, 22.0)
	assert_true(AINetObstacle.pass_crosses_own_slot(from, to, GOAL.z))


func test_own_slot_pass_blocked_team1() -> void:
	# Mirror — team 1 (own goal at -z).
	var from := Vector3(3.0, 0.0, -22.0)
	var to := Vector3(-3.0, 0.0, -22.0)
	assert_true(AINetObstacle.pass_crosses_own_slot(from, to, -GOAL.z))


func test_pass_outside_own_slot_not_blocked() -> void:
	# Pass in NZ — well in front of slot rect. Not blocked.
	var from := Vector3(3.0, 0.0, 5.0)
	var to := Vector3(-3.0, 0.0, 5.0)
	assert_false(AINetObstacle.pass_crosses_own_slot(from, to, GOAL.z))


func test_breakout_pass_not_blocked() -> void:
	# Pass from corner up-ice (DZ → NZ). Segment doesn't cross the
	# slot rect because z exits the slot range before x enters.
	var from := Vector3(8.0, 0.0, 24.0)   # corner near boards
	var to := Vector3(0.0, 0.0, 5.0)      # mid-NZ
	assert_false(AINetObstacle.pass_crosses_own_slot(from, to, GOAL.z))


func test_own_slot_side_of_crease_feed_blocked() -> void:
	# A centering feed hugging the flank of the crease — x ≈ 2.2–2.6, a stick
	# outside the post but squarely in the home-plate high-danger area. This
	# slipped the old ±2.0 rect (x never entered [-2, 2]) and became a
	# goal-against; the widened ±2.75 rect vetoes it as the giveaway it is.
	var from := Vector3(2.6, 0.0, 26.0)
	var to := Vector3(2.2, 0.0, 21.0)
	assert_true(AINetObstacle.pass_crosses_own_slot(from, to, GOAL.z))


# ── Zone predicates ──────────────────────────────────────────────────────────

func test_in_offensive_zone_past_blue_line() -> void:
	var deep := Vector3(0.0, 0.0, 20.0)          # well inside the zone
	var just_in := Vector3(0.0, 0.0, GameRules.BLUE_LINE_Z + 0.5)
	assert_true(AIActionScoring.in_offensive_zone(deep, GOAL))
	assert_true(AIActionScoring.in_offensive_zone(just_in, GOAL))


func test_not_in_offensive_zone_at_or_before_blue_line() -> void:
	var just_out := Vector3(0.0, 0.0, GameRules.BLUE_LINE_Z - 0.5)
	var nz := Vector3(0.0, 0.0, 0.0)
	var own_end := Vector3(0.0, 0.0, -20.0)
	assert_false(AIActionScoring.in_offensive_zone(just_out, GOAL))
	assert_false(AIActionScoring.in_offensive_zone(nz, GOAL))
	assert_false(AIActionScoring.in_offensive_zone(own_end, GOAL))


func test_in_offensive_zone_folds_for_negative_z_attack() -> void:
	# Attacking toward -Z: the O-zone is z < -BLUE_LINE_Z.
	var neg_goal := Vector3(0.0, 0.0, -26.65)
	assert_true(AIActionScoring.in_offensive_zone(Vector3(0, 0, -20.0), neg_goal))
	assert_false(AIActionScoring.in_offensive_zone(Vector3(0, 0, -5.0), neg_goal))
	assert_false(AIActionScoring.in_offensive_zone(Vector3(0, 0, 20.0), neg_goal))


# ── release_ahead_of_goalie / no phantom open net ─────────────────────────────
# GOAL is at +Z, so "in front of the goalie" = farther out = smaller z.

func test_release_clamped_when_behind_goalie() -> void:
	var goalie := Vector3(0.0, 0.0, 24.65)          # 2 m out from GOAL (z 26.65)
	var behind := Vector3(0.5, 0.0, 25.5)           # in the crease, past the goalie
	var clamped: Vector3 = AIGoalieModel.release_ahead_of_goalie(behind, GOAL, goalie)
	assert_almost_eq(clamped.z, 24.65 - AIGoalieModel.GOALIE_JAM_DISTANCE_M, 1e-4,
			"pushed out to the jam distance in front of the goalie")
	assert_almost_eq(clamped.x, 0.5, 1e-6, "lateral offset is untouched")


func test_release_untouched_when_in_front_of_goalie() -> void:
	var goalie := Vector3(0.0, 0.0, 24.65)
	var in_front := Vector3(1.0, 0.0, 20.0)         # out in the slot, well in front
	var out: Vector3 = AIGoalieModel.release_ahead_of_goalie(in_front, GOAL, goalie)
	assert_eq(out, in_front, "a normal in-front shot is not clamped")


func test_shot_quality_is_the_seams_goalie_half() -> void:
	# A caller that memoizes shot_quality and hands it back reads exactly what
	# the seam computes itself, for every keeper the seam takes.
	var defenders: Array[Vector3] = [Vector3(1.0, 0.0, 20.0), Vector3(-3.0, 0.0, 18.0)]
	var keepers: Array[Vector3] = [Vector3.INF, Vector3(0.4, 0.0, 25.9),
			Vector3(-1.5, 0.0, 24.5)]
	for spot: Vector3 in [Vector3(0, 0, 18), Vector3(-7, 0, 21), Vector3(9, 0, 12),
			Vector3(2, 0, 24.5)]:
		for keeper: Vector3 in keepers:
			for stance: int in [AIShotOdds.Stance.UPRIGHT, AIShotOdds.Stance.DOWN]:
				var whole: float = AIActionScoring.score_shoot_value(spot, GOAL, keeper,
						defenders, 0.6, stance)
				var halves: float = AIActionScoring.score_shoot_value(spot, GOAL, keeper,
						defenders, 0.6, stance, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, [],
						AIActionScoring.shot_quality(spot, GOAL, keeper, 0.6, stance))
				assert_almost_eq(halves, whole, 1e-9, "%s vs keeper %s" % [spot, keeper])


func test_delay_discount_bounds_patience() -> void:
	# The delay discount is constant-hazard survival, exp(-t / READ_VALIDITY_TAU_S):
	# 1 at t=0, strictly decreasing. The UPPER-BOUND guard the value sweep was
	# missing — patience must stay bounded, so a multi-second play is meaningfully
	# discounted and τ can't be cranked toward "the future is free" (dithering).
	assert_almost_eq(AIActionScoring.delay_discount(0.0), 1.0, 0.0001,
			"no delay, no discount")
	assert_lt(AIActionScoring.delay_discount(1.0), 1.0, "a future play is worth less")
	assert_lt(AIActionScoring.delay_discount(2.0), AIActionScoring.delay_discount(1.0),
			"further out is worth strictly less")
	assert_lt(AIActionScoring.delay_discount(3.0), 0.62,
			"a 3 s-out play is substantially discounted — patience stays bounded")
	# Sanity: the geometric identity the per-second reading rests on — the
	# discount over 2 s equals the 1 s discount squared.
	assert_almost_eq(AIActionScoring.delay_discount(2.0),
			AIActionScoring.delay_discount(1.0) * AIActionScoring.delay_discount(1.0),
			0.0001, "constant-hazard: memoryless, so it compounds geometrically")


# ── The loose-puck race ──────────────────────────────────────────────────────

# Our first man to `target` against theirs.
func _race(target: Vector3, ours: Array[Vector3], theirs: Array[Vector3],
		our_vels: Array[Vector3] = [], their_vels: Array[Vector3] = []) -> float:
	return AIActionScoring.arrival_race(target,
			AIActionScoring.first_arrival(target, ours, our_vels), theirs, their_vels)


func test_the_loose_puck_race() -> void:
	var target := Vector3(10, 0, 20)
	# No chaser of ours → we never get it; no opponent → uncontested.
	assert_eq(_race(target, [] as Array[Vector3], [Vector3(9, 0, 20)] as Array[Vector3]), 0.0)
	assert_eq(_race(target, [Vector3(9, 0, 20)] as Array[Vector3], [] as Array[Vector3]), 1.0)
	# Dead tie → coin flip.
	var tie: float = _race(target, [Vector3(7, 0, 20)] as Array[Vector3],
			[Vector3(13, 0, 20)] as Array[Vector3])   # both 3 m out
	assert_almost_eq(tie, 0.5, 1e-6)
	# We're a full contest-margin closer → near-certain.
	var ours: Array[Vector3] = [Vector3(10, 0, 20)]              # 0 m
	var theirs: Array[Vector3] = [Vector3(10, 0, 24)]           # 4 m = 2× margin
	assert_gt(_race(target, ours, theirs), 0.99)
	# They're closer → near-zero.
	assert_lt(_race(target, theirs, ours), 0.01)


func test_the_loose_puck_race_runs_on_arrivals_not_metres() -> void:
	# The race is won by whoever GETS there, which is not whoever is nearest: a
	# body 2 m closer but skating the other way has to shed its speed, turn, and
	# come back. Distance alone cannot see that.
	var target := Vector3(0, 0, 0)
	# Ours is FARTHER but already flying at the spot; theirs is nearer and leaving.
	var ours: Array[Vector3] = [Vector3(0, 0, 12)]
	var our_vels: Array[Vector3] = [Vector3(0, 0, -9)]
	var theirs: Array[Vector3] = [Vector3(0, 0, -10)]
	var their_vels: Array[Vector3] = [Vector3(0, 0, -9)]
	# On metres alone this is a race we lose outright (10 m vs 12 m — a
	# cruise-pace gap of exactly the contest band, so 0 to rounding).
	assert_almost_eq(_race(target, ours, theirs), 0.0, 1e-9,
			"the distance read hands it to the nearer body")
	assert_gt(_race(target, ours, theirs, our_vels, their_vels), 0.99,
			"...but we arrive first, so the arrival race gives it to us")
	# Symmetric: the same two bodies with the momentum swapped flips it back.
	assert_lt(_race(target, theirs, ours, their_vels, our_vels), 0.01)


func test_the_loose_puck_race_without_velocities_runs_from_rest() -> void:
	# Callers holding no velocities still get a real ramp rather than an instant
	# full-speed sprint, and the contest band is a stride:
	# CHASE_CONTEST_MARGIN_S is that stride's duration at reference pace.
	var target := Vector3(0, 0, 0)
	assert_almost_eq(_race(target, [Vector3(0, 0, 4)] as Array[Vector3],
			[Vector3(0, 0, 4)] as Array[Vector3]), 0.5, 1e-6,
			"equal standing starts are a coin flip")
	assert_almost_eq(
			AIActionScoring.CHASE_CONTEST_MARGIN_S
					* AIArrival.SKATER_REF_SPEED_M_S,
			AIActionScoring.CHASE_CONTEST_MARGIN_M, 1e-6,
			"the time band is the stride band at reference pace")


# ── time_to_arrive ───────────────────────────────────────────────────────────

func test_time_to_arrive_zero_at_destination() -> void:
	var p := Vector3(5.0, 0.0, 5.0)
	assert_almost_eq(
			AIArrival.time_to_arrive(p, p, Vector3.ZERO),
			0.0, 0.0001)


func test_time_to_arrive_charges_the_standing_start_ramp() -> void:
	# Stationary skater 10 m from dest: the calibrated phase model charges
	# the stride's real ramp before the cruise — a standing start is
	# genuinely slower than dist / top_speed. Exact phase math: constant
	# accel to the power knee, constant power to v_max, then cruise.
	var from := Vector3(0.0, 0.0, 0.0)
	var dest := Vector3(10.0, 0.0, 0.0)
	var t: float = AIArrival.time_to_arrive(from, dest, Vector3.ZERO)
	var vmax: float = AIArrival.SKATER_REF_SPEED_M_S
	var a: float = AIArrival.SHED_ACCEL_DEFAULT_M_S2 \
			* AIStrideRamp.EFFICIENCY
	var knee: float = GameRules.DEFAULT_SKATER_POWER_KNEE_M_S
	var p: float = a * knee
	var d_a: float = knee * knee / (2.0 * a)
	var d_b: float = (vmax * vmax * vmax - knee * knee * knee) / (3.0 * p)
	var expected: float = knee / a
	if 10.0 - d_a <= d_b:
		var v_end: float = pow(knee * knee * knee + 3.0 * p * (10.0 - d_a), 1.0 / 3.0)
		expected += (v_end * v_end - knee * knee) / (2.0 * p)
	else:
		expected += (vmax * vmax - knee * knee) / (2.0 * p) + (10.0 - d_a - d_b) / vmax
	assert_almost_eq(t, expected, 0.001)
	assert_gt(t, 10.0 / vmax, "the ramp costs real time over the naive cruise")


func test_time_to_arrive_faster_with_momentum_toward_dest() -> void:
	var from := Vector3(0.0, 0.0, 0.0)
	var dest := Vector3(10.0, 0.0, 0.0)
	var stationary: float = AIArrival.time_to_arrive(from, dest, Vector3.ZERO)
	var with_momentum: float = AIArrival.time_to_arrive(
			from, dest, Vector3(AIArrival.SKATER_REF_SPEED_M_S, 0.0, 0.0))
	assert_lt(with_momentum, stationary,
			"velocity component toward dest reduces arrival time")


func test_time_to_arrive_slower_with_momentum_away() -> void:
	var from := Vector3(0.0, 0.0, 0.0)
	var dest := Vector3(10.0, 0.0, 0.0)
	var stationary: float = AIArrival.time_to_arrive(from, dest, Vector3.ZERO)
	var with_momentum: float = AIArrival.time_to_arrive(
			from, dest, Vector3(-5.0, 0.0, 0.0))
	assert_gt(with_momentum, stationary,
			"velocity component away from dest increases arrival time")


func test_time_to_arrive_prices_the_full_reversal() -> void:
	# Skater flying away from the destination: the phase model brakes the
	# retreat out at the measured brake decel, gives back the ground lost
	# while braking, then runs a standing-start pursuit. Finite, large, and
	# monotone in how hard the retreat was.
	var from := Vector3(0.0, 0.0, 0.0)
	var dest := Vector3(10.0, 0.0, 0.0)
	var mild: float = AIArrival.time_to_arrive(
			from, dest, Vector3(-5.0, 0.0, 0.0))
	var extreme: float = AIArrival.time_to_arrive(
			from, dest, Vector3(-50.0, 0.0, 0.0))
	var rest: float = AIArrival.time_to_arrive(from, dest, Vector3.ZERO)
	assert_gt(mild, rest, "a retreat costs more than a standing start")
	assert_gt(extreme, mild, "a harder retreat costs more")
	assert_lt(extreme, 60.0, "and stays finite")


# ─── expected_pass_speed / pass_launch_speed (target-arrival model) ──────

func test_pass_launch_speed_short_feed_hits_the_magnet_pace() -> void:
	# A close feed launches right at the magnet target (friction over a short
	# distance is negligible) — crisp, not the old floaty ~11 m/s touch.
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	assert_almost_eq(AIPuckLane.pass_launch_speed(0.0, maxw),
			AIPuckLane.PASS_TARGET_CLOSING_M_S, 0.001)
	assert_lt(absf(AIPuckLane.pass_launch_speed(2.0, maxw)
			- AIPuckLane.PASS_TARGET_CLOSING_M_S), 0.1,
			"a 2 m feed launches within a whisker of the magnet pace")
	assert_gt(AIPuckLane.PASS_TARGET_CLOSING_M_S, AIPuckLane.PASS_SPEED_M_S,
			"the magnet pace is crisper than the old quick-snap speed")


func test_pass_launch_speed_arrives_at_the_target_after_friction() -> void:
	# The launch is backed out of the target arrival: simulate the puck shedding
	# ice friction over the distance and it lands on the target speed.
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	for d: float in [4.0, 12.0, 26.0]:
		var launch: float = AIPuckLane.pass_launch_speed(d, maxw)
		var arrival: float = sqrt(maxf(
				launch * launch - 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * d, 0.0))
		assert_almost_eq(arrival, AIPuckLane.PASS_TARGET_CLOSING_M_S, 0.001,
				"a %.0f m pass arrives at the magnet pace" % d)


func test_pass_launch_speed_rises_slightly_with_distance() -> void:
	# Longer passes launch a hair harder to cover the extra friction, but the whole
	# spread stays tight around the target (< 1 m/s even at 26 m) — no distance ramp.
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	var near: float = AIPuckLane.pass_launch_speed(4.0, maxw)
	var far: float = AIPuckLane.pass_launch_speed(26.0, maxw)
	assert_gt(far, near, "a longer pass launches marginally harder (more friction)")
	assert_lt(far - AIPuckLane.PASS_TARGET_CLOSING_M_S, 1.0,
			"even a long pass launches within 1 m/s of the magnet target")


func test_pass_launch_speed_clamps_to_passer_max() -> void:
	# A soft-shooting passer (low max wrister) can't reach the magnet pace — the launch
	# clamps to its own ceiling.
	var weak_max: float = 16.0
	assert_almost_eq(AIPuckLane.pass_launch_speed(40.0, weak_max), weak_max, 0.001)


func test_expected_pass_speed_uses_the_target_model() -> void:
	# expected_pass_speed is just pass_launch_speed at the league cap.
	var shooter := Vector3.ZERO
	var far := Vector3(0.0, 0.0, 18.0)
	assert_almost_eq(
			AIPuckLane.expected_pass_speed(shooter, far),
			AIPuckLane.pass_launch_speed(18.0, GameRules.DEFAULT_WRISTER_POWER_MAX_M_S),
			0.001)


func test_pass_speed_scale_defaults_to_unchanged() -> void:
	# The difficulty pace arg defaults to 1.0, so an unscaled call is identical to
	# the two-arg form — the cross-player threat model is untouched by the knob.
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	assert_eq(
			AIPuckLane.pass_launch_speed(18.0, maxw, 1.0),
			AIPuckLane.pass_launch_speed(18.0, maxw))


func test_pass_speed_scale_softens_the_arrival_and_still_delivers() -> void:
	# The pace knob scales the TARGET ARRIVAL pace, and the launch is then solved
	# to deliver that — so an easier bot's puck lands soft instead of landing
	# short. Both halves are asserted because the knob spent its whole life
	# retired at 1.0 for failing the second one.
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	var decel: float = GameRules.PUCK_ICE_DECEL_M_S2
	var dist: float = 12.0

	# Static receiver: the arrival pace backed out of the launch is exactly the
	# scaled target, not merely "lower than before".
	var slowed: float = AIPuckLane.pass_launch_speed(dist, maxw, 0.85)
	var arrival: float = sqrt(slowed * slowed - 2.0 * decel * dist)
	assert_almost_eq(arrival, AIPuckLane.PASS_TARGET_CLOSING_M_S * 0.85, 0.01,
			"the puck arrives at the scaled target closing pace")
	assert_lt(slowed, AIPuckLane.pass_launch_speed(dist, maxw, 1.0),
			"and it is a genuinely slower puck than the full-pace feed")

	# THE REGRESSION GUARD. A receiver streaking away along the pass needs a
	# HARDER launch to close at the target at all. Scaling the finished launch
	# (the retired mechanism) under-delivers that solve and the feed dies behind
	# him; scaling the target keeps the lead intact, just softer.
	var pass_dir := Vector3(1, 0, 0)
	var streak := Vector3(6, 0, 0)
	var lead: float = AIPuckLane.pass_launch_speed(dist, maxw, 0.85, streak, pass_dir)
	var lead_arrival: float = sqrt(lead * lead - 2.0 * decel * dist)
	assert_almost_eq(lead_arrival - streak.x,
			AIPuckLane.PASS_TARGET_CLOSING_M_S * 0.85, 0.01,
			"a streaking receiver still gets the scaled closing pace on his tape")
	assert_gt(lead, slowed,
			"and the lead feed still fires harder than the standing one")


func test_pass_launch_speed_fires_harder_onto_a_streaking_receiver() -> void:
	# Receiver-relative launch (#373): a receiver skating ALONG the pass (onto a
	# lead feed) closes slower on the puck, so the passer fires harder to keep the
	# closing pace. One curling BACK toward the passer closes faster — but the
	# softening is CAPPED at the reception ceiling (PASS_RECEIVE_CEILING): a mild
	# curl-back stays crisp, and only a hard close softens, and only down to what a
	# squared receiver can still catch — never the old min-wrister floater.
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	var dist: float = 15.0
	var pass_dir := Vector3(1, 0, 0)
	var static_launch: float = AIPuckLane.pass_launch_speed(dist, maxw)
	var streaking: float = AIPuckLane.pass_launch_speed(
			dist, maxw, 1.0, Vector3(6, 0, 0), pass_dir)
	var mild_curl: float = AIPuckLane.pass_launch_speed(
			dist, maxw, 1.0, Vector3(-6, 0, 0), pass_dir)
	var hard_curl: float = AIPuckLane.pass_launch_speed(
			dist, maxw, 1.0, Vector3(-9, 0, 0), pass_dir)
	assert_gt(streaking, static_launch,
			"fire harder onto a receiver skating away along the pass")
	assert_almost_eq(mild_curl, static_launch, 0.01,
			"a mild curl-back stays crisp — softening is capped at the catch ceiling")
	assert_lt(hard_curl, static_launch,
			"a hard curl-back still softens to stay catchable")
	assert_gt(hard_curl, AIPuckLane.SOFTEST_FEED_M_S + 5.0,
			"but only to the reception ceiling, not collapsed to the soft floater")


func test_pass_launch_speed_lands_at_target_closing_in_receiver_frame() -> void:
	# The whole point: after friction, the puck's speed in the receiver's frame is
	# the magnet CLOSING pace regardless of the receiver's (along + lateral) motion.
	var maxw: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
	var dist: float = 12.0
	var pass_dir := Vector3(1, 0, 0)
	var rvel := Vector3(5, 0, 3)   # along + lateral, both under the target
	var launch: float = AIPuckLane.pass_launch_speed(dist, maxw, 1.0, rvel, pass_dir)
	# Reconstruct the world arrival velocity after shedding friction over the pass.
	var arrival_world: float = sqrt(maxf(
			launch * launch - 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * dist, 0.0))
	var closing: float = (pass_dir * arrival_world - rvel).length()
	assert_almost_eq(closing, AIPuckLane.PASS_TARGET_CLOSING_M_S, 0.1,
			"the puck lands at the target closing speed in the receiver's frame")


# ─── score_pass: speed-aware lane clearance ─────────────────────────────

func test_score_pass_higher_at_charged_speed_with_in_lane_defender() -> void:
	# Same defender on the same pass line. At quick-shot speed (14 m/s)
	# the defender has more time to react and step toward the line,
	# producing a lower lane-clear (and a lower pass score). At
	# charged speed (~19 m/s) the puck arrives sooner, defender
	# contributes less, score is higher.
	#
	# Defender geometry has to put time-to-defender INSIDE the
	# LANE_REACTION_DELAY_S..+RAMP_S band (0.08..0.18s) at both
	# speeds, otherwise reaction_factor clamps and the two scores
	# match. With a 15 m pass and defender at z=2.5 (parameter
	# t=0.167): slow flight=1.07s, t*flight=0.18s (top of ramp);
	# fast flight=0.79s, t*flight=0.13s (mid ramp). Both inside,
	# slow reaction stronger → slow score lower.
	var shooter := Vector3.ZERO
	var receiver := Vector3(0.0, 0.0, 15.0)
	# Goalie offset half a metre so the receiver's look stays a real (nonzero)
	# window — a dead-centred set keeper reads 0 from 11.65 m under the
	# body-occlusion model and both pass speeds would tie at 0.
	var goalie := Vector3(0.5, 0.0, GOAL.z - 1.0)
	var in_lane: Array[Vector3] = [Vector3(0.5, 0.0, 2.5)]
	var slow: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, in_lane, AIPuckLane.PASS_SPEED_M_S)
	var fast: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, in_lane, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	assert_gt(fast, slow,
			"charged pass scores higher than quick-shot when a defender sits in the lane (less reaction time)")


# ── lane_clear: closest-approach reachability model (now public) ─────────────
# The carrier's pass scoring uses this directly. Covered invariants: a
# defender who can get a stick onto the puck's path cuts the clearance; a
# defender already ON the path blocks even when sitting right at the
# release (the old reaction-window product zeroed these — the breakout
# turnover bug); a faster puck threads better (less time to close); and a
# defender bearing down on the lane (velocity-aware) blocks more than the
# same defender standing still.

func test_lane_clear_full_with_no_defenders() -> void:
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var s: float = AIPuckLane.lane_clear(from, to, [], AIPuckLane.PASS_SPEED_M_S)
	assert_almost_eq(s, 1.0, 0.0001, "empty lane is fully clear")


func test_lane_clear_reduced_by_mid_lane_defender() -> void:
	# Defender mid-segment, dead on the line: the puck's path runs straight
	# through their stick reach → full block → clearance drops below 1.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var mid_lane: Array[Vector3] = [Vector3(0.2, 0.0, 7.0)]
	var s: float = AIPuckLane.lane_clear(from, to, mid_lane, AIPuckLane.PASS_SPEED_M_S)
	assert_lt(s, 1.0, "a defender on the mid-lane reduces clearance")


func test_lane_block_scales_with_defender_reach_and_speed() -> void:
	# A defender 2.5 m off the pass line — a partial block at league reach. A
	# longer-stick, faster defender slides further into the lane and
	# reaches the puck → blocks more (lower clearance); a short, slow one blocks
	# less. Empty caps sits at the league default between them.
	var from := Vector3(0, 0, 0)
	var to := Vector3(0, 0, 14)
	var off_lane: Array[Vector3] = [Vector3(2.5, 0, 7)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var pass_speed: float = AIPuckLane.PASS_SPEED_M_S
	var league: float = AIPuckLane.lane_clear(from, to, off_lane, pass_speed, vels)
	var big := AISkaterCaps.new()
	big.stick_reach = 1.6
	big.max_speed = 12.0
	var vs_big: float = AIPuckLane.lane_clear(from, to, off_lane, pass_speed, vels, [big])
	var small := AISkaterCaps.new()
	small.stick_reach = 1.1
	small.max_speed = 6.0
	var vs_small: float = AIPuckLane.lane_clear(from, to, off_lane, pass_speed, vels, [small])
	assert_lt(vs_big, league, "a longer-reach, faster defender intercepts more of the lane")
	assert_gt(vs_small, league, "a shorter, slower defender lets more through")


func test_pass_score_prices_lane_defender_by_build() -> void:
	# The #567 calibration case: the SAME feed scored against a lane defender
	# whose build differs. A long-stick, fast defender covers the thread his
	# real reach buys (lower pass score); a short, slow one concedes it.
	# League (no caps) sits strictly between — empty caps reproduce the
	# constants exactly, so the ordering table only moves where an opponent
	# is non-neutral.
	var shooter := Vector3(0.0, 0.0, 8.0)
	var receiver := Vector3(0.0, 0.0, 22.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var off_lane: Array[Vector3] = [Vector3(2.5, 0.0, 15.0)]
	var league: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, off_lane)
	var long_stick := AISkaterCaps.new()
	long_stick.stick_reach = 1.6
	long_stick.max_speed = 12.0
	var vs_long: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, off_lane, AIPuckLane.PASS_SPEED_M_S, [long_stick])
	var short_stick := AISkaterCaps.new()
	short_stick.stick_reach = 1.1
	short_stick.max_speed = 6.0
	var vs_short: float = AIActionScoring.score_pass_value(shooter, receiver, GOAL, goalie, off_lane, AIPuckLane.PASS_SPEED_M_S, [short_stick])
	assert_lt(vs_long, league,
			"the long-stick defender's real reach covers the same feed")
	assert_gt(vs_short, league,
			"the short-stick defender concedes the same feed")


func test_lane_loss_point_follows_the_caps_aware_worst_defender() -> void:
	# lane_loss_point shares the per-defender block helpers with lane_clear so
	# the two agree on which defender is worst BY CONSTRUCTION — including when
	# builds decide it: a near short-stick man is league's worst blocker, but a
	# long-stick fast man deeper down the lane out-blocks him on real caps, and
	# the predicted pick spot must move to HIS crossing.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 16.0)
	# Near man 2.0 m off the lane at z=5; deep man 4.3 m off at z=10 — outside
	# league reach there, inside a long-stick sprinter's.
	var opps: Array[Vector3] = [Vector3(2.0, 0.0, 5.0), Vector3(4.3, 0.0, 10.0)]
	var vels: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var league_p: Vector3 = AIPuckLane.lane_loss_point(
			from, to, opps, AIPuckLane.PASS_SPEED_M_S, vels)
	assert_lt(absf(league_p.z - 5.0), absf(league_p.z - 10.0),
			"at league reach the near defender is the interceptor")
	var short_slow := AISkaterCaps.new()
	short_slow.stick_reach = 1.05
	short_slow.max_speed = 5.0
	var long_fast := AISkaterCaps.new()
	long_fast.stick_reach = 1.6
	long_fast.max_speed = 12.0
	var caps_p: Vector3 = AIPuckLane.lane_loss_point(
			from, to, opps, AIPuckLane.PASS_SPEED_M_S, vels,
			[short_slow, long_fast])
	assert_lt(absf(caps_p.z - 10.0), absf(caps_p.z - 5.0),
			"on real builds the long-stick man deeper in the lane is the pick spot")


func test_lane_clear_blocks_close_on_line_defender() -> void:
	# THE breakout-turnover regression. A defender 1 m in front of the
	# passer, dead on the line — a man in the slot the pass would go
	# straight through. The old reaction-window model treated them as
	# unable to react (puck "blows past" before the delay) and read the
	# lane as clear, so the turnover cost collapsed to zero. The
	# reachability model sees the puck pass within a stick of where they
	# already are → full block.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var close_on_line: Array[Vector3] = [Vector3(0.0, 0.0, 1.0)]
	var s: float = AIPuckLane.lane_clear(from, to, close_on_line, AIPuckLane.PASS_SPEED_M_S)
	assert_lt(s, 0.05, "a defender right on the line at the release fully blocks the lane")


func test_lane_clear_charged_pass_threads_better_than_quick() -> void:
	# A faster (charged) pass reaches the defender's closest-approach point
	# sooner, leaving less time to close the gap → smaller reach → the lane
	# reads as more open. This is why routing the carrier through the real
	# pass speed matters for pickoff risk. Defender held off the line so
	# both speeds give a partial (non-saturated) block that can differ.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 15.0)
	var lane_def: Array[Vector3] = [Vector3(1.0, 0.0, 2.5)]
	var quick: float = AIPuckLane.lane_clear(from, to, lane_def, AIPuckLane.PASS_SPEED_M_S)
	var charged: float = AIPuckLane.lane_clear(from, to, lane_def, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	assert_gt(charged, quick, "faster pass → less time for the defender to close → cleaner lane")


func test_lane_clear_clean_stretch_pass_stays_open() -> void:
	# A long pass with the only defender 8 m off the lane: even with the
	# whole flight to close, they can't reach the path → lane stays open.
	# Guards against the model over-rejecting legitimate stretch passes.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 20.0)
	var far_off: Array[Vector3] = [Vector3(8.0, 0.0, 10.0)]
	var s: float = AIPuckLane.lane_clear(from, to, far_off, AIPuckLane.PASS_SPEED_M_S)
	assert_almost_eq(s, 1.0, 0.0001, "a defender far off a stretch-pass lane doesn't block it")


func test_lane_clear_closing_defender_blocks_more_than_stationary() -> void:
	# Same defender 2 m off the mid-lane. Standing still they only partly
	# block; bearing down on the lane (−X velocity) they're dead-reckoned
	# INTO it → strictly more block (lower clearance). The old position-
	# only model could not tell these apart.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var pos: Array[Vector3] = [Vector3(2.0, 0.0, 6.0)]
	var stationary: float = AIPuckLane.lane_clear(
			from, to, pos, AIPuckLane.PASS_SPEED_M_S, [Vector3.ZERO])
	var closing: float = AIPuckLane.lane_clear(
			from, to, pos, AIPuckLane.PASS_SPEED_M_S, [Vector3(-4.0, 0.0, 0.0)])
	assert_lt(closing, stationary, "a defender closing on the lane blocks more")


func test_lane_clear_defender_drifting_away_blocks_less() -> void:
	# Mirror image: the same defender drifting AWAY from the lane (+X)
	# can't reach it → blocks less than standing still (higher clearance).
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var pos: Array[Vector3] = [Vector3(2.0, 0.0, 6.0)]
	var stationary: float = AIPuckLane.lane_clear(
			from, to, pos, AIPuckLane.PASS_SPEED_M_S, [Vector3.ZERO])
	var drifting: float = AIPuckLane.lane_clear(
			from, to, pos, AIPuckLane.PASS_SPEED_M_S, [Vector3(4.0, 0.0, 0.0)])
	assert_gt(drifting, stationary, "a defender drifting off the lane blocks less")


func test_lane_clear_accurate_compounds_two_separated_defenders() -> void:
	# The legacy model takes 1 − max(block): two defenders threatening DIFFERENT
	# segments of a long lane read only as open as the easier gap. The `accurate`
	# survival product makes the puck beat BOTH — two separated half-blockers
	# compound to a much less clear lane than either alone.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 16.0)
	var one_a: Array[Vector3] = [Vector3(3.6, 0.0, 12.0)]     # contests the middle
	var one_b: Array[Vector3] = [Vector3(-4.2, 0.0, 14.0)]    # contests the receiver end
	var both: Array[Vector3] = [one_a[0], one_b[0]]
	var speed: float = 18.0
	var clear_a: float = AIPuckLane.lane_clear(from, to, one_a, speed, [], [], true)
	var clear_b: float = AIPuckLane.lane_clear(from, to, one_b, speed, [], [], true)
	var clear_both: float = AIPuckLane.lane_clear(from, to, both, speed, [], [], true)
	# Each leaves a real gap alone (~0.6–0.7 clear); together the lane is much
	# worse than either — the product compounds two independent, separated threats.
	assert_gt(clear_a, 0.3)
	assert_gt(clear_b, 0.3)
	assert_lt(clear_both, minf(clear_a, clear_b) - 0.1,
			"two separated defenders compound to much less clear than either alone")
	# Legacy max prices it as just the single worst gap — no compounding.
	var legacy_both: float = AIPuckLane.lane_clear(from, to, both, speed)
	assert_lt(clear_both, legacy_both - 0.1,
			"the survival product reads a two-defender lane far less clear than legacy max")


func test_friction_traverse_time_exceeds_frictionless() -> void:
	# Gap 3: the puck sheds ice friction, so it takes longer to cover the lane than
	# dist/v0 — the far end gives lane defenders more time. Small (~a few %) but in
	# the honest direction. Checks the closed-form arrival root against the
	# frictionless baseline and the kinematic identity dist = v0·T − ½·a·T².
	var dist: float = 18.0
	var v0: float = 20.0
	var t: float = AIPuckLane._friction_traverse_time(dist, v0)
	assert_gt(t, dist / v0, "friction makes the traversal take longer than dist/v0")
	var a: float = GameRules.PUCK_ICE_DECEL_M_S2
	assert_almost_eq(v0 * t - 0.5 * a * t * t, dist, 0.001,
			"traverse time satisfies dist = v0·T − ½·a·T²")


func test_lane_clear_release_windup_projection_blocks_more() -> void:
	# The carrier prices a PASS lane at RELEASE time, not decision time: every bot
	# pass is a charged wrister that leaves the blade ~135 ms (BOT_WRISTER_LOOKAHEAD_S)
	# after the intent commits, so the carrier feeds lane_clear the defenders
	# ADVANCED by that windup (_scratch_opponents_release). This mirrors that step:
	# the same closing defender, advanced by the windup before the flight
	# dead-reckon, blocks strictly more than at his decision-time spot — which is
	# exactly the "clear at decision, closed at release" breakout feed the model was
	# shipping into a stick.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var charged_pass_speed: float = 20.0             # a real charged breakout pace
	var vel := Vector3(-3.0, 0.0, 0.0)               # closing on the lane from the +X side
	var at_decision: Array[Vector3] = [Vector3(3.0, 0.0, 6.0)]
	var at_release: Array[Vector3] = [AITrajectory.predict_at(
			at_decision[0], vel, AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S)]
	var decision_lane: float = AIPuckLane.lane_clear(
			from, to, at_decision, charged_pass_speed, [vel])
	var release_lane: float = AIPuckLane.lane_clear(
			from, to, at_release, charged_pass_speed, [vel])
	assert_gt(decision_lane, 0.5,
			"at decision time the closing defender still leaves a mostly-open lane")
	assert_lt(release_lane, decision_lane,
			"pricing the closing defender at his release-time spot reads the lane more blocked")


# ── lane_clear_saucer: a low flip over a near stick ──────────────────────────
# The saucer flight is pure kinematics of the LOW loft's fixed vertical
# launch: the puck is above the blade plane for the over window
# [t_over, t_down], during which only a BODY in the lane blocks it; before
# (still on the blade) and after (landed) a stick intercepts normally.
# Airborne carry = launch speed × hang time, so a softer flip lands sooner
# — the close-quarters saucer — and a defender past the touch-down point
# plays it like a flat pass.

func test_lane_clear_saucer_clears_near_stick_range_defender() -> void:
	# Defender mid-lane (~3 m out — well inside the over window at charge
	# pace) and off the line by more than a body radius (within stick +
	# closing reach, so the grounded lane is contested). The saucer flies
	# over their stick, body out of the way → clear.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var near_stick: Array[Vector3] = [Vector3(0.7, 0.0, 3.0)]
	var grounded: float = AIPuckLane.lane_clear(from, to, near_stick, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	var saucer: float = AIPuckLane.lane_clear_saucer(from, to, near_stick, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	assert_lt(grounded, 1.0, "sanity: grounded lane is contested by the stick-range defender")
	assert_almost_eq(saucer, 1.0, 0.0001, "saucer flies over a near stick → lane clear")


func test_lane_clear_saucer_blocked_by_body_in_lane() -> void:
	# Defender standing dead in the lane inside the over window (within a
	# body radius of the line): the saucer can't fly over a torso, blocks.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var body_in_lane: Array[Vector3] = [Vector3(0.0, 0.0, 3.0)]
	var saucer: float = AIPuckLane.lane_clear_saucer(from, to, body_in_lane, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	assert_lt(saucer, 0.1, "a body dead in the lane blocks a saucer")


func test_lane_clear_saucer_stuffed_by_stick_on_the_release() -> void:
	# Defender's closest approach is right off the blade (t < t_over — the
	# puck hasn't climbed above the blade plane yet): full grounded stick
	# reach applies, so a stick already on the puck stuffs the flip.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var on_release: Array[Vector3] = [Vector3(0.4, 0.0, 0.3)]
	var saucer: float = AIPuckLane.lane_clear_saucer(from, to, on_release, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	assert_lt(saucer, 0.5, "a stick on the puck at release still stuffs a saucer")


func test_lane_clear_saucer_blocked_after_touch_down() -> void:
	# Stick-range defender past the touch-down point (speed × hang time —
	# ~9.7 m at charge pace): the puck has landed by then, so it blocks the
	# saucer with a full stick just like a flat pass. A saucer doesn't
	# clear a defender far down the lane.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var landed_dist: float = AIPuckLane.saucer_airborne_distance_m(
			AIPuckLane.PASS_CHARGE_SPEED_M_S) + 1.0
	var far_stick: Array[Vector3] = [Vector3(0.5, 0.0, landed_dist)]
	var saucer: float = AIPuckLane.lane_clear_saucer(from, to, far_stick, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	assert_lt(saucer, 1.0, "a defender past the touch-down point still blocks a landed saucer")


func test_lane_clear_saucer_soft_flip_lands_earlier() -> void:
	# The airborne carry scales with launch speed: the crisp flip clears a
	# defender 5 m out and lands far enough past him that the puck runs away
	# from his stick; the SOFT flip lands beside him and he plays it. This is
	# the physical trade the close-quarters saucer makes: softer pace buys a
	# receivable landing, at the cost of clearing less lane.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var mid_stick: Array[Vector3] = [Vector3(0.5, 0.0, 5.0)]
	var crisp: float = AIPuckLane.lane_clear_saucer(from, to, mid_stick, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	var soft: float = AIPuckLane.lane_clear_saucer(from, to, mid_stick, 12.0)
	assert_almost_eq(crisp, 1.0, 0.0001, "the crisp flip lands well past the 5 m defender")
	assert_lt(soft, crisp, "the soft flip lands beside him — he blocks it")


func test_lane_clear_saucer_the_man_it_flew_over_plays_the_landing() -> void:
	# Over him the puck is out of his stick's reach, but it lands a metre past
	# him: on the ice it is a flat pass sliding off his blade, and he plays it.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var landing: float = AIPuckLane.saucer_airborne_distance_m(AIPuckLane.PASS_CHARGE_SPEED_M_S)
	var under: Array[Vector3] = [Vector3(0.5, 0.0, landing - 1.0)]
	assert_lt(AIPuckLane.lane_clear_saucer(from, to, under, AIPuckLane.PASS_CHARGE_SPEED_M_S),
			0.5)


func test_saucer_max_launch_speed_bounds_receivable_flips() -> void:
	# The receivability bound: launch × hang time + landing run must fit
	# inside the pass distance. At the bound the flip lands exactly a
	# landing-run short of the tape; below the softest feed (~6.5 m feeds and
	# shorter) no saucer is offered.
	var bound: float = AIPuckLane.saucer_max_launch_speed(10.0)
	assert_almost_eq(
			AIPuckLane.saucer_airborne_distance_m(bound)
					+ AIPuckLane.SAUCER_LANDING_RUN_M,
			10.0, 0.0001,
			"at the bound the flip lands exactly a landing-run before the tape")
	assert_gt(AIPuckLane.saucer_max_launch_speed(7.0),
			AIPuckLane.SOFTEST_FEED_M_S,
			"a 7 m feed still admits a soft saucer above the softest feed")
	assert_lt(AIPuckLane.saucer_max_launch_speed(6.0),
			AIPuckLane.SOFTEST_FEED_M_S,
			"a 6 m feed can't be saucered — even the softest flip lands too late")


# ── lane_loss_point: interceptor location for the turnover-cost term ──────────
# The loss location must be the worst blocker's closest-point ON the
# segment (where the puck actually gets picked), and INF when the lane
# is clean (no turnover to cost).

func test_lane_loss_point_inf_when_no_blocker() -> void:
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var p: Vector3 = AIPuckLane.lane_loss_point(from, to, [], AIPuckLane.PASS_SPEED_M_S)
	assert_false(p.is_finite(), "clean lane has no interception point")


func test_lane_loss_point_inf_when_defender_off_lane() -> void:
	# Defender far off the segment with no time to close → no block.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var off_lane: Array[Vector3] = [Vector3(6.0, 0.0, 7.0)]
	var p: Vector3 = AIPuckLane.lane_loss_point(from, to, off_lane, AIPuckLane.PASS_SPEED_M_S)
	assert_false(p.is_finite(), "defender off the lane yields no interception point")


func test_lane_loss_point_is_on_the_path() -> void:
	# Single mid-lane defender at (0.4, 7.0) on a straight +Z lane: the
	# loss point is where the puck is at the defender's closest approach —
	# x on the lane (0), z at the defender's 7.0.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var mid: Array[Vector3] = [Vector3(0.4, 0.0, 7.0)]
	var p: Vector3 = AIPuckLane.lane_loss_point(from, to, mid, AIPuckLane.PASS_SPEED_M_S)
	assert_true(p.is_finite(), "a blocking defender yields an interception point")
	assert_almost_eq(p.x, 0.0, 0.001, "loss point sits on the lane (x=0)")
	assert_almost_eq(p.z, 7.0, 0.001, "loss point sits at the defender's position along the lane")


func test_lane_loss_point_finite_for_close_release_defender() -> void:
	# Companion to the lane_clear close-defender regression: a defender 1 m
	# in front of the passer on the line now produces a finite loss point
	# (the old model returned INF here, zeroing the turnover cost). The
	# pick spot is right where they stand, ~1 m down the line.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var close_on_line: Array[Vector3] = [Vector3(0.0, 0.0, 1.0)]
	var p: Vector3 = AIPuckLane.lane_loss_point(from, to, close_on_line, AIPuckLane.PASS_SPEED_M_S)
	assert_true(p.is_finite(), "a close on-line defender yields a real interception point")
	assert_almost_eq(p.z, 1.0, 0.1, "the pick happens right where the defender stands")


func test_lane_loss_point_prices_a_lane_only_the_planted_interceptor_blocks() -> void:
	# 4.5 m off a 16 m lane at z = 10: coasting, he never reaches the puck, but
	# he can skate down the lane and plant on it ahead of the feed. The accurate
	# lane prices that pick, so the loss point must be that planted spot — not
	# INF, which turnover_cost reads as a free interception.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 16.0)
	var planter: Array[Vector3] = [Vector3(4.5, 0.0, 10.0)]
	var speed: float = AIPuckLane.PASS_SPEED_M_S
	assert_eq(AIPuckLane.lane_clear(from, to, planter, speed), 1.0,
			"precondition: the coasting read sees no block")
	assert_lt(AIPuckLane.lane_clear(from, to, planter, speed, [], [], true), 1.0,
			"the accurate lane does")
	var p: Vector3 = AIPuckLane.lane_loss_point(from, to, planter, speed)
	assert_true(p.is_finite(), "an interception the lane prices has a place")
	assert_almost_eq(p.x, 0.0, 0.001, "on the lane")
	assert_between(p.z, 10.0, 16.0, "planted downstream of his crossing, short of the tape")


func test_the_lane_and_its_loss_point_agree_on_whether_anyone_blocks() -> void:
	# One model for the chance and the place: a lane the accurate read says can
	# be picked always has a loss point, and a clean one never does.
	var rng := RandomNumberGenerator.new()
	rng.seed = 772
	for i: int in 400:
		var from := Vector3(rng.randf_range(-10.0, 10.0), 0.0, rng.randf_range(-20.0, 20.0))
		var to: Vector3 = from + Vector3(rng.randf_range(-14.0, 14.0), 0.0,
				rng.randf_range(-14.0, 14.0))
		var opps: Array[Vector3] = []
		var vels: Array[Vector3] = []
		for j: int in rng.randi_range(0, 3):
			opps.append(from.lerp(to, rng.randf()) + Vector3(rng.randf_range(-6.0, 6.0), 0.0,
					rng.randf_range(-6.0, 6.0)))
			vels.append(Vector3(rng.randf_range(-5.0, 5.0), 0.0, rng.randf_range(-5.0, 5.0)))
		var speed: float = rng.randf_range(8.0, 24.0)
		var lane: float = AIPuckLane.lane_clear(from, to, opps, speed, vels, [], true)
		var p: Vector3 = AIPuckLane.lane_loss_point(from, to, opps, speed, vels)
		assert_eq(p.is_finite(), lane < 1.0,
				"case %d: lane %.4f but loss point %s" % [i, lane, p])


func test_lane_loss_point_picks_worst_blocker() -> void:
	# Two blockers; the one with higher block strength defines the loss
	# point. The dead-on mid-lane defender at z=7 outweighs one far off the
	# line at z=11 (only a partial block) — loss point should be at z≈7.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 14.0)
	var blockers: Array[Vector3] = [
			Vector3(0.05, 0.0, 7.0),   # dead-on, mid-lane → strong block
			Vector3(4.0, 0.0, 11.0),   # well off the line → weak block
	]
	var p: Vector3 = AIPuckLane.lane_loss_point(from, to, blockers, AIPuckLane.PASS_SPEED_M_S)
	assert_almost_eq(p.z, 7.0, 0.001, "loss point follows the strongest blocker")


const OUR_NET := Vector3(0.0, 0.0, 26.65)        # we defend +Z


# ── pass_miss_prob: derived execution-miss probability ────────────────────────
# The miss chance is no longer a flat constant: it's the irreducible base floor
# compounded with the passer's hand error projected to the tape over the pass
# distance, vs the receiver's catch envelope.

func test_pass_miss_prob_is_the_base_floor_for_a_perfect_hand() -> void:
	# Zero aim error (the perfect baseline / cross-player threat model) → only the
	# irreducible base survives, at any distance.
	assert_almost_eq(AIPuckLane.pass_miss_prob(4.0, 0.0),
			AIPuckLane.PASS_MISS_BASE_PROB, 0.0001, "no hand error → base floor")
	assert_almost_eq(AIPuckLane.pass_miss_prob(25.0, 0.0),
			AIPuckLane.PASS_MISS_BASE_PROB, 0.0001, "distance alone doesn't miss")


func test_pass_miss_prob_grows_once_the_spread_outruns_the_catch_envelope() -> void:
	# A reachable off-target feed is adjusted to (spread ≤ catch envelope) and
	# stays at the base — realistic: clean-lane passes to a reachable spot complete
	# almost always. Only when the spread OUTRUNS the catch reach (a long and/or
	# wobbly feed) does execution risk climb.
	var reachable: float = AIPuckLane.pass_miss_prob(15.0, 0.04)   # spread 0.6 < 0.9
	var long_feed: float = AIPuckLane.pass_miss_prob(30.0, 0.04)   # spread 1.2 > 0.9
	var wobbly_feed: float = AIPuckLane.pass_miss_prob(30.0, 0.055)
	assert_almost_eq(reachable, AIPuckLane.PASS_MISS_BASE_PROB, 0.0001,
			"a reachable feed is adjusted to → base only")
	assert_gt(long_feed, reachable, "a stretch feed spreads the error past the reach → misses more")
	assert_gt(wobbly_feed, long_feed, "a wobblier hand at the same range misses more")


func test_pass_miss_prob_tighter_catch_envelope_misses_more() -> void:
	# A receiver with less reach (lower Hands handle) corrals fewer off-target
	# feeds, so the same long pass misses more.
	var wide: float = AIPuckLane.pass_miss_prob(30.0, 0.04, 1.2)
	var tight: float = AIPuckLane.pass_miss_prob(30.0, 0.04, 0.6)
	assert_gt(tight, wide, "a shorter catch envelope corrals fewer off-target feeds")


func test_pass_miss_prob_receiver_uncertainty_adds_to_the_spread() -> void:
	# The receiver's own heading uncertainty (a turning receiver curving off the
	# lead) adds to the passer's hand spread — a settled receiver (0) is unchanged,
	# and turn uncertainty can push a reachable feed past the catch envelope.
	var settled: float = AIPuckLane.pass_miss_prob(15.0, 0.04, 0.9, 0.0)
	assert_almost_eq(settled, AIPuckLane.pass_miss_prob(15.0, 0.04, 0.9),
			0.0001, "a settled receiver (0 uncertainty) is priced like a clean feed")
	# hand spread 0.6 < 0.9 catch → base; add 0.6 m of turn uncertainty → 1.2 > 0.9.
	var turning: float = AIPuckLane.pass_miss_prob(15.0, 0.04, 0.9, 0.6)
	assert_gt(turning, settled,
			"a turning receiver's catch-point uncertainty raises the miss chance")


# ── receiver_heading_uncertainty_m: turning-receiver catch-point uncertainty ───
# The lateral deviation R·(1−cos θ) of a constant-radius arc from its launch
# tangent — the metres a turning receiver misses the straight-line lead by.

func test_receiver_heading_uncertainty_zero_for_a_committed_receiver() -> void:
	# No turn, no speed, or no flight → nothing to be uncertain about.
	assert_almost_eq(AIPuckLane.receiver_heading_uncertainty_m(6.0, 0.0, 0.55),
			0.0, 0.0001, "a straight-line receiver has zero heading uncertainty")
	assert_almost_eq(AIPuckLane.receiver_heading_uncertainty_m(0.0, 3.0, 0.55),
			0.0, 0.0001, "a stationary receiver has no heading to miss")
	assert_almost_eq(AIPuckLane.receiver_heading_uncertainty_m(6.0, 3.0, 0.0),
			0.0, 0.0001, "an instantaneous pass has no flight to curve over")


func test_receiver_heading_uncertainty_matches_arc_geometry() -> void:
	# v=6, ω=2, t=0.55 → θ=1.1 rad, R=3 m, dev = 3·(1−cos 1.1) ≈ 1.64 m.
	var dev: float = AIPuckLane.receiver_heading_uncertainty_m(6.0, 2.0, 0.55)
	assert_almost_eq(dev, 3.0 * (1.0 - cos(1.1)), 0.001,
			"exact tangent-deviation of the arc")


func test_receiver_heading_uncertainty_grows_with_turn_and_saturates() -> void:
	# A harder cut curves further off the lead...
	var soft: float = AIPuckLane.receiver_heading_uncertainty_m(6.0, 1.0, 0.5)
	var hard: float = AIPuckLane.receiver_heading_uncertainty_m(6.0, 3.0, 0.5)
	assert_gt(hard, soft, "a harder turn adds more catch-point uncertainty")
	# ...but the swept angle caps at π, so it never exceeds the arc's 2R diameter.
	var spun: float = AIPuckLane.receiver_heading_uncertainty_m(6.0, 100.0, 1.0)
	assert_lte(spun, 2.0 * (6.0 / 100.0) + 0.0001,
			"the swept-angle cap keeps the deviation at ≤ 2R (no runaway)")


# ── pass_miss_loss_point: execution-miss loss location ────────────────────────
# A lane-clear pass can still miss on execution; the puck dies
# PASS_MISS_OVERSHOOT_M past the receiver on the pass line.

func test_pass_miss_loss_point_overshoots_past_receiver() -> void:
	var from := Vector3(0.0, 0.0, 20.0)
	var receiver := Vector3(0.0, 0.0, 24.0)  # straight backpass toward our net
	var loss: Vector3 = AIPuckLane.pass_miss_loss_point(from, receiver)
	assert_almost_eq(loss.z, 24.0 + AIPuckLane.PASS_MISS_OVERSHOOT_M, 0.001,
			"miss point sits the overshoot distance past the receiver on the pass line")
	assert_almost_eq(loss.x, 0.0, 0.001)


func test_pass_miss_loss_point_degenerate_falls_back_to_receiver() -> void:
	var p := Vector3(3.0, 0.0, 10.0)
	assert_eq(AIPuckLane.pass_miss_loss_point(p, p), p,
			"overlapping endpoints → miss point is the receiver itself")


func test_pass_miss_cost_self_localizes_by_rink_end() -> void:
	# The property the miss mode exists for: the identical pass shape,
	# missed in our own end, costs far more than missed in the opponent's
	# end — because the overshoot loss point lands in front of OUR net in
	# one case and a full rink away in the other. This is what lets the
	# risk term punish own-zone touch-passes without taxing OZ passing. Our
	# pair stands back at our blue line, as it does for either pass: on an empty
	# rink a man a full rink away still walks in, and only the race says he
	# does not.
	var own_end_loss: Vector3 = AIPuckLane.pass_miss_loss_point(
			Vector3(2.0, 0.0, 20.0), Vector3(-2.0, 0.0, 23.0))
	var opp_end_loss: Vector3 = AIPuckLane.pass_miss_loss_point(
			Vector3(2.0, 0.0, -20.0), Vector3(-2.0, 0.0, -23.0))
	var theirs := AIPossessionValue.new()
	var our_pair: Array[Vector3] = [Vector3(-3.0, 0.0, 9.0), Vector3(3.0, 0.0, 9.0)]
	var still: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	theirs.fill(OUR_NET, our_pair, still, [])
	var own_end_cost: float = AIPuckLane.PASS_MISS_BASE_PROB * theirs.at(own_end_loss)
	var opp_end_cost: float = AIPuckLane.PASS_MISS_BASE_PROB * theirs.at(opp_end_loss)
	assert_gt(own_end_cost, opp_end_cost * 4.0,
			"a missed pass in our own end costs multiples of the same miss in theirs")


# ─── Stance-aware five-hole (measured slot from the replicated pose) ──────

func test_derive_post_seal_only_fires_in_the_sharp_near_line_zone() -> void:
	# The predictor matches the keeper: his sharp angle (below the dots, past 60°)
	# and, outside it, a look whose net window his standing span covers. A
	# dead-angle corner seals; a normal slot / mid look does not; an in-tight
	# look wide enough to shoot past his body does not.
	var goal := Vector3(0, 0, -26.65)
	assert_ne(AIGoalieModel.derive_post_seal_x_sign(Vector3(8, 0, -25.5), goal), 0.0,
			"dead-angle corner (1.15 m out, ~82°) is sealed")
	assert_eq(AIGoalieModel.derive_post_seal_x_sign(Vector3(0, 0, -20.65), goal), 0.0,
			"the slot is never sealed")
	assert_eq(AIGoalieModel.derive_post_seal_x_sign(Vector3(7, 0, -18.0), goal), 0.0,
			"an off-angle mid look (8.6 m out) is not sealed")
	assert_eq(AIGoalieModel.derive_post_seal_x_sign(Vector3(3.5, 0, -23.65), goal), 0.0,
			"an in-tight look (3 m out, ~49°) is a real shot, not a seal")
	# The seal side is the shooter's side of the goal center.
	assert_eq(AIGoalieModel.derive_post_seal_x_sign(Vector3(-8, 0, -25.5), goal), -1.0,
			"seals the side the shooter is on")


func test_arc_match_x_bounded_by_goalie_radius() -> void:
	# A puck reference near the goal line at wide x used to explode the arc-x
	# toward the corner boards. The goalie squares along his ARC: |x offset|
	# can never exceed his radial distance from the goal.
	var goal := Vector3(0, 0, -26.65)
	var goalie := Vector3(0, 0, -24.9)   # 1.75 out
	var x: float = AIGoalieModel.goalie_arc_match_x(
			goalie, goal, Vector3(4.0, 0, -26.4))   # wide, 0.25 m off the line
	assert_lte(absf(x), 1.7501, "arc-x is bounded by the goalie's own radius")
	# Moderate angles unchanged: well inside the radius, wider than the post.
	var mid: float = AIGoalieModel.goalie_arc_match_x(
			goalie, goal, Vector3(1.75, 0, -24.05))
	assert_almost_eq(mid, 1.75 * 1.75 / 2.6, 0.001,
			"a moderate-angle arc-x is the raw arc match (unclamped)")


# ─── Spread-aware entry inset ─────────────────────────────────────────────

func _tip_fixture(tip_man: Vector3, pace: float,
		defenders: Array[Vector3]) -> float:
	# Point release, set challenged goalie — the same look the screen tests
	# use, now with a body to deflect off.
	return AIActionScoring.tip_ev(
			Vector3(0.0, 0.0, 10.0), tip_man, GOAL,
			Vector3(0.0, 0.0, 25.5), defenders, pace)


func test_tip_needs_a_blade_the_shot_line_actually_crosses() -> void:
	# A man 5 m off the line can't reach the flight in time (the same
	# reach/reaction race a lane defender runs) — no tip outcome exists.
	var none: Array[Vector3] = []
	assert_eq(_tip_fixture(Vector3(5.0, 0.0, 24.0), 33.0, none), 0.0,
			"an unreachable flight is not tippable")


func test_tip_needs_deflect_pace() -> void:
	# Below the deflect threshold (Puck.deflect_min_speed mirror) the puck
	# lands on the tape as a catch — a pass, not a tip.
	var none: Array[Vector3] = []
	assert_eq(_tip_fixture(Vector3(0.0, 0.0, 24.0), 18.0, none), 0.0,
			"a soft feed is a pass, not a tip")


func test_lane_clear_accurate_never_reads_a_crossing_defender_clearer() -> void:
	# The guided floor: a defender on the lane at any crossing speed reads no
	# clearer than standing still, where the ballistic coast lets a fast one
	# sail through.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var d: Array[Vector3] = [Vector3(2.0, 0.0, 6.0)]
	var still: float = AIPuckLane.lane_clear(from, to, d, 18.0, [Vector3.ZERO], [], true)
	for vx: float in [-4.0, -10.0, -16.0, -22.0]:
		var v: Array[Vector3] = [Vector3(vx, 0.0, 0.0)]
		var accurate: float = AIPuckLane.lane_clear(from, to, d, 18.0, v, [], true)
		assert_lte(accurate, still + 1e-4, "crossing at %.0f reads clearer than standing" % vx)
	var fast: Array[Vector3] = [Vector3(-16.0, 0.0, 0.0)]
	assert_lt(AIPuckLane.lane_clear(from, to, d, 18.0, fast, [], true),
			AIPuckLane.lane_clear(from, to, d, 18.0, fast),
			"the floor is what stops a fast crosser coasting through")

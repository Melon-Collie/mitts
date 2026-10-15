extends GutTest

# AIActionScoring is pure-function. Tests cover the obvious geometric
# cases and the boundary conditions on shot geometry / pressure / lane.

const NET_HW: float = 0.915
# Goal at +Z for these tests; shooter shoots toward +Z, goalie sits in front.
const GOAL := Vector3(0.0, 0.0, 26.65)


func test_shoot_score_falls_off_with_pressure() -> void:
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var clear: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,[])
	# Defender one stick from the RELEASE POINT (the puck a carry-handle
	# toward the net): his blade genuinely contests the windup
	# (release_contest_clean). Off the shot lane laterally so lane_clear
	# stays ~1.0 — this tests release duress in isolation.
	var nearby_opp: Array[Vector3] = [Vector3(1.2, 0.0, 22.4)]
	var pressured: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,nearby_opp)
	assert_lt(pressured, clear, "a blade within reach of the release contests the shot")


func test_shoot_score_ignores_defender_beyond_blade_reach() -> void:
	# The old density curve penalized any body within 4 m of the shooter's
	# forward cone. Physically, a defender ~3 m away cannot touch a ~135 ms
	# release — only a blade that can reach the puck during the windup
	# contests it. He's also kept off the shot lane so lane_clear is 1.0.
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var clear: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,[])
	var watcher: Array[Vector3] = [Vector3(2.8, 0.0, 22.5)]
	var watched: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,watcher)
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
	var clear: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,[])
	# Defender at z=20, 5 m from shooter along an ~11 m segment —
	# t ≈ 0.43, time_to_defender ≈ 0.16 s > LANE_REACTION_DELAY_S
	# (0.08), so they have time to position their stick.
	var blocker: Array[Vector3] = [Vector3(-0.1, 0.0, 20.0)]
	var blocked: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,blocker)
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
	var league: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW, off_lane)
	var big := AISkaterCaps.new()
	big.stick_reach = 1.7
	big.max_speed = 12.0
	var vs_big: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW, off_lane,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, [big])
	var small := AISkaterCaps.new()
	small.stick_reach = 1.0
	small.max_speed = 6.0
	var vs_small: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW, off_lane,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, [small])
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
	var clear: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,[])
	# Defender to the far side, outside both pressure radius and shot lane.
	var off_lane: Array[Vector3] = [Vector3(8.0, 0.0, 24.0)]
	var s: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,off_lane)
	assert_almost_eq(s, clear, 0.001)


func test_pass_score_zero_when_lane_blocked() -> void:
	var shooter := Vector3(0.0, 0.0, 10.0)
	var receiver := Vector3(0.0, 0.0, 22.0)  # close to goal, would normally score
	var goalie := Vector3(0.5, 0.0, 26.0)
	var blocker: Array[Vector3] = [Vector3(0.0, 0.0, 16.0)]  # right on the line
	var s: float = AIActionScoring.score_pass(shooter, receiver, GOAL, goalie, NET_HW,blocker)
	assert_eq(s, 0.0, "opponent on the pass line should zero the score")


func test_pass_lane_only_counts_opponents_between_endpoints() -> void:
	var shooter := Vector3(0.0, 0.0, 10.0)
	var receiver := Vector3(0.0, 0.0, 22.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	# Opponent BEHIND the shooter (z=5, before z=10) — shouldn't block
	var behind: Array[Vector3] = [Vector3(0.0, 0.0, 5.0)]
	var s: float = AIActionScoring.score_pass(shooter, receiver, GOAL, goalie, NET_HW,behind)
	assert_gt(s, 0.0, "opponent behind the shooter shouldn't block the lane")


func test_shoot_score_zero_from_behind_goal_line() -> void:
	# GOAL.z = +26.65; shooter past it (z=27) is behind the net.
	var shooter := Vector3(0.0, 0.0, 27.0)
	var goalie := Vector3(0.0, 0.0, 26.0)
	var s: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,[])
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
		assert_eq(AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW, []), 0.0,
				"behind-the-net shot at x=%.1f must score 0" % x)
		assert_eq(AIGoalieModel.release_ahead_of_goalie(shooter, GOAL, goalie), shooter,
				"a behind-the-line release is not clamped into a phantom in-front spot")


func test_shoot_score_dead_from_beside_the_net() -> void:
	# From beside the net near the goal line the sightline to the far post runs
	# along the crease THROUGH the goalie's body — his depth occludes it (the
	# body-disc model). The old zero-depth cover left the far post "open" from
	# here, which is where the hopeless bad-angle fires came from. RVH/VH make
	# it worse, but even an upright keeper walls it with his body alone.
	var goalie := Vector3(0.8, 0.0, 26.3)
	for x: float in [3.0, 5.0, 7.0]:
		for fwd: float in [0.5, 1.0]:
			var shooter := Vector3(x, 0.0, GOAL.z - fwd)
			var s: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW, [])
			assert_lt(s, 0.02, "side-of-net x=%.1f fwd=%.1f is never a real chance" % [x, fwd])


func test_pass_score_zero_to_receiver_behind_goal_line() -> void:
	var shooter := Vector3(0.0, 0.0, 20.0)
	var receiver := Vector3(0.0, 0.0, 28.0)  # past attacking goal line
	var goalie := Vector3(0.0, 0.0, 26.0)
	var s: float = AIActionScoring.score_pass(shooter, receiver, GOAL, goalie, NET_HW,[])
	assert_eq(s, 0.0, "pass to receiver behind goal line should score 0")


func test_pass_score_falls_off_with_receiver_pressure() -> void:
	var shooter := Vector3(0.0, 0.0, 10.0)
	var receiver := Vector3(0.0, 0.0, 22.0)
	var goalie := Vector3(0.5, 0.0, 26.0)
	var clear: float = AIActionScoring.score_pass(shooter, receiver, GOAL, goalie, NET_HW,[])
	# Defender 2 m past the receiver (toward the attacking goal) and
	# 0.5 m off-axis — inside the receiver's forward pressure cone but
	# past the shooter→receiver segment so lane_clear isn't triggered.
	var checker: Array[Vector3] = [Vector3(0.5, 0.0, 24.0)]
	var pressured: float = AIActionScoring.score_pass(shooter, receiver, GOAL, goalie, NET_HW,checker)
	assert_lt(pressured, clear)


# Pressure cube-falloff sanity checks. The directional formula zeros
# opponents behind and beside the play, so shoot/pass scoring no
# longer counts defenders who can't realistically disrupt the action.

func test_shoot_pressure_ignores_defender_behind_shooter() -> void:
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 25.4)
	var clean: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,[])
	# Defender 2 m behind shooter (between shooter and own net).
	var behind: Array[Vector3] = [Vector3(0.5, 0.0, 19.0)]
	var pressured: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,behind)
	assert_almost_eq(pressured, clean, 0.001,
			"defender behind the shooter should not pressure the shot")


func test_shoot_pressure_ignores_perpendicular_defender() -> void:
	var shooter := Vector3(0.0, 0.0, 21.0)
	var goalie := Vector3(0.5, 0.0, 25.4)
	var clean: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,[])
	# Defender 2 m sideways at the same depth — directly perpendicular
	# to the shooter→goal axis. Cube weight = 0 (dot = 0).
	var perp: Array[Vector3] = [Vector3(2.0, 0.0, 21.0)]
	var pressured: float = AIActionScoring.score_shoot(shooter, GOAL, goalie, NET_HW,perp)
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
	var clean: float = AIActionScoring.score_pass(shooter, receiver, GOAL, goalie, NET_HW,[])
	var pressured: float = AIActionScoring.score_pass(shooter, receiver, GOAL, goalie, NET_HW,trailing)
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
	var s: float = AIActionScoring.score_pass(
			shooter, receiver, attacking_goal, goalie,
			NET_HW, [])
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


# ── Shot danger: the seven-hole model ────────────────────────────────────────
# score_shoot rates a shot by the best of the seven goalie holes (open_net_danger)
# — top/bottom corners, five-hole, armpits — each scored as the net it clears past
# the goalie's height-appropriate, reaction-gated cover; best_shot_loft returns the
# winning hole's elevation. Its shape over angle, range, keeper placement and
# traffic, and the calibrated values, are test_shot_danger_properties.gd.
# (GOAL at +Z; a lower goalie z = further OUT.)

func test_shot_danger_backdoor_tap_in_is_shot_flat() -> void:
	# A gaping open net low: no reason to elevate — bury it along the ice.
	var loft: int = AIActionScoring.best_shot_loft(
			Vector3(-0.8, 0.0, 25.5), GOAL, Vector3(0.85, 0.0, 25.45),
			NET_HW, AIBotMechanics.WRISTER_SHOT_SPEED_M_S)
	assert_eq(loft, ShotMechanics.ELEVATION_FLAT, "an open net gets buried flat")


func test_shot_danger_open_look_dwarfs_firing_into_a_set_goalie() -> void:
	# In tight nothing walls a placed shot (standing → quick-released, down →
	# roofed), so the honest comparison is against RANGE, where the wall is
	# real: the same open look dwarfs the direct shot once the keeper's
	# read + reach covers the flight.
	var open_s: float = AIActionScoring.score_shoot(
			Vector3(3.0, 0.0, 22.0), GOAL, Vector3(0.0, 0.0, 25.15), NET_HW, [])
	var ranged_s: float = AIActionScoring.score_shoot(
			Vector3(0.0, 0.0, 13.65), GOAL, Vector3(0.0, 0.0, 25.15), NET_HW, [])
	assert_gt(open_s, ranged_s, "an open net beats the covered ranged look")


func test_aim_spread_softens_the_window_to_a_partial_make() -> void:
	# Execution spread is part of shot SELECTION: the same window scores LOWER for
	# a noisier hand (its wobble eats the opening — monotonically with spread). But
	# a wobble comparable to or wider than the window no longer CLOSES it: the shot
	# is priced as a PARTIAL make (_soft_make_angle), so the bot still takes it and
	# gets saved on the shots that miss — instead of the old certain-make-only cut
	# that declined every shot the goalie could reach (and left the keeper without
	# a save to make). Window: the cross-seam look past a frozen centred goalie.
	# A sub-saturation window (the 8 m set-goalie knife cell) so the mapping's
	# gradient is visible — a wide-open look saturates to 1.0 for every hand,
	# which is correct and asserted elsewhere.
	var shooter := Vector3(0.0, 0.0, GOAL.z - 8.0)
	var goalie := Vector3(0.0, 0.0, GOAL.z - 1.15)
	var clean: float = AIActionScoring.score_shoot(
			shooter, GOAL, goalie, NET_HW, [], AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
			0.0, [], -1.0, false, 0.0, false, 0.0)
	var noisy: float = AIActionScoring.score_shoot(
			shooter, GOAL, goalie, NET_HW, [], AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
			0.0, [], -1.0, false, 0.0, false, 0.03)
	var wild: float = AIActionScoring.score_shoot(
			shooter, GOAL, goalie, NET_HW, [], AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
			0.0, [], -1.0, false, 0.0, false, 0.4)
	assert_gt(clean, noisy, "a noisier hand rates the same window lower")
	assert_gt(noisy, wild, "…and a wild hand lower still (monotonic in spread)")
	assert_gt(wild, 0.0,
			"a wobble wider than the window is a partial make, not a hard cut")
	assert_lt(wild, clean * 0.6,
			"…rated well below the clean look — a low-percentage shot, not a gimme")


func test_shot_danger_top_band_glove_race_in_tight_deploy_shuts_it_at_range() -> void:
	# In tight the glove can't extend, but no blade's steepest rung gets the
	# puck over a STANDING keeper's 0.86 m pad seam from 2.4 m: nobody roofs the
	# doorstep (docs/elevation-rework-plan.md §1), on any gear. A DOWN keeper's
	# pads are 0.28 m tall and his glove starts there, so over the pad is live.
	# At RANGE the puck's trip to his body covers the whole deploy and the set
	# glove shuts the band.
	var shooter := Vector3(0.0, 0.0, 24.25)    # 2.4 m
	var goalie := Vector3(0.0, 0.0, 25.9)
	var m28 := Vector3(tan(deg_to_rad(6.4)), tan(deg_to_rad(10.0)), tan(deg_to_rad(13.6)))
	var set_high: float = AIActionScoring._hole_open_angle(
			0, shooter, GOAL, goalie, NET_HW, 33.0, 0.0, -1.0, false, 0.0, false,
			0.0, 0.0, Vector4.INF, Vector4.INF, m28)
	var down_high: float = AIActionScoring._hole_open_angle(
			0, shooter, GOAL, goalie, NET_HW, 33.0, 0.0, -1.0, true)
	assert_almost_eq(set_high, 0.0, 0.0001,
			"even the toe hook can't roof a standing keeper from the doorstep")
	assert_gt(down_high, 0.0, "over a down keeper's pad is live in tight")
	var far_shooter := Vector3(0.0, 0.0, 15.65)    # 11 m
	var far_goalie := Vector3(0.0, 0.0, 25.15)     # 1.5 m challenge
	var far_high: float = AIActionScoring._hole_open_angle(
			0, far_shooter, GOAL, far_goalie, NET_HW, 33.0, 0.0)
	assert_almost_eq(far_high, 0.0, 0.0001,
			"at range the deploy beats the puck to his body — top band shut")


func test_point_blank_roof_is_live_over_a_down_goalie() -> void:
	# The contact-point identity shot: from 2 m over a butterflied goalie the
	# open toe's solved arc arrives top-shelf at full pace — the doorstep roof
	# the old fixed-vy model physically could not produce (its arc needed
	# ~0.25 s to rise above the pad-top seam). The keeper is DEEP (beaten to
	# his crease): dead on the shooter's nose his body-disc still occludes
	# the whole mouth from 2 m, which is the honest no-shot.
	var shooter := Vector3(0.0, 0.0, 24.65)    # 2 m
	var goalie := Vector3(0.0, 0.0, 25.9)
	var loft: int = AIActionScoring.best_shot_loft(
			shooter, GOAL, goalie, NET_HW, 33.0,
			0.0, 0.0, true)   # slide gap sealed — the roof is the way in
	assert_gte(loft, ShotMechanics.ELEVATION_MID,
			"the open toe roofs the butterfly from the doorstep")
	# With his slide gap leaking (caught mid-slide), the five-hole is the
	# wider, simpler hole and the finish stays flat — the tie-break at work.
	var leaky: int = AIActionScoring.best_shot_loft(
			shooter, GOAL, goalie, NET_HW, 33.0,
			0.0, GoalieBehaviorRules.five_hole_gap_m(true, 0.18), true)
	assert_eq(leaky, ShotMechanics.ELEVATION_FLAT,
			"a leaking five-hole out-simples the roof")


func test_high_band_is_a_rung_choice_per_ladder() -> void:
	# The roofing gradient IS the ladder (docs/elevation-rework-plan.md §1):
	# each gear's HIGH rung lands top-shelf at its own home range, nobody roofs
	# the 2 m doorstep, and from the point the league ladder's in-band rung is
	# MID, because HIGH would miss high and the band never lets the bot sail on
	# purpose.
	var gears: Array = [
		["M88", Vector3(5.0, 6.9, 8.9), 8.5],
		["M92", Vector3(5.5, 8.2, 11.0), 6.0],
		["M28", Vector3(6.4, 10.0, 13.6), 4.5],
	]
	for gear: Array in gears:
		var deg: Vector3 = gear[1]
		var tans := Vector3(tan(deg_to_rad(deg.x)), tan(deg_to_rad(deg.y)),
				tan(deg_to_rad(deg.z)))
		assert_eq(AIActionScoring._best_high_rung(2.0, 33.0, tans),
				ShotMechanics.ELEVATION_FLAT, "%s cannot roof the doorstep" % gear[0])
		assert_eq(AIActionScoring._best_high_rung(gear[2], 33.0, tans),
				ShotMechanics.ELEVATION_HIGH,
				"%s's toe rung is top-shelf at its home range" % gear[0])
	assert_eq(AIActionScoring._best_high_rung(15.0, 33.0),
			ShotMechanics.ELEVATION_MID,
			"from the point the league's top-shelf rung is the toe-side snipe")


func test_standing_keeper_on_top_bars_the_point_blank_roof() -> void:
	# Against a STANDING goalie right on the puck, even the toe rung crosses
	# his plane under the stick assembly (PADDLE_HEIGHT_M) — the paddle eats
	# it, so the band is closed and the finish stays flat. (Only the DOWN
	# goalie, paddle on the ice, concedes the doorstep roof.)
	var m28 := Vector3(0.14945, 0.34433, 0.53171)
	assert_eq(AIActionScoring._best_high_rung(2.0, 33.0, m28, 1.0),
			ShotMechanics.ELEVATION_FLAT, "standing keeper at 1 m: the paddle bars the roof")
	assert_ne(AIActionScoring._best_high_rung(2.0, 33.0, m28, 1.0, true),
			ShotMechanics.ELEVATION_FLAT, "the same look over a DOWN goalie is live")


func test_the_seal_only_takes_net_away_from_a_sharp_angle() -> void:
	# A ~70° wall look sits inside the predicted post seal (the live keeper's
	# RVH/VH zone), and threading the seal can only remove holes.
	var shooter := Vector3(7.0, 0.0, 24.0)
	var seal: float = AIGoalieModel.derive_post_seal_x_sign(shooter, GOAL)
	assert_ne(seal, 0.0, "premise: the ~70° look is inside the predicted post seal")
	var keeper := Vector3(0.9, 0.0, 25.05)
	var sealed: float = AIActionScoring.score_shoot(
			shooter, GOAL, keeper, NET_HW, [],
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, [], -1.0, false,
			seal, true)
	assert_lte(sealed, AIActionScoring.score_shoot(shooter, GOAL, keeper, NET_HW, []))


func test_shot_danger_unsettled_goalie_scores_higher() -> void:
	# Same geometry; an unsettled (mid-slide) goalie can't deploy his glove in
	# time, so the shot beats him more.
	# At the 8.5 m band the set look sits below saturation (the calibrated
	# knife cell), so the late-read credit is visible; in tight both reads
	# saturate to the certain look they really are.
	var shooter := Vector3(0.0, 0.0, 18.15)   # ~8.5 m
	var goalie := Vector3(0.0, 0.0, 25.5)
	var set_s: float = AIActionScoring.score_shoot(
			shooter, GOAL, goalie, NET_HW, [],
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0)
	var unsettled: float = AIActionScoring.score_shoot(
			shooter, GOAL, goalie, NET_HW, [],
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 1.0)
	assert_gt(unsettled, set_s, "a mid-slide goalie reads the shot late → higher danger")


func test_shot_aim_targets_the_open_side() -> void:
	# Off the strong side (+x) vs a centred goalie: the open net is the near side,
	# so the aim resolves to a point on that side of the net.
	var aim: Vector3 = AIActionScoring.best_shot_aim(
			Vector3(3.0, 0.0, 22.0), GOAL, Vector3(0.0, 0.0, 25.15),
			NET_HW, AIBotMechanics.WRISTER_SHOT_SPEED_M_S)
	assert_gt(aim.x, 0.0, "aim resolves to the open near side")
	assert_lt(absf(aim.x), NET_HW + 0.001, "aim stays inside the posts")
	assert_almost_eq(aim.z, GOAL.z, 0.001, "aim sits on the net plane")


func test_shot_aim_roofs_toward_a_post() -> void:
	# Down-goalie slot (five-hole sealed): the loft goes over the pad and the aim
	# is a CORNER (near a post), not dead centre — aim and loft describe the same
	# hole.
	var shooter := Vector3(0.0, 0.0, 23.15)   # 3.5 m
	var goalie := Vector3(0.0, 0.0, 25.05)
	var loft: int = AIActionScoring.best_shot_loft(
			shooter, GOAL, goalie, NET_HW, AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
			0.0, 0.0, true)
	var aim: Vector3 = AIActionScoring.best_shot_aim(
			shooter, GOAL, goalie, NET_HW, AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
			0.0, 0.0, true)
	assert_ne(loft, ShotMechanics.ELEVATION_FLAT, "the down goalie's opening is over the pad")
	assert_gt(absf(aim.x), 0.4, "...so the aim is a top corner, not the goalie's chest")


# ── in_offensive_zone ─────────────────────────────────────────────────────────
# The value-map regime boundary: the attacking blue line. Attacking GOAL at +Z, so
# the O-zone is z > BLUE_LINE_Z.

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


func test_shot_from_behind_goalie_is_not_a_phantom_open_net() -> void:
	# A shooter jammed dead-center just past the goalie used to read as an open net
	# (keeper modelled behind the shooter → danger 1.0). Clamped in front of him,
	# it's a point-blank jam into a set keeper — near zero, and far below a real
	# slot shot from the same centered line.
	var goalie := Vector3(0.0, 0.0, 24.65)
	var behind := Vector3(0.0, 0.0, 25.8)           # crease, dead center, past goalie
	var behind_danger: float = AIActionScoring.score_shoot(behind, GOAL, goalie, NET_HW, [])
	var slot := Vector3(0.0, 0.0, 20.65)            # real slot look, same line
	var slot_danger: float = AIActionScoring.score_shoot(slot, GOAL, goalie, NET_HW, [])
	assert_lte(behind_danger, slot_danger,
			"a jam from behind the goalie is not more dangerous than a slot shot")
	assert_lt(behind_danger, 0.2,
			"…it's a near-nothing point-blank jam, not a phantom open net")


# ── position_potential ───────────────────────────────────────────────────────
# position_potential models "value of being at this position" — used
# only when the evaluator is OUTSIDE shooting range (the regime rule
# in AICarrierField.value_at). Closeness peaks at the slot and ramps to 0 at the
# goal mouth (inside) and at the goal-to-goal rink length (outside).

func test_potential_zero_behind_goal_line() -> void:
	# Past the attacking goal line — no shooting potential. position_potential is
	# the raw geometric progression (no possession floor — that floor lives in the
	# offensive _score_at path, so the shared defensive threat_surface stays clean).
	var pos := Vector3(0.0, 0.0, 27.5)
	assert_eq(AIActionScoring.position_potential(pos, GOAL, []), 0.0)


func test_potential_zero_at_90_degrees_off_axis() -> void:
	# Pure perpendicular — angle factor zeros.
	var pos := Vector3(8.0, 0.0, 26.65)  # same z as goal
	assert_almost_eq(AIActionScoring.position_potential(pos, GOAL, []), 0.0, 0.01)


func test_potential_peaks_at_slot() -> void:
	# Slot position should score above any nearby non-slot position.
	var slot := Vector3(0.0, 0.0, 20.65)  # 6 m from goal — slot radius
	var deeper := Vector3(0.0, 0.0, 24.65)  # 2 m from goal — past slot
	var farther := Vector3(0.0, 0.0, 14.65)  # 12 m from goal — past slot outward
	var slot_v: float = AIActionScoring.position_potential(slot, GOAL, [])
	var deeper_v: float = AIActionScoring.position_potential(deeper, GOAL, [])
	var farther_v: float = AIActionScoring.position_potential(farther, GOAL, [])
	assert_gt(slot_v, deeper_v, "slot scores higher than past-slot toward goal")
	assert_gt(slot_v, farther_v, "slot scores higher than past-slot away from goal")


func test_potential_drops_inside_slot_toward_goal() -> void:
	# Closeness ramps DOWN inside slot — getting closer to the goal
	# than the slot doesn't keep increasing the position value.
	var slot := Vector3(0.0, 0.0, 20.65)   # 6 m from goal
	var crease := Vector3(0.0, 0.0, 25.65)  # 1 m from goal — in the crease
	assert_gt(
			AIActionScoring.position_potential(slot, GOAL, []),
			AIActionScoring.position_potential(crease, GOAL, []),
			"slot has higher potential than the crease (no carry-into-net pull)")


func test_potential_drops_with_far_distance() -> void:
	# Linear ramp on the outside — further from goal = lower potential.
	# Near OZ blue line vs deep DZ — both have full angle, no defenders.
	var oz_high := Vector3(0.0, 0.0, 5.0)    # ~22 m from goal
	var deep_dz := Vector3(0.0, 0.0, -20.0)  # ~46 m from goal
	assert_gt(
			AIActionScoring.position_potential(oz_high, GOAL, []),
			AIActionScoring.position_potential(deep_dz, GOAL, []),
			"closer to goal scores higher")


func test_potential_angle_is_goalmouth_projection() -> void:
	# The angle term is the goal mouth's projected width (cos of the bearing off
	# the goal normal), not a linear taper. Two positions the SAME distance (5 m)
	# from the goal — one head-on, one ~53° off (forward 3, lateral 4 → cos = 0.6)
	# — so closeness and openness match; only the projection differs. The off-axis
	# value must be the head-on value scaled by cos ≈ 0.6.
	var head_on := Vector3(0.0, 0.0, GOAL.z - 5.0)          # dist 5, cos 1
	var off_axis := Vector3(4.0, 0.0, GOAL.z - 3.0)         # dist 5, cos 0.6
	var head_v: float = AIActionScoring.position_potential(head_on, GOAL, [])
	var off_v: float = AIActionScoring.position_potential(off_axis, GOAL, [])
	assert_almost_eq(off_v, head_v * 0.6, 0.02,
			"off-axis value is the head-on value foreshortened by cos(θ)")


func test_potential_drops_with_pressure() -> void:
	# Forward-cone pressure cuts openness, dropping potential.
	var pos := Vector3(0.0, 0.0, 5.0)  # ~22 m from goal — outside shoot range
	var clean: float = AIActionScoring.position_potential(pos, GOAL, [])
	# Defender 2 m forward toward goal, on-axis.
	var pressured_opps: Array[Vector3] = [Vector3(0.0, 0.0, 7.0)]
	var pressured: float = AIActionScoring.position_potential(pos, GOAL, pressured_opps)
	assert_lt(pressured, clean, "forward-cone defender drops position potential")


# ── potential_realization_discount ───────────────────────────────────────────
# Potential is future value — it still has to be skated to the slot — so
# the carrier's compete discounts it over that remaining travel time.

func test_realization_discount_full_at_slot() -> void:
	# Inside the slot platform the promise is already real — no discount.
	var slot := Vector3(0.0, 0.0, 21.65)  # 5 m from goal, inside SLOT_RADIUS_M
	assert_eq(AIActionScoring.potential_realization_discount(slot, GOAL), 1.0)


func test_realization_discount_decays_with_distance() -> void:
	# Further from the slot = longer to realize = deeper discount.
	var near := Vector3(0.0, 0.0, 12.0)   # ~14.7 m from goal
	var far := Vector3(0.0, 0.0, -5.0)    # ~31.7 m from goal
	var near_d: float = AIActionScoring.potential_realization_discount(near, GOAL)
	var far_d: float = AIActionScoring.potential_realization_discount(far, GOAL)
	assert_lt(near_d, 1.0, "outside the slot the discount is real")
	assert_lt(far_d, near_d, "deeper positions pay a deeper discount")


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


func test_realization_discount_matches_delay_discount_currency() -> void:
	# The discount IS the standard delay discount over the remaining travel time
	# at reference speed — same currency (delay_discount) as every other future
	# action in the carrier's EV model.
	var pos := Vector3(0.0, 0.0, 8.65)  # 18 m from goal → 12 m past slot edge
	var expected: float = AIActionScoring.delay_discount(
			12.0 / AIArrival.SKATER_REF_SPEED_M_S)
	assert_almost_eq(
			AIActionScoring.potential_realization_discount(pos, GOAL),
			expected, 0.0001)


# ── Dumping: zone gates, chase race ───────────────────────────────────────────
# GOAL is at +Z, so the attacking side of centre is z > 0.

func test_past_center_toward_attack() -> void:
	assert_true(AIActionScoring.past_center_toward_attack(Vector3(0, 0, 5.0), GOAL))
	assert_false(AIActionScoring.past_center_toward_attack(Vector3(0, 0, -5.0), GOAL))
	assert_false(AIActionScoring.past_center_toward_attack(Vector3(0, 0, 0.0), GOAL),
			"exactly on centre is not past it")
	# Folds for the other attack direction.
	var neg_goal := Vector3(0, 0, -26.65)
	assert_true(AIActionScoring.past_center_toward_attack(Vector3(0, 0, -5.0), neg_goal))
	assert_false(AIActionScoring.past_center_toward_attack(Vector3(0, 0, 5.0), neg_goal))


func test_chase_recovery_race() -> void:
	var target := Vector3(10, 0, 20)
	# No chaser of ours → we never get it; no opponent → uncontested.
	assert_eq(AIActionScoring.chase_recovery(target, [], [Vector3(9, 0, 20)]), 0.0)
	assert_eq(AIActionScoring.chase_recovery(target, [Vector3(9, 0, 20)], []), 1.0)
	# Dead tie → coin flip.
	var tie: float = AIActionScoring.chase_recovery(
			target, [Vector3(7, 0, 20)], [Vector3(13, 0, 20)])   # both 3 m out
	assert_almost_eq(tie, 0.5, 1e-6)
	# We're a full contest-margin closer → near-certain.
	var ours: Array[Vector3] = [Vector3(10, 0, 20)]              # 0 m
	var theirs: Array[Vector3] = [Vector3(10, 0, 24)]           # 4 m = 2× margin
	assert_gt(AIActionScoring.chase_recovery(target, ours, theirs), 0.99)
	# They're closer → near-zero.
	assert_lt(AIActionScoring.chase_recovery(target, theirs, ours), 0.01)


func test_chase_recovery_races_arrivals_not_metres() -> void:
	# The race is won by whoever GETS there, which is not whoever is nearest: a
	# body 2 m closer but skating the other way has to shed its speed, turn, and
	# come back. Distance alone cannot see that, and over the 30-40 m a clear
	# travels it is the difference between a puck we recover and one we hand over.
	var target := Vector3(0, 0, 0)
	# Ours is FARTHER but already flying at the spot; theirs is nearer and leaving.
	var ours: Array[Vector3] = [Vector3(0, 0, 12)]
	var our_vels: Array[Vector3] = [Vector3(0, 0, -9)]
	var theirs: Array[Vector3] = [Vector3(0, 0, -10)]
	var their_vels: Array[Vector3] = [Vector3(0, 0, -9)]
	# On metres alone this is a race we lose outright (10 m vs 12 m — a
	# cruise-pace gap of exactly the contest band, so 0 to rounding).
	assert_almost_eq(AIActionScoring.chase_recovery(target, ours, theirs), 0.0, 1e-9,
			"the distance read hands it to the nearer body")
	assert_gt(AIActionScoring.chase_recovery(
			target, ours, theirs, our_vels, their_vels), 0.99,
			"...but we arrive first, so the arrival race gives it to us")
	# Symmetric: the same two bodies with the momentum swapped flips it back.
	assert_lt(AIActionScoring.chase_recovery(
			target, theirs, ours, their_vels, our_vels), 0.01)


func test_chase_recovery_without_velocities_races_from_rest() -> void:
	# Callers holding no velocities still get a real ramp rather than an instant
	# full-speed sprint, and the contest band is the same stride it always was —
	# CHASE_CONTEST_MARGIN_S is that stride's duration at reference pace, so a
	# standing race calibrates exactly where the metre form did.
	var target := Vector3(0, 0, 0)
	assert_almost_eq(AIActionScoring.chase_recovery(
			target, [Vector3(0, 0, 4)], [Vector3(0, 0, 4)]), 0.5, 1e-6,
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
	assert_gt(hard_curl, GameRules.DEFAULT_WRISTER_POWER_MIN_M_S + 5.0,
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
	var slow: float = AIActionScoring.score_pass(
			shooter, receiver, GOAL, goalie, NET_HW, in_lane,
			AIPuckLane.PASS_SPEED_M_S)
	var fast: float = AIActionScoring.score_pass(
			shooter, receiver, GOAL, goalie, NET_HW, in_lane,
			AIPuckLane.PASS_CHARGE_SPEED_M_S)
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
	var league: float = AIActionScoring.score_pass(
			shooter, receiver, GOAL, goalie, NET_HW, off_lane)
	var long_stick := AISkaterCaps.new()
	long_stick.stick_reach = 1.6
	long_stick.max_speed = 12.0
	var vs_long: float = AIActionScoring.score_pass(
			shooter, receiver, GOAL, goalie, NET_HW, off_lane,
			AIPuckLane.PASS_SPEED_M_S, 0.0, -1.0, Vector4.INF, Vector4.INF,
			[long_stick])
	var short_stick := AISkaterCaps.new()
	short_stick.stick_reach = 1.1
	short_stick.max_speed = 6.0
	var vs_short: float = AIActionScoring.score_pass(
			shooter, receiver, GOAL, goalie, NET_HW, off_lane,
			AIPuckLane.PASS_SPEED_M_S, 0.0, -1.0, Vector4.INF, Vector4.INF,
			[short_stick])
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


func test_threat_surface_pass_prices_defenders_by_build() -> void:
	# The defensive mirror of the per-build lane read: OUR defender's real
	# blade decides how much of the opponent's hypothetical feed we cover.
	# A long-stick fast defender deflates the threat below the league read;
	# a short slow one concedes more of it.
	# 2.0 m off the lane: partially inside the league blade's closing reach at
	# this feed's charged pace (the threat read must sit strictly below its
	# 1.0 saturation for the short stick to have headroom above it).
	var opp_carrier := Vector3(0.0, 0.0, 8.0)
	var opp_receiver := Vector3(0.0, 0.0, 22.0)
	var our_goalie := Vector3(0.5, 0.0, 26.0)
	var our_defender: Array[Vector3] = [Vector3(2.0, 0.0, 15.0)]
	var league: float = AIActionScoring.threat_surface_pass(
			opp_carrier, opp_receiver, GOAL, our_goalie, NET_HW, our_defender)
	var long_stick := AISkaterCaps.new()
	long_stick.stick_reach = 1.6
	long_stick.max_speed = 12.0
	var vs_long: float = AIActionScoring.threat_surface_pass(
			opp_carrier, opp_receiver, GOAL, our_goalie, NET_HW, our_defender,
			[long_stick])
	var short_stick := AISkaterCaps.new()
	short_stick.stick_reach = 1.1
	short_stick.max_speed = 6.0
	var vs_short: float = AIActionScoring.threat_surface_pass(
			opp_carrier, opp_receiver, GOAL, our_goalie, NET_HW, our_defender,
			[short_stick])
	assert_lt(vs_long, league,
			"a long-stick defender covers more of the opponent's feed")
	assert_gt(vs_short, league,
			"a short-stick defender concedes more of it")


func test_turnover_cost_prices_defenders_by_build() -> void:
	# Conceding the puck next to a long-stick defender costs less than the
	# league read says — his real blade contests the opponent's release and
	# lane; a short slow defender's does not.
	var loss_point := Vector3(0.0, 0.0, 20.0)
	var our_goalie := Vector3(0.0, 0.0, 25.9)
	# Inside the league blade's contest ring at the opponent's release point
	# (a carry-handle net-ward of the loss), outside the short stick's — the
	# same narrow ring the position_potential case pins.
	var our_defender: Array[Vector3] = [Vector3(1.4, 0.0, 20.9)]
	var league: float = AIActionScoring.turnover_cost(
			loss_point, 1.0, GOAL, our_goalie, NET_HW, our_defender)
	var long_fast := AISkaterCaps.new()
	long_fast.stick_reach = 1.6
	long_fast.max_speed = 12.0
	var vs_long: float = AIActionScoring.turnover_cost(
			loss_point, 1.0, GOAL, our_goalie, NET_HW, our_defender, [long_fast])
	var short_slow := AISkaterCaps.new()
	short_slow.stick_reach = 1.05
	short_slow.max_speed = 5.0
	var vs_short: float = AIActionScoring.turnover_cost(
			loss_point, 1.0, GOAL, our_goalie, NET_HW, our_defender, [short_slow])
	assert_lt(vs_long, league,
			"losing it next to a long-stick defender is cheaper than league")
	assert_gt(vs_short, league,
			"losing it next to a short-stick defender is dearer than league")


func test_position_potential_prices_contester_by_build() -> void:
	# Openness is the same release contest score_shoot runs, so a contesting
	# body's real blade decides how covered the spot reads: a long-stick fast
	# contester closes more of the windup than the league read, a short slow
	# one less.
	# The release point sits a carry-handle toward the goal (z = 15.9); the
	# windup window is short (~135 ms), so the build split lives in a narrow
	# ring: inside the league blade's contest reach (~1.55 m) but outside the
	# short stick's (~1.19 m).
	var pos := Vector3(0.0, 0.0, 15.0)
	var contester: Array[Vector3] = [Vector3(1.4, 0.0, 15.9)]
	var league: float = AIActionScoring.position_potential(pos, GOAL, contester)
	var long_fast := AISkaterCaps.new()
	long_fast.stick_reach = 1.6
	long_fast.max_speed = 12.0
	var vs_long: float = AIActionScoring.position_potential(
			pos, GOAL, contester, [long_fast])
	var short_slow := AISkaterCaps.new()
	short_slow.stick_reach = 1.05
	short_slow.max_speed = 5.0
	var vs_short: float = AIActionScoring.position_potential(
			pos, GOAL, contester, [short_slow])
	assert_lt(vs_long, league,
			"a long-stick fast contester covers more of the spot's release")
	assert_gt(vs_short, league,
			"a short slow contester covers less of it")


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
	# The airborne carry scales with launch speed: a defender ~8.5 m out is
	# still under the crisp flip (in the air at charge pace) but past the
	# SOFT flip's touch-down — the soft flip has landed and gets blocked.
	# This is the physical trade the close-quarters saucer makes: softer
	# pace buys a receivable landing, at the cost of clearing less lane.
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(0.0, 0.0, 12.0)
	var mid_stick: Array[Vector3] = [Vector3(0.5, 0.0, 8.5)]
	var crisp: float = AIPuckLane.lane_clear_saucer(from, to, mid_stick, AIPuckLane.PASS_CHARGE_SPEED_M_S)
	var soft: float = AIPuckLane.lane_clear_saucer(from, to, mid_stick, 12.0)
	assert_almost_eq(crisp, 1.0, 0.0001, "crisp flip is still airborne over the 8.5 m defender")
	assert_lt(soft, crisp, "the soft flip has landed by 8.5 m — the defender blocks it")


func test_saucer_max_launch_speed_bounds_receivable_flips() -> void:
	# The receivability bound: launch × hang time + landing run must fit
	# inside the pass distance. At the bound the flip lands exactly a
	# landing-run short of the tape; below the soft-touch wrister floor
	# (~6.5 m feeds and shorter) no legal saucer exists.
	var bound: float = AIPuckLane.saucer_max_launch_speed(10.0)
	assert_almost_eq(
			AIPuckLane.saucer_airborne_distance_m(bound)
					+ AIPuckLane.SAUCER_LANDING_RUN_M,
			10.0, 0.0001,
			"at the bound the flip lands exactly a landing-run before the tape")
	assert_gt(AIPuckLane.saucer_max_launch_speed(7.0),
			GameRules.DEFAULT_WRISTER_POWER_MIN_M_S,
			"a 7 m feed still admits a soft saucer above the wrister floor")
	assert_lt(AIPuckLane.saucer_max_launch_speed(6.0),
			GameRules.DEFAULT_WRISTER_POWER_MIN_M_S,
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


# ── turnover_cost: defensive half of the carrier EV ──────────────────────────
# cost = loss_prob × threat_surface_shoot(loss_point → our net). Zero
# when there's nothing to lose; scales with both probability and how
# dangerous the steal location is, which self-localizes by geometry.

const OUR_NET := Vector3(0.0, 0.0, 26.65)        # we defend +Z
const OUR_GOALIE := Vector3(0.0, 0.0, 26.0)


func test_turnover_cost_zero_when_no_loss_point() -> void:
	var c: float = AIActionScoring.turnover_cost(
			Vector3.INF, 0.5, OUR_NET, OUR_GOALIE, NET_HW, [])
	assert_eq(c, 0.0, "no interception point → no turnover cost")


func test_turnover_cost_zero_when_no_loss_prob() -> void:
	var loss := Vector3(0.0, 0.0, 21.0)  # dangerous spot, but...
	var c: float = AIActionScoring.turnover_cost(
			loss, 0.0, OUR_NET, OUR_GOALIE, NET_HW, [])
	assert_eq(c, 0.0, "zero loss probability → no turnover cost")


func test_turnover_cost_scales_with_loss_probability() -> void:
	var loss := Vector3(0.0, 0.0, 21.0)  # in our slot, in front of our net
	var low: float = AIActionScoring.turnover_cost(
			loss, 0.2, OUR_NET, OUR_GOALIE, NET_HW, [])
	var high: float = AIActionScoring.turnover_cost(
			loss, 0.8, OUR_NET, OUR_GOALIE, NET_HW, [])
	assert_gt(high, low, "higher interception probability → higher turnover cost")


func test_turnover_cost_self_localizes_by_geometry() -> void:
	# Same loss probability: a steal in our slot must cost far more than
	# one out by our blue line / center ice — this is the "no zone flag"
	# property. threat_surface_shoot toward our net does the localizing.
	var in_slot := Vector3(0.0, 0.0, 21.0)       # ~5.6 m from our net
	var far_out := Vector3(0.0, 0.0, 2.0)        # near center ice
	var slot_cost: float = AIActionScoring.turnover_cost(
			in_slot, 0.5, OUR_NET, OUR_GOALIE, NET_HW, [])
	var far_cost: float = AIActionScoring.turnover_cost(
			far_out, 0.5, OUR_NET, OUR_GOALIE, NET_HW, [])
	assert_gt(slot_cost, far_cost,
			"own-zone turnover costs more than a neutral-ice one at equal probability")


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
	# risk term punish own-zone touch-passes without taxing OZ passing.
	var own_end_loss: Vector3 = AIPuckLane.pass_miss_loss_point(
			Vector3(2.0, 0.0, 20.0), Vector3(-2.0, 0.0, 23.0))
	var opp_end_loss: Vector3 = AIPuckLane.pass_miss_loss_point(
			Vector3(2.0, 0.0, -20.0), Vector3(-2.0, 0.0, -23.0))
	var own_end_cost: float = AIActionScoring.turnover_cost(
			own_end_loss, AIPuckLane.PASS_MISS_BASE_PROB, OUR_NET, OUR_GOALIE, NET_HW, [])
	var opp_end_cost: float = AIActionScoring.turnover_cost(
			opp_end_loss, AIPuckLane.PASS_MISS_BASE_PROB, OUR_NET, OUR_GOALIE, NET_HW, [])
	assert_gt(own_end_cost, opp_end_cost * 4.0,
			"a missed pass in our own end costs multiples of the same miss in theirs")


# ─── Stance-aware five-hole (measured slot from the replicated pose) ──────

func test_five_hole_scores_only_the_clearance_past_the_puck() -> void:
	# The five-hole pays the puck's own diameter, same honesty the corners pay
	# via the clean-entry inset: a down-goalie slide leak WIDER than the puck is
	# the live five-hole; a gap the puck can't fit through scores exactly 0.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(0, 0, -22.65)
	var goalie := Vector3(0, 0, -24.9)
	var wide_leak: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0,
			GoalieBehaviorRules.five_hole_gap_m(true, 0.18), true)   # 0.36 m
	var thin_leak: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0,
			GoalieBehaviorRules.five_hole_gap_m(true, 0.10), true)   # 0.20 m
	var no_fit: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0,
			2.0 * GameRules.PUCK_COLLISION_RADIUS - 0.01, true)      # narrower than the puck
	var five_disabled: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0, 0.0, true)
	assert_gt(wide_leak, thin_leak, "a wider slide leak is a bigger five-hole")
	assert_almost_eq(no_fit, five_disabled, 0.001,
			"a gap the puck cannot fit through contributes nothing (only corners remain)")


func test_five_hole_pays_the_execution_spread() -> void:
	# The five-hole pays the shooter's execution spread exactly as the corners
	# do (via _soft_make_angle): a razor slot a noisy hand can barely thread
	# scores LOWER (so it can't out-score a wider corner via the flat-loft
	# tie-break — the "five-hole happy" bug), and a wobble wider than the slot
	# softens it to a low-percentage partial make rather than a hard zero.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(0, 0, -23.65)
	var goalie := Vector3(0, 0, -24.9)
	var gap: float = GoalieBehaviorRules.five_hole_gap_m(false, 0.02)
	var clean: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0,
			gap, false, 0.0, false, 0.0)
	var noisy: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0,
			gap, false, 0.0, false, 0.02)
	assert_gt(clean, noisy, "a noisier hand rates the same slot lower")
	var wild: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0,
			gap, false, 0.0, false, 0.2)
	assert_gt(noisy, wild, "a wilder hand rates the razor slot lower still")
	assert_lt(wild, clean * 0.5,
			"a wobble wider than the slot leaves only a low-percentage partial make")


func test_standing_five_hole_sealed_from_range() -> void:
	# Same slot from 12 m: flight ~0.36 s ≫ legs delay + pads-to-floor — the
	# goalie reads the release and drops; the slot is gone when the puck arrives.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(0, 0, -14.65)
	var goalie := Vector3(0, 0, -24.9)
	var gap: float = GoalieBehaviorRules.five_hole_gap_m(false, 0.02)
	var angle: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0, gap, false)
	# From range the corners re-open (long flight buys arm reach... inverse) —
	# assert specifically that the FIVE hole contributes nothing: compare with
	# gap 0 (five disabled) — identical means the slot was sealed.
	var no_five: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0, 0.0, false)
	assert_almost_eq(angle, no_five, 0.001,
			"from range the drop seals the slot before the puck arrives")


func test_down_goalie_five_hole_is_the_slide_leak() -> void:
	# A goalie mid-slide (down, openness 0.18) leaks the measured 0.36 m gap —
	# and being down there is no further drop to seal it with. In tight (4 m,
	# goalie challenging) the leak out-scores the walled-off corners, so the
	# best-hole read rises above the no-leak baseline.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(0, 0, -22.65)
	var goalie := Vector3(0, 0, -24.9)
	var gap: float = GoalieBehaviorRules.five_hole_gap_m(true, 0.18)
	var with_leak: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0, gap, true)
	var sealed: float = AIActionScoring.open_net_danger(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0, 0.0, true)
	assert_gt(with_leak, sealed,
			"a mid-slide leak is a real five-hole in tight")


# ─── Predicted post-seal (the "one model, consistent inputs" fix) ──────────────

func test_derive_post_seal_only_fires_in_the_sharp_near_line_zone() -> void:
	# The predictor matches the live goalie's RVH/VH trigger: within ~2 m of the
	# goal line AND past ~80° off the goal normal. A dead-angle corner seals; a
	# normal slot / mid look does not; a sharp-but-in-tight shot still short of the
	# extreme angle does not.
	var goal := Vector3(0, 0, -26.65)
	assert_ne(AIGoalieModel.derive_post_seal_x_sign(Vector3(8, 0, -25.5), goal), 0.0,
			"dead-angle corner (1.15 m out, ~82°) is sealed")
	assert_eq(AIGoalieModel.derive_post_seal_x_sign(Vector3(0, 0, -20.65), goal), 0.0,
			"the slot is never sealed")
	assert_eq(AIGoalieModel.derive_post_seal_x_sign(Vector3(7, 0, -18.0), goal), 0.0,
			"an off-angle mid look (8.6 m out) is not sealed")
	assert_eq(AIGoalieModel.derive_post_seal_x_sign(Vector3(4, 0, -24.0), goal), 0.0,
			"a sharp but in-tight look (2.65 m out, ~56°) is a real shot, not a seal")
	# The seal side is the shooter's side of the goal center.
	assert_eq(AIGoalieModel.derive_post_seal_x_sign(Vector3(-8, 0, -25.5), goal), -1.0,
			"seals the side the shooter is on")


func test_predicted_seal_kills_the_phantom_dead_angle_shot() -> void:
	# The bug: a carry candidate / receiver at the dead-angle corner scored a
	# phantom far-side open net (the predictive path fed score_shoot an unsealed
	# keeper), so a bot would carry there and never shoot. With the predicted seal
	# threaded, the same model reads the wall the live keeper actually adopts.
	var goal := Vector3(0, 0, -26.65)
	var corner := Vector3(8, 0, -25.5)
	var goalie: Vector3 = AIGoalieModel.goalie_squared_pos(
			Vector3(0, 0, goal.z + 1.3), goal, corner)
	var seal: float = AIGoalieModel.derive_post_seal_x_sign(corner, goal)
	var unsealed: float = AIActionScoring.score_shoot(
			corner, goal, goalie, GameRules.NET_HALF_WIDTH, [] as Array[Vector3])
	var sealed: float = AIActionScoring.score_shoot(
			corner, goal, goalie, GameRules.NET_HALF_WIDTH, [] as Array[Vector3],
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, [], -1.0, false, seal, seal != 0.0)
	assert_gt(unsealed, 0.05, "sanity: the unsealed read is the phantom the bug scored")
	assert_almost_eq(sealed, 0.0, 0.001, "the predicted seal walls the dead-angle look")


func test_score_pass_walls_a_dead_angle_receiver() -> void:
	# The seal predictor now lives inside score_pass too, so every predictive pass
	# read (defensive threat surfaces, off-puck staging, developing feeds) walls a
	# feed to the dead-angle wraparound instead of crediting the phantom open net.
	# A slot receiver on an equally clear lane stays a real feed.
	var shooter := Vector3(6, 0, 20.0)
	var corner := Vector3(8, 0, 25.5)      # dead angle, in the seal zone
	var slot := Vector3(0, 0, 20.65)       # a real look
	var g_corner: Vector3 = AIGoalieModel.goalie_squared_pos(
			Vector3(0, 0, GOAL.z - 1.3), GOAL, corner)
	var g_slot: Vector3 = AIGoalieModel.goalie_squared_pos(
			Vector3(0, 0, GOAL.z - 1.3), GOAL, slot)
	var no_opps: Array[Vector3] = []
	assert_almost_eq(AIActionScoring.score_pass(
			shooter, corner, GOAL, g_corner, GameRules.NET_HALF_WIDTH, no_opps),
			0.0, 0.001, "the dead-angle feed is walled by the seal")
	assert_gt(AIActionScoring.score_pass(
			shooter, slot, GOAL, g_slot, GameRules.NET_HALF_WIDTH, no_opps),
			0.05, "the slot feed on an equally clear lane is a real threat")


func test_threat_surface_shoot_seals_a_dead_angle_opponent() -> void:
	# Defensive symmetry: an opponent at the dead-angle wraparound of OUR net is
	# walled by our keeper, so the threat surface reads the seal too. At this spot
	# the unsealed phantom shot (~0.29) dominates the positional read (~0.14) — so
	# without the seal our defenders would over-respect a shot the keeper has
	# already sealed. Sealed, only the positional fallback remains.
	var opp := Vector3(5, 0, 25.8)         # in the seal zone, phantom-dominant
	var g: Vector3 = AIGoalieModel.goalie_squared_pos(
			Vector3(0, 0, GOAL.z - 1.3), GOAL, opp)
	var no_opps: Array[Vector3] = []
	var unsealed_shot: float = AIActionScoring.score_shoot(
			opp, GOAL, g, GameRules.NET_HALF_WIDTH, no_opps)
	var positional: float = AIActionScoring.position_potential(opp, GOAL, no_opps)
	var surface: float = AIActionScoring.threat_surface_shoot(
			opp, GOAL, g, GameRules.NET_HALF_WIDTH, no_opps)
	assert_gt(unsealed_shot, positional,
			"sanity: unsealed, the phantom shot dominates the positional read here")
	assert_almost_eq(surface, positional, 0.001,
			"sealed → the phantom shot is gone, only the positional fallback remains")


# ─── Post-seal stances (VH / RVH) — the pose IS the coverage ───────────────

func test_vh_seal_closes_short_side_high() -> void:
	# Short-side HIGH vs a goalie AT his post: his body-reach cover alone
	# leaves a slice over the shoulder — the RVH weakness — and closing it is
	# VH's whole reason to exist. Sealed-tall reads 0; RVH (not tall) keeps
	# the same measured opening the bare read gives. The look rides an EASED
	# MID (19 m/s): at ~4.35 m the M92 ladder's full-pace arcs all miss the
	# band (the documented mid-range gap), and the seal's structure is
	# pace-independent — what the deployed wall covers, not a race.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(3.0, 0, -23.5)
	var goalie := Vector3(0.5, 0, -26.2)
	var high_near: int = 1   # HIGH band, +x side — the seal side for this shooter
	var bare: float = AIActionScoring._hole_open_angle(
			high_near, shooter, goal, goalie, GameRules.NET_HALF_WIDTH,
			19.0, 0.0, -1.0, true)
	assert_gt(bare, 0.0, "sanity: body reach alone leaves short-side high open")
	var vh: float = AIActionScoring._hole_open_angle(
			high_near, shooter, goal, goalie, GameRules.NET_HALF_WIDTH,
			19.0, 0.0, -1.0, true, 1.0, true)
	assert_eq(vh, 0.0, "VH walls the whole near column — no short-side high")
	var rvh: float = AIActionScoring._hole_open_angle(
			high_near, shooter, goal, goalie, GameRules.NET_HALF_WIDTH,
			19.0, 0.0, -1.0, true, 1.0, false)
	assert_eq(rvh, bare, "RVH stays compressed — short-side high stays measured")


func test_post_seal_closes_five_hole_and_near_low() -> void:
	# Between-the-legs is closed in BOTH post-seal families (back pad + the
	# post-sealed pad close the ice slot), and the near-post LOW column is
	# gone in both too.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(1.0, 0, -23.9)
	var goalie := Vector3(0.6, 0, -26.3)
	var gap: float = GoalieBehaviorRules.five_hole_gap_m(true, 0.18)  # slide leak
	var five_bare: float = AIActionScoring._hole_open_angle(
			4, shooter, goal, goalie, GameRules.NET_HALF_WIDTH,
			33.0, 0.0, gap, true)
	assert_gt(five_bare, 0.0, "sanity: a mid-slide leak is a real five-hole read")
	var five_rvh: float = AIActionScoring._hole_open_angle(
			4, shooter, goal, goalie, GameRules.NET_HALF_WIDTH,
			33.0, 0.0, gap, true, 1.0, false)
	assert_eq(five_rvh, 0.0, "the post-seal back pad closes the slot")
	var low_vh: float = AIActionScoring._hole_open_angle(
			3, shooter, goal, goalie, GameRules.NET_HALF_WIDTH,
			33.0, 0.0, -1.0, true, 1.0, true)
	assert_eq(low_vh, 0.0, "near-post low is sealed")


func test_vh_seal_aims_the_far_corner_not_the_wall() -> void:
	# From the seal side the only surviving look is the thin cross-net window
	# at the far post — the chosen aim must sit in the far half, never on the
	# walled-off short side. ("Never fire into the VH wall.") The shooter sits a
	# couple of strides off the goal line: right ON the line the goalie's body
	# depth occludes even the far post and nothing is open at all.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(4.5, 0, -24.0)
	var goalie := Vector3(0.85, 0, -26.55)   # parked at the +x post, VH
	var aim: Vector3 = AIActionScoring.best_shot_aim(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0,
			0.0, -1.0, true, 0.0, 1.0, true)
	assert_lt(aim.x, 0.0, "the only look vs VH is across — aim sits in the far half")


# ─── Post-clearance aim clamp ─────────────────────────────────────────────

func test_hole_aim_never_targets_the_post_band() -> void:
	# Goalie shades hard to one side leaving a sliver at the far post — the aim
	# must stay inside the puck-entry line (post radius + puck radius inside the
	# post centerline), never on the pipe itself.
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(0, 0, -20.65)
	var goalie := Vector3(0.8, 0, -25.3)  # shaded far to +X
	var aim: Vector3 = AIActionScoring.best_shot_aim(
			shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0)
	assert_lte(absf(aim.x), GameRules.NET_ENTRY_HALF_WIDTH + 0.0001,
			"aim stays inside the clean-entry line; got x=%f" % aim.x)


# ─── Arc-radius clamp (no goalie off the cage) ────────────────────────────

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

func test_aim_spread_pulls_a_degenerate_corner_aim_off_the_post() -> void:
	# A noisy hand budgets its own wobble inside the entry line. Exercised on
	# the hole-aim primitive directly: a goalie hugging the left post collapses
	# the left corner's open segment onto the post itself; the physical entry
	# clamp pulls the aim to the clean-entry line, and a nonzero spread pulls
	# it a further spread × range inside so the wobble can't reach the iron.
	# (Chosen corner aims normally sit well off the post via the corner bias —
	# the clamp is the backstop for degenerate slivers.)
	var goal := Vector3(0, 0, -26.65)
	var shooter := Vector3(0, 0, -22.65)   # 4 m out, dead center
	var goalie := Vector3(-0.8, 0, -25.6)  # hugging the left post
	var exact: float = AIActionScoring._hole_aim_x(
			2, shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0)
	assert_almost_eq(exact, -GameRules.NET_ENTRY_HALF_WIDTH, 0.001,
			"degenerate left-corner aim rides the physical entry clamp")
	var spread: float = 0.01   # rad — ~0.02 m cursor noise on the 2 m aim arm
	var noisy: float = AIActionScoring._hole_aim_x(
			2, shooter, goal, goalie, GameRules.NET_HALF_WIDTH, 33.0, 0.0, spread)
	assert_almost_eq(noisy, exact + spread * shooter.distance_to(goal), 0.01,
			"spread inset pulls the clamped aim inside by spread × range")


# ─── Screen perception (sightline occlusion) ──────────────────────────────

# Shared fixture: a point-range shooter against a set, centred, challenged
# goalie. The screen tests move ONE body around the sightline; they pass it
# through `screeners` (the shooter's own traffic) so lane/pressure stay
# constant and the sightline effect is isolated.
func _screened_point_shot(screeners: Array[Vector3]) -> float:
	var shooter := Vector3(0.0, 0.0, 10.0)   # 16.65 m out — the point
	var goalie := Vector3(0.0, 0.0, 25.5)    # set, challenged ~1.15 m
	return AIActionScoring.score_shoot(
			shooter, GOAL, goalie, NET_HW, [],
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0, [], -1.0, false,
			0.0, false, 0.0, screeners)


func test_body_off_the_sightline_does_not_screen() -> void:
	# Same depth as the deadly screen, 1.5 m off the shooter→goalie line: the
	# goalie sees the release the whole way — identical score to the clean look.
	var clean: float = _screened_point_shot([])
	var off_line: float = _screened_point_shot([Vector3(1.5, 0.0, 24.0)])
	assert_almost_eq(off_line, clean, 0.0000001,
			"an off-line body changes nothing")


# ─── Shoot-for-tip EV (the deflection play) ────────────────────────────────

func _tip_fixture(tip_man: Vector3, pace: float,
		defenders: Array[Vector3]) -> float:
	# Point release, set challenged goalie — the same look the screen tests
	# use, now with a body to deflect off.
	return AIActionScoring.tip_ev(
			Vector3(0.0, 0.0, 10.0), tip_man, GOAL,
			Vector3(0.0, 0.0, 25.5), NET_HW, defenders, pace)


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


# ── Hole-model v3: the HIGH band reads the replicated hands ──────────────────
# Pose numbers cited from GoalieBodyConfigBuilder: READY glove (−0.42, 0.90),
# blocker (0.44, 0.86); butterfly drops both to y ≈ 0.44. GOAL here is +z, so
# net_dx = local_x (hands_read's m = +1).

const HANDS_READY := Vector4(-0.42, 0.90, 0.44, 0.86)
const HANDS_BUTTERFLY := Vector4(-0.42, 0.44, 0.44, 0.44)


func test_ready_hands_reproduce_the_legacy_high_cover() -> void:
	# The resting stance parks the hands at ~the torso edge inside the band —
	# the pose path must degenerate to the legacy deploy there (no static
	# armpit hole the stance actually covers).
	var spread: float = BotSkillProfile.hard().shot_aim_error_rad
	for dist: float in [5.0, 9.0, 14.0]:
		var shooter := Vector3(0.0, 0.0, GOAL.z - dist)
		var goalie := Vector3(0.0, 0.0, GOAL.z - 1.2)
		var legacy: float = AIActionScoring.open_net_danger(
				shooter, GOAL, goalie, NET_HW,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0,
				-1.0, false, 0.0, false, spread)
		var posed: float = AIActionScoring.open_net_danger(
				shooter, GOAL, goalie, NET_HW,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0,
				-1.0, false, 0.0, false, spread, 0.0, HANDS_READY)
		assert_almost_eq(posed, legacy, 0.12,
				"READY pose ≈ legacy cover at %.0f m (posed %.3f legacy %.3f)"
				% [dist, posed, legacy])


func test_committed_glove_side_covers_and_vacates_correctly() -> void:
	# Glove dragged WIDE toward net-left (a committed reach): its side's high
	# corner is covered sooner, and the vacated right side (blocker parked
	# low) opens — per-side asymmetry the band aggregate could never see.
	var shooter := Vector3(0.0, 0.0, GOAL.z - 6.0)   # the league toe rung's home range
	var goalie := Vector3(0.0, 0.0, GOAL.z - 1.2)
	var committed_left := Vector4(-0.80, 0.95, 0.44, 0.40)  # glove wide-left, blocker low
	var left_open: float = AIActionScoring._hole_open_angle(
			0, shooter, GOAL, goalie, NET_HW,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0,
			-1.0, false, 0.0, false, 0.0, 0.0, committed_left)
	var right_open: float = AIActionScoring._hole_open_angle(
			1, shooter, GOAL, goalie, NET_HW,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0,
			-1.0, false, 0.0, false, 0.0, 0.0, committed_left)
	assert_lt(left_open, right_open,
			"the committed glove walls its side; the low blocker's side opens"
			+ " (L %.4f vs R %.4f)" % [left_open, right_open])


# ── Hole-model v3: the LOW band reads the replicated pads ────────────────────
# Standing pads local ±0.22 at ~12° roll; butterfly ±0.42 rolled 90° flat
# (GoalieBodyConfigBuilder). GOAL is +z here → net_dx = local_x.

const PADS_STANDING := Vector4(-0.22, -0.209, 0.22, 0.209)
const PADS_BUTTERFLY := Vector4(-0.42, -PI * 0.5, 0.42, PI * 0.5)


func test_ready_pads_reproduce_the_legacy_low_cover() -> void:
	var spread: float = BotSkillProfile.hard().shot_aim_error_rad
	for dist: float in [5.0, 9.0, 14.0]:
		var shooter := Vector3(0.0, 0.0, GOAL.z - dist)
		var goalie := Vector3(0.0, 0.0, GOAL.z - 1.2)
		var legacy: float = AIActionScoring.open_net_danger(
				shooter, GOAL, goalie, NET_HW,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0,
				-1.0, false, 0.0, false, spread)
		var posed: float = AIActionScoring.open_net_danger(
				shooter, GOAL, goalie, NET_HW,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0,
				-1.0, false, 0.0, false, spread, 0.0,
				HANDS_READY, PADS_STANDING)
		assert_almost_eq(posed, legacy, 0.15,
				"standing pads ≈ legacy LOW at %.0f m (posed %.3f legacy %.3f)"
				% [dist, posed, legacy])


func test_butterfly_pads_measure_the_full_splay() -> void:
	# A DOWN goalie's measured splayed pads equal the declared butterfly
	# edge exactly (0.42 offset + 0.42 rolled-flat half-length = 0.84). The
	# hands stay at their default on both sides, so only the pads differ.
	var spread: float = BotSkillProfile.hard().shot_aim_error_rad
	var shooter := Vector3(0.0, 0.0, GOAL.z - 8.0)
	var goalie := Vector3(0.0, 0.0, GOAL.z - 1.2)
	var legacy: float = AIActionScoring.open_net_danger(
			shooter, GOAL, goalie, NET_HW,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0,
			-1.0, true, 0.0, false, spread)
	var posed: float = AIActionScoring.open_net_danger(
			shooter, GOAL, goalie, NET_HW,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.0,
			-1.0, true, 0.0, false, spread, 0.0,
			Vector4.INF, PADS_BUTTERFLY)
	assert_almost_eq(posed, legacy, 0.1,
			"butterfly measurement = the declared splay (posed %.3f legacy %.3f)"
			% [posed, legacy])


func test_slid_pads_open_the_vacated_low_corner() -> void:
	# The goalie mid-slide toward net-left: both pads carried left of
	# center. His left low corner is walled beyond the stance; the vacated
	# right low corner opens — asymmetry the declared symmetric core could
	# never see (the cross-crease slide leak, measured).
	var shooter := Vector3(0.0, 0.0, GOAL.z - 6.0)
	var goalie := Vector3(-0.3, 0.0, GOAL.z - 1.2)
	var slid_left := Vector4(-0.75, -PI * 0.5, -0.05, -PI * 0.5)
	var left_low: float = AIActionScoring._hole_open_angle(
			2, shooter, GOAL, goalie, NET_HW,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.6,
			-1.0, true, 0.0, false, 0.0, 0.0, Vector4.INF, slid_left)
	var right_low: float = AIActionScoring._hole_open_angle(
			3, shooter, GOAL, goalie, NET_HW,
			AIBotMechanics.WRISTER_SHOT_SPEED_M_S, 0.6,
			-1.0, true, 0.0, false, 0.0, 0.0, Vector4.INF, slid_left)
	assert_lt(left_low, right_low,
			"the slide walls its side low and vacates the other (L %.4f R %.4f)"
			% [left_low, right_low])


func test_predicted_hands_sink_when_unsettled() -> void:
	# The pre-arm rebuild seam: a keeper predicted to be moving at release
	# is scored against hands at the sliding pose height, not the presented
	# stance — the unsettled body's partial silhouette, measured.
	var set_hands: Vector4 = AIGoalieModel.predicted_goalie_hands(HANDS_READY, 0.0)
	assert_almost_eq(set_hands.y, HANDS_READY.y, 0.001, "a set keeper keeps his stance")
	var moving: Vector4 = AIGoalieModel.predicted_goalie_hands(HANDS_READY, 1.0)
	assert_almost_eq(moving.y, AIGoalieModel.SLIDING_HANDS_Y_M, 0.001,
			"a fully caught-moving keeper's glove rides at the slide height")
	assert_almost_eq(moving.x, HANDS_READY.x, 0.001, "laterals travel with the body")
	assert_false(AIGoalieModel.predicted_goalie_hands(Vector4.INF, 1.0).is_finite(),
			"absent pose passes through")


# XG_SLOT_REF converts in-zone xG into position_potential's unit, so it must be
# the xG of exactly the situation potential reads as 1.0: the slot ring, head-on,
# nothing in the way, a set keeper.
func test_xg_slot_ref_is_the_xg_of_potentials_full_value() -> void:
	var goal := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var ring := Vector3(0.0, 0.0, goal.z + AIActionScoring.SLOT_RADIUS_M)
	var none: Array[Vector3] = []
	assert_almost_eq(AIActionScoring.position_potential(ring, goal, none), 1.0, 0.0001,
			"potential's full value sits on the slot ring, head-on")
	assert_almost_eq(AIActionScoring.potential_realization_discount(ring, goal), 1.0, 0.0001,
			"…with nothing left to skate")
	assert_almost_eq(AIActionScoring.XG_SLOT_REF,
			AIShotValue.set_keeper(ring, goal), 0.000001,
			"XG_SLOT_REF is the odds of that same look")
	assert_gt(AIActionScoring.XG_SLOT_REF, 0.0, "and it is a real number, not the unset default")


# turnover_cost(in_xg) skips the opponent's shot read outside our zone with the
# keeper home, on the claim that his shot xG beats his possession promise there by
# no more than a long shot's logistic tail. Swept across both outer zones.
func test_in_xg_turnover_shot_skip_is_safe() -> void:
	var our_net := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)
	var keeper := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z - 0.8)
	var none: Array[Vector3] = []
	var worst: float = INF
	for x: float in [-11.0, -6.0, 0.0, 6.0, 11.0]:
		for z: float in [-24.0, -15.0, -6.0, 0.0, 4.0, 7.0]:
			var spot := Vector3(x, 0.0, z)
			var promise: float = AIActionScoring.position_potential(spot, our_net, none) \
					* AIActionScoring.potential_realization_discount(spot, our_net) \
					* AIActionScoring.XG_SLOT_REF
			var shot: float = AIActionScoring.score_shoot_value(spot, our_net, keeper, none)
			worst = minf(worst, promise - shot)
	assert_gte(worst, -0.005,
			"outside our zone the shot never beats the possession promise by more than a tail (worst %.4f)"
			% worst)

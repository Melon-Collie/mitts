extends GutTest

# AIRoleRushD — the back line's carrier owner and middle (BACK_STRONG / BACK_MID;
# docs/transition-defense-plan.md §5–§6).
# Team 0 defends +Z and attacks -Z; peer 1 is the bot under test, peer 10 is
# the opposing carrier. A rush at us travels in +Z. The cushions the current
# ramp gives at the reference fixtures are the snapshot,
# test_rush_d_cushion_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/role_rush_d.txt"
const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z
const STICK: float = 2.0


# `support_behind` puts a teammate home between us and our net. It is ON by
# default because it makes the LAST-MAN STEP-UP BOUND inert
# (AIRoleRushD._settable_gap), and every case below is about the ladder, the
# numbers rungs, or the angling — one variable each, per this file's premise.
# The bound now only survives for a LOOSE puck (a live carrier is a frame the
# route regulates on its own), and there it still dominates these fixtures:
# they place the D 9-16 m goal-side of the stand he is being asked to take,
# which is a step-up no ice-frame seek arrives at set, so the ladder underneath
# would be invisible.
func _ctx(self_pos: Vector3, skaters: Array, carrier_pid: int,
		numbers: int = AIRushRead.Numbers.EVEN_OR_UP,
		backpressure: float = INF, support_behind: bool = true) -> RoleContext:
	var snap := WorldSnapshot.new()
	var s := SkaterNetworkState.new()
	s.position = self_pos
	snap.skater_states[1] = s
	var team_map: Dictionary = {1: TEAM_ID}
	if support_behind:
		var home := SkaterNetworkState.new()
		home.position = Vector3(0.0, 0.0, OUR_NET_Z - 2.0)
		snap.skater_states[2] = home
		team_map[2] = TEAM_ID
	for e: Array in skaters:
		var sk := SkaterNetworkState.new()
		sk.position = e[2]
		sk.velocity = e[3] if e.size() > 3 else Vector3.ZERO
		snap.skater_states[e[0]] = sk
		team_map[e[0]] = e[1]
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = carrier_pid
	puck.position = snap.skater_states[carrier_pid].position \
			if snap.skater_states.has(carrier_pid) else Vector3.ZERO
	snap.puck_state = puck

	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -OUR_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	ctx.team_size = 5
	ctx.self_is_defense = true
	ctx.self_home_side = 1.0
	ctx.self_blade_reach = STICK
	# A live read with the posture under test. Filled directly rather than via
	# a brain so each case pins one variable.
	var read := AIRushRead.new()
	read.fill(snap, TEAM_ID, OUR_NET_Z, team_map, {}, {})
	read.numbers = numbers
	read.backpressure_s = backpressure
	ctx.rush_read = read
	# The lane fan is a separate concern; keep these cases on the ladder.
	ctx.plays_rush_pass_lanes = false
	return ctx


# The gap the model actually holds, measured against the carrier's REAL body —
# which is the only reference the carrier can be beaten off.
#
# This used to measure against his velocity-LED point, on the grounds that the
# role built its stand there and folding the lead into every reading was "a
# couple of metres of pure artifact". That was true for isolating the ladder and
# false for the behaviour: the lead was a real part of the gap the bot held, and
# measuring around it is exactly why nobody noticed the held gap was 86% wider
# than the ladder asked for. The role no longer leads the reference at all (the
# route carries the carrier's velocity instead), so the two agree again — but the
# reading stays on the real body so it cannot hide a lead if one comes back.
func _gap(d: RoleDecision, carrier: Vector3, _vel: Vector3 = Vector3.ZERO) -> float:
	return Vector2(d.target_position.x, d.target_position.z).distance_to(
			Vector2(carrier.x, carrier.z))


# ── The gap ladder: ice remaining, not pace ──────────────────────────────────

func test_gap_tightens_as_the_carrier_approaches_our_blue_line() -> void:
	# The doctrine ladder: ~3 sticks at their blue line, 2 at the red line, 1 at
	# ours. The old model was a function of PACE, so a carrier at full flight
	# held a ~3-stick gap all the way to our net — that is the sag.
	var far_carrier := Vector3(0.0, 0.0, -7.29)   # their blue line
	var mid_carrier := Vector3(0.0, 0.0, 0.0)     # red line
	var near_carrier := Vector3(0.0, 0.0, 7.29)   # our blue line
	var vel := Vector3(0.0, 0.0, 7.0)
	var gaps: Array[float] = []
	for c: Vector3 in [far_carrier, mid_carrier, near_carrier]:
		var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
				[[10, 1, c, vel]], 10,
				AIRushRead.Numbers.DOWN_ONE)   # neutral rung: no tighten/loosen
		# Travelling with the rush, so no ramp cushion: the ladder alone.
		ctx.self_velocity = vel
		var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
		gaps.append(_gap(d, c, vel))
	assert_gt(gaps[0], gaps[1], "gap shrinks from their blue line to the red line")
	assert_gt(gaps[1], gaps[2], "gap shrinks from the red line to ours")
	assert_lt(gaps[2], 2.5 * STICK,
			"at our own blue line the gap is tight, not a 3-stick sag; got %.2f m"
			% gaps[2])


func test_pace_alone_cannot_produce_the_old_sag() -> void:
	# Same spot on the ice, wildly different closing speeds, and the defender
	# already travelling with each rush. Pace only buys cushion through the
	# stride ramp, and a body riding the rush at its pace has nothing left to
	# build — so the ladder alone sets the gap and pace cannot be the driver.
	var carrier := Vector3(0.0, 0.0, 4.0)
	var slow_v := Vector3(0.0, 0.0, 4.0)
	var fast_v := Vector3(0.0, 0.0, 9.0)
	var slow_ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, slow_v]], 10, AIRushRead.Numbers.DOWN_ONE)
	slow_ctx.self_velocity = slow_v
	var fast_ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, fast_v]], 10, AIRushRead.Numbers.DOWN_ONE)
	fast_ctx.self_velocity = fast_v
	var slow: float = _gap(
			AIRoleRushD.decide(slow_ctx, AIRoleSlots.Slot.BACK_STRONG), carrier, slow_v)
	var fast: float = _gap(
			AIRoleRushD.decide(fast_ctx, AIRoleSlots.Slot.BACK_STRONG), carrier, fast_v)
	assert_lt(absf(fast - slow), 0.5 * STICK,
			"riding the rush, pace barely moves the gap; slow=%.2f fast=%.2f"
			% [slow, fast])


func test_a_standing_defender_gives_a_flying_carrier_the_ramp() -> void:
	# The other half: the same carrier at 9 m/s against a defender standing
	# still. He concedes the stride ramp's head start before he can travel with
	# the rush, so the stand sits that much deeper than the riding one. The
	# carrier is close enough to our line that neither stand is held out at it.
	var carrier := Vector3(0.0, 0.0, 5.0)
	var vel := Vector3(0.0, 0.0, 9.0)
	var riding: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, vel]], 10, AIRushRead.Numbers.DOWN_ONE)
	riding.self_velocity = vel
	var standing: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, vel]], 10, AIRushRead.Numbers.DOWN_ONE)
	var ice_to_gate: float = OUR_NET_Z - carrier.z - AIRoleRushD.RETREAT_FINISH_M
	var ramp: float = minf(AIStrideRamp.head_start(9.0,
			AIArrival.SKATER_REF_SPEED_M_S,
			AIArrival.SHED_ACCEL_DEFAULT_M_S2, 0.0,
			standing.self_max_speed, standing.self_max_accel,
			AIArrival.REVERSAL_BRAKE_DECEL_M_S2,
			AIStrideRamp.time_to_cover(9.0, ice_to_gate,
					AIArrival.SKATER_REF_SPEED_M_S,
					AIArrival.SHED_ACCEL_DEFAULT_M_S2)), ice_to_gate)
	assert_gt(ramp, STICK, "a flat start against 9 m/s concedes real ice")
	var deeper: float = \
			_gap(AIRoleRushD.decide(standing, AIRoleSlots.Slot.BACK_STRONG), carrier, vel) \
			- _gap(AIRoleRushD.decide(riding, AIRoleSlots.Slot.BACK_STRONG), carrier, vel)
	assert_almost_eq(deeper, ramp, 0.3,
			"the standing defender's stand is deeper by the ramp's head start")


# The cushion a D 16 m goal-side of a 6 m/s carrier owes, drifting at
# `up_ice_m_s` away from our net when the rush starts.
func _cushion(up_ice_m_s: float) -> float:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var vel := Vector3(0.0, 0.0, 6.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, vel]], 10, AIRushRead.Numbers.DOWN_ONE)
	ctx.self_velocity = Vector3(0.0, 0.0, -up_ice_m_s)
	var ap := AICarrierApproach.new()
	AIDefensiveVerbs.fill_approach(ctx, carrier, vel, ap)
	return AIRoleRushD.ramp_cushion_m(ctx, ap, 10)


func test_momentum_up_ice_costs_more_cushion_than_standing() -> void:
	# A defender still drifting up-ice from the attack has to brake that out
	# before the stride can start — the more he carries, the more he owes.
	var prev: float = -INF
	for drift: float in [0.0, 1.0, 2.0, 3.0]:
		var cushion: float = _cushion(drift)
		assert_gte(cushion, prev, "up-ice momentum is ice the defender owes (%.0f m/s)" % drift)
		prev = cushion
	assert_gt(_cushion(3.0), _cushion(0.0), "drifting up-ice owes more than standing")


func test_no_cushion_once_the_carrier_is_past_where_a_retreat_ends() -> void:
	# The race finishes where a ridden retreat ends; past it the ladder alone
	# stands him up, however flat the defender is.
	var carrier := Vector3(0.0, 0.0, OUR_NET_Z - AIRoleRushD.RETREAT_FINISH_M + 0.3)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, OUR_NET_Z - 3.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 9.0)]], 10)
	var ap := AICarrierApproach.new()
	AIDefensiveVerbs.fill_approach(ctx, carrier, Vector3(0.0, 0.0, 9.0), ap)
	assert_eq(AIRoleRushD.ramp_cushion_m(ctx, ap, 10), 0.0,
			"no retreat race is left past where a retreat ends")


# ── Numbers ──────────────────────────────────────────────────────────────────

func test_even_numbers_tighten_the_gap() -> void:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var even: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 6.0)]], 10,
			AIRushRead.Numbers.EVEN_OR_UP)
	var down: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 6.0)]], 10,
			AIRushRead.Numbers.DOWN_ONE)
	assert_lt(_gap(AIRoleRushD.decide(even, AIRoleSlots.Slot.BACK_STRONG), carrier, Vector3(0.0, 0.0, 6.0)),
			_gap(AIRoleRushD.decide(down, AIRoleSlots.Slot.BACK_STRONG), carrier, Vector3(0.0, 0.0, 6.0)),
			"even numbers is licence to stand up")


func test_down_one_does_not_concede_depth() -> void:
	# The failure mode this exists to prevent: conceding DEPTH on an odd-man
	# rush turns a 2-on-1 into a breakaway. An odd-man concession is lateral.
	var carrier := Vector3(0.0, 0.0, 0.0)
	var down_one: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 6.0)]], 10,
			AIRushRead.Numbers.DOWN_ONE)
	var down_two: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 6.0)]], 10,
			AIRushRead.Numbers.DOWN_TWO_PLUS)
	assert_lt(_gap(AIRoleRushD.decide(down_one, AIRoleSlots.Slot.BACK_STRONG), carrier, Vector3(0.0, 0.0, 6.0)),
			_gap(AIRoleRushD.decide(down_two, AIRoleSlots.Slot.BACK_STRONG), carrier, Vector3(0.0, 0.0, 6.0)),
			"DOWN_ONE holds its depth; only DOWN_TWO_PLUS buys time with ground")


func test_backpressure_lets_the_d_stand_up() -> void:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var alone: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 6.0)]], 10,
			AIRushRead.Numbers.DOWN_ONE, INF)
	var helped: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 6.0)]], 10,
			AIRushRead.Numbers.DOWN_ONE, 0.8)
	assert_lt(_gap(AIRoleRushD.decide(helped, AIRoleSlots.Slot.BACK_STRONG), carrier, Vector3(0.0, 0.0, 6.0)),
			_gap(AIRoleRushD.decide(alone, AIRoleSlots.Slot.BACK_STRONG), carrier, Vector3(0.0, 0.0, 6.0)),
			"a backchecker on his hip lets the D tighten and stand up")


# ── The stand rides the carrier ──────────────────────────────────────────────
# The ladder says where the stand IS. What used to answer "may I take the trip to
# it?" was a stand-PLACEMENT bound (AILastManDiscipline.settable_stand_depth): hold the
# stand back to where a charge would end set, because an ice-frame seek could only
# ever reach a spot by charging it and braking to zero.
#
# The route answers it now. BACK_STRONG publishes the stand's own velocity and the
# steering flies the whole approach in that frame (AISteering, "moving-frame
# pursuit"), where the commanded velocity is the stand's plus a closing term that
# decays to nothing on arrival — so the trip ENDS matched to the rush by
# construction, and there is no charge left to bound. Running both put two
# controllers on one axis: the bound charges for a pivot the route no longer
# performs, which placed the stand within 0.3 m of wherever the D already stood,
# and a D whose stand is always where he is never closes on anybody.
#
# The behavioural half of this — how much up-ice speed he actually carries into
# the meet — is pinned in tests/slow/ai/test_rush_gap_discipline.gd, which
# measures the body over multi-second rushes. That is the only place it can
# honestly live; a single dispatch cannot see a route. Here we pin the contract
# the route is built on.

func test_the_stand_publishes_the_carriers_velocity() -> void:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var vel := Vector3(0.0, 0.0, 7.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 20.0),
			[[10, 1, carrier, vel]], 10, AIRushRead.Numbers.DOWN_ONE, INF, false)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_almost_eq(d.target_velocity.z, vel.z, 0.01,
			"the gap stand rides the man it gaps; got %.2f" % d.target_velocity.z)


func test_the_ladder_is_the_stand_whether_or_not_anyone_is_home() -> void:
	# The last man reads the SAME gap as a D with a layer behind him: the route
	# regulates his approach, so his depth no longer has to. (The numbers rungs
	# still move the gap — that is the shared read, and a different question.)
	var carrier := Vector3(0.0, 0.0, 0.0)      # red line, coming at pace
	var vel := Vector3(0.0, 0.0, 7.0)
	var alone: RoleContext = _ctx(Vector3(0.0, 0.0, 20.0),
			[[10, 1, carrier, vel]], 10, AIRushRead.Numbers.DOWN_ONE, INF, false)
	var layered: RoleContext = _ctx(Vector3(0.0, 0.0, 20.0),
			[[10, 1, carrier, vel]], 10, AIRushRead.Numbers.DOWN_ONE, INF, true)
	assert_almost_eq(
			_gap(AIRoleRushD.decide(alone, AIRoleSlots.Slot.BACK_STRONG), carrier, vel),
			_gap(AIRoleRushD.decide(layered, AIRoleSlots.Slot.BACK_STRONG), carrier, vel),
			0.05, "the last man reads the ladder, not a depth bound")


func test_a_loose_puck_keeps_the_ice_frame_bound() -> void:
	# There is no man to ride when the puck is loose — a puck is decelerating and
	# unowned, and nobody gaps up on one — so the stand is a point on the ice
	# again and the last-man bound is still the thing that governs the trip.
	var puck := Vector3(0.0, 0.0, 0.0)
	var alone: RoleContext = _ctx(Vector3(0.0, 0.0, 20.0),
			[[10, 1, puck, Vector3(0.0, 0.0, 7.0)]], -1,
			AIRushRead.Numbers.DOWN_ONE, INF, false)
	alone.snapshot.puck_state.position = puck
	alone.snapshot.puck_state.velocity = Vector3(0.0, 0.0, 7.0)
	var layered: RoleContext = _ctx(Vector3(0.0, 0.0, 20.0),
			[[10, 1, puck, Vector3(0.0, 0.0, 7.0)]], -1,
			AIRushRead.Numbers.DOWN_ONE, INF, true)
	layered.snapshot.puck_state.position = puck
	layered.snapshot.puck_state.velocity = Vector3(0.0, 0.0, 7.0)
	var d_alone: RoleDecision = AIRoleRushD.decide(alone, AIRoleSlots.Slot.BACK_STRONG)
	assert_eq(d_alone.target_velocity, Vector3.ZERO,
			"a loose puck is not a frame to hold station in")
	assert_gt(_gap(d_alone, puck, Vector3(0.0, 0.0, 7.0)),
			_gap(AIRoleRushD.decide(layered, AIRoleSlots.Slot.BACK_STRONG), puck,
					Vector3(0.0, 0.0, 7.0)),
			"the last man still holds ice he cannot cover set")


# ── Gap up ───────────────────────────────────────────────────────────────────

func test_gap_up_when_the_carrier_has_no_speed() -> void:
	# The concept the pace model could not express: his speed advantage is gone,
	# so ATTACK rather than merely fear him less. Inside our line, where the back
	# line no longer waits on it.
	var carrier := Vector3(0.0, 0.0, 9.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 0.5)]], 10,
			AIRushRead.Numbers.DOWN_ONE)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	var vel := Vector3(0.0, 0.0, 0.5)
	assert_lt(_gap(d, carrier, vel), 1.6 * STICK,
			"a stalled carrier is met at challenge range; got %.2f m"
			% _gap(d, carrier, vel))


func test_no_gap_up_when_outnumbered_by_two() -> void:
	# Stepping up into a rush you're two men down is how a scoring chance
	# becomes a goal. The trigger must respect the numbers.
	var carrier := Vector3(0.0, 0.0, 9.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 0.5)]], 10,
			AIRushRead.Numbers.DOWN_TWO_PLUS)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_gt(_gap(d, carrier, Vector3(0.0, 0.0, 0.5)), 1.6 * STICK,
			"down two, hold the cushion even against a slow carrier")


func test_gap_up_against_a_carrier_pinned_to_the_wall() -> void:
	# No support behind on purpose: the gap-up is exempt from the last-man
	# step-up bound, because a carrier with no outside left cannot beat the
	# challenge with the pace that bound exists to respect.
	var carrier := Vector3(GameRules.INNER_HALF_WIDTH - 1.0, 0.0, 9.0)
	var ctx: RoleContext = _ctx(Vector3(6.0, 0.0, 18.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 7.0)]], 10,
			AIRushRead.Numbers.DOWN_ONE, INF, false)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_lt(_gap(d, carrier, Vector3(0.0, 0.0, 7.0)), 1.6 * STICK,
			"a carrier with no outside left gets challenged")


# ── Angling and floors ───────────────────────────────────────────────────────

func test_stand_shades_inside_to_steer_him_wide() -> void:
	# Take away the middle, give the outside. A stand dead on the carrier→net
	# line offers both lanes equally.
	var carrier := Vector3(8.0, 0.0, 0.0)
	var ctx: RoleContext = _ctx(Vector3(6.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 7.0)]], 10,
			AIRushRead.Numbers.DOWN_ONE)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	var on_line_x: float = carrier.x + (0.0 - carrier.x) \
			* (_gap(d, carrier) / carrier.distance_to(Vector3(0, 0, OUR_NET_Z)))
	assert_lt(d.target_position.x, on_line_x,
			"the stand shades to the inside of the retreat line")


func test_never_stands_deeper_than_the_house_gate() -> void:
	# A rush role on the goal line duplicates the goalie. The doorstep belongs
	# to in-zone coverage, which is a different state.
	var carrier := Vector3(0.0, 0.0, 24.0)   # already at our doorstep
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 25.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 2.0)]], 10,
			AIRushRead.Numbers.DOWN_TWO_PLUS)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_lte(d.target_position.z, OUR_NET_Z - AIZoneCoverage.HOUSE_TOP_DEPTH_M + 0.01,
			"the stand is clamped to the top of the circles; got %s"
			% d.target_position)


# ── BACK_MID ──────────────────────────────────────────────────────────────────

func test_d2_takes_the_mid_lane_driver() -> void:
	# "The mid-lane drive is fed to D2": of the two non-carrier attackers, D2
	# covers the one driving the middle, not the one out on the wall.
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 18.0), [
		[10, 1, Vector3(-9.0, 0.0, 4.0), Vector3(0.0, 0.0, 7.0)],   # carrier, wide
		[11, 1, Vector3(0.5, 0.0, 5.0), Vector3(0.0, 0.0, 7.0)],    # mid-lane drive
		[12, 1, Vector3(10.0, 0.0, 5.0), Vector3(0.0, 0.0, 7.0)],   # far wall
	], 10)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_MID)
	assert_lt(absf(d.target_position.x), 6.0,
			"D2 covers the middle driver, not the wall man; got %s"
			% d.target_position)
	# A rush D's stick belongs in the lane: no stick-tie lock in transition.
	assert_eq(d.locked_man_pid, -1, "D2 covers without a stick-tie lock")


func test_d2_holds_mid_ice_with_nobody_driving() -> void:
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 18.0),
			[[10, 1, Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, 7.0)]], 10)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_MID)
	assert_lt(absf(d.target_position.x), 6.0, "D2 holds mid-ice")
	assert_lt(d.target_position.z, OUR_NET_Z,
			"and stays in front of the net, not on it")


# ── Inside angling scales with the carrier's own lateral offset ──────────────
# The shade takes away the middle. A carrier already IN the middle has no inside
# to take, so the depth goes to zero there — which is also what makes the two
# sides meet continuously instead of the stand jumping across as he crosses
# centre.

func _stand_for_carrier_x(carrier_x: float) -> Vector3:
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 14.0), [
		[10, 1, Vector3(carrier_x, 0.0, 0.0), Vector3(0.0, 0.0, 7.0)],
	], 10)
	return AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG).target_position


func test_a_centre_lane_carrier_gets_no_lateral_shade() -> void:
	var stand: Vector3 = _stand_for_carrier_x(0.0)
	assert_almost_eq(stand.x, 0.0, 0.05,
			"dead centre there is no inside to take away; got %s" % stand)


func test_the_shade_does_not_jump_across_centre() -> void:
	# The defect: a fixed shade had to pick a side, so the stand flipped a full
	# 2x ANGLE_INSIDE_M between a carrier a centimetre either side of x = 0.
	var left: Vector3 = _stand_for_carrier_x(-0.05)
	var right: Vector3 = _stand_for_carrier_x(0.05)
	assert_lt(absf(left.x - right.x), 0.15,
			"the stand must be continuous through centre; got %s vs %s"
			% [left, right])


func test_a_wide_carrier_is_shaded_toward_the_middle() -> void:
	# Out at the dot lane the inside/outside split is real and the full shade
	# applies — toward centre, i.e. the opposite side from the carrier.
	var stand: Vector3 = _stand_for_carrier_x(GameRules.END_ZONE_FACEOFF_DOT_X)
	assert_lt(stand.x, GameRules.END_ZONE_FACEOFF_DOT_X,
			"shaded inside of the carrier, not outside him; got %s" % stand)
	var mid: Vector3 = _stand_for_carrier_x(GameRules.END_ZONE_FACEOFF_DOT_X * 0.5)
	var wide_shade: float = GameRules.END_ZONE_FACEOFF_DOT_X - stand.x
	var mid_shade: float = GameRules.END_ZONE_FACEOFF_DOT_X * 0.5 - mid.x
	assert_gt(wide_shade, mid_shade,
			"the shade deepens as the carrier gets wider (%.2f vs %.2f)"
			% [wide_shade, mid_shade])


func test_the_shade_is_mirror_symmetric() -> void:
	var left: Vector3 = _stand_for_carrier_x(-GameRules.END_ZONE_FACEOFF_DOT_X)
	var right: Vector3 = _stand_for_carrier_x(GameRules.END_ZONE_FACEOFF_DOT_X)
	assert_almost_eq(left.x, -right.x, 0.05,
			"both wings are angled the same way; got %s vs %s" % [left, right])


# ── BACK_MID only leaves mid-ice for a genuinely mid-lane man ───────────────
# D2's whole job is the middle. Picking argmin|x| over the rush with no bound
# meant a lone second attacker on the boards read as "the mid-lane drive" and
# pulled him off the lane the layered defense keeps him in.

func _d2_target(second_x: float) -> Vector3:
	var ctx: RoleContext = _ctx(Vector3(-2.0, 0.0, 16.0), [
		[10, 1, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 7.0)],       # carrier
		[11, 1, Vector3(second_x, 0.0, 5.0), Vector3(0.0, 0.0, 7.0)],  # second man
	], 10)
	return AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_MID).target_position


func test_d2_covers_a_man_driving_the_middle() -> void:
	var target: Vector3 = _d2_target(1.5)
	assert_lt(absf(target.x - 1.5), 6.0,
			"a man in the middle is D2's to take; got %s" % target)


func test_d2_holds_mid_ice_against_a_wall_man() -> void:
	# Outside the dot lane he is the mid trackers' pickup as he cuts in, not
	# D2's to chase — chasing him vacates the middle.
	var wall_x: float = GameRules.END_ZONE_FACEOFF_DOT_X + 3.0
	var target: Vector3 = _d2_target(wall_x)
	assert_lt(absf(target.x), absf(wall_x) * 0.5,
			"D2 stays central instead of chasing the wall man; got %s" % target)


func test_the_mid_lane_band_is_the_dot_lane() -> void:
	# Just inside the dots is his; just outside is not. Pinned so the boundary
	# can't drift without the intent being restated.
	var inside: Vector3 = _d2_target(GameRules.END_ZONE_FACEOFF_DOT_X - 0.5)
	var outside: Vector3 = _d2_target(GameRules.END_ZONE_FACEOFF_DOT_X + 0.5)
	assert_gt(absf(inside.x), absf(outside.x),
			"the man inside the dots pulls D2 wider than the one outside them; "
			+ "got %s vs %s" % [inside, outside])


# ── Stand him up at our line ─────────────────────────────────────────────────

class StubStrategy extends TeamStrategyView:
	var slots: Dictionary = {}

	func get_slot(peer_id: int) -> int:
		return slots.get(peer_id, AIRoleSlots.Slot.NONE)


func test_the_back_man_waits_for_him_on_our_line() -> void:
	# A carrier coming up the middle at the red line: the ladder would put the
	# stand out in the neutral zone. The back line does not go out to him.
	var carrier := Vector3(2.0, 0.0, 0.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 7.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 3.0)]], 10)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_almost_eq(OUR_NET_Z - d.target_position.z, AIRoleNeutralZone.line_depth_m(),
			0.05, "the stand is on our line; got %s" % d.target_position)
	assert_false(d.arrive_at_speed, "he stops on the line")


func test_the_line_stand_stays_inside_the_dots() -> void:
	# A carrier up the wall at the red line: protect the middle, give him the
	# outside — the stand on the line does not follow him out to the boards.
	var carrier := Vector3(GameRules.INNER_HALF_WIDTH - 1.0, 0.0, 0.0)
	var ctx: RoleContext = _ctx(Vector3(5.0, 0.0, 7.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 5.0)]], 10)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_lte(absf(d.target_position.x), GameRules.END_ZONE_FACEOFF_DOT_X + 0.01,
			"the line stand is inside the dots; got %s" % d.target_position)


func test_a_deep_back_man_does_not_race_up_to_the_line_against_pace() -> void:
	# Deep in our zone with a carrier coming hard from the red line: he cannot be
	# set on the line before the carrier is on him, so the line is not his stand.
	var carrier := Vector3(0.0, 0.0, 0.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 16.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 9.0)]], 10)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_gt(d.target_position.z, GameRules.BLUE_LINE_Z + 1.0,
			"he keeps his ice inside the zone; got %s" % d.target_position)


func test_a_back_man_caught_up_the_ice_rides_the_ladder_back() -> void:
	# Out in the neutral zone in front of the carrier already: he keeps the
	# ladder's gap on him as he comes rather than turning to race for the line.
	var carrier := Vector3(0.0, 0.0, -8.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, -2.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 6.0)]], 10)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_lt(d.target_position.z, GameRules.BLUE_LINE_Z - 1.0,
			"he holds his gap out in the neutral zone; got %s" % d.target_position)


func _fan_ctx(mid_holder_inside: bool) -> RoleContext:
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 14.0), [
		[10, 1, Vector3(-3.0, 0.0, 8.0), Vector3(0.0, 0.0, 7.0)],    # carrier
		[11, 1, Vector3(4.0, 0.0, 10.0), Vector3(0.0, 0.0, 7.0)],    # the man across
		[12, 0, Vector3(1.0, 0.0, 15.5) if mid_holder_inside \
				else Vector3(1.0, 0.0, -4.0)],                       # our middle
	], 10, AIRushRead.Numbers.DOWN_ONE, INF, false)
	ctx.plays_rush_pass_lanes = true
	var strategy := StubStrategy.new()
	strategy.slots = {1: AIRoleSlots.Slot.BACK_STRONG, 12: AIRoleSlots.Slot.BACK_MID}
	ctx.team_brain = strategy
	ctx.rush_read.recovery_by_peer[12] = AIRushRead.Recovery.INSIDE if mid_holder_inside \
			else AIRushRead.Recovery.BEATEN
	return ctx


func test_the_pass_across_is_the_middles_while_he_holds_it() -> void:
	# The last-man confusion: the carrier owner reading the feed across while a
	# teammate holds the middle behind him leaves the carrier walking in. The
	# pass is the middle man's; with nobody there it is his own again.
	var held: RoleContext = _fan_ctx(true)
	var stand_held: Vector3 = AIRoleRushD.decide(held, AIRoleSlots.Slot.BACK_STRONG).target_position
	var no_fan: RoleContext = _fan_ctx(true)
	no_fan.plays_rush_pass_lanes = false
	var stand_no_fan: Vector3 = AIRoleRushD.decide(no_fan, AIRoleSlots.Slot.BACK_STRONG).target_position
	assert_lt(stand_held.distance_to(stand_no_fan), 0.01,
			"with the middle held he plays the carrier, not the lane; got %s vs %s"
			% [stand_held, stand_no_fan])
	assert_false(AIRoleRushD._middle_held(_fan_ctx(false)),
			"a middle man who is not back holds nothing")
	assert_true(AIRoleRushD._middle_held(held), "a middle man back holds it")


func test_back_mid_does_not_leave_the_line_for_a_man_up_the_ice() -> void:
	# A man driving the middle still at centre ice is not his yet: covering him
	# there would walk the middle of our line out into the neutral zone.
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 8.0), [
		[10, 1, Vector3(-8.0, 0.0, -6.0), Vector3(0.0, 0.0, 6.0)],   # carrier, wide
		[11, 1, Vector3(0.5, 0.0, -4.0), Vector3(0.0, 0.0, 6.0)],    # middle, far
	], 10)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_MID)
	assert_almost_eq(OUR_NET_Z - d.target_position.z, AIRoleNeutralZone.line_depth_m(),
			0.05, "the middle holds our line; got %s" % d.target_position)


func test_rush_d_cushion_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	snap.record("ramp cushion, D standing 16 m off a 6 m/s carrier", _cushion(0.0))
	snap.record("ramp cushion, same D drifting up-ice at 3 m/s", _cushion(3.0))
	snap.verify(self)


# ── A turn keeps a skater's speed ────────────────────────────────────────────

func _crossing_read(carrier_vel: Vector3) -> Array:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var ctx: RoleContext = _ctx(Vector3(3.0, 0.0, 12.0), [[10, 1, carrier, carrier_vel]], 10)
	var ap := AICarrierApproach.new()
	AIDefensiveVerbs.fill_approach(ctx, carrier, carrier_vel, ap)
	var cushion: float = AIRoleRushD.ramp_cushion_m(ctx, ap, 10)
	return [cushion, AIRoleRushD.should_gap_up(ctx, ctx.rush_read, ap, cushion)]


func test_a_carrier_crossing_at_speed_has_a_head_start_a_standing_one_does_not() -> void:
	# Crossing the ice he is not closing on our net at all, but a turn swings
	# that speed at it: the race is priced on it, never on his pace along the line.
	var standing: Array = _crossing_read(Vector3.ZERO)
	var crossing: Array = _crossing_read(Vector3(6.0, 0.0, 0.0))
	var leaving: Array = _crossing_read(Vector3(0.0, 0.0, -6.0))
	assert_gt(crossing[0], standing[0], "crossing at speed earns more cushion than standing")
	assert_lt(leaving[0], crossing[0], "skating away needs a longer turn than crossing")


func test_a_carrier_crossing_at_speed_is_not_regrouping() -> void:
	assert_true(_crossing_read(Vector3.ZERO)[1], "a standing carrier is a regroup: step up")
	assert_false(_crossing_read(Vector3(6.0, 0.0, 0.0))[1],
			"one crossing at speed is not: his speed is a turn from our net")


# ── Depth before width ───────────────────────────────────────────────────────

# How far across the carrier→net line the D1 target sits from the defender, for
# a defender at `self_pos` moving at `self_vel` off a wide carrier.
func _width_asked(self_pos: Vector3, self_vel: Vector3) -> Array:
	var carrier := Vector3(8.0, 0.0, 0.0)
	var carrier_vel := Vector3(0.0, 0.0, 6.0)
	var ctx: RoleContext = _ctx(self_pos, [[10, 1, carrier, carrier_vel]], 10,
			AIRushRead.Numbers.DOWN_ONE)
	ctx.self_velocity = self_vel
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	var dir_net: Vector3 = (Vector3(0.0, 0.0, OUR_NET_Z) - carrier).normalized()
	var to_target: Vector3 = d.target_position - self_pos
	var across: Vector3 = to_target - dir_net * to_target.dot(dir_net)
	var ride_across: Vector3 = d.target_velocity \
			- dir_net * d.target_velocity.dot(dir_net)
	return [across.length(), ride_across.length(), to_target.dot(dir_net)]


func test_a_standing_defender_short_of_his_stand_goes_down_the_line_first() -> void:
	# Level with a wide carrier, out on the far side of his lane: the stand is
	# deeper AND across. From a stand every push goes to depth.
	var standing: Array = _width_asked(Vector3(-2.0, 0.0, 2.0), Vector3.ZERO)
	assert_gt(standing[2], 0.0, "the fixture leaves him short of his stand")
	assert_almost_eq(standing[0], 0.0, 0.05,
			"no width until he has the pace; got %.2f m across" % standing[0])
	assert_almost_eq(standing[1], 0.0, 0.05, "and the ride goes straight down the line")


func test_a_defender_already_at_pace_spends_the_spare_stride_across() -> void:
	var standing: Array = _width_asked(Vector3(-2.0, 0.0, 2.0), Vector3.ZERO)
	var retreating: Array = _width_asked(Vector3(-2.0, 0.0, 2.0), Vector3(0.0, 0.0, 6.0))
	gut.p("  across: standing %.2f m, retreating %.2f m" % [standing[0], retreating[0]])
	assert_gt(retreating[0], standing[0] + 0.5,
			"carrying the pace leaves stride to take ice across")


func test_a_defender_carrying_width_keeps_it() -> void:
	# Short of his stand, he gets no NEW width — but speed he already carries
	# across, the way he is sent, is not braked off: gliding costs no stride.
	var standing: Array = _width_asked(Vector3(-2.0, 0.0, 2.0), Vector3.ZERO)
	var sliding: Array = _width_asked(Vector3(-2.0, 0.0, 2.0), Vector3(4.0, 0.0, 0.0))
	assert_almost_eq(standing[1], 0.0, 0.05, "the fixture's standing ride has no width")
	assert_gt(sliding[1], 0.5, "the ride keeps the width he carries")
	assert_gt(sliding[0], standing[0] + 0.5, "and so does the stand")


# ── A step-up never outruns the turn ─────────────────────────────────────────

func _step_up(carrier_vel: Vector3) -> RoleDecision:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 4.0), [[10, 1, carrier, carrier_vel]], 10,
			AIRushRead.Numbers.DOWN_ONE)
	return AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)


func test_a_step_up_on_a_carrier_crossing_at_speed_holds_its_ice() -> void:
	# In his lane with the retreat unable to hold a gap, he steps up — but the
	# carrier can turn 6 m/s at our net, so the route may not carry him up-ice.
	var d: RoleDecision = _step_up(Vector3(6.0, 0.0, 0.5))
	assert_lt(d.advance_cap_m_s, 0.5, "got %.2f m/s up-ice" % d.advance_cap_m_s)


func test_a_step_up_on_a_stalled_carrier_may_attack() -> void:
	var d: RoleDecision = _step_up(Vector3(0.0, 0.0, 0.3))
	assert_gt(d.advance_cap_m_s, 2.0, "a carrier with no speed is attacked")


# ── Turn and skate ───────────────────────────────────────────────────────────

# A rush D `depth` m goal-side of a carrier coming straight at our net at
# `pace`, facing the play and backpedalling at `self_speed`, on `profile`
# skates (the backward stride is the profile's).
func _retreat(depth: float, pace: float, self_speed: float,
		profile: int = PlayerAttributes.PROFILE_POWER) -> RoleDecision:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, depth),
			[[10, 1, carrier, Vector3(0.0, 0.0, pace)]], 10)
	ctx.snapshot.skater_states[1].facing = Vector2(0.0, -1.0)
	ctx.self_velocity = Vector3(0.0, 0.0, self_speed)
	var caps := AISkaterCaps.new()
	var lean: float = PlayerAttributes.new(73, 201, profile).backward_mult()
	caps.movement.backward_thrust_multiplier *= lean
	caps.movement.backward_max_speed_multiplier *= lean
	ctx.caps_by_peer[ctx.peer_id] = caps
	return AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)


func test_backpedalling_into_a_race_he_loses_he_turns_and_skates() -> void:
	assert_true(_retreat(6.0, 9.0, 7.4).face_travel,
			"at his power-skate backward top speed against 9 m/s with 6 m to give: turn and skate")


func test_on_stability_skates_he_can_backpedal_the_same_rush() -> void:
	# The gap-control skate: his backward top speed matches a 9 m/s rush.
	assert_false(_retreat(6.0, 9.0, 9.0, PlayerAttributes.PROFILE_STABILITY).face_travel,
			"stability skates hold the gap facing the play")


func test_a_route_mostly_across_the_ice_stays_square_to_the_man() -> void:
	# A turnover the carrier drifts wide from (test_nz_turnover_recovery's 8 m
	# start, 2 m off his lane, the tick he was turning): the backward race is lost,
	# but the route to the stand runs mostly across, which that race (priced down
	# the line to the net) says nothing about — and turned, a cut back costs him a
	# turn to undo.
	var ctx: RoleContext = _ctx(Vector3(1.0, 0.0, 5.4),
			[[10, 1, Vector3(-1.5, 0.0, -0.3), Vector3(-4.7, 0.0, 5.2)]], 10,
			AIRushRead.Numbers.EVEN_OR_UP, INF, false)
	ctx.snapshot.skater_states[1].facing = Vector2(-1.0, -0.1)
	ctx.self_velocity = Vector3(-3.8, 0.0, 1.5)
	var d: RoleDecision = AIRoleRushD.decide(ctx, AIRoleSlots.Slot.BACK_STRONG)
	assert_gt(absf(d.target_position.x - 1.0), absf(d.target_position.z - 5.4),
			"precondition: the stand is more across than goal-side")
	assert_false(d.face_travel, "covering sideways he faces the play")


func test_with_depth_to_spare_he_faces_the_play() -> void:
	assert_false(_retreat(14.0, 9.0, 7.5).face_travel)


func test_from_a_stand_he_backpedals_first() -> void:
	assert_false(_retreat(6.0, 9.0, 0.0).face_travel,
			"a standing turn costs more ground than backpedalling")


func test_draped_on_the_carrier_he_faces_him() -> void:
	assert_false(_retreat(1.5, 9.0, 7.5).face_travel, "within a stick he plays the man")

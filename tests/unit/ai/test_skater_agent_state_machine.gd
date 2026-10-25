extends GutTest

# SkaterAgentStateMachine against fabricated WorldSnapshots: the chase and
# reception predicates, the cursor and aim geometry, the press states and their
# wind-ups, the carry handler's transitions (with a stubbed carrier), the
# dispatch throttle, the deke, and the cognition gates. No live
# actors — everything runs headless off the bot's identity set by setup.

const Agent := preload("res://Scripts/ai/skater_agent_state_machine.gd")
const Snapshot := preload("res://tests/snapshot.gd")

# peer 1 = self (team 0), peer 2 = teammate (team 0), peers 11/12 = team 1.
const SELF_ID := 1
const TEAMMATE_ID := 2
const OPP_ID := 11
var _team_map := {1: 0, 2: 0, 11: 1, 12: 1}

var sm: SkaterAgentStateMachine


func before_each() -> void:
	sm = Agent.new()
	sm.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, false)


# ── Snapshot builders ────────────────────────────────────────────────────────

func _loose_puck_snap(puck_pos: Vector3) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = puck_pos
	s.puck_state.carrier_peer_id = -1
	return s


func _add_skater(s: WorldSnapshot, peer_id: int, pos: Vector3, ghost: bool = false) -> void:
	var st := SkaterNetworkState.new()
	st.position = pos
	st.is_ghost = ghost
	s.skater_states[peer_id] = st


# ── _should_chase_loose_puck ─────────────────────────────────────────────────

func test_should_chase_false_when_no_puck_state() -> void:
	var s := WorldSnapshot.new()  # puck_state stays null
	assert_false(sm._should_chase_loose_puck(s, Vector3.ZERO))


func test_should_chase_false_when_puck_is_carried() -> void:
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	s.puck_state.carrier_peer_id = OPP_ID
	s.real_puck_carrier_peer_id = OPP_ID
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))
	assert_false(sm._should_chase_loose_puck(s, Vector3(4, 0, 0)),
			"a held puck is never chased even if we're nearest")


# ── Chase reads the REAL carrier, not the team's delayed belief ──────────────
# The delayed carrier_peer_id is the TEAM-SHAPE possession belief (GameManager's
# debounce). Gating chase on it meant that for the whole reaction window — longer
# under scramble noise, since the old debounce restarted on every carrier change
# — no bot would chase a puck that was visibly loose, so bots skated off to their
# role posts past a live puck. Chase now reads the real carrier and applies its
# own bounded delay (_loose_elapsed_s).

func test_chase_uses_real_carrier_not_the_delayed_belief() -> void:
	# Puck is genuinely loose; the team still BELIEVES an opponent has it.
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	s.puck_state.carrier_peer_id = OPP_ID   # stale belief, mid-debounce
	s.real_puck_carrier_peer_id = -1        # truth: nobody has it
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))
	assert_true(sm._should_chase_loose_puck(s, Vector3(4, 0, 0)),
			"a genuinely loose puck is chased even while the team belief lags")


func test_chase_waits_out_the_reaction_delay() -> void:
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	s.real_puck_carrier_peer_id = -1
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))
	sm._chase_reaction_delay_s = 0.2
	sm._loose_elapsed_s = 0.0
	assert_false(sm._should_chase_loose_puck(s, Vector3(4, 0, 0)),
			"no chase before the bot has had time to react")
	sm._loose_elapsed_s = 0.25
	assert_true(sm._should_chase_loose_puck(s, Vector3(4, 0, 0)),
			"chase once the reaction delay has elapsed")


func test_loose_clock_survives_a_scramble_graze() -> void:
	# The failure the old global debounce had: a puck grazing sticks restarted the
	# reaction clock every time, so a scramble could defer the chase indefinitely.
	# A touch shorter than CONTROL_CONFIRM_S must NOT clear the loose clock.
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	s.real_puck_carrier_peer_id = -1
	for i: int in 30:
		sm._update_loose_reaction_clock(s, 1.0 / 120.0)
	var loose_before: float = sm._loose_elapsed_s
	assert_gt(loose_before, 0.2, "clock accumulated while genuinely loose")
	# A 4-tick graze (~0.033 s, under CONTROL_CONFIRM_S 0.08).
	s.real_puck_carrier_peer_id = OPP_ID
	for i: int in 4:
		sm._update_loose_reaction_clock(s, 1.0 / 120.0)
	assert_eq(sm._loose_elapsed_s, loose_before, "a graze does not reset the loose clock")
	# Sustained control does clear it.
	for i: int in 12:
		sm._update_loose_reaction_clock(s, 1.0 / 120.0)
	assert_eq(sm._loose_elapsed_s, 0.0, "sustained control clears the loose clock")


func test_should_chase_true_when_nearest_teammate() -> void:
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))
	_add_skater(s, TEAMMATE_ID, Vector3(10, 0, 0))
	assert_true(sm._should_chase_loose_puck(s, Vector3(4, 0, 0)))


func test_should_chase_false_when_teammate_is_nearer() -> void:
	# Both outside the incidental reach band, so this is purely the election's
	# call — the teammate owns the race and we hold our station.
	var s := _loose_puck_snap(Vector3(15, 0, 0))
	_add_skater(s, SELF_ID, Vector3(0, 0, 0))         # 15 m away
	_add_skater(s, TEAMMATE_ID, Vector3(8, 0, 0))     # 7 m away
	assert_false(sm._should_chase_loose_puck(s, Vector3(0, 0, 0)))


func test_should_chase_a_puck_inside_our_reach_even_when_teammate_is_nearer() -> void:
	# The election picks ONE chaser, which is right for a race across the zone
	# and wrong for a puck sitting a metre from this bot's stick: losing the
	# election is no reason to watch it slide by. Inside the reach band the
	# puck is played by whoever it came to.
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))         # 1.0 m away
	_add_skater(s, TEAMMATE_ID, Vector3(4.5, 0, 0))   # 0.5 m away — elected
	assert_true(sm._should_chase_loose_puck(s, Vector3(4, 0, 0)))


# ── _is_closest_teammate_to_puck_at: cache vs. live scan ─────────────────────

func test_closest_cache_overrides_geometry() -> void:
	# When the per-team cache is populated it is authoritative — geometry is
	# not consulted, so a far-away self still "wins" if the cache names it.
	var s := _loose_puck_snap(Vector3(0, 0, 0))
	_add_skater(s, SELF_ID, Vector3(50, 0, 0))        # nowhere near the puck
	s.closest_to_puck_by_team = {0: SELF_ID}
	assert_true(sm._is_closest_teammate_to_puck_at(s, Vector3(50, 0, 0)))
	s.closest_to_puck_by_team = {0: TEAMMATE_ID}
	assert_false(sm._is_closest_teammate_to_puck_at(s, Vector3(50, 0, 0)))


func test_closest_live_scan_ignores_opponents() -> void:
	# An opponent sitting on the puck must not block our chase — only
	# same-team skaters count toward "closest teammate".
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))
	_add_skater(s, OPP_ID, Vector3(5, 0, 0))          # opponent right on the puck
	assert_true(sm._is_closest_teammate_to_puck_at(s, Vector3(4, 0, 0)))


# ── _post_puck_lost_state ────────────────────────────────────────────────────

func test_post_lost_off_puck_when_no_puck() -> void:
	assert_eq(sm._post_puck_lost_state(WorldSnapshot.new()), Agent.State.OFF_PUCK)


func test_post_lost_off_puck_when_carried() -> void:
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	s.puck_state.carrier_peer_id = TEAMMATE_ID
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))
	assert_eq(sm._post_puck_lost_state(s), Agent.State.OFF_PUCK)


func test_post_lost_off_puck_when_ghosted() -> void:
	# A ghosted (offside/icing) bot stays off-puck even if it's nearest.
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3(4, 0, 0), true)
	assert_eq(sm._post_puck_lost_state(s), Agent.State.OFF_PUCK)


func test_post_lost_chase_when_nearest_and_live() -> void:
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))
	_add_skater(s, TEAMMATE_ID, Vector3(12, 0, 0))
	assert_eq(sm._post_puck_lost_state(s), Agent.State.CHASE_PUCK)


func test_post_lost_off_puck_when_not_nearest() -> void:
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))
	_add_skater(s, TEAMMATE_ID, Vector3(4.5, 0, 0))
	assert_eq(sm._post_puck_lost_state(s), Agent.State.OFF_PUCK)


# ── _opponent_within_forward ─────────────────────────────────────────────────

func test_opponent_within_forward_detects_opponent_ahead() -> void:
	var s := WorldSnapshot.new()
	_add_skater(s, SELF_ID, Vector3.ZERO)
	_add_skater(s, OPP_ID, Vector3(0, 0, 5))
	assert_true(sm._opponent_within_forward(s, Vector3.ZERO, Vector3(0, 0, 1), 10.0))


func test_opponent_within_forward_excludes_teammates() -> void:
	var s := WorldSnapshot.new()
	_add_skater(s, SELF_ID, Vector3.ZERO)
	_add_skater(s, TEAMMATE_ID, Vector3(0, 0, 5))  # teammate ahead — not an opponent
	assert_false(sm._opponent_within_forward(s, Vector3.ZERO, Vector3(0, 0, 1), 10.0))


func test_opponent_within_forward_ignores_opponent_behind() -> void:
	var s := WorldSnapshot.new()
	_add_skater(s, OPP_ID, Vector3(0, 0, -5))  # behind the forward vector
	assert_false(sm._opponent_within_forward(s, Vector3.ZERO, Vector3(0, 0, 1), 10.0))


func test_opponent_within_forward_ignores_opponent_outside_radius() -> void:
	var s := WorldSnapshot.new()
	_add_skater(s, OPP_ID, Vector3(0, 0, 50))  # ahead but far
	assert_false(sm._opponent_within_forward(s, Vector3.ZERO, Vector3(0, 0, 1), 10.0))


func test_opponent_within_forward_degenerate_dir_is_omnidirectional() -> void:
	# A zero forward vector falls through to a pure radius check, so an
	# opponent behind us still counts.
	var s := WorldSnapshot.new()
	_add_skater(s, OPP_ID, Vector3(0, 0, -5))
	assert_true(sm._opponent_within_forward(s, Vector3.ZERO, Vector3.ZERO, 10.0))


# ── _shade_intercept_goal_side (static, pure geometry) ───────────────────────
# Full coverage lives in test_ai_chase_angling.gd; this is the slice's smoke
# check that the shade pulls the intercept toward the defended net by one
# blade reach.

func test_shade_intercept_pulls_toward_our_net() -> void:
	var target := Vector3(3, 0, -10)
	var our_net := Vector3(0, 0, GameRules.GOAL_LINE_Z)
	var shaded: Vector3 = Agent._shade_intercept_goal_side(target, our_net)
	assert_almost_eq(
			Vector2(shaded.x - target.x, shaded.z - target.z).length(),
			AIBotMechanics.BLADE_REACH_M, 0.0001)
	assert_gt(shaded.z, target.z, "shade moves the point toward the +Z net")


# ── _lead_intercept (speed-capped kinematic reachability) ────────────────────
# The solve interpolates arrival slack linearly across a walk step, so its point
# can sit this far either side of the exact crossing.
const INTERCEPT_SLACK_S: float = 0.02
const INTERCEPT_SLACK_M: float = 0.05

func test_lead_intercept_stationary_puck_targets_puck() -> void:
	# A stationary puck's trajectory never moves; the intercept must be the
	# puck itself regardless of which constraint binds first.
	var out: Vector3 = sm._lead_intercept(
			Vector3.ZERO, Vector3.ZERO, Vector3(6, 0, 0), Vector3.ZERO)
	assert_almost_eq(out.x, 6.0, 0.001)
	assert_almost_eq(out.z, 0.0, 0.001)


# When the puck's own predicted path (the shared race walk) reaches `z`,
# for a puck travelling +z.
func _path_time_at_z(puck_pos: Vector3, puck_vel: Vector3, z: float) -> float:
	var traj: Array[Vector3] = AILoosePuckChase.race_trajectory(puck_pos, puck_vel)
	var step_dt: float = AILoosePuckChase.RACE_LOOKAHEAD_S \
			/ float(AILoosePuckChase.RACE_STEPS)
	var prev: Vector3 = puck_pos
	for i: int in traj.size():
		if traj[i].z >= z:
			return (i + inverse_lerp(prev.z, traj[i].z, z)) * step_dt
		prev = traj[i]
	return INF


# Arrival slack at path point `z` for a body starting at the origin from rest,
# driving straight down +z on the stride ramp: positive when his blade gets
# there with the set-up margin to spare before the puck does.
func _straight_line_slack(puck_pos: Vector3, puck_vel: Vector3, z: float) -> float:
	var blade_t: float = AIStrideRamp.time_to_cover(
			0.0, z - sm._blade_reach, sm._self_max_speed, sm._chase_max_accel)
	return _path_time_at_z(puck_pos, puck_vel, z) \
			- AILoosePuckChase.setup_margin(puck_vel) - blade_t


func test_lead_intercept_receding_fast_puck_is_chased_to_where_he_can_make_it() -> void:
	# From rest, a puck receding at 8 m/s from 6 m ahead. No point he passes on
	# the way to his target is one his stride ramp gets the blade to in time, and
	# the target is either a point he can make or, failing every one, the end of
	# the walk where the puck is collected.
	var puck_pos := Vector3(0, 0, 6)
	var puck_vel := Vector3(0, 0, 8)
	var out: Vector3 = sm._lead_intercept(Vector3.ZERO, Vector3.ZERO, puck_pos, puck_vel)
	for z: float in range(7, int(out.z - 0.5)):
		assert_lt(_straight_line_slack(puck_pos, puck_vel, z), 0.0,
				"%.0f m, short of his target, was out of reach" % z)
	var walk_end: Vector3 = AILoosePuckChase.race_trajectory(puck_pos, puck_vel)[-1]
	assert_true(_straight_line_slack(puck_pos, puck_vel, out.z) >= -INTERCEPT_SLACK_S
			or out.distance_to(walk_end) < INTERCEPT_SLACK_M,
			"he steers to a point he can make, or to the end of the walk")



func test_lead_intercept_puts_the_stick_in_a_lane_passing_a_stride_off() -> void:
	# A 12 m/s cross-ice pass whose line runs 2 m off a backing-in defender: his
	# stick is on it with a step, half a second out. He steers into the lane
	# there, not to where his body could catch the puck down by the end boards.
	var self_pos := Vector3(0, 0, -19.4)
	var puck_pos := Vector3(-3.9, 0, -14.0)
	var puck_vel := Vector3(9.9, 0, -7.3)
	var out: Vector3 = sm._lead_intercept(self_pos, Vector3(0.3, 0, -1.8), puck_pos, puck_vel)
	assert_lt(out.distance_to(self_pos), sm._blade_reach + AILoosePuckChase.INCIDENTAL_STRIDE_M,
			"the lane a stride off him, not %s" % out)
	var dir: Vector3 = puck_vel.normalized()
	var off: Vector3 = out - puck_pos
	assert_almost_eq((off - dir * off.dot(dir)).length(), 0.0, 0.1, "on the pass's line")

func test_lead_intercept_moving_with_puck_is_where_a_flying_start_closes() -> void:
	# Already at top speed right behind a slower puck: he meets it no later than
	# a body holding top speed closes the gap down to his stick on a puck that
	# never slows.
	var vmax: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var puck_speed: float = 2.0
	var gap: float = 2.0
	var out: Vector3 = sm._lead_intercept(
			Vector3.ZERO, Vector3(0, 0, vmax),
			Vector3(0, 0, gap), Vector3(0, 0, puck_speed))
	var closed_by: float = maxf(gap - sm._blade_reach, 0.0) / (vmax - puck_speed)
	assert_lte(out.z, gap + puck_speed * closed_by + INTERCEPT_SLACK_M,
			"the closing chase resolves where the flying start catches it")


func test_lead_intercept_meets_a_puck_arriving_at_him() -> void:
	# A puck rolling straight AT a body already closing on it — the retrieval the
	# old private model got worst. It solved for a constant acceleration landing
	# the body exactly on the path point at exactly T, which has no distance term
	# (T ≥ 2·|v_puck − v_self| / A), so at 8 m/s of closing it declared every near
	# point unmakeable and aimed 10.6 m down the line — 6.6 m BEHIND the bot, who
	# was skating the other way at a puck due to reach him in half a second.
	sm._chase_max_accel = GameRules.DEFAULT_SKATER_THRUST_M_S2
	sm._self_max_speed = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var puck_pos := Vector3(4, 0, 0)
	var out: Vector3 = sm._lead_intercept(
			Vector3.ZERO, Vector3(8, 0, 0), puck_pos, Vector3(-5, 0, 0))
	assert_lt(out.distance_to(puck_pos), 4.0,
			"meets the puck on its way in, not far down the ice behind him")
	assert_gt(out.x, 0.0, "intercept stays in front of him, not behind")


func test_lead_intercept_counts_the_stick() -> void:
	# A puck already inside his reach is met where it is — the last stick-length
	# is not travel. Without this the solve demanded his body centre land ON the
	# puck and pushed the aim downstream (4.17 m at 8 m/s for a puck 0.5 m off
	# his blade), which is the bot skating past a puck it could have swept up.
	sm._chase_max_accel = GameRules.DEFAULT_SKATER_THRUST_M_S2
	sm._self_max_speed = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var puck_pos := Vector3(0.5, 0, 0)
	for speed: float in [0.0, 4.0, 8.0]:
		var out: Vector3 = sm._lead_intercept(
				Vector3.ZERO, Vector3(speed, 0, 0), puck_pos, Vector3(0, 0, 3))
		assert_almost_eq(out.distance_to(puck_pos), 0.0, 0.001,
				"puck inside reach at %.0f m/s is met where it is" % speed)


func test_election_does_not_count_the_stick() -> void:
	# Reach belongs to the SELF read only. In the election it collapses every
	# body within a stick to t = 0, so bots the sub-step solve exists to
	# separate tie and fall through to the peer-id tie-break. Two bots a stride
	# apart must still rank by geometry.
	var puck_pos := Vector3(0.5, 0, 0)
	var puck_vel := Vector3(0, 0, 3)
	var traj: Array[Vector3] = AILoosePuckChase.race_trajectory(puck_pos, puck_vel)
	var step_dt: float = AILoosePuckChase.RACE_LOOKAHEAD_S \
			/ float(AILoosePuckChase.RACE_STEPS)
	var near: float = AILoosePuckChase.path_intercept_time(
			traj, step_dt, puck_pos, Vector3.ZERO, Vector3.ZERO,
			GameRules.DEFAULT_SKATER_MAX_SPEED_M_S)
	var far: float = AILoosePuckChase.path_intercept_time(
			traj, step_dt, puck_pos, Vector3(-1.0, 0, 0), Vector3.ZERO,
			GameRules.DEFAULT_SKATER_MAX_SPEED_M_S)
	assert_gt(near, 0.0, "election must not collapse a near body to zero")
	assert_lt(near, far, "the nearer body still ranks ahead on geometry")


func test_lead_intercept_has_no_cliff_in_closing_speed() -> void:
	# The defect was intermittent because the old model's feasible set was not an
	# interval: an early point could be makeable at 6 m/s of closing and not at
	# 8 m/s, dropping the search through to a far one. Two m/s of the bot's OWN
	# speed moved the aim point 8 m. Sweep the axis and pin continuity.
	sm._chase_max_accel = GameRules.DEFAULT_SKATER_THRUST_M_S2
	sm._self_max_speed = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var puck_pos := Vector3(4, 0, 0)
	var prev := Vector3.INF
	for closing: float in [0.0, 2.0, 4.0, 6.0, 8.0]:
		var out: Vector3 = sm._lead_intercept(
				Vector3.ZERO, Vector3(closing, 0, 0), puck_pos, Vector3(-5, 0, 0))
		if prev.is_finite():
			assert_lt(out.distance_to(prev), 1.5,
					"aim point jumped between adjacent closing speeds (%.0f m/s)"
					% closing)
		prev = out


func test_lead_intercept_agrees_with_the_election() -> void:
	# The election assigns the chase; the body must go where it was elected on.
	# These disagreed by 8 m before the solvers were unified.
	sm._chase_max_accel = GameRules.DEFAULT_SKATER_THRUST_M_S2
	sm._self_max_speed = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var puck_pos := Vector3(4, 0, 0)
	var puck_vel := Vector3(-5, 0, 0)
	var self_pos := Vector3.ZERO
	var self_vel := Vector3(8, 0, 0)
	var traj: Array[Vector3] = AILoosePuckChase.race_trajectory(puck_pos, puck_vel)
	var step_dt: float = AILoosePuckChase.RACE_LOOKAHEAD_S \
			/ float(AILoosePuckChase.RACE_STEPS)
	# Same solver, same walk, same margin, the same stick-out meet, and the
	# body's own stick — the self read passes reach where the election
	# deliberately does not (see the reach block in AILoosePuckChase), so the
	# agreement is of MODEL, not of arguments.
	var t: float = minf(AILoosePuckChase.path_intercept_time(
					traj, step_dt, puck_pos, self_pos, self_vel,
					sm._self_max_speed, AILoosePuckChase.setup_margin(puck_vel),
					sm._chase_max_accel, sm._blade_reach),
			AILoosePuckChase.reach_meet_time(traj, puck_pos, puck_vel, self_pos,
					self_vel, sm._self_max_speed, sm._blade_reach, true, true))
	var elected: Vector3 = AILoosePuckChase.path_intercept_point(traj, step_dt, puck_pos, t)
	var steered: Vector3 = sm._lead_intercept(
			self_pos, self_vel, puck_pos, puck_vel)
	assert_almost_eq(steered.distance_to(elected), 0.0, 0.001,
			"steering target is the election's own intercept point")


# The calibrated answers at the reference chases; rewrite with
# MITTS_UPDATE_SNAPSHOTS=1 (tests/snapshot.gd) and review the diff.
func test_lead_intercept_calibration_snapshot() -> void:
	var snap := Snapshot.new("res://tests/unit/ai/snapshots/lead_intercept.txt")
	snap.record("from rest, puck receding 8 m/s from 6 m: intercept z", sm._lead_intercept(
			Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 6), Vector3(0, 0, 8)).z)
	snap.record("at top speed, puck 2 m ahead at 2 m/s: intercept z", sm._lead_intercept(
			Vector3.ZERO, Vector3(0, 0, GameRules.DEFAULT_SKATER_MAX_SPEED_M_S),
			Vector3(0, 0, 2), Vector3(0, 0, 2)).z)
	snap.verify(self)


# ── Slice 2: mouse / aim motion geometry ─────────────────────────────────────
# Pure motion model — no snapshot, no role state. The output is the smooth
# _mouse_pos (per-tick cursor noise no longer exists; execution error is a
# per-release sample that never touches raw agents), so exact assertions hold.

func _self_state(facing: Vector2) -> SkaterNetworkState:
	var st := SkaterNetworkState.new()
	st.facing = facing
	return st


const ARC_MAX_STEP := Agent.MOUSE_ARC_RATE_RAD_S * Agent.MOUSE_TICK_DELTA
const STEP_MAX := Agent.MOUSE_MAX_SPEED_M_S * Agent.MOUSE_TICK_DELTA


func test_arc_step_degenerate_target_returns_target() -> void:
	# final_target on top of self → no direction to define; return it as-is.
	assert_eq(sm._arc_step_mouse_target(Vector3.ZERO, Vector3.ZERO, _self_state(Vector2(0, 1)), Agent.MOUSE_ARC_RATE_RAD_S),
			Vector3.ZERO)


func test_arc_step_result_lies_on_aim_ring() -> void:
	sm._mouse_pos_initialized = false
	var r: Vector3 = sm._arc_step_mouse_target(Vector3.ZERO, Vector3(10, 0, 0), _self_state(Vector2(0, 1)), Agent.MOUSE_ARC_RATE_RAD_S)
	assert_almost_eq(r.distance_to(Vector3.ZERO), AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, 0.0001)


func test_arc_step_caps_angular_rate() -> void:
	# Seed from facing +z (bearing 0), desired due east (bearing PI/2):
	# the step is clamped to one tick of MOUSE_ARC_RATE_RAD_S.
	sm._mouse_pos_initialized = false
	var r: Vector3 = sm._arc_step_mouse_target(Vector3.ZERO, Vector3(10, 0, 0), _self_state(Vector2(0, 1)), Agent.MOUSE_ARC_RATE_RAD_S)
	assert_almost_eq(atan2(r.x, r.z), ARC_MAX_STEP, 1e-5)


func test_arc_step_seeds_from_mouse_when_initialized() -> void:
	# Mouse parked due east; facing points +z; target points +z. If the seed
	# came from facing the result would barely move from +z — instead it steps
	# from the east seed, proving mouse-offset precedence.
	sm._mouse_pos = Vector3(2, 0, 0)
	sm._mouse_pos_initialized = true
	var r: Vector3 = sm._arc_step_mouse_target(Vector3.ZERO, Vector3(0, 0, 10), _self_state(Vector2(0, 1)), Agent.MOUSE_ARC_RATE_RAD_S)
	assert_almost_eq(atan2(r.x, r.z), PI / 2.0 - ARC_MAX_STEP, 1e-5)


func test_arc_step_converges_within_cap() -> void:
	# Desired bearing inside one tick of travel → reached exactly.
	sm._mouse_pos_initialized = false
	var desired := 0.03  # < ARC_MAX_STEP
	var ft := Vector3(sin(desired), 0, cos(desired)) * 5.0
	var r: Vector3 = sm._arc_step_mouse_target(Vector3.ZERO, ft, _self_state(Vector2(0, 1)), Agent.MOUSE_ARC_RATE_RAD_S)
	assert_almost_eq(atan2(r.x, r.z), desired, 1e-5)


func test_step_toward_first_call_snaps_and_caches() -> void:
	var r: Vector3 = sm._step_mouse_toward(Vector3(3, 0, 4))
	assert_true(sm._mouse_pos_initialized, "first call initializes the mouse")
	assert_almost_eq(sm._mouse_pos.x, 3.0, 1e-6)
	assert_almost_eq(sm._mouse_pos.z, 4.0, 1e-6)
	assert_eq(r, Vector3(3, 0, 4), "no noise → output equals mouse pos")
	assert_true(sm._has_cached_aim_target)
	assert_eq(sm._cached_aim_target, Vector3(3, 0, 4))
	assert_eq(sm._cached_aim_mode, Agent._STEP_DIRECT, "_step_mouse_toward is the direct path")


func test_step_toward_caps_travel_per_tick() -> void:
	sm._mouse_pos = Vector3.ZERO
	sm._mouse_pos_initialized = true
	sm._step_mouse_toward(Vector3(100, 0, 0))  # far east
	assert_almost_eq(sm._mouse_pos.x, STEP_MAX, 1e-5)
	assert_almost_eq(sm._mouse_pos.z, 0.0, 1e-6)


func test_step_toward_within_cap_snaps_to_target() -> void:
	sm._mouse_pos = Vector3.ZERO
	sm._mouse_pos_initialized = true
	sm._step_mouse_toward(Vector3(0.2, 0, 0.1))  # ~0.22 m < STEP_MAX
	assert_almost_eq(sm._mouse_pos.x, 0.2, 1e-6)
	assert_almost_eq(sm._mouse_pos.z, 0.1, 1e-6)


func test_the_cursor_rides_the_body_and_only_its_own_slew_is_capped() -> void:
	# The controller caps the blade's speed relative to the skater, so a body
	# skating at 9 m/s still moves the cursor a full slew step across himself.
	sm._current_self_pos = Vector3.ZERO
	sm._mouse_pos = Vector3(-1, 0, 0)
	sm._mouse_pos_initialized = true
	sm._step_mouse_toward(Vector3(-1, 0, 0))
	var travel := Vector3(0, 0, -9.0 * Agent.MOUSE_TICK_DELTA)
	sm._current_self_pos = travel
	sm._step_mouse_toward(travel + Vector3(1, 0, 0))
	assert_almost_eq(sm._mouse_pos.x, -1.0 + STEP_MAX, 1e-5, "a full step across him")
	assert_almost_eq(sm._mouse_pos.z, travel.z, 1e-6, "carried along with him")

func test_step_aim_projects_target_onto_ring() -> void:
	sm._current_self_pos = Vector3.ZERO
	sm._current_self_state = _self_state(Vector2(0, 1))
	sm._mouse_pos_initialized = false
	sm._step_mouse_aim(Vector3(10, 0, 0))  # far east; arced onto the 2 m ring
	assert_almost_eq(Vector2(sm._mouse_pos.x, sm._mouse_pos.z).length(),
			AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, 1e-4)
	assert_eq(sm._cached_aim_mode, Agent._STEP_ARC, "_step_mouse_aim is the arc path")


func test_body_face_snaps_cursor_straight_at_an_in_cone_target() -> void:
	# Off-puck body facing must NOT be gated by the bot's Hands blade slew. Like a
	# human flicking the mouse, _step_mouse_face places the cursor DIRECTLY at the
	# in-cone target and snaps to it in a single tick (no per-tick slew) — the body
	# then turns toward it at facing_drag_speed downstream. Even with a very low
	# Hands blade slew applied, the FACE cursor still snaps straight to the target.
	var slow := AISkaterCaps.new()
	slow.blade_speed = 5.0            # low Hands → slow blade slew (must not matter)
	sm.apply_capabilities(slow)
	sm._current_self_pos = Vector3.ZERO
	sm._current_self_state = _self_state(Vector2(0, 1))
	var target := Vector3(4, 0, 3)    # ~53° off +Z, well inside the reach cone
	# A prior cursor parked elsewhere — the snap must ignore it (no slew from it).
	sm._mouse_pos = Vector3(-2, 0, 0)
	sm._mouse_pos_initialized = true
	var r: Vector3 = sm._step_mouse_face(target)
	assert_eq(sm._cached_aim_mode, Agent._STEP_FACE)
	assert_almost_eq(Vector2(r.x, r.z).length(), AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, 1e-4,
			"cursor sits on the body ring in one tick, ignoring the low blade slew")
	assert_almost_eq(Vector2(r.x, r.z).angle(), Vector2(4, 3).angle(), 1e-4,
			"…pointing straight at the in-cone target, no slew")


func test_body_face_points_straight_at_a_target_behind() -> void:
	# A standing body turns round to a cursor behind it, so the cursor goes there.
	sm._current_self_pos = Vector3.ZERO
	sm._current_self_state = _self_state(Vector2(0, 1))
	sm._mouse_pos_initialized = false
	var r: Vector3 = sm._step_mouse_face(Vector3(0.3, 0, -5))
	assert_almost_eq(Vector2(r.x, r.z).angle(), Vector2(0.3, -5).angle(), 1e-4)


# ── Slice 3: shot wind-up geometry ───────────────────────────────────────────
# Pure trig on the aim direction — no snapshot, no goalie. Right-handed bot
# (is_left_handed = false → _handedness_perp_sign = -1.0).

func test_compensated_aim_is_unit_rotation_by_theta() -> void:
	var aim := Vector3(0, 0, 1)
	var dist := 5.0
	var c: Vector3 = sm._aim_dir_compensated_for_side_offset(aim, dist, 1.0)
	var theta := asin(Agent.BOT_WRISTER_SIDE_OFFSET_M / dist)
	assert_almost_eq(c.length(), 1.0, 1e-5, "compensation is a rotation, preserves length")
	assert_almost_eq(c.dot(aim), cos(theta), 1e-5, "angle off aim == asin(offset/dist)")


func test_compensated_aim_degenerate_returns_raw() -> void:
	# aim_distance <= side offset → unreachable setup; return raw aim.
	var aim := Vector3(0, 0, 1)
	assert_eq(sm._aim_dir_compensated_for_side_offset(aim, 0.1, 1.0), aim)


func test_compensated_aim_approaches_raw_at_long_range() -> void:
	var aim := Vector3(0, 0, 1)
	var c: Vector3 = sm._aim_dir_compensated_for_side_offset(aim, 1000.0, 1.0)
	assert_almost_eq(c.dot(aim), 1.0, 1e-4, "theta → 0 as distance grows")


func test_wind_up_sweep_length_equals_charge() -> void:
	var ep: Dictionary = sm._wind_up_endpoint_offsets(Vector3(0, 0, 1), 15.0, 0.7, 1.0)
	var sweep: Vector3 = ep["target"] - ep["start"]
	assert_almost_eq(sweep.length(), 0.7, 1e-5, "blade travels target_charge_m end to end")


func test_wind_up_midpoint_is_side_offset() -> void:
	var ep: Dictionary = sm._wind_up_endpoint_offsets(Vector3(0, 0, 1), 15.0, 0.7, 1.0)
	var mid: Vector3 = (ep["start"] + ep["target"]) * 0.5
	assert_almost_eq(mid.length(), Agent.BOT_WRISTER_SIDE_OFFSET_M, 1e-5,
			"both endpoints share the lateral release offset")


func test_wind_up_sweep_is_parallel_to_compensated_aim() -> void:
	var aim := Vector3(0, 0, 1)
	var ep: Dictionary = sm._wind_up_endpoint_offsets(aim, 15.0, 0.7, 1.0)
	var comp: Vector3 = sm._aim_dir_compensated_for_side_offset(aim, 15.0, 1.0)
	var sweep_dir: Vector3 = (ep["target"] - ep["start"]).normalized()
	assert_almost_eq(sweep_dir.dot(comp), 1.0, 1e-5)


# ── Slice 4: dispatch guards + decision throttle ─────────────────────────────
# The dispatch() entry guards and the throttle skip-path both return before the
# state-handler `match` (which runs role behavior), so they're testable without
# mocking the role carrier. A snapshot that can't be acted on resets the bot to
# OFF_PUCK; a throttled tick reuses the last decision instead of re-deciding.

func test_dispatch_null_snapshot_resets_off_puck() -> void:
	sm._state = Agent.State.CARRY
	sm.dispatch(InputState.new(), null)
	assert_eq(sm.get_state(), Agent.State.OFF_PUCK)


func test_dispatch_null_puck_state_resets_off_puck() -> void:
	sm._state = Agent.State.CARRY
	sm.dispatch(InputState.new(), WorldSnapshot.new())  # puck_state stays null
	assert_eq(sm.get_state(), Agent.State.OFF_PUCK)


func test_dispatch_empty_skater_states_resets_off_puck() -> void:
	sm._state = Agent.State.CARRY
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	sm.dispatch(InputState.new(), s)
	assert_eq(sm.get_state(), Agent.State.OFF_PUCK)


func test_dispatch_missing_self_resets_off_puck() -> void:
	# Snapshot has skaters but not this bot (pre-dates its spawn) → freeze.
	sm._state = Agent.State.CARRY
	var s := _loose_puck_snap(Vector3.ZERO)
	_add_skater(s, TEAMMATE_ID, Vector3.ZERO)
	sm.dispatch(InputState.new(), s)
	assert_eq(sm.get_state(), Agent.State.OFF_PUCK)


func test_dispatch_throttled_tick_reuses_cached_decision() -> void:
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3.ZERO)
	sm._state = Agent.State.OFF_PUCK  # non-press → eligible to skip
	sm._dispatch_skip_counter = 1
	sm._cached_move_vector = Vector2(0.3, -0.4)
	sm._cached_brake = true
	sm._cached_stance_held = true
	sm._cached_hit_held = true
	sm._has_cached_aim_target = true
	sm._cached_aim_target = Vector3(1, 0, 2)
	sm._cached_aim_mode = Agent._STEP_DIRECT
	var input := InputState.new()
	sm.dispatch(input, s)
	assert_eq(input.move_vector, Vector2(0.3, -0.4), "throttled tick reuses cached move")
	assert_true(input.brake, "throttled tick keeps the brake held")
	assert_true(input.stance_held, "throttled tick keeps the stance held")
	assert_true(input.hit_held, "throttled tick keeps the check committed")
	assert_eq(sm._dispatch_skip_counter, 0, "skip counter decremented")
	assert_eq(sm.get_state(), Agent.State.OFF_PUCK, "no re-decision on a skip tick")
	# Mouse re-stepped toward the cached target (no-arc → first call snaps).
	assert_almost_eq(input.mouse_world_pos.x, 1.0, 1e-6)
	assert_almost_eq(input.mouse_world_pos.z, 2.0, 1e-6)


func test_leaving_the_role_clears_the_covered_man() -> void:
	# A defender who breaks off to chase the puck covers nobody — his last
	# role decision's lock must not survive as "the man I'm on".
	sm._state = Agent.State.OFF_PUCK
	sm._prev_locked_man_pid = 7
	sm._set_state(Agent.State.CHASE_PUCK)
	assert_eq(sm._prev_locked_man_pid, -1, "chasing the puck drops the cover lock")


# ── Slice 5: press-state handlers + transitions ──────────────────────────────
# The fire states (SHOOT_PRESSED / ONE_TIMER_PRESSED / PASS_PRESSED) are
# entered by the carrier from CARRY, but once entered they run
# to completion off pre-set fields — no carrier needed. They read only the
# snapshot + this bot's identity, and every helper they touch (steering,
# shot-aim, goalie prediction) has a headless fallback (empty per-team cache →
# live partition, null goalie → aim at the net). So they're drivable through
# dispatch() directly, which also exercises the press-state throttle bypass.
#
# have_puck is read from `snapshot.real_puck_carrier_peer_id == _peer_id`
# (proprioception), NOT the reaction-delayed `puck_state.carrier_peer_id`.

func _self_snap(self_pos: Vector3, have_puck: bool) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = self_pos
	var owner_id: int = SELF_ID if have_puck else -1
	s.puck_state.carrier_peer_id = owner_id
	s.real_puck_carrier_peer_id = owner_id
	_add_skater(s, SELF_ID, self_pos)
	return s


# ── press-state dispatch throttle ────────────────────────────────────────────

func test_press_state_ignores_dispatch_throttle() -> void:
	# A non-press state with a pending skip counter would reuse its cached
	# decision; a press state must always dispatch full (charge timing is
	# tick-sensitive). Exercised via a dump's charge starting on this tick.
	sm._state = Agent.State.PASS_PRESSED
	sm._dump_target = Vector3(12, 0, 0)
	sm._dispatch_skip_counter = 5
	var i := InputState.new()
	sm.dispatch(i, _self_snap(Vector3.ZERO, true))
	assert_true(i.shoot_pressed, "press states are never throttled")
	assert_eq(sm.get_state(), Agent.State.PASS_PRESSED, "the charge holds the state")


# ── SHOOT_PRESSED (multi-tick wrister charge) ────────────────────────────────

func test_shoot_pressed_charges_then_releases_into_carry() -> void:
	sm._state = Agent.State.SHOOT_PRESSED
	var s := _self_snap(Vector3.ZERO, true)
	# Tick 0 fires the shoot_pressed edge and begins holding the charge.
	var i0 := InputState.new()
	sm.dispatch(i0, s)
	assert_true(i0.shoot_pressed, "tick 0 fires the shoot_pressed edge")
	assert_true(i0.shoot_held, "tick 0 holds the charge")
	assert_eq(sm.get_state(), Agent.State.SHOOT_PRESSED, "still charging after tick 0")
	# The edge is a one-tick event — later charge ticks don't re-press.
	var i1 := InputState.new()
	sm.dispatch(i1, s)
	assert_false(i1.shoot_pressed, "shoot_pressed is a tick-0-only edge")
	assert_true(i1.shoot_held, "still holding the charge")
	# Drive to release: shoot_held drops on the final tick and we return to CARRY.
	var released := false
	for _n in range(AIBotMechanics.BOT_WRISTER_CHARGE_TICKS + 2):
		var i := InputState.new()
		sm.dispatch(i, s)
		if sm.get_state() == Agent.State.CARRY:
			assert_false(i.shoot_held, "release tick drops shoot_held for the wrister")
			released = true
			break
		assert_true(i.shoot_held, "held high through the whole charge")
	assert_true(released, "the charge releases into CARRY within the charge budget")


func test_shoot_pressed_lost_puck_bails() -> void:
	sm._state = Agent.State.SHOOT_PRESSED
	var s := _self_snap(Vector3.ZERO, true)
	sm.dispatch(InputState.new(), s)  # tick 0 → charge begins
	assert_eq(sm.get_state(), Agent.State.SHOOT_PRESSED)
	# Puck stripped mid-charge.
	s.puck_state.carrier_peer_id = -1
	s.real_puck_carrier_peer_id = -1
	sm.dispatch(InputState.new(), s)
	assert_ne(sm.get_state(), Agent.State.SHOOT_PRESSED, "lost puck bails out of the charge")
	assert_eq(sm.get_state(), sm._post_puck_lost_state(s))


func test_shoot_pressed_stagger_cancels_via_slap() -> void:
	# A body check mid-charge (stagger_timer set) cancels the wrister rather
	# than flailing it through the hit. Cancel routes through slap_pressed (the
	# other shot button), not a release — block no longer cancels shots.
	sm._state = Agent.State.SHOOT_PRESSED
	var s := _self_snap(Vector3.ZERO, true)
	sm.dispatch(InputState.new(), s)  # tick 0 (bail only fires once charge_tick > 0)
	s.skater_states[SELF_ID].stagger_timer = 0.5
	var i := InputState.new()
	sm.dispatch(i, s)
	assert_eq(sm.get_state(), Agent.State.CARRY, "a check mid-charge cancels the wrister")
	assert_true(i.slap_pressed, "cancel routes through slap_pressed, not a shot release")


func test_shoot_pressed_front_pressure_cancels_via_slap() -> void:
	# An opponent closing from the front (toward the attacking goal) within the
	# bail radius cancels the windup. Team 0 attacks −Z.
	sm._state = Agent.State.SHOOT_PRESSED
	var s := _self_snap(Vector3.ZERO, true)
	sm.dispatch(InputState.new(), s)  # tick 0
	_add_skater(s, OPP_ID, Vector3(0, 0, -1))  # 1 m ahead, inside BOT_WRISTER_BAIL_RADIUS_M
	var i := InputState.new()
	sm.dispatch(i, s)
	assert_eq(sm.get_state(), Agent.State.CARRY, "front pressure cancels the windup")
	assert_true(i.slap_pressed)


func _wind_up_side_with_puck_at(puck_offset: Vector3) -> float:
	# A fresh right-handed bot per call, facing its attack (-Z): tick 0 reads
	# the hand from where the puck sits and locks the wind-up side.
	before_each()
	sm._state = Agent.State.SHOOT_PRESSED
	var s := _self_snap(Vector3.ZERO, true)
	s.skater_states[SELF_ID].facing = Vector2(0.0, -1.0)
	s.puck_state.position = puck_offset
	sm.dispatch(InputState.new(), s)
	return sm._shoot_side_sign


func test_wind_up_side_is_the_hand_the_puck_gives() -> void:
	# The blade freezes where the press finds the puck, so the hand is the
	# load's: beside the stick hip a shot ahead is a forehand, beside the other
	# hip a backhand, and the cosmetic wind-up is drawn on that side.
	assert_eq(_wind_up_side_with_puck_at(Vector3(0.9, 0.0, 0.0)), 1.0,
			"a puck beside a right-hander's stick hip winds up on the forehand")
	assert_eq(_wind_up_side_with_puck_at(Vector3(-0.9, 0.0, 0.0)), -1.0,
			"one beside the other hip winds up on the backhand")


func test_shoot_pressed_ignores_rear_pressure() -> void:
	# The bail is forward-only: a backchecker behind the shooter (toward our own
	# net, +Z for team 0) can't disrupt the windup and must not cancel a clean shot.
	sm._state = Agent.State.SHOOT_PRESSED
	var s := _self_snap(Vector3.ZERO, true)
	sm.dispatch(InputState.new(), s)  # tick 0
	_add_skater(s, OPP_ID, Vector3(0, 0, 1))  # 1 m behind
	sm.dispatch(InputState.new(), s)
	assert_eq(sm.get_state(), Agent.State.SHOOT_PRESSED, "rear pressure does not cancel the charge")


# ── ONE_TIMER_PRESSED (the real slapper one-timer: wind up, settle, release) ─

func _inbound_feed_snap(self_pos: Vector3, puck_pos: Vector3,
		puck_vel: Vector3) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = puck_pos
	s.puck_state.velocity = puck_vel
	s.puck_state.carrier_peer_id = -1
	_add_skater(s, SELF_ID, self_pos)
	return s


# A feed along +X whose line runs through this bot's slapper circle, `ahead_m`
# metres short of it.
func _feed_through_circle(ahead_m: float) -> WorldSnapshot:
	var zone: Vector3 = sm._one_timer.zone_center(Vector3.ZERO, sm._attacking_goal_pos)
	return _inbound_feed_snap(Vector3.ZERO, Vector3(zone.x - ahead_m, 0, zone.z),
			Vector3(16, 0, 0))


func test_one_timer_winds_up_the_slapper_through_the_flight() -> void:
	# A live feed inbound: tick 0 presses SLAP (the real slapper one-timer —
	# the diegetic wind-up the controller animates) and holds it while the
	# feed flies. On attachment (the controller's one-timer window) the button
	# drops and release_slapper fires.
	sm._state = Agent.State.ONE_TIMER_PRESSED
	var s := _feed_through_circle(8.0)
	var i0 := InputState.new()
	sm.dispatch(i0, s)
	assert_true(i0.slap_pressed, "tick 0 presses the slap charge")
	assert_true(i0.slap_held, "the wind-up holds while the feed is in flight")
	assert_eq(sm.get_state(), Agent.State.ONE_TIMER_PRESSED, "keeps waiting off-puck")
	# Puck attaches mid-charge → the window opens → release.
	s.real_puck_carrier_peer_id = SELF_ID
	var i1 := InputState.new()
	sm.dispatch(i1, s)
	assert_false(i1.slap_held, "release drops slap_held inside the window")
	assert_eq(sm.get_state(), Agent.State.CARRY)


func test_one_timer_bails_when_the_feed_dies() -> void:
	# No live inbound line and no puck at the zone (picked off / deflected
	# dead): drop the swing (honest whiff) and get back into the play.
	sm._state = Agent.State.ONE_TIMER_PRESSED
	var s := _self_snap(Vector3(4, 0, 4), false)   # stationary dead puck
	var i := InputState.new()
	sm.dispatch(i, s)
	assert_false(i.slap_held, "a dead feed releases the swing")
	assert_eq(sm.get_state(), sm._post_puck_lost_state(s), "back into the play")


func test_one_timer_budget_backstop_bails() -> void:
	# Even with a (pathologically) ever-inbound feed, the press budget bails.
	sm._state = Agent.State.ONE_TIMER_PRESSED
	sm._one_timer_press_tick = Agent.ONE_TIMER_PRESS_MAX_TICKS - 1
	var s := _inbound_feed_snap(Vector3.ZERO, Vector3(-8, 0, -1.5), Vector3(16, 0, 0))
	var i := InputState.new()
	sm.dispatch(i, s)
	assert_false(i.slap_held, "budget backstop releases")
	assert_ne(sm.get_state(), Agent.State.ONE_TIMER_PRESSED, "and exits the press")


func test_one_timer_settles_onto_the_live_feed_line() -> void:
	# The feed crosses 3 m net-side of the waiting shooter: the body seeks the
	# live-line settle anchor (walking the slapper ZONE onto the pass's real
	# path) rather than braking on the spot it anticipated.
	sm._state = Agent.State.ONE_TIMER_PRESSED
	var s := _inbound_feed_snap(Vector3.ZERO, Vector3(-8, 0, -3.0), Vector3(16, 0, 0))
	var i := InputState.new()
	sm.dispatch(i, s)
	assert_lt(i.move_vector.y, -0.3, "shuffles toward the actual crossing line")


func test_one_timer_press_waits_for_the_pivot_to_fit_the_flight() -> void:
	# Wound up, the hips pivot into the stance at their own rate and the circle
	# turns with them (SkaterAgentOneTimer.time_to_set). Turned square away from
	# the stance (0.4 s of pivot) against a feed 5 m out at 16 m/s, the press waits;
	# opened side-on to the net, it fires.
	sm._state = Agent.State.ONE_TIMER_PRESSED
	var s := _feed_through_circle(5.0)
	var stance: Vector2 = sm._one_timer.stance_facing(Vector2(0, -1))
	s.skater_states[SELF_ID].facing = -stance
	var i0 := InputState.new()
	sm.dispatch(i0, s)
	assert_false(i0.slap_pressed, "no press while the pivot outlasts the feed")
	assert_false(i0.slap_held, "…and nothing to hold yet")
	assert_eq(sm.get_state(), Agent.State.ONE_TIMER_PRESSED, "still waiting on the feed")
	s.skater_states[SELF_ID].facing = stance
	var i1 := InputState.new()
	sm.dispatch(i1, s)
	assert_true(i1.slap_pressed, "opened up — the press fires with a real net aim")
	assert_true(i1.slap_held, "…and the wind-up holds")


func test_one_timer_aborts_when_the_feed_beats_the_set() -> void:
	# A feed arriving before a wind-up could open the one-timer's window, with
	# the body still unable to set for it, is caught instead of swung at.
	# Nothing was pressed, so no slapper charge to cancel.
	sm._state = Agent.State.ONE_TIMER_PRESSED
	var s := _feed_through_circle(2.0)
	s.skater_states[SELF_ID].facing = -sm._one_timer.stance_facing(Vector2(0, -1))
	var i := InputState.new()
	sm.dispatch(i, s)
	assert_false(i.slap_pressed, "an unset wind-up is not fired wide")
	assert_ne(sm.get_state(), Agent.State.ONE_TIMER_PRESSED, "it bails to catch instead")


func test_oz_receiver_stance_opens_hips_between_puck_and_net() -> void:
	# A teammate has the puck and we're camped in the OZ — we're a candidate
	# receiver, so the near-anchor ready stance splits between the play and
	# the net (the puck-net bisector) instead of staring straight at the
	# puck: the catch lands with the shot already loaded.
	var self_pos := Vector3(0, 0, -15)
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(8, 0, -15)
	s.puck_state.carrier_peer_id = TEAMMATE_ID
	_add_skater(s, SELF_ID, self_pos)
	_add_skater(s, TEAMMATE_ID, Vector3(8, 0, -15))
	var dir: Vector3 = sm._compute_desired_aim_dir(self_pos, self_pos, s)
	assert_gt(dir.x, 0.4, "the play stays in front of the stance")
	assert_lt(dir.z, -0.4, "…and the hips open toward the net")


func test_defensive_watching_still_faces_the_puck() -> void:
	# An OPPONENT carrier in the same geometry: eyes stay on the threat —
	# the open-hips split is a receiver's stance, not a defender's.
	var self_pos := Vector3(0, 0, -15)
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(8, 0, -15)
	s.puck_state.carrier_peer_id = OPP_ID
	_add_skater(s, SELF_ID, self_pos)
	_add_skater(s, OPP_ID, Vector3(8, 0, -15))
	var dir: Vector3 = sm._compute_desired_aim_dir(self_pos, self_pos, s)
	assert_gt(dir.x, 0.9, "faces the carrier square")
	assert_gt(dir.z, -0.1, "no net bias while defending")


func test_aim_flip_is_debounced_at_the_near_anchor_boundary() -> void:
	# A bot orbiting right at FACE_THREAT_NEAR_ANCHOR_M used to swing the aim
	# between the anchor (far) and the puck/threat (near) every dispatch. The
	# hysteresis band latches the mode: crossing the raw threshold is not enough,
	# the distance must clear a full band past it before the direction flips.
	# self at origin, anchor down -z, a loose puck (threat) out +x — anchor-dir
	# and threat-dir are ~90° apart, so a flip is unambiguous in the output.
	var self_pos := Vector3.ZERO
	var s := _loose_puck_snap(Vector3(10, 0, 0))   # threat_dir ≈ +x
	var near_m: float = Agent.FACE_THREAT_NEAR_ANCHOR_M   # 6.0
	var band: float = Agent.FACE_NEAR_ANCHOR_HYSTERESIS_M # 0.75

	# Start clearly FAR → aims the anchor (−z).
	var far_anchor := Vector3(0, 0, -(near_m + band + 2.0))
	assert_lt(sm._compute_desired_aim_dir(self_pos, far_anchor, s).z, -0.9,
			"clearly far: aims the anchor")
	# Ease inside the RAW threshold but still within the band — latch holds far.
	var boundary_anchor := Vector3(0, 0, -(near_m - 0.25))
	assert_lt(sm._compute_desired_aim_dir(self_pos, boundary_anchor, s).z, -0.9,
			"just inside the threshold but within the band: still aims the anchor")
	# Clear the band on the near side → flips to the threat (+x).
	var near_anchor := Vector3(0, 0, -(near_m - band - 1.0))
	assert_gt(sm._compute_desired_aim_dir(self_pos, near_anchor, s).x, 0.9,
			"past the band: flips to the threat")
	# Drift back inside the raw threshold from below — latch holds near.
	assert_gt(sm._compute_desired_aim_dir(self_pos, boundary_anchor, s).x, 0.9,
			"back within the band from the near side: still aims the threat")
	# Clear the band on the far side → flips back to the anchor.
	assert_lt(sm._compute_desired_aim_dir(self_pos, far_anchor, s).z, -0.9,
			"past the far edge of the band: flips back to the anchor")


func test_live_off_puck_aim_tracks_the_carrier_puck_during_a_jab() -> void:
	# On skipped throttle ticks an ACTIVE poke-jab re-derives its aim from the
	# CURRENT carrier puck position (the counters advance on dispatch, but the
	# stab tracks live so the swept blade actually sweeps THROUGH the moving
	# puck). The helper returns the live puck point while _off_puck_jab_live.
	var self_pos := Vector3.ZERO
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(1.4, 0, 0)
	s.puck_state.carrier_peer_id = OPP_ID
	_add_skater(s, OPP_ID, Vector3(1.6, 0, 0))
	sm._off_puck_jab_live = true
	var aim: Vector3 = sm._off_puck_live_aim(s, self_pos)
	assert_almost_eq(aim.x, 1.4, 0.001, "jab aim tracks the live carrier puck")
	# Puck slides; the live re-derive follows it (a staircased stab would lag).
	s.puck_state.position = Vector3(1.1, 0, 0.5)
	aim = sm._off_puck_live_aim(s, self_pos)
	assert_almost_eq(aim.x, 1.1, 0.001, "…and keeps following as it moves")
	assert_almost_eq(aim.z, 0.5, 0.001, "…on both axes")
	# Carrier releases (loose puck) → no carrier to jab → INF, fall to cached.
	s.puck_state.carrier_peer_id = -1
	assert_false(sm._off_puck_live_aim(s, self_pos).is_finite(),
			"no opposing carrier → no live jab target")


func test_man_to_beat_reads_reach_not_proximity() -> void:
	# The square-to-net facing hinges on _has_man_to_beat, which reads the
	# carrier's published forward-puck clearance (metres of room the presented
	# puck has from the nearest un-beaten stick) rather than a distance band.
	# EVADE_SAFE_CLEAR_MIN_M — a blade of real air — is the bar.
	var bar: float = Agent.CARRY_MAN_TO_BEAT_CLEAR_M
	sm._carry_has_man = false
	sm._carrier.forward_puck_clearance = bar + 0.01
	assert_false(sm._has_man_to_beat(), "a blade of air on the forward puck: no man")
	sm._carrier.forward_puck_clearance = bar - 0.01
	assert_true(sm._has_man_to_beat(), "a stick inside that: a man to beat")
	# Sticky: while a man is engaged the bar drops, so a defender riding the
	# boundary holds the prior answer instead of flipping the whole carry aim.
	sm._carrier.forward_puck_clearance = bar + 0.01
	assert_true(sm._has_man_to_beat(),
			"riding the boundary holds the prior answer (sticky)")
	# Open more than the sustain band and he is finally beaten.
	sm._carrier.forward_puck_clearance = \
			bar + Agent.CARRY_MAN_TO_BEAT_HYSTERESIS_M + 0.01
	assert_false(sm._has_man_to_beat(), "past the sustain band: man beaten")


func test_a_defender_abreast_but_out_of_reach_is_not_a_man_to_beat() -> void:
	# The defect the reach read exists to remove, driven through the real
	# carrier: a defender level with the carrier but wide of him projects ~0
	# along the netward line, so the old goal-side radius counted him and held
	# the square-to-net facing off — while no stick of his could touch the puck.
	# Team 0 attacks -z.
	var carrier := AIRoleCarrier.new()
	var stride := Vector3(0, 0, -9.0)
	var ctx := _carry_ctx(Vector3.ZERO, stride, Vector3(3.0, 0, 0.0), stride)
	carrier.decide(ctx)
	gut.p("  abreast and 3 m wide: forward-puck clearance %.2f m (bar %.2f)"
			% [carrier.forward_puck_clearance, Agent.CARRY_MAN_TO_BEAT_CLEAR_M])
	assert_gt(carrier.forward_puck_clearance, Agent.CARRY_MAN_TO_BEAT_CLEAR_M,
			"a defender abreast but a stick-and-a-half wide cannot reach the puck")
	# …and the same defender ON the puck line in front very much can.
	var tight := _carry_ctx(Vector3.ZERO, stride, Vector3(0.3, 0, -1.2), stride)
	var pressed := AIRoleCarrier.new()
	pressed.decide(tight)
	gut.p("  in front at 1.2 m: forward-puck clearance %.2f m"
			% pressed.forward_puck_clearance)
	assert_lt(pressed.forward_puck_clearance, Agent.CARRY_MAN_TO_BEAT_CLEAR_M,
			"a stick in front of the puck is a man to beat")


# A carrier at `self_pos` with `self_vel`, one opponent at `opp_pos`, attacking -z.
func _carry_ctx(self_pos: Vector3, self_vel: Vector3, opp_pos: Vector3,
		opp_vel: Vector3 = Vector3.ZERO) -> RoleContext:
	var snap := WorldSnapshot.new()
	for entry: Array in [[SELF_ID, self_pos, self_vel], [OPP_ID, opp_pos, opp_vel]]:
		var sk := SkaterNetworkState.new()
		sk.position = entry[1]
		sk.velocity = entry[2]
		sk.facing = Vector2(0.0, -1.0)
		snap.skater_states[entry[0]] = sk
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = SELF_ID
	puck.position = self_pos
	snap.puck_state = puck
	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.self_velocity = self_vel
	ctx.team_id = 0
	ctx.peer_id = SELF_ID
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = {SELF_ID: 0, OPP_ID: 1}
	return ctx


func test_threat_facing_fallback_is_debounced() -> void:
	# _face_threat_or_current holds facing when the puck is inside a geometry
	# floor (too close to aim by). A bare threshold flipped the ready-stance aim
	# between the puck and frozen facing per tick; the band latches it.
	var self_pos := Vector3.ZERO
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	_add_skater(s, SELF_ID, self_pos)
	s.skater_states[SELF_ID].facing = Vector2(1, 0)   # facing +x
	# Puck clearly beyond the floor (+z) → aims at the puck.
	s.puck_state.position = Vector3(0, 0, 1.0)
	assert_gt(sm._face_threat_or_current(s, self_pos).z, 0.9, "far puck: aims at it")
	# Eases inside the raw floor (0.3) but within the band → still aims the puck.
	s.puck_state.position = Vector3(0, 0, 0.25)
	assert_gt(sm._face_threat_or_current(s, self_pos).z, 0.9,
			"inside the floor but within the band: still aims the puck")
	# Clear the band on the near side (< 0.15) → holds facing (+x).
	s.puck_state.position = Vector3(0, 0, 0.1)
	assert_gt(sm._face_threat_or_current(s, self_pos).x, 0.9, "past the near band: holds facing")
	# Drift back inside the floor from below → latched close, still holds facing.
	s.puck_state.position = Vector3(0, 0, 0.25)
	assert_gt(sm._face_threat_or_current(s, self_pos).x, 0.9,
			"back within the band from close: still holds facing")
	# Clear the band on the far side (> 0.45) → re-aims the puck.
	s.puck_state.position = Vector3(0, 0, 0.5)
	assert_gt(sm._face_threat_or_current(s, self_pos).z, 0.9, "past the far band: re-aims the puck")


func test_carry_entry_resets_the_smoothed_shield() -> void:
	# A fresh pickup must not inherit a phantom shield (or a stale man-to-beat
	# latch) from a previous carry — _set_state zeroes them on CARRY entry so the
	# shield eases in from nothing.
	sm._state = Agent.State.OFF_PUCK
	sm._carry_protect_gain_smooth = 0.8
	sm._carry_protect_offset_smooth = Vector3(1, 0, 0)
	sm._carry_has_man = true
	sm._set_state(Agent.State.CARRY)
	assert_eq(sm._carry_protect_gain_smooth, 0.0, "shield gain resets on carry entry")
	assert_eq(sm._carry_protect_offset_smooth, Vector3.ZERO, "shield offset resets on carry entry")
	assert_false(sm._carry_has_man, "man-to-beat latch resets on carry entry")


# ── incoming-feed reception: give with the puck ──────────────────────────────

func test_receiver_gives_with_a_hot_incoming_feed() -> void:
	# A feed inbound at pace with the receiver skating INTO it: the catch gate
	# judges the puck in the RECEIVER'S frame, so the bot's own closing stacks
	# onto the puck's — over the receivable ceiling it brakes (sheds its own
	# closing) and never sprints at the feed.
	# Staged in OUR half so the shot reception's catch-and-shoot posture
	# (Mode B) never engages — this pins the plain reception path.
	sm._state = Agent.State.CHASE_PUCK
	var s := _loose_puck_snap(Vector3(-10, 0, 15))
	s.puck_state.velocity = Vector3(18, 0, 0)
	_add_skater(s, SELF_ID, Vector3(0, 0, 15))
	s.skater_states[SELF_ID].velocity = Vector3(-4, 0, 0)   # charging the feed
	s.skater_states[SELF_ID].facing = Vector2(-1, 0)
	var i := InputState.new()
	sm.dispatch(i, s)
	assert_true(i.brake, "over the receiver-frame ceiling — give with the puck")


func test_receiver_in_stride_keeps_skating_on_a_soft_feed() -> void:
	# The same inbound geometry at a catchable relative pace: reception stays
	# IN STRIDE — no brake, the blade gate does the catching.
	sm._state = Agent.State.CHASE_PUCK
	var s := _loose_puck_snap(Vector3(-10, 0, 15))
	s.puck_state.velocity = Vector3(15, 0, 0)
	_add_skater(s, SELF_ID, Vector3(0, 0, 15))
	s.skater_states[SELF_ID].velocity = Vector3(-1, 0, 0)   # settled at the gate
	s.skater_states[SELF_ID].facing = Vector2(-1, 0)
	var i := InputState.new()
	sm.dispatch(i, s)
	assert_false(i.brake, "a catchable relative pace keeps the in-stride reception")


func test_far_chase_faces_its_route() -> void:
	# The far-chase cursor is FACE-aimed (snapped pointing intent), so the bot
	# looks down its chase line immediately instead of arc-swinging the cursor
	# for seconds while skating sideways.
	sm._state = Agent.State.CHASE_PUCK
	var s := _loose_puck_snap(Vector3(10, 0, -10))
	_add_skater(s, SELF_ID, Vector3.ZERO)
	s.skater_states[SELF_ID].facing = Vector2(0, -1)
	var i := InputState.new()
	sm.dispatch(i, s)
	var mouse_dir := Vector2(i.mouse_world_pos.x, i.mouse_world_pos.z).normalized()
	var to_puck := Vector2(10, -10).normalized()
	assert_gt(mouse_dir.dot(to_puck), 0.85,
			"the chase cursor points down the pursuit line on the first tick")


# ── PASS_PRESSED ─────────────────────────────────────────────────────────────

func test_pass_pressed_lost_puck_bails_and_clears() -> void:
	sm._state = Agent.State.PASS_PRESSED
	sm._pass_should_saucer = true
	sm._pass_target_peer_id = TEAMMATE_ID
	var s := _self_snap(Vector3.ZERO, false)  # no puck
	sm.dispatch(InputState.new(), s)
	assert_ne(sm.get_state(), Agent.State.PASS_PRESSED, "lost puck bails")
	assert_eq(sm.get_state(), sm._post_puck_lost_state(s))
	assert_eq(sm._pass_target_peer_id, -1, "bail clears the stale pass target")
	assert_false(sm._pass_should_saucer, "bail clears the saucer flag")


func test_pass_pressed_charged_releases_after_windup() -> void:
	sm._state = Agent.State.PASS_PRESSED
	sm._pass_target_peer_id = TEAMMATE_ID
	var s := _self_snap(Vector3.ZERO, true)
	_add_skater(s, TEAMMATE_ID, Vector3(8, 0, 0))
	var released := false
	for _n in range(AIBotMechanics.BOT_WRISTER_CHARGE_TICKS + 2):
		var i := InputState.new()
		sm.dispatch(i, s)
		if sm.get_state() == Agent.State.CARRY:
			assert_false(i.shoot_held, "charged pass releases by dropping shoot_held")
			released = true
			break
		assert_true(i.shoot_held, "held high through the charge")
	assert_true(released, "the charged pass releases within the charge budget")
	assert_eq(sm._pass_target_peer_id, -1, "release clears the pass target")


func test_pass_pressed_rim_charges_flat_at_its_searched_pace() -> void:
	# The rim pass (AIRimPass) walks its path at a searched pace, and the one-tick
	# quick release only fires at the fixed quick-pass pace, which would die in
	# the first corner. So the rim takes the charged wrister at _dump_launch_speed,
	# FLAT: a charged release normalizes (dir.x, tan, dir.z) at its power, so any
	# loft spends pace going up and the puck's ground speed stops being the pace
	# the search walked.
	sm._state = Agent.State.PASS_PRESSED
	sm._dump_target = Vector3(20, 0, 0)
	sm._dump_launch_speed = 26.4
	var i := InputState.new()
	sm.dispatch(i, _self_snap(Vector3.ZERO, true))
	assert_eq(i.elevation_level, ShotMechanics.ELEVATION_FLAT, "a rim rides the ice")
	assert_eq(sm._pass_target_speed, 26.4, "…at the pace its search walked")
	assert_eq(sm.get_state(), Agent.State.PASS_PRESSED, "the charge holds the state")

	# …and the wind-up spends the dump target when it finally releases (the
	# quick-release branch, which normally clears it, never runs for a rim).
	var released: bool = false
	for _t: int in range(AIBotMechanics.BOT_WRISTER_CHARGE_TICKS + 4):
		var t := InputState.new()
		sm.dispatch(t, _self_snap(Vector3.ZERO, true))
		if sm.get_state() == Agent.State.CARRY:
			released = true
			break
	assert_true(released, "the charged rim releases within the charge budget")
	assert_false(sm._dump_target.is_finite(), "releasing clears the dump target")


func test_pass_pressed_dump_lost_puck_clears_target() -> void:
	# Puck knocked loose before the dump fires — bail clears the dump target so a
	# later PASS/DUMP starts fresh.
	sm._state = Agent.State.PASS_PRESSED
	sm._dump_target = Vector3(12, 0, 0)
	sm.dispatch(InputState.new(), _self_snap(Vector3.ZERO, false))  # no puck
	assert_ne(sm.get_state(), Agent.State.PASS_PRESSED, "lost puck bails")
	assert_false(sm._dump_target.is_finite(), "bail clears the dump target")


# ── Slice 6: CARRY handler + carrier-driven transitions ──────────────────────
# _state_carry is the one handler that runs the AIRoleCarrier scoring behavior.
# We swap in a stub carrier (a subclass that publishes a scripted intent instead
# of scoring) so the CARRY handler's own logic — the puck-loss bail, the
# intent→State mapping, the pre-aim-then-fire commit, the hysteresis hold, and
# the timeout — is tested in isolation from the scorer. The stub also spies on
# clear_intent / reset so we can assert the handler drives the carrier's
# re-eval lifecycle as documented.

# Stub carrier: publishes `next_intent` (+ anchor / pass target) into the mirror
# fields the SM reads after decide(), and counts the lifecycle calls. Subclasses
# the real carrier so it satisfies the SM's typed `_carrier` field; super() on
# the lifecycle methods keeps the real field-clearing so SM invariants hold.
class _CarrierStub extends AIRoleCarrier:
	var decide_calls: int = 0
	var clear_intent_calls: int = 0
	var reset_calls: int = 0
	var next_intent: int = AIRoleCarrier.INTENT_CARRY
	var next_anchor: Vector3 = Vector3.ZERO
	var next_pass_target: int = -1
	var next_dump_target: Vector3 = Vector3.INF

	func decide(_ctx: RoleContext) -> RoleDecision:
		decide_calls += 1
		intended_action = next_intent
		last_carry_anchor = next_anchor
		pass_target_peer_id = next_pass_target
		dump_target = next_dump_target
		return RoleDecision.new()

	func clear_intent() -> void:
		clear_intent_calls += 1
		super()

	func reset() -> void:
		reset_calls += 1
		super()


func _stub_carry(intent: int, anchor: Vector3 = Vector3.ZERO,
		pass_target: int = -1) -> _CarrierStub:
	var carrier_stub := _CarrierStub.new()
	carrier_stub.next_intent = intent
	carrier_stub.next_anchor = anchor
	carrier_stub.next_pass_target = pass_target
	sm._carrier = carrier_stub
	sm._state = Agent.State.CARRY
	return carrier_stub


func test_carry_lost_puck_bails_and_resets_carrier() -> void:
	var carrier_stub := _stub_carry(AIRoleCarrier.INTENT_CARRY)
	sm._intended_action = Agent.State.SHOOT_PRESSED  # some stale intent to clear
	sm._pass_target_peer_id = TEAMMATE_ID
	var s := _self_snap(Vector3.ZERO, false)  # no puck
	sm.dispatch(InputState.new(), s)
	assert_ne(sm.get_state(), Agent.State.CARRY, "no puck leaves CARRY")
	assert_eq(sm.get_state(), sm._post_puck_lost_state(s))
	assert_eq(sm._intended_action, Agent.State.CARRY, "stale intent cleared on bail")
	assert_eq(sm._pass_target_peer_id, -1, "pass target cleared on bail")
	assert_eq(carrier_stub.reset_calls, 1, "the carrier is reset when the puck is lost")


func test_carry_intent_carry_stays_and_steers_to_anchor() -> void:
	# CARRY intent → no transition; steer toward the carrier's anchor.
	_stub_carry(AIRoleCarrier.INTENT_CARRY, Vector3(6, 0, 0))
	var i := InputState.new()
	sm.dispatch(i, _self_snap(Vector3.ZERO, true))
	assert_eq(sm.get_state(), Agent.State.CARRY, "carry intent holds CARRY")
	assert_eq(sm._intended_action, Agent.State.CARRY)
	assert_gt(i.move_vector.x, 0.0, "steers toward the carry anchor at +X")


func test_carry_shoot_intent_commits_to_shoot_pressed() -> void:
	_stub_carry(AIRoleCarrier.INTENT_SHOOT)
	var s := _self_snap(Vector3.ZERO, true)
	# Point facing at the attacking goal (−Z for team 0) so pre-aim converges fast.
	s.skater_states[SELF_ID].facing = Vector2(0, -1)
	var committed := false
	for _n in range(sm._intent_max_wait_ticks + 2):
		sm.dispatch(InputState.new(), s)
		if sm.get_state() == Agent.State.SHOOT_PRESSED:
			committed = true
			break
		assert_eq(sm.get_state(), Agent.State.CARRY, "still pre-aiming until convergence")
	assert_true(committed, "shoot intent pre-aims then commits to SHOOT_PRESSED")


func test_carry_intent_maps_to_matching_press_state() -> void:
	# The intent→State mapping for each fire kind. Manipulate the pre-aim lock +
	# tick budget so the commit fires on the first dispatch regardless of aim
	# geometry (timeout path), isolating the mapping.
	var cases := {
		AIRoleCarrier.INTENT_SHOOT: Agent.State.SHOOT_PRESSED,
		AIRoleCarrier.INTENT_PASS: Agent.State.PASS_PRESSED,
	}
	for intent: int in cases:
		before_each()  # fresh SM per case
		var carrier_stub := _stub_carry(intent, Vector3.ZERO, TEAMMATE_ID)
		var s := _self_snap(Vector3.ZERO, true)
		_add_skater(s, TEAMMATE_ID, Vector3(4, 0, 0))
		# Force the timeout branch on the first pre-aim tick: after tick-0 sets
		# _intended_action, the convergence gate sees wait >= max and commits.
		sm._intent_max_wait_ticks = 0
		var landed: int = -1
		for _n in range(3):
			sm.dispatch(InputState.new(), s)
			if sm.get_state() != Agent.State.CARRY:
				landed = sm.get_state()
				break
		assert_eq(landed, cases[intent], "intent %d maps to its press state" % intent)
		assert_eq(carrier_stub.clear_intent_calls, 1, "commit forces a carrier re-eval")


func test_carry_dump_intent_commits_and_freezes_target() -> void:
	# INTENT_DUMP maps to PASS_PRESSED (the reused release path) and the dump
	# target is captured at commit. Force the timeout branch so the commit lands
	# on the first pre-aim tick, isolating the mapping + freeze from aim geometry.
	var carrier_stub := _stub_carry(AIRoleCarrier.INTENT_CARRY)
	carrier_stub.next_intent = AIRoleCarrier.INTENT_DUMP
	carrier_stub.next_dump_target = Vector3(12, 0, 5)
	sm._intent_max_wait_ticks = 0
	var s := _self_snap(Vector3.ZERO, true)
	var landed: int = -1
	for _n in range(3):
		sm.dispatch(InputState.new(), s)
		if sm.get_state() != Agent.State.CARRY:
			landed = sm.get_state()
			break
	assert_eq(landed, Agent.State.PASS_PRESSED, "a dump commits to the PASS_PRESSED release path")
	assert_eq(sm._dump_target, Vector3(12, 0, 5), "the dump target is frozen at commit")
	assert_eq(carrier_stub.clear_intent_calls, 1, "commit forces a carrier re-eval")


func test_carry_holds_intent_against_carrier_flip() -> void:
	# Hysteresis: once a fire intent is locked and the bot is pre-aiming, a
	# carrier that flips back to CARRY must NOT cancel the pending shot.
	_stub_carry(AIRoleCarrier.INTENT_CARRY)  # carrier now wants CARRY
	sm._intended_action = Agent.State.SHOOT_PRESSED       # but we're mid-pre-aim
	sm._intent_wait_ticks = 0
	# Priced at full load with the puck still unloaded at the body, so the press
	# can't fire this tick.
	sm._locked_pre_aim_point = Vector3(0, 0, -20)
	sm._shot_hold_share_locked = 1.0
	sm.dispatch(InputState.new(), _self_snap(Vector3.ZERO, true))
	assert_eq(sm._intended_action, Agent.State.SHOOT_PRESSED,
			"a carrier CARRY flip does not cancel the pending shot")
	assert_eq(sm.get_state(), Agent.State.CARRY, "still pre-aiming, not yet committed")
	assert_gt(sm._intent_wait_ticks, 0, "the pre-aim wait counter advances")


func test_carry_pre_aim_times_out_and_fires() -> void:
	# Even with the cursor never converging, the pre-aim commits once the wait
	# counter reaches the timeout — the safety hatch against a never-arriving aim.
	_stub_carry(AIRoleCarrier.INTENT_SHOOT)
	sm._intended_action = Agent.State.SHOOT_PRESSED
	sm._intent_wait_ticks = sm._intent_max_wait_ticks  # at the timeout threshold
	sm._mouse_max_speed_m_s = 0.0001
	sm._mouse_pos = Vector3(50, 0, 50)  # nowhere near the aim
	sm._mouse_pos_initialized = true
	sm.dispatch(InputState.new(), _self_snap(Vector3.ZERO, true))
	assert_eq(sm.get_state(), Agent.State.SHOOT_PRESSED, "timeout commits the shot anyway")


# ── Wrister wind-up handedness (regression: the perp sign was inverted, so bots
# charged every wrister/pass on the backhand side and paid the backhand penalty).
# Authoritative reference: SkaterAgentReception.read_shot defines RH forehand as
# -left_dir where left_dir = Vector3(aim.z, 0, -aim.x); LH mirrors. The wind-up
# midpoint offset = perp * SIDE_OFFSET (the ±aim*half endpoints cancel), so its
# projection onto the forehand direction must be positive on the forehand side. ─

func _windup_midpoint(agent: SkaterAgentStateMachine, aim_dir: Vector3, side_sign: float) -> Vector3:
	# aim_distance well past SIDE_OFFSET so the compensation tilt is tiny and the
	# degenerate guard doesn't fire; target_charge arbitrary positive.
	var e: Dictionary = agent._wind_up_endpoint_offsets(aim_dir, 10.0, 0.5, side_sign)
	return (e.start as Vector3 + e.target as Vector3) * 0.5

func _forehand_dir(aim_dir: Vector3, is_left_handed: bool) -> Vector3:
	var left_dir := Vector3(aim_dir.z, 0.0, -aim_dir.x)
	return left_dir if is_left_handed else -left_dir

func test_windup_forehand_side_right_handed() -> void:
	# sm from before_each is right-handed. For several aim directions the wind-up
	# must sit on the forehand side (positive dot with the reception forehand dir).
	for aim: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0, -1).normalized(), Vector3(-1, 0, -1).normalized()]:
		var mid: Vector3 = _windup_midpoint(sm, aim, 1.0)
		assert_gt(mid.dot(_forehand_dir(aim, false)), 0.0,
				"RH wind-up on the forehand side for aim %s" % aim)

func test_windup_forehand_side_left_handed() -> void:
	var lh := Agent.new()
	lh.setup(SELF_ID, 0, TeamBrain.new(0, _team_map), _team_map, true)  # left-handed
	for aim: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0, -1).normalized(), Vector3(-1, 0, -1).normalized()]:
		var mid: Vector3 = _windup_midpoint(lh, aim, 1.0)
		assert_gt(mid.dot(_forehand_dir(aim, true)), 0.0,
				"LH wind-up on the forehand side for aim %s" % aim)

func test_windup_side_flip_moves_to_backhand() -> void:
	# The defender-driven side flip (side_sign = -1) must move the wind-up to the
	# opposite (backhand) side, i.e. negative dot with the forehand dir.
	var aim := Vector3(0, 0, -1)
	var mid: Vector3 = _windup_midpoint(sm, aim, -1.0)
	assert_lt(mid.dot(_forehand_dir(aim, false)), 0.0,
			"side-flip moves the RH wind-up to the backhand side")


# ── Receive in stride vs settle ──────────────────────────────────────────────
# The side-stand reception only settles (arrival brake) when arriving AND
# stopping both fit before the puck; a tight window takes the feed in stride.

func _receive_snap(puck_pos: Vector3, puck_vel: Vector3,
		self_pos: Vector3, self_vel: Vector3) -> WorldSnapshot:
	var s := _loose_puck_snap(puck_pos)
	s.puck_state.velocity = puck_vel
	_add_skater(s, SELF_ID, self_pos)
	s.skater_states[SELF_ID].velocity = self_vel
	return s


func test_receive_takes_the_feed_in_stride_when_roughly_synced() -> void:
	# Puck closing at 20 with the crossing ~0.7 s out; bot 4 m off the line at
	# 6 m/s arrives inside its own blade window of the puck — running through
	# the reception keeps the blade on the line when the puck gets there, so no
	# brake: full speed through the catch (stride is the DEFAULT now).
	# (Coordinates kept inside the real rink — the receive geometry is
	# board-aware now, so an out-of-rink stance would be clamped.)
	var s := _receive_snap(Vector3(-14, 0, 0), Vector3(20, 0, 0),
			Vector3(0, 0, 4), Vector3(0, 0, -6))
	var input := InputState.new()
	assert_true(sm._pass_receive_aim_and_steer(input, s, Vector3(0, 0, 4)),
			"scenario commits the reception")
	assert_false(input.brake, "synced arrival → take it in stride, no arrival brake")


func test_receive_settles_only_when_genuinely_early() -> void:
	# Bot already sitting ON the anchor at 4 m/s with the puck still a full
	# second away — far outside the blade window its motion covers, so waiting
	# is forced and it brakes to hold the gate.
	# (In-rink coordinates — see the in-stride test above.)
	var self_pos := Vector3(0, 0, 1.4)
	var s := _receive_snap(Vector3(-20, 0, 0), Vector3(20, 0, 0),
			self_pos, Vector3(0, 0, -4))
	var input := InputState.new()
	assert_true(sm._pass_receive_aim_and_steer(input, s, self_pos),
			"scenario commits the reception")
	assert_true(input.brake, "genuinely early → brake and hold the gate")


# ── Pass lead origin = the carried puck ──────────────────────────────────────

func test_pass_aim_leads_from_the_puck_not_the_body() -> void:
	# Receiver cutting PERPENDICULAR to the pass line (so the intercept solve
	# doesn't saturate the lead cap). The lead scales with flight time, and the
	# flight starts at the PUCK — a puck carried out ahead of the body shortens
	# the flight, so the led aim trails the body-origin lead by a real margin.
	var receiver_pos := Vector3(8, 0, 0)
	var receiver_vel := Vector3(0, 0, 4)

	var make := func(puck_pos: Vector3) -> WorldSnapshot:
		var s := WorldSnapshot.new()
		s.puck_state = PuckNetworkState.new()
		s.puck_state.carrier_peer_id = SELF_ID
		s.puck_state.position = puck_pos
		_add_skater(s, SELF_ID, Vector3.ZERO)
		_add_skater(s, TEAMMATE_ID, receiver_pos)
		s.skater_states[TEAMMATE_ID].velocity = receiver_vel
		return s

	sm._pass_target_peer_id = TEAMMATE_ID
	sm._pass_target_speed = 20.0
	var aim_body: Vector3 = sm._pass_aim_point(
			make.call(Vector3.ZERO), Vector3.ZERO)
	var aim_blade: Vector3 = sm._pass_aim_point(
			make.call(Vector3(3, 0, 0)), Vector3.ZERO)
	assert_lt(aim_blade.z, aim_body.z - 0.3,
			"a puck 3 m out front shortens the flight and the lead follows")


func test_pass_aim_feeds_a_ready_one_timer_man_on_his_tape() -> void:
	# A ready one-timer man takes the feed in his slapper zone, so the fired aim
	# is his tape — the point the carrier's pass search scored him at — and an
	# unready receiver is still fed at the body.
	var receiver_pos := Vector3(-2.5, 0, -24.45)
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.carrier_peer_id = SELF_ID
	s.puck_state.position = Vector3(7, 0, -22.6)
	_add_skater(s, SELF_ID, Vector3(7, 0, -22.6))
	_add_skater(s, TEAMMATE_ID, receiver_pos)
	sm._pass_target_peer_id = TEAMMATE_ID
	sm._pass_target_speed = 20.0
	sm._current_strategy = sm._strategy()
	var at_body: Vector3 = sm._pass_aim_point(s, s.skater_states[SELF_ID].position)
	assert_almost_eq(at_body, receiver_pos, Vector3.ONE * 0.001, "unready: fed at the body")
	sm._team_brain.set_one_timer_ready(TEAMMATE_ID, true)
	var at_tape: Vector3 = sm._pass_aim_point(s, s.skater_states[SELF_ID].position)
	assert_almost_eq(at_tape, AIPassLead.one_timer_tape(receiver_pos,
			sm._caps_by_peer.get(TEAMMATE_ID), sm._attacking_goal_pos), Vector3.ONE * 0.001,
			"ready: fed on his tape")
	assert_gt(at_tape.distance_to(receiver_pos), 0.5, "which sits off his body")


func test_pass_aim_feeds_the_body_of_a_one_timer_man_who_cannot_set() -> void:
	# Turned square away from the stance he would shoot from, a feed from close
	# in arrives before his hips can pivot round: he will catch it, so it goes to
	# his body.
	var receiver_pos := Vector3(-2.5, 0, -24.45)
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.carrier_peer_id = SELF_ID
	s.puck_state.position = Vector3(0.5, 0, -24.45)
	_add_skater(s, SELF_ID, s.puck_state.position)
	_add_skater(s, TEAMMATE_ID, receiver_pos)
	var caps := AISkaterCaps.new()
	var tape: Vector3 = AIPassLead.one_timer_tape(receiver_pos, caps, sm._attacking_goal_pos)
	s.skater_states[TEAMMATE_ID].facing = -SlapperRules.stance_facing(Vector2(
			sm._attacking_goal_pos.x - tape.x, sm._attacking_goal_pos.z - tape.z).normalized(),
			-1.0 if caps.is_left_handed else 1.0, caps.slapper_stance_open_rad)
	sm._pass_target_peer_id = TEAMMATE_ID
	sm._pass_target_speed = 20.0
	sm._current_strategy = sm._strategy()
	sm._team_brain.set_one_timer_ready(TEAMMATE_ID, true)
	assert_almost_eq(sm._pass_aim_point(s, s.skater_states[SELF_ID].position), receiver_pos,
			Vector3.ONE * 0.001, "fed at the body, to catch")


func test_a_released_pass_leaves_the_blade_for_the_lead() -> void:
	# The puck leaves from the blade, not the body: the release direction is the
	# blade's line to the lead, or the pass runs a blade's offset wide of it.
	var s := _self_snap(Vector3.ZERO, true)
	var blade := Vector3(1.0, 0.0, -0.5)
	s.puck_state.position = blade
	s.skater_states[SELF_ID].blade_contact_world = blade
	_add_skater(s, TEAMMATE_ID, Vector3(10, 0, 0))
	sm._state = Agent.State.PASS_PRESSED
	sm._pass_target_peer_id = TEAMMATE_ID
	sm._pass_target_speed = 20.0
	sm._pass_charge_tick = AIBotMechanics.BOT_WRISTER_CHARGE_TICKS
	var input := InputState.new()
	input.delta = 1.0 / 120.0
	sm.dispatch(input, s)
	assert_false(input.shoot_held, "the pass releases this tick")
	assert_almost_eq(input.bot_wrister_aim_dir, Vector3(9.0, 0.0, 0.5).normalized(),
			Vector3.ONE * 0.001, "from the blade to the receiver")


# ── Contest read + live-bot execution error ─────────────────────────────────

func test_opponent_within_of_reads_contest_range() -> void:
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3(3, 0, 0))
	_add_skater(s, OPP_ID, Vector3(6.5, 0, 0))   # 1.5 m from the puck
	assert_true(sm._opponent_within_of(s, Vector3(5, 0, 0), Agent.ENGAGEMENT_PROXIMITY_M),
			"an opponent inside blade-on-puck range is a live contest")
	s.skater_states[OPP_ID].position = Vector3(9, 0, 0)   # 4 m away
	assert_false(sm._opponent_within_of(s, Vector3(5, 0, 0), Agent.ENGAGEMENT_PROXIMITY_M),
			"an opponent out of reach is not a contest")
	# Teammates never make a contest.
	s.skater_states.erase(OPP_ID)
	_add_skater(s, TEAMMATE_ID, Vector3(5.5, 0, 0))
	assert_false(sm._opponent_within_of(s, Vector3(5, 0, 0), Agent.ENGAGEMENT_PROXIMITY_M),
			"a teammate near the puck is not an opposing contest")


func test_aim_error_off_raw_on_after_profile() -> void:
	# A bare state machine is bit-deterministic (tests, replay tooling); a LIVE
	# bot wired through apply_profile gets the per-tier execution error pair
	# plus the timing humaniser.
	assert_almost_eq(sm._shot_aim_error_rad, 0.0, 1e-9,
			"raw agents stay error-free on shots")
	assert_almost_eq(sm._pass_aim_error_rad, 0.0, 1e-9,
			"raw agents stay error-free on passes")
	assert_almost_eq(sm._shot_timing_error_s, 0.0, 1e-9,
			"raw agents release tick-perfect")
	sm.apply_profile(BotSkillProfile.hard())
	assert_almost_eq(sm._shot_aim_error_rad, BotSkillProfile.hard().shot_aim_error_rad, 1e-9,
			"profiled (live) agents carry the shot aim error")
	assert_almost_eq(sm._pass_aim_error_rad, BotSkillProfile.hard().pass_aim_error_rad, 1e-9,
			"profiled (live) agents carry the pass aim error")
	assert_almost_eq(sm._shot_timing_error_s, BotSkillProfile.hard().shot_timing_error_s, 1e-9,
			"profiled (live) agents carry the release timing variance")


func test_press_entry_samples_release_error_per_budget() -> void:
	# Each press entry draws ONE aim error for the whole release: shots and
	# one-timers on the (larger) shot budget, passes on the pass budget. The
	# budget IS the radian bound (tier errors are angles, ring-independent) —
	# bound it, and check a fresh entry re-samples rather than reusing the
	# previous release's error.
	sm.apply_profile(BotSkillProfile.easy())
	var shot_bound: float = BotSkillProfile.easy().shot_aim_error_rad
	var pass_bound: float = BotSkillProfile.easy().pass_aim_error_rad
	var samples: Array[float] = []
	for i: int in 16:
		sm._set_state(Agent.State.SHOOT_PRESSED)
		assert_lte(absf(sm._committed_aim_error_rad), shot_bound,
				"shot error stays inside the shot budget")
		samples.append(sm._committed_aim_error_rad)
		sm._set_state(Agent.State.CARRY)
	var all_equal: bool = true
	for v: float in samples:
		if absf(v - samples[0]) > 1e-12:
			all_equal = false
	assert_false(all_equal, "each release draws a fresh error sample")
	sm._set_state(Agent.State.PASS_PRESSED)
	assert_lte(absf(sm._committed_aim_error_rad), pass_bound,
			"pass error stays inside the (smaller) pass budget")
	sm._set_state(Agent.State.CARRY)
	sm._set_state(Agent.State.ONE_TIMER_PRESSED)
	assert_lte(absf(sm._committed_aim_error_rad), shot_bound,
			"a one-timer samples on the shot budget")
	sm._set_state(Agent.State.OFF_PUCK)


func test_shot_entry_samples_release_hold_inside_timing_budget() -> void:
	# The late-release hold is bounded by the tier's timing variance, and a
	# raw (zero-variance) agent always releases on the intended tick.
	assert_eq(sm._sample_release_hold_ticks(), 0,
			"raw agents never hold the release")
	sm.apply_profile(BotSkillProfile.normal())
	var max_ticks: int = int(round(
			BotSkillProfile.normal().shot_timing_error_s / Agent.MOUSE_TICK_DELTA))
	for i: int in 16:
		sm._set_state(Agent.State.SHOOT_PRESSED)
		assert_between(sm._shoot_release_hold_ticks, 0, max_ticks,
				"sampled hold stays inside the timing budget")
		sm._set_state(Agent.State.CARRY)
	sm._set_state(Agent.State.OFF_PUCK)


# ── Cognition gates (difficulty-tiered hockey IQ) ────────────────────────────

func test_apply_profile_sets_cognition_gates() -> void:
	# Raw agents keep the perfect-bot defaults (all reads on).
	assert_true(sm._reads_goalie_motion, "raw agent reads goalie motion")
	assert_true(sm._holds_for_developing_feeds, "raw agent holds for developing plays")
	assert_true(sm._angles_the_chase, "raw agent angles its chase")
	assert_true(sm._reads_receiver_commitment, "raw agent reads receiver commitment")
	sm.apply_profile(BotSkillProfile.easy())
	assert_false(sm._reads_goalie_motion, "Easy is goalie-motion blind")
	assert_false(sm._holds_for_developing_feeds, "Easy plays only what exists now")
	assert_false(sm._angles_the_chase, "Easy chases straight-line")
	assert_false(sm._reads_receiver_commitment,
			"Easy is commitment-blind — chucks feeds at turning players")
	sm.apply_profile(BotSkillProfile.normal())
	assert_true(sm._reads_goalie_motion,
			"Normal keeps the goalie-motion read — Hard/Normal differ by tuning only")
	assert_true(sm._holds_for_developing_feeds, "Normal keeps the developing-feed hold")
	assert_true(sm._angles_the_chase, "Normal keeps the chase angling")
	assert_true(sm._reads_receiver_commitment, "Normal keeps the receiver-commitment read")


func test_motion_blind_aim_ignores_the_goalie_slide() -> void:
	# Goalie on the shooter's arc but sliding hard +x: a motion-reading bot
	# projects the shadow along the slide and aims into the recovery arc
	# ("across the grain"); a motion-blind bot's aim is EXACTLY the aim
	# against the same goalie standing still — it shoots at where he IS.
	var s := WorldSnapshot.new()
	var gs := GoalieNetworkState.new()
	gs.position_x = 0.0
	gs.position_z = -GameRules.GOAL_LINE_Z + 1.2   # out on the challenge arc
	gs.velocity_x = 4.0                            # committed slide
	s.goalie_states[1] = gs                        # opp team (self is team 0)
	var self_pos := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 10.0)

	var aim_reading: Vector3 = sm._shot_aim_point(s, self_pos)
	sm._reads_goalie_motion = false
	var aim_blind: Vector3 = sm._shot_aim_point(s, self_pos)
	sm._reads_goalie_motion = true
	gs.velocity_x = 0.0
	var aim_still: Vector3 = sm._shot_aim_point(s, self_pos)

	assert_almost_eq(aim_blind.x, aim_still.x, 1e-6,
			"blind aim equals the still-goalie aim — where he IS, not where he'll be")
	assert_gt(absf(aim_reading.x - aim_blind.x), 0.05,
			"the motion read genuinely moves the aim into the recovery arc")


# ── Protect-side turn (carry arc direction) ──────────────────────────────────
# A carrier's turn-around picks which way the puck sweeps: shortest by default,
# the long way when the short sweep drags the puck through a defender's poke
# reach and the far side is clear. See PROTECT_TURN_* on the state machine.

func _protect_snap(self_pos: Vector3, opp_pos: Vector3) -> WorldSnapshot:
	var s := _loose_puck_snap(self_pos)
	s.puck_state.carrier_peer_id = SELF_ID
	_add_skater(s, SELF_ID, self_pos)
	_add_skater(s, OPP_ID, opp_pos)
	return s


func test_a_left_hander_s_holds_read_left_handed_from_the_first_build() -> void:
	sm._handedness_perp_sign = 1.0
	var s := _protect_snap(Vector3.ZERO, Vector3(0, 0, -30))
	sm._build_role_context(s, Vector3.ZERO, s.skater_states[SELF_ID])
	assert_true(sm._holds.is_left_handed)


func test_protect_turn_shortest_in_open_ice() -> void:
	var s := _protect_snap(Vector3.ZERO, Vector3(0, 0, -30))   # opponent far away
	# Facing +z (angle 0), target ~172° around via the +x side.
	assert_eq(sm._protect_turn_direction(Vector3.ZERO, 0.0, 3.0, s), 1.0,
			"open ice → the shortest way around")


func test_protect_turn_flips_away_from_short_side_defender() -> void:
	# Defender's blade sits right where the short (+x) sweep would carry the
	# puck; the long (−x) side is empty → sweep the long way.
	var s := _protect_snap(Vector3.ZERO, Vector3(2.0, 0, 0.2))
	assert_eq(sm._protect_turn_direction(Vector3.ZERO, 0.0, 3.0, s), -1.0,
			"short sweep through a poke threat → turn the long way, puck shielded")


func test_protect_turn_stays_short_when_both_sides_threatened() -> void:
	var s := _protect_snap(Vector3.ZERO, Vector3(2.0, 0, 0.2))
	_add_skater(s, 12, Vector3(-2.0, 0, 0.2))   # second defender mirrors the first
	assert_eq(sm._protect_turn_direction(Vector3.ZERO, 0.0, 3.0, s), 1.0,
			"nowhere safer to sweep → don't pay the long rotation for nothing")


func test_arc_step_commits_to_the_protected_direction() -> void:
	# Integration through _arc_step_mouse_target: with a defender on the short
	# side, successive arc steps walk the mouse the LONG way and stay committed.
	# The target sits ~172° around — genuinely BEHIND the body — so this is a
	# turn-around, the only case the long-way orbit still fires (see
	# _target_is_behind); a front-hemisphere protect reach takes the short way.
	var self_pos := Vector3.ZERO
	var s := _protect_snap(self_pos, Vector3(2.0, 0, 0.2))
	s.skater_states[SELF_ID].facing = Vector2(0, 1)   # facing +z; target is behind
	sm._state = Agent.State.CARRY
	sm._current_snapshot = s
	sm._mouse_pos = Vector3(0, 0, 2.0)   # parked dead ahead (angle 0)
	sm._mouse_pos_initialized = true
	var target := self_pos + Vector3(sin(3.0), 0, cos(3.0)) * 5.0
	var stepped: Vector3 = sm._arc_step_mouse_target(
			self_pos, target, s.skater_states[SELF_ID], 5.0)
	var ang: float = atan2(stepped.x - self_pos.x, stepped.z - self_pos.z)
	assert_lt(ang, 0.0, "first step sweeps the long (−) way, away from the defender")
	assert_eq(sm._arc_protect_sign, -1.0, "…and the direction is latched")
	sm._mouse_pos = stepped
	var stepped2: Vector3 = sm._arc_step_mouse_target(
			self_pos, target, s.skater_states[SELF_ID], 5.0)
	var ang2: float = atan2(stepped2.x - self_pos.x, stepped2.z - self_pos.z)
	assert_lt(ang2, ang, "the commitment holds on the next step — no mid-sweep flip")


func test_arc_step_front_reach_takes_short_way_despite_short_side_threat() -> void:
	# A protect REACH to a spot in the FRONT hemisphere never orbits the long way
	# around the back, even with a defender on the short-sweep side — the blade's
	# ROM extends across the front instead of the body spinning around. Only a
	# genuine turn-around (target behind) earns the long-way shield (see
	# _target_is_behind). Target ~86° to the +x side; mouse parked dead ahead.
	var self_pos := Vector3.ZERO
	var s := _protect_snap(self_pos, Vector3(1.4, 0, 1.0))   # defender on the +x short side
	s.skater_states[SELF_ID].facing = Vector2(0, 1)          # facing +z; target is to the side, in front
	sm._state = Agent.State.CARRY
	sm._current_snapshot = s
	sm._mouse_pos = Vector3(0, 0, 2.0)
	sm._mouse_pos_initialized = true
	var target := self_pos + Vector3(sin(1.5), 0, cos(1.5)) * 5.0   # ~86° off forward
	var stepped: Vector3 = sm._arc_step_mouse_target(
			self_pos, target, s.skater_states[SELF_ID], 5.0)
	var ang: float = atan2(stepped.x - self_pos.x, stepped.z - self_pos.z)
	assert_gt(ang, 0.0, "front-hemisphere reach sweeps the short (+) way, no back-orbit spin")
	assert_eq(sm._arc_protect_sign, 0.0, "no long-way commitment latched for a front reach")


func test_front_reach_across_the_body_walks_around_the_front() -> void:
	# Puck on the right hip, its spot on the far side and in front: the straight
	# line runs through the skater, so the cursor walks BladeRoute round the side
	# he faces, never inside the body, at the slew, and arrives.
	sm._current_self_pos = Vector3.ZERO
	sm._current_self_state = _self_state(Vector2(0, -1))
	sm._mouse_max_speed_m_s = 10.0   # a real Hands blade speed
	var step_max: float = 10.0 * Agent.MOUSE_TICK_DELTA
	sm._mouse_pos = Vector3(0.9, 0, 0)
	sm._mouse_pos_initialized = true
	var target := Vector3(-0.9, 0, -0.1)
	assert_true(BladeRoute.crosses_body(Vector2(0.9, 0), Vector2(-0.9, -0.1)))
	var prev: Vector3 = sm._mouse_pos
	var went_front: bool = false
	for _i: int in 120:
		var r: Vector3 = sm._step_mouse_front(target)
		assert_gte(Vector2(r.x, r.z).length(), BladeRoute.CLEAR_M - 0.001, "never through the body")
		# Vector2 is float32, and the route's tangent is a square root near the circle.
		assert_lte(r.distance_to(prev), step_max + 1e-4, "at the slew")
		went_front = went_front or r.z < -BladeRoute.CLEAR_M + 0.01
		prev = r
	assert_true(went_front, "round the side he faces")
	assert_almost_eq(prev.distance_to(target), 0.0, 1e-4)


func test_front_reach_that_clears_the_body_steps_direct() -> void:
	sm._current_self_pos = Vector3.ZERO
	sm._current_self_state = _self_state(Vector2(0, -1))
	sm._mouse_pos = Vector3(0.9, 0, 0)
	sm._mouse_pos_initialized = true
	var front: Vector3 = sm._step_mouse_front(Vector3(0, 0, -0.9))
	sm._mouse_pos = Vector3(0.9, 0, 0)
	var direct: Vector3 = sm._step_mouse_toward(Vector3(0, 0, -0.9))
	assert_almost_eq(front.distance_to(direct), 0.0, 1e-6)


func test_a_swing_to_a_hold_behind_lands_on_the_hold_at_the_arc_rate() -> void:
	# Turn-around to a charged release's hold behind the body: the swing walks
	# the hold's own reach, not the aim ring, and finishes on it.
	sm._current_self_pos = Vector3.ZERO
	sm._current_self_state = _self_state(Vector2(0, -1))
	sm._mouse_max_speed_m_s = 10.0
	sm._mouse_arc_rate_rad_s = 5.0
	sm._mouse_pos = Vector3(0.9, 0, 0)
	sm._mouse_pos_initialized = true
	var target := Vector3(-0.6, 0, 0.67)
	var reach: float = Vector2(target.x, target.z).length()
	var prev: float = atan2(0.9, 0.0)
	var r := Vector3.ZERO
	for _i: int in 120:
		r = sm._step_mouse_hold_arc(target)
		var ang: float = atan2(r.x, r.z)
		assert_lte(absf(wrapf(ang - prev, -PI, PI)), 5.0 * Agent.MOUSE_TICK_DELTA + 1e-4,
				"at the arc rate")
		assert_almost_eq(Vector2(r.x, r.z).length(), reach, 0.02, "on the hold's reach")
		prev = ang
	assert_almost_eq(r.distance_to(target), 0.0, 1e-4)


func test_arc_step_shortest_way_in_open_ice() -> void:
	var self_pos := Vector3.ZERO
	var s := _protect_snap(self_pos, Vector3(0, 0, -30))
	sm._state = Agent.State.CARRY
	sm._current_snapshot = s
	sm._mouse_pos = Vector3(0, 0, 2.0)
	sm._mouse_pos_initialized = true
	var target := self_pos + Vector3(sin(3.0), 0, cos(3.0)) * 5.0
	var stepped: Vector3 = sm._arc_step_mouse_target(
			self_pos, target, s.skater_states[SELF_ID], 5.0)
	var ang: float = atan2(stepped.x - self_pos.x, stepped.z - self_pos.z)
	assert_gt(ang, 0.0, "open ice keeps the shortest sweep")
	assert_eq(sm._arc_protect_sign, 0.0, "no long-way commitment latched")


# ── Aim slew arc rate projects onto the blade's real orbit radius ────────────

func test_aim_slew_arc_rate_uses_blade_orbit_radius() -> void:
	sm._apply_aim_slew(10.0, 1.6)
	assert_almost_eq(sm._mouse_arc_rate_rad_s, 6.25, 1e-6,
			"arc rate = blade speed / blade orbit span")
	# The IK-gate ceiling still caps a fast-hands build.
	sm._apply_aim_slew(40.0, 1.6)
	assert_almost_eq(sm._mouse_arc_rate_rad_s, Agent.MOUSE_ARC_RATE_RAD_S, 1e-6,
			"arc rate never exceeds the IK-gate ceiling")


# ── Carry facing follows the route (face where you're going) ─────────────────

func _carry_snap(self_pos: Vector3) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	var me := SkaterNetworkState.new()
	me.position = self_pos
	me.facing = Vector2(0, -1)
	s.skater_states[SELF_ID] = me
	s.puck_state = PuckNetworkState.new()
	s.puck_state.carrier_peer_id = SELF_ID
	s.puck_state.position = self_pos
	return s


func test_carry_aim_faces_the_route_when_driving_laterally() -> void:
	# Anchor due +X (a wall exit / a seam it just cut to); attacking -Z. The
	# cursor — and with it body facing — points down the ROUTE: the
	# goal-facing default had the carrier crabbing the whole way in the slow
	# crossover class, letting beaten defenders catch back up.
	sm._last_carry_anchor = Vector3(8, 0, 0)
	var target: Vector3 = sm._carry_mouse_aim(_carry_snap(Vector3.ZERO), Vector3.ZERO)
	assert_gt(target.normalized().x, 0.9, "cursor points down the lateral route")


func test_carry_aim_faces_the_play_when_retreating() -> void:
	# A genuine regroup (route back toward our own +Z net): back out facing
	# the attacking net — the real posture, at the honest backward-speed cost.
	sm._last_carry_anchor = Vector3(0, 0, 8)
	var target: Vector3 = sm._carry_mouse_aim(_carry_snap(Vector3.ZERO), Vector3.ZERO)
	assert_lt(target.normalized().z, -0.9, "a regroup keeps the eyes up ice")


func test_carry_aim_faces_the_play_when_anchor_is_underfoot() -> void:
	# Settling on a spot: no meaningful travel direction — face the play.
	sm._last_carry_anchor = Vector3(0.3, 0, 0.3)
	var target: Vector3 = sm._carry_mouse_aim(_carry_snap(Vector3.ZERO), Vector3.ZERO)
	assert_lt(target.normalized().z, -0.9, "underfoot anchor: face the play")


# ── O-zone square-up: point at the goalie when there's no man to beat ────────
# Team 0 attacks -Z; the O-zone is z < -BLUE_LINE_Z. Facing is measured as the
# cursor direction relative to the body (target - self), since self isn't at
# the origin here.

func test_carry_aim_squares_to_goalie_in_ozone_with_no_man_to_beat() -> void:
	# Deep in the O-zone with a LATERAL carry anchor and nobody to beat: face
	# the net (the goalie, at the attacking goal with no goalie state) rather
	# than skating on down the sideways route into an awkward-angle shot.
	var oz_pos := Vector3(0, 0, -15)   # z < -BLUE_LINE_Z → offensive zone
	sm._last_carry_anchor = Vector3(8, 0, -15)   # due +X, a lateral route
	var target: Vector3 = sm._carry_mouse_aim(_carry_snap(oz_pos), oz_pos)
	var facing: Vector3 = (target - oz_pos).normalized()
	assert_lt(facing.z, -0.9, "no man to beat in the O-zone: squared to the goalie")


func test_carry_aim_keeps_the_route_in_ozone_when_a_man_must_be_beaten() -> void:
	# Same lateral O-zone carry, but a goal-side defender is inside the contest
	# band — a man still to beat, so FACE THE ROUTE keeps the fast forward
	# stride down the escape instead of squaring up early.
	var oz_pos := Vector3(0, 0, -15)
	sm._last_carry_anchor = Vector3(8, 0, -15)
	var s := _carry_snap(oz_pos)
	_add_skater(s, OPP_ID, Vector3(2, 0, -16))   # goal-side, ~2.2 m away
	# The facing seam reads the carrier's published forward-puck clearance (see
	# _has_man_to_beat); that this defender's stick genuinely covers the puck is
	# the carrier-level claim, pinned in
	# test_a_defender_abreast_but_out_of_reach_is_not_a_man_to_beat.
	sm._carrier.forward_puck_clearance = -0.2
	var target: Vector3 = sm._carry_mouse_aim(s, oz_pos)
	var facing: Vector3 = (target - oz_pos).normalized()
	assert_gt(facing.x, 0.9, "a man to beat keeps the carrier facing its route")


func test_carry_aim_ignores_a_beaten_man_behind_in_the_ozone() -> void:
	# A defender the carrier has already skated PAST (behind it toward our own
	# end) is beaten and doesn't count, so the carrier squares up to the goalie
	# even with him trailing close behind.
	var oz_pos := Vector3(0, 0, -15)
	sm._last_carry_anchor = Vector3(8, 0, -15)
	var s := _carry_snap(oz_pos)
	_add_skater(s, OPP_ID, Vector3(0, 0, -12))   # 3 m behind toward our +Z end
	var target: Vector3 = sm._carry_mouse_aim(s, oz_pos)
	var facing: Vector3 = (target - oz_pos).normalized()
	assert_lt(facing.z, -0.9, "a beaten man behind doesn't stop the square-up")


# ── Behind-net blade cradle (both cages) ─────────────────────────────────────
# The carry blade shortens toward CARRY_BEHIND_NET_CRADLE_M when the body is
# behind/beside a net, so the offset puck rides tight instead of chording the
# blade through the cage. This must fire behind OUR net (team 0: +Z), not just
# the attacking one — the residual blade-into-net contact behind our own cage
# pops the puck loose (own goal) and re-pins the bot back there (the "stuck
# behind our net, can't skate it out" report).

func test_carry_reach_cradles_behind_our_own_net() -> void:
	var reach: float = sm._carry_reach_behind_net(
			Vector3(0, 0, GameRules.GOAL_LINE_Z + 0.5))
	assert_almost_eq(reach, SkaterAgentStateMachine.CARRY_BEHIND_NET_CRADLE_M, 0.01,
			"blade cradles tight behind our own net")


func test_carry_reach_symmetric_behind_both_nets() -> void:
	var own: float = sm._carry_reach_behind_net(
			Vector3(0, 0, GameRules.GOAL_LINE_Z + 0.5))
	var att: float = sm._carry_reach_behind_net(
			Vector3(0, 0, -GameRules.GOAL_LINE_Z - 0.5))
	assert_almost_eq(own, att, 0.001, "cradle is symmetric behind both nets")


func test_carry_reach_full_in_neutral_zone() -> void:
	var reach: float = sm._carry_reach_behind_net(Vector3(0, 0, 0))
	assert_almost_eq(reach, AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, 0.01,
			"full reach away from both cages")


func test_carry_reach_full_wide_behind_own_net() -> void:
	# Wide of the cage (in the corner) behind our own net — carrying the wall,
	# not net-working — keeps full reach.
	var reach: float = sm._carry_reach_behind_net(
			Vector3(2.5, 0, GameRules.GOAL_LINE_Z + 0.5))
	assert_almost_eq(reach, AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, 0.01,
			"wide in the corner behind our net keeps full reach")


# ── Off-puck arrival: velocity-matched seek to the role spot ─────────────────

func test_off_puck_arrival_redirects_cross_momentum() -> void:
	# Off-puck steering opts into the velocity-matched seek: a bot drifting
	# cross-ice toward its role spot steers back ONTO the line to it, where a
	# plain seek would ignore the drift and orbit past.
	var s := WorldSnapshot.new()
	var me := SkaterNetworkState.new()
	me.position = Vector3.ZERO
	me.velocity = Vector3(4, 0, 0)   # drifting +X across the approach
	s.skater_states[SELF_ID] = me
	s.puck_state = PuckNetworkState.new()
	s.puck_state.carrier_peer_id = -1
	var anchor := Vector3(0, 0, -8)  # role spot straight ahead (-Z)
	var seek_in := InputState.new()
	sm._apply_steering(seek_in, s, Vector3.ZERO, anchor)                  # plain seek
	var match_in := InputState.new()
	sm._apply_steering(match_in, s, Vector3.ZERO, anchor, true, sm._self_max_speed)
	assert_almost_eq(seek_in.move_vector.x, 0.0, 0.02, "plain seek ignores the cross-drift")
	assert_lt(match_in.move_vector.x, -0.1,
			"off-puck arrival redirects onto the line to the spot")


# ── Own-net blade discipline (_deflect_safe_aim_dir) ─────────────────────────

func test_house_blade_clears_the_puck_to_mouth_corridor() -> void:
	# Net-front defender, loose puck up the middle: the ready-stance dir
	# points at the puck, parking the blade dead in the puck→mouth corridor —
	# a deflection surface in tight (the own-goal tip). The safe dir slides
	# the blade to the corridor's edge at full stance length; the body stays
	# where the role put it.
	var self_pos := Vector3(0, 0, 24.5)            # in the house; own net +26.65
	var s := _loose_puck_snap(Vector3(0, 0, 17))   # slot shot line through us
	var dir := Vector3(0, 0, -1)                   # aiming straight at the puck
	var safe: Vector3 = sm._deflect_safe_aim_dir(self_pos, dir, s)
	var blade_pt: Vector3 = self_pos + safe * Agent.READY_STANCE_AIM_FORWARD_M
	# The corridor runs up the z-axis here, so |x| IS the perp clearance.
	assert_gte(absf(blade_pt.x), Agent.BLADE_LANE_CLEAR_M - 0.01,
			"parked blade slides to the corridor edge; got %s" % blade_pt)
	assert_almost_eq(self_pos.distance_to(blade_pt),
			Agent.READY_STANCE_AIM_FORWARD_M, 0.01,
			"stance length is preserved — only the direction rotates")


func test_blade_discipline_only_applies_in_the_house() -> void:
	var self_pos := Vector3(0, 0, 12)              # high zone, out of the house
	var s := _loose_puck_snap(Vector3(0, 0, 5))
	var dir := Vector3(0, 0, -1)
	assert_eq(sm._deflect_safe_aim_dir(self_pos, dir, s), dir,
			"outside the house the ready stance is untouched")


func test_blade_discipline_yields_to_contest_range() -> void:
	# Puck inside blade reach: play it — winning the puck ends the danger.
	var self_pos := Vector3(0, 0, 24.5)
	var s := _loose_puck_snap(Vector3(0, 0, 23.4))   # ~1.1 m away, in reach
	var dir := Vector3(0, 0, -1)
	assert_eq(sm._deflect_safe_aim_dir(self_pos, dir, s), dir,
			"a puck in contest range is played, not conceded")


func test_blade_discipline_ignores_our_own_possession() -> void:
	# Teammate carrying near our net (breakout regroup): no lane to guard.
	var self_pos := Vector3(0, 0, 24.5)
	var s := _loose_puck_snap(Vector3(0, 0, 17))
	s.puck_state.carrier_peer_id = TEAMMATE_ID
	var dir := Vector3(0, 0, -1)
	assert_eq(sm._deflect_safe_aim_dir(self_pos, dir, s), dir,
			"our own possession needs no deflection discipline")


# ── CARRY handler: two gaps the slice above (the _CarrierStub tests) leaves ──
# The _CarrierStub slice (test_carry_*) already drives the CARRY handler through
# every transition — lost-puck bail, INTENT_CARRY steering, shoot pre-aim+commit,
# intent→press mapping, dump freeze, hysteresis hold, timeout. These two fill the
# remainder: the pure INTENT_*→State map in isolation (all branches incl. the
# fallback), and the post-commit freeze of the SHOT aim (the `_intended_action ==
# CARRY` mirror guard, which the intent-hold test doesn't assert on).

func test_state_from_carrier_intent_maps_every_intent() -> void:
	# The map is intentionally decoupled from State (INTENT_* ints) for exactly
	# this unit test — cover all four intents plus the unknown fallback directly.
	assert_eq(sm._state_from_carrier_intent(AIRoleCarrier.INTENT_SHOOT),
			Agent.State.SHOOT_PRESSED)
	assert_eq(sm._state_from_carrier_intent(AIRoleCarrier.INTENT_PASS),
			Agent.State.PASS_PRESSED)
	assert_eq(sm._state_from_carrier_intent(AIRoleCarrier.INTENT_DUMP),
			Agent.State.PASS_PRESSED, "a dump reuses the PASS_PRESSED release path")
	assert_eq(sm._state_from_carrier_intent(AIRoleCarrier.INTENT_CARRY),
			Agent.State.CARRY)
	assert_eq(sm._state_from_carrier_intent(999), Agent.State.CARRY,
			"an unknown intent falls back to CARRY")


func test_carry_freezes_shot_aim_after_commit() -> void:
	# Shot params (aim/loft/power) are mirrored from the carrier only WHILE still
	# deliberating (_intended_action == CARRY). Once a fire intent latches they
	# freeze, so the bot fires the exact shot that won the compete — not whatever
	# a later re-eval moved the hole to. Deferring (facing away + frozen cursor)
	# holds the latch across dispatches without committing to the press state.
	var carrier_stub := _stub_carry(AIRoleCarrier.INTENT_SHOOT)
	carrier_stub.shot_aim_point = Vector3(0, 0, -20)           # the hole the compete won
	var s := _self_snap(Vector3.ZERO, true)
	s.skater_states[SELF_ID].facing = Vector2(0, 1)    # net in the back wedge → defer
	sm._mouse_max_speed_m_s = 0.0001                   # cursor can't converge this tick
	sm._mouse_pos = Vector3(50, 0, 50)
	sm._mouse_pos_initialized = true
	sm.dispatch(InputState.new(), s)
	assert_eq(sm._intended_action, Agent.State.SHOOT_PRESSED, "fire intent latched, deferring")
	assert_eq(sm._shot_aim_locked, Vector3(0, 0, -20), "the winning hole aim was captured at commit")
	# The carrier now drags its hole aim elsewhere; the committed shot must not follow.
	carrier_stub.shot_aim_point = Vector3(0, 0, -5)
	sm.dispatch(InputState.new(), s)
	assert_eq(sm.get_state(), Agent.State.CARRY, "still pre-aiming")
	assert_eq(sm._shot_aim_locked, Vector3(0, 0, -20),
			"the committed shot aim is frozen — it stops tracking the carrier post-commit")


func test_reach_band_yields_to_a_dead_puck() -> void:
	# A goalie smother / phase lock publishes a -1 election for the team. The
	# reach band bypasses the election, so it has to honor that veto itself —
	# otherwise the whole team crowds a puck nobody can legally touch.
	var s := _loose_puck_snap(Vector3(5, 0, 0))
	_add_skater(s, SELF_ID, Vector3(4, 0, 0))         # 1.0 m away
	s.closest_to_puck_by_team[0] = -1
	assert_false(sm._should_chase_loose_puck(s, Vector3(4, 0, 0)))


# ── Re-eval cadence: the zone pressure owner is reactive ─────────────────────
# A zone defender whose AREA owns the puck runs the full AIRolePressure cut-off
# argmax against a live carrier — PRESSURE's job under a different slot name, so
# it needs PRESSURE's cadence. Ownership moves with the puck, so the classifier
# has to ask AIZoneCoverage.pressure_owner rather than name one slot.

func _puck_at(x: float, z: float) -> WorldSnapshot:
	var s := WorldSnapshot.new()
	s.puck_state = PuckNetworkState.new()
	s.puck_state.position = Vector3(x, 0.0, z)
	s.puck_state.carrier_peer_id = OPP_ID
	return s


# Team 0 defends +Z; depth is metres off that goal line into our end.
func _our_zone_pt(x: float, depth: float) -> WorldSnapshot:
	return _puck_at(x, GameRules.GOAL_LINE_Z - depth)


func test_the_zone_owner_of_a_low_puck_is_reactive() -> void:
	# The corner battle — ZONE_D_STRONG, which used to be the only zone slot
	# the classifier recognised.
	var snap: WorldSnapshot = _our_zone_pt(9.0, 3.0)
	assert_true(sm._is_reactive_slot(AIRoleSlots.Slot.ZONE_D_STRONG, snap),
			"the low battle D owns this puck")


func test_the_zone_owner_of_a_slot_puck_is_reactive() -> void:
	# The regression: a carrier in the slot is ZONE_C's to pressure, and it was
	# being re-evaluated on the shape-holding cadence instead.
	var snap: WorldSnapshot = _our_zone_pt(1.0, 8.5)
	assert_eq(AIZoneCoverage.pressure_owner(1.0, GameRules.GOAL_LINE_Z,
			snap.puck_state.position), AIRoleSlots.Slot.ZONE_C,
			"fixture sanity: this puck is ZONE_C's")
	assert_true(sm._is_reactive_slot(AIRoleSlots.Slot.ZONE_C, snap),
			"the slot's owner pressures a live carrier and needs the cadence")


func test_the_zone_owner_of_a_net_front_puck_is_reactive() -> void:
	var snap: WorldSnapshot = _our_zone_pt(0.0, 2.0)
	assert_eq(AIZoneCoverage.pressure_owner(1.0, GameRules.GOAL_LINE_Z,
			snap.puck_state.position), AIRoleSlots.Slot.ZONE_D_WEAK,
			"fixture sanity: this puck is the net-front box's")
	assert_true(sm._is_reactive_slot(AIRoleSlots.Slot.ZONE_D_WEAK, snap),
			"the net-front owner pressures a live carrier too")


func test_a_zone_slot_that_does_not_own_the_puck_is_not_reactive() -> void:
	# Everyone else is holding a breathing anchor — the whole point of the
	# slower cadence. Without a live soft-lock they stay non-reactive.
	var snap: WorldSnapshot = _our_zone_pt(1.0, 8.5)   # ZONE_C's puck
	assert_false(sm._is_reactive_slot(AIRoleSlots.Slot.ZONE_W_WEAK, snap),
			"a defender whose area does not hold the puck is a shape-holder")
	assert_false(sm._is_reactive_slot(AIRoleSlots.Slot.ZONE_D_STRONG, snap),
			"including the slot that used to be hardcoded reactive")


func test_zone_reactivity_survives_a_missing_puck() -> void:
	var snap := WorldSnapshot.new()
	assert_false(sm._is_reactive_slot(AIRoleSlots.Slot.ZONE_C, snap),
			"no puck, no owner — and no crash")

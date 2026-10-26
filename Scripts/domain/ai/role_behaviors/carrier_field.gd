class_name AICarrierField
extends RefCounted

# What the carrier sees for one phase of its compete, and the valuation every
# one of its searches shares: what a spot is worth, what a turnover there costs,
# what pass option it opens. AIRoleCarrier owns one, refills it with fill(ctx) at
# the head of each phase (fill_receivers in the fire phase), and hands it to the
# searches; nothing but those two writes the lists, so every search in a phase
# reads the same field. The counter-threat memo and the hold solver are the
# exceptions: both are scratch the valuations fill as they go.

# ── Transition-exposure appetite (5v5 only — plan §6) ────────────────────────
# The per-position risk-aversion FEEL scalar on the counter-rush cost: the model
# does the seeing, this sets the appetite. Forwards discount it because the
# F3-high rotation is expected to absorb a forward caught deep. 3v3 pays zero.
const EXPOSURE_APPETITE_DEFENSE: float = 1.0
const EXPOSURE_APPETITE_FORWARD: float = 0.7
# Loss probabilities below this skip the counter read entirely (hot-path
# floor, not a tuning knob: at 4% × a bounded threat the term is noise).
const EXPOSURE_PROB_FLOOR: float = 0.04

# Receiver drive-in credit (see receiver_drive_in_value): the one drive in every
# possession read credits (AIPossessionValue), here carried on the carrier's
# own reach and clearance machinery.
const RECEIVER_DRIVE_MAX_M: float = AIPossessionValue.DRIVE_MAX_M
const RECEIVER_DRIVE_MIN_NET_DIST_M: float = AIPossessionValue.DRIVE_MIN_NET_DIST_M

# RECEIVE: how far inside the line a pass target must sit when the carrier is
# in the OZ. The catch plays the puck up to a stick's reach around the body and
# gives with it (~a stride), so routine reception slop on a line-hugging target
# takes the puck out. Such feeds are hard reads for a human receiver too, so
# they're excluded, not discounted.
const OZ_RECEIVE_LINE_BUFFER_M: float = GameRules.DEFAULT_STICK_LENGTH_M + 0.7
# Haircut on the pass-OPTION value a carry candidate inherits (see
# pass_option_from): the option is a coarse read — receiver valued at his
# CURRENT spot, lane judged against CURRENT defenders — and it still has to
# survive until the carrier arrives and releases. Tactical haircut; the grounded
# terms are inside the option itself.
const PASS_OPTION_DISCOUNT: float = 0.8

# Opponents, index-matched: positions, velocities, AISkaterCaps (entries may be
# null, so the reachable-set model reads each defender's real reach), and
# positions advanced by the commit→release windup (BOT_WRISTER_LOOKAHEAD_S) —
# the shot and the charged pass both leave the blade ~135 ms after the intent
# commits, so their lanes are priced at release-time defender spots.
var opponents: Array[Vector3] = []
# The opposing keeper's live stance (AIShotOdds.Stance), read once per fill.
var keeper_stance: int = AIShotOdds.Stance.UPRIGHT
var opponent_vels: Array[Vector3] = []
var opponent_caps: Array[AISkaterCaps] = []
var opponents_release: Array[Vector3] = []
# Their blades (on the ice plane), carried at their skating to the same instant.
var opponent_blades_release: Array[Vector3] = []
# Our skaters excluding the carrier (the man who just lost it covers nothing) —
# the defenders that reduce the opponent's threat in the turnover-cost term —
# with their caps and velocities, index-matched.
var our_defenders: Array[Vector3] = []
var our_defender_caps: Array[AISkaterCaps] = []
var our_defender_vels: Array[Vector3] = []
# Teammate times to stand set at the counter point (5v5), candidate-invariant
# across a phase, and the counter-threat memo by covering-body count, -1-seeded
# with them.
var exposure_mate_etas: Array[float] = []
var exposure_threat_memo: Array[float] = []
var exposure_opp_home: Array[float] = []

# ── Receivers (fill_receivers: the FIRE phase only) ──────────────────────────
# Read in the fire phase and carried into a sliced commit phase unchanged, since
# fill() does not touch them. Our teammates, and the pass-OPTION cache: each
# legal receiver's position and spot value at his CURRENT location, so a
# candidate's option read only prices the LANE from the candidate.
var teammate_ids: Array[int] = []
var receiver_pos: Array[Vector3] = []
var receiver_val: Array[float] = []
# The option read at the current puck spot — candidates credit only their
# improvement over it — and the best cached value × PASS_OPTION_DISCOUNT, the
# exact upper bound on any candidate's option read.
var pass_option_at_self: float = 0.0
var pass_option_ceiling: float = 0.0

# The hold solver every valuation shares: the shoot-now sweep, a carry
# candidate's shot on arrival, a pass's launch cap. Its results are read back
# right after each solve, so it is a tool, not a list.
var holds := AIShotHolds.new()
# Where the last receiver_drive_in_value drive was stopped or arrived: the spot
# its value was priced at, read back right after the call.
var drive_in_reached: Vector3 = Vector3.INF
# Projection scratch for receiver_drive_in_value: opponents at the start of the
# drive, and at its end.
# The way the carrier attacks along z, where he is, and the net he attacks (fill).
var _attack_z: float = -1.0
var _carrier_pos: Vector3 = Vector3.ZERO
var _goal: Vector3 = Vector3.ZERO
# _tag_up_time while a teammate owes a tag-up, else 0.
var _tag_up_s: float = 0.0
var _entry_buf: Array[Vector3] = []
var _entry_vels: Array[Vector3] = []
var _drive_buf: Array[Vector3] = []
var _drive_vels: Array[Vector3] = []
# What the carrier is trying to do from where he is, the currency every option
# of his is priced in (AIPossessionValue.Objective).
var objective: int = AIPossessionValue.Objective.SCORE
# What possession of a spot is worth to us (against the opponents) and to them
# (against our defenders), priced by fill().
var _ours := AIPossessionValue.new()
var _theirs := AIPossessionValue.new()
# The opponents _theirs pairs our defence to: all but the one nearest the carrier.
var _their_attackers: Array[Vector3] = []
var _their_attacker_vels: Array[Vector3] = []


func fill(ctx: RoleContext) -> void:
	_attack_z = signf(ctx.attacking_goal_pos.z)
	_carrier_pos = ctx.self_pos
	_goal = ctx.attacking_goal_pos
	opponents.clear()
	opponent_vels.clear()
	opponent_caps.clear()
	opponents_release.clear()
	opponent_blades_release.clear()
	our_defenders.clear()
	our_defender_caps.clear()
	our_defender_vels.clear()
	for peer_id: int in ctx.snapshot.skater_states:
		if peer_id == ctx.peer_id:
			continue
		var s: SkaterNetworkState = ctx.snapshot.skater_states[peer_id]
		if ctx.team_id_by_peer.get(peer_id, -1) != ctx.team_id:
			opponents.append(s.position)
			opponent_vels.append(s.velocity)
			opponent_caps.append(ctx.caps_by_peer.get(peer_id))
			opponents_release.append(AITrajectory.predict_at(
					s.position, s.velocity, AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S))
			var blade := Vector3(s.blade_contact_world.x, 0.0, s.blade_contact_world.z)
			opponent_blades_release.append(AITrajectory.predict_at(
					blade, s.velocity, AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S))
		else:
			our_defenders.append(s.position)
			our_defender_caps.append(ctx.caps_by_peer.get(peer_id))
			our_defender_vels.append(s.velocity)
	if ctx.team_size >= 5:
		AIActionScoring.fill_counter_cover_etas(ctx.defending_goal_pos, our_defenders,
				our_defender_vels, our_defender_caps, exposure_mate_etas)
		exposure_threat_memo.resize(our_defenders.size() + 2)
		exposure_threat_memo.fill(-1.0)
		AIActionScoring.fill_counter_opp_home(ctx.defending_goal_pos, opponents,
				opponent_vels, opponent_caps, exposure_opp_home)
	var opp_keeper: GoalieNetworkState = ctx.snapshot.goalie_states.get(1 - ctx.team_id)
	keeper_stance = AIShotOdds.stance_of(opp_keeper, ctx.attacking_goal_pos) \
			if opp_keeper != null else AIShotOdds.Stance.UPRIGHT
	# In the zone the carrier reads our possession only of spots in it. The
	# defence pairs to his teammates, him holding; a turnover's is the opponents',
	# their man nearest him collecting.
	_ours.fill(ctx.attacking_goal_pos, opponents, opponent_vels, opponent_caps,
			AIActionScoring.in_offensive_zone(ctx.self_pos, ctx.attacking_goal_pos),
			our_defenders, our_defender_vels, ctx.self_pos)
	objective = _ours.objective_at(ctx.self_pos)
	_tag_up_s = _tag_up_time(ctx) if ctx.zone_entry_blocked else 0.0
	var collector: int = -1
	for i: int in opponents.size():
		if collector == -1 or opponents[i].distance_squared_to(ctx.self_pos) \
				< opponents[collector].distance_squared_to(ctx.self_pos):
			collector = i
	_their_attackers.clear()
	_their_attacker_vels.clear()
	for i: int in opponents.size():
		if i != collector:
			_their_attackers.append(opponents[i])
			_their_attacker_vels.append(opponent_vels[i])
	_theirs.fill(ctx.defending_goal_pos, our_defenders, our_defender_vels, our_defender_caps,
			false, _their_attackers, _their_attacker_vels,
			opponents[collector] if collector != -1 else Vector3.INF)


func fill_receivers(ctx: RoleContext, cur_puck_pos: Vector3) -> void:
	teammate_ids.clear()
	for peer_id: int in ctx.snapshot.skater_states:
		if peer_id == ctx.peer_id:
			continue
		if ctx.team_id_by_peer.get(peer_id, -1) == ctx.team_id:
			teammate_ids.append(peer_id)

	# Pass-OPTION cache: each legal receiver's spot value at his CURRENT position
	# (goalie arc-squared to it). Legality approximates AICarrierPassSearch.search's: no
	# out-of-play receivers, and an OZ carrier counts only receivers standing
	# OZ_RECEIVE_LINE_BUFFER_M inside the line (the live pass applies that
	# buffer to the solved lead instead).
	receiver_pos.clear()
	receiver_val.clear()
	var in_oz_now: bool = zone_taken(ctx)
	for pid: int in teammate_ids:
		var tm: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		if ctx.snapshot.is_out_of_play(pid):
			continue
		if in_oz_now and not AIActionScoring.in_offensive_zone(
				tm.position, ctx.attacking_goal_pos, OZ_RECEIVE_LINE_BUFFER_M):
			continue
		receiver_pos.append(tm.position)
		receiver_val.append(value_at(ctx, tm.position, ctx.self_pos, opponents, Vector3.INF,
				0.0, 1.0, AIShotOdds.Stance.UPRIGHT, NAN, 0.0, Vector3.ZERO,
				ctx.caps_by_peer.get(pid)))
	# The same option read at the CURRENT puck spot — the baseline a candidate's
	# option credit is measured against (see AICarrierCarrySearch._upgrade_candidate_two_ply): an
	# option already available from here belongs to the live pass in the fire
	# compete, so only the IMPROVEMENT motivates a carry. Subtracting it also
	# cancels the coarse option model's bias against the fully-priced pass
	# common-mode.
	pass_option_at_self = pass_option_from(ctx, cur_puck_pos)
	# Exact ceiling on ANY candidate's option (lane/miss/decay all ≤ 1); when
	# it can't improve on the at-self read, the per-candidate option read skips.
	pass_option_ceiling = 0.0
	for v: float in receiver_val:
		if v * PASS_OPTION_DISCOUNT > pass_option_ceiling:
			pass_option_ceiling = v * PASS_OPTION_DISCOUNT


# Every opponent `time_s` ahead, into `out_buf` and his velocity then into
# `out_vels`, index-matched to `opponents`, against the carrier at
# `carrier_then` by then, on the possession read's model of where a defender
# will be (AIDefenderProjection.at): a man backing off in front of
# the carrier holds his gap to where the carrier has got to, never to where he
# might have been — carried on regardless, his retreat would show every delay of
# the entry a blue line he has left, and the carrier would pull up to wait. A
# man closing on the carrier keeps his momentum until he is level with him;
# behind the play, he backchecks.
func project_opponents(time_s: float, out_buf: Array[Vector3],
		out_vels: Array[Vector3], carrier_then: Vector3) -> void:
	out_buf.clear()
	out_vels.clear()
	for i: int in opponents.size():
		out_buf.append(AIDefenderProjection.at(opponents[i], opponent_vels[i],
				time_s, _carrier_pos, carrier_then, _goal, opponent_caps[i]))
		out_vels.append(AIDefenderProjection.vel_then)


# The cost of losing the puck at `loss_point` with probability `loss_prob`,
# `loss_s` from now, in the carrier's currency and discounted to now as his gains
# are (AIPossessionValue.turnover_cost). In their zone it is a credit (negative):
# the carry and pass ceilings that assume a cost is never negative are short by
# at most that much.
func turnover_cost(loss_point: Vector3, loss_prob: float, loss_s: float = 0.0) -> float:
	if not loss_point.is_finite() or loss_prob <= 0.0:
		return 0.0
	return loss_prob * AIPossessionValue.turnover_cost(objective, loss_point, loss_s,
			_ours, _theirs)


# Transition-exposure cost of losing the puck at `loss_point` with
# probability `loss_prob`, while this carrier would be recovering from
# `recover_from` — the additive counter-rush half of the turnover price
# (AIActionScoring.counter_rush_cost; plan §6). 5v5 only, from their zone only.
func counter_exposure_cost(ctx: RoleContext, loss_point: Vector3,
		loss_prob: float, recover_from: Vector3, our_goalie: Vector3) -> float:
	# Outside their zone the turnover cost already is their run at our zone.
	if objective != AIPossessionValue.Objective.SCORE or ctx.team_size < 5 \
			or loss_prob <= EXPOSURE_PROB_FLOOR:
		return 0.0
	var appetite: float = EXPOSURE_APPETITE_DEFENSE if ctx.self_is_defense \
			else EXPOSURE_APPETITE_FORWARD
	return appetite * AIActionScoring.counter_rush_cost(
			loss_point, loss_prob, ctx.defending_goal_pos, our_goalie,
			our_defenders,
			recover_from, ctx.caps_by_peer.get(ctx.peer_id),
			opponents, opponent_vels, opponent_caps,
			exposure_mate_etas, exposure_threat_memo, true, exposure_opp_home)


# ── Stateless reads every search shares ──────────────────────────────────────

# Where the carried puck sits off a body at `body_pos`, a carry-handle toward
# the attacking goal.
static func puck_pos_at(body_pos: Vector3, attacking_goal: Vector3) -> Vector3:
	var to_goal: Vector3 = attacking_goal - body_pos
	to_goal.y = 0.0
	var len_sq: float = to_goal.x * to_goal.x + to_goal.z * to_goal.z
	if len_sq < 0.0001:
		return body_pos
	var inv: float = 1.0 / sqrt(len_sq)
	return body_pos + to_goal * (inv * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M)


# The pass valve's read: the offside line reads the PUCK, which leads the body,
# so the zone is taken once the body, the puck, or the puck at release is in.
static func zone_taken(ctx: RoleContext) -> bool:
	var goal: Vector3 = ctx.attacking_goal_pos
	if AIActionScoring.in_offensive_zone(ctx.self_pos, goal):
		return true
	if ctx.snapshot.puck_state == null:
		return false
	var puck: Vector3 = ctx.snapshot.puck_state.position
	return AIActionScoring.in_offensive_zone(puck, goal) or AIActionScoring.in_offensive_zone(
			puck + ctx.self_velocity * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S, goal)


# OZ slot anchor — the slot destination and the forward axis of the
# carry search, a fixed depth off the attacking goal line.
static func slot_anchor(own_goal_dir: float) -> Vector3:
	var slot_z: float = -own_goal_dir * (GameRules.GOAL_LINE_Z - GameRules.SLOT_DIST_M)
	return Vector3(0.0, 0.0, slot_z)


# Where a pass physically leaves from: the carried puck (up to a stick's reach
# from the body), falling back to the body center when the snapshot has no
# puck, carried on to the release — the windup (BOT_WRISTER_LOOKAHEAD_S) later,
# the carrier braking through it as a pass press does — where the defenders are
# read too (opponents_release). Measured from the chest instead, the ~1 m origin
# error is a systematic over-lead on a close feed; from where he stands at the
# decision, a carrier at speed prices a lane a metre behind the one he throws.
static func pass_origin(ctx: RoleContext) -> Vector3:
	var at: Vector3 = ctx.self_pos
	if ctx.snapshot.puck_state != null:
		at = Vector3(ctx.snapshot.puck_state.position.x, 0.0,
				ctx.snapshot.puck_state.position.z)
	return pass_origin_from(at, ctx.self_velocity)


# pass_origin for a puck at `at` carried by a skater moving at `v`.
static func pass_origin_from(at: Vector3, v: Vector3) -> Vector3:
	var speed: float = sqrt(v.x * v.x + v.z * v.z)
	if speed < 0.01:
		return at
	var t: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	var b: float = GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2
	var travel: float = speed * t - 0.5 * b * t * t if speed > b * t \
			else speed * speed / (2.0 * b)
	return Vector3(at.x + v.x / speed * travel, 0.0, at.z + v.z / speed * travel)


# The keeper's stance at a shot `t` s from now: the one he is in for a shot
# before he could stand up (AIGoalieModel.GOALIE_RECOVERY_S); upright after it,
# since when he chooses to rise is his read, not one the carrier can make.
func keeper_stance_at(t: float) -> int:
	return keeper_stance if t < AIGoalieModel.GOALIE_RECOVERY_S else AIShotOdds.Stance.UPRIGHT


# The opposing goalie's CURRENT world position; the attacking goal when his
# state isn't buffered yet.
static func goalie_now(ctx: RoleContext) -> Vector3:
	var opp_goalie: GoalieNetworkState = ctx.snapshot.goalie_states.get(1 - ctx.team_id)
	if opp_goalie == null:
		return ctx.attacking_goal_pos
	return Vector3(opp_goalie.position_x, 0.0, opp_goalie.position_z)


# How unsettled [0,1] the goalie is at a release `release_time_s` from now — the
# share of his push he has left. Cognition gate: a goalie-motion-blind tier
# (ctx.reads_goalie_motion false) reads 0.
static func goalie_unsettled_at(ctx: RoleContext, release_time_s: float,
		puck_pos_at_release: Vector3, closing_speed_m_s: float = 0.0) -> float:
	if not ctx.reads_goalie_motion:
		return 0.0
	return AIGoalieModel.goalie_unsettled(
			goalie_now(ctx), ctx.attacking_goal_pos,
			release_time_s, puck_pos_at_release, closing_speed_m_s)


# The fastest charged pass along `dir` (world XZ) this bot can load: its pace at
# the pocket's share, the hold the state machine pulls the puck to first when
# the puck's own spot can't carry the feed.
func pass_launch_cap(ctx: RoleContext, dir: Vector3, facing: Vector2) -> float:
	holds.configure_from(ctx)
	holds.pocket(Vector2(dir.x, dir.z), Vector2(ctx.self_velocity.x, ctx.self_velocity.z),
			facing)
	return ctx.self_wrister_shot_speed * holds.pocket_result.power_share


# Whether a shot released at `release` by a carrier now at `from_pos` is what
# value_at prices the spot by. Outside the zone, from outside it, at a keeper
# home, the spot is worth its position and the shot (near nothing at that range)
# is never the better read, so its hold is not worth solving.
static func shot_reads(ctx: RoleContext, from_pos: Vector3, release: Vector3) -> bool:
	return AIActionScoring.in_offensive_zone(from_pos, ctx.attacking_goal_pos) \
			or AIActionScoring.in_offensive_zone(release, ctx.attacking_goal_pos) \
			or goalie_now(ctx).distance_to(ctx.attacking_goal_pos) \
					>= AIActionScoring.THREAT_GOALIE_HOME_M


# The hold a carry candidate's shot on arrival is taken from (AIShotHolds
# .solve_arrival, its share and keep left in holds), and the wait it owes before
# the press: the pull there from where the puck sits now, less the `carry_s` the
# carry gives the hands to make it.
func arrival_hold_wait(ctx: RoleContext, candidate: Vector3, arrive_vel: Vector3,
		carry_s: float) -> float:
	var aim := Vector2(ctx.attacking_goal_pos.x - candidate.x,
			ctx.attacking_goal_pos.z - candidate.z)
	if aim.length_squared() < 0.0001:
		aim = Vector2(0.0, -signf(ctx.attacking_goal_pos.z))
	var facing: Vector2 = ctx.snapshot.skater_states[ctx.peer_id].facing
	var windup: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
	holds.solve_arrival(aim.normalized(), Vector2(arrive_vel.x, arrive_vel.z), facing,
			candidate + arrive_vel * windup, carry_s + windup,
			opponents, opponent_vels, opponent_caps, ctx.self_pos)
	var puck: Vector3 = ctx.self_pos if ctx.snapshot.puck_state == null \
			else ctx.snapshot.puck_state.position
	var from := Vector2(puck.x - ctx.self_pos.x, puck.z - ctx.self_pos.z)
	return maxf(0.0, holds.pull_time(from, holds.arrival_offset, facing,
			Vector2(ctx.self_velocity.x, ctx.self_velocity.z)) - carry_s)


# Position-value scorer at `pos`, evaluated from the carrier at `from_pos`, in
# the odds of scoring: the better of the shot there and our play on from the
# spot (horizon_value), one read on both sides of the line.
#
# `opps` must already be projected to the time the actor will be at `pos`, in
# the same snapshot order as opponent_caps. The keeper is at `keeper_pos` moving
# across at `keeper_vel_x` (AIShotValue.now), or square and set on `pos` when
# `keeper_pos` is INF (AIShotValue.set_keeper), in `stance` (an
# AIShotOdds.Stance; keeper_stance_at), facing `keeper_yaw` (his rotation_y; NAN
# when not read). The actor reaches `pos` `arrive_s` from now moving at
# `arrive_vel`, on his build `man_caps`, which is when and how he starts for the
# zone from it (horizon_value). It takes no aim spread: the seam prices
# the chance, not the shooter. `shot_keep` is the odds the shooter still has the
# puck at the press; it discounts the shot, never the position value.
func value_at(ctx: RoleContext, pos: Vector3, from_pos: Vector3,
		opps: Array[Vector3], keeper_pos: Vector3 = Vector3.INF,
		keeper_vel_x: float = 0.0, shot_keep: float = 1.0,
		stance: int = AIShotOdds.Stance.UPRIGHT, keeper_yaw: float = NAN,
		arrive_s: float = 0.0, arrive_vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	if objective != AIPossessionValue.Objective.SCORE \
			or _shot_is_dead_from_here(ctx, pos, from_pos, keeper_vel_x, keeper_pos):
		return horizon_value(pos, arrive_s, arrive_vel, man_caps)
	var shoot_s: float = AIActionScoring.score_shoot_value(
			pos, ctx.attacking_goal_pos, keeper_pos, opps, keeper_vel_x,
			stance, AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
			opponent_caps, -1.0, keeper_yaw) * shot_keep
	return maxf(shoot_s, horizon_value(pos, arrive_s, arrive_vel, man_caps))


# A receiver's shot at `pos` off a feed from `passer` at `pass_speed`, the keeper
# square on the passer as it leaves (AIShotValue.feed), 0 where a shot from there
# is dead. `one_timer`: he one-times it; otherwise he catches and charges. A
# goalie-motion-blind tier (ctx.reads_goalie_motion) reads the keeper already set
# on the receiver.
func feed_shot_at(ctx: RoleContext, passer: Vector3, pos: Vector3, pass_speed: float,
		one_timer: bool, from_pos: Vector3, opps: Array[Vector3]) -> float:
	if objective != AIPossessionValue.Objective.SCORE or _shot_is_dead_from_here(ctx, pos, from_pos, 0.0):
		return 0.0
	var shoot_s: float = AIShotValue.feed(passer, pos, pass_speed, ctx.attacking_goal_pos,
			goalie_now(ctx), one_timer) if ctx.reads_goalie_motion \
			else AIShotValue.set_keeper(pos, ctx.attacking_goal_pos)
	if shoot_s > 0.0:
		var aim: Vector3 = AIShotAim.compute_open_net_aim(pos, goalie_now(ctx),
				ctx.attacking_goal_pos.z, GameRules.NET_HALF_WIDTH,
				AIGoalieModel.GOALIE_SHADOW_HALF_M)
		shoot_s *= AIPuckLane.lane_clear(pos, aim, opps,
				AIBotMechanics.WRISTER_SHOT_SPEED_M_S, AIActionScoring.EMPTY_VEC3, opponent_caps) \
				* AIPuckLane.release_contest_clean(
						AIPuckLane.release_point_toward(pos, ctx.attacking_goal_pos),
						opps, opponent_caps)
	return shoot_s


# Hot-path skip (the same proof AIPossessionValue.threat_of_carrier runs): with the keeper HOME
# and still, a direct shot from OUTSIDE the attacking zone is dead, so the
# horizon branch always wins. A moving or pulled keeper voids the proof.
# `keeper_pos` INF reads the keeper where he stands now.
func _shot_is_dead_from_here(ctx: RoleContext, pos: Vector3, from_pos: Vector3,
		keeper_vel_x: float, keeper_pos: Vector3 = Vector3.INF) -> bool:
	var keeper: Vector3 = keeper_pos if keeper_pos.is_finite() else goalie_now(ctx)
	return keeper_vel_x == 0.0 \
			and not AIActionScoring.in_offensive_zone(pos, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(from_pos, ctx.attacking_goal_pos) \
			and keeper.distance_to(ctx.attacking_goal_pos) < AIActionScoring.THREAT_GOALIE_HOME_M


# What the puck at `pos` is worth past the end of what the carrier searches: our
# play on from there (AIPossessionValue.play_on — the shot from the spot itself
# is the caller's, against the keeper as he is), on arrival — its man reaches it
# `arrive_s` from now moving at `arrive_vel`, on his build `man_caps`, and plays
# on from then, though never over the line before a tag-up owed is made
# (_tag_up_time). The caller discounts the trip there, so the read's own
# discount of it is divided back out (delay_discount is exponential, so that is
# exact).
func horizon_value(pos: Vector3, arrive_s: float = 0.0,
		arrive_vel: Vector3 = Vector3.ZERO, man_caps: AISkaterCaps = null) -> float:
	var start_s: float = arrive_s
	if _tag_up_s > start_s and not AIActionScoring.in_offensive_zone(pos, _goal):
		start_s = _tag_up_s
	var v: float
	if objective == AIPossessionValue.Objective.ENTER:
		v = _ours.p_enter(pos, start_s, arrive_vel, man_caps)
	elif objective == AIPossessionValue.Objective.EXIT:
		v = _ours.p_exit(pos, start_s, arrive_vel, man_caps)
	else:
		v = _ours.play_on(pos, start_s, arrive_vel, man_caps)
	return v / AIActionScoring.delay_discount(arrive_s)


# While a teammate owes a tag-up, how long until the last of ours in the zone is
# back over the line: no entry is ours before it.
func _tag_up_time(ctx: RoleContext) -> float:
	var line_z: float = _attack_z * GameRules.BLUE_LINE_Z
	var t: float = 0.0
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id or ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		var s: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		if not AIActionScoring.in_offensive_zone(s.position, ctx.attacking_goal_pos):
			continue
		t = maxf(t, AIArrival.time_to_arrive_caps(s.position, Vector3(s.position.x, 0.0,
				line_z), s.velocity, ctx.caps_by_peer.get(pid)))
	return t


# The value of a man DRIVING IN from `receiver_spot`: the value he reaches by
# carrying toward the net, up to RECEIVER_DRIVE_MAX_M and only as far as the path
# stays clear (carry_strip_point). Value = value_at(reached) × keep × decay(time
# to reach it) − the turnover where it is stripped, on the same reach/clearance
# machinery and loss pricing as the carrier's own carry,
# so both sides of a pass are valued alike. One straight drive, no search.
# Serves pass receivers, the carrier's own floor, and the entry continuation.
#
# `start_s` > 0 prices a drive that begins that far in the future (the entry
# continuation after a carry candidate): defenders are read where they will be
# then, and `from_pos` names where the carrier starts from (his shot's hold and
# the dead-shot proof read it). `own_hands`:
# the drive is this carrier's, so the shot at its end is held as a carry
# candidate's is (arrival_hold_wait); a receiver's hands are not modelled.
func receiver_drive_in_value(ctx: RoleContext, receiver_spot: Vector3,
		receiver_caps: AISkaterCaps,
		receiver_vel: Vector3 = Vector3.ZERO, from_pos: Vector3 = Vector3.INF,
		start_s: float = 0.0, own_hands: bool = false) -> float:
	drive_in_reached = Vector3.INF
	# A delayed offside is up: driving in from outside the zone is not on.
	if ctx.zone_entry_blocked \
			and not AIActionScoring.in_offensive_zone(receiver_spot, ctx.attacking_goal_pos):
		return 0.0
	var to_net_x: float = ctx.attacking_goal_pos.x - receiver_spot.x
	var to_net_z: float = ctx.attacking_goal_pos.z - receiver_spot.z
	var d: float = sqrt(to_net_x * to_net_x + to_net_z * to_net_z)
	# Already tight to the net: no room to improve by driving.
	if d <= RECEIVER_DRIVE_MIN_NET_DIST_M + 0.1:
		return 0.0
	var reach: float = minf(RECEIVER_DRIVE_MAX_M, d - RECEIVER_DRIVE_MIN_NET_DIST_M)
	var inv: float = 1.0 / d
	var dir_x: float = to_net_x * inv
	var dir_z: float = to_net_z * inv
	var target := Vector3(
			receiver_spot.x + dir_x * reach, 0.0, receiver_spot.z + dir_z * reach)
	if not AIStationSearch.is_legal_position(target) \
			or AINetObstacle.carry_path_blocked_by_net(receiver_spot, target):
		return 0.0
	# Momentum-honest: a man in stride carries his pace into the drive, one curling
	# back brakes it out first. Never `reach / max_speed`.
	var reach_time: float = _drive_time(ctx, receiver_spot, target, receiver_vel,
			receiver_caps, own_hands)
	# A defender in the way drops keep and stops the drive where he covers it;
	# apply_escape as for the carrier's own candidates.
	var opps: Array[Vector3] = opponents
	var opp_vels: Array[Vector3] = opponent_vels
	if start_s > 0.0:
		project_opponents(start_s, _entry_buf, _entry_vels, receiver_spot)
		opps = _entry_buf
		opp_vels = _entry_vels
	var keep: float = AICarrySpace.carry_safety(
			receiver_spot, target, reach_time,
			opps, opp_vels, opponent_caps, true)
	var reached: Vector3 = AICarrySpace.carry_strip_point(
			receiver_spot, target, reach_time,
			opps, opp_vels, opponent_caps, true, true)
	if keep <= 0.0:
		drive_in_reached = reached
		return -_drive_loss_cost(ctx, reached, 1.0, own_hands, _drive_time(ctx, receiver_spot,
				reached, receiver_vel, receiver_caps, own_hands))
	var t: float = reach_time if reached == target \
			else _drive_time(ctx, receiver_spot, reached, receiver_vel, receiver_caps, own_hands)
	project_opponents(start_s + t, _drive_buf, _drive_vels, reached)
	# The keeper tracks the drive the whole way, so it arrives at him square and
	# set — for the carrier's own drive and a receiver's alike.
	var regime_from: Vector3 = from_pos if from_pos.is_finite() else ctx.self_pos
	var hold_keep: float = 1.0
	var wait: float = 0.0
	var arrive_vel: Vector3 = (reached - receiver_spot) / t if t > 0.001 else receiver_vel
	if own_hands and shot_reads(ctx, regime_from, reached):
		wait = arrival_hold_wait(ctx, reached, arrive_vel, start_s + t)
		hold_keep = holds.arrival_keep
	var advanced: float = value_at(ctx, reached, regime_from, _drive_buf, Vector3.INF,
			0.0, hold_keep, AIShotOdds.Stance.UPRIGHT, NAN, start_s + t, arrive_vel,
			receiver_caps)
	drive_in_reached = reached
	return advanced * keep * AIActionScoring.delay_discount(t + wait) \
			- _drive_loss_cost(ctx, reached, 1.0 - keep, own_hands, t)


# The driver's time from `from` to `to` on his build: `caps`, or for the
# carrier's own drive his reads off the context; a receiver with none is the
# league build.
static func _drive_time(ctx: RoleContext, from: Vector3, to: Vector3, vel: Vector3,
		caps: AISkaterCaps, own_hands: bool) -> float:
	if caps != null or not own_hands:
		return AIArrival.time_to_arrive_caps(from, to, vel, caps)
	return AIArrival.time_to_arrive(from, to, vel, ctx.self_max_speed, ctx.self_max_accel,
			ctx.self_lateral_grip)


# A drive lost at `at` with probability `lost`, as a carry candidate's strip is
# priced: the carrier's own recovery starts there, a receiver's passer stays put.
# `loss_s` is from the drive's start, as the drive's own value is discounted.
func _drive_loss_cost(ctx: RoleContext, at: Vector3, lost: float, own_hands: bool,
		loss_s: float) -> float:
	if lost <= 0.0:
		return 0.0
	return turnover_cost(at, lost, loss_s) + counter_exposure_cost(ctx, at, lost,
			at if own_hands else ctx.self_pos, AIRoleReads.resolve_our_goalie_pos(ctx))


# The pass-option cache's spot value for the receiver standing at `pos` (0.0 when
# he is not in it — an illegal or out-of-play receiver).
func receiver_value_at(pos: Vector3) -> float:
	for i: int in receiver_pos.size():
		if receiver_pos[i] == pos:
			return receiver_val[i]
	return 0.0


# The pass OPTION a carry candidate opens: the best cached receiver value
# reachable through a CLEAR lane from the candidate spot, priced as a future
# action — lane × completion odds × the pass's flight decay ×
# PASS_OPTION_DISCOUNT. Without it a contained carrier's retreat earns nothing,
# since separation's value is the lanes it reopens. Coarse by design (receivers
# at their CURRENT spots, lanes against CURRENT defenders): it only has to rank
# spots; the fired pass is fully solved at fire time.
func pass_option_from(ctx: RoleContext, candidate: Vector3,
		useless_below: float = 0.0) -> float:
	var best: float = 0.0
	for i: int in receiver_pos.size():
		# Receiver ceiling (exact): lane/miss/decay all ≤ 1.
		if receiver_val[i] * PASS_OPTION_DISCOUNT \
				<= maxf(best, useless_below):
			continue
		var rpos: Vector3 = receiver_pos[i]
		if AINetObstacle.pass_lane_blocked_by_net(candidate, rpos):
			continue
		if AINetObstacle.pass_crosses_own_slot(
				candidate, rpos, ctx.own_goal_dir * GameRules.GOAL_LINE_Z):
			continue
		var dist: float = candidate.distance_to(rpos)
		var pass_speed: float = AIPuckLane.pass_launch_speed(
				dist, ctx.self_wrister_shot_speed, ctx.pass_speed_scale)
		var lane: float = AIPuckLane.lane_clear(
				candidate, rpos, opponents, pass_speed,
				opponent_vels, opponent_caps)
		if lane <= 0.0:
			continue
		var option: float = receiver_val[i] \
				* lane * (1.0 - AIPuckLane.pass_miss_prob(
						dist, ctx.self_pass_aim_error_rad)) \
				* AIActionScoring.delay_discount(dist / maxf(pass_speed, 1.0)) \
				* PASS_OPTION_DISCOUNT
		if option > best:
			best = option
	return best

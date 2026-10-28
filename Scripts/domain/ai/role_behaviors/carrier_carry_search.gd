class_name AICarrierCarrySearch
extends RefCounted

# The carrier's CARRY (docs/hybrid-carry-plan.md). The destination it carries
# FOR (AICarrierDestinations: the slot, the wide lanes, the zone exits, post
# walkouts, the 5v5 wheel, regroup) is chosen from the menu with hysteresis, each
# priced as a carry there. The NEAR move is one of AICarryRollout's inputs,
# skated a second toward it through the real physics and priced on where that
# leaves him, the pass option it opens, the best second move from there, and the
# odds of keeping the puck along the way; it competes with standing still.
# AIRoleCarrier owns one over its AICarrierField, calls search() in the commit
# phase and reads the result fields; it never writes them.

var _field: AICarrierField

# ── Result of search() ───────────────────────────────────────────────────────
# The best plan's value floored at 0 (what the compete reads), where it goes,
# and the unfloored value (what retention_hopeless reads).
var value: float = 0.0
var anchor: Vector3 = Vector3.ZERO
var raw_value: float = 0.0
# The destination carried to (AICarrierDestinations.Kind, -1 for none) and where.
var destination_kind: int = -1
var destination: Vector3 = Vector3.INF
# The near move that won (AICarryRollout.Move, -1 for standing still); its input
# is rollout.stick / brake / cursor at that index, and `anchor` is where it ends.
var move: int = -1
var rollout := AICarryRollout.new()
# The move this search keeps unless a challenger beats it by
# ACTION_HYSTERESIS_MARGIN_FRAC: last search's, while the destination holds.
# Every move is priced as held for a horizon and re-planned a fraction of one
# later, so without it two near-equal cuts alternate and the turns between them
# spend the speed neither priced.
var _incumbent_move: int = -1
# The second step's moves, rolled from where one first move ends.
var _rollout2 := AICarryRollout.new()

var _dest := AICarrierDestinations.new()
# The menu's totals and values on arrival, index-matched to _dest.kinds.
var _dest_totals: Array[float] = []
var _dest_arrival: Array[float] = []
# Prices the wheel destination, a carry round the back of our cage.
var _wheel: AICarrierWheel
# A carrier with no caps of its own skates the league body.
var _league_caps := AISkaterCaps.new()
# Where the last _rolled_safety read expects a loss (INF when none), and when,
# from the start of its move.
var _strip_point: Vector3 = Vector3.INF
var _strip_t: float = 0.0
# How many of each first move's path samples are skated (reach_short_of_net),
# index-matched by AICarryRollout.Move.
var _move_reach: Array[int] = []


# ── Attacking blue-line keep-out bands ──────────────────────────────────────
# Physical measurements of how far play around the carried puck extends past
# the body: the offside puck-line is the TRUE blue line, while these decisions
# are made in body positions.
#
# RETREAT: how close to the line the OZ one-way valve lets a carry candidate
# sit (see _score_move_candidate_base). The charged pass windup sweeps the
# carried puck up to a stick's reach back from the body, and the ~135 ms charge
# drifts a still-retreating body further (~7 m/s × 0.135 s); parked closer, the
# puck crosses the line mid-pass and the pass lands the whole team offside.
const OZ_RETREAT_LINE_BUFFER_M: float = GameRules.DEFAULT_STICK_LENGTH_M + 1.0

# ── Scratch buffers (reused across ticks, refilled per call) ────────────────
# Opponents projected to a carry's arrival.
var _scratch_opponents_path: Array[Vector3] = []
var _scratch_vels_path: Array[Vector3] = []

# ── The near moves' beam (two-ply search budget) ─────────────────────────────
# The two-ply pass-OPTION read is most of a move's cost. Pass 1 (_score_move)
# scores every move ONE-PLY — a strict LOWER bound on its full value, since the
# two-ply reads only ever RAISE a spot — and pass 2 (_upgrade_candidate_two_ply)
# completes the two-ply reads for the CARRY_BEAM_WIDTH best one-ply rows only,
# best-first, and for the incumbent move wherever it ranks. The argmax is
# therefore approximate (a challenger whose whole winning margin lives in the
# second ply can miss the beam) — a search-budget policy, not an
# evaluation-model change.
const CARRY_BEAM_WIDTH: int = 5
# How many of the beam's best rolled moves are searched a second step deep
# (_carry_on_value): carrying on from where each ends is a full roll of the
# moves, the costliest read in the search.
const CARRY_PLY2_WIDTH: int = 3

# Beam rows — one entry per base-scored candidate this re-eval, index-matched
# (cleared per search; clear() keeps capacity, so steady state allocates
# nothing).
var _beam_pos: Array[Vector3] = []
var _beam_total: Array[float] = []
var _beam_dest: Array[float] = []
var _beam_decay: Array[float] = []
var _beam_safety: Array[float] = []
var _beam_cost: Array[float] = []
var _beam_move: Array[int] = []

# Pass-1 running prune bound: stand-still's secured total, tightened to the
# BEST one-ply total seen so far. Exact for the argmax even though it can prune
# candidates out of the beam: a candidate whose ceiling ≤ the best one-ply row
# can never out-upgrade that row, since upgrades only raise values. Reset per
# search.
var _beam_prune_bound: float = -INF

# Is a carry candidate on ice this bot can legally stand and handle on? In
# front of the net: rink side of both goal lines, a body's width off the boards.
#
# With `allow_behind` (the carrier is already behind a goal line) the ice back
# there is legal too, except what is genuinely illegal: off the playing surface
# (corners included) and inside the cage. Without it a carrier behind the net
# has no lateral move in the search — every local candidate fails the goal-line
# clamp — and plants on the end wall until stripped. The route to each candidate
# is still checked against the net by _score_move_candidate_base.
func _candidate_ice_legal(candidate: Vector3, allow_behind: bool) -> bool:
	if absf(candidate.x) > GameRules.RINK_HALF_WIDTH - AIStationSearch.RINK_INSET_M:
		return false
	if absf(candidate.z) <= GameRules.GOAL_LINE_Z - AIStationSearch.GOAL_LINE_BUFFER_M:
		return true
	if not allow_behind:
		return false
	# On the surface (rounded corners honoured) with a body's clearance.
	var xz := Vector2(candidate.x, candidate.z)
	if not GameRules.clamp_to_rink_inner(xz, AIStationSearch.RINK_INSET_M) \
			.is_equal_approx(xz):
		return false
	# Outside the cage (the same exclusion box the skater body is held clear of).
	return GameRules.push_out_of_net(xz).is_equal_approx(xz)


func _init(field: AICarrierField) -> void:
	_field = field
	_wheel = AICarrierWheel.new(field)
	_move_reach.resize(AICarryRollout.MOVE_COUNT)


# Searches the best carry into the result fields. `value` is floored at 0, the
# "keep the puck" value for the fire compete; `raw_value` keeps the honest sign
# for the carrier's retention_hopeless read (a pinned carry that will be
# stripped must read negative). It first chooses the destination (each on the menu priced as a
# carry there, the incumbent kept by hysteresis), then the near move toward it:
# standing still, or one of the rolled moves, in TWO PASSES (see
# CARRY_BEAM_WIDTH).
#
# `shoot_now_score` is the top-level SHOOT eval (pre-ping, pre-hysteresis):
# stand-still's shot branch shares it verbatim — see the stand-still block.
func search(ctx: RoleContext, shoot_now_score: float) -> void:
	var self_pos: Vector3 = ctx.self_pos
	_field.holds.configure_from(ctx)
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	var our_goalie: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var behind_net: bool = absf(self_pos.z) > GameRules.GOAL_LINE_Z

	# Stand-still is COMPUTED up front because it doubles as an exact pruning
	# floor: it always participates in this argmax, so a movement candidate whose
	# ceiling can't strictly beat stand_total can't affect the outcome.
	var stand_score: float = shoot_now_score
	# Outside the zone the plan is still to get in, and standing a step brings
	# the entry no closer: it pays the step's time as every move does.
	if not AIActionScoring.in_offensive_zone(self_pos, attacking_goal):
		stand_score = maxf(stand_score, _field.horizon_value(self_pos, 0.0, Vector3.ZERO,
				ctx.caps_by_peer.get(ctx.peer_id))
				* AIActionScoring.delay_discount(AICarryRollout.HORIZON_S))
	var stand_puck_pos: Vector3 = AICarrierField.puck_pos_at(self_pos, attacking_goal)
	var stand_safety: float = AICarrySpace.carry_safety(
			stand_puck_pos, stand_puck_pos, AICarrySpace.EVADE_HORIZON_S,
			_field.opponents, _field.opponent_vels, _field.opponent_caps)
	var stand_cost: float = _field.turnover_cost(stand_puck_pos,
			1.0 - stand_safety)
	stand_cost += _field.counter_exposure_cost(ctx, stand_puck_pos,
			1.0 - stand_safety, self_pos, our_goalie)
	var stand_total: float = stand_score * stand_safety - stand_cost

	_beam_pos.clear()
	_beam_total.clear()
	_beam_dest.clear()
	_beam_decay.clear()
	_beam_safety.clear()
	_beam_cost.clear()
	_beam_move.clear()

	# ── The destination ─────────────────────────────────────────────────────
	# The incumbent is priced first and honestly; a challenger only matters if it
	# beats the incumbent's hysteresis key and every challenger before it, so it
	# is priced under that bound (exact: a pruned one cannot be chosen).
	_dest.fill(ctx)
	_dest_totals.resize(_dest.kinds.size())
	_dest_totals.fill(-INF)
	_dest_arrival.resize(_dest.kinds.size())
	_dest_arrival.fill(0.0)
	var key_bound: float = -INF
	# The incumbent competes at the plan last search found toward it, when that
	# beats its straight-carry estimate: the estimate is all a challenger has,
	# and through a defender's reach every lane's reads alike, so near-equal
	# lanes would trade places on noise and turn the moves' frame each time.
	var incumbent: int = _dest.kinds.find(_dest.chosen_kind)
	if incumbent >= 0:
		var t: float = _score_destination(ctx, incumbent, our_goalie, behind_net, -INF)
		if t > -INF:
			t = maxf(t, value)
		_dest_totals[incumbent] = t
		key_bound = t * (1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC) if t > 0.0 else t
	for i: int in _dest.kinds.size():
		if i == incumbent:
			continue
		var t: float = _score_destination(ctx, i, our_goalie, behind_net, key_bound)
		_dest_totals[i] = t
		key_bound = maxf(key_bound, t)
	var prev_kind: int = destination_kind
	_dest.choose(_dest_totals)
	_incumbent_move = move if _dest.chosen_kind == prev_kind else -1
	destination_kind = _dest.chosen_kind
	destination = _dest.chosen_spot

	var dest_arrival: float = 0.0
	var dest_i: int = _dest.kinds.find(destination_kind)
	if dest_i >= 0:
		dest_arrival = _dest_arrival[dest_i]

	# ── Pass 1 (beam base): the near moves, one-ply ──────────────────────────
	# The seven inputs skated from here toward the destination (the slot when
	# none can be carried to). Stand-still is always in the argmax, so it seeds
	# the exact prune bound, tightened to the best one-ply total as rows land.
	var caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	if caps == null:
		caps = _league_caps
	var aim: Vector3 = _fan_aim(ctx)
	# A destination across a cage is skated at the first waypoint round it.
	if AINetObstacle.carry_path_blocked_by_net(self_pos, aim):
		aim = AIArrival.cage_waypoint(self_pos, aim, ctx.self_velocity, caps.max_speed,
				caps.max_accel, caps.lateral_grip)
	var toward := Vector2(aim.x - self_pos.x, aim.z - self_pos.z)
	if toward.length_squared() < 0.0001:
		toward = Vector2(0.0, -ctx.own_goal_dir)
	var self_state: SkaterNetworkState = ctx.snapshot.skater_states.get(ctx.peer_id)
	var facing: Vector2 = self_state.facing if self_state != null else toward.normalized()
	rollout.roll_all(self_pos, ctx.self_velocity, facing, toward, caps, true,
			-self_state.facing_angular_velocity if self_state != null else 0.0)
	_beam_prune_bound = stand_total
	for m: int in AICarryRollout.MOVE_COUNT:
		_score_move(ctx, m, our_goalie, behind_net, caps, dest_arrival)

	var best_pos: Vector3 = self_pos
	var best_score: float = -INF
	var best_key: float = -INF
	var best_move: int = -1

	# ── Pass 2: complete the two-ply reads for the beam's best rows ──────────
	# Best-first, consuming each row as it upgrades. Rows outside the beam never
	# enter best_score (see CARRY_BEAM_WIDTH), except the incumbent: the move
	# being skated is always read as deep as the moves challenging it, or one
	# whose worth lives in its second step loses to a challenger read there
	# whenever its first step drops out of the beam, and wins back the next
	# re-plan, and the turns between them spend the speed.
	var incumbent_row: int = _beam_move.find(_incumbent_move) if _incumbent_move >= 0 else -1
	for rank: int in CARRY_BEAM_WIDTH + 1:
		var bi: int = -1
		if rank < CARRY_BEAM_WIDTH:
			var bt: float = -INF
			for j: int in _beam_total.size():
				if _beam_total[j] > bt:
					bt = _beam_total[j]
					bi = j
		elif incumbent_row >= 0 and _beam_total[incumbent_row] > -INF:
			bi = incumbent_row
		if bi == -1:
			break
		var up_total: float = _upgrade_candidate_two_ply(ctx, bi,
				rank < CARRY_PLY2_WIDTH or bi == incumbent_row, our_goalie, caps,
				_prune_bound_for(_beam_move[bi], best_key))
		var key: float = up_total
		if _beam_move[bi] == _incumbent_move and up_total > 0.0:
			key *= 1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC
		if key > best_key:
			best_key = key
			best_score = up_total
			best_pos = _beam_pos[bi]
			best_move = _beam_move[bi]
		_beam_total[bi] = -INF   # consumed — next rank takes the next-best row

	# Stand-still last, winning only on STRICTLY greater. Its shot branch is the
	# shoot-now score verbatim because "hold and fire from here" and SHOOT are the
	# same physical act; priced separately at the CURRENT spot, a mid-cut hold
	# would read richer than the fire from the same instant and the bot would
	# hold exactly when the window is open. Sharing it makes fire-wins-ties hold
	# by definition: stand_total = shoot_now × safety − cost ≤ shoot_now ≤ fire.
	# Stand pays the strip cost like every candidate; without it freezing would be
	# the one option that never prices losing the puck, and a bot under a
	# converging forechecker would plant itself exactly when it should skate clear.
	if stand_total > best_key:
		best_score = stand_total
		best_pos = self_pos
		best_move = -1

	value = maxf(best_score, 0.0)
	anchor = best_pos
	raw_value = best_score
	move = best_move


# A new possession: the destination is chosen afresh.
func reset() -> void:
	_dest.reset()
	destination_kind = -1
	destination = Vector3.INF
	move = -1


# The full value of carrying to menu destination `i`, -INF when it cannot be
# carried to or cannot beat `best_so_far`. Scored outside the beam: its row is
# dropped again.
func _score_destination(ctx: RoleContext, i: int, our_goalie: Vector3, behind_net: bool,
		best_so_far: float) -> float:
	var kind: int = _dest.kinds[i]
	var spot: Vector3 = _dest.spots[i]
	if AICarrierDestinations.is_wheel(kind):
		var wheel_total: float = _wheel.score(ctx, spot, our_goalie, best_so_far)
		_dest_arrival[i] = _wheel.arrival
		return wheel_total
	if not _candidate_ice_legal(spot, behind_net):
		return -INF
	var rows_before: int = _beam_total.size()
	var total: float = _score_move_candidate(ctx, spot, our_goalie,
			AICarrierDestinations.is_walkout(kind), best_so_far)
	if _beam_total.size() > rows_before:
		_dest_arrival[i] = _beam_dest[rows_before]
	_beam_move.resize(rows_before)
	_beam_pos.resize(rows_before)
	_beam_total.resize(rows_before)
	_beam_dest.resize(rows_before)
	_beam_decay.resize(rows_before)
	_beam_safety.resize(rows_before)
	_beam_cost.resize(rows_before)
	return total


# Pass-1 row for rolled move `m`: priced on where it leaves him —
#
#   max(arrival value there, the destination's value carried on from there)
#     × decay(horizon) × keep odds along the rolled path − turnover cost
#
# The arrival value is the shot or position at the move's end at its real end
# velocity; carried on, the destination is worth its value on arrival × the keep
# odds of the rest of the trip × its decay. Illegal moves add no row:
# out of the zone through the one-way valve, or into it while a tag-up is owed.
# A move ends at its last sample short of a crease, or of the goal line from in
# front: the carrier re-plans many times a horizon, so a drive at the net is a
# release on the way in. Pruned whole, every move at pace in tight was, and only
# the brake and the cut back were left.
func _score_move(ctx: RoleContext, m: int, our_goalie: Vector3, behind_net: bool,
		caps: AISkaterCaps, dest_arrival: float) -> void:
	_move_reach[m] = 0
	if not _move_legal(ctx, rollout, m, ctx.self_pos):
		return
	var reach: int = rollout.reach_short_of_net(m, _max_abs_z(behind_net))
	if reach == 0:
		return
	_move_reach[m] = reach
	var end: Vector3 = rollout.reach_pos(m, reach)
	var t0: float = AICarryRollout.HORIZON_S * reach / AICarryRollout.SAMPLES
	var decay: float = AIActionScoring.delay_discount(t0)
	var bound: float = _prune_bound_for(m, _beam_prune_bound)
	if decay <= bound:
		return
	var safety: float = _rolled_safety(ctx, rollout, m, reach)
	if decay * safety <= bound:
		return
	_field.project_opponents(t0, _scratch_opponents_path, _scratch_vels_path, end)
	var worth: float = _end_worth(ctx, end, rollout.reach_vel(m, reach, ctx.self_pos), t0,
			caps, dest_arrival)
	var cost: float = 0.0
	if safety < 1.0 and _strip_point.is_finite():
		cost = _field.turnover_cost(_strip_point, 1.0 - safety, _strip_t)
		cost += _field.counter_exposure_cost(ctx, _strip_point, 1.0 - safety, end,
				our_goalie)
	var total: float = worth * decay * safety - cost
	_beam_pos.append(end)
	_beam_total.append(total)
	_beam_dest.append(worth)
	_beam_decay.append(decay)
	_beam_safety.append(safety)
	_beam_cost.append(cost)
	_beam_move.append(m)
	if total > _beam_prune_bound:
		_beam_prune_bound = total


# The total move `m` must beat to matter against `bound`: the incumbent move
# wins with its hysteresis margin, so its own bar sits that much lower.
func _prune_bound_for(m: int, bound: float) -> float:
	if m == _incumbent_move and bound > 0.0:
		return bound / (1.0 + AIActionScoring.ACTION_HYSTERESIS_MARGIN_FRAC)
	return bound


# What the rolled moves are oriented on: the destination, or the slot when no
# carry pays anywhere — an argmax of the menu's losses is an arbitrary lane,
# and it would turn the whole fan with it.
func _fan_aim(ctx: RoleContext) -> Vector3:
	if destination_kind >= 0 and _dest.chosen_total > 0.0:
		return destination
	return AICarrierField.slot_anchor(ctx.own_goal_dir)


# The |z| a move from in front of the goal lines may not pass; none from behind.
static func _max_abs_z(behind_net: bool) -> float:
	return INF if behind_net else GameRules.GOAL_LINE_Z - AIStationSearch.GOAL_LINE_BUFFER_M


# Whether rolled move `m` of `roll`, skated from `from`, is one the carrier may
# make: not out of the zone through the one-way valve, not into it while a
# tag-up is owed.
func _move_legal(ctx: RoleContext, roll: AICarryRollout, m: int, from: Vector3) -> bool:
	var goal: Vector3 = ctx.attacking_goal_pos
	var end: Vector3 = roll.end_pos[m]
	if AIActionScoring.in_offensive_zone(from, goal) \
			and not AIActionScoring.in_offensive_zone(end, goal, OZ_RETREAT_LINE_BUFFER_M):
		return false
	if ctx.zone_entry_blocked and AIActionScoring.in_offensive_zone(end, goal) \
			and not AIActionScoring.in_offensive_zone(from, goal):
		return false
	return true


# What a rolled move's end at `end`, moving at `end_vel` and reached `t_end`
# from now, is worth: the arrival value there, or the destination's value carried on from there —
# its value on arrival × the keep odds of the rest of the trip × its decay —
# unless that carry crosses into the attacking zone: getting in past the
# defence at the line is priced by the race in the end's own horizon value
# (AICarrierField.horizon_value), not by a straight carry read beyond what the
# search reached. Reads the defence in _scratch_opponents_path, projected to
# `t_end`.
func _end_worth(ctx: RoleContext, end: Vector3, end_vel: Vector3, t_end: float,
		caps: AISkaterCaps, dest_arrival: float) -> float:
	var worth: float = _arrival_value(ctx, end, end_vel, t_end)
	var goal: Vector3 = ctx.attacking_goal_pos
	if destination_kind >= 0 and dest_arrival > worth \
			and (AIActionScoring.in_offensive_zone(end, goal)
					or not AIActionScoring.in_offensive_zone(destination, goal)):
		var t_rest: float = AIArrival.time_to_arrive(end, destination, end_vel,
				caps.max_speed, caps.max_accel, caps.lateral_grip)
		worth = maxf(worth, dest_arrival * AIActionScoring.delay_discount(t_rest)
				* AICarrySpace.carry_safety(
						AICarrierField.puck_pos_at(end, goal),
						AICarrierField.puck_pos_at(destination, goal), t_rest,
						_field.opponents, _field.opponent_vels, _field.opponent_caps,
						0.0, t_end))
	return worth


# The best second step from where first move `m1` ends, as a value at that end:
# each rolled move again, from the end's position, pace and facing, setting off
# a first move's horizon from now, priced as a first move is —
# its end's worth × the decay of the step × its keep odds − its strip cost.
# Returns `floor_value` when no second move beats it (exact: a move whose worth ×
# decay cannot clear it is not read for safety, nor costed when × keep odds cannot).
func _carry_on_value(ctx: RoleContext, m1: int, our_goalie: Vector3,
		caps: AISkaterCaps, floor_value: float = -INF) -> float:
	var t1: float = AICarryRollout.HORIZON_S
	var start: Vector3 = rollout.end_pos[m1]
	var aim: Vector3 = _fan_aim(ctx)
	if AINetObstacle.carry_path_blocked_by_net(start, aim):
		aim = AIArrival.cage_waypoint(start, aim, rollout.end_vel[m1], caps.max_speed,
				caps.max_accel, caps.lateral_grip)
	var toward := Vector2(aim.x - start.x, aim.z - start.z)
	if toward.length_squared() < 0.0001:
		toward = Vector2(0.0, -ctx.own_goal_dir)
	_rollout2.roll_all(start, rollout.end_vel[m1], rollout.end_facing[m1], toward, caps, true,
			rollout.end_turn_rate[m1])
	var dest_arrival: float = 0.0
	var dest_i: int = _dest.kinds.find(destination_kind)
	if dest_i >= 0:
		dest_arrival = _dest_arrival[dest_i]
	var behind_net: bool = absf(start.z) > GameRules.GOAL_LINE_Z
	var best: float = floor_value
	for m: int in AICarryRollout.MOVE_COUNT:
		if not _move_legal(ctx, _rollout2, m, start):
			continue
		var reach: int = _rollout2.reach_short_of_net(m, _max_abs_z(behind_net))
		if reach == 0:
			continue
		var t2: float = AICarryRollout.HORIZON_S * reach / AICarryRollout.SAMPLES
		_field.project_opponents(t1 + t2, _scratch_opponents_path, _scratch_vels_path,
				_rollout2.reach_pos(m, reach))
		var worth: float = _end_worth(ctx, _rollout2.reach_pos(m, reach),
				_rollout2.reach_vel(m, reach, start), t1 + t2, caps, dest_arrival) \
				* AIActionScoring.delay_discount(t2)
		if worth <= best:
			continue
		var safety: float = _rolled_safety(ctx, _rollout2, m, reach, t1)
		var move_value: float = worth * safety
		if move_value <= best:
			continue
		if safety < 1.0 and _strip_point.is_finite():
			move_value -= _field.turnover_cost(_strip_point, 1.0 - safety, _strip_t)
			move_value -= _field.counter_exposure_cost(ctx, _strip_point, 1.0 - safety,
					_rollout2.reach_pos(m, reach), our_goalie)
		best = maxf(best, move_value)
	return best


# The odds of keeping the puck along rolled move `m` of `roll` from `from`,
# setting off `start_s` from now against the defence as it is now: each
# defender's one chance at the move's skated samples (AIStripOdds), each sample
# at its own time. Leaves where a loss is expected in _strip_point (INF: none) —
# each defender's first chance, weighted by his odds of taking it — and when,
# from the start of the move, in _strip_t.
func _rolled_safety(ctx: RoleContext, roll: AICarryRollout, m: int,
		reach: int = AICarryRollout.SAMPLES, start_s: float = 0.0) -> float:
	var goal: Vector3 = ctx.attacking_goal_pos
	var opps: Array[Vector3] = _field.opponents
	var has_caps: bool = _field.opponent_caps.size() == opps.size()
	var keep: float = 1.0
	var lost: float = 0.0
	var at := Vector3.ZERO
	var when: float = 0.0
	for i: int in opps.size():
		var caps: AISkaterCaps = _field.opponent_caps[i] if has_caps else null
		var best: float = 0.0
		var best_p := Vector3.ZERO
		var best_t: float = 0.0
		var first: bool = false
		for k: int in reach:
			var t: float = AICarryRollout.HORIZON_S * float(k + 1) / AICarryRollout.SAMPLES
			var p: Vector3 = AICarrierField.puck_pos_at(roll.sample(m, k), goal)
			var c: float = AIStripOdds.strip_at(opps[i], _field.opponent_vels[i], caps, p,
					start_s + t)
			if not first and (c > best or c >= 0.5):
				best_p = p
				best_t = t
				first = c >= 0.5
			best = maxf(best, c)
		keep *= 1.0 - best
		at += best_p * best
		when += best_t * best
		lost += best
	_strip_point = at / lost if lost > 1e-4 else Vector3.INF
	_strip_t = when / lost if lost > 1e-4 else 0.0
	return keep


# One-ply EV of one movement carry candidate — the scoring every non-stand-still
# candidate in the beam runs:
#
#   dest_score × decay × safety − turnover_cost
#
# `safety` is the reachable clearance over the PUCK's path to the candidate
# across the arrival time, so it sees both a defender converging on the ROUTE
# and one waiting at the DESTINATION; a committed charger whose momentum
# carries him past reads as clear. 1 − safety is the strip probability, priced
# at the EARLIEST covered point on the route (carry_strip_point), not the
# destination: a carry that ends in open ice but threads our own slot pays the
# slot's turnover cost.
#
# Returns -INF for an illegal or unreachable candidate, or one whose ceiling
# cannot beat `best_so_far`. Every finite score appends a beam row stashing the
# intermediates _upgrade_candidate_two_ply needs, so pass 2 recomputes nothing.
func _score_move_candidate_base(ctx: RoleContext, candidate: Vector3,
		our_goalie: Vector3, is_post_walkout: bool = false,
		best_so_far: float = -INF) -> float:
	var self_pos: Vector3 = ctx.self_pos
	# One-way valve: once in the offensive zone, don't carry the puck back out,
	# buffered by OZ_RETREAT_LINE_BUFFER_M. Stand-still never trips this, so the
	# candidate set is never empty; a carrier already inside the band keeps only
	# deeper candidates, easing it off the line.
	if AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(
					candidate, ctx.attacking_goal_pos, OZ_RETREAT_LINE_BUFFER_M):
		return -INF
	# Its NHL mirror: with a teammate owing a tag-up, carrying in is whistled at
	# once. Judged on the body, so stand-still (outside) always survives; the last
	# stick of puck lead is the steering's offside brake on the puck.
	if ctx.zone_entry_blocked \
			and AIActionScoring.in_offensive_zone(candidate, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos):
		return -INF
	# The cage is a wall: the time/safety math below assumes the straight
	# traverse. POST-WALKOUT candidates are exempt — they are reached around the
	# post (the steering's net detour), which the straight-segment test can't see.
	if not is_post_walkout \
			and AINetObstacle.carry_path_blocked_by_net(self_pos, candidate):
		return -INF
	var local_time: float = AIArrival.time_to_arrive(
			self_pos, candidate, ctx.self_velocity, ctx.self_max_speed,
			ctx.self_max_accel, ctx.self_lateral_grip)
	# CEILING PRUNES (exact): with dest_score ≤ 1 and cost ≥ 0, each partial
	# product of the ≤ 1 factors is a hard upper bound, checked in cost order —
	# decay alone before the safety read, × safety before the arrival-shot /
	# strip machinery. Under pressure SAFETY is the killer, so a swarmed carrier
	# doesn't pay full price for doomed spots.
	var decay: float = AIActionScoring.delay_discount(local_time)
	if decay <= best_so_far:
		return -INF
	var cand_puck_pos: Vector3 = AICarrierField.puck_pos_at(candidate, ctx.attacking_goal_pos)
	var cur_puck_pos: Vector3 = AICarrierField.puck_pos_at(self_pos, ctx.attacking_goal_pos)
	# apply_escape: a defender the carrier out-skates on this drive can't sustain
	# the strip, so driving PAST a man reads as winnable, not as a wall.
	var safety: float = AICarrySpace.carry_safety(
			cur_puck_pos, cand_puck_pos, local_time,
			_field.opponents, _field.opponent_vels, _field.opponent_caps)
	if decay * safety <= best_so_far:
		return -INF
	_field.project_opponents(local_time, _scratch_opponents_path, _scratch_vels_path,
			candidate)
	var to_cand: Vector3 = candidate - self_pos
	to_cand.y = 0.0
	var cand_dist: float = to_cand.length()
	var arrive_vel: Vector3 = Vector3.ZERO
	if cand_dist > 0.001 and local_time > 0.001:
		# Arrival pace consistent with time_to_arrive's constant-effective-speed
		# travel model, capped at this bot's real top end.
		var arrive_speed: float = minf(cand_dist / local_time, ctx.self_max_speed)
		arrive_vel = to_cand * (arrive_speed / cand_dist)
	var dest_score: float = _arrival_value(ctx, candidate, arrive_vel, local_time)
	var keep_prob: float = safety
	var cost: float = 0.0
	# A fully safe route (the common open-ice case) skips localizing a strip
	# that cannot happen.
	if keep_prob < 1.0:
		var strip_point: Vector3 = AICarrySpace.carry_strip_point(
				cur_puck_pos, cand_puck_pos, local_time,
				_field.opponents, _field.opponent_vels, _field.opponent_caps)
		var cand_len: float = cur_puck_pos.distance_to(cand_puck_pos)
		cost = _field.turnover_cost(strip_point, 1.0 - keep_prob, local_time
				* cur_puck_pos.distance_to(strip_point) / cand_len if cand_len > 0.001 else 0.0)
		# Transition exposure (5v5): the carrier's recovery race starts from the
		# CANDIDATE, the spot this carry commits him to.
		cost += _field.counter_exposure_cost(ctx, strip_point, 1.0 - keep_prob,
				candidate, our_goalie)
	var total: float = dest_score * decay * safety - cost
	# Beam row: this candidate's final value unless pass 2 upgrades it.
	_beam_pos.append(candidate)
	_beam_total.append(total)
	_beam_dest.append(dest_score)
	_beam_decay.append(decay)
	_beam_safety.append(safety)
	_beam_cost.append(cost)
	_beam_move.append(-1)
	return total


# What `candidate` is worth to this carrier arriving there at `arrive_vel` after
# `local_time`, against the defence projected to then in _scratch_opponents_path
# (the caller fills it): the shot on arrival, or the position.
#
# The candidate's shot is taken ARRIVING AT PACE (carry steps are skated at
# speed; the arrival brake skips carry waypoints), so it is the same
# moving-release wrister the shoot-now eval prices. Two-phase keeper:
#   1. TRACK: he follows the whole carry to the candidate's arc-square
#      (generous to him: he never falls behind en route).
#   2. FINAL RACE: from that square he races the wind-up + flight against a
#      release still sliding at the arrival speed — the race a hard lateral
#      cut in tight genuinely wins.
# Phase 2 is what gives a STANDSTILL 1v1 a gradient toward building the
# lateral speed that opens the window; a static release would score every
# one-step spot against a set keeper ~0. Because he is SQUARE at every
# candidate before the final race, a further cut never prices more than the
# last-quarter-second window, so the cut cannot recede forever.
#
# The arrival UNSETTLE is read from the TRACKED keeper over the FINAL window
# only: the carry never catches him, only the re-square the release demands
# can. Never measure it from his CURRENT position over the whole carry — that
# charges him for a swing his tracking already covers and makes every
# doorstep drive a phantom caught-moving goalie.
func _arrival_value(ctx: RoleContext, candidate: Vector3, arrive_vel: Vector3,
		local_time: float) -> float:
	var self_pos: Vector3 = ctx.self_pos
	# The shot on arrival is held as the shoot-now sweep would hold it
	# (arrival_hold_wait): at that hold's pace and keep odds, with any pull the
	# carry is too short for waited out in the wind-up the keeper races.
	var cand_wait: float = 0.0
	var cand_keep: float = 1.0
	if AICarrierField.shot_reads(ctx, self_pos,
			candidate + arrive_vel * AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S):
		cand_wait = _field.arrival_hold_wait(ctx, candidate, arrive_vel, local_time)
		cand_keep = _field.holds.arrival_keep
	var cand_windup: float = AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S + cand_wait
	# The keeper backs in as the carry closes on him (the planning depth model).
	# Closing is the rate this carry shortens the puck's distance to the goal.
	var carry_closing: float = (self_pos.distance_to(ctx.attacking_goal_pos)
			- candidate.distance_to(ctx.attacking_goal_pos)) / maxf(local_time, 0.001)
	var tracked_goalie: Vector3 = AIGoalieModel.predict_goalie_pos(
			AICarrierField.goalie_now(ctx), ctx.attacking_goal_pos, local_time, candidate,
			carry_closing)
	var cand_release: Vector3 = AIGoalieModel.release_ahead_of_goalie(
			candidate + arrive_vel * cand_windup,
			ctx.attacking_goal_pos, tracked_goalie)
	# The shot is decided on ARRIVAL, against the keeper as he is then: a carry
	# that outran him leaves him still pushing toward his square, at the share of
	# the push he has left (goalie_unsettled). The field prices what he does over
	# the wind-up and flight itself. A goalie-motion-blind tier reads him still.
	var lag: float = AIGoalieModel.goalie_arc_match_x(
			tracked_goalie, ctx.attacking_goal_pos, cand_release) - tracked_goalie.x
	var keeper_vel_x: float = signf(lag) * AIGoalieModel.GOALIE_MAX_LATERAL_SPEED_MPS \
			* AICarrierField.goalie_unsettled_at(ctx, local_time, candidate, carry_closing)
	# Having tracked the carry he faces the shot, as the shoot-now read will see
	# him there. Left unread, the field blends in keepers turned to a decoy or a
	# feed, which in tight promise odds the shot on arrival never has.
	var dest_score: float = _field.value_at(ctx, cand_release, self_pos,
			_scratch_opponents_path, tracked_goalie, keeper_vel_x, cand_keep,
			_field.keeper_stance_at(local_time + cand_windup),
			atan2(tracked_goalie.x - cand_release.x, tracked_goalie.z - cand_release.z),
			local_time, arrive_vel, ctx.caps_by_peer.get(ctx.peer_id))
	# ENTRY CONTINUATION: from outside the zone an in-zone candidate is worth what
	# a carrier there does next — the drive-in from it, priced in the in-zone
	# regime and starting when we arrive — which its own shot xG badly
	# understates just inside the line.
	if AIActionScoring.in_offensive_zone(candidate, ctx.attacking_goal_pos) \
			and not AIActionScoring.in_offensive_zone(self_pos, ctx.attacking_goal_pos):
		dest_score = maxf(dest_score, _field.receiver_drive_in_value(
				ctx, candidate, ctx.caps_by_peer.get(ctx.peer_id), arrive_vel, candidate,
				local_time, true))
	return dest_score


# TWO-PLY pass of the beam (see CARRY_BEAM_WIDTH): completes beam row `i` with
# the pass OPTION the spot opens (pass_option_from), credited as the
# IMPROVEMENT over the same read at the current spot — a lane already open from
# here is the live pass's to take, so holding a cashable option is never a
# reason to keep carrying. CEILING PRUNE (exact): the credit can't exceed
# _field.pass_option_ceiling − _field.pass_option_at_self, so when that can't raise
# dest_score the per-receiver lane loop is skipped.
#
# With `carry_on`, the row's move is also searched a second step deep, for a
# step that lifts the row past `best_so_far` (exact: a step's worth is odds, at
# most 1, so it is worth at most its own decay; one that cannot win the argmax
# is not priced).
func _upgrade_candidate_two_ply(ctx: RoleContext, i: int, carry_on: bool = false,
		our_goalie: Vector3 = Vector3.ZERO, caps: AISkaterCaps = null,
		best_so_far: float = -INF) -> float:
	var candidate: Vector3 = _beam_pos[i]
	var dest_score: float = _beam_dest[i]
	var decay: float = _beam_decay[i]
	var safety: float = _beam_safety[i]
	var row_scale: float = decay * safety
	var step_needs: float = dest_score
	if row_scale > 0.0:
		step_needs = maxf(step_needs, (best_so_far + _beam_cost[i]) / row_scale)
	if carry_on and _beam_move[i] >= 0 \
			and _move_reach[_beam_move[i]] == AICarryRollout.SAMPLES \
			and AIActionScoring.delay_discount(AICarryRollout.HORIZON_S) > step_needs:
		var step: float = _carry_on_value(ctx, _beam_move[i], our_goalie, caps, step_needs)
		if step > step_needs:
			dest_score = step
	if _field.pass_option_ceiling - _field.pass_option_at_self > dest_score:
		dest_score = maxf(dest_score, maxf(
				0.0, _field.pass_option_from(ctx, candidate,
						dest_score + _field.pass_option_at_self) - _field.pass_option_at_self))
	_beam_dest[i] = dest_score
	return dest_score * decay * safety - _beam_cost[i]


# FULL eval of a single candidate — base + two-ply upgrade in one call: a
# destination, and the single-candidate consumers (unit tests, the ai_micro
# bench). Leaves the candidate's row in the beam scratch.
func _score_move_candidate(ctx: RoleContext, candidate: Vector3,
		our_goalie: Vector3, is_post_walkout: bool = false,
		best_so_far: float = -INF) -> float:
	var rows_before: int = _beam_total.size()
	var base: float = _score_move_candidate_base(
			ctx, candidate, our_goalie, is_post_walkout, best_so_far)
	if _beam_total.size() == rows_before:
		return base   # ceiling-pruned — no row to upgrade
	return _upgrade_candidate_two_ply(ctx, _beam_total.size() - 1)

class_name AICarrierPassSearch
extends RefCounted

# The carrier's PASS options: the best feed this eval (straight, saucer or rim,
# per receiver, on EV), and the value of a feed a teammate is still developing.
# AIRoleCarrier owns one over its AICarrierField, calls search() in the fire
# phase and developing_feed_value() in the commit phase, and reads the result
# fields; it never writes them.

# EV multiplier a live human ping puts on a pass: a tactical ORDER, the pass's
# twin of AIRoleCarrier.PING_SHOOT_EV_MULT.
const PING_PASS_EV_MULT: float = 3.0

# Cap on a pass's solved lead time (s); longer leads rest on stale opponent
# projections. 1.0 s leads a soft feed (12 m/s closing) ~12 m and a full-pace
# one ~20 m, so a pass softens across the distances the NHL ones do.
const PASS_LEAD_MAX_S: float = 1.0

# A rim is fired as soft as the race allows: any launch reaching the receiver at
# least this share as surely as the best one may be picked, and the softest of
# those is. Doctrine, not a measurement — a soft rim is easier to stop, and one
# that gets by him dies sooner (under NHL rules, short of an icing).
const RIM_SOFT_SHARE: float = 0.9

# Developing-feed hold: how far ahead (s) a skating teammate's spot is projected
# when valuing the pass he is CREATING (see developing_feed_value) — the spot he
# is getting open at. 1.2 s ≈ a finisher's next two strides at a zone entry,
# still inside the pass-lead horizon by release; the delay discount prices the
# wait. Much shorter (~0.7 s) and the window cannot see past the calibrated
# surface's dead mid-band, so a fresh entry reads "nothing developing" while the
# house drive is one stride from being the best play on the ice.
const OUTLET_DEVELOP_WINDOW_S: float = 1.2

# Below this speed the outlet isn't going anywhere — the spot it offers
# is the spot it's at, and the live pass scoring already prices that.
const OUTLET_DEVELOP_MIN_SPEED_M_S: float = 1.0

var _field: AICarrierField

# ── Result of search() ───────────────────────────────────────────────────────
# The best feed: its receiver (0 when none), EV, whether it is the saucer
# variant, and for a rim its launch bearing and pace (ZERO / 0 for a straight
# feed).
var best_peer: int = 0
var best_score: float = 0.0
var best_is_saucer: bool = false
var best_rim_dir: Vector3 = Vector3.ZERO
var best_rim_pace: float = 0.0
# The straight feed's pace, as its AIPuckLane.PASS_PACE_FRACS step on the pace
# scale (1.0 for a rim or no feed): what the commit fires it at.
var best_pace_frac: float = 1.0


# ── Scratch ──────────────────────────────────────────────────────────────────
# The best launch _rim_launch_for found, and its path reads.
var _rim_k: int = -1
var _rim_t: float = 0.0
var _rim_lane: float = 0.0
var _rim_miss: float = 0.0
# Per-launch reads for one receiver (index-matched to AIRimPass' scratch, -1 =
# not a candidate), so the softest near-best launch can be picked after the scan.
var _rim_sure_by_k: PackedFloat64Array = PackedFloat64Array()
var _rim_t_by_k: PackedFloat64Array = PackedFloat64Array()
var _rim_lane_by_k: PackedFloat64Array = PackedFloat64Array()
var _rim_miss_by_k: PackedFloat64Array = PackedFloat64Array()
# Opponents projected to a feed's arrival (and a developing feed's flight).
var _proj_buf: Array[Vector3] = []
var _proj_vels: Array[Vector3] = []
# Lane of the last FLAT _pass_variant_ev (0.0 when the variant filtered out
# before its lane solve). The saucer gate reads it — see search.
var _last_flat_variant_lane: float = 0.0


func _init(field: AICarrierField) -> void:
	_field = field


# Searches the best pass this eval into the best_* result fields.
#
# Each receiver is scored as up to two straight variants competing on EV
# (_pass_variant_ev): the flat feed at the best of its paces
# (AIPuckLane.PASS_PACE_FRACS, each a receiver-relative launch), and — when the
# flat lane is contested — a saucer at min(that pace, the receivability bound),
# paying SAUCER_EXTRA_MISS_PROB for its landing. Rim
# launches are ranked per receiver too, and only the eval's single best rim is
# priced through the full _pass_ev, after the loop.
#
# Filtered here: out-of-play receivers, and, for an OZ carrier, receivers
# outside the zone. The lead-dependent filters live in _pass_variant_ev, the
# lane hard-zeros in _pass_ev. Behind-the-back receivers are NOT skipped: only
# the narrow wedge past the reach cone pays, as rotation time in the delay
# (_facing_rotation_time).
func search(ctx: RoleContext, self_facing_xz: Vector2,
		teammate_ids: Array[int]) -> void:
	var snapshot: WorldSnapshot = ctx.snapshot
	var self_pos: Vector3 = ctx.self_pos
	var best_pass_peer: int = 0
	var best_pass_score: float = 0.0
	var best_pass_saucer: bool = false
	var best_pass_frac: float = 1.0
	var our_goalie: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var attacking_goal: Vector3 = ctx.attacking_goal_pos
	# One-way valve: once the zone is taken the carrier won't pass the puck back
	# out of it (the carry-side valve is in AICarrierCarrySearch).
	var carrier_in_oz: bool = AICarrierField.zone_taken(ctx)
	var pass_origin: Vector3 = AICarrierField.pass_origin(ctx)
	var best_pass_rim_dir := Vector3.ZERO
	var best_pass_rim_pace: float = 0.0
	# Rim launches are receiver-independent: searched once per eval, and only
	# once some receiver's flat lane is contested enough to want one (-1 =
	# not searched yet).
	var rim_count: int = -1
	# The eval's best rim candidate: receiver, launch, and its path reads.
	var rim_rank: float = 0.0
	var rim_peer: int = -1
	var rim_k: int = -1
	var rim_t: float = 0.0
	var rim_lane: float = 0.0
	var rim_miss: float = 0.0
	for peer_id: int in teammate_ids:
		var receiver_state: SkaterNetworkState = snapshot.skater_states[peer_id]
		if snapshot.is_out_of_play(peer_id):
			continue
		if carrier_in_oz and not AIActionScoring.in_offensive_zone(
				receiver_state.position, attacking_goal):
			continue
		var receiver_is_one_timer: bool = (ctx.team_brain != null
				and ctx.team_brain.is_one_timer_ready(peer_id))
		# Score at the speed the commit will actually fire: the same
		# receiver-relative launch solve as the INTENT_PASS block in
		# _pick_commit_phase, capped at what this bot's load can carry
		# (pass_launch_cap). Any other pace mis-places the lead and gives the
		# defenders the wrong flight time to close.
		var dist: float = pass_origin.distance_to(receiver_state.position)
		var to_recv: Vector3 = receiver_state.position - pass_origin
		to_recv.y = 0.0
		var scored_pass_dir: Vector3 = to_recv.normalized() \
				if to_recv.length_squared() > 0.0001 else Vector3.ZERO
		var launch_cap: float = _field.pass_launch_cap(ctx, scored_pass_dir, self_facing_xz)
		var receiver_accel: Vector3 = ctx.acceleration_by_peer.get(peer_id, Vector3.ZERO)
		# Receiver's heading turn rate — the commitment read; 0 for a
		# commitment-blind tier.
		var receiver_omega: float = ctx.heading_omega_by_peer.get(peer_id, 0.0) \
				if ctx.reads_receiver_commitment else 0.0
		var receiver_caps: AISkaterCaps = ctx.caps_by_peer.get(peer_id)
		var receiver_top_speed: float = receiver_caps.max_speed if receiver_caps != null \
				else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
		# Exact prune floor for this receiver: the running best, divided by any
		# bonus applied to him AFTER scoring (the ping multiplier below), so the
		# bound stays sound.
		var prune_floor: float = best_pass_score
		if peer_id == ctx.ping_pass_target_peer:
			prune_floor /= PING_PASS_EV_MULT
		# Flat feed, at each pace from full down; the saucer gate reads the winning
		# pace's lane, or full pace's when none scores.
		var s: float = 0.0
		var pass_speed: float = 0.0
		var pass_frac: float = 1.0
		var flat_lane: float = 0.0
		var full_speed: float = 0.0
		var full_lane: float = 0.0
		var prev_speed: float = -1.0
		var prev_hold: float = INF
		var fracs: Array[float] = AIPuckLane.PASS_PACE_FRACS
		for i: int in range(fracs.size() - 1, -1, -1):
			var frac: float = fracs[i]
			var speed: float = AIPuckLane.pass_launch_speed(dist, launch_cap,
					ctx.pass_speed_scale * frac, receiver_state.velocity, scored_pass_dir)
			if speed == prev_speed:
				continue   # clamped onto the last pace's launch: the same pass
			# A softer pace only flies longer, so it can win only by tying the
			# receiver up for less than the harder one did (read on the straight
			# line, before the lead solve) — and only if its flight fits the lead
			# horizon even with him skating flat out at the passer.
			var hold: float = 0.0 if receiver_is_one_timer else AIFeedReception.reception_hold_s(
					AIFeedReception.arrival_closing_speed(pass_origin, receiver_state.position,
							speed, receiver_state.velocity))
			if frac < 1.0 and (hold >= prev_hold
					or dist > (speed + receiver_top_speed) * PASS_LEAD_MAX_S):
				continue
			prev_speed = speed
			prev_hold = hold
			_last_flat_variant_lane = 0.0
			var s_pace: float = _pass_variant_ev(
					ctx, receiver_state, receiver_accel, receiver_omega, receiver_caps,
					pass_origin, speed, false, receiver_is_one_timer,
					self_facing_xz, our_goalie, carrier_in_oz, maxf(prune_floor, s),
					frac < 1.0)
			if frac == 1.0:
				full_speed = speed
				full_lane = _last_flat_variant_lane
			if s_pace > s:
				s = s_pace
				pass_speed = speed
				pass_frac = frac
				flat_lane = _last_flat_variant_lane
		if s <= 0.0:
			pass_speed = full_speed
			pass_frac = 1.0
			flat_lane = full_lane
		_last_flat_variant_lane = flat_lane
		var use_saucer: bool = false
		# Saucer variant: the fastest RECEIVABLE flip. Below the soft-touch
		# wrister floor no legal saucer exists (the physical minimum saucer
		# distance, ~6.5 m).
		var saucer_speed: float = minf(
				pass_speed, AIPuckLane.saucer_max_launch_speed(dist))
		# Saucer competes only when the FLAT feed is contested
		# (SAUCER_SKIP_WHEN_LANE_CLEAR), read off the flat variant's solved lane so
		# a clear-lane receiver skips the second solve. A flat variant filtered
		# before its lane solve leaves 0.0 — "contested" — so the saucer still
		# gets its own look at leads the flat pass couldn't take.
		if saucer_speed >= AIPuckLane.SOFTEST_FEED_M_S \
				and _last_flat_variant_lane < AIPuckLane.SAUCER_SKIP_WHEN_LANE_CLEAR:
			var s_saucer: float = _pass_variant_ev(
					ctx, receiver_state, receiver_accel, receiver_omega, receiver_caps,
					pass_origin, saucer_speed, true, receiver_is_one_timer,
					self_facing_xz, our_goalie, carrier_in_oz, maxf(prune_floor, s))
			if s_saucer > s:
				s = s_saucer
				use_saucer = true
		# Like the saucer, the rim competes only when the flat feed is contested:
		# with the lane clear there is nothing for the boards to carry it past.
		# Its candidate is only RANKED here (see _rim_launch_for); the one best
		# rim of the eval is priced after the loop.
		if rim_count != 0 \
				and _last_flat_variant_lane < AIPuckLane.SAUCER_SKIP_WHEN_LANE_CLEAR:
			if rim_count < 0:
				rim_count = AIRimPass.build(pass_origin, ctx.self_wrister_shot_speed,
						ctx.defending_goal_pos.z, _field.opponents,
						_field.opponent_vels, _field.opponent_caps)
			var rank: float = _rim_launch_for(ctx, receiver_state, receiver_omega,
					receiver_caps, carrier_in_oz) \
					* _field.receiver_value_at(receiver_state.position)
			if rank > rim_rank:
				rim_rank = rank
				rim_peer = peer_id
				rim_k = _rim_k
				rim_t = _rim_t
				rim_lane = _rim_lane
				rim_miss = _rim_miss
		# Smart-ping PASS_TO_ME / IM_OPEN (see PING_PASS_EV_MULT).
		if peer_id == ctx.ping_pass_target_peer and s > 0.0:
			s *= PING_PASS_EV_MULT
		if s > best_pass_score:
			best_pass_score = s
			best_pass_peer = peer_id
			best_pass_saucer = use_saucer
			best_pass_frac = pass_frac
	if rim_peer != -1:
		var rim_state: SkaterNetworkState = snapshot.skater_states[rim_peer]
		var rim_caps: AISkaterCaps = ctx.caps_by_peer.get(rim_peer)
		var floor_ev: float = best_pass_score
		if rim_peer == ctx.ping_pass_target_peer:
			floor_ev /= PING_PASS_EV_MULT
		var rotation_time: float = _facing_rotation_time(self_facing_xz,
				ctx.self_pos, ctx.self_pos + AIRimPass.dirs[rim_k],
				ctx.self_reach_cone_half_angle, ctx.self_facing_turn_rate)
		var s_rim: float = _pass_ev(ctx, AIRimPass.meet_point(rim_k, rim_t),
				AIRimPass.paces[rim_k], rim_t,
				rim_t + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S,
				rim_t + rotation_time, our_goalie, rim_caps, rim_lane, rim_miss,
				rim_state.velocity, floor_ev,
				AIRimPass.dirs[rim_k], AIRimPass.opp_meet[rim_k])
		if rim_peer == ctx.ping_pass_target_peer and s_rim > 0.0:
			s_rim *= PING_PASS_EV_MULT
		if s_rim > best_pass_score:
			best_pass_score = s_rim
			best_pass_peer = rim_peer
			best_pass_saucer = false
			best_pass_frac = 1.0
			best_pass_rim_dir = AIRimPass.dirs[rim_k]
			best_pass_rim_pace = AIRimPass.paces[rim_k]
	best_peer = best_pass_peer
	best_score = best_pass_score
	best_is_saucer = best_pass_saucer
	best_rim_dir = best_pass_rim_dir
	best_rim_pace = best_pass_rim_pace
	best_pace_frac = best_pass_frac


# How surely and soon a RIM reaches `receiver_state` (completion × the delay
# discount, 0.0 when none does) — the softest launch within RIM_SOFT_SHARE of the
# surest — with that launch's path reads (meet time on the walked path, the race
# against the soonest opponent as the lane, the passer's aim error over the path
# length) left in _rim_k / _rim_t / _rim_lane / _rim_miss.
#
# A RANK, not a price: search weighs it by the receiver's cached spot
# value and pays the full _pass_ev only for the eval's single best rim. Launches
# that reach one receiver meet him within a stride of each other, so his value
# cannot reorder them.
#
# Zone rules follow the straight feed's: a carrier in the zone keeps the puck in
# it up to the meet, and one outside it does not rim the puck into it (the
# receiver would be offside).
func _rim_launch_for(ctx: RoleContext, receiver_state: SkaterNetworkState,
		receiver_omega: float, receiver_caps: AISkaterCaps,
		carrier_in_oz: bool) -> float:
	var catch_radius: float = receiver_caps.handle_reach if receiver_caps != null \
			else AIBotMechanics.EVADE_CARRY_HANDLE_M
	var receiver_speed: float = Vector2(
			receiver_state.velocity.x, receiver_state.velocity.z).length()
	if _rim_sure_by_k.size() != AIRimPass.MAX_LAUNCHES:
		_rim_sure_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_rim_t_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_rim_lane_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_rim_miss_by_k.resize(AIRimPass.MAX_LAUNCHES)
	var best_sure: float = 0.0
	for k: int in AIRimPass.count:
		_rim_sure_by_k[k] = -1.0
		var t: float = AIRimPass.meet_time(k, receiver_state.position,
				receiver_state.velocity, receiver_caps)
		if t == INF:
			continue
		if not AIRimPass.catchable(k, t, receiver_state.velocity):
			continue
		if carrier_in_oz:
			if not AIRimPass.stays_in_zone(k, t, ctx.attacking_goal_pos,
					AICarrierField.OZ_RECEIVE_LINE_BUFFER_M):
				continue
		elif AIActionScoring.in_offensive_zone(
				AIRimPass.meet_point(k, t), ctx.attacking_goal_pos):
			continue
		var miss_prob: float = AIPuckLane.pass_miss_prob(
				AIRimPass.path_length(k, t), ctx.self_pass_aim_error_rad,
				catch_radius, AIPuckLane.receiver_heading_uncertainty_m(
						receiver_speed, receiver_omega, t))
		var sure: float = (1.0 - miss_prob) * AIActionScoring.delay_discount(t)
		# Exact prune before the opponent race (the costly read): the lane is at
		# most 1, so a launch that cannot reach the soft band unraced cannot raced.
		if sure < best_sure * RIM_SOFT_SHARE:
			continue
		var lane: float = AIRimPass.race_completion(k, t)
		sure *= lane
		_rim_sure_by_k[k] = sure
		_rim_t_by_k[k] = t
		_rim_lane_by_k[k] = lane
		_rim_miss_by_k[k] = miss_prob
		best_sure = maxf(best_sure, sure)
	if best_sure <= 0.0:
		return 0.0
	# Fire it as soft as the race allows: among the launches nearly as sure as the
	# best, the softest — easier to stop, and a missed one dies sooner.
	var pick: int = -1
	for k: int in AIRimPass.count:
		var sure_k: float = _rim_sure_by_k[k]
		if sure_k < best_sure * RIM_SOFT_SHARE:
			continue
		if pick == -1 or AIRimPass.paces[k] < AIRimPass.paces[pick] \
				or (AIRimPass.paces[k] == AIRimPass.paces[pick] and sure_k > _rim_sure_by_k[pick]):
			pick = k
	_rim_k = pick
	_rim_t = _rim_t_by_k[pick]
	_rim_lane = _rim_lane_by_k[pick]
	_rim_miss = _rim_miss_by_k[pick]
	return _rim_sure_by_k[pick]


# EV of ONE pass variant (flat, or saucer at a possibly-reduced launch
# speed) to `receiver_state`. Solves the intercept lead at the variant's
# actual speed, applies the per-variant filters, then prices it through
# the shared _pass_ev. Returns 0.0 when the variant is filtered out:
#   - Lead past our own goal line (own-goal risk).
#   - Carrier in OZ → lead must sit AICarrierField.OZ_RECEIVE_LINE_BUFFER_M inside the line.
#   - Carrier outside with a delayed offside up → lead must stay outside.
#   - Saucer only: the lead must leave the flip landing runway (airborne carry
#     + SAUCER_LANDING_RUN_M — a closing receiver can shrink the solved lead
#     under what the current distance allowed), the flat lane must be contested
#     (SAUCER_SKIP_WHEN_LANE_CLEAR), and the loft must clear MORE of the lane
#     than staying flat.
#   - A softer pace (`soft`) whose flight outruns PASS_LEAD_MAX_S: its lead is
#     the horizon's, not the meet's, so it is not priced at all.
#
# A one-timer-ready receiver who can set for the feed takes it on his tape and
# fires on contact (no wrister windup), so the goalie only gets the pass flight
# to react; nor does he settle the catch. One who cannot set catches it.
func _pass_variant_ev(ctx: RoleContext, receiver_state: SkaterNetworkState,
		receiver_accel: Vector3, receiver_omega: float, receiver_caps: AISkaterCaps,
		pass_origin: Vector3, pass_speed: float, saucer: bool,
		receiver_is_one_timer: bool, self_facing_xz: Vector2,
		our_goalie: Vector3, carrier_in_oz: bool,
		useless_below: float = -INF, soft: bool = false) -> float:
	# Intercept-aware lead, shared with the state machine's firing aim; flight_t
	# is the SOLVED time. The receiver's real build bounds how far he is led. He
	# skates on through the windup, so the lead is solved from the release, where
	# the state machine aims it and pass_origin throws it.
	var lead: Array = AIPassLead.lead(
			pass_origin, receiver_state, receiver_accel, pass_speed,
			PASS_LEAD_MAX_S, receiver_caps, AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S)
	var receiver: Vector3 = lead[0]
	var flight_t: float = lead[1]
	# Fed on his tape only when he can set for it; otherwise he catches it.
	var one_timed: bool = receiver_is_one_timer and AIPassLead.one_timer_sets(
			receiver_state, receiver, flight_t, receiver_caps, ctx.attacking_goal_pos)
	if one_timed:
		receiver = AIPassLead.one_timer_tape(receiver, receiver_caps, ctx.attacking_goal_pos)
	if soft and flight_t >= PASS_LEAD_MAX_S - 0.0001:
		return 0.0
	if ctx.own_goal_dir * receiver.z > GameRules.GOAL_LINE_Z:
		return 0.0
	if carrier_in_oz and not AIActionScoring.in_offensive_zone(
			receiver, ctx.attacking_goal_pos, AICarrierField.OZ_RECEIVE_LINE_BUFFER_M):
		return 0.0
	# A delayed offside is up: a feed caught in the zone is a touch that whistles.
	if ctx.zone_entry_blocked and not carrier_in_oz \
			and AIActionScoring.in_offensive_zone(receiver, ctx.attacking_goal_pos):
		return 0.0
	var lane: float
	# Execution miss (AIPuckLane.pass_miss_prob): this bot's release error
	# projected over the pass distance vs the receiver's catch envelope.
	var catch_radius: float = receiver_caps.handle_reach if receiver_caps != null \
			else AIBotMechanics.EVADE_CARRY_HANDLE_M
	# Receiver-commitment term: a receiver mid-cut curves off the straight-line
	# lead. Zero for a settled receiver (or a commitment-blind tier, which
	# passes receiver_omega 0).
	var receiver_speed: float = sqrt(
			receiver_state.velocity.x * receiver_state.velocity.x
			+ receiver_state.velocity.z * receiver_state.velocity.z)
	var turn_uncertainty: float = AIPuckLane.receiver_heading_uncertainty_m(
			receiver_speed, receiver_omega, flight_t)
	var miss_prob: float = AIPuckLane.pass_miss_prob(
			pass_origin.distance_to(receiver), ctx.self_pass_aim_error_rad,
			catch_radius, turn_uncertainty)
	if saucer:
		# Small tolerance: a speed sitting exactly on the receivability
		# bound round-trips through the kinematics to the exact distance.
		if pass_origin.distance_to(receiver) \
				< AIPuckLane.saucer_airborne_distance_m(pass_speed) \
				+ AIPuckLane.SAUCER_LANDING_RUN_M - 0.01:
			return 0.0
		var lane_flat: float = AIPuckLane.lane_clear(
				pass_origin, receiver, _field.opponents_release, pass_speed,
				_field.opponent_vels, _field.opponent_caps, true,
				_field.opponent_blades_release)
		if lane_flat >= AIPuckLane.SAUCER_SKIP_WHEN_LANE_CLEAR:
			return 0.0
		lane = AIPuckLane.lane_clear_saucer(
				pass_origin, receiver, _field.opponents_release, pass_speed,
				_field.opponent_vels, _field.opponent_caps)
		if lane <= lane_flat:
			return 0.0
		miss_prob += AIPuckLane.SAUCER_EXTRA_MISS_PROB
	else:
		lane = AIPuckLane.lane_clear(
				pass_origin, receiver, _field.opponents_release, pass_speed,
				_field.opponent_vels, _field.opponent_caps, true,
				_field.opponent_blades_release)
		_last_flat_variant_lane = lane
	var receiver_release_t: float = flight_t
	var closing: float = 0.0
	if not one_timed:
		receiver_release_t += AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
		closing = AIFeedReception.arrival_closing_speed(
				pass_origin, receiver, pass_speed, receiver_state.velocity)
	var rotation_time: float = _facing_rotation_time(
			self_facing_xz, ctx.self_pos, receiver,
			ctx.self_reach_cone_half_angle, ctx.self_facing_turn_rate)
	return _pass_ev(ctx, receiver, pass_speed, flight_t,
			receiver_release_t, flight_t + rotation_time, our_goalie,
			receiver_caps, lane, miss_prob, receiver_state.velocity, useless_below,
			Vector3.ZERO, Vector3.INF, closing)


# Expected value of firing a pass from our current position to
# `receiver_spot`. Shared by the live pass scoring (search) and the
# developing-outlet hold (_developing_outlet_feed), so "the pass this wait is
# creating" and "the pass I can fire now" are priced identically — the hold
# self-terminates the instant the real pass matches it (fire wins ties).
#
# Benefit = P(complete) × the receiver's value at the spot, decayed by
# `delay_s` (flight + any facing rotation). Cost = the opponent's value at each
# loss mode's location (release poke, lane interception, execution miss,
# reception strip), so a low-upside backpass deep in our own end loses to
# skating: its miss mode surrenders the ice in front of our net.
#
# `lane` < 0 has the flat lane computed here; `miss_prob` is this variant's
# execution-miss probability. The goalie is predicted at `receiver_release_t`
# (flight + the receiver's wrister charge, or flight alone for a one-timer —
# the caller decides), so a cross-seam feed is scored against a keeper caught
# mid-slide. The receiver shoots at his own build's speed and loft when
# `receiver_caps` is given, the league default otherwise. A rim passes
# `rim_dir` and the point its path is lost at (`rim_loss_point`). `closing` is
# the feed's speed in the receiver's frame as it reaches him (0 for a one-timer
# or a rim: no reception to price). By its odds it is caught, and he settles
# (AIFeedReception.receiver_settle_s) with the puck on his stick for the defence to
# poke at, or it bobbles, and lies loose until he regathers it
# (AIFeedReception.bobble_regather_s) — his only if he wins that race.
func _pass_ev(ctx: RoleContext, receiver_spot: Vector3, pass_speed: float,
		flight_t: float, receiver_release_t: float, delay_s: float,
		our_goalie: Vector3, receiver_caps: AISkaterCaps = null,
		lane: float = -1.0,
		miss_prob: float = AIPuckLane.PASS_MISS_BASE_PROB,
		receiver_vel: Vector3 = Vector3.ZERO,
		useless_below: float = -INF,
		rim_dir: Vector3 = Vector3.ZERO,
		rim_loss_point: Vector3 = Vector3.INF,
		closing: float = 0.0) -> float:
	var self_pos: Vector3 = ctx.self_pos
	# The pass flies from the PUCK, not the body: behind the net the two differ
	# by up to a stick's reach. The lane and its loss points are the puck's;
	# self_pos stays the body reference for the release and recovery terms.
	var origin: Vector3 = AICarrierField.pass_origin(ctx)
	# Hard zeros: net-blocker (segment crosses a net body) and own-DZ
	# slot crossing (intercepted = goal-against). A rim's path is not this
	# segment — AIRimPass checked each of its legs instead.
	var is_rim: bool = rim_dir != Vector3.ZERO
	if not is_rim and AINetObstacle.pass_lane_blocked_by_net(origin, receiver_spot):
		return 0.0
	if not is_rim and AINetObstacle.pass_crosses_own_slot(
			origin, receiver_spot, ctx.own_goal_dir * GameRules.GOAL_LINE_Z):
		return 0.0
	if lane < 0.0:
		lane = AIPuckLane.lane_clear(
				origin, receiver_spot, _field.opponents_release, pass_speed,
				_field.opponent_vels, _field.opponent_caps, true,
				_field.opponent_blades_release)
	if lane <= 0.0:
		return 0.0
	# RELEASE CONTEST — the cough-up loss mode: a forechecker whose stick reaches
	# the release point inside the ~135 ms windup pokes the puck off the blade
	# before it flies (the same race as the shot's release_contest_clean). It is
	# what prices a defender on the carrier's HIP, off the lane line. Raced from
	# CURRENT opponent spots, since the windup starts now.
	var release_clean: float = AIPuckLane.release_contest_clean(
			AIPuckLane.release_point_toward(self_pos,
					self_pos + rim_dir if is_rim else receiver_spot),
			_field.opponents, _field.opponent_caps)
	_field.project_opponents(flight_t, _proj_buf, _proj_vels, receiver_spot)
	var settle_s: float = AIFeedReception.receiver_settle_s(closing)
	var p_bobble: float = AIFeedReception.receiver_bobble_prob(closing)
	var catch_s: float = delay_s + settle_s
	# What the receiver does at the catch: his shot off this feed, the keeper
	# square on the passer as it leaves (the goalie's own answer to the flight,
	# AIShotValue.feed; a one-timer-ready receiver's release is the flight alone,
	# _pass_variant_ev), or the short drive toward the net an open receiver can
	# carry into. (The drive re-projects _proj_buf, which the shot has consumed.)
	var drive_in: float = _field.receiver_drive_in_value(ctx, receiver_spot, receiver_caps,
			receiver_vel, Vector3.INF, flight_t)
	var at_catch: float = maxf(_field.feed_shot_at(ctx, origin, receiver_spot, pass_speed,
			receiver_release_t <= flight_t, self_pos, _proj_buf), drive_in)
	# His possession is read when the carry's first step is (_possession_on_clock),
	# so a pass and a carry are told apart by where each leaves the puck then.
	var on_catch: float = maxf(at_catch * AIActionScoring.delay_discount(catch_s),
			_possession_on_clock(receiver_spot, receiver_vel, receiver_caps, delay_s, catch_s))
	# Reception pressure on a catch: the reachable-set clearance at the reception
	# spot when the puck arrives — defenders momentum-projected from their
	# RELEASE-TIME spots over the flight, sticks maneuvering over the short
	# reception window and his settle. It prices a defender draped on the
	# receiver's back, who is off both the lane and the receiver's forward shot cone.
	var catch_safety: float = AICarrySpace.clearance_to_safety(
			AICarrySpace.reach_clearance(receiver_spot, flight_t + settle_s,
					_field.opponents_release, _field.opponent_vels,
					_field.opponent_caps, AICarrySpace.EVADE_HORIZON_S + settle_s))
	# A bobble is a loose puck he must win back: the race to the spot, him at his
	# regather against their first body there from the release, and his drive or
	# his possession from there once he has it.
	var bobble_won: float = 0.0
	var on_bobble: float = 0.0
	if p_bobble > 0.0:
		var regather_s: float = AIFeedReception.bobble_regather_s(closing)
		bobble_won = AIActionScoring.arrival_race(receiver_spot, flight_t + regather_s,
				_field.opponents_release, _field.opponent_vels, false, _field.opponent_caps)
		on_bobble = maxf(drive_in * AIActionScoring.delay_discount(delay_s + regather_s),
				_possession_on_clock(receiver_spot, Vector3.ZERO, receiver_caps,
						delay_s + regather_s, delay_s + regather_s))
	var reception_kept: float = (1.0 - p_bobble) * catch_safety + p_bobble * bobble_won
	# Four completion loss modes, mutually exclusive and summing to 1 with the
	# retained case: poked at the release (1 − release_clean), lane interception
	# (release_clean × (1 − lane)), execution miss (release_clean × lane × miss),
	# and lost on reception (clean lane, no miss, but a stick on the catch or a
	# lost race to the bobble).
	var clean_lane: float = lane * (1.0 - miss_prob)   # reaches the tape, in flight
	var benefit: float = release_clean * clean_lane * (
			(1.0 - p_bobble) * catch_safety * on_catch + p_bobble * bobble_won * on_bobble)
	# CEILING PRUNE (exact): every turnover cost below can only LOWER this EV,
	# so the benefit is a hard upper bound.
	if benefit <= useless_below:
		return 0.0
	# No separate "escape" bonus for a pressured carrier: the pressure is
	# already priced by the carry/hold alternatives' own strip cost.
	# Poked at the release: the puck squirts loose at the blade.
	var cost: float = _field.turnover_cost(origin,
			1.0 - release_clean)
	# A rim is lost where the soonest opponent meets its path.
	var loss_point: Vector3 = rim_loss_point if is_rim and rim_loss_point.is_finite() \
			else AIPuckLane.lane_loss_point(
					origin, receiver_spot, _field.opponents_release, pass_speed,
					_field.opponent_vels, _field.opponent_caps,
					_field.opponent_blades_release)
	var loss_s: float = minf(AIPuckLane.traverse_time(origin.distance_to(loss_point), pass_speed),
			flight_t) if loss_point.is_finite() else flight_t
	cost += _field.turnover_cost(loss_point,
			release_clean * (1.0 - lane), loss_s)
	cost += _field.turnover_cost(AIPuckLane.pass_miss_loss_point(origin, receiver_spot),
			release_clean * lane * miss_prob, flight_t)
	# Lost on reception: the puck dies AT the receiver, in whatever traffic he was
	# about to catch it in.
	cost += _field.turnover_cost(receiver_spot,
			release_clean * clean_lane * (1.0 - reception_kept), flight_t + settle_s)
	# Transition exposure (5v5): each loss mode also prices the COUNTER-RUSH
	# it hands over — the carrier stays at self_pos through a pass, so his
	# own recovery race starts from here (plan §6).
	cost += _field.counter_exposure_cost(ctx, loss_point, 1.0 - lane,
			self_pos, our_goalie)
	cost += _field.counter_exposure_cost(ctx, receiver_spot,
			clean_lane * (1.0 - reception_kept), self_pos, our_goalie)
	return benefit - cost


# The receiver's possession, discounted to now, read when the carry's first step
# is (AICarryRollout.HORIZON_S) or when he has the puck, whichever is later: he
# has it at `has_s`, standing at `spot` `at_spot_s` from now and skating on at
# `vel` from there.
func _possession_on_clock(spot: Vector3, vel: Vector3, caps: AISkaterCaps,
		at_spot_s: float, has_s: float) -> float:
	var t: float = maxf(AICarryRollout.HORIZON_S, has_s)
	var there: Vector3 = spot + Vector3(vel.x, 0.0, vel.z) * (t - at_spot_s)
	if not AIStationSearch.is_legal_position(there):
		there = spot
	return _field.horizon_value(there, t, vel, caps) * AIActionScoring.delay_discount(t)


# Seconds the bot needs to rotate its facing before the blade can fire at
# `target`. The blade reaches anywhere inside the reach cone (`cone_half_angle`
# = ROM + torso twist, the IK gate the pose coordinator enforces), so an in-cone
# target costs 0; past the cone only the OVERSHOOT pays, at this bot's real
# turn rate.
func _facing_rotation_time(self_facing_xz: Vector2, self_pos: Vector3,
		target: Vector3, cone_half_angle: float, turn_rate: float) -> float:
	var to_target_x: float = target.x - self_pos.x
	var to_target_z: float = target.z - self_pos.z
	var to_target_len: float = sqrt(
			to_target_x * to_target_x + to_target_z * to_target_z)
	if to_target_len <= 0.001:
		return 0.0
	var inv_len: float = 1.0 / to_target_len
	var cos_angle: float = clampf(
			self_facing_xz.x * to_target_x * inv_len
			+ self_facing_xz.y * to_target_z * inv_len, -1.0, 1.0)
	var angular_distance: float = acos(cos_angle)
	var overshoot: float = maxf(0.0, angular_distance - cone_half_angle)
	return overshoot / maxf(turn_rate, 0.001)


# Value (EV) of the best DEVELOPING feed — a play a teammate is still
# creating, worth keeping the puck for. 0 if nothing is developing, and always
# 0 for a tier with ctx.holds_for_developing_feeds false (a cognition gate: it
# plays only what exists right now). Two kinds, both self-gating:
#
#   - FINISHER (or the 5v5 NET_FRONT, who runs the finisher's role), not yet
#     one-timer-ready: the feed to the spot he is DRIVING TO
#     (projected OUTLET_DEVELOP_WINDOW_S along his velocity, inside the zone by
#     the reception band), priced on the seam (score_pass_value) with the keeper
#     given the flight plus the finisher's wrister charge to re-square. So a
#     fresh zone entry holds for the mates still arriving instead of settling
#     for the weak from-the-top shot.
#
#   - Breakout OUTLET (BREAKOUT_STRONG / OUTLET / BREAKOUT_D2): an outlet
#     skating its route toward open ice — see _developing_outlet_feed. This is
#     why a pressured own-zone carrier protects the puck and skates instead of
#     forcing a low-value backpass.
func developing_feed_value(ctx: RoleContext) -> float:
	if not ctx.holds_for_developing_feeds:
		return 0.0
	if ctx.team_brain == null:
		return 0.0
	var self_pos: Vector3 = ctx.self_pos
	var our_goalie: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var self_state: SkaterNetworkState = ctx.snapshot.skater_states.get(ctx.peer_id)
	var self_facing: Vector2 = self_state.facing if self_state != null else Vector2.ZERO
	var best: float = 0.0
	for pid: int in _field.teammate_ids:
		var slot: int = ctx.team_brain.get_slot(pid)
		var tm: SkaterNetworkState = ctx.snapshot.skater_states.get(pid)
		# The live pass scoring skips a mate who can't legally play the puck, so
		# holding for one would wait forever.
		if tm == null or ctx.snapshot.is_out_of_play(pid):
			continue
		var feed: float = 0.0
		if slot == AIRoleSlots.Slot.FINISHER or slot == AIRoleSlots.Slot.NET_FRONT:
			# A one-timer-flagged finisher is already fed by the normal pass
			# scoring. The OZ gate reads the PROJECTED spot — a finisher a stride
			# outside the line, driving in, is the developing cross-seam — and
			# uses the live pass filter's reception band, since holding for a
			# spot the pass scoring may never hit would wait forever.
			var fin_vel: Vector3 = tm.velocity
			var spot := Vector3(
					tm.position.x + fin_vel.x * OUTLET_DEVELOP_WINDOW_S, 0.0,
					tm.position.z + fin_vel.z * OUTLET_DEVELOP_WINDOW_S)
			if ctx.team_brain.is_one_timer_ready(pid) \
					or not AIActionScoring.in_offensive_zone(
							spot, ctx.attacking_goal_pos, AICarrierField.OZ_RECEIVE_LINE_BUFFER_M) \
					or not AIStationSearch.is_legal_position(spot):
				continue
			var dist: float = self_pos.distance_to(spot)
			var pass_speed: float = AIPuckLane.pass_launch_speed(
					dist, ctx.self_wrister_shot_speed, ctx.pass_speed_scale)
			var flight_t: float = clampf(dist / pass_speed, 0.0, PASS_LEAD_MAX_S)
			_field.project_opponents(flight_t, _proj_buf, _proj_vels, spot)
			# On the seam, because this value is compared directly against
			# fire_score (see score_pass_value).
			feed = AIActionScoring.score_pass_value(
					self_pos, spot, ctx.attacking_goal_pos, AICarrierField.goalie_now(ctx),
					_proj_buf, pass_speed, _field.opponent_caps)
		elif slot == AIRoleSlots.Slot.BREAKOUT_STRONG \
				or slot == AIRoleSlots.Slot.OUTLET \
				or slot == AIRoleSlots.Slot.BREAKOUT_D2:
			# BREAKOUT_D2 (5v5): the D-to-D behind the net that reverses the flow
			# when F1 overcommits strong-side — worth a beat's hold while the
			# partner is still SKATING to it (unlike BREAKOUT_WEAK, see
			# _developing_outlet_feed). The min-speed gate means a partner
			# already parked there never reads as developing.
			feed = _developing_outlet_feed(ctx, tm, our_goalie, self_facing, ctx.caps_by_peer.get(pid))
		if feed > best:
			best = feed
	return best


# EV of the breakout feed a skating outlet is CREATING: the pass to his spot
# projected OUTLET_DEVELOP_WINDOW_S along his velocity, priced through the SAME
# _pass_ev as the live pass scoring. That parity is the termination guarantee:
# as the outlet arrives the live pass converges to this value and fire wins
# the tie (and _hold_elapsed_s decays a wait that never materialises).
#
# BREAKOUT_WEAK is deliberately excluded: the weak-side valve stays goal-side
# of the carrier by role contract, so waiting for it would mean holding for a
# backpass — the play this hold exists to avoid forcing.
func _developing_outlet_feed(ctx: RoleContext, tm: SkaterNetworkState,
		our_goalie: Vector3, self_facing_xz: Vector2,
		receiver_caps: AISkaterCaps = null) -> float:
	var vel: Vector3 = tm.velocity
	if vel.x * vel.x + vel.z * vel.z \
			< OUTLET_DEVELOP_MIN_SPEED_M_S * OUTLET_DEVELOP_MIN_SPEED_M_S:
		return 0.0
	var spot := Vector3(
			tm.position.x + vel.x * OUTLET_DEVELOP_WINDOW_S, 0.0,
			tm.position.z + vel.z * OUTLET_DEVELOP_WINDOW_S)
	if not AIStationSearch.is_legal_position(spot):
		return 0.0
	var dist: float = ctx.self_pos.distance_to(spot)
	var rotation_time: float = _facing_rotation_time(self_facing_xz, ctx.self_pos, spot,
			ctx.self_reach_cone_half_angle, ctx.self_facing_turn_rate)
	# At each pace, as the live pass scoring prices it (and with the same horizon
	# rule for a softer one), so the two still converge.
	var best: float = 0.0
	for frac: float in AIPuckLane.PASS_PACE_FRACS:
		var pass_speed: float = AIPuckLane.pass_launch_speed(
				dist, ctx.self_wrister_shot_speed, ctx.pass_speed_scale * frac)
		var flight_t: float = dist / pass_speed
		if frac < 1.0 and flight_t >= PASS_LEAD_MAX_S:
			continue
		flight_t = minf(flight_t, PASS_LEAD_MAX_S)
		# Breakout receivers carry on reception (no one-timer): flight + wrister
		# charge and the hold, as the live pass scoring bills a non-ready one.
		var release_t: float = flight_t + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S
		best = maxf(best, _pass_ev(ctx, spot, pass_speed, flight_t, release_t,
				flight_t + rotation_time, our_goalie, receiver_caps, -1.0,
				AIPuckLane.PASS_MISS_BASE_PROB, Vector3.ZERO, best,
				Vector3.ZERO, Vector3.INF,
				AIFeedReception.arrival_closing_speed(ctx.self_pos, spot, pass_speed, vel)))
	return best

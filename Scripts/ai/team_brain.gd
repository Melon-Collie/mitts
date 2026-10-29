class_name TeamBrain
extends TeamStrategyView

# Per-team strategy node, host only. Ticked by AICoordinator's worker at the head
# of each AI batch (tick → build_view → agent decide); computes once every
# TICK_PERIOD seconds (~6 Hz) unless force_retick() is pending.
#
# Blackboard:
#   state                    — AIPossessionState.State.
#   slot_assignments         — peer_id → AIRoleSlots.Slot.
#   threat_assignments       — defender peer → the opponent it covers.
#   threat_shoot_base_by_opp — opp peer → shoot-threat base for MARK's fallback.
#   rush_read                — the shared transition-defence read.
#   coverage_downgraded      — instrumentation only.
#   one-timer readiness and the live ping directives, through the query methods.
# build_view freezes the agents' reads into a TeamBrainView; AICoordinator
# mirrors `state` and `coverage_downgraded` for the main thread.
#
# `team_id_by_peer` is a live reference owned by PlayerRegistry, mutated when
# players spawn / leave / slot-swap, so it is read via `dict.get(pid, -1)`. Keep
# it a Dictionary and never a Callable — AI hot loops eat Callable.call
# overhead.

const TICK_PERIOD: float = 1.0 / 6.0
# Hysteresis band on the strong side: once +1 is picked, flip to -1 only when
# puck.x crosses below -STRONG_SIDE_HYSTERESIS_M, and vice versa, so a puck
# cycling through centre does not flip every strong/weak-sided role's geometry.
const STRONG_SIDE_HYSTERESIS_M: float = 1.5

var team_id: int = 0
# Latched match team size (3 or 5). Selects the role-slot path: 3 → AIRoleSlots,
# 5 → AIRoleSlots5's position-aware group-scoped election.
var team_size: int = GameRules.DEFAULT_TEAM_SIZE
# Latched match ruleset — the shared read needs it for the offside-aware attacker
# filter (an illegally-positioned opponent is not a counter threat).
var rule_set: int = GameRules.DEFAULT_RULE_SET
var state: int = AIPossessionState.State.DZONE
# Host-only AI bookkeeping, never replicated. Slot/threat overrides land in
# _compute_tick; the per-bot queries are read through RoleContext every dispatch.
var ping_directives := AIPingDirectives.new()
var slot_assignments: Dictionary[int, int] = {}      # peer_id -> AIRoleSlots.Slot
# Man-on-threat partition over every body whose job is a man (MARK and the 5v5
# zone roles), so each covers a DISTINCT opponent instead of all collapsing on
# the most dangerous one. Empty outside DZONE / TRANS_DEFENSE.
var threat_assignments: Dictionary[int, int] = {}    # defender peer -> opp peer
# opp peer_id → his threat with the puck (AIPossessionValue.threat_of_carrier)
# against our net, goalie and full team, computed once per brain tick so MARK's
# unassigned fallback does not pay it per marker per re-eval. APPROXIMATE: full-team defender set (the
# exact read excludes the marker himself), raw unled positions, up to a brain
# tick stale — usable only as ordering / pruning bounds, never for an
# assigned-man cover. Empty whenever no MARK slot is live, so consumers fall back
# to the exact local computation.
var threat_shoot_base_by_opp: Dictionary[int, float] = {}
# Scratch defender list + index-matched velocities and caps for the memo fill,
# and the possession read over them.
var _memo_defenders: Array[Vector3] = []
var _memo_defender_vels: Array[Vector3] = []
var _memo_defender_caps: Array[AISkaterCaps] = []
var _memo_possession := AIPossessionValue.new()
# The opposing attack's possession read with no defenders, for the partition's
# man values (see _compute_threat_assignments).
var _open_possession := AIPossessionValue.new()
var _no_skaters: Array[Vector3] = []

# The team's shared transition-defense read (docs/transition-defense-plan.md
# §4), computed once per brain tick so no defender runs a private last-man race.
# Refilled in place, never reallocated.
var rush_read := AIRushRead.new()
# Last tick's recovery classification, threaded back in for the enter/hold
# hysteresis on the recovery race (see AIRushRead.TRACK_ENTER_MARGIN_S).
var _prev_recovery: Dictionary[int, int] = {}

# Sticky possession for loose-puck handling.
var _last_carrier_team: int = -1
var _strong_x: float = 1.0

var _accumulator: float = 0.0

# ── Coverage readiness state (docs/transition-defense-plan.md §9) ────────────
# Whether the team is currently running D-zone COVERAGE rather than the rush /
# recovery shape, and how many consecutive ticks the readiness read has disagreed
# with that posture (the leave-coverage hysteresis).
var _coverage_was_set: bool = false
var _coverage_unready_ticks: int = 0
# Instrumentation only (AIPossessionShapeTally): true while the raw read said
# DZONE but the brain held the rush shape because the backcheck wasn't home.
# Nothing reads it back into a decision.
var coverage_downgraded: bool = false
# Their puck in their zone: whether we are forechecking it (AIForecheckRead) —
# last tick's answer, for the read's hysteresis — and the race margin it read.
var _forechecking: bool = false
var forecheck_margin_s: float = -INF
# Team 1's natural ticks run half a period out of phase with team 0's (see
# Scripts/ai/CLAUDE.md → "Two brains, two cadences"). Re-applied at every
# forced-tick accumulator reset, since both brains are force-reticked together.
var _cadence_offset_s: float = 0.0
var _force_tick_pending: bool = false
# Peers that must NOT receive a slot: tutorial bots puppeted in scripted mode,
# which a role behavior would otherwise steer.
var _excluded_peers: Dictionary = {}
var _team_id_by_peer: Dictionary = {}
# Live per-peer AISkaterCaps from PlayerRegistry. Empty when unwired (tests) →
# league default.
var _caps_by_peer: Dictionary = {}
# Live peer_id → lobby team_slot (0–4) from PlayerRegistry. Read only by
# AIRoleSlots5 (F/D group split, home-side rest bias); empty in 3v3 / tests.
var _position_by_peer: Dictionary = {}
# Live set of BOT peers from PlayerRegistry. A human is not a body the bots can
# wait on for coverage readiness (see AIRushRead._coverage_ready). Empty when
# unwired (tests) → every teammate counts, which is the stricter reading.
var _bot_peers: Dictionary = {}
# Team 0 defends +GOAL_LINE_Z, team 1 -GOAL_LINE_Z.
var _own_goal_z: float = 0.0


func _init(t: int, team_id_by_peer: Dictionary, caps_by_peer: Dictionary = {},
		p_team_size: int = GameRules.DEFAULT_TEAM_SIZE,
		position_by_peer: Dictionary = {},
		bot_peers: Dictionary = {}) -> void:
	team_id = t
	_team_id_by_peer = team_id_by_peer
	_caps_by_peer = caps_by_peer
	team_size = p_team_size
	_position_by_peer = position_by_peer
	_bot_peers = bot_peers
	_own_goal_z = GameRules.GOAL_LINE_Z if t == 0 else -GameRules.GOAL_LINE_Z
	_cadence_offset_s = TICK_PERIOD * 0.5 if t == 1 else 0.0
	_accumulator = _cadence_offset_s


# Called every AI batch with the freshest captured world state (delay 0).
# Rate-limited to TICK_PERIOD unless force_retick() is pending.
func tick(delta: float, snapshot: WorldSnapshot) -> void:
	# Ping directives age in real host time, not brain-tick time — advance
	# before the rate-limit gate so expiry never stretches with the cadence.
	ping_directives.advance(delta)
	_accumulator += delta
	if _accumulator < TICK_PERIOD and not _force_tick_pending:
		return
	# A forced tick resets to this brain's cadence phase rather than draining,
	# so the next natural tick is never a back-to-back double-rate burst and the
	# two teams come out of a shared force-retick de-phased.
	if _force_tick_pending:
		_accumulator = _cadence_offset_s
		_force_tick_pending = false
	else:
		_accumulator -= TICK_PERIOD
	_compute_tick(snapshot)


# Makes the next tick() compute regardless of the rate limit, for an event (a
# puck-carrier change, a ping) that makes the assignment stale now rather than
# up to ~166 ms from now. A carrier change affects both teams' possession state,
# so both brains are force-reticked together.
func force_retick() -> void:
	_force_tick_pending = true


func exclude_skater(peer_id: int) -> void:
	_excluded_peers[peer_id] = true
	slot_assignments.erase(peer_id)


func include_skater(peer_id: int) -> void:
	_excluded_peers.erase(peer_id)


func _compute_tick(snapshot: WorldSnapshot) -> void:
	var possession: AIPossessionState.Result = AIPossessionState.compute(
			snapshot, team_id, _own_goal_z, _team_id_by_peer, _last_carrier_team)
	_last_carrier_team = possession.carrier_team
	state = possession.state

	# The shared transition read, before the slot elections so everything
	# downstream reads ONE answer instead of each bot deriving its own.
	_prev_recovery.clear()
	for pid: int in rush_read.recovery_by_peer:
		_prev_recovery[pid] = rush_read.recovery_by_peer[pid]
	rush_read.fill(snapshot, team_id, _own_goal_z, _team_id_by_peer,
			_caps_by_peer, _prev_recovery, rule_set != GameRules.RuleSet.OFF,
			_bot_peers, _last_carrier_team)

	# Coverage readiness: hold the rush/recovery shape until the backcheck is
	# home (Scripts/domain/ai/CLAUDE.md → "DZONE is a shape, not a location").
	# Only while an OPPONENT actually carries: a loose or dead puck in our zone is
	# not a rush being defended, and holding the rush shape over it would stop the
	# team setting up around a puck nobody has.
	if state == AIPossessionState.State.DZONE \
			and rush_read.carrier_peer != -1:
		if rush_read.coverage_ready:
			_coverage_unready_ticks = 0
		else:
			_coverage_unready_ticks += 1
		var set_now: bool = AIPossessionState.coverage_read(
				rush_read.coverage_ready, _coverage_unready_ticks,
				_coverage_was_set)
		_coverage_was_set = set_now
		coverage_downgraded = not set_now
		if not set_now:
			state = AIPossessionState.State.TRANS_DEFENSE
	else:
		# Left the zone (or we got it back): the next entry starts fresh, so a
		# stale "we were set" can't wave a new rush straight into coverage.
		_coverage_was_set = false
		_coverage_unready_ticks = 0
		coverage_downgraded = false

	# Their puck deep in their zone, carried or loose and slow: forecheck it only
	# while our first forechecker can get on it before it is out, else set up in
	# the neutral zone (Scripts/domain/ai/CLAUDE.md → "Forecheck or set up").
	if state == AIPossessionState.State.FORECHECK \
			or (state == AIPossessionState.State.NEUTRAL
					and AIPossessionState.in_their_zone(snapshot, _own_goal_z)):
		forecheck_margin_s = AIForecheckRead.pressure_margin_s(snapshot, team_id,
				_own_goal_z, _team_id_by_peer, _caps_by_peer, _position_by_peer,
				team_size >= 5)
		_forechecking = AIForecheckRead.can_forecheck(forecheck_margin_s, _forechecking)
		state = AIPossessionState.State.FORECHECK if _forechecking \
				else AIPossessionState.State.TRANS_DEFENSE
	else:
		_forechecking = false
		forecheck_margin_s = -INF

	# Strong-side X with hysteresis (see STRONG_SIDE_HYSTERESIS_M).
	if snapshot != null and snapshot.puck_state != null:
		var puck_x: float = snapshot.puck_state.position.x
		if _strong_x > 0.0 and puck_x < -STRONG_SIDE_HYSTERESIS_M:
			_strong_x = -1.0
		elif _strong_x < 0.0 and puck_x > STRONG_SIDE_HYSTERESIS_M:
			_strong_x = 1.0

	var prev_assignments: Dictionary = slot_assignments
	if team_size >= 5:
		slot_assignments = AIRoleSlots5.assign(
				snapshot, team_id, _own_goal_z, state, _team_id_by_peer,
				prev_assignments, _strong_x, _caps_by_peer, _position_by_peer)
	else:
		slot_assignments = AIRoleSlots.assign(
				snapshot, team_id, _own_goal_z, state, _team_id_by_peer,
				prev_assignments, _strong_x, _caps_by_peer)
	# Drop excluded peers (puppeted tutorial bots) so neither they nor any
	# downstream consumer of get_slot steers them — assign() may already have
	# given them a slot.
	for excluded_pid: int in _excluded_peers:
		slot_assignments.erase(excluded_pid)

	# Excluded peers are already absent from slot_assignments, so they are never
	# picked as defenders here.
	threat_assignments = _compute_threat_assignments(snapshot, threat_assignments)

	_refresh_threat_base_memo(snapshot)

	# Smart-ping obedience: force-slot the obeying bots (COVER_HIM also pins its
	# man into the threat partition, the house-pin shape). Applied last so a live
	# human order wins over the geometric assignment.
	var ping_carrier: int = -1
	if snapshot != null and snapshot.puck_state != null:
		ping_carrier = snapshot.puck_state.carrier_peer_id
	ping_directives.apply_overrides(slot_assignments, threat_assignments, ping_carrier)


# The man-on-threat partition for the current tick. DZONE and TRANS_DEFENSE
# only; every other state returns {} so no defender carries a stale assignment.
#
# The men are every opponent who is not already owned: while an opponent
# CARRIES he is the puck-owner's, so he is excluded and the men are his potential
# receivers; with the puck loose every opponent is a man, the ex-carrier
# included. Each man's value is the raw pass-threat surface from the feed source
# (no defenders in the view). `prev` is last tick's partition, threaded through
# for switch hysteresis — which is also what carries a marker across a pass
# without re-shuffling the whole coverage.
func _compute_threat_assignments(snapshot: WorldSnapshot,
		prev: Dictionary) -> Dictionary[int, int]:
	var empty: Dictionary[int, int] = {}
	if state != AIPossessionState.State.DZONE \
			and state != AIPossessionState.State.TRANS_DEFENSE:
		return empty
	if snapshot == null or snapshot.puck_state == null:
		return empty
	var carrier_pid: int = snapshot.puck_state.carrier_peer_id
	# We have it — this is not a coverage problem.
	if carrier_pid != -1 and _team_id_by_peer.get(carrier_pid, -1) == team_id:
		return empty
	# The feed source: the opponent carrier, else the puck — the same resolution
	# as AIRoleReads.resolve_defensive_play_ref, so brain and marker read one
	# play. Do not require a live carrier: that dissolves the whole coverage for
	# the flight of every pass, shot, rebound and dump.
	var play_ref: Vector3 = snapshot.puck_state.position
	if carrier_pid != -1 and snapshot.skater_states.has(carrier_pid):
		play_ref = snapshot.skater_states[carrier_pid].position

	# The defenders are every body whose job is a man: MARK and, in 5v5 D-zone
	# coverage, the four zone roles not on the puck. A zone role's area enters as
	# ELIGIBILITY (Scripts/domain/ai/CLAUDE.md → "Covering a man is one behavior").
	var pressure_slot: int = AIZoneCoverage.pressure_owner(
			_strong_x, _own_goal_z, snapshot.puck_state.position)
	var defenders: Array[int] = []
	var defender_pos: Dictionary = {}
	var defender_vel: Dictionary = {}
	var defender_caps: Dictionary = {}
	var eligible_men: Dictionary = {}
	var zone_slot_by_def: Dictionary = {}
	for pid: int in slot_assignments:
		var slot: int = slot_assignments[pid]
		var is_zone: bool = AIRoleSlots5.is_zone_slot(slot)
		if slot != AIRoleSlots.Slot.MARK and not is_zone:
			continue
		# The area that owns the puck is pressuring it, not covering a man.
		if is_zone and slot == pressure_slot:
			continue
		if not snapshot.skater_states.has(pid):
			continue
		if is_zone:
			zone_slot_by_def[pid] = slot
		var s: SkaterNetworkState = snapshot.skater_states[pid]
		defenders.append(pid)
		defender_pos[pid] = s.position
		defender_vel[pid] = s.velocity
		var caps: AISkaterCaps = _caps_by_peer.get(pid)
		if caps != null:
			defender_caps[pid] = caps
	if defenders.is_empty():
		return empty

	# Men = every opponent the puck-owner does not already own (see the header).
	var our_net := Vector3(0.0, 0.0, _own_goal_z)
	var our_goalie_pos: Vector3 = _resolve_our_goalie_pos(snapshot)
	_open_possession.fill(our_net, _no_skaters, _no_skaters, [])
	var men: Array[int] = []
	var man_pos: Dictionary = {}
	var man_value: Dictionary = {}
	var man_danger: Dictionary = {}
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == team_id:
			continue
		if pid == carrier_pid:
			continue
		var mp: Vector3 = snapshot.skater_states[pid].position
		men.append(pid)
		man_pos[pid] = mp
		# Area eligibility, built as the men are collected. The incumbent gets a
		# release margin so a man skating a seam is held a metre past the edge
		# rather than flickering between two defenders; the matcher's own switch
		# margin covers the rest. The puck owner's area is everyone's while he is
		# on the puck, or a man in it is in nobody's.
		var in_pressure_area: bool = AIZoneCoverage.in_area(pressure_slot, _strong_x,
				_own_goal_z, mp)
		for def_pid: int in zone_slot_by_def:
			var margin: float = AIZoneCoverage.AREA_RELEASE_MARGIN_M \
					if prev.get(def_pid, -1) == pid else 0.0
			if in_pressure_area or AIZoneCoverage.in_area(zone_slot_by_def[def_pid],
					_strong_x, _own_goal_z, mp, margin):
				if not eligible_men.has(def_pid):
					eligible_men[def_pid] = {}
				(eligible_men[def_pid] as Dictionary)[pid] = true
		man_value[pid] = _open_possession.threat_of_feed(play_ref, mp,
				snapshot.skater_states[pid].velocity, our_goalie_pos)
		# Finish danger if fed: his one-timer off the feed, our keeper square on
		# the play as he stands (AIShotValue.feed). Unlike man_value it carries no
		# lane factor: a contested feed still becomes a tap-in if it arrives. And
		# no defenders: coverage is this scan's output, and feeding the markers
		# back in would free a covered man's marker, raise his danger, and pull
		# the marker back.
		man_danger[pid] = AIShotValue.feed(play_ref, mp,
				AIPuckLane.expected_pass_speed(play_ref, mp), our_net, our_goalie_pos, true)
	if men.is_empty():
		return empty

	# A zone defender with nobody in his ice carries an EMPTY eligibility set,
	# which assign() would read as "no restriction". Give him a sentinel the
	# men can never match so he stays idle and his rest anchor takes over.
	for def_pid: int in zone_slot_by_def:
		if not eligible_men.has(def_pid):
			eligible_men[def_pid] = {-1: true}

	return AIThreatAssignment.assign(
			defenders, defender_pos, defender_vel,
			men, man_pos, man_value, our_net, prev, defender_caps, man_danger,
			eligible_men)


func _refresh_threat_base_memo(snapshot: WorldSnapshot) -> void:
	threat_shoot_base_by_opp.clear()
	if snapshot == null:
		return
	var have_mark: bool = false
	for pid: int in slot_assignments:
		if slot_assignments[pid] == AIRoleSlots.Slot.MARK:
			have_mark = true
			break
	if not have_mark:
		return
	var our_net := Vector3(0.0, 0.0, _own_goal_z)
	var our_goalie_pos: Vector3 = _resolve_our_goalie_pos(snapshot)
	_memo_defenders.clear()
	_memo_defender_vels.clear()
	_memo_defender_caps.clear()
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == team_id:
			_memo_defenders.append(snapshot.skater_states[pid].position)
			_memo_defender_vels.append(snapshot.skater_states[pid].velocity)
			_memo_defender_caps.append(_caps_by_peer.get(pid))
	_memo_possession.fill(our_net, _memo_defenders, _memo_defender_vels,
			_memo_defender_caps)
	for pid: int in snapshot.skater_states:
		if _team_id_by_peer.get(pid, -1) == team_id:
			continue
		var s: SkaterNetworkState = snapshot.skater_states[pid]
		threat_shoot_base_by_opp[pid] = _memo_possession.threat_of_carrier(s.position,
				s.velocity, our_goalie_pos)


# Our goalie's current world position, or the goal mouth as a first-frame
# fallback. The brain has no RoleContext, so it cannot call
# AIRoleReads.resolve_our_goalie_pos.
func _resolve_our_goalie_pos(snapshot: WorldSnapshot) -> Vector3:
	var goalie: GoalieNetworkState = snapshot.goalie_states.get(team_id)
	if goalie == null:
		return Vector3(0.0, 0.0, _own_goal_z)
	return Vector3(goalie.position_x, 0.0, goalie.position_z)


# NONE when the peer isn't on this team or the brain hasn't ticked yet.
func get_slot(peer_id: int) -> int:
	return slot_assignments.get(peer_id, AIRoleSlots.Slot.NONE)


# -1 when the peer has no man-coverage assignment this tick.
func assigned_threat(peer_id: int) -> int:
	return threat_assignments.get(peer_id, -1)


# Hysteretic strong-side sign (+1 = +X, -1 = -X). Roles read this rather than
# sign(puck.x) so their strong/weak split matches the slot assignment.
func strong_x() -> float:
	return _strong_x


# This peer's lobby position (team_slot 0–4; see PlayerRules.POSITION_NAMES).
# 0 (C) when unknown — tests / 3v3, where nothing reads it.
func position_of(peer_id: int) -> int:
	return _position_by_peer.get(peer_id, 0)


# ── One-timer readiness signaling ───────────────────────────────────────────
# Off-puck bots publish "I'm camped + pre-aimed, fire me a pass and I'll
# one-time it". The carrier reads it when scoring passes: a ready receiver gets
# a no-charge goalie prediction, since a shot fired on contact gives the goalie
# no wind-up to react to. Host-side AI bookkeeping only, never replicated.
var _one_timer_ready_by_peer: Dictionary = {}   # peer_id -> bool


func set_one_timer_ready(peer_id: int, ready: bool) -> void:
	if ready:
		_one_timer_ready_by_peer[peer_id] = true
	else:
		_one_timer_ready_by_peer.erase(peer_id)


func is_one_timer_ready(peer_id: int) -> bool:
	return _one_timer_ready_by_peer.get(peer_id, false)


# ── Smart-ping directives ───────────────────────────────────────────────────
# A validated ping arrives through AICoordinator's queue; force_retick applies
# its slot/threat overrides on the next brain tick, and the per-bot queries
# below are read every AI dispatch.

func apply_ping(type: int, pinger_peer: int, target_peer: int,
		obeyer_peer: int, world_pos: Vector3) -> void:
	ping_directives.add(type, pinger_peer, target_peer, obeyer_peer,
			world_pos, PingRules.directive_duration_s(type))
	force_retick()


func ping_move_target(peer_id: int) -> Vector3:
	return ping_directives.move_target_for(peer_id)


func ping_chase_peer() -> int:
	return ping_directives.chase_peer()


func ping_shoot(peer_id: int) -> bool:
	return ping_directives.shoot_ping_for(peer_id)


func ping_pass_target(peer_id: int) -> int:
	return ping_directives.pass_target_for(peer_id)


func get_team_size() -> int:
	return team_size


func icing_enforced() -> bool:
	return rule_set == GameRules.RuleSet.NHL


func get_threat_shoot_base_by_opp() -> Dictionary[int, float]:
	return threat_shoot_base_by_opp


func get_rush_read() -> AIRushRead:
	return rush_read


# ── Frozen strategy view ─────────────────────────────────────────────────────
# Rebuilt after every brain tick and read by the agent dispatch instead of the
# live brain (Scripts/ai/CLAUDE.md → "The agents do not read the live brain").
# Per-peer ping reads are frozen only for peers that currently hold a slot.
var _view: TeamBrainView = null


func get_view() -> TeamBrainView:
	return _view


func build_view() -> void:
	if _view == null:
		_view = TeamBrainView.new()
	var v: TeamBrainView = _view
	v.strong_x_val = _strong_x
	v.team_size_val = team_size
	v.icing_enforced_val = icing_enforced()
	v.ping_chase_peer_val = ping_directives.chase_peer()
	_freeze_int_dict(slot_assignments, v.slot_by_peer)
	_freeze_int_dict(threat_assignments, v.assigned_threat_by_peer)
	_freeze_int_dict(_position_by_peer, v.position_by_peer)
	_freeze_bool_dict(_one_timer_ready_by_peer, v.one_timer_ready_by_peer)
	_freeze_float_dict(threat_shoot_base_by_opp, v.threat_shoot_base)
	v.rush.copy_from(rush_read)
	v.ping_move_by_peer.clear()
	v.ping_shoot_by_peer.clear()
	v.ping_pass_by_peer.clear()
	for pid: int in slot_assignments:
		v.ping_move_by_peer[pid] = ping_directives.move_target_for(pid)
		v.ping_shoot_by_peer[pid] = ping_directives.shoot_ping_for(pid)
		v.ping_pass_by_peer[pid] = ping_directives.pass_target_for(pid)


# Clear-and-refill rather than allocate: these run every AI batch.
func _freeze_int_dict(src: Dictionary, dst: Dictionary[int, int]) -> void:
	dst.clear()
	for k: int in src:
		dst[k] = src[k]


func _freeze_bool_dict(src: Dictionary, dst: Dictionary[int, bool]) -> void:
	dst.clear()
	for k: int in src:
		dst[k] = src[k]


func _freeze_float_dict(src: Dictionary, dst: Dictionary[int, float]) -> void:
	dst.clear()
	for k: int in src:
		dst[k] = src[k]

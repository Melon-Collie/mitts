class_name AIRoleSlots

# Pure-function 3v3 role slot assignment (5v5 is AIRoleSlots5). Each slot goes
# to the peer that would ARRIVE at its reference point soonest
# (momentum-aware time_to_arrive at its real Speed cap, matching
# AILoosePuckChase and the threat partition), with arrival-time hysteresis.
# Never rank by raw DISTANCE — that hands PRESSURE/BACK_STRONG to a nearer bot
# coasting away over a teammate already skating at the carrier.
#
# This file assigns slots and nothing else: every role owns its positional
# target in its behavior module.
#
# Humans get slot assignments the same as bots; the brain doesn't distinguish.

enum Slot {
	NONE,
	# Shared by multiple states.
	CARRIER,    # OZONE + TRANS_OFFENSE + BREAKOUT: peer with the puck.
	PRESSURE,   # DZONE: puck pressurer, closes the carrier.
	# DZONE: covers an assigned man (threat partition). Also a COVER_HIM ping's
	# forced slot and 5v5's spare-body slot outside our possession.
	MARK,
	# Offensive roles.
	FINISHER,   # OZONE: scoring threat near opp net. Roams the slot.
	OUTLET,     # TRANS_OFFENSE: stretch-pass option at opp blue line.
	# OZONE + TRANS_OFFENSE (and 5v5's spare body while we possess): weak-side
	# trail / cycle support.
	SUPPORT,
	# BREAKOUT (we possess in our OWN DZ). Two outlet options for the
	# carrier breaking the puck out:
	BREAKOUT_STRONG,  # strong-side-wall outlet, free to advance up-ice.
	BREAKOUT_WEAK,    # weak-side reverse valve, stays goal-side of carrier.
	# FORECHECK (their puck in THEIR DZ, and we can get on it): 3v3's 1-1-1.
	F1_PRESSURE,  # deep puck-pressurer (runs PRESSURE's behavior).
	F2_NET,       # reads in front of their net: the reverse, the net-front outlet.
	F3_HIGH,      # 3v3: high on the near wall at their line; first man back.
	# NEUTRAL — loose puck, no clear possession. Race + hold shape.
	CHASE,      # soonest peer races to the puck for retrieval.
	FLANK_L,    # left flank, defensive support behind puck.
	FLANK_R,    # right flank, defensive support behind puck.
	# ── 5v5-only slots (assigned by AIRoleSlots5; never in the 3v3 sets) ─────
	# OZONE: 3 F low / 2 D at the points.
	NET_FRONT,      # F: crease-edge screen / backdoor man (finisher job).
	HIGH_SLOT,      # F: F3 — the soft ice between the dots, above the puck.
	POINT_STRONG,   # D: strong-side point, sinks down his wall with the cycle.
	POINT_WEAK,     # D: weak-side point, holds the line shaded central.
	# FORECHECK: the 1-2-2 (F1_PRESSURE and F2_NET shared with 3v3).
	F3_WALL,        # F: support on the near wall — kills the half-wall outlet.
	DP_STRONG,      # D: offensive blue line, strong side, inside the dots.
	DP_WEAK,        # D: offensive blue line, weak side.
	# DZONE: hybrid zone with soft-lock (see zone_coverage.gd).
	ZONE_D_STRONG,  # D: puck-side low — the corner/boards battle.
	ZONE_D_WEAK,    # D: net-front box.
	ZONE_C,         # F: the slot — low support + seam insurance.
	ZONE_W_STRONG,  # F: strong wall/point coverage high.
	ZONE_W_WEAK,    # F: weak-side high-slot sag.
	# BREAKOUT extras (CARRIER + BREAKOUT_STRONG shared with 3v3).
	BREAKOUT_D2,      # D: net-front/opposite post — the D-to-D "over" valve.
	BREAKOUT_C,       # F: center's low swing — the second outlet.
	BREAKOUT_STRETCH, # F: weak-side winger — mid-ice cross / stretch option.
	# TRANS_OFFENSE rush shape (CARRIER fixed).
	LANE_L,         # F: the left of the two rush lanes the carrier leaves free.
	LANE_R,         # F: the right of them.
	TRAILER,        # ANY: high-slot trailer (the activating fourth man).
	DVALVE,         # D: safety valve trailing the rush.
	# NEUTRAL back shape (CHASE/FLANK reused).
	DBACK_L,        # D: left goal-side hold inside the dots.
	DBACK_R,        # D: right goal-side hold.
	# TRANS_DEFENSE: the set neutral-zone shape, filled from the back — 5v5's
	# 1-1-3, 3v3's 1-2 (NZ_F1 + BACK_STRONG + BACK_MID).
	NZ_F1,        # the high "1": steers the carrier wide, then backchecks his hip.
	NZ_MID,       # F (5v5): the middle "1" — mid-ice up the neutral zone, then back.
	BACK_STRONG,  # our line's strong side: stands the carrier up at it.
	BACK_MID,     # our line's middle: the mid-lane drive and the pass across.
	BACK_WEAK,    # F (5v5): our line's weak lane.
}

# The fixed facts the agent reads per slot, as [debug label, REACTIVE, PRESSURER]:
# REACTIVE slots track something moving at play speed (the carrier, a man, a
# race) and keep the fast argmax cadence; PRESSURER slots own the puck
# defensively and may reach in. The situational cases — the 5v5 zone role that
# owns the puck this tick, the finisher's camp in the zone, a live soft-lock —
# are the agent's to add on top.
const _SLOT_INFO: Dictionary = {
	Slot.CARRIER: ["Carrier", false, false],
	Slot.PRESSURE: ["Pressure", true, true],
	Slot.MARK: ["Mark", true, false],
	Slot.FINISHER: ["Finisher", false, false],
	Slot.OUTLET: ["Outlet", false, false],
	Slot.SUPPORT: ["Support", false, false],
	Slot.BREAKOUT_STRONG: ["BreakStrong", false, false],
	Slot.BREAKOUT_WEAK: ["BreakWeak", false, false],
	Slot.F1_PRESSURE: ["F1", true, true],
	Slot.F2_NET: ["F2Net", false, false],
	Slot.F3_HIGH: ["F3", false, false],
	Slot.CHASE: ["Chase", true, false],
	Slot.FLANK_L: ["FlankL", false, false],
	Slot.FLANK_R: ["FlankR", false, false],
	Slot.NET_FRONT: ["NetFront", false, false],
	Slot.HIGH_SLOT: ["HighSlot", false, false],
	Slot.POINT_STRONG: ["PointS", false, false],
	Slot.POINT_WEAK: ["PointW", false, false],
	Slot.F3_WALL: ["F3Wall", false, false],
	Slot.DP_STRONG: ["DPointS", false, false],
	Slot.DP_WEAK: ["DPointW", false, false],
	Slot.ZONE_D_STRONG: ["ZDS", false, false],
	Slot.ZONE_D_WEAK: ["ZDW", false, false],
	Slot.ZONE_C: ["ZC", false, false],
	Slot.ZONE_W_STRONG: ["ZWS", false, false],
	Slot.ZONE_W_WEAK: ["ZWW", false, false],
	Slot.BREAKOUT_D2: ["BreakD2", false, false],
	Slot.BREAKOUT_C: ["BreakC", false, false],
	Slot.BREAKOUT_STRETCH: ["Stretch", false, false],
	Slot.LANE_L: ["LaneL", false, false],
	Slot.LANE_R: ["LaneR", false, false],
	Slot.TRAILER: ["Trailer", false, false],
	Slot.DVALVE: ["DValve", false, false],
	Slot.DBACK_L: ["DBackL", false, false],
	Slot.DBACK_R: ["DBackR", false, false],
	Slot.NZ_F1: ["NzF1", true, true],
	Slot.NZ_MID: ["NzMid", true, false],
	Slot.BACK_STRONG: ["BackS", true, true],
	Slot.BACK_MID: ["BackM", true, false],
	Slot.BACK_WEAK: ["BackW", true, false],
}


# The slot's short debug label; "-" for NONE.
static func label(slot: int) -> String:
	var info: Array = _SLOT_INFO.get(slot, ["-", false, false])
	return info[0]


static func is_reactive(slot: int) -> bool:
	var info: Array = _SLOT_INFO.get(slot, ["-", false, false])
	return info[1]


static func pressures_puck(slot: int) -> bool:
	var info: Array = _SLOT_INFO.get(slot, ["-", false, false])
	return info[2]


# Hysteresis for the soonest-to-arrive elections: a peer that didn't hold the
# slot last tick pays this many seconds of effective arrival time to take it.
# A hand-set STABILITY MARGIN (it damps an argmin, it measures nothing), scaled
# so the distance it buys — ≈1 m from a standing start, ≈1.8 m at cruise — is
# ANTI_CROWD_RADIUS_M, the span inside which two bots occupy the same spot.
# ~1.2 brain ticks, so it outlives the re-election cadence.
#
# Equal to AILoosePuckChase.HYSTERESIS_S (test_bot_mirrors.gd): the chase and
# slot elections race the same bodies over the same ETA model, and if their
# stickiness disagreed a bot could hold the chase while losing the slot that
# assumes it.
const HYSTERESIS_PENALTY_S: float = 0.2

# Hysteresis for the NEUTRAL flank L/R split, which is an X-axis SIDE choice
# rather than a race: a peer wobbling near centre keeps its previous side unless
# it drifts this far past it.
const HYSTERESIS_PENALTY_M: float = 1.0

# Where our line's posts are raced to: the strong and weak lanes, inside the
# dots (a D's home lane, AIZoneCoverage.D_HOME_U_M).
const BACK_LANE_X_M: float = AIZoneCoverage.D_HOME_U_M


# The back line's post at world-x `x`, as an election target: on our blue line
# while the puck is outside it, at the puck's depth once it is in, but never
# deeper than the house gate (the roles own where each really stands).
static func back_post(own_goal_z: float, puck_pos: Vector3, x: float) -> Vector3:
	var own_dir: float = signf(own_goal_z)
	var depth: float = clampf(GameRules.GOAL_LINE_Z - own_dir * puck_pos.z,
			AIZoneCoverage.HOUSE_TOP_DEPTH_M, GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z)
	return Vector3(x, 0.0, own_dir * (GameRules.GOAL_LINE_Z - depth))


# Assigns each teammate to a slot. Returns Dictionary[peer_id, Slot].
#
# Per state ("soonest" = the time_to_arrive election):
#   DZONE          PRESSURE = soonest to puck;  MARK = the rest
#   OZONE          CARRIER fixed;  FINISHER = soonest to opp net;  SUPPORT = the rest
#   TRANS_OFFENSE  CARRIER fixed;  OUTLET = soonest to opp net;  SUPPORT = the rest
#   BREAKOUT       CARRIER fixed;  BREAKOUT_STRONG = soonest to the strong-side
#                  wall at our blue line;  BREAKOUT_WEAK = the rest
#   TRANS_DEFENSE  BACK_STRONG = soonest to the strong post of our line;
#                  BACK_MID = soonest to its middle of the rest;  NZ_F1 = the rest
#   FORECHECK      F3_HIGH = soonest to their blue line;  F1_PRESSURE = soonest
#                  to the puck of the rest;  F2_NET = the rest
#   NEUTRAL        CHASE = soonest to puck;  FLANK_L / FLANK_R = X-axis split
#
# `prev_assignments` is last tick's Dictionary[peer_id, Slot]; pass {} on the
# first tick. `caps_by_peer` is the live peer→AISkaterCaps map (missing entries
# → league default).
static func assign(
		snapshot: WorldSnapshot,
		team_id: int,
		own_goal_z: float,
		state: int,
		team_id_by_peer: Dictionary,
		prev_assignments: Dictionary,
		_strong_x: float = 1.0,
		caps_by_peer: Dictionary = {}) -> Dictionary[int, int]:
	var result: Dictionary[int, int] = {}
	if snapshot == null:
		return result

	var teammates: Array[int] = []
	for peer_id: int in snapshot.skater_states:
		if team_id_by_peer.get(peer_id, -1) == team_id:
			teammates.append(peer_id)
	if teammates.is_empty():
		return result

	var fixed_peers: Dictionary = {}

	# Fixed CARRIER for OZONE / TRANS_OFFENSE / BREAKOUT.
	if state == AIPossessionState.State.OZONE \
			or state == AIPossessionState.State.TRANS_OFFENSE \
			or state == AIPossessionState.State.BREAKOUT:
		var carrier_pid: int = snapshot.puck_state.carrier_peer_id if snapshot.puck_state else -1
		if carrier_pid != -1 and team_id_by_peer.get(carrier_pid, -1) == team_id:
			result[carrier_pid] = Slot.CARRIER
			fixed_peers[carrier_pid] = true

	var puck_pos: Vector3 = snapshot.puck_state.position if snapshot.puck_state else Vector3.ZERO
	var opp_net := Vector3(0.0, 0.0, -own_goal_z)

	match state:
		AIPossessionState.State.DZONE:
			# Which marker ends up net-front vs. weak-side is decided by
			# TeamBrain's threat partition (which man each is assigned), not a
			# fixed slot split.
			_assign_one_then_remainder(
					snapshot, teammates, fixed_peers, prev_assignments, result,
					Slot.PRESSURE, puck_pos,
					Slot.MARK, caps_by_peer)

		AIPossessionState.State.TRANS_DEFENSE:
			# The 1-2, filled from the back: the two posts of our line first, so
			# whoever can get there holds it, and the last body is the high one.
			_assign_pair_then_remainder(
					snapshot, teammates, fixed_peers, prev_assignments, result,
					Slot.BACK_STRONG, back_post(own_goal_z, puck_pos,
							_strong_x * BACK_LANE_X_M),
					Slot.BACK_MID, back_post(own_goal_z, puck_pos, 0.0),
					Slot.NZ_F1, caps_by_peer)

		AIPossessionState.State.OZONE:
			_assign_one_then_remainder(
					snapshot, teammates, fixed_peers, prev_assignments, result,
					Slot.FINISHER, opp_net,
					Slot.SUPPORT, caps_by_peer)

		AIPossessionState.State.TRANS_OFFENSE:
			_assign_one_then_remainder(
					snapshot, teammates, fixed_peers, prev_assignments, result,
					Slot.OUTLET, opp_net,
					Slot.SUPPORT, caps_by_peer)

		AIPossessionState.State.BREAKOUT:
			# `_strong_x` is the brain's hysteretic strong side, so the
			# strong/weak split doesn't thrash when the D carries the puck
			# across the middle behind the net.
			var own_dir: float = signf(own_goal_z)
			var strong_wall := Vector3(
					_strong_x * GameRules.RINK_HALF_WIDTH, 0.0,
					own_dir * GameRules.BLUE_LINE_Z)
			_assign_one_then_remainder(
					snapshot, teammates, fixed_peers, prev_assignments, result,
					Slot.BREAKOUT_STRONG, strong_wall,
					Slot.BREAKOUT_WEAK, caps_by_peer)

		AIPossessionState.State.FORECHECK:
			# Conservative 1-1-1. F3, the high safety, elects first so the
			# safety is always filled even when the geometry is awkward.
			var opp_blue := Vector3(0.0, 0.0, -signf(own_goal_z) * GameRules.BLUE_LINE_Z)
			_assign_pair_then_remainder(
					snapshot, teammates, fixed_peers, prev_assignments, result,
					Slot.F3_HIGH, opp_blue,
					Slot.F1_PRESSURE, puck_pos,
					Slot.F2_NET, caps_by_peer)

		AIPossessionState.State.NEUTRAL:
			_assign_chase_and_flanks(
					snapshot, teammates, fixed_peers, prev_assignments, result,
					puck_pos, caps_by_peer)

	return result


# ── Assignment helpers ──────────────────────────────────────────────────────

# The peer that would ARRIVE at `target_pos` soonest, excluding already-fixed
# peers, with hysteresis; ties break on the lower peer id. -1 if no eligible
# peer.
static func _pick_soonest_with_hysteresis(
		snapshot: WorldSnapshot,
		teammates: Array,
		fixed_peers: Dictionary,
		prev_assignments: Dictionary,
		target_pos: Vector3,
		slot: Slot,
		caps_by_peer: Dictionary) -> int:
	var best_pid: int = -1
	var best_score: float = INF
	for pid: int in teammates:
		if fixed_peers.has(pid):
			continue
		var s: SkaterNetworkState = snapshot.skater_states[pid]
		var caps: AISkaterCaps = caps_by_peer.get(pid)
		var speed: float = caps.max_speed if caps != null \
				else AIArrival.SKATER_REF_SPEED_M_S
		var t: float = AIArrival.time_to_arrive(
				s.position, target_pos, s.velocity, speed)
		if _hysteresis_class(prev_assignments.get(pid, Slot.NONE)) != _hysteresis_class(slot):
			t += HYSTERESIS_PENALTY_S
		if t < best_score or (t == best_score and (best_pid == -1 or pid < best_pid)):
			best_score = t
			best_pid = pid
	return best_pid


# Cross-state hysteresis continuity. A possession-state flip renames the slots
# (BREAKOUT_STRONG → OUTLET, BACK_STRONG → PRESSURE, ...), and an exact-enum match
# would see no continuity across it, so near-tied peers would swap jobs at the
# handoff and cross paths. Each slot maps to its continuity CLASS; every slot
# not listed maps to itself.
static func _hysteresis_class(slot: int) -> int:
	match slot:
		Slot.BREAKOUT_STRONG, Slot.OUTLET, Slot.FINISHER:
			return Slot.OUTLET       # up-ice attacking option
		Slot.BREAKOUT_WEAK, Slot.SUPPORT:
			return Slot.SUPPORT      # trailing support / reverse valve
		Slot.BACK_STRONG, Slot.PRESSURE:
			return Slot.PRESSURE     # the body that owns the carrier
		Slot.BACK_MID, Slot.MARK:
			return Slot.MARK         # off-puck coverage
		Slot.NZ_F1, Slot.F1_PRESSURE:
			return Slot.F1_PRESSURE  # the first forechecker, deep or high
		_:
			return slot


# Assigns slot1 to soonest-to-target1 peer, slot2 to soonest-to-target2
# peer, then dumps any remainder into slot_remainder. Used by TRANS_DEFENSE and
# FORECHECK.
static func _assign_pair_then_remainder(
		snapshot: WorldSnapshot,
		teammates: Array,
		fixed_peers: Dictionary,
		prev_assignments: Dictionary,
		result: Dictionary,
		slot1: Slot, target1: Vector3,
		slot2: Slot, target2: Vector3,
		slot_remainder: Slot,
		caps_by_peer: Dictionary) -> void:
	var pid1: int = _pick_soonest_with_hysteresis(
			snapshot, teammates, fixed_peers, prev_assignments,
			target1, slot1, caps_by_peer)
	if pid1 != -1:
		result[pid1] = slot1
		fixed_peers[pid1] = true

	var pid2: int = _pick_soonest_with_hysteresis(
			snapshot, teammates, fixed_peers, prev_assignments,
			target2, slot2, caps_by_peer)
	if pid2 != -1:
		result[pid2] = slot2
		fixed_peers[pid2] = true

	for pid: int in teammates:
		if not fixed_peers.has(pid):
			result[pid] = slot_remainder


# Assigns slot1 to soonest-to-target1 peer, then dumps any remainder
# into slot_remainder. Used by DZONE, OZONE, TRANS_OFFENSE and BREAKOUT
# (after CARRIER fix).
static func _assign_one_then_remainder(
		snapshot: WorldSnapshot,
		teammates: Array,
		fixed_peers: Dictionary,
		prev_assignments: Dictionary,
		result: Dictionary,
		slot: Slot, target: Vector3,
		slot_remainder: Slot,
		caps_by_peer: Dictionary) -> void:
	var pid: int = _pick_soonest_with_hysteresis(
			snapshot, teammates, fixed_peers, prev_assignments,
			target, slot, caps_by_peer)
	if pid != -1:
		result[pid] = slot
		fixed_peers[pid] = true

	for pid_r: int in teammates:
		if not fixed_peers.has(pid_r):
			result[pid_r] = slot_remainder


# NEUTRAL: CHASE goes to soonest-to-puck. Remaining peers split on X with
# HYSTERESIS_PENALTY_M biasing each toward its previous side — lowest effective
# X = FLANK_L, rest = FLANK_R.
static func _assign_chase_and_flanks(
		snapshot: WorldSnapshot,
		teammates: Array,
		fixed_peers: Dictionary,
		prev_assignments: Dictionary,
		result: Dictionary,
		puck_pos: Vector3,
		caps_by_peer: Dictionary) -> void:
	var chase_pid: int = _pick_soonest_with_hysteresis(
			snapshot, teammates, fixed_peers, prev_assignments,
			puck_pos, Slot.CHASE, caps_by_peer)
	if chase_pid != -1:
		result[chase_pid] = Slot.CHASE
		fixed_peers[chase_pid] = true

	var remaining: Array = []
	for pid: int in teammates:
		if not fixed_peers.has(pid):
			remaining.append(pid)
	if remaining.is_empty():
		return

	var effective_x: Dictionary = {}
	for pid_r: int in remaining:
		var x: float = snapshot.skater_states[pid_r].position.x
		var prev_slot: int = prev_assignments.get(pid_r, Slot.NONE)
		if prev_slot == Slot.FLANK_L:
			x -= HYSTERESIS_PENALTY_M
		elif prev_slot == Slot.FLANK_R:
			x += HYSTERESIS_PENALTY_M
		effective_x[pid_r] = x

	remaining.sort_custom(func(a: int, b: int) -> bool:
			return effective_x[a] < effective_x[b])

	result[remaining[0]] = Slot.FLANK_L
	for i: int in range(1, remaining.size()):
		result[remaining[i]] = Slot.FLANK_R

class_name AILastManDiscipline

# Last-man discipline: when a station may hold its forward stand, and where it
# falls back to when it may not — the numbers floor, the retreat floor, the
# house gate — plus PRESSURE's step-up bound. See Scripts/domain/ai/CLAUDE.md →
# "Last-man discipline". The pinch read's three facts (docs/transition-defense-
# plan.md §13): SUPPORT and NUMBERS are _attacker_behind (a man behind us whom
# no teammate is better placed to pick up); CONTROL stays unread (CLAUDE.md →
# "The three facts a station reads").


# While HOLDING, a station demands this much extra separation before it accepts
# that a man has got behind it — one more stick beyond the cover envelope.
const BEHIND_HOLD_EXTRA_M: float = 1.8


# How long a feed may be in flight and still make you a live passing option —
# sized on how long a carrier holds the puck in the offensive zone before he must
# move it.
const PLAY_CONNECTION_FLIGHT_S: float = 1.1


# True when a station may keep its forward stand. It is lost only when they have
# it and it is coming at us, or somebody is behind us and nobody covers for us —
# never because control is contested.
static func may_hold_forward_stand(ctx: RoleContext, was_holding: bool,
		stand: Vector3) -> bool:
	var read: AIRushRead = ctx.rush_read
	# An unwired read knows nothing: hold the shape.
	if not read.is_live:
		return true
	if not _we_possess(ctx) and read.mode == AIRushRead.Mode.RUSH:
		# THEIR puck: possession alone is no reason to bail — a bottled carrier is
		# exactly who you pinch on. The trigger is that they are moving out
		# (Mode.RUSH); bottled or turning back reads REGROUP: hold.
		return false
	# The numbers half: nobody behind us that we are the body to pick up.
	# `was_holding` makes it hysteretic — see _attacker_behind.
	return not _attacker_behind(ctx, stand, was_holding)


# True when one of ours carries the puck — whether a station is making a pinch
# decision at all.
static func _we_possess(ctx: RoleContext) -> bool:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return false
	var pid: int = ctx.snapshot.puck_state.carrier_peer_id
	return pid != -1 and ctx.team_id_by_peer.get(pid, -1) == ctx.team_id


# The numbers-restoring retreat: only as far back as puts us goal-side of the
# deepest attacker behind our stand as we race him (AIRoleRushD.race_depth_to_net)
# — "count numbers, and if any are behind you, deal with it". With nobody behind
# the stand it is its own floor: no station is walked home for a phantom.
static func numbers_floor(ctx: RoleContext, stand: Vector3) -> Vector3:
	var read: AIRushRead = ctx.rush_read
	var our_net: Vector3 = ctx.defending_goal_pos
	var stand_d: float = AIRoleReads.xz_distance(stand, our_net)
	var deepest: float = stand_d
	for i: int in read.attackers.size():
		var d: float = AIRoleRushD.race_depth_to_net(ctx, read.attackers[i])
		if d < deepest:
			deepest = d
	if deepest >= stand_d:
		return stand   # nobody behind us — hold
	# Goal-side of him by a cover depth, along our own retreat line.
	var target_d: float = maxf(deepest - AIThreatAssignment.COVER_DEPTH_M, 0.0)
	var dx: float = stand.x - our_net.x
	var dz: float = stand.z - our_net.z
	var len_s: float = sqrt(dx * dx + dz * dz)
	if len_s < 0.001:
		return stand
	return Vector3(our_net.x + dx * (target_d / len_s), 0.0,
			our_net.z + dz * (target_d / len_s))


# Pull a station's target back within feedable range of the puck. See
# Scripts/domain/ai/CLAUDE.md → "The play-connection leash".
static func pull_into_play(ctx: RoleContext, target: Vector3) -> Vector3:
	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		return target
	# Only while WE have it: there is no passing option to be otherwise.
	if not _we_possess(ctx):
		return target
	var puck: Vector3 = ctx.snapshot.puck_state.position
	var reach: float = AIPuckLane.expected_pass_speed(puck, target) \
			* PLAY_CONNECTION_FLIGHT_S
	var dx: float = target.x - puck.x
	var dz: float = target.z - puck.z
	var d: float = sqrt(dx * dx + dz * dz)
	if d <= reach or d < 0.001:
		return target
	return Vector3(puck.x + dx * (reach / d), 0.0, puck.z + dz * (reach / d))


# The whole offensive-station decision: hold the forward stand (leashed to the
# play) while the read allows it; else restore the numbers layer if we still
# have the puck, or retreat to structure if we don't.
static func offensive_station_target(ctx: RoleContext, stand: Vector3,
		was_holding: bool, as_back_layer: bool = false) -> Vector3:
	if may_hold_forward_stand(ctx, was_holding, stand):
		return pull_into_play(ctx, stand)
	if _we_possess(ctx):
		# No leash on a retreat: clamping a recovery back up-ice toward the puck
		# would undo the coverage the read just called for.
		return numbers_floor(ctx, stand)
	return station_retreat_floor(ctx, stand, as_back_layer)


# The last-man bound for the NEUTRAL shapes (3v3 FLANK, 5v5 DBACK): the same
# read as offensive_station_target, but losing the forward stand restores a
# numbers layer — the deeper of numbers_floor and the caller's `layer_stand` —
# floored at the house gate, rather than a post. `layer_stand` also demands
# home_layer_behind_me to hold. See Scripts/domain/ai/CLAUDE.md → "Last-man
# discipline".
static func neutral_station_target(ctx: RoleContext, stand: Vector3,
		was_holding: bool, layer_stand: Vector3 = Vector3.INF) -> Vector3:
	if may_hold_forward_stand(ctx, was_holding, stand) \
			and (not layer_stand.is_finite() or home_layer_behind_me(ctx)):
		return stand
	var our_net: Vector3 = ctx.defending_goal_pos
	var sagged: Vector3 = numbers_floor(ctx, stand)
	# numbers_floor returns the stand untouched when nobody has beaten us, which
	# says nothing in a loose-puck state; take the deeper so both reasons bind.
	# Both lie on the net → stand ray, so a distance compare suffices.
	if layer_stand.is_finite() \
			and AIRoleReads.xz_distance(layer_stand, our_net) < AIRoleReads.xz_distance(sagged, our_net):
		sagged = layer_stand
	if AIRoleReads.xz_distance(sagged, our_net) >= AIZoneCoverage.HOUSE_TOP_DEPTH_M:
		return sagged
	return house_gate_floor(our_net, sagged)


# ── "If I go, is anybody home?" ──────────────────────────────────────────────
#
# A teammate deeper than us by a cover envelope, the elected chaser aside
# (committed to the puck, he holds nothing). With the margin, two bodies level
# with each other cover nothing for one another. Antisymmetric: exactly one body
# draws the layer, and no two can each appoint the other.
static func home_layer_behind_me(ctx: RoleContext) -> bool:
	if ctx.snapshot == null:
		return false
	var chaser: int = ctx.snapshot.closest_to_puck_by_team.get(ctx.team_id, -1)
	var my_depth: float = ctx.own_goal_dir * ctx.self_pos.z \
			+ AIRushRead.cover_envelope_m()
	for pid: int in ctx.snapshot.skater_states:
		if pid == ctx.peer_id or pid == chaser:
			continue
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
			continue
		var mate: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		if mate.is_ghost:
			continue
		if ctx.own_goal_dir * mate.position.z > my_depth:
			return true
	return false


# Is any attacker deeper (nearer our net) than `stand`, as we have to race him,
# with no teammate better placed than us to pick him up?
static func _attacker_behind(ctx: RoleContext, stand: Vector3,
		was_holding: bool = false) -> bool:
	var our_net: Vector3 = ctx.defending_goal_pos
	var stand_d: float = AIRoleReads.xz_distance(stand, our_net)
	# "Behind" means past the cover envelope (a goal-side stand plus a stick): a
	# man level with the stand is in the same layer, not past it.
	var margin: float = AIRushRead.cover_envelope_m()
	if was_holding:
		margin += BEHIND_HOLD_EXTRA_M
	for pid: int in ctx.rush_read.attackers:
		if AIRoleRushD.race_depth_to_net(ctx, pid) < stand_d - margin \
				and not _mate_better_placed(ctx, pid):
			return true
	return false


# True when a teammate can still get goal-side of the threat on his run at our
# net, somewhere past us, before he gets there: the layer that picks him up
# if our challenge is beaten. False: we are the last man back. The threat is
# `ap`'s subject (carrier or loose puck), timed on its carrier's build; nobody
# is charged the time it takes him to beat us.
static func has_support_behind(ctx: RoleContext, ap: AICarrierApproach) -> bool:
	if ctx.snapshot == null or ap.dir_net == Vector3.ZERO:
		return false
	var line_len: float = ap.net_dist
	# Only ground past us covers for us: a mate who is goal-side of him only
	# where we already are is level with the challenge, not behind it.
	var from_s: float = maxf((ctx.self_pos.x - ap.carrier_pos.x) * ap.dir_net.x
			+ (ctx.self_pos.z - ap.carrier_pos.z) * ap.dir_net.z
			+ AIRushRead.cover_envelope_m(), 0.0)
	if from_s >= line_len:
		return false
	var threat_caps: AISkaterCaps = ctx.caps_by_peer.get(_threat_peer(ctx))
	for k: int in range(1, SUPPORT_RACE_SAMPLES + 1):
		var s: float = from_s + (line_len - from_s) * float(k) / SUPPORT_RACE_SAMPLES
		var spot: Vector3 = ap.carrier_pos + ap.dir_net * s
		var t_threat: float = AIArrival.time_to_arrive_caps(
				ap.carrier_pos, spot, ap.carrier_vel, threat_caps)
		for pid: int in ctx.snapshot.skater_states:
			if pid == ctx.peer_id or ctx.team_id_by_peer.get(pid, -1) != ctx.team_id:
				continue
			var mate: SkaterNetworkState = ctx.snapshot.skater_states[pid]
			if mate.is_ghost:
				continue
			# Exact prescreen: no skate there beats the straight line at his best pace.
			var caps: AISkaterCaps = ctx.caps_by_peer.get(pid)
			var pace: float = maxf(caps.max_speed if caps != null
					else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S, mate.velocity.length())
			if AIRoleReads.xz_distance(mate.position, spot) > pace * t_threat:
				continue
			if AIArrival.time_to_arrive_caps(mate.position, spot, mate.velocity, caps) \
					<= t_threat:
				return true
	return false


# Points on a threat's run that the support races sample, evenly to its end.
const SUPPORT_RACE_SAMPLES: int = 4


# The opposing carrier, whose build a threat run is timed on; -1 (the league
# build) for a loose puck or our own.
static func _threat_peer(ctx: RoleContext) -> int:
	if ctx.snapshot.puck_state == null:
		return -1
	var pid: int = ctx.snapshot.puck_state.carrier_peer_id
	if pid == -1 or ctx.team_id_by_peer.get(pid, -1) == ctx.team_id:
		return -1
	return pid


# Is some teammate better placed than us to get goal-side of attacker `pid` on
# his run at our net? Placement is the best lead a body can take on him at any
# point of the run (arrival time against his). The station that is not the best
# placed body has no business retreating for him: someone else gets there
# first. Ties go to the lower peer id, so exactly one body draws the job. Our
# carrier is not a candidate: the man behind matters only once the puck is lost.
static func _mate_better_placed(ctx: RoleContext, pid: int) -> bool:
	var threat: SkaterNetworkState = ctx.snapshot.skater_states.get(pid)
	if threat == null:
		return false
	var our_net: Vector3 = ctx.defending_goal_pos
	var net_dist: float = AIRoleReads.xz_distance(threat.position, our_net)
	if net_dist < 0.001:
		return false
	var dir_net := Vector3((our_net.x - threat.position.x) / net_dist, 0.0,
			(our_net.z - threat.position.z) / net_dist)
	var line_len: float = net_dist
	var threat_caps: AISkaterCaps = ctx.caps_by_peer.get(pid)
	var mine: float = _lead_on_run(threat, threat_caps, dir_net, line_len,
			ctx.self_pos, ctx.self_velocity, ctx.caps_by_peer.get(ctx.peer_id))
	var carrier: int = ctx.snapshot.puck_state.carrier_peer_id \
			if ctx.snapshot.puck_state != null else -1
	for mate_pid: int in ctx.snapshot.skater_states:
		if mate_pid == ctx.peer_id or mate_pid == carrier \
				or ctx.team_id_by_peer.get(mate_pid, -1) != ctx.team_id:
			continue
		var mate: SkaterNetworkState = ctx.snapshot.skater_states[mate_pid]
		if mate.is_ghost:
			continue
		var theirs: float = _lead_on_run(threat, threat_caps, dir_net, line_len,
				mate.position, mate.velocity, ctx.caps_by_peer.get(mate_pid))
		if theirs > mine or (theirs == mine and mate_pid < ctx.peer_id):
			return true
	return false


# The most time a body arrives ahead of a threat at any sampled point of his run
# (negative: it is beaten everywhere).
static func _lead_on_run(threat: SkaterNetworkState, threat_caps: AISkaterCaps,
		dir_net: Vector3, line_len: float, body_pos: Vector3, body_vel: Vector3,
		body_caps: AISkaterCaps) -> float:
	var best: float = -INF
	for k: int in range(1, SUPPORT_RACE_SAMPLES + 1):
		var spot: Vector3 = threat.position + dir_net * (line_len * float(k) / SUPPORT_RACE_SAMPLES)
		var lead: float = AIArrival.time_to_arrive_caps(
				threat.position, spot, threat.velocity, threat_caps) \
				- AIArrival.time_to_arrive_caps(body_pos, spot, body_vel, body_caps)
		best = maxf(best, lead)
	return best


# The shallowest stand depth — metres goal-side of `threat_pos` along `dir_net`
# — the last man may take this dispatch, wanting `desired_depth` against a
# threat closing on our net at `closing` m/s. An ICE-FRAME bound: callers apply
# it only to a stand that does not ride a man.
#
# A speed limit on the approach, expressed as the stand that enforces it. In the
# threat-relative frame the defender's depth shrinks at `v + closing`, so
# becoming rush-matched from approach speed `v` costs
#
#     consumed(v) = v²/2B  +  closing·v/B  +  ramp(closing)
#                   \_____/    \________/     \___________/
#                   braking    the rush's     the PIVOT: the stride's distance
#                   distance   share of it    back up to his pace going the
#                                             other way
#
# which must fit in `spare = self_along - desired_depth`. The pivot term is what
# makes it gap control rather than merely arriving stopped. The stand is where a
# body at the cap would begin braking (v²/2B ahead), so the arrival brake is the
# actuator.
#
# The cap depends on the ICE, not the defender's speed, so it is state feedback.
# Never re-derive it as a per-dispatch step-up plan: recomputed with no memory
# of the plan it revises, that shape ratchets.
#
# `threat_peer` is the man who drives at our net from the threat, bursting from
# `closing` on his own build the moment we commit (approach_speed_cap); -1 for
# nobody, when only `closing` itself comes at us.
#
# Returns `desired_depth` unchanged when no bound applies (a stand already
# goal-side of us, or nothing coming at us).
static func settable_stand_depth(ctx: RoleContext, threat_pos: Vector3,
		dir_net: Vector3, desired_depth: float, closing: float,
		threat_peer: int = -1) -> float:
	var self_along: float = (ctx.self_pos.x - threat_pos.x) * dir_net.x \
			+ (ctx.self_pos.z - threat_pos.z) * dir_net.z
	var spare: float = self_along - desired_depth
	if spare <= 0.0 or (closing <= 0.01 and threat_peer == -1):
		return desired_depth
	var threat_vmax: float = 0.0
	var threat_accel: float = 0.0
	if threat_peer != -1:
		var caps: AISkaterCaps = ctx.caps_by_peer.get(threat_peer)
		threat_vmax = caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
		threat_accel = caps.max_accel if caps != null else GameRules.DEFAULT_SKATER_THRUST_M_S2
	var v_cap: float = approach_speed_cap(spare, closing, ctx.self_max_speed,
			ctx.self_max_accel, threat_vmax, threat_accel)
	var brake_lead: float = v_cap * v_cap \
			/ (2.0 * AISteering.ARRIVAL_BRAKE_DECEL_M_S2)
	return maxf(desired_depth, self_along - brake_lead)


# Their man on a loose puck — who drives at our net once he has it — or -1.
static func loose_puck_driver(ctx: RoleContext) -> int:
	if ctx.snapshot == null:
		return -1
	return ctx.snapshot.closest_to_puck_by_team.get(1 - ctx.team_id, -1)


# Halvings of [0, v_max] approach_speed_cap solves to: under a centimetre a second
# of cap at any body's top speed.
const APPROACH_CAP_BISECT: int = 16


# The fastest approach `v` in [0, v_max] whose consumed depth fits in `spare`:
# braking it out (v²/2B), the ground the threat covers meanwhile, and the pivot
# that builds back to the pace he has then. The threat goes at `closing` and,
# with `threat_accel`, drives up from it along his stride ramp to
# `threat_vmax` while the defender brakes — a man standing still bursts the
# moment he sees the defender commit. With less spare depth than the pivot
# alone costs, he holds.
static func approach_speed_cap(spare: float, closing: float, v_max: float,
		max_accel: float, threat_vmax: float = 0.0, threat_accel: float = 0.0) -> float:
	var top: float = maxf(v_max, 0.0)
	if _consumed_depth(top, closing, max_accel, threat_vmax, threat_accel) <= spare:
		return top
	if _consumed_depth(0.0, closing, max_accel, threat_vmax, threat_accel) > spare:
		return 0.0
	var lo: float = 0.0
	var hi: float = top
	for _i: int in APPROACH_CAP_BISECT:
		var mid: float = (lo + hi) * 0.5
		if _consumed_depth(mid, closing, max_accel, threat_vmax, threat_accel) <= spare:
			lo = mid
		else:
			hi = mid
	return lo


static func _consumed_depth(v: float, closing: float, max_accel: float,
		threat_vmax: float, threat_accel: float) -> float:
	var brake_decel: float = AISteering.ARRIVAL_BRAKE_DECEL_M_S2
	var t_b: float = v / brake_decel
	var gone: float = closing * t_b
	var pace: float = closing
	if threat_accel > 0.0:
		gone = AIStrideRamp.distance_in(closing, t_b, maxf(threat_vmax, closing), threat_accel)
		pace = AIStrideRamp.speed_at(closing, t_b, maxf(threat_vmax, closing), threat_accel)
	return v * v / (2.0 * brake_decel) + gone + AIStrideRamp.distance_to_speed(pace, max_accel)


# How much deeper than the stand a home post must be to count as a retreat — one
# stride, so a station standing on its own post falls to the house gate instead.
const HOME_FLOOR_BIND_MARGIN_M: float = 1.0


# offensive_station_target's retreat when the puck is no longer ours: "get back
# to your post", never the crease — defending an actual rush is transition
# defense's job (docs/transition-defense-plan.md §2.1). A station up-ice of its
# home post (AIZoneCoverage.defensive_anchor) floors there; one already at home
# floors at the house gate.
#
# `as_back_layer` forces the DEFENSEMAN's post: ctx.self_is_defense is a lobby
# fact, and in 3v3 every peer reads "forward", so a role that is its team's whole
# back layer (3v3's F3_HIGH) would otherwise floor too shallow.
static func station_retreat_floor(ctx: RoleContext, fwd: Vector3,
		as_back_layer: bool = false) -> Vector3:
	var our_net: Vector3 = ctx.defending_goal_pos
	var home: Vector3 = AIZoneCoverage.defensive_anchor(
			ctx.self_is_defense or as_back_layer, ctx.self_home_side, our_net.z)
	if ctx.own_goal_dir * home.z > ctx.own_goal_dir * fwd.z + HOME_FLOOR_BIND_MARGIN_M:
		return home
	return house_gate_floor(our_net, fwd)


# Holds `pos` OUT at the house gate when it was placed deeper, projecting along
# the net → pos ray (straight up the rink axis from the net itself).
static func hold_out_to_house_gate(our_net: Vector3, pos: Vector3) -> Vector3:
	var dx: float = pos.x - our_net.x
	var dz: float = pos.z - our_net.z
	var dsq: float = dx * dx + dz * dz
	var gate: float = AIZoneCoverage.HOUSE_TOP_DEPTH_M
	if dsq >= gate * gate:
		return pos
	var dl: float = sqrt(dsq)
	if dl < 0.001:
		return Vector3(our_net.x, 0.0, our_net.z - signf(our_net.z) * gate)
	return Vector3(our_net.x + dx * (gate / dl), 0.0, our_net.z + dz * (gate / dl))


# Clamps `fwd` onto the net → `fwd` ray at the house gate when it lies beyond it:
# the deepest a last-man bound may push a field skater. Inside it he duplicates
# the goalie and fights his own crease repel.
static func house_gate_floor(our_net: Vector3, fwd: Vector3) -> Vector3:
	var dx: float = fwd.x - our_net.x
	var dz: float = fwd.z - our_net.z
	var d: float = sqrt(dx * dx + dz * dz)
	if d < 0.001 or d <= AIZoneCoverage.HOUSE_TOP_DEPTH_M:
		return fwd
	var k: float = AIZoneCoverage.HOUSE_TOP_DEPTH_M / d
	return Vector3(our_net.x + dx * k, 0.0, our_net.z + dz * k)

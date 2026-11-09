class_name AICarrierRimSearch
extends RefCounted

# The rim launches (AIRimPass, built once per eval by AICarrierPassSearch)
# ranked for one receiver: how surely and soon the softest near-best launch
# reaches him, and whether one that gets by him ices. AICarrierPassSearch owns
# one over its AICarrierField and prices only the eval's single best rim.

# A rim is fired as soft as the race allows: any launch reaching the receiver at
# least this share as surely as the best one may be picked, and the softest of
# those is. Doctrine, not a measurement — a soft rim is easier to stop, and one
# that gets by him dies sooner (under NHL rules, short of an icing).
const RIM_SOFT_SHARE: float = 0.9

# The best launch launch_for found, and its path reads: its index in
# AIRimPass, its meet time, the race as its lane and the passer's aim error.
var pick_k: int = -1
var pick_t: float = 0.0
var pick_lane: float = 0.0
var pick_miss: float = 0.0
# Per-launch reads for one receiver (index-matched to AIRimPass' scratch, -1 =
# not a candidate), so the softest near-best launch can be picked after the scan.
var sure_by_k: PackedFloat64Array = PackedFloat64Array()
var _t_by_k: PackedFloat64Array = PackedFloat64Array()
var _lane_by_k: PackedFloat64Array = PackedFloat64Array()
var _miss_by_k: PackedFloat64Array = PackedFloat64Array()

# Our side at the release, for the icing race to the dots (ices).
var _ours_pos: Array[Vector3] = []
var _ours_vel: Array[Vector3] = []
var _ours_caps: Array[AISkaterCaps] = []

var _field: AICarrierField


func _init(field: AICarrierField) -> void:
	_field = field


# How surely and soon a RIM reaches `receiver_state` (completion × the delay
# discount, 0.0 when none does) — the softest launch within RIM_SOFT_SHARE of the
# surest — with that launch's path reads (meet time on the walked path, the race
# against the soonest opponent as the lane, the passer's aim error over the path
# length) left in pick_k / pick_t / pick_lane / pick_miss.
#
# A RANK, not a price: AICarrierPassSearch.search weighs it by the receiver's
# cached spot value and prices only the eval's single best rim. Launches
# that reach one receiver meet him within a stride of each other, so his value
# cannot reorder them.
#
# Zone rules follow the straight feed's: a carrier in the zone keeps the puck in
# it up to the meet, and one outside it does not rim the puck into it (the
# receiver would be offside).
func launch_for(ctx: RoleContext, receiver_state: SkaterNetworkState,
		receiver_omega: float, receiver_caps: AISkaterCaps,
		carrier_in_oz: bool) -> float:
	var speed: float = receiver_caps.max_speed if receiver_caps != null \
			else AIArrival.SKATER_REF_SPEED_M_S
	var catch_radius: float = receiver_caps.handle_reach if receiver_caps != null \
			else AIBotMechanics.EVADE_CARRY_HANDLE_M
	var receiver_speed: float = Vector2(
			receiver_state.velocity.x, receiver_state.velocity.z).length()
	if sure_by_k.size() != AIRimPass.MAX_LAUNCHES:
		sure_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_t_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_lane_by_k.resize(AIRimPass.MAX_LAUNCHES)
		_miss_by_k.resize(AIRimPass.MAX_LAUNCHES)
	var best_sure: float = 0.0
	for k: int in AIRimPass.count:
		sure_by_k[k] = -1.0
		var t: float = AIRimPass.meet_time(k, receiver_state.position,
				receiver_state.velocity, speed)
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
		sure_by_k[k] = sure
		_t_by_k[k] = t
		_lane_by_k[k] = lane
		_miss_by_k[k] = miss_prob
		best_sure = maxf(best_sure, sure)
	if best_sure <= 0.0:
		return 0.0
	# Fire it as soft as the race allows: among the launches nearly as sure as the
	# best, the softest — easier to stop, and a missed one dies sooner.
	var pick: int = -1
	for k: int in AIRimPass.count:
		var sure_k: float = sure_by_k[k]
		if sure_k < best_sure * RIM_SOFT_SHARE:
			continue
		if pick == -1 or AIRimPass.paces[k] < AIRimPass.paces[pick] \
				or (AIRimPass.paces[k] == AIRimPass.paces[pick] and sure_k > sure_by_k[pick]):
			pick = k
	pick_k = pick
	pick_t = _t_by_k[pick]
	pick_lane = _lane_by_k[pick]
	pick_miss = _miss_by_k[pick]
	return sure_by_k[pick]


# Whether rim launch `k` from `origin` ices when it gets by our receiver
# (AIIcingRead): its path across their goal line before their soonest man meets
# it, the next stick on it once ours has missed it.
func ices(ctx: RoleContext, origin: Vector3, k: int) -> bool:
	var attack_z: float = signf(ctx.attacking_goal_pos.z)
	var path: Array[Vector3] = AIRimPass.paths[k]
	var crossed_s: float = AIIcingRead.crossing_s(path, AIRimPass.STEP_DT, attack_z)
	var touched_s: float = AIRimPass.opp_time(k)
	if crossed_s >= touched_s:
		return false
	_ours_pos.clear()
	_ours_vel.clear()
	_ours_caps.clear()
	for pid: int in ctx.snapshot.skater_states:
		if ctx.team_id_by_peer.get(pid, -1) != ctx.team_id \
				or (pid != ctx.peer_id and ctx.snapshot.is_out_of_play(pid)):
			continue
		var st: SkaterNetworkState = ctx.snapshot.skater_states[pid]
		_ours_pos.append(st.position)
		_ours_vel.append(st.velocity)
		_ours_caps.append(ctx.caps_by_peer.get(pid))
	return AIIcingRead.ices(origin.z, attack_z, crossed_s, touched_s,
			AIIcingRead.first_to_dots(attack_z, _ours_pos, _ours_vel, _ours_caps),
			AIIcingRead.first_to_dots(attack_z, _field.opponents_release,
					_field.opponent_vels, _field.opponent_caps))

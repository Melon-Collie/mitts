class_name CrossCheckClaimResolver
extends RefCounted

# Host-only resolver for client-initiated cross-check claims with lag
# compensation, plus the client-side send. The claimant, in the push
# (CrossCheckRules EXTEND), had an opponent's body on his shaft as he saw him,
# the shaft pushed out along the aim his throw latched.
#
# Flow:
#   maybe_send_claim()  [client, every tick]
#     → once per throw: the nearest rendered opponent in reach while pushing
#   receive_claim(peer_id, host_ts, interp_delay, input_lead, target_peer_id)
#     → reject if the claim is stale, the target is missing / self / a teammate
#     → rewind the claimant to self_view_time (ClaimantView's catch-up); reject a
#       ghost or one not in the push then
#     → rewind the target to remote_view_time(host_ts, interp_delay), forward-
#       predicted as the client rendered him (LagCompRewind.forward_predict_
#       skater); reject a ghost
#     → reject unless CrossCheckRules.in_reach on those two bodies, along the
#       claimant's aim at self_view_time (the host latched it off the same press)
#     → CrossCheckTracker.try_land, which re-checks the present (idempotent with
#       the host's own present-time landing: one per throw)
#
# The shared claim-resolver contract is in Scripts/game/CLAUDE.md.

var _registry: PlayerRegistry = null
var _state_buffer: StateBufferManager = null
var _tracker_getter: Callable = Callable()   # () -> CrossCheckTracker
var _fp_result := SkaterMovementRules.ForwardResult.new()
var _claimant := ClaimantView.new()
var _sent_this_throw: bool = false


func setup(registry: PlayerRegistry, state_buffer: StateBufferManager,
		tracker_getter: Callable) -> void:
	_registry = registry
	_state_buffer = state_buffer
	_tracker_getter = tracker_getter


# Client side, every tick: once per throw, while the local skater is pushing,
# claim the nearest opponent his rendered body has in reach.
func maybe_send_claim() -> void:
	if NetworkManager.is_host or not NetworkManager.is_clock_ready() or _registry == null:
		return
	var local: PlayerRecord = _registry.get_local()
	if local == null or local.skater == null:
		return
	var me: Skater = local.skater
	if not CrossCheckRules.can_land(me.cross_check_phase, me.cross_check_elapsed):
		_sent_this_throw = false
		return
	if _sent_this_throw or me.is_ghost:
		return
	var my_team: int = _registry.team_id_by_skater.get(me, -1)
	var best_pid: int = -1
	var best_d: float = INF
	var players: Dictionary[int, PlayerRecord] = _registry.all()
	for pid: int in players:
		var rec: PlayerRecord = players[pid]
		if rec.skater == null or rec.skater == me or rec.skater.is_ghost \
				or _registry.team_id_by_skater.get(rec.skater, -1) == my_team:
			continue
		if not CrossCheckRules.in_reach(me.global_position, me.cross_check_aim,
				me.collision_radius(), rec.skater.global_position, rec.skater.collision_radius()):
			continue
		var d: float = me.global_position.distance_squared_to(rec.skater.global_position)
		if d < best_d:
			best_d = d
			best_pid = pid
	if best_pid == -1:
		return
	_sent_this_throw = true
	# The adapted interp delay positioned the rendered body this frame; see the
	# pickup claim send in LocalController.
	NetworkManager.send_cross_check_claim(NetworkManager.estimated_host_time(),
			NetworkManager.get_interpolation_delay() * 1000.0, best_pid)


func receive_claim(peer_id: int, host_timestamp: float, interp_delay_ms: float,
		input_lead_ms: float, target_peer_id: int) -> void:
	if not _tracker_getter.is_valid() or _registry == null:
		return
	var tracker: CrossCheckTracker = _tracker_getter.call() as CrossCheckTracker
	if tracker == null:
		return
	interp_delay_ms = LagCompRewind.plausible_interp_delay_ms(
			interp_delay_ms, float(NetworkManager.get_peer_ping_ms(peer_id)))
	if not LagCompRewind.claim_is_fresh(host_timestamp):
		return
	var record: PlayerRecord = _registry.get_record(peer_id)
	var target: PlayerRecord = _registry.get_record(target_peer_id)
	if record == null or record.skater == null or target == null or target.skater == null:
		return
	if record.skater == target.skater:
		return
	var my_team: int = _registry.team_id_by_skater.get(record.skater, -1)
	var their_team: int = _registry.team_id_by_skater.get(target.skater, -1)
	if my_team == -1 or their_team == -1 or my_team == their_team:
		return
	if _state_buffer == null or not _state_buffer.is_ready():
		return
	var self_time: float = LagCompRewind.self_view_time(host_timestamp, input_lead_ms)
	var shover_snap: SkaterNetworkState = _state_buffer.get_state_at(self_time) \
			.get_skater_state(peer_id)
	if shover_snap == null or shover_snap.is_ghost \
			or not CrossCheckRules.can_land(shover_snap.cross_check_phase,
					shover_snap.cross_check_elapsed):
		return
	if not _claimant.resolve(_registry, peer_id, shover_snap,
			record.controller as SkaterController, self_time,
			_state_buffer.newest_host_timestamp()):
		return
	var shover_pos: Vector3 = shover_snap.position + _claimant.catch_up()
	var victim_snap: SkaterNetworkState = _state_buffer.get_state_at(
			LagCompRewind.remote_view_time(host_timestamp, interp_delay_ms)) \
			.get_skater_state(target_peer_id)
	if victim_snap == null or victim_snap.is_ghost:
		return
	var victim_pos: Vector3 = victim_snap.position
	if LagCompRewind.forward_predict_skater(victim_snap,
			target.controller as SkaterController, interp_delay_ms, input_lead_ms,
			_fp_result):
		victim_pos = _fp_result.position
	if not CrossCheckRules.in_reach(shover_pos, shover_snap.cross_check_aim,
			record.skater.collision_radius(), victim_pos, target.skater.collision_radius()):
		return
	tracker.try_land(record.skater, target.skater)

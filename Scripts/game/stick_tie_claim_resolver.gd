class_name StickTieClaimResolver
extends RefCounted

# Host-only resolver for client-initiated stick-tie claims with lag compensation,
# plus the client-side send. Mirrors StickLiftClaimResolver with a non-carrier
# target: the claimant, in the TIE phase of a stick check, has their blade within
# reach of an opponent's hand→blade shaft as they saw it.
#
# Flow:
#   receive_claim(peer_id, host_ts, interp_delay, input_lead, target_peer_id,
#                 client_blade_curr)
#     → reject if the claim is stale, the target is missing / self / a teammate
#     → rewind the target's shaft to remote_view_time(host_ts, interp_delay),
#       shifted by its forward-predicted displacement (LagCompRewind
#       .forward_predict_skater, as the lift resolver does); reject if the target
#       was carrying then (a carrier's stick is lifted, not tied)
#     → rewind the claimant to self_view_time; reject a ghost or one not in TIE
#     → ClaimantView-clamp the client blade, and reject unless it is within
#       StickCheckRules.TIE_ENGAGE_RADIUS_M of the rewound shaft
#     → StickTieTracker.try_engage, which re-checks the present (idempotent)
#
# The shared claim-resolver contract is in Scripts/game/CLAUDE.md.

# A claimant in reach of an untied stick re-sends no faster than this, so a held
# tie the host refused is retried a few times a second rather than every tick.
const _RESEND_S: float = 0.15

var _registry: PlayerRegistry = null
var _state_buffer: StateBufferManager = null
var _ties_getter: Callable = Callable()             # () -> StickTieTracker
var _puck_controller_getter: Callable = Callable()  # () -> PuckController
var _fp_result := SkaterMovementRules.ForwardResult.new()
var _claimant := ClaimantView.new()
var _last_sent_at: float = -INF


func setup(registry: PlayerRegistry, state_buffer: StateBufferManager,
		ties_getter: Callable, puck_controller_getter: Callable) -> void:
	_registry = registry
	_state_buffer = state_buffer
	_ties_getter = ties_getter
	_puck_controller_getter = puck_controller_getter


# Client side, every tick: while the local skater's stick is out in TIE, claim
# the first untied, non-carrying opponent whose rendered shaft is in reach.
func maybe_send_claim() -> void:
	if NetworkManager.is_host or not NetworkManager.is_clock_ready() or _registry == null:
		return
	var local: PlayerRecord = _registry.get_local()
	if local == null or local.skater == null or local.skater.is_ghost:
		return
	var me: Skater = local.skater
	if me.stick_check_phase != StickCheckRules.Phase.TIE:
		return
	var now: float = NetworkManager.local_time()
	if now - _last_sent_at < _RESEND_S:
		return
	var pc: PuckController = _puck_controller_getter.call() as PuckController \
			if _puck_controller_getter.is_valid() else null
	var carrier_pid: int = pc.get_client_carrier_peer_id() if pc != null else -1
	var my_team: int = _registry.team_id_by_skater.get(me, -1)
	var blade: Vector3 = me.get_blade_contact_global()
	var players: Dictionary[int, PlayerRecord] = _registry.all()
	for pid: int in players:
		var rec: PlayerRecord = players[pid]
		if rec.skater == null or rec.skater == me or pid == carrier_pid or rec.skater.stick_tied:
			continue
		if _registry.team_id_by_skater.get(rec.skater, -1) == my_team:
			continue
		var d: float = PuckInteractionRules.distance_to_shaft(blade,
				rec.skater.upper_body_to_global(rec.skater.get_top_hand_position()),
				rec.skater.get_blade_contact_global())
		if d <= StickCheckRules.TIE_ENGAGE_RADIUS_M:
			_last_sent_at = now
			# The adapted interp delay positioned the rendered shaft this frame; see
			# the pickup claim send in LocalController.
			NetworkManager.send_stick_tie_claim(NetworkManager.estimated_host_time(),
					NetworkManager.get_interpolation_delay() * 1000.0, pid, blade)
			return


func receive_claim(peer_id: int, host_timestamp: float, interp_delay_ms: float,
		input_lead_ms: float, target_peer_id: int, client_blade_curr: Vector3) -> void:
	if not _ties_getter.is_valid() or _registry == null:
		return
	var ties: StickTieTracker = _ties_getter.call() as StickTieTracker
	if ties == null:
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
	var blade_rewind_time: float = LagCompRewind.self_view_time(host_timestamp, input_lead_ms)
	var shaft_rewind_time: float = LagCompRewind.remote_view_time(host_timestamp, interp_delay_ms)
	var shaft_snap: WorldSnapshot = _state_buffer.get_state_at(shaft_rewind_time)
	if shaft_snap.puck_state != null and shaft_snap.puck_state.carrier_peer_id == target_peer_id:
		return
	var victim_snap: SkaterNetworkState = shaft_snap.get_skater_state(target_peer_id)
	if victim_snap == null:
		return
	var shaft_top: Vector3 = victim_snap.top_hand_world
	var shaft_blade: Vector3 = victim_snap.blade_contact_world
	if LagCompRewind.forward_predict_skater(victim_snap,
			target.controller as SkaterController, interp_delay_ms, input_lead_ms,
			_fp_result):
		var delta: Vector3 = _fp_result.position - victim_snap.position
		shaft_top += delta
		shaft_blade += delta
	var blade_snap: WorldSnapshot = _state_buffer.get_state_at(blade_rewind_time)
	var attacker_snap: SkaterNetworkState = blade_snap.get_skater_state(peer_id)
	if attacker_snap == null or attacker_snap.is_ghost:
		return
	if attacker_snap.stick_check_phase != StickCheckRules.Phase.TIE:
		return
	if not _claimant.resolve(_registry, peer_id, attacker_snap,
			record.controller as SkaterController,
			blade_rewind_time, _state_buffer.newest_host_timestamp()):
		return
	var attacker_blade: Vector3 = _claimant.clamp_blade(client_blade_curr, attacker_snap)
	if PuckInteractionRules.distance_to_shaft(attacker_blade, shaft_top, shaft_blade) \
			> StickCheckRules.TIE_ENGAGE_RADIUS_M:
		return
	ties.try_engage(record.skater, target.skater)

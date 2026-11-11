extends GutTest

# StickTieClaimResolver.receive_claim end to end on the host: a rewound buffer,
# real skaters and the real tracker. The claimant's own snapshot is caught up to
# its self-view instant (ClaimantView), and the stick it is judged by is the
# caught-up one — hand and blade both. A catch-up is non-zero only when the
# deferred queue's hold clamp releases a claim early, so the claimant view here
# is stubbed to report one rather than staged through a live controller.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const CLAIMANT: int = 1
const TARGET: int = 2
const CATCH := Vector3(0.0, 0.0, 2.0)
# Claimant's snapshot stick, before the catch-up, running along +x.
const SNAP_HAND := Vector3(0.0, 1.0, 0.0)
const SNAP_BLADE := Vector3(1.5, 0.0, 0.0)


class CaughtUpClaimant extends ClaimantView:
	var catch: Vector3 = Vector3.ZERO

	func resolve(_registry: PlayerRegistry, _peer_id: int, snap: SkaterNetworkState,
			_ctrl: SkaterController, _self_view_t: float, _newest_ts: float) -> bool:
		_catch = catch
		return snap != null


var _resolver: StickTieClaimResolver = null
var _ties: StickTieTracker = null
var _sbm: StateBufferManager = null
var _claimant: Skater = null
var _target: Skater = null
var _saved_telemetry: NetworkTelemetry = null
var _telemetry: NetworkTelemetry = null


func before_each() -> void:
	_saved_telemetry = NetworkTelemetry.instance
	_telemetry = NetworkTelemetry.new()
	NetworkTelemetry.instance = _telemetry
	_claimant = _spawn_skater()
	_target = _spawn_skater()
	_claimant.stick_check_phase = StickCheckRules.Phase.TIE
	_claimant.stick_check_held = true
	var registry := PlayerRegistry.new()
	registry._players[CLAIMANT] = _record(CLAIMANT, _claimant)
	registry._players[TARGET] = _record(TARGET, _target)
	registry._skaters_cache = [_claimant, _target] as Array[Skater]
	registry.team_id_by_skater = {_claimant: 0, _target: 1}
	_ties = StickTieTracker.new()
	_ties.setup(registry, func() -> Skater: return null)
	_sbm = StateBufferManager.new()
	_resolver = StickTieClaimResolver.new()
	_resolver.setup(registry, _sbm, func() -> StickTieTracker: return _ties, Callable())
	var view := CaughtUpClaimant.new()
	view.catch = CATCH
	_resolver._claimant = view


func after_each() -> void:
	NetworkTelemetry.instance = _saved_telemetry


func _spawn_skater() -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.set_physics_process(false)
	s.set_process(false)
	return s


func _record(peer_id: int, skater: Skater) -> PlayerRecord:
	var r := PlayerRecord.new(peer_id, 0, false, null)
	r.skater = skater
	return r


func _stick_state(hand: Vector3, blade: Vector3) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.top_hand_world = hand
	s.blade_contact_world = blade
	return s


# Two captures of the same state, both older than every instant the claim asks
# for, so each lookup answers with the newest.
func _buffer(peer_id: int, state: SkaterNetworkState, newest_ts: float) -> void:
	_sbm._alloc_skater(peer_id)
	var older := SkaterNetworkState.new()
	older.copy_from(state)
	older.copy_stick_play_from(state)
	older.host_timestamp = newest_ts - 0.011
	state.host_timestamp = newest_ts
	var buf: Array = _sbm._skater_buffers[peer_id]
	buf[0] = older
	buf[1] = state
	_sbm._skater_ptrs[peer_id] = 2
	_sbm._skater_counts[peer_id] = 2


# Stages both snapshots and sends the claim with the client's blade where its
# caught-up body put it. `target_hand` / `target_blade` place the target's stick.
func _claim(target_hand: Vector3, target_blade: Vector3) -> void:
	var now: float = NetworkManager.local_time()
	var mine := _stick_state(SNAP_HAND, SNAP_BLADE)
	mine.stick_check_phase = StickCheckRules.Phase.TIE
	_buffer(CLAIMANT, mine, now - 0.05)
	_buffer(TARGET, _stick_state(target_hand, target_blade), now - 0.05)
	_sbm._capture_count = 2
	_sbm._newest_ts = now - 0.05
	_resolver.receive_claim(CLAIMANT, now, 0.0, -1.0, TARGET, SNAP_BLADE + CATCH)


func test_a_stick_touching_the_caught_up_hand_ties() -> void:
	# The target's blade sits just off the claimant's caught-up hand. Judged by
	# the snapshot's hand instead — two metres back, at the other end of a
	# stick skewed between two instants — the two never touch.
	_claim(Vector3(-0.6, 1.0, 2.02), Vector3(-0.02, 0.0, 2.02))
	assert_true(_target.stick_tied, "the tie latches on the target")
	assert_true(_claimant.stick_tied, "and on the claimant")
	assert_eq(_telemetry._stick_tie_claim_count, 1, "the claim reached the geometry test")
	assert_eq(_telemetry._stick_tie_claim_miss_count, 0)


func test_a_stick_out_of_reach_is_a_counted_miss() -> void:
	_claim(Vector3(-1.6, 1.0, 2.5), Vector3(-1.0, 0.0, 2.5))
	assert_false(_target.stick_tied)
	assert_eq(_telemetry._stick_tie_claim_count, 1)
	assert_eq(_telemetry._stick_tie_claim_miss_count, 1, "a refused reach shows as a miss")


func test_a_teammate_is_never_claimed() -> void:
	_resolver._registry.team_id_by_skater[_target] = 0
	_claim(Vector3(-0.6, 1.0, 2.02), Vector3(-0.02, 0.0, 2.02))
	assert_false(_target.stick_tied)
	assert_eq(_telemetry._stick_tie_claim_count, 0, "refused before the geometry test")

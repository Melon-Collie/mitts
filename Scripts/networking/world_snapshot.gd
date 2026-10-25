class_name WorldSnapshot
extends RefCounted

# Flat snapshot of all actor states at a single host timestamp.
# Used by StateBufferManager.get_state_at() for lag-compensated rewind (Phase 7).

var host_timestamp: float = 0.0
var skater_states: Dictionary[int, SkaterNetworkState] = {}  # peer_id -> state
var puck_state: PuckNetworkState = null
var goalie_states: Dictionary[int, GoalieNetworkState] = {}  # team_id -> state

# AI-helper caches — populated by GameManager once per host physics frame
# on the live `current_snapshot` only. Lag-comp rewind snapshots
# (PickupClaimResolver / PokeClaimResolver) leave these empty; AI code
# shouldn't consume rewind snapshots anyway. Read via `.get(team_id, ...)`.
var teammate_ids_by_team: Dictionary[int, Array] = {}     # team_id -> Array[int] (peer_ids)
var closest_to_puck_by_team: Dictionary[int, int] = {}    # team_id -> peer_id (-1 if team empty)
# Per-skater smoothed acceleration (XZ, m/s²), a GLOBAL dead-reckoning read
# shared by every bot instead of each bot recomputing the identical velocity
# diff every tick. Populated by reference from the host's AIAccelerationTracker
# on `current_snapshot` only (empty on rewind snapshots). Read via `.get(pid,
# Vector3.ZERO)`. Feeds receiver-lead in pass scoring / PASS_PRESSED aim.
var accel_by_peer: Dictionary[int, Vector3] = {}          # peer_id -> smoothed accel
# Per-skater smoothed HEADING turn rate (rad/s, signed), the same global
# dead-reckoning shared once from AIAccelerationTracker.heading_omega_by_peer.
# The passer's "how committed is this receiver to a direction" read — a turning
# receiver is hard to lead, so a feed to one is priced as riskier in the pass EV
# (see AIPuckLane.receiver_heading_uncertainty_m). Read via `.get(pid, 0.0)`.
var heading_omega_by_peer: Dictionary[int, float] = {}    # peer_id -> smoothed turn rate
# NHL delayed offside: peers who must get back to the blue line, from
# GameManager.must_tag_up. A touch by one whistles the play, so the AI treats
# them like a ghost. Empty on rewind snapshots and outside NHL.
var tag_up_peers: Dictionary[int, bool] = {}

# Bot reaction-delay support. `puck_state.carrier_peer_id` on the AI snapshot
# carries the DEBOUNCED (delayed) carrier so all AI consumers react to
# possession changes a beat late (see GameManager._apply_bot_carrier_reaction_
# delay). This field stashes the REAL current carrier so a bot can still read
# its OWN possession instantly (proprioception — you know the moment the puck
# is on your stick). -1 = loose.
var real_puck_carrier_peer_id: int = -1

# The skater whose deliberate release the loose puck is still on: set when a
# carrier shoots or passes it, cleared by the next touch of any stick, body or
# goalie (the boards keep it), and -1 otherwise. Who RELEASED it is what anyone
# watching sees; who it was meant for is never here. AI-only, host-filled
# (GameManager._enrich_snapshot_for_ai).
var loose_puck_released_by: int = -1

func get_skater_state(peer_id: int) -> SkaterNetworkState:
	return skater_states.get(peer_id)


# Whether peer_id can't legally play the puck right now: ghosted, or must tag
# up under NHL delayed offside.
func is_out_of_play(peer_id: int) -> bool:
	if tag_up_peers.has(peer_id):
		return true
	var s: SkaterNetworkState = skater_states.get(peer_id)
	return s != null and s.is_ghost

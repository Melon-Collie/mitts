class_name WorldSnapshot
extends RefCounted

# Flat snapshot of all actor states at a single host timestamp.
# Used by StateBufferManager.get_state_at() for lag-compensated rewind (Phase 7).

var host_timestamp: float = 0.0
var skater_states: Dictionary = {}       # peer_id -> SkaterNetworkState
var puck_state: PuckNetworkState = null
var goalie_states: Dictionary = {}  # team_id -> GoalieNetworkState

func get_skater_state(peer_id: int) -> SkaterNetworkState:
	return skater_states.get(peer_id)

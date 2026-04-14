class_name GameStateMachine
extends RefCounted

# Pure-domain state owned by the FSM:
#   - current phase + timer
#   - scores
#   - player slot registry (peer_id → {slot, team_id, faceoff_position})
#   - icing state + last carrier tracking
#   - ghost computation (uses InfractionRules + dead-puck check)
#
# GameManager still owns infrastructure: references to actors, the PlayerRecord
# with node refs, RPC sending, signal emission. It calls state-machine methods
# and reacts to the outcomes (what phase are we in? did something transition?).
#
# The state machine exists on both host and client. On the host, GameManager
# drives it with tick(delta). On the client, apply_remote_state() syncs it
# from world-state broadcasts.

# ── Phase + timer ────────────────────────────────────────────────────────────
var current_phase: int = GamePhase.Phase.PLAYING
var _phase_timer: float = 0.0

# ── Scores ───────────────────────────────────────────────────────────────────
var scores: Array[int] = [0, 0]
var last_scoring_team_id: int = -1

# ── Player registry (domain view) ────────────────────────────────────────────
# peer_id → { slot: int, team_id: int, faceoff_position: Vector3 }
var players: Dictionary = {}
var next_slot: int = 1  # host takes slot 0 up front

# ── Icing ────────────────────────────────────────────────────────────────────
var last_carrier_team_id: int = -1
var last_carrier_z: float = 0.0
var icing_team_id: int = -1
var _icing_timer: float = 0.0


# ── Frame tick (host only) ───────────────────────────────────────────────────
# Returns true if the phase changed this tick, so GameManager knows to fire
# phase-entry side effects.
func tick(delta: float) -> bool:
	_tick_icing(delta)
	return _tick_phase(delta)


# ── Events from infrastructure ───────────────────────────────────────────────

# Returns the scoring team id (0 or 1), or -1 if the goal is ignored (wrong phase).
func on_goal_scored(defending_team_id: int) -> int:
	if current_phase != GamePhase.Phase.PLAYING:
		return -1
	var scoring_team_id: int = 1 - defending_team_id
	scores[scoring_team_id] += 1
	last_scoring_team_id = scoring_team_id
	_set_phase(GamePhase.Phase.GOAL_SCORED)
	return scoring_team_id

# Called when a puck is picked up during FACEOFF phase. Returns true if it
# caused the transition back to PLAYING.
func on_faceoff_puck_picked_up() -> bool:
	if current_phase != GamePhase.Phase.FACEOFF:
		return false
	_set_phase(GamePhase.Phase.PLAYING)
	return true

# Host-side: called every physics frame while the puck has a carrier. Tracks
# carrier info for icing detection. Any pickup clears active icing (opponent
# pickup instantly resets; same-team pickup just refreshes the tracker).
func notify_puck_carried(carrier_team_id: int, carrier_z: float) -> void:
	last_carrier_team_id = carrier_team_id
	last_carrier_z = carrier_z
	if icing_team_id != -1:
		icing_team_id = -1
		_icing_timer = 0.0

# Host-side: called every physics frame when the puck is loose. Detects icing
# and starts the ghost timer.
func check_icing_for_loose_puck(puck_z: float) -> void:
	if current_phase != GamePhase.Phase.PLAYING:
		return
	if icing_team_id != -1:
		return
	var offender: int = InfractionRules.check_icing(last_carrier_team_id, last_carrier_z, puck_z)
	if offender != -1:
		icing_team_id = offender
		_icing_timer = GameRules.ICING_GHOST_DURATION
		last_carrier_team_id = -1

# Host-side: compute ghost state for all players. Returns {peer_id: should_ghost}.
func compute_ghost_state(
		player_positions: Dictionary,
		puck_carrier_peer_id: int,
		puck_position: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var is_active_play: bool = (current_phase == GamePhase.Phase.PLAYING
			or current_phase == GamePhase.Phase.FACEOFF)
	for peer_id in player_positions:
		if not players.has(peer_id):
			result[peer_id] = false
			continue
		var slot: Dictionary = players[peer_id]
		var ghost: bool = false
		if is_active_play:
			var is_carrier: bool = peer_id == puck_carrier_peer_id
			if InfractionRules.is_offside(
					player_positions[peer_id].z, slot.team_id,
					puck_position.z, is_carrier):
				ghost = true
			elif icing_team_id == slot.team_id:
				ghost = true
		result[peer_id] = ghost
	return result


# ── Player registry ──────────────────────────────────────────────────────────

# Call once at host startup to assign slot 0.
# Returns { slot: int, team_id: int }.
func register_host(peer_id: int) -> Dictionary:
	var team_id: int = PlayerRules.assign_team(
			count_players_on_team(0), count_players_on_team(1))
	players[peer_id] = {
		"slot": 0,
		"team_id": team_id,
		"faceoff_position": PlayerRules.faceoff_position_for_slot(0),
	}
	return {"slot": 0, "team_id": team_id}

# Call for each non-host peer that connects.
# Returns { slot: int, team_id: int }.
func on_player_connected(peer_id: int) -> Dictionary:
	var slot: int = next_slot
	next_slot += 1
	var team_id: int = PlayerRules.assign_team(
			count_players_on_team(0), count_players_on_team(1))
	players[peer_id] = {
		"slot": slot,
		"team_id": team_id,
		"faceoff_position": PlayerRules.faceoff_position_for_slot(slot),
	}
	return {"slot": slot, "team_id": team_id}

# Called by remote clients when they receive a slot assignment RPC. Takes a
# pre-assigned slot+team_id rather than computing them.
func register_remote_assigned_player(peer_id: int, slot: int, team_id: int) -> void:
	players[peer_id] = {
		"slot": slot,
		"team_id": team_id,
		"faceoff_position": PlayerRules.faceoff_position_for_slot(slot),
	}

func on_player_disconnected(peer_id: int) -> void:
	players.erase(peer_id)

func count_players_on_team(team_id: int) -> int:
	var count: int = 0
	for peer_id in players:
		if players[peer_id].team_id == team_id:
			count += 1
	return count


# ── Reset ────────────────────────────────────────────────────────────────────

func reset_scores() -> void:
	scores[0] = 0
	scores[1] = 0

# Transitions to FACEOFF_PREP and clears icing state. Used by manual reset and
# after goals (the goal path is driven automatically by tick timer).
func begin_faceoff_prep() -> void:
	icing_team_id = -1
	_icing_timer = 0.0
	last_carrier_team_id = -1
	_set_phase(GamePhase.Phase.FACEOFF_PREP)


# ── Remote state application (clients) ──────────────────────────────────────
# World-state broadcasts carry authoritative phase + scores. Returns true if
# the phase changed (so GameManager can emit phase_changed, lock/unlock puck).

func apply_remote_state(score0: int, score1: int, phase: int) -> bool:
	scores[0] = score0
	scores[1] = score1
	if phase == current_phase:
		return false
	current_phase = phase
	_phase_timer = 0.0
	return true

# Called on clients when they receive the goal RPC directly (arrives before
# world state most of the time).
func apply_remote_goal(scoring_team_id: int, score0: int, score1: int) -> void:
	scores[0] = score0
	scores[1] = score1
	last_scoring_team_id = scoring_team_id
	if current_phase != GamePhase.Phase.GOAL_SCORED:
		current_phase = GamePhase.Phase.GOAL_SCORED
		_phase_timer = 0.0


# ── Queries ──────────────────────────────────────────────────────────────────

func is_movement_locked() -> bool:
	return PhaseRules.is_movement_locked(current_phase)

# Returns { peer_id: Vector3 } — each player's faceoff position for their slot.
func get_faceoff_positions() -> Dictionary:
	var result: Dictionary = {}
	for peer_id in players:
		result[peer_id] = players[peer_id].faceoff_position
	return result


# ── Internal ─────────────────────────────────────────────────────────────────

func _set_phase(phase: int) -> void:
	current_phase = phase
	_phase_timer = 0.0

func _tick_phase(delta: float) -> bool:
	if current_phase == GamePhase.Phase.PLAYING:
		return false
	_phase_timer += delta
	match current_phase:
		GamePhase.Phase.GOAL_SCORED:
			if _phase_timer >= GameRules.GOAL_PAUSE_DURATION:
				_set_phase(GamePhase.Phase.FACEOFF_PREP)
				return true
		GamePhase.Phase.FACEOFF_PREP:
			if _phase_timer >= GameRules.FACEOFF_PREP_DURATION:
				_set_phase(GamePhase.Phase.FACEOFF)
				return true
		GamePhase.Phase.FACEOFF:
			if _phase_timer >= GameRules.FACEOFF_TIMEOUT:
				_set_phase(GamePhase.Phase.PLAYING)
				return true
	return false

func _tick_icing(delta: float) -> void:
	if icing_team_id == -1:
		return
	_icing_timer -= delta
	if _icing_timer <= 0.0:
		icing_team_id = -1

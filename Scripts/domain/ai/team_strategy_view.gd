class_name TeamStrategyView
extends RefCounted

# Read-only team-strategy surface the AI role behaviors consume during dispatch.
# Implemented by TeamBrain (the live node, read directly when no frozen view
# exists, e.g. unit tests) and TeamBrainView (the frozen per-batch copy the
# dispatch normally reads). RoleContext.team_brain holds one of these. The
# defaults below are the "no strategy" neutral of an unwired context.

func get_slot(_peer_id: int) -> int:
	return AIRoleSlots.Slot.NONE

func strong_x() -> float:
	return 1.0

func carrier_lane() -> int:
	return 0

func assigned_threat(_peer_id: int) -> int:
	return -1

func position_of(_peer_id: int) -> int:
	return 0

func is_one_timer_ready(_peer_id: int) -> bool:
	return false

func ping_move_target(_peer_id: int) -> Vector3:
	return Vector3.INF

func ping_shoot(_peer_id: int) -> bool:
	return false

func ping_pass_target(_peer_id: int) -> int:
	return -1

# Team-scoped (not per-peer): at most one bot is under a GET_PUCK retrieval order
# at a time, so the view freezes the ordered peer as a scalar rather than a dict.
func ping_chase_peer() -> int:
	return -1

func get_team_size() -> int:
	return GameRules.DEFAULT_TEAM_SIZE

# Whether the match calls icing (the NHL rule set).
func icing_enforced() -> bool:
	return false

func get_threat_shoot_base_by_opp() -> Dictionary[int, float]:
	return {}

# Inert transition read (Mode.NONE, no attackers) for an unwired context.
# Shared across every instance, so it must never be mutated.
static var _inert_rush_read := AIRushRead.new()

func get_rush_read() -> AIRushRead:
	return _inert_rush_read

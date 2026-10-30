class_name TeamBrainView
extends TeamStrategyView

# Frozen copy of a TeamBrain's outputs, refilled (never reallocated) by
# TeamBrain.build_view on the AI worker right after the brain tick and before
# the agents decide, so no mutex is needed (see Scripts/ai/CLAUDE.md → "The
# agents do not read the live brain").
#
# Storage is public so TeamBrain.build_view can fill it directly; consumers read
# through the TeamStrategyView interface methods below.

var strong_x_val: float = 1.0
var carrier_lane_val: int = 0
var team_size_val: int = GameRules.DEFAULT_TEAM_SIZE
var icing_enforced_val: bool = false
var ping_chase_peer_val: int = -1
var slot_by_peer: Dictionary[int, int] = {}
var assigned_threat_by_peer: Dictionary[int, int] = {}
var position_by_peer: Dictionary[int, int] = {}
var one_timer_ready_by_peer: Dictionary[int, bool] = {}
var ping_move_by_peer: Dictionary[int, Vector3] = {}
var ping_shoot_by_peer: Dictionary[int, bool] = {}
var ping_pass_by_peer: Dictionary[int, int] = {}
var threat_shoot_base: Dictionary[int, float] = {}
# Refilled in place via AIRushRead.copy_from.
var rush: AIRushRead = AIRushRead.new()


func get_slot(peer_id: int) -> int:
	return slot_by_peer.get(peer_id, AIRoleSlots.Slot.NONE)


func strong_x() -> float:
	return strong_x_val


func carrier_lane() -> int:
	return carrier_lane_val


func assigned_threat(peer_id: int) -> int:
	return assigned_threat_by_peer.get(peer_id, -1)


func position_of(peer_id: int) -> int:
	return position_by_peer.get(peer_id, 0)


func is_one_timer_ready(peer_id: int) -> bool:
	return one_timer_ready_by_peer.get(peer_id, false)


func ping_move_target(peer_id: int) -> Vector3:
	return ping_move_by_peer.get(peer_id, Vector3.INF)


func ping_shoot(peer_id: int) -> bool:
	return ping_shoot_by_peer.get(peer_id, false)


func ping_pass_target(peer_id: int) -> int:
	return ping_pass_by_peer.get(peer_id, -1)


func ping_chase_peer() -> int:
	return ping_chase_peer_val


func get_team_size() -> int:
	return team_size_val


func icing_enforced() -> bool:
	return icing_enforced_val


func get_threat_shoot_base_by_opp() -> Dictionary[int, float]:
	return threat_shoot_base


func get_rush_read() -> AIRushRead:
	return rush

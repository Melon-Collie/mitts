class_name FeatTracker
extends RefCounted
## Host-only memory of who won the current possession back, for the feats a goal
## on it earns (FeatRules.PICK_AND_FINISH / STRIP_AND_FINISH). TurnoverTracker
## reports a won possession as it credits the takeaway or interception; the
## possession ends when the other team establishes one, or at a stoppage.

var _registry: PlayerRegistry = null
var _won_by: int = -1
var _won_kind: String = ""
var _won_team: int = -1


func setup(registry: PlayerRegistry) -> void:
	_registry = registry


func on_possession_won(peer_id: int, kind: String) -> void:
	_won_by = peer_id
	_won_kind = kind
	_won_team = _registry.resolve_team_id_for_peer(peer_id) if _registry != null else -1


func on_possession_established(_peer_id: int, team_id: int) -> void:
	if team_id != _won_team:
		reset()


func reset() -> void:
	_won_by = -1
	_won_kind = ""
	_won_team = -1


# Fills the won-possession part of `ctx` when the scoring team still holds the
# possession it won.
func fill(ctx: GoalFeatContext, scoring_team_id: int) -> void:
	if _won_by != -1 and _won_team == scoring_team_id:
		ctx.won_by = _won_by
		ctx.won_kind = _won_kind

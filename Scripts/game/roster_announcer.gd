class_name RosterAnnouncer
extends RefCounted

# Turns roster changes into HUD ticker lines ("JONES joined", "JONES now
# spectating") in the team's UI palette. Runs on every peer off the same
# registry events, so host and clients toast the same moments.
#
# A move between the ice and the spectator gallery reaches the registry as an
# ordinary despawn / spawn; `is_spectator` is what tells it apart from a leave
# or a join. The owner therefore marks a peer a spectator BEFORE despawning them
# and clears the mark only AFTER spawning them. A client learns of a spectator
# only from a demotion broadcast, so one who chose the gallery in the lobby
# reads as "joined" there when promoted.

signal announced(player_name: String, detail_key: StringName, team_colors: Dictionary)

var _is_spectator: Callable


func _init(player_added: Signal, player_removed: Signal, is_spectator: Callable) -> void:
	_is_spectator = is_spectator
	player_added.connect(_on_player_added)
	player_removed.connect(_on_player_removed)


# Call after the swap is applied, so `record.team` is the team they moved to.
# A slot change within a team is not announced.
func on_swap_confirmed(record: PlayerRecord, old_team_id: int) -> void:
	if record == null or record.is_local or record.team.team_id == old_team_id:
		return
	_announce(record, &"TOAST_PLAYER_SWITCHED_TEAMS")


func _on_player_added(record: PlayerRecord) -> void:
	if record.is_local:
		return
	_announce(record, &"TOAST_PLAYER_NOW_PLAYING" if _is_spectator.call(record.peer_id)
			else &"TOAST_PLAYER_JOINED")


func _on_player_removed(record: PlayerRecord) -> void:
	if record.is_local:
		return
	_announce(record, &"TOAST_PLAYER_SPECTATING" if _is_spectator.call(record.peer_id)
			else &"TOAST_PLAYER_LEFT")


func _announce(record: PlayerRecord, detail_key: StringName) -> void:
	announced.emit(record.display_name(), detail_key,
			TeamColorRegistry.get_ui_colors(record.team.color_slot, record.team.team_id))

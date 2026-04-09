class_name PlayerRecord

var peer_id: int = 0
var slot: int = 0
var skater: Skater = null
var controller: SkaterController = null
var is_local: bool = false
var team: Team = null
var faceoff_position: Vector3 = Vector3.ZERO

func _init(p_peer_id: int, p_slot: int, p_is_local: bool, p_team: Team) -> void:
	peer_id = p_peer_id
	slot = p_slot
	is_local = p_is_local
	team = p_team

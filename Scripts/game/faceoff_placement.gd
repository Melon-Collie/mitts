class_name FaceoffPlacement
extends RefCounted

# Who stands where when play stops: the reads PhaseCoordinator places a
# faceoff from. Most skaters are cast into the faceoff's spots
# (FaceoffFormation); one in the penalty box goes to his door, and when a
# penalty shot is set up in the faceoff's place the shooter goes to centre and
# everyone else to his bench. Reads the registry and the skaters' flags, which
# PenaltyTracker sets from the ledger on every peer; moves nothing.

var _registry: PlayerRegistry = null


func _init(registry: PlayerRegistry) -> void:
	_registry = registry


# Each team's FaceoffFormation.cast over the seats `peer_ids` hold, indexed by
# team id. A boxed skater holds no seat.
func casts(peer_ids: Array[int]) -> Array[PackedInt32Array]:
	var on_ice: Array[int] = [0, 0]
	for peer_id: int in peer_ids:
		var record: PlayerRecord = _registry.get_record(peer_id) \
				if _registry.has(peer_id) else null
		if record != null and record.team != null and not is_boxed(record):
			on_ice[record.team.team_id] |= FaceoffFormation.seat_bit(record.team_slot)
	return [FaceoffFormation.cast(on_ice[0]), FaceoffFormation.cast(on_ice[1])]


func spot(team_casts: Array[PackedInt32Array], record: PlayerRecord) -> int:
	return team_casts[record.team.team_id][record.team_slot]


# Sitting out a penalty: skated to his box's door, and no part of the faceoff.
func is_boxed(record: PlayerRecord) -> bool:
	return record != null and record.skater != null and record.skater.in_box


# Taking a penalty shot, or stood at his bench while one is taken.
func in_penalty_shot(record: PlayerRecord) -> bool:
	return record != null and record.skater != null \
			and (record.skater.takes_penalty_shot or record.skater.sidelined)


func penalty_shot_is_staged() -> bool:
	for peer_id: int in _registry.all():
		var record: PlayerRecord = _registry.get_record(peer_id)
		if record != null and record.skater != null and record.skater.takes_penalty_shot:
			return true
	return false


# Where a skater in a penalty shot stands for it.
func penalty_shot_spot(record: PlayerRecord) -> Vector3:
	if record.skater.takes_penalty_shot:
		return PlayerRules.penalty_shot_start()
	return PlayerRules.bench_start_position(record.team.team_id, record.team_slot)


# Which way a skater placed off the faceoff ends up facing.
func held_out_facing(record: PlayerRecord) -> Vector2:
	if record.skater.in_box:
		return PlayerRules.penalty_box_facing()
	if record.skater.takes_penalty_shot:
		return PlayerRules.faceoff_facing(record.team.team_id)
	return PlayerRules.bench_facing()

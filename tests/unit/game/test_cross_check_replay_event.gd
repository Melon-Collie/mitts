extends GutTest

# A landed cross-check replays as the live broadcast plays it
# (ReplayEventReplayer's "cross_check" kind): the burst on the shoved skater at
# the hardness of the stagger it landed, and nothing for a shove he held.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")


func _victim_records() -> Dictionary:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	var rec := PlayerRecord.new(7, 0, false, null)
	rec.skater = skater
	return {7: rec}


func _event(dv: float) -> Dictionary:
	return {"kind": "cross_check", "pos": [0.0, 0.0, 0.0], "speed": dv,
			"victim_peer_id": 7, "push_dir": [1.0, 0.0, 0.0]}


func _burst(records: Dictionary) -> CPUParticles3D:
	var vfx: SkaterVFX = (records[7] as PlayerRecord).skater.get_node("VFX") as SkaterVFX
	return vfx._body_check_burst


func test_a_landed_shove_bursts_on_the_man_it_moved() -> void:
	var records: Dictionary = _victim_records()
	ReplayEventReplayer.dispatch_with_records(_event(1.2), records)
	assert_true(_burst(records).emitting)


func test_a_held_shove_replays_nothing() -> void:
	var records: Dictionary = _victim_records()
	ReplayEventReplayer.dispatch_with_records(_event(0.2), records)
	assert_false(_burst(records).emitting)

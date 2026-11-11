extends GutTest

# A client's goalie predictor (KeeperPredictor, #903) steps a keeper of its own
# against a shadow world built from the client's game (GameKeeperWorld), and
# nothing it does reaches that game: the real puck, its controller and the
# skaters keep every value and emit nothing, however far he is stepped, and his
# shadow nodes join no group the game finds actors by.

const Harness := preload("res://tests/harness/keeper_play_harness.gd")

var _heard: int = 0


func _hear() -> void:
	_heard += 1


# Every signal `o` has, script and engine, heard.
func _spy_on(o: Object) -> void:
	for sig: Dictionary in o.get_signal_list():
		var args: int = (sig["args"] as Array).size()
		o.connect(String(sig["name"]), _hear.unbind(args) if args > 0 else _hear)


func test_the_game_is_untouched_by_his_steps() -> void:
	var host := Harness.new(add_child_autofree)
	var puck: Puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var pc := PuckController.new()
	add_child_autofree(pc)
	pc.set_physics_process(false)
	pc.setup(puck, false)
	var skater: Skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	skater.global_position = Vector3(0.0, 0.0, Harness.GOAL_Z + 6.0)
	var registry := PlayerRegistry.new()
	var record := PlayerRecord.new(7, 0, false, null)
	record.skater = skater
	registry._players[7] = record
	registry.peer_id_by_skater[skater] = 7
	registry._rebuild_skaters_cache()
	# A loose puck sliding at his net, as the newest snapshot has it.
	var snap := PuckNetworkState.new()
	snap.position = Vector3(1.0, puck.ice_height, Harness.GOAL_Z + 8.0)
	snap.velocity = Vector3(-1.0, 0.0, -12.0)
	snap.carrier_peer_id = -1
	puck.global_position = Vector3(3.0, 0.2, 4.0)

	var pred := KeeperPredictor.new()
	add_child_autofree(pred)
	pred.setup(Harness.GOAL_Z, -1, GoalieSkillProfile.hard(), GameKeeperWorld.new(pc, registry))
	_spy_on(puck)
	_spy_on(pc)
	_spy_on(skater)
	var puck_was := [puck.global_position, puck.linear_velocity, puck.carrier, puck.pickup_locked,
			puck.motion_pinned]
	var skater_was := [skater.global_position, skater.velocity, skater.current_shot_state, skater.is_ghost]

	var drawn: int = 0
	for t: int in Harness.SETTLE_TICKS + 30:
		host.tick(Harness.Play.SLOT_SHOT, t)
		if t % 2 != 0 or t < 40:
			continue
		var blob := PackedByteArray()
		host.ctrl.append_wire_state(blob)
		pc.apply_state(snap, float(t) * Harness.DT)
		pred.offer(blob, float(t) * Harness.DT, t / 2)
		if pred.advance(float(t + 13) * Harness.DT):
			drawn += 1

	assert_gt(drawn, 50, "predicted through the play")
	assert_gt(pred.steps, 300, "and stepped well past each snapshot")
	assert_eq([puck.global_position, puck.linear_velocity, puck.carrier, puck.pickup_locked,
			puck.motion_pinned], puck_was, "the real puck as it was")
	assert_eq([skater.global_position, skater.velocity, skater.current_shot_state, skater.is_ghost],
			skater_was, "the real skater as it was")
	assert_eq(_heard, 0, "no signal from the puck, its controller or the skater")
	for n: Node in pred.find_children("*", "", true, false):
		assert_false(n.is_in_group(Puck.GROUP) or n.is_in_group("skaters"),
				"%s joins no actor group" % n.name)
	assert_eq(pred.process_mode, Node.PROCESS_MODE_DISABLED, "never processed")
	assert_false(pred.visible, "never drawn")

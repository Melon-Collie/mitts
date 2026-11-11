extends GutTest

# A called-off slapshot leaves its carrier in SKATING_WITH_PUCK with the blade
# still up and the puck held on the ice where it lay. A replay that pinned the
# puck to that blade snapped it out from under the recording; it must hold the
# recorded spot, carried along with the skater, until the pin clears.

const _PEER: int = 7
# Where the host held the puck off the skater (world XZ), well clear of the
# raised blade below.
const _HELD := Vector3(0.6, 0.0, -1.1)
const _RAISED_BLADE := Vector3(0.4, 0.9, 0.3)


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func test_a_called_off_slapshot_holds_the_recorded_puck() -> void:
	var rig: Array = _rig()
	var record: PlayerRecord = rig[0]
	var puck: Puck = rig[1]
	var from_snap: Dictionary = _snap(Vector3(0.0, 0.0, 0.0), true)
	var to_snap: Dictionary = _snap(Vector3(0.0, 0.0, -0.2), true)
	ReplayPlaybackEngine.apply_interpolated_snapshot(
			from_snap, to_snap, 0.5, 1.0 / 45.0, 1.0 / 60.0, {_PEER: record}, puck, [])
	var want: Vector3 = record.skater.global_position + _HELD
	var got: Vector3 = puck.get_puck_position()
	assert_almost_eq(Vector2(got.x, got.z), Vector2(want.x, want.z), Vector2(0.001, 0.001),
			"the puck holds the recorded spot off the skater, mid-bracket")
	assert_almost_eq(got.y, puck.ice_height, 0.001, "on the ice")


func test_a_carry_on_the_blade_still_pins_to_it() -> void:
	var rig: Array = _rig()
	var record: PlayerRecord = rig[0]
	var puck: Puck = rig[1]
	var snap: Dictionary = _snap(Vector3.ZERO, false)
	ReplayPlaybackEngine.apply_interpolated_snapshot(
			snap, snap, 0.5, 1.0 / 45.0, 1.0 / 60.0, {_PEER: record}, puck, [])
	var contact: Vector3 = record.skater.get_blade_contact_global()
	var got: Vector3 = puck.get_puck_position()
	assert_almost_eq(Vector2(got.x, got.z), Vector2(contact.x, contact.z), Vector2(0.001, 0.001),
			"unpinned, the puck rides the blade")
	assert_gt(Vector2(got.x, got.z).distance_to(Vector2(_HELD.x, _HELD.z)), 0.3,
			"the test's blade sits away from the held spot, so the two cases differ")


# One recorded frame of the recovery: the carrier skating with the puck, the
# blade raised, the puck at _HELD off him, the pin bit as given.
func _snap(at: Vector3, pinned: bool) -> Dictionary:
	var s := SkaterNetworkState.new()
	s.position = Vector3(at.x, GameRules.FACEOFF_SPAWN_HEIGHT, at.z)
	s.velocity = Vector3(0.0, 0.0, -9.0)
	s.facing = Vector2(0.0, -1.0)
	s.shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	s.blade_position = _RAISED_BLADE
	s.top_hand_position = Vector3(0.2, 0.3, 0.0)
	s.slapshot_pinned = pinned
	s.slapshot_pin_offset = Vector2(_HELD.x, _HELD.z)
	var p := PuckNetworkState.new()
	p.position = s.position + _HELD
	p.carrier_peer_id = _PEER
	return {"skaters": {_PEER: s}, "puck": p, "goalies": [], "carrier_peer_id": _PEER}


# A live skater, its controller and the puck, still, for the engine to pose.
func _rig() -> Array:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var game_state := StubGameState.new()
	add_child_autofree(game_state)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, game_state)
	controller.set_process(false)
	controller.set_physics_process(false)
	var record := PlayerRecord.new(_PEER, 0, false, null)
	record.skater = skater
	record.controller = controller
	return [record, puck]

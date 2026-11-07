extends GutTest

# A loose-puck snapshot stamped a hair after this client's estimate of
# host-present is the freshest data there is, not a stale one. On a LAN or
# same-machine session the clock's error exceeds the one-way trip, so packets
# land "from the future" routinely; dropping each into the interpolation
# fallback drew the puck a whole interpolation delay back for that packet.

const ClockSyncScript: GDScript = preload("res://Scripts/networking/clock_sync.gd")
const PUCK_SPEED: float = 10.0

var _saved_clock: RefCounted = null


func before_each() -> void:
	_saved_clock = NetworkManager._clock_sync
	var clock: RefCounted = ClockSyncScript.new()
	clock.is_ready = true
	NetworkManager._clock_sync = clock


func after_each() -> void:
	NetworkManager._clock_sync = _saved_clock


func _pc() -> PuckController:
	var pc := PuckController.new()
	var puck := Puck.new()
	add_child_autofree(puck)
	autofree(pc)
	pc.setup(puck, false)
	return pc


func _loose_at(pc: PuckController, host_ts: float) -> void:
	var state := PuckNetworkState.new()
	state.position = Vector3(0.0, pc.puck.ice_height, 0.0)
	state.velocity = Vector3(PUCK_SPEED, 0.0, 0.0)
	pc.apply_state(state, host_ts)


func test_a_snapshot_ahead_of_the_clock_is_predicted() -> void:
	var pc := _pc()
	_loose_at(pc, NetworkManager.estimated_host_time() + 0.003)
	assert_true(pc._predict_loose(1.0 / float(Constants.PHYSICS_TICK)),
			"a snapshot 3 ms past host-present drives the prediction")
	assert_gt(pc._sim_pos.x, 0.0, "and the puck is predicted ahead of it, not held")


func test_a_snapshot_ahead_of_an_unready_clock_falls_back() -> void:
	# Before sync the host-time estimate means nothing, so a "future" stamp is
	# no evidence of freshness.
	NetworkManager._clock_sync.is_ready = false
	var pc := _pc()
	_loose_at(pc, 1000.0)
	assert_false(pc._predict_loose(1.0 / float(Constants.PHYSICS_TICK)))

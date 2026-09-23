extends GutTest

# PuckController's release seed — the shooter's own shot, predicted from the
# client's release until the host's snapshots carry the flight. The seed must be
# stamped on the clock the prediction renders at: stamped at host-present while
# predicting to host-present + input lead, the puck left the stick a lead's worth
# of flight ahead of the blade (~1 m at shot speed) and was pulled back at the
# snapshot handover.

const SHOT_SPEED: float = 40.0


func _pc() -> PuckController:
	var pc := PuckController.new()
	var puck := Puck.new()
	add_child_autofree(puck)
	autofree(pc)
	pc.setup(puck, false)  # the client path: builds the prediction scratch
	return pc


func test_released_puck_starts_at_the_blade() -> void:
	var pc := _pc()
	var blade := Vector3(3.0, pc.puck.ice_height, -5.0)
	pc.puck.set_puck_position(blade)
	var release_pos: Vector3 = pc.notify_local_release(Vector3.FORWARD, SHOT_SPEED)
	assert_true(pc._predict_loose(1.0 / float(Constants.PHYSICS_TICK)),
			"the seed drives the loose puck on the release frame")
	assert_lt(pc._sim_pos.distance_to(release_pos), 0.01,
			"zero flight on the release frame — the seed and the render share one clock")


func test_released_nudge_starts_at_the_blade() -> void:
	var pc := _pc()
	var blade := Vector3(-2.0, pc.puck.ice_height, 8.0)
	pc.puck.set_puck_position(blade)
	pc.notify_local_nudge(Vector3(0.0, 0.0, 6.0))
	assert_true(pc._predict_loose(1.0 / float(Constants.PHYSICS_TICK)))
	assert_lt(pc._sim_pos.distance_to(blade), 0.01,
			"a nudge seeds on the same clock as a shot")

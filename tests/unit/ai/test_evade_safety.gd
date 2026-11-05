extends GutTest

# AICarrySpace.evade_safety is the evadability read at the max-clearance seam;
# its early stop must never change the answer the seam itself gives.


func test_it_reads_what_the_seam_reads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for trial: int in 200:
		var carrier := Vector3(rng.randf_range(-13.0, 13.0), 0.0, rng.randf_range(-29.0, 29.0))
		var vel := Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		var opps: Array[Vector3] = []
		var vels: Array[Vector3] = []
		for _k: int in rng.randi_range(0, 5):
			opps.append(carrier + Vector3(rng.randf_range(-5.0, 5.0), 0.0,
					rng.randf_range(-5.0, 5.0)))
			vels.append(Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0)))
		var reach: float = AIBotMechanics.EVADE_CARRY_HANDLE_M
		var seam: Vector3 = AICarrySpace.best_evade_point(carrier, vel, opps, vels, reach)
		var expected: float = AICarrySpace.clearance_to_safety(AICarrySpace.reach_clearance(
				seam, AICarrySpace.EVADE_HORIZON_S, opps, vels))
		assert_almost_eq(AICarrySpace.evade_safety(carrier, vel, opps, vels, reach),
				expected, 1e-6, "trial %d" % trial)


func test_open_ice_is_fully_safe_and_a_man_on_the_puck_is_not() -> void:
	var none: Array[Vector3] = []
	var at := Vector3(0.0, 0.0, -10.0)
	assert_eq(AICarrySpace.evade_safety(at, Vector3.ZERO, none, none,
			AIBotMechanics.EVADE_CARRY_HANDLE_M), 1.0, "nobody near")
	var on_him: Array[Vector3] = [at + Vector3(0.6, 0.0, 0.0), at + Vector3(-0.6, 0.0, 0.0)]
	var still: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	assert_lt(AICarrySpace.evade_safety(at, Vector3.ZERO, on_him, still,
			AIBotMechanics.EVADE_CARRY_HANDLE_M), 1.0, "two men on him")

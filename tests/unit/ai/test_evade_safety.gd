extends GutTest

# AIEvadeRead.evade_safety is the evadability read at the max-clearance seam;
# its early stop must never change the answer the seam itself gives.


func test_it_reads_what_the_seam_reads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	# Defenders standing, drifting under the shed speed and skating past it, the
	# league build and their own; carriers out on the ice and against the boards.
	for trial: int in 600:
		var carrier := Vector3(rng.randf_range(-14.5, 14.5), 0.0, rng.randf_range(-29.5, 29.5))
		var vel := Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		var opps: Array[Vector3] = []
		var vels: Array[Vector3] = []
		var caps: Array = []
		var built: bool = trial % 2 == 1
		for _k: int in rng.randi_range(0, 5):
			opps.append(carrier + Vector3(rng.randf_range(-5.0, 5.0), 0.0,
					rng.randf_range(-5.0, 5.0)))
			var pace: float = [0.0, 1.5, 6.0][rng.randi_range(0, 2)]
			vels.append(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
					.normalized() * pace)
			var c := AISkaterCaps.new()
			c.max_accel = rng.randf_range(8.0, 16.0)
			c.blade_span = rng.randf_range(1.4, 2.2)
			c.max_speed = rng.randf_range(7.0, 10.0)
			c.lateral_grip = rng.randf_range(0.7, 1.3)
			caps.append(c if built else null)
		var reach: float = AIBotMechanics.EVADE_CARRY_HANDLE_M
		var seam: Vector3 = AICarrySpace.best_evade_point(carrier, vel, opps, vels, reach, caps)
		var expected: float = AICarrySpace.clearance_to_safety(AICarrySpace.reach_clearance(
				seam, AICarrySpace.EVADE_HORIZON_S, opps, vels, caps))
		assert_almost_eq(AIEvadeRead.evade_safety(carrier, vel, opps, vels, reach, caps),
				expected, 1e-6, "trial %d" % trial)


func test_open_ice_is_fully_safe_and_a_man_on_the_puck_is_not() -> void:
	var none: Array[Vector3] = []
	var at := Vector3(0.0, 0.0, -10.0)
	assert_eq(AIEvadeRead.evade_safety(at, Vector3.ZERO, none, none,
			AIBotMechanics.EVADE_CARRY_HANDLE_M), 1.0, "nobody near")
	var on_him: Array[Vector3] = [at + Vector3(0.6, 0.0, 0.0), at + Vector3(-0.6, 0.0, 0.0)]
	var still: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	assert_lt(AIEvadeRead.evade_safety(at, Vector3.ZERO, on_him, still,
			AIBotMechanics.EVADE_CARRY_HANDLE_M), 1.0, "two men on him")

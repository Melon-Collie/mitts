extends GutTest

# ── One skater's whole frame (report-only; NOT in the default suite) ──────────
# The physics tick (SkaterController._process_input) and the render pass
# (Skater._process: the gait, the head, the off hand, the spine and the contact
# seat, the arm and stick rebuild, the flex, the world HUD), driven by real
# input through each locomotion state, so every cache sees the state change it
# sees in a match. The micro-benchmarks time one call against a held state;
# this is the number that scales with the skaters on the ice.
#
# The rows under each frame time one more call of a part on its own, cache
# cleared, as the frame left it: what that part costs when it has work.
#
# Run explicitly:
#   bash .claude/hooks/run-gut.sh -gdir=res://benchmarks -gselect=test_skater_frame
#
# The host is noisy (±20% run to run): compare alternating runs.

const DT: float = 1.0 / 120.0
const WARMUP: int = 300
const FRAMES: int = 1200


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _sum: Dictionary = {}


func _timed(key: String, fn: Callable) -> void:
	var t0: int = Time.get_ticks_usec()
	fn.call()
	_sum[key] = _sum.get(key, 0) + (Time.get_ticks_usec() - t0)


func _frame(label: String, steer: Callable) -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 20.0)
	sk.set_process(false)
	sk.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(sk, puck, state)
	c.set_process(false)
	c.set_physics_process(false)
	c._pose.facing = Vector2(0.0, -1.0)
	sk.set_facing(Vector2(0.0, -1.0))
	var input := InputState.new()
	for i: int in WARMUP + FRAMES:
		if i == WARMUP:
			_sum = {}
		steer.call(input, i, sk.velocity)
		input.mouse_world_pos += sk.global_position
		input.mouse_world_pos.y = 0.0
		input.delta = DT
		_timed("tick", func() -> void: c._process_input(input, DT))
		sk.global_position += sk.velocity * DT
		_timed("render", func() -> void: sk._process(DT))
		var hips: Transform3D = sk._legs._skeleton.get_bone_pose(SkaterBodySkeleton.HIPS_BONE)
		_timed("  contact seat", func() -> void: sk._legs.seat_on_ice(hips))
		_timed("  gait", func() -> void: c._skating.apply(DT))
		_timed("  stick mesh", func() -> void: sk.update_stick_mesh())
		_timed("  bottom-hand IK", func() -> void: c._ik.update_bottom_hand())
		_timed("  arms", func() -> void:
			sk.update_arm_mesh()
			sk.update_bottom_arm_mesh())
	var tick: float = float(_sum["tick"]) / FRAMES
	var render: float = float(_sum["render"]) / FRAMES
	var line: String = "%-11s tick %6.1f  render %6.1f  =  %6.1f µs |" % [label, tick, render, tick + render]
	for k: String in ["  contact seat", "  gait", "  stick mesh", "  bottom-hand IK", "  arms"]:
		line += " %s %.1f" % [k.strip_edges(), float(_sum[k]) / FRAMES]
	gut.p(line)


func test_skater_frame_by_state() -> void:
	gut.p("── One skater's frame, µs (tick + render; parts timed once more on their own) ──")
	_frame("stride", func(inp: InputState, _i: int, _v: Vector3) -> void:
		inp.move_vector = Vector2(0.0, -1.0)
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0))
	_frame("crossovers", func(inp: InputState, i: int, v: Vector3) -> void:
		var travel := Vector2(v.x, v.z)
		var t: Vector2 = travel.normalized() if travel.length() > 0.5 else Vector2(0.0, -1.0)
		inp.move_vector = (t + Vector2(-t.y, t.x) * 1.2).normalized() \
				if i > 150 and travel.length() > 2.0 else Vector2(0.0, -1.0)
		inp.mouse_world_pos = Vector3(t.x, 0.0, t.y) * 6.0)
	_frame("glide", func(inp: InputState, i: int, _v: Vector3) -> void:
		inp.move_vector = Vector2(0.0, -1.0) if i < 240 else Vector2.ZERO
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0))
	_frame("stance", func(inp: InputState, _i: int, _v: Vector3) -> void:
		inp.move_vector = Vector2(0.0, -1.0)
		inp.stance_held = true
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0))
	_frame("stop", func(inp: InputState, i: int, _v: Vector3) -> void:
		var stopping: bool = i % 360 >= 240
		inp.move_vector = Vector2.ZERO if stopping else Vector2(0.0, -1.0)
		inp.brake = stopping
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0))
	assert_true(true, "benchmark produced rows")

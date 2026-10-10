extends GutTest

# The skating body stands on its blades, in every locomotion state
# (SkaterLegRig.seat_on_ice): one is always on the ice, and in the two-footed
# stances the other is too, while a stroking foot goes where the stroke puts it
# — and none of it pops a leg. Measured on the live rig, every rendered frame, through
# the render pass the game runs, from the runner mesh's own vertices rather than
# from the edge the solve reads, so a solve that seats the wrong points fails.

const DT: float = 1.0 / 120.0
const LegBone = SkaterMeshBuilder.LegBone
const WARMUP_TICKS: int = 300
const MEASURE_TICKS: int = 300
# Contact tolerance: the runner is 7 mm wide and the solve seats its centre
# line, so an edge rolled onto the ice may sit a few millimetres under.
const CONTACT_TOL_M: float = 0.006
# The lift a stroking skate must at least show — well clear of the contact
# tolerance, so a plant that pins a foot the stroke is moving fails.
const RECOVERY_LIFT_MIN_M: float = 0.015
# The most any leg pivot may turn in one 120 Hz tick: above every stroke the gait
# skates (the hockey stop's onset, the stiffest, ~0.08), below a contact solve
# that hops between answers and pops a leg (0.14 and up).
const MAX_JOINT_STEP_RAD: float = 0.1
# A skate pushing moves back at least this much a tick (~0.12 m/s): a push runs
# several millimetres a tick, and a recovery lifting off can still drift back a
# hair as it settles.
const PUSH_BACK_MIN_M: float = 0.001


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
# The largest change any leg pivot made in one tick over the last _skate's
# measured ticks, radians: a contact solve that hops between answers pops a leg
# far faster than any stroke moves one.
var _joint_step: float = 0.0
# Over the last _skate's measured ticks, the highest a skate's runner rode while
# that skate was pushing: moving back and out from under the body.
var _push_float: float = 0.0
var _runner := PackedVector3Array()


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 20.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	# Facing up-ice, as a spawn leaves it: the cursor ahead is then reachable,
	# where from the scene's default facing it sits in the wedge behind the body
	# that freezes facing (SkaterPoseCoordinator.apply_facing).
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))
	var boot: ArrayMesh = SkaterMeshBuilder.shared_boot_assembly()
	_runner = boot.surface_get_arrays(SkaterMeshBuilder.BOOT_SURF_RUNNER)[Mesh.ARRAY_VERTEX] \
			as PackedVector3Array


# Lowest runner vertex of one skate, metres above the ice. The skeleton's own
# global_transform is stale in a hand-ticked harness, so compose by hand.
func _runner_height(left: bool) -> float:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var bone: int = SkaterBodySkeleton.LEG_BONE_OFFSET \
			+ (LegBone.FOOT_L if left else LegBone.FOOT_R)
	var xf: Transform3D = _skater.global_transform * _skater.mesh_root.transform \
			* body.transform * body.get_bone_global_pose(bone)
	var lowest: float = INF
	for v: Vector3 in _runner:
		lowest = minf(lowest, (xf * v).y)
	return lowest


# Skates `steer` for WARMUP + MEASURE ticks and returns, over the ticks from
# `measure_from` on, the lower runner's height range [min, max] in x, y and the
# higher runner's in z, w. `steer` fills the input from the tick index and the
# current velocity.
func _skate(steer: Callable, measure_from: int = WARMUP_TICKS) -> Vector4:
	var input := InputState.new()
	var lo: float = INF
	var hi: float = -INF
	var up_lo: float = INF
	var up_hi: float = -INF
	var pivots: Array[int] = [LegBone.LEG_L, LegBone.SHIN_L, LegBone.LEG_R, LegBone.SHIN_R]
	var last := PackedVector3Array()
	last.resize(pivots.size())
	_joint_step = 0.0
	_push_float = 0.0
	var skate_at: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	for i: int in WARMUP_TICKS + MEASURE_TICKS:
		steer.call(input, i, _skater.velocity)
		input.mouse_world_pos += _skater.global_position
		input.mouse_world_pos.y = 0.0
		_controller._process_input(input, DT)
		_skater.global_position += _skater.velocity * DT
		_skater._process(DT)
		for k: int in pivots.size():
			var euler: Vector3 = _skater.leg_bone_euler(pivots[k])
			if i > measure_from:
				var d: Vector3 = (euler - last[k]).abs()
				_joint_step = maxf(_joint_step, maxf(d.x, maxf(d.y, d.z)))
			last[k] = euler
		if i < measure_from:
			continue
		var left: float = _runner_height(true)
		var right: float = _runner_height(false)
		lo = minf(lo, minf(left, right))
		hi = maxf(hi, minf(left, right))
		up_lo = minf(up_lo, maxf(left, right))
		up_hi = maxf(up_hi, maxf(left, right))
		for side: int in 2:
			var at: Vector3 = _skate_in_body(side == 0)
			var moved: Vector3 = at - skate_at[side]
			if i > measure_from and moved.z > PUSH_BACK_MIN_M and moved.x * at.x > 0.0:
				_push_float = maxf(_push_float, left if side == 0 else right)
			skate_at[side] = at
	return Vector4(lo, hi, up_lo, up_hi)


# Where a skate is drawn, in the skeleton's frame (the body's heading).
func _skate_in_body(left: bool) -> Vector3:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	return body.get_bone_global_pose(SkaterBodySkeleton.LEG_BONE_OFFSET
			+ (LegBone.FOOT_L if left else LegBone.FOOT_R)).origin


func _assert_on_ice(label: String, contact: Vector4) -> void:
	gut.p("%s: lower runner %+.4f .. %+.4f m, higher %+.4f .. %+.4f m, joint step %.4f rad"
			% [label, contact.x, contact.y, contact.z, contact.w, _joint_step])
	assert_gt(contact.x, -CONTACT_TOL_M, "%s: the support blade is in the ice" % label)
	assert_lt(contact.y, CONTACT_TOL_M, "%s: both blades are off the ice" % label)
	assert_lt(_joint_step, MAX_JOINT_STEP_RAD, "%s: a leg pops between frames" % label)


# A state skated on both blades: the second one is on the ice too
# (SkaterLegRig.seat_on_ice's plant).
func _assert_both_on_ice(label: String, contact: Vector4) -> void:
	_assert_on_ice(label, contact)
	assert_lt(contact.w, CONTACT_TOL_M, "%s: the second blade floats off the ice" % label)


func test_rest_stance_stands_on_the_ice() -> void:
	_assert_both_on_ice("rest", _skate(func(inp: InputState, _i: int, _v: Vector3) -> void:
		inp.move_vector = Vector2.ZERO
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0)))


# The stroke puts the second foot: the recovery lifts its skate.
func test_forward_stride_stands_on_the_ice() -> void:
	var contact: Vector4 = _skate(func(inp: InputState, _i: int, _v: Vector3) -> void:
		inp.move_vector = Vector2(0.0, -1.0)
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0))
	_assert_on_ice("stride", contact)
	assert_gt(contact.w, RECOVERY_LIFT_MIN_M, "the recovery skate comes off the ice")
	# The push drives along the ice: the stroke puts the pushing skate's runner
	# on it, edge and lean and all, rather than swinging it through the air.
	gut.p("stride: a pushing skate rode at most %.4f m off the ice" % [_push_float])
	assert_lt(_push_float, CONTACT_TOL_M, "the push is on the ice")


func test_loaded_stance_stride_stands_on_the_ice() -> void:
	_assert_on_ice("stance stride", _skate(func(inp: InputState, _i: int, _v: Vector3) -> void:
		inp.move_vector = Vector2(0.0, -1.0)
		inp.stance_held = true
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0)))


func test_glide_stands_on_the_ice() -> void:
	_assert_both_on_ice("glide", _skate(func(inp: InputState, i: int, _v: Vector3) -> void:
		inp.move_vector = Vector2(0.0, -1.0) if i < WARMUP_TICKS - 60 else Vector2.ZERO
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0)))


# A held turn at speed: crossovers under the full balance lean, the crossing
# skate stepped over.
# C-cuts keep both blades on the ice: the push sweeps out and back in along it.
func test_backward_c_cuts_stand_on_the_ice() -> void:
	_assert_both_on_ice("c-cuts", _skate(func(inp: InputState, _i: int, _v: Vector3) -> void:
		inp.move_vector = Vector2(0.0, 1.0)
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0)))


func test_crossovers_stand_on_the_ice() -> void:
	var contact: Vector4 = _skate(func(inp: InputState, i: int, v: Vector3) -> void:
		var travel := Vector2(v.x, v.z)
		var t: Vector2 = travel.normalized() if travel.length() > 0.5 else Vector2(0.0, -1.0)
		inp.move_vector = (t + Vector2(-t.y, t.x) * 1.2).normalized() \
				if i > WARMUP_TICKS / 2 and travel.length() > 2.0 else Vector2(0.0, -1.0)
		inp.mouse_world_pos = Vector3(t.x, 0.0, t.y) * 6.0)
	_assert_on_ice("crossovers", contact)
	assert_gt(contact.w, RECOVERY_LIFT_MIN_M, "the crossing skate steps over, off the ice")


# Measured once the stop has taken the legs: the stride's last recovery skate is
# still coming down for the first tenth of a second of it.
func test_hockey_stop_stands_on_the_ice() -> void:
	_assert_both_on_ice("hockey stop", _skate(func(inp: InputState, i: int, _v: Vector3) -> void:
		var stopping: bool = i >= WARMUP_TICKS
		inp.move_vector = Vector2.ZERO if stopping else Vector2(0.0, -1.0)
		inp.brake = stopping
		inp.mouse_world_pos = Vector3(0.0, 0.0, -6.0), WARMUP_TICKS + 30))


# The seat moves the visible body only: the gameplay frames the hands and
# blade hang from keep the height the crouch gave them.
func test_the_seat_leaves_the_gameplay_frame() -> void:
	var upper_y: float = _skater.upper_body.position.y
	var lower_y: float = _skater.lower_body.position.y
	_controller._render_pose_update(DT)
	assert_almost_eq(_skater.upper_body.position.y, upper_y, 1e-6)
	assert_almost_eq(_skater.lower_body.position.y, lower_y, 1e-6)
	assert_almost_eq(minf(_runner_height(true), _runner_height(false)), 0.0, CONTACT_TOL_M,
			"while the visible body stands on the ice")

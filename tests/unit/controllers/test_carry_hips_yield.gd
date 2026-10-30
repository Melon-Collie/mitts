extends GutTest

# A skating carrier's hips yield to a cursor going round the forehand
# (FacingRules.yield_on_forehand), so a fast sweep never takes the blade to the
# stop the two-hand reach puts just short of the pivot, and the pivot has little
# of the turn left to throw the puck with. Driven through the real controller,
# since the stop is the IK's.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const AHEAD := Vector2(0.0, -1.0)


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


class Sweep:
	# Where the blade's target first fell under half the cursor's angular speed,
	# degrees round the forehand off the body (INF: never).
	var stall_deg: float = INF
	var fastest_hips_deg_s: float = 0.0
	var face_changes: int = 0


# `held_on_line`: the hips never yield, as before the rule.
func _make_carrier(attrs: PlayerAttributes, held_on_line: bool) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(attrs)
	if held_on_line:
		c.carry_facing_rules.forehand_yield_rad = INF
	# Skating up the rink from the far end, so the run never reaches the boards.
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 25.0)
	puck.set_carrier(skater)
	c.on_puck_picked_up_network()
	return c


# Degrees round the forehand off `from`.
func _round(sk: Skater, from: Vector2, at: Vector3) -> float:
	var rel: Vector3 = at - sk.global_position
	return rad_to_deg(from.angle_to(Vector2(rel.x, rel.z))) \
			* FacingRules.forehand_sign(sk.is_left_handed)


# Skates ahead, then sweeps the cursor `radius_m` out from ahead round the
# forehand to `to_deg` at `deg_s`, and holds it there half a second.
func _sweep(c: SkaterController, radius_m: float, deg_s: float, to_deg: float) -> Sweep:
	var sk: Skater = c.skater
	var fore: float = FacingRules.forehand_sign(sk.is_left_handed)
	var out := Sweep.new()
	sk.carry_face_changed.connect(
			func(_cause: int, _speed: float, _travel_m: float) -> void: out.face_changes += 1)
	var input := InputState.new()
	var settle: int = 90
	var prev_target: float = INF
	var prev_cursor: float = INF
	var prev_facing := Vector2.ZERO
	for t: int in settle + int(ceil(to_deg / deg_s / DT)) + 60:
		var dir: Vector2 = AHEAD.rotated(deg_to_rad(clampf((t - settle) * DT * deg_s,
				0.0, to_deg)) * fore)
		input.delta = DT
		input.host_timestamp += DT
		input.move_vector = Vector2(0.0, -1.0)
		input.mouse_world_pos = sk.global_position + Vector3(dir.x, 0.0, dir.y) * radius_m
		input.mouse_world_pos.y = 0.0
		if t == settle:
			out.face_changes = 0
		c._process_input(input, DT)
		sk._physics_process(DT)
		sk._process(DT)
		if t <= settle:
			prev_facing = sk.get_facing()
			continue
		# In the world frame, so the hips' own turn is not in it.
		var target: float = _round(sk, AHEAD, c._ik.last_target_blade_world)
		var cursor: float = _round(sk, AHEAD, input.mouse_world_pos)
		var cursor_step: float = cursor - prev_cursor
		if prev_cursor != INF and cursor_step > 0.5 and target - prev_target < 0.5 * cursor_step \
				and out.stall_deg == INF and _round(sk, sk.get_facing(), input.mouse_world_pos) > 60.0:
			out.stall_deg = _round(sk, sk.get_facing(), input.mouse_world_pos)
		prev_target = target
		prev_cursor = cursor
		out.fastest_hips_deg_s = maxf(out.fastest_hips_deg_s,
				rad_to_deg(absf(prev_facing.angle_to(sk.get_facing()))) / DT)
		prev_facing = sk.get_facing()
	return out


func test_a_fast_sweep_never_stalls_the_blade_on_any_build() -> void:
	for build: Array in [[67, 165], [73, 201], [80, 250]]:
		for stick: int in [0, 2]:
			for radius_m: float in [1.1, 6.0]:
				var attrs := PlayerAttributes.new(build[0], build[1], 1, 1, 1, stick)
				var label: String = "%d in %d lb, stick %d, cursor %.1f m" % [build[0], build[1],
						stick, radius_m]
				var held: Sweep = _sweep(_make_carrier(attrs, true), radius_m, 400.0, 160.0)
				assert_lt(held.stall_deg, 155.0, label + ": hips held on the line, it stalls")
				var yielded: Sweep = _sweep(_make_carrier(attrs, false), radius_m, 400.0, 160.0)
				assert_eq(yielded.stall_deg, INF, label + ": the hips yield first")


func test_the_hips_carry_the_puck_round_into_the_pivot() -> void:
	var neutral: PlayerAttributes = PlayerAttributes.neutral()
	var deg_s: float = 250.0
	var held: Sweep = _sweep(_make_carrier(neutral, true), 1.1, deg_s, 175.0)
	var yielded: Sweep = _sweep(_make_carrier(neutral, false), 1.1, deg_s, 175.0)
	gut.p("hips peak %.0f°/s held on the line, %.0f°/s yielding; face changes %d, %d" % [
			held.fastest_hips_deg_s, yielded.fastest_hips_deg_s, held.face_changes,
			yielded.face_changes])
	assert_gt(held.fastest_hips_deg_s, 2.5 * deg_s, "held on the line, the pivot whips the hips")
	assert_lt(yielded.fastest_hips_deg_s, 1.5 * deg_s, "yielding, they turn with the sweep")
	assert_lt(yielded.face_changes, held.face_changes,
			"and the puck is not left at the stop and thrown on")

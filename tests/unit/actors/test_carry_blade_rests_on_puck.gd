extends GutTest

# A carried puck sits on the cursor, and the drawn blade rests against it: the
# IK lays mid-blade, where the puck pins, on the cursor rather than the heel,
# and the mesh's carry seat (Skater._seat_on_puck) slides the blade, however
# the shaft pitches and the wrists roll it, until the part of it on the ice
# meets the puck's rim. Pulled in close, the heel comes up and the toe holds
# the puck, which comes no closer than the carry's floor
# (SkaterController.carry_reach_min_m). Driven through the real controller and
# render pass.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# The drawn puck's rim (PuckMeshBuilder) is the collision radius.
const PUCK_R: float = GameRules.PUCK_COLLISION_RADIUS
# Off its forehand-ahead diagonal, or round the backhand, from the body.
const FOREHAND := Vector3(-0.65, 0.0, -0.76)
const BACKHAND := Vector3(0.65, 0.0, -0.76)


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _make_carrier() -> SkaterController:
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
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	puck.set_carrier(skater)
	c.on_puck_picked_up_network()
	return c


# Standing, the cursor moved from 1.1 m to `radius_m` along `dir` (a lefty's
# side; mirrored for a righty), and held.
func _pull_in(c: SkaterController, dir: Vector3, radius_m: float) -> Vector3:
	var sk: Skater = c.skater
	var along: Vector3 = dir.normalized()
	if not sk.is_left_handed:
		along.x = -along.x
	var input := InputState.new()
	for t: int in 200:
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = sk.global_position \
				+ along * lerpf(1.1, radius_m, clampf((t - 40) / 120.0, 0.0, 1.0))
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		sk._process(DT)
	return input.mouse_world_pos


# The horizontal gap from the puck's rim to the drawn blade where it is on the
# ice (its vertices within a puck's height of its lowest), negative overlapping,
# and how far along the blade that is (0 heel, 1 toe).
func _rest(sk: Skater) -> Vector2:
	var mi: MeshInstance3D = sk._blade_mesh_instance
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var xf: Transform3D = mi.global_transform
	var lowest: float = INF
	for v: Vector3 in verts:
		lowest = minf(lowest, (xf * v).y)
	var pin: Vector3 = sk.get_carry_target_global()
	var nearest: float = INF
	var at_u: float = 0.0
	for v: Vector3 in verts:
		var w: Vector3 = xf * v
		if w.y > lowest + sk.drawn_puck_height:
			continue
		var d: float = Vector2(w.x - pin.x, w.z - pin.z).length()
		if d < nearest:
			nearest = d
			at_u = -v.z / sk.blade_length
	return Vector2(nearest - PUCK_R, at_u)


func test_the_puck_sits_on_the_cursor() -> void:
	for dir: Vector3 in [FOREHAND, BACKHAND]:
		for radius_m: float in [1.1, 0.95, 0.85]:
			var c: SkaterController = _make_carrier()
			var cursor: Vector3 = _pull_in(c, dir, radius_m)
			var pin: Vector3 = c.skater.get_carry_target_global()
			assert_lt(Vector2(pin.x - cursor.x, pin.z - cursor.z).length(), 0.04,
					"%s, cursor %.2f m out" % ["forehand" if dir == FOREHAND else "backhand",
					radius_m])


func test_pulled_in_past_the_carrys_floor_the_puck_holds_at_it() -> void:
	for dir: Vector3 in [FOREHAND, BACKHAND]:
		for radius_m: float in [0.6, 0.3]:
			var c: SkaterController = _make_carrier()
			var cursor: Vector3 = _pull_in(c, dir, radius_m)
			var pin: Vector3 = c.skater.get_carry_target_global() - c.skater.global_position
			var bearing := Vector2(cursor.x, cursor.z)
			var what: String = "%s, cursor %.2f m out" % [
					"forehand" if dir == FOREHAND else "backhand", radius_m]
			assert_almost_eq(Vector2(pin.x, pin.z).length(), c.carry_reach_min_m, 0.04,
					"%s: the puck at the floor" % what)
			assert_lt(rad_to_deg(absf(Vector2(pin.x, pin.z).angle_to(bearing))), 3.0,
					"%s: on the cursor's bearing" % what)


func test_the_blade_rests_on_the_puck() -> void:
	for dir: Vector3 in [FOREHAND, BACKHAND]:
		for radius_m: float in [1.1, 0.75, 0.5, 0.35]:
			var c: SkaterController = _make_carrier()
			_pull_in(c, dir, radius_m)
			var rest: Vector2 = _rest(c.skater)
			assert_between(rest.x, -0.015, 0.012, "%s, cursor %.2f m out: the blade on the puck" % [
					"forehand" if dir == FOREHAND else "backhand", radius_m])


func test_pulled_in_close_the_toe_holds_it() -> void:
	var flat: SkaterController = _make_carrier()
	_pull_in(flat, FOREHAND, 1.4)
	var close: SkaterController = _make_carrier()
	_pull_in(close, FOREHAND, 0.4)
	assert_between(_rest(flat.skater).y, 0.4, 0.65, "out at the rim, mid-blade on it")
	assert_gt(_rest(close.skater).y, 0.7, "in tight the heel is up, and the toe on the puck")


func test_folded_over_his_skating_the_floor_moves_out() -> void:
	var c: SkaterController = _make_carrier()
	var full: float = deg_to_rad(c.velocity_lean_forward_max_deg)
	c.skater.set_upper_body_lean(0.0, 0.0, 0.0)
	assert_almost_eq(c._ik.carry_reach_floor(), c.carry_reach_min_m, 0.0001, "upright")
	c.skater.set_upper_body_lean(-full * 0.5, 0.0, -full * 0.5)
	assert_almost_eq(c._ik.carry_reach_floor(), c.carry_reach_min_m + c.carry_reach_fold_m * 0.5,
			0.0001, "half folded")
	c.skater.set_upper_body_lean(-full, 0.0, -full * 1.5)
	assert_almost_eq(c._ik.carry_reach_floor(), c.carry_reach_min_m + c.carry_reach_fold_m,
			0.0001, "and no further past the full fold")
	c.skater.set_upper_body_lean(0.1, 0.0, 0.1)
	assert_almost_eq(c._ik.carry_reach_floor(), c.carry_reach_min_m, 0.0001,
			"sitting back takes none off")

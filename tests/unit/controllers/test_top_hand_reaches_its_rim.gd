extends GutTest

# A cursor past the reachable set must put the top hand ON its ROM rim, with the
# reach lean committed — through the real controller, because the fault this
# pins lived between two of its steps. The cursor target was projected at the
# upright blade height and the final solve ran at the lean-corrected one; a
# leaned frame lifts the local blade, the stick's horizontal span grows, and the
# solve drew the hand back in to land on a target short of the rim. Measured: the
# arm settled at 0.24 m of a 0.39 m rim in every direction, the lean at 7° of 18°.
#
# The blade that results must also stay inside the reach the host's anti-cheat
# clamp allows (AISkaterCaps.max_blade_reach), or it would pull honest claims in.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0
const TICKS: int = 120
const CURSOR_M: float = 3.5


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _make_controller() -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, gs)
	controller.apply_attributes(PlayerAttributes.all_average())
	return controller


# Holds the cursor CURSOR_M out at `deg` off the facing (positive toward the
# forehand) with the body pinned facing +Z, so the reach and not a turn answers.
func _reach(c: SkaterController, deg: float) -> void:
	var sk: Skater = c.skater
	sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	var forward := Vector3(0.0, 0.0, 1.0)
	# A lefty's forehand is the body's local −X, which is world +X facing +Z.
	var forehand := Vector3(1.0, 0.0, 0.0)
	var a: float = deg_to_rad(deg)
	var dir: Vector3 = forward * cos(a) + forehand * sin(a)
	for i: int in TICKS:
		c._pose.facing = Vector2(0.0, 1.0)
		sk.set_facing(c._pose.facing)
		var input := InputState.new()
		input.delta = DT
		input.mouse_world_pos = sk.global_position + dir * CURSOR_M
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		# The render pass poses the bottom hand.
		sk._process(DT)


func _hand_off_shoulder(c: SkaterController) -> Vector2:
	var hand: Vector3 = c.skater.get_top_hand_position()
	var shoulder: Vector3 = c.skater.shoulder.position
	return Vector2(hand.x - shoulder.x, hand.z - shoulder.z)


func _rim_toward(c: SkaterController, hand_vec: Vector2) -> float:
	var sign_val: float = -1.0 if c.skater.is_left_handed else 1.0
	return TopHandIK.rim_reach(atan2(hand_vec.x, -hand_vec.y) * sign_val,
			c.rom_forward_reach_max, c.rom_forehand_reach_max, c.rom_backhand_reach_max)


func test_the_hand_reaches_its_rim_in_every_direction() -> void:
	var c: SkaterController = _make_controller()
	for deg: float in [0.0, 45.0, 90.0, -45.0, -90.0]:
		_reach(c, deg)
		var hand_vec: Vector2 = _hand_off_shoulder(c)
		assert_almost_eq(hand_vec.length(), _rim_toward(c, hand_vec), 0.01,
				"cursor %.0f° off facing: the hand sits on its rim" % deg)


func test_reaching_ahead_commits_the_lean() -> void:
	var c: SkaterController = _make_controller()
	_reach(c, 0.0)
	assert_almost_eq(-c.skater.upper_body.rotation.x,
			deg_to_rad(c.upper_body_lean_max_deg), deg_to_rad(1.0),
			"full reach ahead folds the torso the whole way")


func test_straight_ahead_is_the_arms_longest_reach() -> void:
	var c: SkaterController = _make_controller()
	assert_gt(c.rom_forward_reach_max, c.rom_backhand_reach_max,
			"the shoulder blade protracts behind a forward reach")
	assert_gt(c.rom_backhand_reach_max, c.rom_forehand_reach_max,
			"and the chest stops a reach across the body first")


func test_the_full_reach_stays_inside_the_hosts_reach_clamp() -> void:
	var c: SkaterController = _make_controller()
	var caps: AISkaterCaps = c.build_ai_caps()
	var allowed: float = caps.max_blade_reach + caps.max_lean_shift
	for deg: float in [0.0, 45.0, 90.0, 135.0, -45.0, -90.0, -135.0]:
		_reach(c, deg)
		var body: Vector3 = c.skater.global_position
		var reach: float = c.skater.get_blade_contact_global().distance_to(body)
		assert_lt(reach, allowed,
				"cursor %.0f°: an honest blade at %.2f m is inside the %.2f m clamp" % [
						deg, reach, allowed])


func test_a_released_bottom_hand_tucks_ahead_of_the_body() -> void:
	var c: SkaterController = _make_controller()
	_reach(c, -150.0)
	var sk: Skater = c.skater
	var bh: Vector3 = sk.bottom_hand.position
	var shoulder: Vector3 = sk.visible_shoulder(sk.bottom_shoulder.position)
	assert_lt(bh.z, shoulder.z - 0.15, "ahead of the body, not hanging at its side")
	assert_lt(bh.y, shoulder.y - 0.2, "down at the belly, not up at the chest")
	var arm: float = sk.upper_arm_length + sk.forearm_length
	assert_lt(bh.distance_to(shoulder), arm * 0.9, "on a bent elbow, not hung straight")

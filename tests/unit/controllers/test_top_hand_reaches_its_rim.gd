extends GutTest

# A cursor past the reachable set must put the top hand ON its ROM rim, with the
# reach lean committed — through the real controller, because the fault this
# pins lived between two of its steps. The cursor target was projected at the
# upright blade height and the final solve ran at the lean-corrected one; a
# leaned frame lifts the local blade, the stick's horizontal span grows, and the
# solve drew the hand back in to land on a target short of the rim. Measured: the
# arm settled at 0.24 m of a 0.39 m rim in every direction, the lean at 7° of 18°.
#
# The rim is a disc about gravity, not about the chest: solved in the leaned
# frame, a lean tipped "out in front" down toward the skates, and reaching ahead
# while skating the fully extended arm hung 82° below horizontal.
#
# The blade that results must also stay inside the reach the host's anti-cheat
# clamp allows (AISkaterCaps.max_blade_reach), or it would pull honest claims in.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const TICKS: int = 120
const CURSOR_M: float = 3.5
# Where the loose puck lies along the cursor's line: inside every build's reach.
const PUCK_M: float = 2.0


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
	controller.apply_attributes(PlayerAttributes.neutral())
	# Standing on the ice as in a game: the claim clamp's lean allowance is read
	# off the body's height.
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	return controller


# Holds the cursor CURSOR_M out at `deg` off the facing (positive toward the
# forehand) with the body pinned facing +Z, so the reach and not a turn answers.
# A loose puck lies on the cursor's line within reach unless `purpose` is false:
# something to reach for (SkaterIKCoordinator.reach_purpose).
func _reach(c: SkaterController, deg: float, purpose: bool = true) -> void:
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
		if purpose:
			c.puck.global_position = sk.global_position + dir * PUCK_M
			c.puck.global_position.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		# The render pass poses the bottom hand.
		sk._process(DT)


# The hand off the shoulder its arm is drawn from, in the arm's level frame —
# where the ROM is a horizontal disc.
func _hand_off_shoulder(c: SkaterController) -> Vector2:
	var rot: Vector3 = c.skater.upper_body.rotation
	var tilt: Basis = Basis.from_euler(Vector3(rot.x, 0.0, rot.z))
	var hand: Vector3 = tilt * c.skater.get_top_hand_position()
	var shoulder: Vector3 = tilt * c._ik.arm_shoulder()
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


func test_reaching_ahead_commits_the_forward_lean() -> void:
	var c: SkaterController = _make_controller()
	_reach(c, 0.0)
	assert_almost_eq(-c.skater.upper_body.rotation.x,
			deg_to_rad(c.upper_body_lean_forward_max_deg), deg_to_rad(1.0),
			"full reach ahead folds the torso the whole way")


func test_reaching_to_the_side_leans_by_the_side_cap() -> void:
	var c: SkaterController = _make_controller()
	for deg: float in [90.0, -90.0]:
		_reach(c, deg)
		var rot: Vector3 = c.skater.upper_body.rotation
		var lean: float = rad_to_deg(Vector2(rot.x, rot.z).length())
		assert_almost_eq(lean, c.upper_body_lean_max_deg, 2.0,
				"cursor %.0f°: a side reach leans over the hip, not the forward fold" % deg)


# Skating folds the trunk forward and a backhand reach twists it, and the
# skeleton folds before it twists, so its shoulder sits off the frame's marker
# (SkaterSpineRig.shoulder_in_frame). The hand is solved from where the arm is
# drawn; solved from the marker, the drawn arm here stretched to 1.03 of itself.
# A carrier pivots past its backhand stop, so it reaches just inside it.
func test_a_skating_backhand_reach_never_outreaches_the_drawn_arm() -> void:
	for carrying: bool in [false, true]:
		var c: SkaterController = _make_controller()
		var sk: Skater = c.skater
		sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		var deg: float = 77.0
		if carrying:
			c.puck.set_carrier(sk)
			c.on_puck_picked_up_network()
			deg = c.bh_release_angle_deg - 5.0
		var a: float = deg_to_rad(deg)
		var arm: float = sk.upper_arm_length + sk.forearm_length
		var worst: float = 0.0
		var input := InputState.new()
		for i: int in 160:
			input.delta = DT
			input.move_vector = Vector2.ZERO if i < 40 else Vector2(0.0, 1.0)
			var aim: Vector3 = Vector3(0.0, 0.0, 3.0) if i < 40 \
					else Vector3(-sin(a), 0.0, cos(a)) * 3.6
			input.mouse_world_pos = sk.global_position + aim
			input.mouse_world_pos.y = 0.0
			c._process_input(input, DT)
			sk._physics_process(DT)
			sk._process(DT)
			var hand: Vector3 = sk.top_hand.position
			var root: Vector3 = sk._arms.arm_root(sk.shoulder.position, hand)
			worst = maxf(worst, root.distance_to(sk.upper_body.transform * hand) / arm)
		var what: String = "carrying" if carrying else "empty stick"
		assert_gt(-sk.trunk_fold(), deg_to_rad(5.0),
				"%s: skating folds the trunk, or this means nothing" % what)
		assert_lt(worst, 1.0, "%s: the drawn arm spans %.3f of its length" % [what, worst])


# In close the hand sits over the shoulder, and skating folds that shoulder out
# ahead of the hips; the chest still turns to the blade, or a cursor beside the
# hips lies past the arm's backhand angle and the blade stops ahead of it.
func test_a_close_skating_reach_still_twists_to_the_blade() -> void:
	for deg: float in [45.0, -90.0]:
		var c: SkaterController = _make_controller()
		var sk: Skater = c.skater
		var a: float = deg_to_rad(deg)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var input := InputState.new()
		for i: int in 200:
			if i == 120:
				sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
			input.delta = DT
			input.move_vector = Vector2(0.0, 1.0)
			var aim: Vector3 = Vector3(0.0, 0.0, 3.0) if i < 40 else dir * 1.0
			input.mouse_world_pos = sk.global_position + aim
			input.mouse_world_pos.y = 0.0
			c._process_input(input, DT)
			sk._physics_process(DT)
			sk._process(DT)
		assert_gt(-sk.trunk_fold(), deg_to_rad(5.0), "skating folds the trunk, or this means nothing")
		assert_gt(absf(sk.upper_body.rotation.y), deg_to_rad(20.0),
				"cursor %.0f°: the chest turns to a blade in close" % deg)
		var blade: Vector3 = sk.get_blade_contact_global() - sk.global_position
		var off: float = rad_to_deg(absf(Vector2(blade.x, blade.z).angle_to(Vector2(dir.x, dir.z))))
		assert_lt(off, 6.0, "cursor %.0f°: the blade sits %.1f° off it" % [deg, off])


# The copy of the rig's build order the hand solve uses, held against the rig.
func test_the_arm_shoulder_is_where_the_rig_puts_it() -> void:
	var c: SkaterController = _make_controller()
	var sk: Skater = c.skater
	var marker: Vector3 = sk.shoulder.position
	for case: Vector3 in [Vector3(-0.3, -1.0, 0.1), Vector3(-0.2, 0.9, -0.05),
			Vector3(-0.35, -0.4, 0.0)]:
		var fold: float = case.x * 0.6
		sk.set_upper_body_rotation(case.y)
		sk.set_upper_body_lean(case.x, case.z, fold)
		sk.lower_body.rotation.y = 0.0
		sk._spine.update()
		var spine: Basis = sk._arms._skeleton.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE).basis
		var drawn: Vector3 = sk.upper_body.basis.inverse() * (spine * marker)
		var solved: Vector3 = SkaterSpineRig.shoulder_in_frame(
				marker, sk.upper_body.rotation, 0.0, fold)
		assert_almost_eq(solved.distance_to(drawn), 0.0, 0.002,
				"fold %.2f twist %.2f: the solve's shoulder is the rig's" % [fold, case.y])


func test_straight_ahead_is_the_arms_longest_reach() -> void:
	var c: SkaterController = _make_controller()
	assert_gt(c.rom_forward_reach_max, c.rom_backhand_reach_max,
			"the shoulder blade protracts behind a forward reach")
	assert_gt(c.rom_backhand_reach_max, c.rom_forehand_reach_max,
			"and the chest stops a reach across the body first")


func test_reaching_ahead_extends_the_arm_out_in_front() -> void:
	var c: SkaterController = _make_controller()
	_reach(c, 0.0)
	var sk: Skater = c.skater
	var arm: Vector3 = sk.upper_body.to_global(sk.get_top_hand_position()) \
			- sk.upper_body.to_global(c._ik.arm_shoulder())
	var below: float = rad_to_deg(atan2(-arm.y, Vector2(arm.x, arm.z).length()))
	assert_lt(below, 55.0, "the arm reaches out at %.0f° below horizontal" % below)


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
	# Skating folds the trunk on top of the reach lean, the deepest reach there is.
	for deg: float in [0.0, 30.0, -30.0]:
		c = _make_controller()
		var sk: Skater = c.skater
		sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		var a: float = deg_to_rad(deg)
		var input := InputState.new()
		for i: int in 160:
			input.delta = DT
			input.move_vector = Vector2.ZERO if i < 40 else Vector2(0.0, 1.0)
			input.mouse_world_pos = sk.global_position + Vector3(sin(a), 0.0, cos(a)) * CURSOR_M
			input.mouse_world_pos.y = 0.0
			c._process_input(input, DT)
			sk._physics_process(DT)
		var reach: float = sk.get_blade_contact_global().distance_to(sk.global_position)
		assert_lt(reach, allowed,
				"skating, cursor %.0f°: an honest blade at %.2f m is inside the %.2f m clamp" % [
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


# With nothing to reach for, a far cursor rests the blade where both hands hold
# the stick and the trunk keeps its posture.
func test_with_nothing_to_reach_for_the_stick_rests_in_both_hands() -> void:
	var c: SkaterController = _make_controller()
	_reach(c, 0.0, false)
	var sk: Skater = c.skater
	var hand: Vector3 = sk.drawn_top_hand()
	var shaft: Vector3 = sk.get_blade_position() - hand
	var bh: Vector3 = sk.bottom_hand.position
	var t: float = clampf((bh - hand).dot(shaft) / shaft.length_squared(), 0.0, 1.0)
	assert_lt(bh.distance_to(hand + shaft * t), 0.02, "the bottom hand holds the shaft")
	assert_almost_eq(sk.upper_body.rotation.x, 0.0, deg_to_rad(0.5), "no reach lean")
	var reaching: SkaterController = _make_controller()
	_reach(reaching, 0.0)
	assert_gt(reaching.skater.get_blade_contact_global().distance_to(reaching.skater.global_position),
			sk.get_blade_contact_global().distance_to(sk.global_position) + 0.1,
			"the same cursor reaches out once there is a puck to reach for")


func test_the_league_default_reach_is_the_neutral_builds() -> void:
	var c: SkaterController = _make_controller()
	assert_almost_eq(c.build_ai_caps().max_blade_reach, AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M, 0.01,
			"bots price an unknown defender's reach as the neutral build's")


# Carrying, the puck stays in both hands: the blade stops where the bottom hand
# could no longer hold the shaft, and on the backhand at the angle it lets go.
func _carry(c: SkaterController, deg: float, skate: bool) -> void:
	var sk: Skater = c.skater
	c.puck.set_carrier(sk)
	c.on_puck_picked_up_network()
	var a: float = deg_to_rad(deg)
	var input := InputState.new()
	for i: int in 200:
		if skate:
			if i == 120:
				sk.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		else:
			c._pose.facing = Vector2(0.0, 1.0)
			sk.set_facing(c._pose.facing)
		input.delta = DT
		input.move_vector = Vector2(0.0, 1.0) if skate else Vector2.ZERO
		var aim: Vector3 = Vector3(0.0, 0.0, 3.0) if skate and i < 120 \
				else Vector3(sin(a), 0.0, cos(a)) * 4.5
		input.mouse_world_pos = sk.global_position + aim
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		sk._process(DT)


func test_a_carrier_keeps_both_hands_on_the_stick() -> void:
	for skate: bool in [false, true]:
		for deg: float in [0.0, 45.0, -45.0, -90.0, -135.0]:
			var c: SkaterController = _make_controller()
			_carry(c, deg, skate)
			var sk: Skater = c.skater
			# The shaft as drawn, which the stride's pump pivots about the blade.
			var hand: Vector3 = sk.drawn_top_hand()
			var shaft: Vector3 = sk.get_blade_position() - hand
			var bh: Vector3 = sk.bottom_hand.position
			var t: float = clampf((bh - hand).dot(shaft) / shaft.length_squared(), 0.0, 1.0)
			var what: String = "%s, cursor %.0f°" % ["skating" if skate else "standing", deg]
			assert_lt(bh.distance_to(hand + shaft * t), 0.02,
					"%s: the bottom hand holds the shaft" % what)
			assert_lt(rad_to_deg(c._ik._bh_backhand_angle()), c.bh_release_angle_deg + 0.5,
					"%s: the blade stops at the backhand angle the hand lets go at" % what)


func test_an_empty_stick_still_reaches_one_handed() -> void:
	var with_puck: SkaterController = _make_controller()
	_carry(with_puck, 0.0, false)
	var empty: SkaterController = _make_controller()
	_reach(empty, 0.0)
	var carried: float = with_puck.skater.get_blade_contact_global().distance_to(
			with_puck.skater.global_position)
	var reached: float = empty.skater.get_blade_contact_global().distance_to(
			empty.skater.global_position)
	assert_gt(reached - carried, 0.1,
			"one hand reaches %.2f m past the two-handed carry" % (reached - carried))

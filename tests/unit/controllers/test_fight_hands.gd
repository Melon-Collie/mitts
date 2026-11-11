extends GutTest

# A fighter's hands with the gloves off (FightRules.Role.FIGHTING): the punching
# fist chases the cursor within the arm's reach, never faster than a fist moves;
# the holding hand keeps the guard until the grab button takes the other man's
# sweater; the slap button swaps the hands, letting go; an arm he holds is tied
# up; the pair cannot pass through each other; a replay lays the fists the live
# tick left. The stick is hidden, the shot machine stands down, and the stick
# and gloves drop to the ice until the fight is over (SkaterDroppedGear).

const DT: float = 1.0 / 120.0
const Grip = FightHoldRules.Grip
const Side = FightHoldRules.Side


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func allows_blade_aim_during_lock() -> bool:
		return false

	func is_in_goal_celebration() -> bool:
		return false


var _puck: Puck = null
var _state: StubGameState = null
var _skater: Skater = null
var _controller: SkaterController = null
var _man: Skater = null
var _man_controller: SkaterController = null
var _input := InputState.new()
var _man_input := InputState.new()
# The man's controller sits out the tick: what he holds is set by hand.
var _man_still: bool = false


func before_each() -> void:
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.global_position = Vector3(20.0, 0.0, 20.0)
	_state = StubGameState.new()
	add_child_autofree(_state)
	var attrs := PlayerAttributes.new(73, 201, 1, 1, 1, 1)
	_skater = _spawn(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0), 0, attrs)
	_controller = _control(_skater, attrs)
	_input = InputState.new()
	_input.delta = DT
	_aim(Vector3(0.0, 0.0, -0.35))


func _spawn(at: Vector3, team: int, attrs: PlayerAttributes) -> Skater:
	var s: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(s)
	s.global_position = at
	s.set_process(false)
	s.set_physics_process(false)
	s.apply_appearance(attrs)
	s.set_team_id_resolver(func() -> int: return team)
	return s


func _control(s: Skater, attrs: PlayerAttributes) -> SkaterController:
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(s, _puck, _state)
	c.apply_attributes(attrs)
	return c


# A second fighter on the other team, `gap` metres ahead, facing back.
func _square_up(gap: float) -> void:
	var attrs := PlayerAttributes.new(73, 201, 1, 1, 1, 1)
	_man = _spawn(_skater.global_position + Vector3(0.0, 0.0, -gap), 1, attrs)
	_man_controller = _control(_man, attrs)
	_man_controller._pose.facing = Vector2(0.0, 1.0)
	_man.set_facing(Vector2(0.0, 1.0))
	var both: Array = [_skater, _man]
	_skater.set_skater_collision_provider(func() -> Array: return both)
	_man.set_skater_collision_provider(func() -> Array: return both)
	_man_input = InputState.new()
	_man_input.delta = DT
	_man_input.mouse_world_pos = _man.global_position + Vector3(0.0, 0.0, 0.35)


# The cursor, relative to the skater.
func _aim(rel: Vector3) -> void:
	_input.mouse_world_pos = _skater.global_position + rel


func _fight() -> void:
	_skater.fight_role = FightRules.Role.FIGHTING
	if _man != null:
		_man.fight_role = FightRules.Role.FIGHTING


func _tick(n: int = 1) -> void:
	for i: int in n:
		_controller._process_input(_input, DT)
		if _man != null and not _man_still:
			_man_controller._process_input(_man_input, DT)
		_skater._physics_process(DT)
		if _man != null:
			_man._physics_process(DT)
		_skater._process(DT)
		_input.shoot_pressed = false
		_input.slap_pressed = false


func _reach() -> float:
	return SkaterFightHands.arm_reach(_skater)


func test_the_guard_rules_hold_a_free_fist_up_in_front_inside_the_shoulder() -> void:
	var shoulder := Vector3(0.2, 0.45, 0.0)
	var hand: Vector3 = FightGuardRules.guard_hand(shoulder)
	assert_lt(hand.z, shoulder.z, "in front of the shoulder")
	assert_gt(hand.y, shoulder.y, "above it, at the chin")
	assert_true(absf(hand.x) < absf(shoulder.x) and signf(hand.x) == signf(shoulder.x),
			"inside the shoulder, on its own side")


func test_the_punching_fist_chases_the_cursor_and_no_further_than_the_arm() -> void:
	_fight()
	_tick(40)
	var resting: Vector3 = _skater.get_top_hand_position()
	_aim(Vector3(0.0, 0.0, -3.0))
	var top: float = 0.0
	var prev: Vector3 = resting
	for i: int in 30:
		_tick()
		var now: Vector3 = _skater.get_top_hand_position()
		top = maxf(top, now.distance_to(prev) / DT)
		prev = now
	assert_lte(top, FightFistRules.MAX_SPEED_M_S + 0.01, "no faster than a fist moves")
	assert_gt(top, 0.5 * FightFistRules.MAX_SPEED_M_S, "a punch, not a reach")
	var shoulder: Vector3 = _controller._ik.arm_shoulder()
	assert_almost_eq(prev.distance_to(shoulder), _reach(), 0.01, "out at the arm's length")
	assert_lt(prev.z, resting.z, "out in front")


func test_the_holding_hand_keeps_the_guard_while_the_fist_punches() -> void:
	_fight()
	_aim(Vector3(0.0, 0.0, -3.0))
	_tick(60)
	var guard: Vector3 = FightGuardRules.guard_hand(_skater.bottom_shoulder.position)
	assert_almost_eq(_skater.get_blade_position().distance_to(guard), 0.0, 0.01,
			"the bottom fist rides the blade marker, held in the guard")


func test_the_grab_takes_his_sweater_and_letting_go_lets_go() -> void:
	_square_up(0.85)
	_fight()
	_tick(30)
	_input.shoot_pressed = true
	_input.shoot_held = true
	_tick(30)
	assert_eq(_skater.fight_grip, Grip.JERSEY)
	var held: Vector3 = _skater.upper_body_to_global(_skater.get_blade_position())
	var sweater: Vector3 = FightHoldRules.jersey_point(_man.global_position,
			_man.collision_radius(), _skater.global_position,
			_man.upper_body_to_global(_man.shoulder.position).y)
	assert_almost_eq(held.distance_to(sweater), 0.0, 0.05, "the hand on his chest")
	_input.shoot_held = false
	_tick()
	assert_eq(_skater.fight_grip, Grip.NONE)


func test_a_thrown_arm_is_caught() -> void:
	_square_up(0.85)
	_fight()
	_man_input.mouse_world_pos = _man.global_position + Vector3(0.0, 0.0, 3.0)
	_tick(30)
	_input.shoot_held = true
	_tick(5)
	assert_eq(_skater.fight_grip,
			FightHoldRules.arm_grip_for(_man.fight_punch_side), "his punching arm, caught")


func test_after_the_swap_the_grab_waits_for_the_button_to_come_up() -> void:
	_square_up(0.85)
	_fight()
	_input.shoot_held = true
	_tick(20)
	_input.slap_pressed = true
	_tick(5)
	assert_eq(_skater.fight_grip, Grip.NONE, "still held, it does not take hold again")
	_input.shoot_held = false
	_tick()
	_input.shoot_held = true
	_tick(20)
	assert_eq(_skater.fight_grip, Grip.JERSEY, "a fresh grab does")


func test_nothing_to_grab_out_of_reach() -> void:
	_square_up(2.5)
	_fight()
	_input.shoot_pressed = true
	_input.shoot_held = true
	_tick(10)
	assert_eq(_skater.fight_grip, Grip.NONE)


func test_the_swap_changes_hands_and_lets_go() -> void:
	_square_up(0.85)
	_fight()
	_input.shoot_held = true
	_tick(20)
	assert_eq(_skater.fight_grip, Grip.JERSEY)
	_input.slap_pressed = true
	_tick()
	assert_eq(_skater.fight_punch_side, Side.BOTTOM)
	assert_eq(_skater.fight_grip, Grip.NONE, "the grip lets go on the swap")
	_input.shoot_held = false
	_aim(Vector3(0.0, 0.0, -3.0))
	_tick(40)
	var bottom_shoulder: Vector3 = _skater.bottom_shoulder.position
	assert_almost_eq(_skater.get_blade_position().distance_to(bottom_shoulder), _reach(), 0.02,
			"the bottom arm throws now")


func test_an_arm_he_holds_is_tied_up() -> void:
	_square_up(0.85)
	_fight()
	_man_still = true
	_man.fight_grip = Grip.ARM_TOP  # he has hold of the arm we punch with
	_aim(Vector3(0.0, 0.0, -3.0))
	_tick(40)
	var shoulder: Vector3 = _controller._ik.arm_shoulder()
	assert_almost_eq(_skater.get_top_hand_position().distance_to(shoulder),
			_reach() * FightFistRules.TIED_REACH_SHARE, 0.02, "held short")


func test_the_pair_cannot_pass_through_each_other() -> void:
	_square_up(0.9)
	_fight()
	_skater.velocity = Vector3(0.0, 0.0, -4.0)
	_controller._process_input(_input, DT)
	assert_gt(_skater.velocity.z, -4.0, "driving into him is held off")


func test_a_replay_lays_the_fists_the_live_tick_left() -> void:
	_fight()
	_aim(Vector3(0.0, 0.0, -3.0))
	_tick(5)
	var fist: Vector3 = _controller._fight._top
	var moving: Vector3 = _controller._fight._top_vel
	_controller.is_replaying = true
	_aim(Vector3(1.0, 0.0, 0.0))
	_controller._process_input(_input, DT)
	_controller.is_replaying = false
	assert_eq(_controller._fight._top, fist, "the fist's own state is not stepped again")
	assert_eq(_controller._fight._top_vel, moving)


func test_no_shot_is_begun_and_none_carries_on() -> void:
	_input.slap_pressed = true
	_input.slap_held = true
	_tick(1)
	_tick(5)
	assert_eq(_controller.get_shot_state(), SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK,
			"a puckless wind-up before the fight")
	_fight()
	_tick(1)
	assert_eq(_controller.get_shot_state(), SkaterStateMachine.State.SKATING_WITHOUT_PUCK,
			"called off as the gloves come off")
	_input.shoot_pressed = true
	_input.shoot_held = true
	_tick(3)
	assert_eq(_controller.get_shot_state(), SkaterStateMachine.State.SKATING_WITHOUT_PUCK,
			"and nothing new starts")


func test_the_stick_and_gloves_drop_and_lie_on_the_ice_until_the_fight_is_over() -> void:
	_tick(10)
	assert_true(_skater.stick_mesh.visible)
	_fight()
	_tick(1)
	assert_false(_skater.stick_mesh.visible, "the stick in hand is hidden")
	assert_false(_skater.blade_mesh_instance().visible)
	assert_eq(_skater._dropped_gear.piece_count(), 3, "the stick and both gloves")
	_tick(roundi(2.0 / DT))
	for piece: SkaterDroppedGear.Piece in _skater._dropped_gear._pieces:
		assert_true(piece.landed, "down on the ice")
		assert_almost_eq(piece.node.global_position.y, piece.rest_y, 1e-4)
		assert_eq(piece.velocity, Vector3.ZERO, "slid to a stop")
	_skater.fight_role = FightRules.Role.NONE
	_tick(1)
	assert_eq(_skater._dropped_gear.piece_count(), 0, "picked up when it is over")
	assert_true(_skater.stick_mesh.visible, "and back in his hands")
	assert_eq(_skater.fight_grip, Grip.NONE)
	assert_eq(_skater.fight_punch_side, Side.TOP, "the next fight starts with the top hand")


func test_a_punch_rattles_him_and_a_full_rattle_puts_him_down() -> void:
	_fight()
	_tick(5)
	var back: Vector3 = _skater.global_transform.basis.z.normalized()
	var dv: Vector3 = back * FightPunchRules.impulse_dv(FightFistRules.MAX_SPEED_M_S,
			_skater.weight * FightPunchRules.NEUTRAL_MASS_KG)
	_controller.absorb_punch(dv, FightPunchRules.Hit.HEAD, FightFistRules.MAX_SPEED_M_S)
	assert_almost_eq(_skater.fight_rattle, FightPunchRules.RATTLE_HEAD_S, 1e-4)
	assert_eq(_controller.knockdown_timer, 0.0, "a sound man rides a punch")
	assert_gt(_controller.stagger_timer, 0.0, "and reels from it")
	_skater.fight_rattle = FightPunchRules.RATTLE_MAX_S
	_controller.absorb_punch(dv, FightPunchRules.Hit.HEAD, FightFistRules.MAX_SPEED_M_S)
	assert_gt(_controller.knockdown_timer, 0.0, "rattled to the full, a clean shot drops him")


func test_the_rattle_wears_off_on_the_host() -> void:
	_fight()
	_skater.fight_rattle = 1.0
	_tick(roundi(1.0 / DT))
	assert_almost_eq(_skater.fight_rattle, 1.0 - FightPunchRules.RATTLE_DECAY_PER_S, 0.02)


func test_a_rattled_fist_is_slower() -> void:
	_fight()
	_skater.fight_rattle = FightPunchRules.RATTLE_MAX_S
	_tick(40)
	_aim(Vector3(0.0, 0.0, -3.0))
	var top: float = 0.0
	var prev: Vector3 = _skater.get_top_hand_position()
	for i: int in 30:
		_tick()
		_skater.fight_rattle = FightPunchRules.RATTLE_MAX_S
		var now: Vector3 = _skater.get_top_hand_position()
		top = maxf(top, now.distance_to(prev) / DT)
		prev = now
	assert_lte(top, FightFistRules.MAX_SPEED_M_S
			* FightPunchRules.fist_scale(FightPunchRules.RATTLE_MAX_S) + 0.01)

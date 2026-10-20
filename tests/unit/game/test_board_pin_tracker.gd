extends GutTest

# The board pin on the host (BoardPinTracker): a checker holding his stick out on
# the stick button, driving an unbraced opponent square into the boards, locks
# them both; the lock ends when the victim's body gets past the pinner's along the
# wall, when the pinner lets go of the button, when the bodies part, at the cap,
# at a stoppage, or on a release — and then the victim is immune for a moment and
# the pinner's stick cools down. A pinned carrier loses the puck at once.
# Real Skater scenes, never ticked; positions, velocities and buttons by hand.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const Role = BoardPinRules.Role

var _registry: PlayerRegistry = null
var _pins: BoardPinTracker = null
var _pinner: Skater = null
var _victim: Skater = null
var _now: float = 100.0
var _stripped: Array[Skater] = []


func before_each() -> void:
	_victim = _spawn_skater()
	_pinner = _spawn_skater()
	_registry = PlayerRegistry.new()
	_registry._skaters_cache = [_pinner, _victim] as Array[Skater]
	_registry.team_id_by_skater = {_pinner: 1, _victim: 0}
	_stripped.clear()
	_pins = BoardPinTracker.new()
	_pins.setup(_registry, func() -> float: return _now,
			func(victim: Skater, _p: Skater) -> void: _stripped.append(victim))
	_place(0.0)
	_hold_stick(_pinner, true)
	_pinner.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_pinner.velocity = Vector3(1.5, 0.0, 0.0)


func _spawn_skater() -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.set_physics_process(false)
	s.set_process(false)
	return s


# The stick button held past the hook (StickCheckRules' TIE phase), or let go.
func _hold_stick(skater: Skater, held: bool) -> void:
	skater.stick_check_held = held
	skater.stick_check_phase = StickCheckRules.Phase.TIE if held else StickCheckRules.Phase.IDLE


# The victim against the +x side boards, the pinner touching him from the ice
# side, `along` metres further down the wall.
func _place(along: float) -> void:
	var r_v: float = _victim.collision_radius()
	var r_p: float = _pinner.collision_radius()
	_victim.global_position = Vector3(GameRules.INNER_HALF_WIDTH - r_v - 0.05,
			GameRules.FACEOFF_SPAWN_HEIGHT, along)
	_pinner.global_position = Vector3(_victim.global_position.x - r_v - r_p,
			GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)


func test_a_stick_held_out_driving_into_the_boards_locks_both() -> void:
	_pins.tick(true)
	assert_eq(_pinner.pin_role, Role.PINNER)
	assert_eq(_victim.pin_role, Role.PINNED)
	assert_almost_eq(_victim.pin_strength,
			BoardPinRules.pin_strength(_pinner.weight, _victim.weight), 1e-6)
	assert_eq(_pins.victim_of(_pinner), _victim)
	assert_eq(_stripped, [_victim] as Array[Skater], "the victim's puck, if any, goes loose")


func test_a_braced_victim_is_not_pinned() -> void:
	_victim.hit_committed = true
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE)


func test_the_commit_or_a_stick_still_in_the_hook_pins_nobody() -> void:
	_hold_stick(_pinner, false)
	_pinner.hit_committed = true
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE, "a check is not a pin")
	_pinner.hit_committed = false
	_pinner.stick_check_held = true
	_pinner.stick_check_phase = StickCheckRules.Phase.HOOK
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE, "a tap at the wall stays a lift")


func test_a_carrier_a_tied_stick_or_a_cooling_one_pins_nobody() -> void:
	_pinner.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE, "a carrier")
	_pinner.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_pinner.stick_tied = true
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE, "a tied stick")
	_pinner.stick_tied = false
	_pinner.start_stick_check_cooldown()
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE, "a cooling stick")


func test_a_teammate_or_a_body_off_the_wall_is_not_pinned() -> void:
	_registry.team_id_by_skater[_pinner] = 0
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE, "teammate")
	_registry.team_id_by_skater[_pinner] = 1
	_victim.global_position.x -= 1.5
	_pinner.global_position.x -= 1.5
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE, "open ice")


func test_getting_past_the_pinner_along_the_wall_frees_him_either_way() -> void:
	for side: float in [1.0, -1.0]:
		before_each()
		_pins.tick(true)
		_place(side * (BoardPinRules.PIN_ESCAPE_OFFSET_M * 0.8))
		_pins.tick(true)
		assert_eq(_victim.pin_role, Role.PINNED, "still lined up (side %d)" % side)
		_place(side * (BoardPinRules.PIN_ESCAPE_OFFSET_M + 0.05))
		_pins.tick(true)
		assert_eq(_victim.pin_role, Role.NONE, "past him (side %d)" % side)
		assert_eq(_pinner.pin_role, Role.NONE)


func test_letting_go_of_the_button_ends_it_and_the_victim_is_immune() -> void:
	_pins.tick(true)
	_pinner.stick_check_held = false
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE)
	assert_true(_pinner.is_stick_check_cooling(), "the pinner's stick cools down")
	_pinner._stick_check_cooldown = 0.0
	_hold_stick(_pinner, true)
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE, "immune for a moment")
	_now += BoardPinRules.PIN_IMMUNITY_S + 0.01
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.PINNED, "then fair game again")


func test_the_bodies_parting_ends_it() -> void:
	_pins.tick(true)
	_pinner.global_position.x -= BoardPinRules.PIN_SEPARATION_M + 0.1
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE)


func test_the_cap_ends_it() -> void:
	_pins.tick(true)
	_now += BoardPinRules.PIN_MAX_S - 0.05
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.PINNED)
	_now += 0.1
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.NONE)


func test_a_release_or_a_stoppage_lets_go() -> void:
	_pins.tick(true)
	_pins.release(_victim)
	assert_eq(_victim.pin_role, Role.NONE, "the frozen-puck squirt")
	assert_eq(_pinner.pin_role, Role.NONE)
	assert_true(_pinner.is_stick_check_cooling())
	_pinner._stick_check_cooldown = 0.0
	_now += BoardPinRules.PIN_IMMUNITY_S + 0.01
	_pins.tick(true)
	_pins.tick(false)
	assert_eq(_victim.pin_role, Role.NONE, "a stoppage")
	_pins.tick(true)
	assert_eq(_victim.pin_role, Role.PINNED, "a stoppage leaves no immunity")


# The goal replay stamps its recorded frames onto the live actors, so it can end
# on a lock the tracker has already ended (or never held).
func test_a_stoppage_lets_go_of_a_lock_the_tracker_does_not_hold() -> void:
	_pinner.pin_role = Role.PINNER
	_victim.pin_role = Role.PINNED
	_victim.pin_strength = 0.5
	_pins.tick(false)
	assert_eq(_pinner.pin_role, Role.NONE)
	assert_eq(_victim.pin_role, Role.NONE)
	assert_eq(_victim.pin_strength, 0.0)


func test_a_pinned_carrier_loses_the_puck_at_his_feet() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.set_process(false)
	puck.set_carrier(_victim)
	_victim.velocity = Vector3(0.0, 0.0, 1.2)
	puck.apply_pin_strip(_pinner)
	assert_null(puck.carrier)
	assert_eq(puck.linear_velocity, Vector3(0.0, 0.0, 1.2), "it goes on at his speed")

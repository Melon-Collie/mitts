extends GutTest

# PenaltyTracker — the referee's call on a contact, the delayed whistle, and
# seating the box from the ledger. Real Skater scenes, never ticked; contacts
# are fed by hand as HitTracker.opposing_contact would feed them.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const FULL: float = HitRules.FULL_CHECK_IMPULSE
const HITTER: int = 1   # team 0
const VICTIM: int = 2   # team 1
const SIZE: int = 5
const PERIOD_S: float = 240.0
const INTO_WALL := Vector3(1.0, 0.0, 0.0)

class _TeleportSpy extends SkaterController:
	var teleported_to: Array = []

	func teleport_to(pos: Vector3, _facing: Vector2 = Vector2.ZERO) -> void:
		teleported_to.append(pos)


var _registry: PlayerRegistry = null
var _tracker: PenaltyTracker = null
var _teams: Array[Team] = []
var _called: Array = []
var _whistles: Array[int] = []
var _boxed: Array[int] = []
var _released: Array[int] = []


func before_each() -> void:
	_registry = PlayerRegistry.new()
	_teams = [_make_team(0), _make_team(1)]
	_add_player(HITTER, 0)
	_add_player(VICTIM, 1)
	_called.clear()
	_whistles.clear()
	_boxed.clear()
	_released.clear()
	_tracker = PenaltyTracker.new()
	_tracker.setup(_registry, null, func() -> Puck: return null)
	_tracker.foul_called.connect(func(p: int, f: int) -> void: _called.append([p, f]))
	_tracker.possession_whistle.connect(func(t: int) -> void: _whistles.append(t))
	_tracker.skater_boxed.connect(func(p: int) -> void: _boxed.append(p))
	_tracker.skater_released.connect(func(p: int) -> void: _released.append(p))


func _make_team(team_id: int) -> Team:
	var t := Team.new()
	t.team_id = team_id
	return t


func _add_player(peer_id: int, team_id: int) -> PlayerRecord:
	var record := PlayerRecord.new(peer_id, 0, false, _teams[team_id])
	record.skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(record.skater)
	record.skater.set_physics_process(false)
	record.skater.set_process(false)
	_registry._players[peer_id] = record
	return record


func _skater(peer_id: int) -> Skater:
	return _registry.get_record(peer_id).skater


# Half a metre off the +X boards at centre ice.
func _put_victim_by_the_boards(facing: Vector2) -> void:
	var victim: Skater = _skater(VICTIM)
	var at: Vector2 = GameRules.clamp_to_rink_inner(
			Vector2(100.0, 0.0), victim.collision_radius() + 0.5)
	victim.global_position = Vector3(at.x, GameRules.FACEOFF_SPAWN_HEIGHT, at.y)
	victim.set_facing(facing)


func _check(force: float = FULL, victim_is_carrier: bool = true,
		since_loss: float = INF) -> void:
	_tracker.on_opposing_contact(HITTER, VICTIM, force, INTO_WALL, false,
			victim_is_carrier, since_loss, true)


func _box_the_hitter() -> void:
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.BOARDING)
	_tracker.assess_pending(PERIOD_S, SIZE)


# ── The call ─────────────────────────────────────────────────────────────────

func test_a_carrier_hit_from_behind_into_the_boards_is_called_boarding() -> void:
	_put_victim_by_the_boards(Vector2(1.0, 0.0))
	_check()
	assert_eq(_called, [[HITTER, PenaltyRules.Foul.BOARDING]])
	assert_true(_tracker.ledger.has_pending_against(0))
	assert_false(_skater(HITTER).in_box, "play goes on until his team has the puck")


func test_the_same_hit_on_a_man_who_sees_it_is_clean() -> void:
	_put_victim_by_the_boards(Vector2(-1.0, 0.0))
	_check()
	assert_eq(_called, [])


func test_a_check_on_a_man_away_from_the_puck_is_called_interference() -> void:
	_skater(VICTIM).global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_check(FULL, false)
	assert_eq(_called, [[HITTER, PenaltyRules.Foul.INTERFERENCE]])


func test_finishing_a_check_on_a_man_who_just_passed_is_clean() -> void:
	_skater(VICTIM).global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_check(FULL, false, HitRules.JUST_RELEASED_GRACE_S)
	assert_eq(_called, [])


func test_sustained_contact_calls_one_foul() -> void:
	_put_victim_by_the_boards(Vector2(1.0, 0.0))
	_check()
	_check()
	assert_eq(_called.size(), 1)
	assert_eq(_tracker.ledger.entries.size(), 1)


func test_a_ghost_is_not_judged() -> void:
	_put_victim_by_the_boards(Vector2(1.0, 0.0))
	_skater(VICTIM).is_ghost = true
	_check()
	assert_eq(_called, [])


# ── The delayed whistle ──────────────────────────────────────────────────────

func test_the_whistle_waits_for_the_offending_team_to_have_the_puck() -> void:
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.BOARDING)
	_tracker.on_possession_established(1)
	assert_eq(_whistles, [] as Array[int], "the fouled team plays on")
	_tracker.on_possession_established(0)
	assert_eq(_whistles, [0] as Array[int])


func test_a_goal_by_the_fouled_team_washes_the_call_out() -> void:
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.BOARDING)
	_tracker.on_goal(1, SIZE)
	_tracker.assess_pending(PERIOD_S, SIZE)
	assert_false(_skater(HITTER).in_box)
	assert_true(_tracker.ledger.is_empty())


# ── The box ──────────────────────────────────────────────────────────────────

func test_an_assessed_minor_boxes_the_skater() -> void:
	_box_the_hitter()
	assert_true(_skater(HITTER).in_box)
	assert_false(_skater(VICTIM).in_box)
	assert_eq(_boxed, [HITTER] as Array[int])
	assert_eq(_tracker.short_handed_team(SIZE), 0)


func test_a_boxed_skater_is_hidden_once_play_is_live() -> void:
	_box_the_hitter()
	_skater(HITTER).global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_tracker.update_visibility(true)
	assert_true(_skater(HITTER).visible, "still skating to the box during the prep")
	_tracker.update_visibility(false)
	assert_false(_skater(HITTER).visible)
	assert_true(_skater(VICTIM).visible)


func test_a_boxed_skater_is_hidden_at_his_door_during_the_prep() -> void:
	_box_the_hitter()
	_skater(HITTER).global_position = PlayerRules.penalty_box_position(0)
	_tracker.update_visibility(true)
	assert_false(_skater(HITTER).visible)


func test_a_minor_that_runs_out_puts_him_back_on_the_ice() -> void:
	_box_the_hitter()
	_tracker.update_visibility(false)
	_tracker.tick(PenaltyRules.minor_seconds(PERIOD_S) + 0.1, SIZE)
	assert_false(_skater(HITTER).in_box)
	assert_true(_skater(HITTER).visible)
	assert_eq(_released, [HITTER] as Array[int])
	assert_eq(_tracker.short_handed_team(SIZE), -1)


func test_a_power_play_goal_releases_him() -> void:
	_box_the_hitter()
	_tracker.on_goal(1, SIZE)
	assert_false(_skater(HITTER).in_box)
	assert_eq(_released, [HITTER] as Array[int])


# ── A skater who arrives late ────────────────────────────────────────────────

func test_a_skater_who_arrives_during_a_penalty_shot_is_held_at_his_bench() -> void:
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.INTERFERENCE, VICTIM)
	_tracker.assess_pending(PERIOD_S, 3)
	var late: PlayerRecord = _add_player(9, 0)
	late.team_slot = 1
	var controller := _TeleportSpy.new()
	autofree(controller)
	late.controller = controller
	_tracker.seat_late_arrival(late)
	assert_true(late.skater.sidelined)
	assert_eq(controller.teleported_to, [PlayerRules.bench_start_position(0, 1)])


func test_a_skater_who_arrives_in_open_play_is_left_where_he_spawned() -> void:
	var late: PlayerRecord = _add_player(9, 0)
	var controller := _TeleportSpy.new()
	autofree(controller)
	late.controller = controller
	_tracker.seat_late_arrival(late)
	assert_false(late.skater.sidelined)
	assert_eq(controller.teleported_to, [])


# ── Changing seats ───────────────────────────────────────────────────────────

func test_a_man_with_a_call_or_a_minor_against_him_keeps_his_seat() -> void:
	assert_false(_tracker.holds_in_seat(HITTER))
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.BOARDING, VICTIM)
	assert_true(_tracker.holds_in_seat(HITTER), "the call is pending against his team")
	assert_false(_tracker.holds_in_seat(VICTIM))
	_tracker.assess_pending(PERIOD_S, SIZE)
	assert_true(_tracker.holds_in_seat(HITTER), "he is in the box")


func test_nobody_changes_seats_during_a_penalty_shot() -> void:
	_add_player(9, 0)
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.INTERFERENCE, VICTIM)
	_tracker.assess_pending(PERIOD_S, 3)
	assert_true(_tracker.holds_in_seat(9))
	_tracker.end_shot()
	assert_false(_tracker.holds_in_seat(9))


# ── What it costs, for the stat sheet ────────────────────────────────────────

func test_a_minor_and_a_penalty_shot_are_each_a_penalty_to_the_man_who_fouled() -> void:
	var assessed: Array[int] = []
	_tracker.penalty_assessed.connect(func(p: int) -> void: assessed.append(p))
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.BOARDING, VICTIM)
	assert_eq(assessed, [] as Array[int], "a call is not a penalty until it is paid for")
	_tracker.assess_pending(PERIOD_S, SIZE)
	assert_eq(assessed, [HITTER] as Array[int])
	_tracker.clear()
	_tracker.ledger.call_foul(VICTIM, 1, PenaltyRules.Foul.INTERFERENCE, HITTER)
	_tracker.assess_pending(PERIOD_S, 3)
	assert_eq(assessed, [HITTER, VICTIM] as Array[int], "the shot is VICTIM's foul")


func test_a_call_washed_out_by_a_goal_is_no_penalty() -> void:
	var assessed: Array[int] = []
	_tracker.penalty_assessed.connect(func(p: int) -> void: assessed.append(p))
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.BOARDING, VICTIM)
	_tracker.on_goal(1, SIZE)
	_tracker.assess_pending(PERIOD_S, SIZE)
	assert_eq(assessed, [] as Array[int])


# ── A fight ──────────────────────────────────────────────────────────────────

func test_both_fighters_are_called_when_the_fights_are_over() -> void:
	_tracker.note_fight(HITTER, VICTIM)
	assert_true(_tracker.ledger.is_empty(), "nothing is called while they fight")
	_tracker.call_fighters()
	assert_eq(_called, [[HITTER, PenaltyRules.Foul.FIGHTING], [VICTIM, PenaltyRules.Foul.FIGHTING]])
	_tracker.assess_pending(PERIOD_S, SIZE)
	assert_true(_skater(HITTER).in_box)
	assert_true(_skater(VICTIM).in_box)
	assert_eq(_tracker.short_handed_team(SIZE), -1, "four on four: nobody is the short team")


func test_a_fight_is_called_once() -> void:
	_tracker.note_fight(HITTER, VICTIM)
	_tracker.call_fighters()
	_tracker.call_fighters()
	assert_eq(_called.size(), 2)


func test_a_fighter_who_has_left_is_not_called() -> void:
	_tracker.note_fight(HITTER, 99)
	_tracker.call_fighters()
	assert_eq(_called, [[HITTER, PenaltyRules.Foul.FIGHTING]])


# ── The penalty shot (3v3) ───────────────────────────────────────────────────

func _stage_a_shot_for_the_victim() -> Array:
	var events: Array = []
	_tracker.shot_staged.connect(func(p: int) -> void: events.append(["staged", p]))
	_tracker.shot_over.connect(func() -> void: events.append(["over"]))
	_tracker.shot_missed.connect(func() -> void: events.append(["missed"]))
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.INTERFERENCE, VICTIM)
	_tracker.assess_pending(PERIOD_S, 3)
	return events


func test_in_3v3_a_foul_is_a_shot_for_the_man_fouled() -> void:
	var events: Array = _stage_a_shot_for_the_victim()
	assert_true(_tracker.is_shot_on())
	assert_true(_skater(VICTIM).takes_penalty_shot)
	assert_false(_skater(VICTIM).sidelined)
	assert_true(_skater(HITTER).sidelined, "everyone else watches")
	assert_false(_skater(HITTER).in_box, "nobody sits for it")
	assert_eq(events, [["staged", VICTIM]])


func test_a_shot_for_a_man_who_has_left_is_not_taken() -> void:
	_tracker.ledger.call_foul(HITTER, 0, PenaltyRules.Foul.INTERFERENCE, 99)
	_tracker.assess_pending(PERIOD_S, 3)
	assert_false(_tracker.is_shot_on())
	assert_true(_tracker.ledger.is_empty())


func test_a_shot_that_ends_puts_everyone_back_in_the_game() -> void:
	var events: Array = _stage_a_shot_for_the_victim()
	_tracker.end_shot()
	assert_false(_tracker.is_shot_on())
	assert_false(_skater(VICTIM).takes_penalty_shot)
	assert_false(_skater(HITTER).sidelined)
	assert_eq(events, [["staged", VICTIM], ["over"]])


func test_a_save_ends_the_shot_on_the_next_tick() -> void:
	var events: Array = _stage_a_shot_for_the_victim()
	_tracker.note_shot_saved()
	_tracker.tick_shot(1.0 / 90.0)
	assert_eq(events.back(), ["missed"])


func test_a_client_sidelines_everyone_but_the_shooter() -> void:
	var host := PenaltyLedger.new()
	host.call_foul(HITTER, 0, PenaltyRules.Foul.INTERFERENCE, VICTIM)
	host.stage_shot()
	_tracker.apply_remote(host.to_wire())
	assert_true(_skater(VICTIM).takes_penalty_shot)
	assert_true(_skater(HITTER).sidelined)
	_tracker.apply_remote([])
	assert_false(_skater(HITTER).sidelined)


func test_a_client_seats_the_box_from_the_hosts_ledger() -> void:
	var host := PenaltyLedger.new()
	host.call_foul(VICTIM, 1, PenaltyRules.Foul.INTERFERENCE)
	host.assess(24.0, 2)
	_tracker.apply_remote(host.to_wire())
	assert_true(_skater(VICTIM).in_box)
	_tracker.apply_remote([])
	assert_false(_skater(VICTIM).in_box)
	assert_eq(_released, [VICTIM] as Array[int])

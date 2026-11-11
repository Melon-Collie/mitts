extends GutTest

# Fights on the host (FightTracker): a press of the fight button challenges the
# opponent nearest in front of the presser, and a press by that man inside the
# window starts the fight. A bot answers only a man it holds a grudge against
# (his checks on its team), and calls out one it holds a big one against. A fight
# ends when the pair have been apart long enough or at the linesmen's cap, and
# everything goes when fighting is not allowed.
# Real Skater scenes, never ticked; positions, facings and presses by hand.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PLAYING := GamePhase.Phase.PLAYING
const TICK: float = 1.0 / 90.0

var _registry: PlayerRegistry = null
var _grudges: FightGrudges = null
var _fights: FightTracker = null
var _home: Skater = null     # team 0, peer 1
var _away: Skater = null     # team 1, peer 2
var _mate: Skater = null     # team 0, peer 3
var _carrier: Skater = null
var _now: float = 100.0
var _made: Array = []
var _lapsed: Array[Skater] = []
var _started: Array = []
var _over: int = 0


func before_each() -> void:
	_home = _spawn_skater()
	_away = _spawn_skater()
	_mate = _spawn_skater()
	_registry = PlayerRegistry.new()
	_registry._skaters_cache = [_home, _away, _mate] as Array[Skater]
	_registry.team_id_by_skater = {_home: 0, _away: 1, _mate: 0}
	_registry.peer_id_by_skater = {_home: 1, _away: 2, _mate: 3}
	_registry.team_id_by_peer = {1: 0, 2: 1, 3: 0}
	_grudges = FightGrudges.new()
	_carrier = null
	_now = 100.0
	_made.clear()
	_lapsed.clear()
	_started.clear()
	_over = 0
	_fights = FightTracker.new()
	_fights.setup(_registry, func() -> float: return _now, func() -> Skater: return _carrier,
			_grudges)
	_fights.challenge_made.connect(func(c: Skater, t: Skater) -> void: _made.append([c, t]))
	_fights.challenge_lapsed.connect(func(c: Skater) -> void: _lapsed.append(c))
	_fights.fight_started.connect(func(a: Skater, b: Skater) -> void: _started.append([a, b]))
	_fights.fights_over.connect(func() -> void: _over += 1)
	# Home and away face each other a body's width apart; the teammate stands
	# beside home, in front of nobody.
	_put(_home, Vector2(0.0, 0.0), Vector2(0.0, 1.0))
	_put(_away, Vector2(0.0, 1.2), Vector2(0.0, -1.0))
	_put(_mate, Vector2(-1.0, 0.0), Vector2(0.0, 1.0))


func _spawn_skater() -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.set_physics_process(false)
	s.set_process(false)
	return s


func _put(s: Skater, at: Vector2, facing: Vector2) -> void:
	s.global_position = Vector3(at.x, GameRules.FACEOFF_SPAWN_HEIGHT, at.y)
	s.set_facing(facing)


func _press(s: Skater, phase: int = PLAYING) -> void:
	s.fight_press_pending = true
	_fights.tick(TICK, true, phase)


func test_a_press_challenges_the_man_in_front_and_his_press_starts_the_fight() -> void:
	_press(_home)
	assert_eq(_made, [[_home, _away]])
	assert_eq(_fights.challenge_target_of(_home), _away)
	assert_false(_fights.is_fighting(_home), "a challenge alone is not a fight")
	_now += 1.0
	_press(_away)
	assert_eq(_started, [[_home, _away]])
	assert_true(_fights.is_fighting(_home) and _fights.is_fighting(_away))
	assert_eq(_fights.partner_of(_away), _home)
	assert_null(_fights.challenge_target_of(_home), "the challenge is spent")


func test_the_press_is_read_once() -> void:
	_press(_home)
	assert_false(_home.fight_press_pending)
	_fights.tick(TICK, true, PLAYING)
	assert_eq(_made.size(), 1)


func test_nobody_in_front_or_only_a_teammate_challenges_nobody() -> void:
	_put(_home, Vector2.ZERO, Vector2(0.0, -1.0))
	_press(_home)
	assert_true(_made.is_empty(), "the opponent is behind him")
	_put(_mate, Vector2(0.0, -1.0), Vector2(0.0, 1.0))
	_press(_home)
	assert_true(_made.is_empty(), "his teammate is no one to fight")


func test_an_unanswered_challenge_lapses_and_cools_down() -> void:
	_press(_home)
	_now += FightRules.CHALLENGE_WINDOW_S + 0.01
	_fights.tick(TICK, true, PLAYING)
	assert_eq(_lapsed, [_home] as Array[Skater])
	assert_null(_fights.challenge_target_of(_home))
	_press(_away)
	assert_true(_started.is_empty(), "a lapsed challenge cannot be answered")
	_made.clear()
	_press(_home)
	assert_true(_made.is_empty(), "inside the cooldown he cannot call out again")
	_now += FightRules.CHALLENGE_COOLDOWN_S
	_press(_home)
	assert_eq(_made.size(), 1, "after it he can")


func test_an_answer_from_too_far_does_not_start_it() -> void:
	_press(_home)
	_put(_away, Vector2(0.0, FightRules.ACCEPT_RANGE_M + 0.5), Vector2(0.0, -1.0))
	_press(_away)
	assert_true(_started.is_empty())


# `n` full-strength checks by `hitter` on `victim`.
func _checks(hitter: int, victim: int, n: int) -> void:
	for i: int in n:
		_fights.note_check(hitter, victim, HitRules.FULL_CHECK_IMPULSE)


func test_a_bot_holding_nothing_against_him_lets_his_challenge_lapse() -> void:
	_registry.bot_peers[2] = true
	_press(_home)
	assert_eq(_made, [[_home, _away]])
	assert_true(_started.is_empty(), "no answer")
	_now += FightRules.CHALLENGE_WINDOW_S + 0.01
	_fights.tick(TICK, true, PLAYING)
	assert_eq(_lapsed, [_home] as Array[Skater])


func test_hit_enough_a_bot_answers_at_once() -> void:
	_registry.bot_peers[2] = true
	_checks(1, 2, 2)
	_press(_home)
	assert_eq(_started, [[_home, _away]], "on the challenge's own tick")


func test_checks_on_its_teammate_count_for_less() -> void:
	_registry.bot_peers[2] = true
	var fourth: Skater = _spawn_skater()
	_registry._skaters_cache.append(fourth)
	_registry.team_id_by_skater[fourth] = 1
	_registry.peer_id_by_skater[fourth] = 4
	_registry.team_id_by_peer[4] = 1
	_put(fourth, Vector2(5.0, 5.0), Vector2(0.0, -1.0))
	_checks(1, 4, 2)
	assert_almost_eq(_grudges.level(2, 1, _now),
			FightGrudgeRules.ACCEPT_LEVEL * FightGrudgeRules.TEAMMATE_SHARE, 1e-4)
	_press(_home)
	assert_true(_started.is_empty(), "two hits on his mate are not enough")


func test_a_bot_never_holds_its_own_teammate_s_check() -> void:
	_registry.bot_peers[3] = true
	_checks(1, 3, 4)
	assert_eq(_grudges.level(3, 1, _now), 0.0)


func test_hit_more_a_bot_calls_out_the_man() -> void:
	_registry.bot_peers[2] = true
	_checks(1, 2, 3)
	_fights.tick(TICK, true, PLAYING)
	assert_true(_made.is_empty(), "short of the challenge level")
	_checks(1, 2, 1)
	_fights.tick(TICK, true, PLAYING)
	assert_eq(_made, [[_away, _home]])
	assert_eq(_away.fight_role, FightRules.Role.CHALLENGING)
	_press(_home)
	assert_eq(_started, [[_away, _home]], "and his press answers it")


func test_a_bot_calls_out_only_the_man_it_holds_it_against() -> void:
	_registry.bot_peers[2] = true
	_checks(3, 2, 4)  # the teammate did the hitting, and is off to the side
	_put(_mate, Vector2(-4.0, 0.0), Vector2(0.0, 1.0))
	_fights.tick(TICK, true, PLAYING)
	assert_true(_made.is_empty(), "the man in front never touched him")
	_put(_mate, Vector2(0.4, 0.2), Vector2(0.0, 1.0))
	_fights.tick(TICK, true, PLAYING)
	assert_eq(_made, [[_away, _mate]], "past a nearer man, to the one it wants")


func test_a_bot_with_the_puck_does_not_call_anyone_out() -> void:
	_registry.bot_peers[2] = true
	_checks(1, 2, 4)
	_carrier = _away
	_fights.tick(TICK, true, PLAYING)
	assert_true(_made.is_empty())


func test_a_fight_spends_both_grudges() -> void:
	_registry.bot_peers[1] = true
	_registry.bot_peers[2] = true
	_checks(1, 2, 4)
	_checks(2, 1, 2)
	_fights.tick(TICK, true, PLAYING)
	assert_eq(_started, [[_away, _home]], "a bot calls out a bot, which answers")
	assert_eq(_grudges.level(2, 1, _now), 0.0)
	assert_eq(_grudges.level(1, 2, _now), 0.0)


func test_a_carrier_cannot_challenge_but_can_be_challenged() -> void:
	_carrier = _home
	_press(_home)
	assert_true(_made.is_empty())
	_carrier = _away
	_press(_home)
	_press(_away)
	assert_eq(_started.size(), 1)


func test_no_press_counts_outside_the_phases_a_fight_starts_in() -> void:
	for phase: int in [GamePhase.Phase.GOAL_CELEBRATION, GamePhase.Phase.FACEOFF_PREP]:
		_press(_home, phase)
		assert_true(_made.is_empty(), GamePhase.Phase.keys()[phase])
		assert_false(_home.fight_press_pending, "and the press is gone, not saved for later")


func test_a_fight_ends_once_they_have_been_apart_long_enough() -> void:
	_press(_home)
	_press(_away)
	_put(_away, Vector2(0.0, FightRules.DISENGAGE_M + 1.0), Vector2(0.0, -1.0))
	var ticks: int = ceili(FightRules.DISENGAGE_S / TICK) + 1
	for i: int in ticks:
		_fights.tick(TICK, true, GamePhase.Phase.FIGHT)
	assert_false(_fights.is_fighting(_home))
	assert_eq(_over, 1)


func test_the_linesmen_end_it() -> void:
	_press(_home)
	_press(_away)
	_now += FightRules.FIGHT_MAX_S
	_fights.tick(TICK, true, GamePhase.Phase.FIGHT)
	assert_false(_fights.is_fighting(_away))
	assert_eq(_over, 1)


func test_a_second_pair_can_start_inside_the_stoppage() -> void:
	_press(_home)
	_press(_away)
	var fourth: Skater = _spawn_skater()
	_registry._skaters_cache.append(fourth)
	_registry.team_id_by_skater[fourth] = 1
	_registry.peer_id_by_skater[fourth] = 4
	_put(fourth, Vector2(-1.0, 1.2), Vector2(0.0, -1.0))
	_press(_mate, GamePhase.Phase.FIGHT)
	_press(fourth, GamePhase.Phase.FIGHT)
	assert_eq(_started.size(), 2)
	assert_eq(_fights.partner_of(_mate), fourth)


func test_disallowed_clears_everything() -> void:
	_press(_home)
	_press(_away)
	_mate.fight_press_pending = true
	_fights.tick(TICK, false, GamePhase.Phase.FIGHT)
	assert_false(_fights.is_fighting(_home))
	assert_false(_mate.fight_press_pending)
	assert_eq(_over, 0, "nothing to whistle back on")


func test_fights_left_over_after_play_moved_on_are_dropped() -> void:
	_press(_home)
	_press(_away)
	_fights.tick(TICK, true, GamePhase.Phase.FACEOFF_PREP)
	assert_false(_fights.is_fighting(_home))
	_press(_home)
	assert_eq(_made.size(), 2, "and both may fight again")


func test_the_tracker_writes_each_mans_role() -> void:
	_press(_home)
	assert_eq(_home.fight_role, FightRules.Role.CHALLENGING)
	assert_eq(_away.fight_role, FightRules.Role.NONE, "called out is not yet fighting")
	_press(_away)
	assert_eq(_home.fight_role, FightRules.Role.FIGHTING)
	assert_eq(_away.fight_role, FightRules.Role.FIGHTING)
	_now += FightRules.FIGHT_MAX_S
	_fights.tick(TICK, true, GamePhase.Phase.FIGHT)
	assert_eq(_home.fight_role, FightRules.Role.NONE)
	assert_eq(_away.fight_role, FightRules.Role.NONE)


func test_a_lapsed_challenge_stands_the_challenger_down() -> void:
	_press(_home)
	_now += FightRules.CHALLENGE_WINDOW_S + 0.01
	_fights.tick(TICK, true, PLAYING)
	assert_eq(_home.fight_role, FightRules.Role.NONE)


func test_clear_stands_everyone_down() -> void:
	_press(_home)
	_press(_away)
	_mate.fight_role = FightRules.Role.FIGHTING  # as a goal replay's stamp would leave it
	_fights.clear()
	for s: Skater in [_home, _away, _mate]:
		assert_eq(s.fight_role, FightRules.Role.NONE)


func test_a_man_put_down_ends_the_fight() -> void:
	_press(_home)
	_press(_away)
	_away.is_knocked_down = true
	_fights.tick(TICK, true, GamePhase.Phase.FIGHT)
	assert_false(_fights.is_fighting(_home))
	assert_eq(_over, 1)

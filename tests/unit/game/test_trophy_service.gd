extends GutTest

# TrophyService at game-over and on its live hooks, against an injected ledger,
# Steam totals and save step, so nothing touches the real prefs file. Steam is
# unavailable headless, so the mirror and the import stay inert here.

var _totals: Dictionary = {}
var _ledger: TrophyLedger = null
var _saves: int = 0
var _pucks: Array[Array] = []
var _banners: Array[String] = []
var _service: TrophyService = null


func before_each() -> void:
	_totals = {}
	_ledger = TrophyLedger.new()
	_saves = 0
	_pucks.clear()
	_banners.clear()
	_service = TrophyService.new(func() -> Dictionary: return _totals,
			func() -> TrophyLedger: return _ledger, func() -> void: _saves += 1)
	_service.puck_earned.connect(func(id: String, target: int) -> void: _pucks.append([id, target]))
	_service.banner_raised.connect(func(id: String) -> void: _banners.append(id))


func _game(goals: int) -> PlayerStats:
	var s := PlayerStats.new()
	s.goals = goals
	return s


func test_a_hat_trick_game_earns_and_saves_its_pucks() -> void:
	_service.evaluate_game_over(_game(3), {"outcome": "win", "goals_for": 3, "goals_against": 0},
			[], 0, {})
	assert_true(_ledger.has("hat_trick"))
	assert_true(_ledger.has("first_goal"))
	assert_true(_ledger.has("shutout"))
	assert_has(_pucks, ["hat_trick", 0])
	assert_eq(_saves, 1, "one save for the game")


func test_a_repeat_earns_nothing_and_saves_nothing() -> void:
	var ctx: Dictionary = {"outcome": "loss", "goals_for": 3, "goals_against": 4}
	_service.evaluate_game_over(_game(3), ctx, [], 0, {})
	_pucks.clear()
	_service.evaluate_game_over(_game(3), ctx, [], 0, {})
	assert_eq(_pucks.size(), 0)
	assert_eq(_saves, 1)


func test_crossing_a_ladder_tier_and_raising_a_banner_are_announced() -> void:
	var before: Dictionary = {"goals": 49, "hits": 50}
	_totals = {"goals": 50, "hits": 50}
	_service.evaluate_game_over(_game(0), {"outcome": "loss"}, [], 0, before)
	assert_has(_pucks, ["goals", 50])
	assert_eq(_banners, ["power_forward"] as Array[String])
	assert_eq(_saves, 0, "a ladder tier is derived, never stored")


func test_a_banner_already_raised_is_not_announced_again() -> void:
	_totals = {"goals": 60, "hits": 60}
	_service.evaluate_game_over(_game(0), {"outcome": "loss"}, [], 0, _totals)
	assert_eq(_banners.size(), 0)


func test_a_big_hit_earns_its_puck_once() -> void:
	var threshold: float = GamePucks.event_threshold("big_hit")
	_service.on_local_hit(threshold - 0.1)
	assert_false(_ledger.has(GamePucks.FREIGHT_TRAIN), "below the bar")
	_service.on_local_hit(threshold)
	_service.on_local_hit(threshold + 5.0)
	assert_true(_ledger.has(GamePucks.FREIGHT_TRAIN))
	assert_eq(_pucks, [[GamePucks.FREIGHT_TRAIN, 0]] as Array[Array])
	assert_eq(_saves, 1)


func test_the_meta_hooks_earn_their_pucks() -> void:
	_service.on_tutorials_complete()
	_service.on_build_edited()
	assert_true(_ledger.has(GamePucks.STUDENT))
	assert_true(_ledger.has(GamePucks.CUSTOM_BUILD))

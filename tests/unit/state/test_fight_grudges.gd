extends GutTest

# FightGrudges and FightGrudgeRules: a bot's grudge against a man rises with his
# checks by their force, its teammates' by a share, drains slowly on its own,
# caps, and is spent by a fight. Each holder's grudge against each man is its own.

const FULL := HitRules.FULL_CHECK_IMPULSE

var _g := FightGrudges.new()


func before_each() -> void:
	_g = FightGrudges.new()


func test_two_full_checks_reach_the_accept_level_and_four_the_challenge() -> void:
	assert_almost_eq(FightGrudgeRules.victim_gain(FULL) * 2.0, FightGrudgeRules.ACCEPT_LEVEL, 1e-6)
	assert_almost_eq(FightGrudgeRules.victim_gain(FULL) * 4.0, FightGrudgeRules.CHALLENGE_LEVEL, 1e-6)


func test_a_harder_check_counts_for_more_and_a_teammate_for_a_share() -> void:
	assert_gt(FightGrudgeRules.victim_gain(HitRules.KNOCKDOWN_IMPULSE), FightGrudgeRules.victim_gain(FULL))
	assert_almost_eq(FightGrudgeRules.teammate_gain(FULL),
			FightGrudgeRules.victim_gain(FULL) * FightGrudgeRules.TEAMMATE_SHARE, 1e-6)


func test_it_drains_on_its_own() -> void:
	_g.raise(2, 1, 1.0, 10.0)
	assert_almost_eq(_g.level(2, 1, 10.0), 1.0, 1e-6)
	assert_almost_eq(_g.level(2, 1, 10.0 + 90.0), 1.0 - FightGrudgeRules.DECAY_PER_S * 90.0, 1e-5)
	assert_eq(_g.level(2, 1, 10.0 + 1000.0), 0.0, "never below nothing")


func test_a_raise_adds_to_what_is_left_and_caps() -> void:
	_g.raise(2, 1, 1.0, 0.0)
	_g.raise(2, 1, 1.0, 60.0)
	assert_almost_eq(_g.level(2, 1, 60.0), 2.0 - FightGrudgeRules.DECAY_PER_S * 60.0, 1e-5)
	for i: int in 10:
		_g.raise(2, 1, 1.0, 60.0)
	assert_eq(_g.level(2, 1, 60.0), FightGrudgeRules.MAX_LEVEL)


func test_each_pair_is_its_own() -> void:
	_g.raise(2, 1, 1.5, 0.0)
	_g.raise(2, 3, 0.5, 0.0)
	assert_eq(_g.level(1, 2, 0.0), 0.0, "not both ways round")
	assert_eq(_g.angriest_at(2, 0.0), 1)
	assert_eq(_g.angriest_at(1, 0.0), -1)


func test_the_angriest_ties_to_the_lower_peer() -> void:
	_g.raise(2, 7, 1.0, 0.0)
	_g.raise(2, 4, 1.0, 0.0)
	assert_eq(_g.angriest_at(2, 0.0), 4)


func test_a_fight_settles_it_and_a_clear_ends_all() -> void:
	_g.raise(2, 1, 1.5, 0.0)
	_g.raise(2, 3, 0.5, 0.0)
	_g.settle(2, 1)
	assert_eq(_g.level(2, 1, 0.0), 0.0)
	assert_almost_eq(_g.level(2, 3, 0.0), 0.5, 1e-6, "his grudge against the other man stays")
	_g.clear()
	assert_eq(_g.angriest_at(2, 0.0), -1)

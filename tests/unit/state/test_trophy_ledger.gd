extends GutTest

# TrophyLedger — the stored part of a player's Game Pucks. It only grows: a
# merge keeps every puck either copy holds, so a Steam Cloud adopt never loses
# one, and a load never fails on what a prefs file held.


func test_earn_records_once() -> void:
	var ledger := TrophyLedger.new()
	assert_true(ledger.earn("hat_trick", 100))
	assert_false(ledger.earn("hat_trick", 200), "already earned")
	assert_eq(ledger.earned_at("hat_trick"), 100, "the first date stands")
	assert_false(ledger.earn("", 100))


func test_merge_keeps_every_puck_either_copy_holds() -> void:
	var here := TrophyLedger.new()
	here.earn("hat_trick", 100)
	var cloud := TrophyLedger.new()
	cloud.earn("shutout", 300)
	assert_true(here.merge(cloud))
	assert_true(here.has("hat_trick"))
	assert_true(here.has("shutout"))
	assert_false(here.merge(cloud), "nothing new the second time")


func test_merge_keeps_the_earliest_known_date() -> void:
	var here := TrophyLedger.new()
	here.earn("hat_trick", 500)
	here.earn("shutout", 0)
	var other := TrophyLedger.new()
	other.earn("hat_trick", 200)
	other.earn("shutout", 900)
	here.merge(other)
	assert_eq(here.earned_at("hat_trick"), 200)
	assert_eq(here.earned_at("shutout"), 900, "a known date replaces an unknown one")
	var unknown := TrophyLedger.new()
	unknown.earn("hat_trick", 0)
	assert_false(here.merge(unknown), "an unknown date never replaces a known one")


func test_round_trip_through_a_dictionary() -> void:
	var ledger := TrophyLedger.new()
	ledger.earn("hat_trick", 100)
	ledger.earn("a_puck_from_a_newer_build", 7)
	var back := TrophyLedger.from_variant(ledger.to_dict())
	assert_eq(back.size(), 2)
	assert_eq(back.earned_at("hat_trick"), 100)
	assert_true(back.has("a_puck_from_a_newer_build"), "unknown ids are kept, not dropped")


func test_a_malformed_save_loads_what_it_can() -> void:
	assert_eq(TrophyLedger.from_variant("garbage").size(), 0)
	assert_eq(TrophyLedger.from_variant(null).size(), 0)
	var back := TrophyLedger.from_variant({"hat_trick": 5, "bad": "x", 3: 4, "": 1, "neg": -9})
	assert_eq(back.ids().size(), 2)
	assert_eq(back.earned_at("hat_trick"), 5)
	assert_eq(back.earned_at("neg"), 0)

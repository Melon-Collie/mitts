extends GutTest

# FeatTracker — who won the current possession back, held until the other team
# establishes one or play stops, and handed to a goal on that possession.

var feats: FeatTracker
var registry: PlayerRegistry


func before_each() -> void:
	registry = PlayerRegistry.new()
	for entry: Array in [[10, 0], [20, 1], [21, 1]]:
		var team := Team.new()
		team.team_id = int(entry[1])
		registry._players[int(entry[0])] = PlayerRecord.new(int(entry[0]), 0, false, team)
	feats = FeatTracker.new()
	feats.setup(registry)


func _filled(scoring_team: int) -> GoalFeatContext:
	var ctx := GoalFeatContext.new()
	feats.fill(ctx, scoring_team)
	return ctx


func test_a_goal_on_the_won_possession_names_who_won_it() -> void:
	feats.on_possession_won(20, FeatRules.WON_INTERCEPTION)
	feats.on_possession_established(21, 1)  # a teammate carries on
	var ctx := _filled(1)
	assert_eq(ctx.won_by, 20)
	assert_eq(ctx.won_kind, FeatRules.WON_INTERCEPTION)


func test_the_other_team_establishing_ends_it() -> void:
	feats.on_possession_won(20, FeatRules.WON_TAKEAWAY)
	feats.on_possession_established(10, 0)
	assert_eq(_filled(1).won_by, -1)


func test_a_stoppage_ends_it() -> void:
	feats.on_possession_won(20, FeatRules.WON_TAKEAWAY)
	feats.reset()
	assert_eq(_filled(1).won_by, -1)


func test_the_other_team_scoring_reads_nothing() -> void:
	feats.on_possession_won(20, FeatRules.WON_TAKEAWAY)
	assert_eq(_filled(0).won_by, -1)

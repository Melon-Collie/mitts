extends GutTest

# A goalie's cover stops play wherever there are faceoffs: NHL and Arcade
# whistle it; Off (free play) has none, so he plays it out himself.


func test_a_cover_whistles_wherever_there_are_faceoffs() -> void:
	assert_true(GameRules.whistles_a_cover(GameRules.RuleSet.NHL), "NHL")
	assert_true(GameRules.whistles_a_cover(GameRules.RuleSet.ARCADE), "Arcade")
	assert_false(GameRules.whistles_a_cover(GameRules.RuleSet.OFF), "Off: he plays it out")

extends GutTest

# A goalie who plays an iced puck waves the icing off, so while an icing race
# runs in his end the rim stop must not start.

func _puck_play() -> GoaliePuckPlay:
	var pp := GoaliePuckPlay.new()
	pp.goal_line_z = -GameRules.GOAL_LINE_Z
	pp.direction_sign = 1
	return pp


# A rim behind the -Z goal line, running across toward the stop point.
func _rim_pos() -> Vector3:
	return Vector3(-5.0, 0.0, -GameRules.GOAL_LINE_Z - 2.0)


func test_rim_is_considered_without_a_race() -> void:
	assert_true(_puck_play().may_consider(_rim_pos(), Vector3(8.0, 0.0, -1.0)))


func test_icing_race_holds_the_goalie_home() -> void:
	var pp := _puck_play()
	pp.icing_hold = true
	assert_false(pp.may_consider(_rim_pos(), Vector3(8.0, 0.0, -1.0)))

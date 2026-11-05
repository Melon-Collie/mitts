extends GutTest

# The threat grid's cells and solve (AIThreatGrid, docs/xt-plan.md §3): every
# spot on the ice in exactly one cell, no cell across a goal line or blue line,
# the other side's frame its own inverse, either net read in its attacker's
# frame alike, and the solve the closed form of a chain it can be checked on.

const GOAL_Z: float = -GameRules.GOAL_LINE_Z


func test_every_cell_holds_its_own_centre() -> void:
	for c: int in AIThreatGrid.cell_count():
		assert_eq(AIThreatGrid.cell_of(AIThreatGrid.centre(c)), c, "cell %d" % c)


func test_no_cell_straddles_a_line() -> void:
	var lines: Array[float] = [0.0, GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z,
			GameRules.GOAL_LINE_Z + GameRules.BLUE_LINE_Z, 2.0 * GameRules.GOAL_LINE_Z]
	for line: float in lines:
		for x: float in [-10.0, -3.0, 0.0, 3.0, 10.0]:
			var before: int = AIThreatGrid.cell_of(Vector2(x, line - 0.01))
			var after: int = AIThreatGrid.cell_of(Vector2(x, line + 0.01))
			assert_ne(before, after, "the line at %.2f splits the cells at x %.1f" % [line, x])


func test_the_other_sides_frame_is_its_own_inverse() -> void:
	for p: Vector2 in [Vector2(0.0, 0.0), Vector2(-7.5, 4.0), Vector2(11.0, 30.0), Vector2(3.0, 55.0)]:
		assert_almost_eq(AIThreatGrid.other_side(AIThreatGrid.other_side(p)), p, Vector2(1e-4, 1e-4))


func test_either_net_reads_its_attacker_alike() -> void:
	# A spot 6 m out on the glove side of the net at −Z, and the same spot for
	# the side attacking +Z: the rink turned end for end.
	var at := Vector3(2.0, 0.0, GOAL_Z + 6.0)
	var mirrored := Vector3(-2.0, 0.0, -GOAL_Z - 6.0)
	assert_almost_eq(AIThreatGrid.local(at, Vector3(0.0, 0.0, GOAL_Z)),
			AIThreatGrid.local(mirrored, Vector3(0.0, 0.0, -GOAL_Z)), Vector2(1e-4, 1e-4))


func test_the_other_sides_view_is_where_it_attacks() -> void:
	# The puck at a spot, read by the side attacking −Z, then by the side
	# attacking +Z, is that spot turned end for end.
	var world := Vector3(4.0, 0.0, 3.0)
	var ours: Vector2 = AIThreatGrid.local(world, Vector3(0.0, 0.0, GOAL_Z))
	var theirs: Vector2 = AIThreatGrid.local(world, Vector3(0.0, 0.0, -GOAL_Z))
	assert_almost_eq(AIThreatGrid.other_side(ours), theirs, Vector2(1e-4, 1e-4))


func _outcome(weight: float, to: int, theirs: bool = false, terminal: float = 0.0) -> AIThreatGrid.Outcome:
	var o := AIThreatGrid.Outcome.new()
	o.weight = weight
	o.to = to
	o.theirs = theirs
	o.terminal = terminal
	return o


func test_the_solve_is_the_closed_form_of_a_chain() -> void:
	# Two states: from 0, a goal (worth 1) with weight a, or on to 1 with weight
	# b; from 1, back to 0 as a turnover (theirs) with weight c, or a goal with
	# weight d. V0 = a + b·V1, V1 = −c·V0 + d.
	var a: float = 0.1
	var b: float = 0.6
	var c: float = 0.3
	var d: float = 0.2
	var outcomes: Array = [
			[_outcome(a, -1, false, 1.0), _outcome(b, 1)],
			[_outcome(c, 0, true), _outcome(d, -1, false, 1.0)]]
	var v: PackedFloat32Array = AIThreatGrid.solve(outcomes)
	var v0: float = (a + b * d) / (1.0 + b * c)
	assert_almost_eq(v[0], v0, 1e-5, "V0")
	assert_almost_eq(v[1], -c * v0 + d, 1e-5, "V1")

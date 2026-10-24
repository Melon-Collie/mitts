extends GutTest

# A shot-field cell must measure the same whatever the generator ran before it,
# or the field depends on how its cells were sharded. Representative cells
# (a set keeper in the body solve's sleep band, a set keeper in tight, a caught
# feed, a decoy) are measured, a different cell is shot at, and the same cells
# are measured again in reverse order.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z

var _s: RefCounted = null


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	var puck: Node = load("res://Scenes/Puck.tscn").instantiate()
	var shooter: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	var ctrl := KeeperController.new()
	add_child_autofree(goalie)
	add_child_autofree(puck)
	add_child_autofree(shooter)
	add_child_autofree(ctrl)
	_s = Stager.new(goalie, puck, ctrl, shooter)


func _at(x: float, fwd: float) -> Vector3:
	return Vector3(x, 0.0, GOAL_Z + fwd)


# [stage, one_timer, caught] per cell.
func _cells() -> Array:
	var far: Vector3 = _at(-6.0, 15.0)
	var near: Vector3 = _at(0.0, 6.0)
	var fed: Vector3 = _at(2.0, 3.5)
	var lured: Vector3 = _at(-2.0, 4.5)
	return [
		[func() -> Vector3: return _s.stage_set(far), false, false],
		[func() -> Vector3: return _s.stage_set(near), false, false],
		[func() -> Vector3: return _s.stage_feed(fed, _at(-4.0, 3.5), 20.0), false, true],
		[func() -> Vector3: return _s.stage_decoy(lured, _at(3.0, 4.5)), false, false],
	]


func _measure(cell: Array) -> String:
	return "|".join(_s.open_set(cell[0], cell[1], cell[2]))


func test_a_cell_measures_the_same_after_any_other() -> void:
	var cells: Array = _cells()
	var first: Array[String] = []
	for cell: Array in cells:
		first.append(_measure(cell))
	_s.open_set(func() -> Vector3: return _s.stage_feed(_at(4.0, 2.5), _at(-2.0, 2.5), 12.0),
			true, false)
	for i: int in range(cells.size() - 1, -1, -1):
		assert_eq(_measure(cells[i]), first[i],
				"cell %d measures the same after a different cell ran" % i)

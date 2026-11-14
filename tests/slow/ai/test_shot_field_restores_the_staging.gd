extends GutTest

# An open set fires every shot from the staging's world restored
# (shot_odds_stager.gd), not re-staged: it must measure what re-staging before
# every shot does, or the shot field depends on the shortcut. Representative
# cells (a set keeper, feeds caught and one-timed, decoys, a wrap, drives) are
# measured both ways.

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


# [name, stage, one_timer, caught, driven] per cell.
func _cells() -> Array:
	return [
		["set", func() -> Vector3: return _s.stage_set(_at(-4.0, 7.5)), false, false, false],
		["caught feed", func() -> Vector3: return _s.stage_feed(_at(2.0, 3.5), _at(-4.0, 3.5), 20.0),
				false, true, false],
		["one-timed feed", func() -> Vector3: return _s.stage_feed(_at(3.0, 6.0), _at(-1.5, 6.0), 16.0),
				true, false, false],
		["decoy", func() -> Vector3: return _s.stage_decoy(_at(-2.0, 4.5), _at(3.0, 4.5)), false, false, false],
		["wrap", func() -> Vector3: return _s.stage_wrap(_at(1.0, 1.5), _at(1.2, -1.6)), false, false, false],
		# Cells whose shots read what the first shot's save left in a packed
		# array, which a capture that shared it (rather than copied it) put back.
		["wide decoy", func() -> Vector3: return _s.stage_decoy(_at(-12.0, 7.5), _at(-3.0, 7.5)), false, false, false],
		["long caught feed", func() -> Vector3: return _s.stage_feed(_at(-8.0, 15.0), _at(-10.5, 15.0), 16.0),
				false, true, false],
		["long one-timed feed", func() -> Vector3: return _s.stage_feed(_at(-4.0, 17.5), _at(-10.0, 17.5), 20.0),
				true, false, false],
		["drive", func() -> Vector3: return _s.stage_drive(_at(1.0, 6.0)), false, false, true],
		["drive and deke", func() -> Vector3: return _s.stage_drive_deke(_at(0.0, 4.5), 1.0), false, false,
				false],
	]


func test_restored_shots_measure_what_restaged_ones_do() -> void:
	for cell: Array in _cells():
		_s.restage_every_shot = true
		var restaged: String = "|".join(_s.open_set(cell[1], cell[2], cell[3], cell[4]))
		_s.restage_every_shot = false
		var restored: String = "|".join(_s.open_set(cell[1], cell[2], cell[3], cell[4]))
		assert_eq(restored, restaged, "%s: restored as re-staged" % cell[0])

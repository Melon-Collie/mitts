extends GutTest

# expected_goals (the xG stat) — SHAPE contract at the DEFAULT (settled) release
# spread: bounded and goalie-aware.
# The execution half of the model (release spread, context, floor/ceiling) and
# the sanity band against the location-only baseline live in
# test_expected_goals_calibration.gd.


const Snapshot := preload("res://tests/snapshot.gd")
const GOAL := Vector3(0.0, 0.0, -30.0)   # a goal line; exact z is irrelevant to shape

func _nhw() -> float:
	return GameRules.NET_HALF_WIDTH


func _xg(shooter: Vector3, goalie: Vector3) -> float:
	return AIActionScoring.expected_goals(shooter, GOAL, goalie)


func test_bounded_in_zero_to_xg_max() -> void:
	# Sweep a grid of shooter/goalie geometries; every value stays in [0, XG_MAX].
	for dist: float in [2.0, 6.0, 10.0, 16.0, 22.0]:
		var shooter := Vector3(0.0, 0.0, GOAL.z + dist)
		for gx: float in [-1.0, 0.0, 1.0]:
			var goalie := Vector3(gx, 0.0, GOAL.z + 1.2)
			var xg := _xg(shooter, goalie)
			assert_between(xg, 0.0, AIActionScoring.XG_MAX,
					"xG in [0, XG_MAX] at dist=%.0f gx=%.1f (%.3f)" % [dist, gx, xg])


func test_beaten_goalie_beats_a_square_goalie() -> void:
	# The core grounded property: a goalie pulled off the shot line leaves open
	# net → higher xG than a goalie squared on the puck at the same shot.
	var shooter := Vector3(0.0, 0.0, GOAL.z + 6.0)
	var square := Vector3(0.0, 0.0, GOAL.z + 1.5)          # on the puck→net line
	var beaten := Vector3(_nhw() + 0.4, 0.0, GOAL.z + 0.3) # stranded at the far post
	assert_gt(_xg(shooter, beaten), _xg(shooter, square),
			"a beaten goalie yields more open net than a square one")


func test_a_keeper_stranded_outside_the_cone_concedes_the_empty_net() -> void:
	# Point-blank with the goalie stranded past the far post the look is the empty
	# net, short only of what he can push back across over the wind-up: the
	# field's decoy cells measure him drawn there.
	var shooter := Vector3(-1.0, 0.0, GOAL.z + 2.5)
	var stranded := Vector3(_nhw() + 0.4, 0.0, GOAL.z + 0.3)
	var pulled := Vector3(0.0, 0.0, 0.0)
	var empty: float = _xg(shooter, pulled)
	assert_almost_eq(_xg(shooter, stranded), empty, 0.1 * empty,
			"a keeper past the far post leaves the point-blank shot the empty net")


# The calibrated values at the reference looks; rewrite with
# MITTS_UPDATE_SNAPSHOTS=1 (tests/snapshot.gd) and review the diff.
func test_expected_goals_calibration_snapshot() -> void:
	var snap := Snapshot.new("res://tests/unit/ai/snapshots/expected_goals.txt")
	var shooter := Vector3(0.0, 0.0, GOAL.z + 3.0)
	snap.record("3 m, keeper square", _xg(shooter, Vector3(0.0, 0.0, GOAL.z + 0.9)))
	snap.record("6 m, keeper square", _xg(Vector3(0.0, 0.0, GOAL.z + 6.0),
			Vector3(0.0, 0.0, GOAL.z + 1.7)))
	snap.verify(self)

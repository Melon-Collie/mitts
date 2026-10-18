extends GutTest

# The accurate lane read with each defender's blade (AIPuckLane._blade_block): a
# stick already out over the passing lane takes the pass his body alone could not
# reach, and only a stick his body can hold there counts.

const FROM := Vector3(0.0, 0.0, 0.0)
const TO := Vector3(0.0, 0.0, -12.0)
const SPEED: float = 20.0
# Off the lane by more than a stick and what he closes before the puck passes,
# inside the arm, stick and blade a reaching defender holds out (2.06 m).
const BODY := Vector3(2.0, 0.0, -3.0)

var _opps: Array[Vector3] = [BODY]
var _vels: Array[Vector3] = [Vector3.ZERO]


func _lane(blade: Vector3, speed: float = SPEED) -> float:
	var blades: Array[Vector3] = [blade]
	return AIPuckLane.lane_clear(FROM, TO, _opps, speed, _vels, [], true, blades)


func _body_only() -> float:
	return AIPuckLane.lane_clear(FROM, TO, _opps, SPEED, _vels, [], true)


func test_a_body_out_of_reach_leaves_the_lane_open() -> void:
	assert_eq(_body_only(), 1.0, "the fixture's body cannot reach the lane")


func test_a_stick_out_over_the_lane_takes_the_pass() -> void:
	assert_lt(_lane(Vector3(0.5, 0.0, -2.8)), 0.5,
			"a blade a stride off the line, the puck passing it a tenth of a second out")


func test_a_stick_held_away_from_the_lane_changes_nothing() -> void:
	assert_eq(_lane(BODY + Vector3(1.5, 0.0, 0.0)), _body_only())


func test_a_stick_the_body_cannot_hold_does_not_count() -> void:
	var far: Array[Vector3] = [Vector3(3.5, 0.0, -3.0)]
	var blades: Array[Vector3] = [Vector3(0.3, 0.0, -3.0)]
	assert_eq(AIPuckLane.lane_clear(FROM, TO, far, SPEED, _vels, [], true, blades), 1.0,
			"a blade on the line further from his body than any stick reaches is not his")


func test_a_harder_pass_beats_the_stick_more_often() -> void:
	var blade := Vector3(1.6, 0.0, -1.0)
	assert_gt(_lane(blade, 28.0), _lane(blade, 14.0))


func test_the_pass_is_lost_at_the_stick() -> void:
	var blade := Vector3(0.5, 0.0, -2.8)
	var blades: Array[Vector3] = [blade]
	var loss: Vector3 = AIPuckLane.lane_loss_point(FROM, TO, _opps, SPEED, _vels, [], blades)
	assert_true(loss.is_finite())
	assert_lt(absf(loss.z - blade.z), 1.5, "picked off where the blade meets the line")

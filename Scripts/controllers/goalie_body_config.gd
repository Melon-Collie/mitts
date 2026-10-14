class_name GoalieBodyConfig

var left_pad_pos: Vector3 = Vector3.ZERO
var left_pad_rot: Vector3 = Vector3.ZERO
var right_pad_pos: Vector3 = Vector3.ZERO
var right_pad_rot: Vector3 = Vector3.ZERO
var body_pos: Vector3 = Vector3.ZERO
var body_rot: Vector3 = Vector3.ZERO
var head_pos: Vector3 = Vector3.ZERO
var head_rot: Vector3 = Vector3.ZERO
var glove_pos: Vector3 = Vector3.ZERO
var glove_rot: Vector3 = Vector3.ZERO
var blocker_pos: Vector3 = Vector3.ZERO
var blocker_rot: Vector3 = Vector3.ZERO
# The blocker lies over the back of the glove (the smother) rather than
# standing square to the shooter (Goalie._seat_blocker).
var blocker_over_glove: bool = false
# Footwork laid over each pad's eased stance unsmoothed (GoalieFootwork):
# goalie-local metres and degrees.
var left_pad_step_pos: Vector3 = Vector3.ZERO
var left_pad_step_rot: Vector3 = Vector3.ZERO
var right_pad_step_pos: Vector3 = Vector3.ZERO
var right_pad_step_rot: Vector3 = Vector3.ZERO

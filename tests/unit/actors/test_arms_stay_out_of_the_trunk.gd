extends "res://tests/harness/arm_clearance_harness.gd"

# The arms stay out of the trunk where the stick is held close: at rest with
# nothing to reach for, carrying, and pulled in to the skates. The sleeve is
# wider than an arm, so it may press in — the top arm's no deeper than its own
# radius, the bottom arm's, which crosses in front of the belly to the shaft,
# no deeper than twice it. Held at the shoulder, the top hand put the stick
# beside the hip and the bottom arm through the belly to reach it, 17–25 cm in;
# held in front of the body (TopHandIK's pivot) it is 11–14.
# tests/instruments/actors/test_arm_torso_clearance.gd prints the whole sweep.

# [mode, forehand-signed degrees off the top shoulder, cursor metres off it].
const POSES: Array = [
	["rest", 0.0, 1.3], ["rest", 30.0, 0.9], ["rest", 0.0, 0.35],
	["carry", 0.0, 1.3], ["carry", -40.0, 1.1], ["carry", 30.0, 0.5],
]


func test_the_arms_stay_out_of_the_trunk_held_close() -> void:
	for build: PlayerAttributes in [PlayerAttributes.neutral(),
			PlayerAttributes.new(PlayerAttributes.HEIGHT_MIN,
					PlayerAttributes.weight_max(PlayerAttributes.HEIGHT_MIN))]:
		_rig(build)
		for pose: Array in POSES:
			_hold(pose[1], pose[2], pose[0])
			var d: Array[Vector2] = _arm_depths()
			var label: String = "%d in %d lb, %s at %.0f° / %.2f m" % [build.height,
					build.weight, pose[0], pose[1], pose[2]]
			assert_lt(d[0].x, SLEEVE_R, "%s: top arm %.0f cm in" % [label, d[0].x * 100.0])
			assert_lt(d[1].x, 2.0 * SLEEVE_R, "%s: bottom arm %.0f cm in" % [label, d[1].x * 100.0])

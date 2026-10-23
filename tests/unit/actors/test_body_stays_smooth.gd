extends "res://tests/harness/body_jerk_harness.gd"

# The transitions that popped stay smooth: each region's worst jerk (mm/tick²)
# through each, held under a bound — a quarter over what it measured when the
# pops were taken out, and never under the stride's own 8. A ratchet, not a
# calibration: a bound that fires is a pop come back (the instrument,
# instruments/actors/test_body_smoothness.gd, says which frame), and a scenario
# that has got well under its bounds has them tightened.
#
# The knockdown is held from t120: the hit itself is a shove, and meant to jolt.

const KNOCKDOWN_FROM_TICK: int = 120
const ORDER: Array[String] = ["legs", "trunk", "head", "top_arm", "bot_arm", "stick"]
const BOUNDS: Dictionary = {
	"steady stride, cursor 6 m ahead":
		[8.0, 8.0, 8.0, 8.0, 8.0, 8.0],
	"pickup / drop, cursor far ahead":
		[8.0, 30.0, 8.0, 47.0, 35.0, 43.0],
	"forward → backward pivot (cursor flipped)":
		[23.0, 31.0, 13.0, 46.0, 52.0, 49.0],
	"backward → forward (move reversed)":
		[15.0, 8.0, 8.0, 8.0, 8.0, 8.0],
	"forward → backward (move reversed)":
		[12.0, 8.0, 8.0, 8.0, 10.0, 8.0],
	"stance on/off while skating":
		[15.0, 8.0, 8.0, 8.0, 8.0, 8.0],
	"stop and restart":
		[30.0, 8.0, 8.0, 8.0, 9.0, 8.0],
	"wrister: carry, charge, release, skating":
		[23.0, 15.0, 20.0, 81.0, 33.0, 97.0],
	"crossovers into and out of a held turn":
		[13.0, 8.0, 8.0, 11.0, 11.0, 17.0],
	"knocked down from the side and up again":
		[84.0, 16.0, 13.0, 14.0, 21.0, 11.0],
	"shot block down and back up, puck ahead":
		[28.0, 35.0, 27.0, 37.0, 19.0, 27.0],
	"goal celebration while gliding":
		[10.0, 11.0, 8.0, 8.0, 17.0, 10.0],
	"goal celebration while gliding: sword sheath":
		[10.0, 8.0, 8.0, 8.0, 8.0, 14.0],
	"goal celebration while gliding: knee slide":
		[23.0, 13.0, 10.0, 10.0, 14.0, 18.0],
	"goal celebration while gliding: hot stick":
		[10.0, 14.0, 8.0, 8.0, 28.0, 12.0],
	"goal celebration while gliding: bow and arrow":
		[10.0, 16.0, 8.0, 15.0, 26.0, 9.0],
	"goal celebration while gliding: can't hear you":
		[10.0, 12.0, 8.0, 24.0, 15.0, 23.0],
	"shuffle: Space + D held, released":
		[20.0, 8.0, 8.0, 8.0, 9.0, 8.0],
}


func test_the_transitions_stay_smooth() -> void:
	var gated: int = 0
	for s: Dictionary in scenarios():
		var scenario_name: String = s["name"]
		if not BOUNDS.has(scenario_name):
			continue
		gated += 1
		var from_tick: int = KNOCKDOWN_FROM_TICK if scenario_name.begins_with("knocked down") else 2
		var worst: Dictionary = measure(s, false, from_tick)
		var bounds: Array = BOUNDS[scenario_name]
		for k: int in ORDER.size():
			assert_lt(float(worst[ORDER[k]]), float(bounds[k]),
					"%s: %s" % [scenario_name, ORDER[k]])
	assert_eq(gated, BOUNDS.size(), "every bounded scenario is still skated")

extends "res://tests/harness/body_jerk_harness.gd"

# Where the drawn body pops: every scenario the harness skates, each region's
# worst jerk and the frames over SPIKE_MM, with the state they happened in.
#
# Asserts nothing. Run it when the question is "what pops, and when":
#   bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments/actors


func test_body_smoothness() -> void:
	for s: Dictionary in scenarios():
		measure(s, true)
	assert_true(true)

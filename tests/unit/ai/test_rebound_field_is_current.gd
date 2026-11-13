extends GutTest

# The rebound field is a measurement of the goalie, so it goes stale the moment
# the goalie does. Fails until it is regenerated: .claude/hooks/generate-rebound-field.sh.

const Fingerprint := preload("res://tests/unit/ai/rebound_field_fingerprint.gd")


func test_the_rebound_field_was_measured_against_this_goalie() -> void:
	assert_eq(AIReboundFieldData.FINGERPRINT, Fingerprint.compute(),
			"the goalie (or how his rebounds are measured) changed since the rebound field "
			+ "was generated: run .claude/hooks/generate-rebound-field.sh")

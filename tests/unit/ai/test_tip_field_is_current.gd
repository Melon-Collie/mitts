extends GutTest

# The tip field is a measurement of the goalie and the tip, so it goes stale the
# moment either does. Fails until it is regenerated: .claude/hooks/generate-tip-field.sh.

const Fingerprint := preload("res://tests/unit/ai/tip_field_fingerprint.gd")


func test_the_tip_field_was_measured_against_this_goalie() -> void:
	assert_eq(AITipFieldData.FINGERPRINT, Fingerprint.compute(),
			"the goalie (or the tip) changed since the tip field "
			+ "was generated: run .claude/hooks/generate-tip-field.sh")

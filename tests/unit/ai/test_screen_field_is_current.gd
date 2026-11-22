extends GutTest

# The screen field is a measurement of the goalie, so it goes stale the moment
# the goalie does. Fails until it is regenerated: .claude/hooks/generate-screen-field.sh.

const Fingerprint := preload("res://tests/unit/ai/screen_field_fingerprint.gd")


func test_the_screen_field_was_measured_against_this_goalie() -> void:
	assert_eq(AIScreenFieldData.FINGERPRINT, Fingerprint.compute(),
			"the goalie (or how his screened shots are measured) changed since the screen field "
			+ "was generated: run .claude/hooks/generate-screen-field.sh")

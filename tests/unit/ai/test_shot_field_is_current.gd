extends GutTest

# The shot field is a measurement of the goalie, so it goes stale the moment the
# goalie does. Fails until it is regenerated: .claude/hooks/generate-shot-field.sh.

const Fingerprint := preload("res://tests/unit/ai/shot_field_fingerprint.gd")


func test_the_shot_field_was_measured_against_this_goalie() -> void:
	assert_eq(AIShotFieldData.FINGERPRINT, Fingerprint.compute(),
			"the goalie (or how he is measured) changed since the shot field was "
			+ "generated: run .claude/hooks/generate-shot-field.sh")

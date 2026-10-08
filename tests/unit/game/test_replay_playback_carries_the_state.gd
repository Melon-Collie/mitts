extends GutTest

# ReplayPlaybackEngine builds a fresh SkaterNetworkState per rendered frame and
# copies the recorded fields across by hand, so a field added to the wire and
# missed here plays back at its default — the leans did, and every goal replay
# showed the skaters bolt upright. Every field of the state reaches the
# controller with its recorded value unless listed below with its reason.

const _NOT_PLAYED_BACK: Dictionary = {
	# Hermite tangents and clocks: consumed by the interpolation itself.
	"facing_angular_velocity": "a tangent, consumed by the interpolation",
	"upper_body_angular_velocity": "a tangent, consumed by the interpolation",
	"last_processed_host_timestamp": "an input ack, meaningless in playback",
	"host_timestamp": "host-only, not serialized",
	"blade_contact_world": "host-only, not serialized",
	"top_hand_world": "host-only, not serialized",
	# A known gap, not a choice: SkaterController.apply_replay_state has no
	# consumer for it, so a replayed wrister addresses the forehand.
	"wrister_address_side": "not consumed by apply_replay_state",
}


class CaptureController extends SkaterController:
	var applied: SkaterNetworkState = null

	func apply_replay_state(state: SkaterNetworkState, _delta: float) -> void:
		applied = state


func _recorded_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL:
			return not value
		TYPE_INT:
			return -1 if value != -1 else 2
		TYPE_FLOAT:
			return 0.37
		TYPE_VECTOR2:
			return Vector2(0.6, -0.8)
		TYPE_VECTOR3:
			return Vector3(0.4, -0.3, 0.2)
	return null


func _state_fields() -> Array[String]:
	var out: Array[String] = []
	for prop: Dictionary in SkaterNetworkState.new().get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(String(prop["name"]))
	return out


func test_every_recorded_field_reaches_the_controller() -> void:
	var recorded := SkaterNetworkState.new()
	var fields: Array[String] = _state_fields()
	assert_gt(fields.size(), 20, "the property scan must actually find the state's fields")
	for field: String in fields:
		var value: Variant = _recorded_value(recorded.get(field))
		assert_not_null(value, "%s has a type this test cannot fill" % field)
		recorded.set(field, value)
	var controller := CaptureController.new()
	autofree(controller)
	var record := PlayerRecord.new(7, 0, false, null)
	record.controller = controller
	var snap: Dictionary = {"skaters": {7: recorded}, "puck": null, "goalies": []}
	# Both bracket ends hold the recording, so any carry — lerp or newest end —
	# lands on it.
	ReplayPlaybackEngine.apply_interpolated_snapshot(
			snap, snap, 0.5, 1.0 / 60.0, 1.0 / 60.0, {7: record}, null, [])
	assert_not_null(controller.applied, "the engine applied a state")
	for field: String in fields:
		if _NOT_PLAYED_BACK.has(field):
			continue
		assert_eq(controller.applied.get(field), recorded.get(field),
				"%s plays back at its recorded value" % field)

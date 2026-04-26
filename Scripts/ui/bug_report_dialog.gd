class_name BugReportDialog extends Control

# Expected scene structure (user creates in Godot editor):
#   BugReportDialog (Control, this script)
#     Panel
#       VBoxContainer
#         Label ("Describe the bug:")
#         DescriptionEdit   (TextEdit, unique name %DescriptionEdit)
#         HBoxContainer
#           SubmitButton    (Button,   unique name %SubmitButton)
#           CancelButton    (Button,   unique name %CancelButton)
#         StatusLabel       (Label,    unique name %StatusLabel)

@onready var _description: TextEdit = %DescriptionEdit
@onready var _submit_button: Button = %SubmitButton
@onready var _status_label: Label = %StatusLabel

var _bug_reporter := BugReporter.new()
var _telemetry: NetworkTelemetry = null


func setup(telemetry: NetworkTelemetry) -> void:
	_telemetry = telemetry


func open() -> void:
	_description.text = ""
	_status_label.text = ""
	_submit_button.disabled = false
	show()
	_description.grab_focus()


func _on_submit_pressed() -> void:
	var text: String = _description.text.strip_edges()
	if text.is_empty():
		return
	_submit_button.disabled = true
	_status_label.text = "Submitting..."
	_bug_reporter.submit(text, _telemetry)
	await get_tree().create_timer(1.5).timeout
	_status_label.text = "Submitted — thank you!"
	await get_tree().create_timer(1.5).timeout
	hide()


func _on_cancel_pressed() -> void:
	hide()

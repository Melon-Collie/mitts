extends GutTest

# Every AIRoleSlots.Slot the brain can hand out needs an arm in the agent's
# role dispatch (SkaterAgentStateMachine._dispatch_role_decision). A slot that
# falls through to the default arm is silently told to hold where it stands,
# which no test of the role module itself can see. NONE is the one slot that
# holds on purpose.

const _AGENT: String = "res://Scripts/ai/skater_agent_state_machine.gd"


func test_every_slot_has_a_dispatch_arm() -> void:
	var src: String = FileAccess.get_file_as_string(_AGENT)
	var start: int = src.find("func _dispatch_role_decision(")
	assert_gt(start, -1, "found the role dispatch")
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, end - start)
	var armed: Dictionary = {}
	var re := RegEx.create_from_string("AIRoleSlots\\.Slot\\.([A-Z0-9_]+)")
	for m: RegExMatch in re.search_all(body):
		armed[m.get_string(1)] = true
	var missing: Array[String] = []
	for slot_name: String in AIRoleSlots.Slot.keys():
		if slot_name != "NONE" and not armed.has(slot_name):
			missing.append(slot_name)
	assert_eq(missing.size(), 0, "slots with no role dispatch arm: %s" % [missing])

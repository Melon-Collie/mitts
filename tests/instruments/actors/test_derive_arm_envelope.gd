extends GutTest

# Derives the carry's envelope (docs/arm-anatomy-plan.md §6) from the model and
# writes it to data/arm_envelope.json (ArmEnvelope): per build height and trunk
# state, on ArmEnvelope's grid of blade positions round the carrier, whether a
# body holds the blade as players hold it, and where that pose has the top hand
# and the bottom hand's grip (tests/harness/arm_envelope_deriver.gd). Run it
# whenever the model, the body or the carry posture changes;
# tests/slow/controllers/test_arm_envelope_is_current.gd fails until it is.
# An instrument: it asserts nothing.
#
# A part is one build height and trunk state (~35 min); the parts run as
# separate processes and are merged:
#   .claude/hooks/derive-arm-envelope.sh
#   MITTS_ENVELOPE_PART=i      derive part i (PARTS) into PART_PATH
#   MITTS_ENVELOPE_MERGE=1     merge the parts into the data file

const Deriver := preload("res://tests/harness/arm_envelope_deriver.gd")
const PART_PATH: String = "user://arm_envelope_part_%d.json"


# Part i's build height and trunk state.
static func part(i: int) -> Array:
	return [ArmEnvelope.HEIGHTS[i / ArmEnvelope.STATES.size()],
			ArmEnvelope.STATES[i % ArmEnvelope.STATES.size()]]


static func parts() -> int:
	return ArmEnvelope.HEIGHTS.size() * ArmEnvelope.STATES.size()


func test_derive_a_part() -> void:
	var which: String = OS.get_environment("MITTS_ENVELOPE_PART")
	if which.is_empty():
		pending("set MITTS_ENVELOPE_PART (derive-arm-envelope.sh)")
		return
	var i: int = int(which)
	var height: int = part(i)[0]
	var state: String = part(i)[1]
	var d: RefCounted = Deriver.new(height, state == "skate", add_child_autofree)
	var curve: Array = d.crouch_curve() if state == "stand" else []
	var cells: Array = []
	var held: int = 0
	for angle: float in ArmEnvelope.ANGLES_DEG:
		for radius: float in ArmEnvelope.RADII_M:
			var cell: Array = d.cell(angle, radius)
			held += int(cell[0])
			cells.append(cell)
	gut.p("%d\" %s: %d of %d held" % [height, state, held, cells.size()])
	var f: FileAccess = FileAccess.open(PART_PATH % i, FileAccess.WRITE)
	f.store_string(JSON.stringify({"crouch_curve": curve, "cells": cells}))
	f.close()
	assert_true(true)


func test_merge_the_parts() -> void:
	if OS.get_environment("MITTS_ENVELOPE_MERGE") != "1":
		pending("set MITTS_ENVELOPE_MERGE=1 (derive-arm-envelope.sh)")
		return
	var builds: Array = []
	for height: int in ArmEnvelope.HEIGHTS:
		builds.append({"height": height, "crouch_curve": [], "states": {}})
	for i: int in parts():
		var src: FileAccess = FileAccess.open(PART_PATH % i, FileAccess.READ)
		assert_not_null(src, "part %d derived" % i)
		if src == null:
			return
		var got: Dictionary = JSON.parse_string(src.get_as_text())
		var build: Dictionary = builds[ArmEnvelope.HEIGHTS.find(part(i)[0])]
		(build["states"] as Dictionary)[part(i)[1]] = got["cells"]
		if part(i)[1] == "stand":
			build["crouch_curve"] = got["crouch_curve"]
	var out := {"version": ArmEnvelope.VERSION, "angles_deg": ArmEnvelope.ANGLES_DEG,
			"radii_m": ArmEnvelope.RADII_M, "builds": builds}
	var f: FileAccess = FileAccess.open(ArmEnvelope.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	gut.p("wrote " + ArmEnvelope.PATH)
	assert_true(true)

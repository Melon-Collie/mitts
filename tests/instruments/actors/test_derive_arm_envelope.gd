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
# A part is a third of one build height and trunk state's bearings (~12 min);
# the parts run as separate processes, each written as it finishes so a rerun
# skips what is done, and are merged:
#   .claude/hooks/derive-arm-envelope.sh
#   MITTS_ENVELOPE_PART=i      derive part i (part()) into PART_PATH
#   MITTS_ENVELOPE_MERGE=1     merge the parts into the data file

const Deriver := preload("res://tests/harness/arm_envelope_deriver.gd")
const PART_DIR: String = "res://.preview/arm_envelope_parts"
const PART_PATH: String = PART_DIR + "/part_%d.json"
const ANGLE_CHUNKS: int = 3


# Part i's build height, trunk state and slice of ANGLES_DEG [from, to).
static func part(i: int) -> Array:
	var per_state: int = ANGLE_CHUNKS
	var per_height: int = ArmEnvelope.STATES.size() * per_state
	var chunk: int = i % per_state
	var n: int = ArmEnvelope.ANGLES_DEG.size()
	return [ArmEnvelope.HEIGHTS[i / per_height],
			ArmEnvelope.STATES[(i / per_state) % ArmEnvelope.STATES.size()],
			chunk * n / per_state, (chunk + 1) * n / per_state]


static func parts() -> int:
	return ArmEnvelope.HEIGHTS.size() * ArmEnvelope.STATES.size() * ANGLE_CHUNKS


func test_derive_a_part() -> void:
	var which: String = OS.get_environment("MITTS_ENVELOPE_PART")
	if which.is_empty():
		pending("set MITTS_ENVELOPE_PART (derive-arm-envelope.sh)")
		return
	var i: int = int(which)
	var p: Array = part(i)
	var height: int = p[0]
	var state: String = p[1]
	var d: RefCounted = Deriver.new(height, state == "skate", add_child_autofree)
	var curve: Array = d.crouch_curve() if state == "stand" and int(p[2]) == 0 else []
	var cells: Array = []
	var held: int = 0
	for ai: int in range(int(p[2]), int(p[3])):
		for radius: float in ArmEnvelope.RADII_M:
			var cell: Array = d.cell(ArmEnvelope.ANGLES_DEG[ai], radius)
			held += int(cell[0])
			cells.append(cell)
	gut.p("%d\" %s part %d: %d of %d held" % [height, state, i, held, cells.size()])
	DirAccess.make_dir_recursive_absolute(PART_DIR)
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
		var states: Dictionary = build["states"]
		var state: String = part(i)[1]
		if not states.has(state):
			states[state] = []
		(states[state] as Array).append_array(got["cells"])
		if state == "stand" and int(part(i)[2]) == 0:
			build["crouch_curve"] = got["crouch_curve"]
	var out := {"version": ArmEnvelope.VERSION, "angles_deg": ArmEnvelope.ANGLES_DEG,
			"radii_m": ArmEnvelope.RADII_M, "builds": builds}
	var f: FileAccess = FileAccess.open(ArmEnvelope.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	gut.p("wrote " + ArmEnvelope.PATH)
	assert_true(true)

extends GutTest

# Derives the carry's envelope (docs/arm-anatomy-plan.md §6) from the model and
# writes it to data/arm_envelope.json (ArmEnvelope): per build height and trunk
# state, on ArmEnvelope's grid of blade positions round the carrier, whether a
# body holds the blade as players hold it, and where that pose has the top hand
# and the bottom hand's grip (tests/harness/arm_envelope_deriver.gd). Run it
# whenever the model, the body or the carry posture changes;
# tests/slow/controllers/test_arm_envelope_is_current.gd fails until it is.
# ~40 min. An instrument: it asserts nothing.
#
#   bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments/actors \
#       -gselect=test_derive_arm_envelope

const Deriver := preload("res://tests/harness/arm_envelope_deriver.gd")


func test_derive() -> void:
	var builds: Array = []
	for height: int in ArmEnvelope.HEIGHTS:
		var states := {}
		for state: String in ArmEnvelope.STATES:
			var d: RefCounted = Deriver.new(height, state == "skate", add_child_autofree)
			var cells: Array = []
			var held: int = 0
			for angle: float in ArmEnvelope.ANGLES_DEG:
				for radius: float in ArmEnvelope.RADII_M:
					var cell: Array = d.cell(angle, radius)
					held += int(cell[0])
					cells.append(cell)
			gut.p("%d\" %s: %d of %d held" % [height, state, held, cells.size()])
			states[state] = cells
		builds.append({"height": height, "states": states})
	var out := {"version": ArmEnvelope.VERSION, "angles_deg": ArmEnvelope.ANGLES_DEG,
			"radii_m": ArmEnvelope.RADII_M, "builds": builds}
	var f: FileAccess = FileAccess.open(ArmEnvelope.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	gut.p("wrote " + ArmEnvelope.PATH)
	assert_true(true)

extends GutTest

# The press's calibration on the live rig (PressHarness): how far the man gives
# ground in one second at the reference cases — posture, side and build. A
# snapshot (tests/CLAUDE.md): a tuning move shows here as its rows, re-pinned
# with MITTS_UPDATE_SNAPSHOTS=1.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH: String = "res://tests/unit/rules/snapshots/press_table.txt"
const PRESS_S: float = 1.0


func test_the_press_table() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	# man lb, attacker lb, side, man, attacker
	var cases: Array = [
		[201, 201, "behind", "nothing", "skate"],
		[201, 201, "behind", "nothing", "skate commit"],
		[201, 201, "behind", "stance", "skate commit"],
		[201, 201, "behind", "back", "skate commit"],
		[201, 201, "behind", "brake", "skate commit"],
		[201, 201, "behind", "brake stance", "skate commit"],
		[201, 201, "beside", "nothing", "skate commit"],
		[201, 201, "beside", "stance", "skate commit"],
		[201, 201, "beside", "brake", "skate commit"],
		[170, 235, "behind", "brake stance", "skate commit"],
		[235, 170, "behind", "brake stance", "skate commit"],
		[170, 235, "behind", "nothing", "skate commit"],
		[235, 170, "behind", "nothing", "skate commit"],
	]
	for c: Array in cases:
		var spec := PressHarness.Spec.new()
		spec.man_lbs = c[0]
		spec.attacker_lbs = c[1]
		spec.side = c[2]
		spec.man_stance = (c[3] as String).contains("stance")
		spec.man_brake = (c[3] as String).contains("brake")
		spec.man_back = (c[3] as String).contains("back")
		spec.attacker = c[4]
		var r: PressHarness.Result = PressHarness.new(self).run(spec, PRESS_S)
		snap.record("%d on %d, %s, man %s, %s" % [c[1], c[0], c[2], c[3], c[4]], r.gave)
	snap.verify(self)

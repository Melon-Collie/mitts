extends GutTest

const Deriver := preload("res://tests/harness/arm_envelope_deriver.gd")
const CELLS: Array[Vector2] = [Vector2(-30.0, 0.6), Vector2(-45.0, 0.7), Vector2(-60.0, 0.9),
		Vector2(-90.0, 0.6), Vector2(-75.0, 1.3), Vector2(45.0, 1.6), Vector2(60.0, 1.5)]

func test_zz_probe() -> void:
	var d: RefCounted = Deriver.new(73, false, add_child_autofree)
	for spec: Vector2 in CELLS:
		var cell: Array = d.cell(spec.x, spec.y)
		var p: ArmAnatomySearch.Pose = d._pose
		var why: String = "held"
		if not p.feasible():
			why = ("arm%d %s" % [p.binding_arm, ArmAnatomy.Limit.keys()[p.arm_binding]]) if p.binding_arm >= 0 else (ArmTechnique.Limit.keys()[p.technique.binding] if p.trunk_binding == ArmAnatomySearch.Limit.TECHNIQUE else ArmAnatomySearch.Limit.keys()[p.trunk_binding])
		print("PROBE %s %s %s by %.3f | top hand out %.2f up %.2f ahead %.2f | twist %+.0f lean %.0f/%.0f spacing %.2f" % [OS.get_environment("PROBE_TAG"), spec, why, p.violation, float(cell[1]), float(cell[2]), float(cell[3]) * -1.0, rad_to_deg(p.twist), rad_to_deg(p.lean.x), rad_to_deg(p.lean.y), p.spacing])
	assert_true(true)

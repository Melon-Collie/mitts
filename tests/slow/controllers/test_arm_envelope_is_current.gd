extends GutTest

# The carry's envelope table (data/arm_envelope.json) is the model's answer: a
# sample of its cells, re-derived now from the model and the body as they are
# (tests/harness/arm_envelope_deriver.gd), read the same. Fails when the model,
# the body or the carry posture moved since the table was written; rerun
# tests/instruments/actors/test_derive_arm_envelope.gd.

const Deriver := preload("res://tests/harness/arm_envelope_deriver.gd")
# A hand within this of the table's (m), a grip within this down the shaft: the
# search's own repeatability, and room for the float format.
const HAND_M: float = 0.02
const SPACING_M: float = 0.03
# (angle off the facing, + forehand; radius) across the band and past it.
const SAMPLES: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(45.0, 0.9), Vector2(90.0, 1.2),
		Vector2(-45.0, 1.1), Vector2(-120.0, 0.8), Vector2(0.0, 1.7)]


func test_the_table_reads_as_the_model_now_does() -> void:
	var f: FileAccess = FileAccess.open(ArmEnvelope.PATH, FileAccess.READ)
	assert_not_null(f, "the table is written")
	if f == null:
		return
	var table: Dictionary = JSON.parse_string(f.get_as_text())
	assert_not_null(ArmEnvelope.from_dict(table), "and of this version")
	var neutral: int = ArmEnvelope.HEIGHTS.find(PlayerAttributes.HEIGHT_MEDIUM)
	for si: int in ArmEnvelope.STATES.size():
		var state: String = ArmEnvelope.STATES[si]
		var d: RefCounted = Deriver.new(PlayerAttributes.HEIGHT_MEDIUM, state == "skate",
				add_child_autofree)
		var rows: Array = (table["builds"][neutral]["states"] as Dictionary)[state]
		for s: Vector2 in SAMPLES:
			var ai: int = ArmEnvelope.ANGLES_DEG.find(s.x)
			var ri: int = ArmEnvelope.RADII_M.find(s.y)
			var stored: Array = rows[ai * ArmEnvelope.RADII_M.size() + ri]
			var now: Array = d.cell(s.x, s.y)
			var what: String = "%s %+.0f° %.1f m" % [state, s.x, s.y]
			assert_eq(int(now[0]), int(stored[0]), what + ": held the same")
			if int(now[0]) == 1 and int(stored[0]) == 1:
				var a := Vector3(now[1], now[2], now[3])
				var b := Vector3(stored[1], stored[2], stored[3])
				assert_lt(a.distance_to(b), HAND_M, what + ": the hand where it was")
				assert_almost_eq(float(now[4]), float(stored[4]), SPACING_M,
						what + ": the grip where it was")

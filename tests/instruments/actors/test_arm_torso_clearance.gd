extends "res://tests/harness/arm_clearance_harness.gd"

# Sweeps the cursor round a standing skater's top shoulder and prints, per aim,
# where the blade lands and how deep each arm goes into the trunk — with its
# elbow as drawn, and the least any elbow could manage — reaching for a loose
# puck, at rest with nothing to reach for, and carrying. Asserts nothing; the
# gate is tests/unit/actors/test_arms_stay_out_of_the_trunk.gd.


func _sweep(mode: String, attrs: PlayerAttributes) -> void:
	var degs: Array[float] = [-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0, 80.0, 100.0]
	var rs: Array[float] = [1.6, 1.3, 1.1, 0.9, 0.7, 0.5, 0.35, 0.2]
	_rig(attrs)
	print("\n== %d in %d lb, %s. Per cell: blade deg/m off the top shoulder | cm into the trunk, drawn>best elbow: top, bottom ('.' clear)"
			% [attrs.height, attrs.weight, mode])
	var header: String = "cursor m\\deg"
	for deg: float in degs:
		header += "%27.0f" % deg
	print(header)
	var worst := Vector2(-1.0, -1.0)
	var total := Vector2.ZERO
	var cells: int = 0
	var nearest: float = INF
	for r: float in rs:
		var row: String = "%12.2f" % r
		for deg: float in degs:
			_hold(deg, r, mode)
			var bp: Vector2 = _blade_polar()
			var d: Array[Vector2] = _arm_depths()
			worst = Vector2(maxf(worst.x, d[0].x), maxf(worst.y, d[1].x))
			total += Vector2(maxf(d[0].x, 0.0), maxf(d[1].x, 0.0))
			cells += 1
			nearest = minf(nearest, bp.y)
			row += "%27s" % ("%.0f/%.2f|%s>%s %s>%s" % [bp.x, bp.y, _cm(d[0].x), _cm(d[0].y),
					_cm(d[1].x), _cm(d[1].y)])
		print(row)
	print("SUMMARY %s: worst top %d bottom %d cm, mean top %.1f bottom %.1f cm, nearest blade %.2f m"
			% [mode, roundi(worst.x * 100.0), roundi(worst.y * 100.0),
			total.x * 100.0 / cells, total.y * 100.0 / cells, nearest])


func test_print_clearance_grid() -> void:
	for mode: String in ["reach", "rest", "carry"]:
		_sweep(mode, PlayerAttributes.neutral())
	assert_true(true)


static func _cm(d: float) -> String:
	return "." if d <= 0.0 else "%d" % roundi(d * 100.0)

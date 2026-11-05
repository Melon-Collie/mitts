extends RefCounted

# Zeroes the measured odds of every shot from the shot field's farthest row (the
# one a point shot reads) and puts them back: the regression that started
# docs/possession-floor-plan.md, point shots worth nothing, staged on the live
# field without touching production code. Instruments only. Loaded via preload.

const POINT_FWD_M: float = 15.0

static var _saved_odds: PackedFloat32Array
static var _saved_aim: PackedFloat32Array


static func apply() -> void:
	AIShotOdds.prepare()
	_saved_odds = AIShotOdds._odds.duplicate()
	_saved_aim = AIShotOdds._aim_odds.duplicate()
	var odds: PackedFloat32Array = AIShotOdds._odds.duplicate()
	var aim: PackedFloat32Array = AIShotOdds._aim_odds.duplicate()
	var per_cell: int = AIShotOdds._aims_per_cell
	for c: int in AIShotFieldData.ROWS.size():
		if float(AIShotFieldData.ROWS[c].split("\t")[2]) < POINT_FWD_M:
			continue
		odds[c] = 0.0
		for i: int in per_cell:
			aim[c * per_cell + i] = 0.0
	AIShotOdds._odds = odds
	AIShotOdds._aim_odds = aim
	AIPossessionValue._shared.clear()


static func restore() -> void:
	if _saved_odds.is_empty():
		return
	AIShotOdds._odds = _saved_odds
	AIShotOdds._aim_odds = _saved_aim
	_saved_odds = PackedFloat32Array()
	_saved_aim = PackedFloat32Array()
	AIPossessionValue._shared.clear()

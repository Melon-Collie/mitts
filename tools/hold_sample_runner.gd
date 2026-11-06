extends "res://tools/frame_cost_runner.gd"

# The body of tools/hold_sample.gd: the frame-cost runner's match against bots,
# and every SAMPLE_EVERY ticks of live play each skater's top hand (the anchor
# gameplay placed) scored by SkaterHoldModel against the trunk as drawn, with
# culling off so every trunk is drawn, and the stick's sphere searched where it
# is not held. Prints the share not held, what binds, and how far the nearest
# held hand lies, carriers and the rest apart.

const SAMPLE_EVERY: int = 30
const BROKEN_M: float = 0.005

var _body := SkaterHoldModel.Body.new()
var _report := SkaterHoldModel.Report.new()
var _scratch := SkaterHoldModel.Report.new()
var _search := SkaterHoldModel.Search.new()


func sample(skaters: int, seconds: float) -> void:
	SkaterCameraCull.enabled = false
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	await _start_match(clampi(skaters, 2, 10))
	await _play_for(1.0)
	var tallies: Array[Dictionary] = [_tally(), _tally()]
	var end: int = Engine.get_physics_frames() + int(seconds * Engine.physics_ticks_per_second)
	var next: int = Engine.get_physics_frames()
	while Engine.get_physics_frames() < end:
		await get_tree().process_frame
		if Engine.get_physics_frames() < next or not _live():
			continue
		next = Engine.get_physics_frames() + SAMPLE_EVERY
		for record: PlayerRecord in GameManager._registry.all().values():
			if record.is_goalie or record.controller == null or record.skater == null:
				continue
			_score(record, tallies[0 if record.controller.has_puck else 1])
	for i: int in 2:
		print("[hold-sample] %s" % _summary("carriers" if i == 0 else "the rest", tallies[i]))
	get_tree().quit()


static func _tally() -> Dictionary:
	return {"samples": 0, "broken": 0, "unheld": 0, "binds": {}, "moves": PackedFloat64Array(),
			"depths": PackedFloat64Array(), "tail": 0, "tail_held": 0}


func _score(record: PlayerRecord, tally: Dictionary) -> void:
	var sk: Skater = record.skater
	record.controller._ik.fill_hold_body(_body)
	sk.fill_drawn_trunk(_body)
	var hand: Vector3 = sk.top_hand.position
	var blade: Vector3 = sk.blade.position
	SkaterHoldModel.evaluate(_body, hand, blade, _report)
	tally["samples"] += 1
	if _report.total() <= BROKEN_M:
		return
	tally["broken"] += 1
	# Packed arrays are values: append to the copy, then put it back.
	var depths: PackedFloat64Array = tally["depths"]
	depths.append(_report.total())
	tally["depths"] = depths
	var binds: Dictionary = tally["binds"]
	binds[_report.binding()] = int(binds.get(_report.binding(), 0)) + 1
	# Whether the fist and the knob are in the jersey only below its belt, in
	# the tail's cloth, and the rest of the pose held.
	var to_torso: Transform3D = _body.torso.affine_inverse()
	var knob: Vector3 = hand + (hand - blade).normalized() * _body.knob_extend
	var belt_y: float = SkaterMeshBuilder.TORSO_PROFILE[SkaterMeshBuilder.TORSO_BELT_STATION].x
	if (_report.fist > 0.0 or _report.knob > 0.0) \
			and (to_torso * hand).y < belt_y and (to_torso * knob).y < belt_y:
		tally["tail"] += 1
		if _report.total() - _report.fist - _report.knob <= BROKEN_M:
			tally["tail_held"] += 1
	SkaterHoldModel.search(_body, hand, blade, _scratch, _search)
	if _search.held_found:
		var moves: PackedFloat64Array = tally["moves"]
		moves.append(_search.held_hand.distance_to(hand))
		tally["moves"] = moves
	else:
		tally["unheld"] += 1


static func _summary(who: String, tally: Dictionary) -> String:
	return "%s: %d of %d samples not held (%s), by %s mm; fist or knob in the tail below the belt in %d, the rest held in %d; a held hand on the sphere for %d, moved %s cm; none for %d" % [
			who, tally["broken"], tally["samples"], tally["binds"],
			_spread(tally["depths"], 1000.0), tally["tail"], tally["tail_held"],
			(tally["moves"] as PackedFloat64Array).size(),
			_spread(tally["moves"], 100.0), tally["unheld"]]


static func _spread(values: PackedFloat64Array, scale: float) -> String:
	if values.is_empty():
		return "-"
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return "median %.0f, 90%% %.0f, max %.0f" % [sorted[sorted.size() / 2] * scale,
			sorted[mini(int(sorted.size() * 0.9), sorted.size() - 1)] * scale,
			sorted[sorted.size() - 1] * scale]

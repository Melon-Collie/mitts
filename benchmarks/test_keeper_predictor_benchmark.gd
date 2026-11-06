extends GutTest

# What drawing both goalies predicted costs a client (#903, KeeperPredictor),
# per 60 fps frame, on the real keeper through a wrister from the slot and a
# carry across the slot and a shot (keeper_play_harness.gd): two predictors
# stepped against the host's recorded world (the facing keeper twice, so
# pessimistic for the far one), snapshots every 2nd host tick arriving a one-way
# trip late, drawn at host present plus the input lead (the one-way plus
# ~28 ms). Fed the host's world exactly (TRUTH) nearly every snapshot confirms
# and a frame steps a tick or two; fed it on the snapshot's grid (QUANTIZED,
# 1 cm and 0.02 m/s, nearer what a client's own world is) nearly every snapshot
# re-steps the span. Reported: frames, the share of snapshots confirmed,
# re-steps a second, and the frame cost mean / p95 / max (us), split into
# frames with a re-step and frames without. Report-only.

const Harness := preload("res://tests/harness/keeper_play_harness.gd")
const TruthWorld := preload("res://tests/harness/keeper_truth_world.gd")
const FPS: float = 60.0
const MARGIN_S: float = 0.028
const ONE_WAYS_MS: Array[float] = [15.0, 50.0, 100.0]


static func _pct(a: PackedFloat64Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s: PackedFloat64Array = a.duplicate()
	s.sort()
	return s[clampi(int(ceil(q * float(s.size()))) - 1, 0, s.size() - 1)]


static func _mean(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var sum: float = 0.0
	for x: float in a:
		sum += x
	return sum / float(a.size())


func _record(play: int) -> TruthWorld:
	var host := Harness.new(add_child_autofree)
	var world := TruthWorld.new(host)
	for t: int in Harness.length(play):
		world.record(play, t)
	return world


func _row(label: String, steady: PackedFloat64Array, restep: PackedFloat64Array, confirmed: int,
		resteps: int, seconds: float) -> void:
	gut.p("%-22s frames %4d + %3d re-step | confirmed %5.1f%% | %5.1f re-steps/s | steady %6.0f / %6.0f / %6.0f us | re-step frame %6.0f / %6.0f / %6.0f us" % [
			label, steady.size(), restep.size(),
			100.0 * confirmed / maxf(confirmed + resteps, 1.0), resteps / seconds,
			_mean(steady), _pct(steady, 0.95), _pct(steady, 1.0),
			_mean(restep), _pct(restep, 0.95), _pct(restep, 1.0)])


func test_report_two_predicted_goalies_per_frame() -> void:
	var worlds: Array[TruthWorld] = [_record(Harness.Play.SLOT_SHOT), _record(Harness.Play.CARRY_ACROSS)]
	for quantized: bool in [false, true]:
		for one_way_ms: float in ONE_WAYS_MS:
			var steady := PackedFloat64Array()
			var restep := PackedFloat64Array()
			var confirmed: int = 0
			var resteps: int = 0
			var seconds: float = 0.0
			for world: TruthWorld in worlds:
				world.quantized = quantized
				var one_way: float = one_way_ms / 1000.0
				var lead: float = one_way + MARGIN_S
				var preds: Array[KeeperPredictor] = []
				for i: int in 2:
					var p := KeeperPredictor.new()
					add_child_autofree(p)
					p.setup(Harness.GOAL_Z, -1, GoalieSkillProfile.hard(), world)
					preds.append(p)
				var offered: int = -2
				var ticks: int = world.frames.size()
				var f: int = int(float(Harness.SETTLE_TICKS - 40) * Harness.DT * FPS)
				while true:
					var now: float = float(f) / FPS
					if (now + lead) / Harness.DT >= float(ticks - 2):
						break
					f += 1
					while float(offered + 2) * Harness.DT <= now - one_way:
						offered += 2
						if offered >= 0:
							world.known_through = offered
							for p: KeeperPredictor in preds:
								p.offer(world.blobs[offered], float(offered) * Harness.DT, offered / 2)
					var was: int = preds[0].resteps + preds[1].resteps
					var t0: int = Time.get_ticks_usec()
					for p: KeeperPredictor in preds:
						p.advance(now + lead)
					var us: float = float(Time.get_ticks_usec() - t0)
					seconds += 1.0 / FPS
					if preds[0].resteps + preds[1].resteps > was:
						restep.append(us)
					else:
						steady.append(us)
				confirmed += preds[0].confirmed + preds[1].confirmed
				resteps += preds[0].resteps + preds[1].resteps
			_row("%s %3.0f ms one-way" % ["QUANTIZED" if quantized else "TRUTH", one_way_ms],
					steady, restep, confirmed, resteps, seconds)
	assert_true(true)

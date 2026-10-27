extends GutTest

# The defender race (AIDefenderRace, docs/defender-race-plan.md) against our
# real defending bots. Each staging puts a carrier on the ice with one or two
# real defender bots and records when the puck was lost, and where the puck was
# until then. A scripted carrier skates a one-shot path through the real
# movement model and can be stripped; a body in his way stops him as it would. A
# bot carrier decides for himself (protecting, evading), and a release ends his
# run without a loss.
#
# The model: while a defender's stick is in reach the puck is stripped at a rate
# per second, the race giving the odds he is in reach at each moment and the
# defenders' time in reach adding. The race's reaction and grade are fitted on
# the scripted single-defender runs, with a strip rate for a standing puck and
# one for a moving puck in closed form (events over exposure); then the pairs
# test the adding against the worst one alone, the bot carriers measure the
# shield, and the observed-to-expected losses by family and by time test a
# constant rate. Today's carry read is scored beside it on the families it
# prices. Reports only. MITTS_RACE_LIMIT caps the stagings; MITTS_RACE_SAVE
# writes the runs to a file and MITTS_RACE_FROM refits from one.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const CARRIER := 1
const DEFENDER := 201
const HORIZON_S: float = 3.0
const SAMPLE_TICKS: int = 12
const HORIZONS: Array[float] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
const TOP_PACE_M_S: float = 8.0
const REPEATS: int = 2
const JITTER_M: float = 0.5
const JITTER_PACE: float = 0.1
const START_X: float = -3.0
const START_ZS: Array[float] = [14.0, 4.0, -4.0]
const PATH_END_Z: float = -(GameRules.GOAL_LINE_Z - 3.0)
const EDGE_M: float = 1.5
# A puck slower than this between samples is standing.
const STAND_M_S: float = 1.0
# The floor on the race's odds he is in reach at a loss, so one loss the race
# reads as impossible scores as very unlikely rather than ending the fit.
const MIN_REACH_ODDS: float = 0.001

const REACTS: Array[float] = [0.1, 0.15, 0.2, 0.3]
const SIGMAS: Array[float] = [0.05, 0.1, 0.2, 0.3]
const GROWTHS: Array[float] = [0.0, 0.05]
# How long each defender's chance lasts once he first has the puck in reach
# (s; the horizon: all of it), and the strip rates in reach (/s).
const WINDOWS: Array[float] = [3.0]
# The strip rate (/s) on top when the puck comes within his reach of where his
# momentum carries him, with no skate to it — graded across a soft edge (m).
const COAST_RATES: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]
const MOVING_GRID: Array[float] = [0.0, 0.02, 0.05, 0.08, 0.12, 0.16, 0.2, 0.25, 0.3]
const STANDING_GRID: Array[float] = [0.0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.8]
const COAST_EDGE_M: float = 0.3
# The radius (m) the puck must come within of where his momentum has him (the
# stick's reach when negative).
const COAST_RADII: Array[float] = [-1.0, 1.4, 1.0, 0.7]
const MOVING_RATES: Array[float] = [0.02, 0.05, 0.08, 0.12, 0.16, 0.2, 0.25, 0.3, 0.4, 0.5]
const STANDING_RATES: Array[float] = [0.05, 0.1, 0.2, 0.3, 0.45, 0.6, 0.8, 1.0]

var _rng := RandomNumberGenerator.new()
var _caps: AISkaterCaps = Duel.match_caps()
# One row per run.
var _family: Array[String] = []
var _defs: Array = []      # Array[Array[Vector3]]
var _def_vels: Array = []  # Array[Array[Vector3]]
var _points: Array = []    # Array[Array[Vector3]]: the puck on his path, every sample
var _times: Array = []     # Array[Array[float]]
var _stand: Array = []     # Array[Array[bool]]: the puck standing at each sample
var _event_t: Array[float] = []   # when the puck was lost (-1: not)
var _event_kind: Array[String] = []   # poke, lift or hit (or "" when not lost)
var _end_t: Array[float] = []     # when the run stopped being watched


func _stagings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var backing := Vector3(0, 0, -3.0)
	var closing := Vector3(0, 0, 3.0)
	var still := Vector3.ZERO
	for z0: float in START_ZS:
		var c := Vector3(START_X, 0, z0)
		var straight: Array[Vector3] = [c, Vector3(START_X, 0, PATH_END_Z)]
		for v0: float in [0.0, 4.0, 7.5]:
			var cv := Vector3(0, 0, -v0)
			for d: float in [3.0, 6.0, 10.0, 15.0]:
				for lat: float in [0.0, 3.0, 6.0]:
					for dv: Vector3 in [still, backing, closing]:
						out.append(_staging("straight", c, cv, straight,
								[c + Vector3(lat, 0, -d)], [dv]))
			for d: float in [2.0, 4.0]:
				for lat: float in [0.0, 2.0]:
					out.append(_staging("chased", c, cv, straight, [c + Vector3(lat, 0, d)],
							[Vector3(0, 0, -maxf(v0, 3.0))]))
		var p1: Vector3 = c + Vector3(0, 0, -2.0)
		for deg: float in [30.0, 60.0, 90.0]:
			for side: float in [-1.0, 1.0]:
				var a: float = deg_to_rad(deg)
				var cut: Array[Vector3] = [c, p1,
						_on_ice(p1 + Vector3(side * sin(a), 0, -cos(a)) * 30.0)]
				for d: float in [4.0, 8.0, 12.0]:
					for lat: float in [-3.0, 0.0, 3.0]:
						for dv: Vector3 in [still, backing]:
							out.append(_staging("cut", c, Vector3(0, 0, -7.5), cut,
									[c + Vector3(lat, 0, -d)], [dv]))
		var stand: Array[Vector3] = [c]
		for d: float in [2.0, 4.0, 7.0, 10.0]:
			for lat: float in [0.0, 3.0]:
				for dv: Vector3 in [still, closing, Vector3(3.0, 0, 0)]:
					out.append(_staging("stand", c, Vector3.ZERO, stand,
							[c + Vector3(lat, 0, -d)], [dv]))
		for v0: float in [4.0, 7.5]:
			var cv := Vector3(0, 0, -v0)
			for pair: Vector2 in [Vector2(4.0, 8.0), Vector2(6.0, 6.0), Vector2(3.0, 10.0)]:
				for dv: Vector3 in [still, backing]:
					out.append(_staging("pair", c, cv, straight,
							[c + Vector3(3.0, 0, -pair.x), c + Vector3(-3.0, 0, -pair.y)], [dv, dv]))
			out.append(_staging("pair", c, cv, straight,
					[c + Vector3(2.0, 0, -6.0), c + Vector3(1.0, 0, 3.0)],
					[still, Vector3(0, 0, -maxf(v0, 3.0))]))
			var none: Array[Vector3] = []
			for d: float in [3.0, 6.0, 10.0]:
				for lat: float in [0.0, 3.0]:
					for dv: Vector3 in [still, backing]:
						out.append(_staging("bot", c, cv, none, [c + Vector3(lat, 0, -d)], [dv]))
	return out


func _staging(family: String, c_pos: Vector3, c_vel: Vector3, path: Array[Vector3],
		defs: Array, vels: Array) -> Dictionary:
	return {"family": family, "c_pos": c_pos, "c_vel": c_vel, "path": path,
			"defs": defs, "vels": vels}


func _on_ice(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -GameRules.RINK_HALF_WIDTH + EDGE_M, GameRules.RINK_HALF_WIDTH - EDGE_M),
			0, clampf(p.z, PATH_END_Z, -PATH_END_Z))


func _jitter() -> Vector3:
	return Vector3(_rng.randf_range(-JITTER_M, JITTER_M), 0, _rng.randf_range(-JITTER_M, JITTER_M))


func _pace() -> float:
	return 1.0 + _rng.randf_range(-JITTER_PACE, JITTER_PACE)


func _add_carrier(duel: Object, pos: Vector3, vel: Vector3, path: Array[Vector3]) -> void:
	duel.add_skater(CARRIER, 0, pos, null, vel)
	if path.is_empty():
		return
	var s: Object = duel._skater(CARRIER)
	s.script_path = path
	s.script_speed = TOP_PACE_M_S
	s.script_idx = 1 % path.size()
	s.script_skates = true
	s.script_loop = false
	s.script_strippable = true


func _losses(duel: Object) -> int:
	return duel.strips + duel.lifts + duel.hit_strips


func _run(st: Dictionary) -> void:
	var shift: Vector3 = _jitter()
	var c_pos: Vector3 = _on_ice(st["c_pos"] + shift)
	var path: Array[Vector3] = []
	for p: Vector3 in st["path"]:
		path.append(_on_ice(p + shift))
	var c_vel: Vector3 = st["c_vel"] * _pace()
	var defs: Array[Vector3] = []
	var vels: Array[Vector3] = []
	for j: int in st["defs"].size():
		defs.append(_on_ice(st["defs"][j] + _jitter()))
		vels.append(st["vels"][j] * _pace())
	var n: int = int(HORIZON_S / Duel.DT)
	var pts: Array[Vector3] = []
	var ts: Array[float] = []
	var duel: Object = Duel.new()
	_add_carrier(duel, c_pos, c_vel, path)
	for j: int in defs.size():
		duel.add_skater(DEFENDER + j, 1, defs[j], null, vels[j])
	duel.start(CARRIER)
	var event_t: float = -1.0
	var event_kind: String = ""
	var end_t: float = HORIZON_S
	for i: int in n:
		var before := Vector3i(duel.strips, duel.lifts, duel.hit_strips)
		duel.step()
		var t: float = (i + 1) * Duel.DT
		if duel.carrier_id != CARRIER:
			if _losses(duel) > before.x + before.y + before.z:
				event_t = t
				event_kind = "poke" if duel.strips > before.x \
						else ("lift" if duel.lifts > before.y else "hit")
			end_t = t
			break
		if (i + 1) % SAMPLE_TICKS == 0:
			pts.append(duel.puck_pos)
			ts.append(t)
	if pts.is_empty():
		return
	_family.append(st["family"])
	_defs.append(defs)
	_def_vels.append(vels)
	_points.append(pts)
	_times.append(ts)
	_stand.append(_standing(pts, ts, c_pos))
	_event_t.append(event_t)
	_event_kind.append(event_kind)
	_end_t.append(end_t)


func _standing(pts: Array[Vector3], ts: Array[float], start: Vector3) -> Array[bool]:
	var out: Array[bool] = []
	var prev: Vector3 = start
	var prev_t: float = 0.0
	for k: int in pts.size():
		var d := Vector2(pts[k].x - prev.x, pts[k].z - prev.z)
		out.append(d.length() / maxf(ts[k] - prev_t, 0.001) < STAND_M_S)
		prev = pts[k]
		prev_t = ts[k]
	return out


# Every row's stick time per defender at every sample, for a reaction (and a
# reach: the stick's when negative).
func _stick_times(react: float, reach_m: float = -1.0) -> Array:
	var out: Array = []
	for r: int in _family.size():
		var per_def: Array = []
		var defs: Array[Vector3] = _defs[r]
		var vels: Array[Vector3] = _def_vels[r]
		var pts: Array[Vector3] = _points[r]
		for i: int in defs.size():
			var st: Array[float] = []
			for p: Vector3 in pts:
				st.append(AIDefenderRace.stick_time(defs[i], vels[i], _caps, p, react, reach_m))
			per_def.append(st)
		out.append(per_def)
	return out


# The race's odds a stick is in reach at each of row `r`'s samples, each
# defender's counted for `window` s from when he first likely has it (the odds
# past even): the defenders' summed, or the likeliest one's alone.
func _reach(sticks_r: Array, ts: Array[float], sigma: float, growth: float,
		window: float, worst_only: bool = false) -> Array[float]:
	var out: Array[float] = []
	for k: int in ts.size():
		out.append(0.0)
	for st: Array[float] in sticks_r:
		var first: float = INF
		for k: int in ts.size():
			if ts[k] > first + window + 1e-6:
				break
			var p: float = 1.0 - AIDefenderRace.keep(st[k], ts[k], sigma, growth)
			if p >= 0.5 and first == INF:
				first = ts[k]
			out[k] = maxf(out[k], p) if worst_only else out[k] + p
	return out


# Row `r`'s exposure up to `until`: the seconds in reach while the puck stands
# and while it moves.
func _exposure(r: int, reach: Array[float], until: float) -> Vector2:
	var ts: Array[float] = _times[r]
	var stand: Array[bool] = _stand[r]
	var e := Vector2.ZERO
	var prev_t: float = 0.0
	for k: int in ts.size():
		if prev_t >= until - 1e-6:
			break
		var dt: float = minf(ts[k], until) - prev_t
		if stand[k]:
			e.x += dt * reach[k]
		else:
			e.y += dt * reach[k]
		prev_t = ts[k]
	return e


func _event_sample(r: int) -> int:
	var ts: Array[float] = _times[r]
	for k: int in ts.size():
		if ts[k] >= _event_t[r] - 1e-6:
			return k
	return ts.size() - 1


func _fit_set(r: int) -> bool:
	return _family[r] in ["straight", "chased", "cut", "stand"]


# How surely the puck at each of row `r`'s samples is within reach of where each
# defender's momentum has him then, summed over the defenders.
func _coast(r: int, radius: float = -1.0) -> Array[float]:
	var reach: float = radius if radius >= 0.0 else AILaneReach.defender_reach(_caps)
	var defs: Array[Vector3] = _defs[r]
	var vels: Array[Vector3] = _def_vels[r]
	var pts: Array[Vector3] = _points[r]
	var ts: Array[float] = _times[r]
	var out: Array[float] = []
	for k: int in pts.size():
		var c: float = 0.0
		for i: int in defs.size():
			var at: Vector3 = defs[i] + vels[i] * ts[k]
			var d: float = Vector2(pts[k].x - at.x, pts[k].z - at.z).length()
			c += clampf((reach + COAST_EDGE_M - d) / (2.0 * COAST_EDGE_M), 0.0, 1.0)
		out.append(c)
	return out


func _coast_exposure(r: int, coast: Array[float], until: float) -> float:
	var ts: Array[float] = _times[r]
	var e: float = 0.0
	var prev_t: float = 0.0
	for k: int in ts.size():
		if prev_t >= until - 1e-6:
			break
		e += (minf(ts[k], until) - prev_t) * coast[k]
		prev_t = ts[k]
	return e


# Every row's in-reach odds for a fit.
func _odds(sticks: Array, sigma: float, growth: float, window: float,
		worst_only: bool = false) -> Array:
	var out: Array = []
	for r: int in _family.size():
		out.append(_reach(sticks[r], _times[r], sigma, growth, window, worst_only))
	return out


# The fit set's exposure totals and its losses' [row, sample].
func _summaries(odds: Array) -> Array:
	var total := Vector2.ZERO
	var events: Array = []
	for r: int in _family.size():
		if not _fit_set(r):
			continue
		total += _exposure(r, odds[r], _end_t[r])
		if _event_t[r] >= 0.0:
			events.append([r, _event_sample(r)])
	return [total, events]


# `rates`: strip rate in reach standing and moving, and coming to him (/s).
func _log_likelihood(odds: Array, coasts: Array, summary: Array, rates: Vector3) -> float:
	var total: Vector3 = summary[0]
	var ll: float = -rates.x * total.x - rates.y * total.y - rates.z * total.z
	for ev: Array in summary[1]:
		var r: int = ev[0]
		var k: int = ev[1]
		var reach: Array[float] = odds[r]
		var coast: Array[float] = coasts[r]
		ll += log(maxf((rates.x if _stand[r][k] else rates.y) * reach[k] + rates.z * coast[k],
				1e-9))
	return ll


func _fit() -> Array:
	var best: Array = [-INF, 0.0, 0.0, 0.0, Vector3.ZERO, 0.0, -1.0]
	for radius: float in COAST_RADII:
		var res: Array = _fit_radius(radius)
		if res[0] > best[0]:
			best = res
	return best


func _fit_radius(radius: float) -> Array:
	var best: Array = [-INF, 0.0, 0.0, 0.0, Vector3.ZERO, 0.0, radius]
	var coasts: Array = []
	for r: int in _family.size():
		coasts.append(_coast(r, radius))
	for react: float in REACTS:
		var sticks: Array = _stick_times(react)
		for sigma: float in SIGMAS:
			for growth: float in GROWTHS:
				for window: float in WINDOWS:
					var odds: Array = _odds(sticks, sigma, growth, window)
					var summary: Array = _summaries(odds)
					var total := Vector3(summary[0].x, summary[0].y, 0.0)
					for r: int in _family.size():
						if _fit_set(r):
							total.z += _coast_exposure(r, coasts[r], _end_t[r])
					summary[0] = total
					for c: float in COAST_RATES:
						for m: float in MOVING_GRID:
							for st: float in STANDING_GRID:
								var rates := Vector3(st, m, c)
								var ll: float = _log_likelihood(odds, coasts, summary, rates)
								if ll > best[0]:
									best = [ll, react, sigma, growth, rates, window, radius]
	return best


# Observed and expected losses over `rows`, at the fit's rates.
func _observed_expected(odds: Array, best: Array, rows: Array[int],
		t_lo: float = 0.0, t_hi: float = HORIZON_S) -> Vector2:
	var rates: Vector3 = best[4]
	var obs: float = 0.0
	var expct: float = 0.0
	for r: int in rows:
		var until: float = minf(_end_t[r], t_hi)
		if until <= t_lo:
			continue
		var e: Vector2 = _exposure(r, odds[r], until) - _exposure(r, odds[r], t_lo)
		var coast: Array[float] = _coast(r, best[6])
		var c: float = _coast_exposure(r, coast, until) - _coast_exposure(r, coast, t_lo)
		expct += rates.x * e.x + rates.y * e.y + rates.z * c
		if _event_t[r] >= t_lo and _event_t[r] < t_hi:
			obs += 1.0
	return Vector2(obs, expct)


func _rows(family: String) -> Array[int]:
	var out: Array[int] = []
	for r: int in _family.size():
		if _family[r] == family:
			out.append(r)
	return out


func _report(best: Array) -> void:
	var rates: Vector3 = best[4]
	gut.p("fit: react %.2f s, grade %.2f s + %.2f x T | strip rate in reach standing %.2f /s, moving %.2f /s; coming within %.1f m of him %.2f /s" % [
			best[1], best[2], best[3], rates.x, rates.y, best[6], rates.z])
	var sticks: Array = _stick_times(best[1])
	var odds: Array = _odds(sticks, best[2], best[3], best[5])
	gut.p("observed / expected losses by family:")
	for fam: String in ["straight", "chased", "cut", "stand", "pair", "bot"]:
		var oe: Vector2 = _observed_expected(odds, best, _rows(fam))
		gut.p("  %-9s %4.0f / %6.1f = %.2f" % [fam, oe.x, oe.y, oe.x / maxf(oe.y, 1e-6)])
	var worst: Vector2 = _observed_expected(_odds(sticks, best[2], best[3], best[5], true),
			best, _rows("pair"))
	gut.p("  pair, the likeliest man alone: %4.0f / %6.1f = %.2f" % [worst.x, worst.y,
			worst.x / maxf(worst.y, 1e-6)])
	var fit_rows: Array[int] = []
	for r: int in _family.size():
		if _fit_set(r):
			fit_rows.append(r)
	gut.p("observed / expected by time (fit set):")
	for b: int in 3:
		var oe: Vector2 = _observed_expected(odds, best, fit_rows, float(b), b + 1.0)
		gut.p("  %d-%d s  %4.0f / %6.1f = %.2f" % [b, b + 1, oe.x, oe.y, oe.x / maxf(oe.y, 1e-6)])
	var bot: Vector2 = _observed_expected(odds, best, _rows("bot"))
	gut.p("bot carrier: his shield leaves %.2f of the scripted carrier's losses (%d of %.1f)" % [
			bot.x / maxf(bot.y, 1e-6), int(bot.x), bot.y])
	_report_brier(odds, best)


# The fit's keep at each horizon against what was kept, beside predicting the
# base rate and today's read, over the scripted single-defender runs.
func _report_brier(odds: Array, best: Array) -> void:
	var rates: Vector3 = best[4]
	var kept_sum: float = 0.0
	var n: int = 0
	var race_b: float = 0.0
	var now_b: float = 0.0
	var race_sub: float = 0.0
	var n_sub: int = 0
	for r: int in _family.size():
		if not _fit_set(r):
			continue
		var pts: Array[Vector3] = _points[r]
		var ts: Array[float] = _times[r]
		for h: float in HORIZONS:
			var e: Vector2 = _exposure(r, odds[r], h)
			var p: float = exp(-rates.x * e.x - rates.y * e.y
					- rates.z * _coast_exposure(r, _coast(r, best[6]), h))
			var y: float = 0.0 if _event_t[r] >= 0.0 and _event_t[r] < h else 1.0
			kept_sum += y
			race_b += (p - y) * (p - y)
			n += 1
			if _family[r] != "straight" and _family[r] != "stand":
				continue
			var k: int = mini(int(round(h / ts[0])) - 1, pts.size() - 1)
			var defs: Array[Vector3] = _defs[r]
			var vels: Array[Vector3] = _def_vels[r]
			var caps: Array = [_caps]
			var p_now: float
			if _family[r] == "stand":
				p_now = AICarrySpace.clearance_to_safety(AICarrySpace.reach_clearance(pts[k], h,
						defs, vels, caps, minf(h, AICarrySpace.CARRY_LUNGE_WINDOW_S)),
						AICarrySpace.reach_band_m)
			else:
				p_now = AICarrySpace.carry_safety(pts[0], pts[k], h, defs, vels, caps, true)
			now_b += (p_now - y) * (p_now - y)
			race_sub += (p - y) * (p - y)
			n_sub += 1
	var base: float = kept_sum / n
	gut.p("Brier over %d reads: base rate %.3f, race %.3f | straight and standing (%d): today %.3f, race %.3f" % [
			n, base * (1.0 - base), race_b / n, n_sub, now_b / n_sub, race_sub / n_sub])
	gut.p("ranking (the odds a kept run reads safer than a lost one, at %.0f s): %.3f" % [
			HORIZON_S, _ranking(odds, best)])


# Over the fit set at the horizon: how often a run that kept the puck reads safer
# than one that lost it (0.5 is no better than a coin; ties count half).
func _ranking(odds: Array, best: Array) -> float:
	var rates: Vector3 = best[4]
	var kept: Array[float] = []
	var lost: Array[float] = []
	for r: int in _family.size():
		if not _fit_set(r):
			continue
		var e: Vector2 = _exposure(r, odds[r], HORIZON_S)
		var p: float = exp(-rates.x * e.x - rates.y * e.y
				- rates.z * _coast_exposure(r, _coast(r, best[6]), HORIZON_S))
		if _event_t[r] >= 0.0:
			lost.append(p)
		else:
			kept.append(p)
	var wins: float = 0.0
	for a: float in kept:
		for b: float in lost:
			wins += 1.0 if a > b else (0.5 if a == b else 0.0)
	return wins / maxf(float(kept.size() * lost.size()), 1.0)


func _save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for r: int in _family.size():
		var defs: Array[Vector3] = _defs[r]
		var vels: Array[Vector3] = _def_vels[r]
		var line := PackedStringArray([_family[r], str(_event_t[r]), str(_end_t[r]),
				_event_kind[r] if _event_kind[r] != "" else "-", str(defs.size())])
		for i: int in defs.size():
			line.append_array([str(defs[i].x), str(defs[i].z), str(vels[i].x), str(vels[i].z)])
		var pts: Array[Vector3] = _points[r]
		var ts: Array[float] = _times[r]
		var stand: Array[bool] = _stand[r]
		for k: int in pts.size():
			line.append_array([str(ts[k]), str(pts[k].x), str(pts[k].z), "1" if stand[k] else "0"])
		f.store_line(" ".join(line))


func _load(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var parts: PackedStringArray = f.get_line().split(" ", false)
		if parts.size() < 5:
			continue
		_family.append(parts[0])
		_event_t.append(float(parts[1]))
		_end_t.append(float(parts[2]))
		_event_kind.append(parts[3] if parts[3] != "-" else "")
		var nd: int = int(parts[4])
		var defs: Array[Vector3] = []
		var vels: Array[Vector3] = []
		for i: int in nd:
			var b: int = 5 + i * 4
			defs.append(Vector3(float(parts[b]), 0, float(parts[b + 1])))
			vels.append(Vector3(float(parts[b + 2]), 0, float(parts[b + 3])))
		_defs.append(defs)
		_def_vels.append(vels)
		var pts: Array[Vector3] = []
		var ts: Array[float] = []
		var stand: Array[bool] = []
		for k: int in range(5 + nd * 4, parts.size(), 4):
			ts.append(float(parts[k]))
			pts.append(Vector3(float(parts[k + 1]), 0, float(parts[k + 2])))
			stand.append(parts[k + 3] == "1")
		_points.append(pts)
		_times.append(ts)
		_stand.append(stand)


func test_defender_race_truth() -> void:
	if OS.has_environment("MITTS_RACE_FROM"):
		_load(OS.get_environment("MITTS_RACE_FROM"))
	else:
		_rng.seed = 20261027
		var stagings: Array[Dictionary] = _stagings()
		var limit: int = int(OS.get_environment("MITTS_RACE_LIMIT")) \
				if OS.has_environment("MITTS_RACE_LIMIT") else stagings.size()
		var t0: int = Time.get_ticks_msec()
		var stride: int = maxi(1, stagings.size() / maxi(limit, 1))
		for i: int in range(0, stagings.size(), stride):
			for _r: int in REPEATS:
				_run(stagings[i])
		gut.p("%d runs in %.0f s" % [_family.size(), (Time.get_ticks_msec() - t0) / 1000.0])
		if OS.has_environment("MITTS_RACE_SAVE"):
			_save(OS.get_environment("MITTS_RACE_SAVE"))
	for fam: String in ["straight", "chased", "cut", "stand", "pair", "bot"]:
		var rows: Array[int] = _rows(fam)
		var lost: int = 0
		var kinds: Dictionary = {}
		var early: int = 0
		for r: int in rows:
			if _event_t[r] < 0.0:
				continue
			lost += 1
			kinds[_event_kind[r]] = int(kinds.get(_event_kind[r], 0)) + 1
			early += 1 if _event_t[r] < 1.0 else 0
		gut.p("  %-9s lost %d of %d (in the first second %d) %s" % [fam, lost, rows.size(),
				early, str(kinds)])
	_report(_fit())
	assert_true(true)

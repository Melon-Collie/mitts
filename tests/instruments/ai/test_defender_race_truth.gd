extends GutTest

# The defender race (AIDefenderRace, docs/defender-race-plan.md) against our
# real defending bots. Each staging puts a carrier on the ice with one or two
# real defender bots and records when the puck was lost, and where the puck was
# until then. A bot carrier decides for himself (protecting, evading), and a
# release ends his run without a loss; a scripted carrier skates a one-shot path
# through the real movement model and can be stripped.
#
# The model: while a defender's stick is in reach the puck is stripped at a rate
# per second — the race giving the odds he is in reach at each moment, faded by
# how far the puck is off where his momentum has him (what he has to commit to),
# a rate for a standing puck and one for a moving puck — plus a rate while the
# puck is within his reach of where his momentum has him; the defenders'
# exposures add. Fitted on the bot carriers' single-defender runs (MITTS_RACE_FIT
# names other families), scored by likelihood against a constant loss rate and
# by how often a kept run reads safer than a lost one; the pairs test the adding,
# and observed against expected losses by family and by time read the rest.
# Reports only. MITTS_RACE_ONLY runs the named families, MITTS_RACE_LIMIT caps
# the stagings, MITTS_RACE_SAVE writes the runs to a file and MITTS_RACE_FROM
# refits from files (comma separated), MITTS_RACE_MIN_GAP leaving out the runs
# that start with a defender that close.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const CARRIER := 1
const DEFENDER := 201
const HORIZON_S: float = 3.0
const SAMPLE_TICKS: int = 12
const TOP_PACE_M_S: float = 8.0
const REPEATS: int = 2
const JITTER_M: float = 0.5
const JITTER_PACE: float = 0.1
const START_X: float = -3.0
const START_ZS: Array[float] = [14.0, 4.0, -4.0]
const BOT_START_XS: Array[float] = [-6.0, 0.0, 5.0]
const PATH_END_Z: float = -(GameRules.GOAL_LINE_Z - 3.0)
const EDGE_M: float = 1.5
# A puck slower than this between samples is standing.
const STAND_M_S: float = 1.0
const COAST_EDGE_M: float = 0.3
const FAMILIES: Array[String] = ["bot_lane", "bot_off", "bot_pair", "bot",
		"straight", "chased", "cut", "stand", "pair"]
const DEFAULT_FIT: Array[String] = ["bot_lane", "bot_off"]

const REACTS: Array[float] = [0.1, 0.15, 0.2, 0.3]
const SIGMAS: Array[float] = [0.1, 0.2, 0.3]
# How far off his momentum's line (m, past his reach) the race's odds fade by
# e; the last is the pure race.
const COMMITS: Array[float] = [1.0, 2.0, 3.0, 5.0, 8.0, 1.0e6]
const COAST_RATES: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
const MOVING_RATES: Array[float] = [0.0, 0.02, 0.05, 0.08, 0.12, 0.16, 0.2, 0.25, 0.3, 0.4, 0.5]
const STANDING_RATES: Array[float] = [0.0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.8, 1.0]

var _rng := RandomNumberGenerator.new()
var _caps: AISkaterCaps = Duel.match_caps()
var _fit_families: Array[String] = []
# One row per run.
var _family: Array[String] = []
var _defs: Array = []      # Array[Array[Vector3]]
var _def_vels: Array = []  # Array[Array[Vector3]]
var _points: Array = []    # Array[Array[Vector3]]: the puck every sample
var _times: Array = []     # Array[Array[float]]
var _stand: Array = []     # Array[Array[bool]]: the puck standing at each sample
var _event_t: Array[float] = []   # when the puck was lost (-1: not)
var _event_kind: Array[String] = []   # poke, lift or hit ("" when not lost)
var _end_t: Array[float] = []     # when the run stopped being watched


func _stagings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var backing := Vector3(0, 0, -3.0)
	var closing := Vector3(0, 0, 3.0)
	var still := Vector3.ZERO
	var none: Array[Vector3] = []
	for z0: float in START_ZS:
		for x0: float in BOT_START_XS:
			var bc := Vector3(x0, 0, z0)
			for v0: float in [0.0, 4.0, 7.5]:
				for d: float in [3.0, 6.0, 10.0, 15.0]:
					for lat: float in [-3.0, 0.0, 3.0]:
						for dv: Vector3 in [still, backing, closing]:
							out.append(_staging("bot_lane" if lat == 0.0 else "bot_off", bc,
									Vector3(0, 0, -v0), none, [bc + Vector3(lat, 0, -d)], [dv]))
		var c := Vector3(START_X, 0, z0)
		for v0: float in [4.0, 7.5]:
			var cv := Vector3(0, 0, -v0)
			for pair: Vector2 in [Vector2(4.0, 8.0), Vector2(6.0, 6.0), Vector2(3.0, 10.0)]:
				for dv: Vector3 in [still, backing]:
					out.append(_staging("bot_pair", c, cv, none,
							[c + Vector3(3.0, 0, -pair.x), c + Vector3(-3.0, 0, -pair.y)], [dv, dv]))
			out.append(_staging("bot_pair", c, cv, none,
					[c + Vector3(2.0, 0, -6.0), c + Vector3(1.0, 0, 3.0)],
					[still, Vector3(0, 0, -maxf(v0, 3.0))]))
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
	var duel: Object = Duel.new()
	_add_carrier(duel, c_pos, c_vel, path)
	for j: int in defs.size():
		duel.add_skater(DEFENDER + j, 1, defs[j], null, vels[j])
	duel.start(CARRIER)
	var pts: Array[Vector3] = []
	var ts: Array[float] = []
	var event_t: float = -1.0
	var event_kind: String = ""
	var end_t: float = HORIZON_S
	for i: int in int(HORIZON_S / Duel.DT):
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


# Every row's stick time per defender at every sample, for a reaction.
func _stick_times(react: float) -> Array:
	var out: Array = []
	for r: int in _family.size():
		var per_def: Array = []
		var defs: Array[Vector3] = _defs[r]
		var vels: Array[Vector3] = _def_vels[r]
		var pts: Array[Vector3] = _points[r]
		for i: int in defs.size():
			var st: Array[float] = []
			for p: Vector3 in pts:
				st.append(AIDefenderRace.stick_time(defs[i], vels[i], _caps, p, react))
			per_def.append(st)
		out.append(per_def)
	return out


# Every row's distance past his reach of the puck from where each defender's
# momentum has him, at every sample.
func _offsets() -> Array:
	var reach: float = AILaneReach.defender_reach(_caps)
	var out: Array = []
	for r: int in _family.size():
		var per_def: Array = []
		var defs: Array[Vector3] = _defs[r]
		var vels: Array[Vector3] = _def_vels[r]
		var pts: Array[Vector3] = _points[r]
		var ts: Array[float] = _times[r]
		for i: int in defs.size():
			var off: Array[float] = []
			for k: int in pts.size():
				var at: Vector3 = defs[i] + vels[i] * ts[k]
				off.append(Vector2(pts[k].x - at.x, pts[k].z - at.z).length() - reach)
			per_def.append(off)
		out.append(per_def)
	return out


# Row `r`'s in-reach odds at each sample, each defender's faded by `commit_m`,
# summed over the defenders (or the likeliest one's alone).
func _reach(sticks_r: Array, offsets_r: Array, ts: Array[float], sigma: float,
		commit_m: float, worst_only: bool = false) -> Array[float]:
	var out: Array[float] = []
	for k: int in ts.size():
		var total: float = 0.0
		for i: int in sticks_r.size():
			var st: Array[float] = sticks_r[i]
			var off: Array[float] = offsets_r[i]
			var p: float = (1.0 - AIDefenderRace.keep(st[k], ts[k], sigma, 0.0)) \
					* exp(-maxf(off[k], 0.0) / commit_m)
			total = maxf(total, p) if worst_only else total + p
		out.append(total)
	return out


# Row `r`'s odds the puck is within reach of where each defender's momentum has
# him, summed.
func _coast(offsets_r: Array, ts: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for k: int in ts.size():
		var c: float = 0.0
		for off: Array[float] in offsets_r:
			c += clampf((COAST_EDGE_M - off[k]) / (2.0 * COAST_EDGE_M), 0.0, 1.0)
		out.append(c)
	return out


# Row `r`'s exposure up to `until`: seconds in reach while the puck stands, while
# it moves, and seconds coming to him.
func _exposure(r: int, reach: Array[float], coast: Array[float], until: float) -> Vector3:
	var ts: Array[float] = _times[r]
	var stand: Array[bool] = _stand[r]
	var e := Vector3.ZERO
	var prev_t: float = 0.0
	for k: int in ts.size():
		if prev_t >= until - 1e-6:
			break
		var dt: float = minf(ts[k], until) - prev_t
		if stand[k]:
			e.x += dt * reach[k]
		else:
			e.y += dt * reach[k]
		e.z += dt * coast[k]
		prev_t = ts[k]
	return e


func _event_sample(r: int) -> int:
	var ts: Array[float] = _times[r]
	for k: int in ts.size():
		if ts[k] >= _event_t[r] - 1e-6:
			return k
	return ts.size() - 1


func _fit_set(r: int) -> bool:
	return _family[r] in _fit_families


# `rates`: strip rate in reach standing, moving, and coming to him (/s).
func _hazard(r: int, k: int, reach: Array[float], coast: Array[float], rates: Vector3) -> float:
	return (rates.x if _stand[r][k] else rates.y) * reach[k] + rates.z * coast[k]


# A fit's in-reach and coming-to-him odds per row.
func _odds(sticks: Array, offsets: Array, coasts: Array, sigma: float, commit_m: float,
		worst_only: bool = false) -> Array:
	var reach: Array = []
	for r: int in _family.size():
		reach.append(_reach(sticks[r], offsets[r], _times[r], sigma, commit_m, worst_only))
	return [reach, coasts]


func _fit() -> Array:
	var best: Array = [-INF, 0.0, 0.0, 0.0, Vector3.ZERO]
	var offsets: Array = _offsets()
	var coasts: Array = []
	for r: int in _family.size():
		coasts.append(_coast(offsets[r], _times[r]))
	for react: float in REACTS:
		var sticks: Array = _stick_times(react)
		for sigma: float in SIGMAS:
			for commit_m: float in COMMITS:
				var odds: Array = _odds(sticks, offsets, coasts, sigma, commit_m)
				var total := Vector3.ZERO
				var events: Array[Vector2i] = []
				for r: int in _family.size():
					if not _fit_set(r):
						continue
					total += _exposure(r, odds[0][r], coasts[r], _end_t[r])
					if _event_t[r] >= 0.0:
						events.append(Vector2i(r, _event_sample(r)))
				for c: float in COAST_RATES:
					for m: float in MOVING_RATES:
						for s: float in STANDING_RATES:
							var rates := Vector3(s, m, c)
							var ll: float = -rates.x * total.x - rates.y * total.y - rates.z * total.z
							for ev: Vector2i in events:
								ll += log(maxf(_hazard(ev.x, ev.y, odds[0][ev.x], coasts[ev.x],
										rates), 1e-9))
							if ll > best[0]:
								best = [ll, react, sigma, commit_m, rates]
	return best


# Observed and expected losses over `rows`, at the fit's rates.
func _observed_expected(odds: Array, rates: Vector3, rows: Array[int],
		t_lo: float = 0.0, t_hi: float = HORIZON_S) -> Vector2:
	var obs: float = 0.0
	var expct: float = 0.0
	for r: int in rows:
		var until: float = minf(_end_t[r], t_hi)
		if until <= t_lo:
			continue
		var e: Vector3 = _exposure(r, odds[0][r], odds[1][r], until) \
				- _exposure(r, odds[0][r], odds[1][r], t_lo)
		expct += rates.x * e.x + rates.y * e.y + rates.z * e.z
		if _event_t[r] >= t_lo and _event_t[r] < t_hi:
			obs += 1.0
	return Vector2(obs, expct)


func _rows(family: String) -> Array[int]:
	var out: Array[int] = []
	for r: int in _family.size():
		if _family[r] == family:
			out.append(r)
	return out


func _fit_rows() -> Array[int]:
	var out: Array[int] = []
	for r: int in _family.size():
		if _fit_set(r):
			out.append(r)
	return out


func _report(best: Array) -> void:
	var rates: Vector3 = best[4]
	gut.p("fit on %s: react %.2f s, grade %.2f s, commitment fades over %s | strip rate in reach standing %.2f /s, moving %.2f /s; coming to him %.2f /s" % [
			str(_fit_families), best[1], best[2],
			"never" if best[3] > 1000.0 else "%.0f m" % best[3], rates.x, rates.y, rates.z])
	var offsets: Array = _offsets()
	var coasts: Array = []
	for r: int in _family.size():
		coasts.append(_coast(offsets[r], _times[r]))
	var sticks: Array = _stick_times(best[1])
	var odds: Array = _odds(sticks, offsets, coasts, best[2], best[3])
	gut.p("observed / expected losses by family:")
	for fam: String in FAMILIES:
		var rows: Array[int] = _rows(fam)
		if rows.is_empty():
			continue
		var oe: Vector2 = _observed_expected(odds, rates, rows)
		gut.p("  %-9s %4.0f / %6.1f = %.2f" % [fam, oe.x, oe.y, oe.x / maxf(oe.y, 1e-6)])
	for fam: String in ["bot_pair", "pair"]:
		var rows: Array[int] = _rows(fam)
		if rows.is_empty():
			continue
		var worst: Vector2 = _observed_expected(_odds(sticks, offsets, coasts, best[2], best[3],
				true), rates, rows)
		gut.p("  %s, the likeliest man alone: %4.0f / %6.1f = %.2f" % [fam, worst.x, worst.y,
				worst.x / maxf(worst.y, 1e-6)])
	var fit_rows: Array[int] = _fit_rows()
	gut.p("observed / expected by time (fit set):")
	for b: int in 3:
		var oe: Vector2 = _observed_expected(odds, rates, fit_rows, float(b), b + 1.0)
		gut.p("  %d-%d s  %4.0f / %6.1f = %.2f" % [b, b + 1, oe.x, oe.y, oe.x / maxf(oe.y, 1e-6)])
	_report_scores(odds, best)


# Over the fit set: log likelihood per run against a constant loss rate, and how
# often, at each loss, the run that lost it had read riskier up to then than a
# run still in play (0.5 is a coin).
func _report_scores(odds: Array, best: Array) -> void:
	var rates: Vector3 = best[4]
	var rows: Array[int] = _fit_rows()
	var events: float = 0.0
	var watched: float = 0.0
	for r: int in rows:
		events += 1.0 if _event_t[r] >= 0.0 else 0.0
		watched += _end_t[r]
	var rate0: float = events / maxf(watched, 1e-6)
	var ll0: float = events * log(maxf(rate0, 1e-9)) - rate0 * watched
	gut.p("log likelihood per run: race %.3f, a constant %.2f losses/s %.3f" % [
			best[0] / rows.size(), rate0, ll0 / rows.size()])
	var risk: Array = []
	for r: int in _family.size():
		risk.append(_cumulative_risk(r, odds, rates) if _fit_set(r) else [])
	var concordant: float = 0.0
	var pairs: float = 0.0
	for a: int in rows:
		if _event_t[a] < 0.0:
			continue
		var k: int = _event_sample(a)
		var risk_a: Array[float] = risk[a]
		for b: int in rows:
			var risk_b: Array[float] = risk[b]
			if b == a or _end_t[b] <= _event_t[a] or risk_b.size() <= k:
				continue
			pairs += 1.0
			concordant += 1.0 if risk_a[k] > risk_b[k] else (0.5 if risk_a[k] == risk_b[k] else 0.0)
	gut.p("ranking (at each loss, the lost run read riskier than one still in play): %.3f over %.0f pairs" % [
			concordant / maxf(pairs, 1.0), pairs])


# Row `r`'s expected losses up to each sample at `rates`.
func _cumulative_risk(r: int, odds: Array, rates: Vector3) -> Array[float]:
	var ts: Array[float] = _times[r]
	var reach: Array[float] = odds[0][r]
	var coast: Array[float] = odds[1][r]
	var out: Array[float] = []
	var total: float = 0.0
	var prev_t: float = 0.0
	for k: int in ts.size():
		total += (ts[k] - prev_t) * _hazard(r, k, reach, coast, rates)
		prev_t = ts[k]
		out.append(total)
	return out


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
		if _starts_inside(defs, pts):
			_drop_last()


# Whether a defender starts within MITTS_RACE_MIN_GAP (m) of the puck: a staging
# that drops the carrier on a man before he has had a read to react to him.
func _starts_inside(defs: Array[Vector3], pts: Array[Vector3]) -> bool:
	if not OS.has_environment("MITTS_RACE_MIN_GAP") or pts.is_empty():
		return false
	var gap: float = float(OS.get_environment("MITTS_RACE_MIN_GAP"))
	for d: Vector3 in defs:
		if Vector2(d.x - pts[0].x, d.z - pts[0].z).length() < gap:
			return true
	return false


func _drop_last() -> void:
	for arr: Array in [_family, _defs, _def_vels, _points, _times, _stand, _event_t, _event_kind,
			_end_t]:
		arr.pop_back()


func _env_list(key: String, fallback: Array[String]) -> Array[String]:
	if not OS.has_environment(key):
		return fallback
	var out: Array[String] = []
	for part: String in OS.get_environment(key).split(",", false):
		out.append(part.strip_edges())
	return out


func test_defender_race_truth() -> void:
	_fit_families = _env_list("MITTS_RACE_FIT", DEFAULT_FIT)
	if OS.has_environment("MITTS_RACE_FROM"):
		for path: String in OS.get_environment("MITTS_RACE_FROM").split(",", false):
			_load(path)
	else:
		_rng.seed = 20261027
		var only: Array[String] = _env_list("MITTS_RACE_ONLY", FAMILIES)
		var stagings: Array[Dictionary] = []
		for st: Dictionary in _stagings():
			if st["family"] in only:
				stagings.append(st)
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
	for fam: String in FAMILIES:
		var rows: Array[int] = _rows(fam)
		if rows.is_empty():
			continue
		var lost: int = 0
		var released: int = 0
		var kinds: Dictionary = {}
		for r: int in rows:
			if _event_t[r] >= 0.0:
				lost += 1
				kinds[_event_kind[r]] = int(kinds.get(_event_kind[r], 0)) + 1
			elif _end_t[r] < HORIZON_S - 1e-6:
				released += 1
		gut.p("  %-9s lost %d, released %d, of %d %s" % [fam, lost, released, rows.size(),
				str(kinds)])
	_report(_fit())
	assert_true(true)

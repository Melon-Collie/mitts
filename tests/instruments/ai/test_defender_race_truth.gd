extends GutTest

# The defender race (AIDefenderRace, docs/defender-race-plan.md) against our
# real defending bots. A scripted carrier skates a one-shot path through the
# real movement model and can be stripped; one real defender bot plays him. Each
# staging records when the puck was lost, and the path it would have kept to
# (the same carrier skated alone). The race's reaction, σ₀ and growth are then
# fitted to the outcomes at several horizons, linear ramp against logistic, and
# as a strip rate per second his stick is in reach (a hazard on the race's odds
# he is there); today's carry read is scored on the families it prices
# (straight carries, a standing carrier). Reports only. MITTS_RACE_LIMIT caps the
# stagings; MITTS_RACE_SAVE writes the runs to a file and MITTS_RACE_FROM refits
# from one without skating them.

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

const REACTS: Array[float] = [0.0, 0.15, 0.3, 0.5, 0.8, 1.2]
const SIGMAS: Array[float] = [0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 1.0]
const GROWTHS: Array[float] = [0.0, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 1.0]
const RATES: Array[float] = [0.1, 0.2, 0.35, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0]

var _rng := RandomNumberGenerator.new()
# One row per staging run.
var _family: Array[String] = []
var _d_pos: Array[Vector3] = []
var _d_vel: Array[Vector3] = []
var _caps: Array[AISkaterCaps] = []
var _points: Array = []   # Array[Array[Vector3]]: the kept path's puck, every sample
var _times: Array = []    # Array[Array[float]]
var _loss_t: Array[float] = []


func _stagings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var backing := Vector3(0, 0, -3.0)
	var closing := Vector3(0, 0, 3.0)
	for z0: float in START_ZS:
		var c := Vector3(START_X, 0, z0)
		var straight: Array[Vector3] = [c, Vector3(START_X, 0, PATH_END_Z)]
		for v0: float in [0.0, 4.0, 7.5]:
			for d: float in [3.0, 6.0, 10.0, 15.0]:
				for lat: float in [0.0, 3.0, 6.0]:
					for dv: Vector3 in [Vector3.ZERO, backing, closing]:
						out.append(_staging("straight", c, Vector3(0, 0, -v0), straight,
								c + Vector3(lat, 0, -d), dv))
			for d: float in [2.0, 4.0]:
				for lat: float in [0.0, 2.0]:
					out.append(_staging("chased", c, Vector3(0, 0, -v0), straight,
							c + Vector3(lat, 0, d), Vector3(0, 0, -maxf(v0, 3.0))))
		var p1: Vector3 = c + Vector3(0, 0, -2.0)
		for deg: float in [30.0, 60.0, 90.0]:
			for side: float in [-1.0, 1.0]:
				var a: float = deg_to_rad(deg)
				var cut: Array[Vector3] = [c, p1,
						_on_ice(p1 + Vector3(side * sin(a), 0, -cos(a)) * 30.0)]
				for d: float in [4.0, 8.0, 12.0]:
					for lat: float in [-3.0, 0.0, 3.0]:
						for dv: Vector3 in [Vector3.ZERO, backing]:
							out.append(_staging("cut", c, Vector3(0, 0, -7.5), cut,
									c + Vector3(lat, 0, -d), dv))
		var stand: Array[Vector3] = [c]
		for d: float in [2.0, 4.0, 7.0, 10.0]:
			for lat: float in [0.0, 3.0]:
				for dv: Vector3 in [Vector3.ZERO, closing, Vector3(3.0, 0, 0)]:
					out.append(_staging("stand", c, Vector3.ZERO, stand, c + Vector3(lat, 0, -d), dv))
	return out


func _staging(family: String, c_pos: Vector3, c_vel: Vector3, path: Array[Vector3],
		d_pos: Vector3, d_vel: Vector3) -> Dictionary:
	return {"family": family, "c_pos": c_pos, "c_vel": c_vel, "path": path,
			"d_pos": d_pos, "d_vel": d_vel}


func _on_ice(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -GameRules.RINK_HALF_WIDTH + EDGE_M, GameRules.RINK_HALF_WIDTH - EDGE_M),
			0, clampf(p.z, PATH_END_Z, -PATH_END_Z))


func _add_carrier(duel: Object, path: Array[Vector3], vel: Vector3) -> void:
	duel.add_skater(CARRIER, 0, path[0], null, vel)
	var s: Object = duel._skater(CARRIER)
	s.script_path = path
	s.script_speed = TOP_PACE_M_S
	s.script_idx = 1 % path.size()
	s.script_skates = true
	s.script_loop = false
	s.script_strippable = true


func _run(st: Dictionary) -> void:
	var shift := Vector3(_rng.randf_range(-JITTER_M, JITTER_M), 0,
			_rng.randf_range(-JITTER_M, JITTER_M))
	var path: Array[Vector3] = []
	for p: Vector3 in st["path"]:
		path.append(_on_ice(p + shift))
	var c_vel: Vector3 = st["c_vel"] * (1.0 + _rng.randf_range(-JITTER_PACE, JITTER_PACE))
	var d_pos: Vector3 = _on_ice(st["d_pos"] + Vector3(_rng.randf_range(-JITTER_M, JITTER_M), 0,
			_rng.randf_range(-JITTER_M, JITTER_M)))
	var d_vel: Vector3 = st["d_vel"] * (1.0 + _rng.randf_range(-JITTER_PACE, JITTER_PACE))
	var n: int = int(HORIZON_S / Duel.DT)
	# The path he keeps to, skated alone.
	var solo: Object = Duel.new()
	_add_carrier(solo, path, c_vel)
	solo.start(CARRIER)
	var pts: Array[Vector3] = []
	var ts: Array[float] = []
	for i: int in n:
		solo.step()
		if (i + 1) % SAMPLE_TICKS == 0:
			pts.append(solo.puck_pos)
			ts.append((i + 1) * Duel.DT)
	# Against the defender.
	var duel: Object = Duel.new()
	_add_carrier(duel, path, c_vel)
	duel.add_skater(DEFENDER, 1, d_pos, null, d_vel)
	duel.start(CARRIER)
	var lost: float = -1.0
	for i: int in n:
		duel.step()
		if duel.carrier_id != CARRIER:
			lost = (i + 1) * Duel.DT
			break
	_family.append(st["family"])
	_d_pos.append(d_pos)
	_d_vel.append(d_vel)
	_caps.append(duel.caps_by_peer[DEFENDER])
	_points.append(pts)
	_times.append(ts)
	_loss_t.append(lost)


func _kept(row: int, h: float) -> float:
	return 0.0 if _loss_t[row] >= 0.0 and _loss_t[row] < h else 1.0


# Every row's stick time at every sample, for a reaction.
func _stick_times(react: float) -> Array:
	var out: Array = []
	for r: int in _loss_t.size():
		var st: Array[float] = []
		var pts: Array[Vector3] = _points[r]
		for p: Vector3 in pts:
			st.append(AIDefenderRace.stick_time(_d_pos[r], _d_vel[r], _caps[r], p, react))
		out.append(st)
	return out


func _keep(t_stick: float, t: float, sigma: float, growth: float, logistic: bool) -> float:
	if not logistic:
		return AIDefenderRace.keep(t_stick, t, sigma, growth)
	return 1.0 / (1.0 + exp(-(t_stick - t) / maxf(sigma + growth * t, 0.001)))


# The model's keep for row `r` up to horizon `h`.
func _predict(st: Array[float], ts: Array[float], h: float, sigma: float, growth: float,
		logistic: bool) -> float:
	var p: float = 1.0
	for k: int in ts.size():
		if ts[k] > h + 1e-6:
			break
		p = minf(p, _keep(st[k], ts[k], sigma, growth, logistic))
	return p


# The hazard model's exposure for row `r` up to each sample: the seconds his
# stick is in reach, each sample weighted by the race's odds he is there.
func _exposure(st: Array[float], ts: Array[float], sigma: float, growth: float) -> Array[float]:
	var out: Array[float] = []
	var e: float = 0.0
	var prev: float = 0.0
	for k: int in ts.size():
		e += (ts[k] - prev) * (1.0 - AIDefenderRace.keep(st[k], ts[k], sigma, growth))
		prev = ts[k]
		out.append(e)
	return out


func _fit_hazard() -> Array:
	var best: Array = [INF, 0.0, 0.0, 0.0, 0.0, 0.0]
	for react: float in REACTS:
		var sticks: Array = _stick_times(react)
		for sigma: float in SIGMAS:
			for growth: float in GROWTHS:
				var exposures: Array = []
				for r: int in _loss_t.size():
					exposures.append(_exposure(sticks[r], _times[r], sigma, growth))
				for rate: float in RATES:
					var s: Vector2 = _score_hazard(exposures, rate)
					if s.y < best[0]:
						best = [s.y, s.x, react, sigma, growth, rate]
	return best


func _hazard_keep(ex: Array[float], ts: Array[float], h: float, rate: float) -> float:
	var k: int = mini(int(round(h / ts[0])) - 1, ex.size() - 1)
	return exp(-rate * ex[k])


func _score_hazard(exposures: Array, rate: float) -> Vector2:
	var brier: float = 0.0
	var ll: float = 0.0
	var n: int = 0
	for r: int in _loss_t.size():
		for h: float in HORIZONS:
			var p: float = _hazard_keep(exposures[r], _times[r], h, rate)
			var y: float = _kept(r, h)
			brier += (p - y) * (p - y)
			var q: float = clampf(p, 0.01, 0.99)
			ll -= y * log(q) + (1.0 - y) * log(1.0 - q)
			n += 1
	return Vector2(brier / n, ll / n)


func _score(sticks: Array, sigma: float, growth: float, logistic: bool) -> Vector2:
	var brier: float = 0.0
	var ll: float = 0.0
	var n: int = 0
	for r: int in _loss_t.size():
		for h: float in HORIZONS:
			var p: float = _predict(sticks[r], _times[r], h, sigma, growth, logistic)
			var y: float = _kept(r, h)
			brier += (p - y) * (p - y)
			var q: float = clampf(p, 0.01, 0.99)
			ll -= y * log(q) + (1.0 - y) * log(1.0 - q)
			n += 1
	return Vector2(brier / n, ll / n)


func _fit(logistic: bool) -> Array:
	var best: Array = [INF, 0.0, 0.0, 0.0, 0.0]
	for react: float in REACTS:
		var sticks: Array = _stick_times(react)
		for sigma: float in SIGMAS:
			for growth: float in GROWTHS:
				var s: Vector2 = _score(sticks, sigma, growth, logistic)
				if s.y < best[0]:
					best = [s.y, s.x, react, sigma, growth]
	return best


func _report_fit(label: String, best: Array) -> void:
	gut.p("%s: react %.2f s, sigma %.2f s + %.2f x T | log loss %.3f, Brier %.3f" % [
			label, best[2], best[3], best[4], best[0], best[1]])


# Every row's keep at each horizon, from the ramp fit or the hazard fit.
func _predictions(best: Array, hazard: bool) -> Array:
	var sticks: Array = _stick_times(best[2])
	var out: Array = []
	for r: int in _loss_t.size():
		var row: Array[float] = []
		var ex: Array[float] = []
		if hazard:
			ex = _exposure(sticks[r], _times[r], best[3], best[4])
		for h: float in HORIZONS:
			row.append(_hazard_keep(ex, _times[r], h, best[5]) if hazard
					else _predict(sticks[r], _times[r], h, best[3], best[4], false))
		out.append(row)
	return out


func _report_detail(label: String, preds: Array) -> void:
	var bin_n: Array[int] = []
	var bin_p: Array[float] = []
	var bin_y: Array[float] = []
	for b: int in 10:
		bin_n.append(0)
		bin_p.append(0.0)
		bin_y.append(0.0)
	var fam_err: Dictionary = {}
	var h_err: Dictionary = {}
	for r: int in _loss_t.size():
		var row: Array[float] = preds[r]
		for j: int in HORIZONS.size():
			var p: float = row[j]
			var y: float = _kept(r, HORIZONS[j])
			var b: int = mini(int(p * 10.0), 9)
			bin_n[b] += 1
			bin_p[b] += p
			bin_y[b] += y
			var e: Vector2 = fam_err.get(_family[r], Vector2.ZERO)
			fam_err[_family[r]] = e + Vector2(p - y, 1.0)
			var eh: Vector2 = h_err.get(j, Vector2.ZERO)
			h_err[j] = eh + Vector2(p - y, 1.0)
	gut.p("%s calibration (predicted keep: n, mean predicted, kept):" % label)
	for b: int in 10:
		if bin_n[b] > 0:
			gut.p("  %.1f-%.1f: %4d  %.2f  %.2f" % [b / 10.0, (b + 1) / 10.0, bin_n[b],
					bin_p[b] / bin_n[b], bin_y[b] / bin_n[b]])
	gut.p("%s bias (predicted - kept) by family:" % label)
	for key: String in fam_err:
		gut.p("  %-9s %+.3f over %d" % [key, fam_err[key].x / fam_err[key].y, int(fam_err[key].y)])
	gut.p("%s bias by horizon:" % label)
	for j: int in HORIZONS.size():
		gut.p("  %.1f s  %+.3f" % [HORIZONS[j], h_err[j].x / h_err[j].y])


# Today's reads on the families they price directly, against the fits there.
func _report_baseline(ramp: Array, hazard: Array) -> void:
	var now_b: float = 0.0
	var ramp_b: float = 0.0
	var hazard_b: float = 0.0
	var n: int = 0
	for r: int in _loss_t.size():
		if _family[r] != "straight" and _family[r] != "stand":
			continue
		var pts: Array[Vector3] = _points[r]
		var ts: Array[float] = _times[r]
		var opp: Array[Vector3] = [_d_pos[r]]
		var vel: Array[Vector3] = [_d_vel[r]]
		var caps: Array = [_caps[r]]
		var ramp_row: Array[float] = ramp[r]
		var hazard_row: Array[float] = hazard[r]
		for j: int in HORIZONS.size():
			var h: float = HORIZONS[j]
			var k: int = mini(int(round(h / ts[0])) - 1, pts.size() - 1)
			var p_now: float
			if _family[r] == "stand":
				p_now = AICarrySpace.clearance_to_safety(AICarrySpace.reach_clearance(pts[k], h,
						opp, vel, caps, minf(h, AICarrySpace.CARRY_LUNGE_WINDOW_S)),
						AICarrySpace.reach_band_m)
			else:
				p_now = AICarrySpace.carry_safety(pts[0], pts[k], h, opp, vel, caps, true)
			var y: float = _kept(r, h)
			now_b += (p_now - y) * (p_now - y)
			ramp_b += (ramp_row[j] - y) * (ramp_row[j] - y)
			hazard_b += (hazard_row[j] - y) * (hazard_row[j] - y)
			n += 1
	gut.p("straight and standing carriers (%d reads): Brier today %.3f, race %.3f, hazard %.3f" % [
			n, now_b / n, ramp_b / n, hazard_b / n])


func _save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for r: int in _loss_t.size():
		var line := PackedStringArray([_family[r], str(_d_pos[r].x), str(_d_pos[r].z),
				str(_d_vel[r].x), str(_d_vel[r].z), str(_loss_t[r])])
		var pts: Array[Vector3] = _points[r]
		var ts: Array[float] = _times[r]
		for k: int in pts.size():
			line.append_array([str(ts[k]), str(pts[k].x), str(pts[k].z)])
		f.store_line(" ".join(line))


func _load(path: String) -> void:
	var caps: AISkaterCaps = Duel.match_caps()
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var parts: PackedStringArray = f.get_line().split(" ", false)
		if parts.size() < 6:
			continue
		_family.append(parts[0])
		_d_pos.append(Vector3(float(parts[1]), 0, float(parts[2])))
		_d_vel.append(Vector3(float(parts[3]), 0, float(parts[4])))
		_loss_t.append(float(parts[5]))
		_caps.append(caps)
		var pts: Array[Vector3] = []
		var ts: Array[float] = []
		for k: int in range(6, parts.size(), 3):
			ts.append(float(parts[k]))
			pts.append(Vector3(float(parts[k + 1]), 0, float(parts[k + 2])))
		_points.append(pts)
		_times.append(ts)


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
		gut.p("%d runs in %.0f s" % [_loss_t.size(), (Time.get_ticks_msec() - t0) / 1000.0])
		if OS.has_environment("MITTS_RACE_SAVE"):
			_save(OS.get_environment("MITTS_RACE_SAVE"))
	var fams: Dictionary = {}
	for r: int in _loss_t.size():
		var e: Vector2 = fams.get(_family[r], Vector2.ZERO)
		fams[_family[r]] = e + Vector2(1.0 if _loss_t[r] >= 0.0 else 0.0, 1.0)
	for key: String in fams:
		gut.p("  %-9s lost within %.0f s: %.2f of %d" % [key, HORIZON_S, fams[key].x / fams[key].y,
				int(fams[key].y)])
	var base: float = 0.0
	var n: int = 0
	for r: int in _loss_t.size():
		for h: float in HORIZONS:
			base += _kept(r, h)
			n += 1
	var rate: float = base / n
	gut.p("base rate kept %.2f (Brier of predicting it: %.3f)" % [rate, rate * (1.0 - rate)])
	var ramp: Array = _fit(false)
	_report_fit("ramp", ramp)
	_report_fit("logistic", _fit(true))
	var hazard: Array = _fit_hazard()
	gut.p("hazard: react %.2f s, sigma %.2f s + %.2f x T, strip rate %.2f /s in reach | log loss %.3f, Brier %.3f" % [
			hazard[2], hazard[3], hazard[4], hazard[5], hazard[0], hazard[1]])
	var ramp_preds: Array = _predictions(ramp, false)
	var hazard_preds: Array = _predictions(hazard, true)
	_report_detail("hazard", hazard_preds)
	_report_baseline(ramp_preds, hazard_preds)
	assert_true(true)

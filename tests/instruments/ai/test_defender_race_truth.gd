extends GutTest

# The strip odds (AIStripOdds, docs/defender-race-plan.md) against our real
# defending bots. Each staging puts a carrier on the ice with one or two real
# defender bots and records when the puck was lost, where the puck was until then
# and where each defender was. A scripted carrier skates a one-shot path through
# the real movement model, protecting the puck as a bot does, and can be
# stripped; a bot carrier decides for himself, and a release ends his run without
# a loss.
#
# Fitted apart: where the defenders went against the ease of getting there, for
# what their spread is centred on (the movement half), and, given where they
# were, the losses by the puck's path through their reach, by time in reach and
# by entries into it, the strip radius fitted (the strip half); then the two
# together from the start alone, nothing refitted. Scored by likelihood against a
# constant loss rate and by how often, at each loss, the run that lost the puck
# had read riskier than one still in play. Reports only. MITTS_RACE_ONLY runs the
# named families, MITTS_RACE_LIMIT caps the stagings, MITTS_RACE_SAVE writes the
# runs to a file and MITTS_RACE_FROM refits from files (comma separated),
# MITTS_RACE_MIN_GAP leaving out the runs that start with a defender that close;
# MITTS_WRITE_STRIP_TRUTH=1 writes the strip odds' truth file from the tracked
# runs.

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
const FAMILIES: Array[String] = ["bot_lane", "bot_off", "bot_pair", "bot",
		"straight", "straight_lane", "straight_side", "chased", "cut", "stand", "pair"]
# The scripted single-defender families the movement and overlap fits read.
const SCRIPTED: Array[String] = ["straight_lane", "straight_side", "chased", "cut", "stand"]
# Where a defender is read from, after a reaction (s), for the movement fit.
const MOVE_REACTS: Array[float] = [0.0, 0.1, 0.2, 0.3]
const MOVE_MIN_T: float = 0.2
# The overlap fit's strip chance per metre of the puck's path through his reach,
# and rate per second a standing puck sits in it.
const OVERLAP_RATES: Array[float] = [0.0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.8, 1.0, 1.3, 1.7, 2.2, 3.0, 4.0, 5.5]
const STAND_IN_RATES: Array[float] = [0.0, 0.1, 0.2, 0.3, 0.45, 0.6, 1.0, 1.5, 2.2, 3.0, 4.5, 6.0]

var _rng := RandomNumberGenerator.new()
var _caps: AISkaterCaps = Duel.match_caps()
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
var _tracks: Array = []    # Array[Array[Array[Vector3]]]: each defender every sample (empty: not recorded)
# The movement fit's best [log likelihood, react, shaped, scale], and the strip
# fit's time-in-reach [radius, moving rate, standing rate], for the combined read.
var _best_move: Dictionary = {}   # centre → [log likelihood, react, shaped, scale]
var _best_strip: Array = []
var _centres: Dictionary = {}     # "centre/react" → per row, per defender [positions, velocities]


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
						out.append(_staging("straight_lane" if lat == 0.0 else "straight_side", c,
								cv, straight, [c + Vector3(lat, 0, -d)], [dv]))
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
	s.script_protects = OS.get_environment("MITTS_RACE_SHIELD") != "0"


func _add_defender(duel: Object, peer_id: int, pos: Vector3, vel: Vector3) -> void:
	duel.add_skater(peer_id, 1, pos, null, vel)


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
		_add_defender(duel, DEFENDER + j, defs[j], vels[j])
	duel.start(CARRIER)
	var pts: Array[Vector3] = []
	var ts: Array[float] = []
	var track: Array = []
	for j: int in defs.size():
		var tj: Array[Vector3] = []
		track.append(tj)
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
			pts.append(duel._skater(CARRIER).blade)
			ts.append(t)
			for j: int in defs.size():
				track[j].append(duel._skater(DEFENDER + j).pos)
			break
		if (i + 1) % SAMPLE_TICKS == 0:
			pts.append(duel.puck_pos)
			ts.append(t)
			for j: int in defs.size():
				track[j].append(duel._skater(DEFENDER + j).pos)
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
	_tracks.append(track)


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


func _rows(family: String) -> Array[int]:
	var out: Array[int] = []
	for r: int in _family.size():
		if _family[r] == family:
			out.append(r)
	return out


# What a defender's spread is centred on: his momentum's line; skating at the
# puck as he saw it a reaction ago; at where it is heading; or a share of the
# way from his momentum's line to his pursuit's (blend25 a quarter).
const CENTRES: Array[String] = ["coast", "pursuit", "intercept", "blend15", "blend30", "blend50"]


# The movement half: where each tracked defender really went against the ease
# of getting there — the push needed to bend his centre's path onto the spot in
# the time after his reaction, as a share of what his body gives (thrust ahead,
# capped by his top speed; the stop behind; thrust across) — fanned as
# e^(−push / scale), the scale the likelihood's own answer (the mean push over
# 2). Against the same fan with neither the top speed nor the stop (a disc).
func _report_movement() -> void:
	var rows: Array[int] = _tracked_rows(FAMILIES)
	if rows.is_empty():
		return
	gut.p("movement: where %d tracked runs' defenders went, against the ease of getting there" % rows.size())
	for centre: String in CENTRES:
		_best_move[centre] = [-INF, 0.0, true, 1.0]
		for react: float in MOVE_REACTS:
			var centres: Array = _centres_for(centre, react)
			for shaped: bool in [true, false]:
				var us: Array[float] = []
				var log_area: float = 0.0
				for r: int in rows:
					var ts: Array[float] = _times[r]
					var track: Array = _tracks[r]
					for i: int in track.size():
						var cpos: Array[Vector3] = centres[r][i][0]
						var cvel: Array[Vector3] = centres[r][i][1]
						for k: int in ts.size():
							if ts[k] < MOVE_MIN_T:
								continue
							var e: Vector2 = _ease(cpos[k], cvel[k], track[i][k], ts[k], react, shaped)
							us.append(e.x)
							log_area += e.y
				var mean: float = 0.0
				for u: float in us:
					mean += u
				mean /= us.size()
				var scale: float = 0.5 * mean
				var ll: float = (-mean * us.size() / scale - us.size() * 2.0 * log(scale) - log_area) \
						/ us.size()
				if ll > _best_move[centre][0]:
					_best_move[centre] = [ll, react, shaped, scale]
				us.sort()
				gut.p("  %-9s react %.1f s, %s: scale %.2f | log likelihood per point %.3f | push needed: median %.2f, 90%% %.2f; within his body's %.0f%%" % [
						centre, react, "top speed and stop" if shaped else "a disc", scale, ll,
						us[us.size() / 2], us[us.size() * 9 / 10], 100.0 * us.bsearch(1.0) / us.size()])


# Per row, per defender, his centre's [positions, velocities] at each sample,
# for a centre and a reaction (memoized).
func _centres_for(centre: String, react: float) -> Array:
	var key: String = "%s/%.2f" % [centre, react]
	if _centres.has(key):
		return _centres[key]
	var out: Array = []
	for r: int in _family.size():
		var per_def: Array = []
		var defs: Array[Vector3] = _defs[r]
		var vels: Array[Vector3] = _def_vels[r]
		var shares: Array = []
		if centre.begins_with("blend"):
			shares = [_centres_for("coast", react)[r], _centres_for("pursuit", react)[r]]
		for i: int in defs.size():
			if centre.begins_with("blend"):
				var w: float = float(centre.substr(5)) / 100.0
				var cpos: Array[Vector3] = []
				var cvel: Array[Vector3] = []
				var cp: Array[Vector3] = shares[0][i][0]
				var cv: Array[Vector3] = shares[0][i][1]
				var pp: Array[Vector3] = shares[1][i][0]
				var pv: Array[Vector3] = shares[1][i][1]
				for k: int in cp.size():
					cpos.append(cp[k].lerp(pp[k], w))
					cvel.append(cv[k].lerp(pv[k], w))
				per_def.append([cpos, cvel])
			elif centre == "coast":
				var cpos: Array[Vector3] = []
				var cvel: Array[Vector3] = []
				for t: float in _times[r]:
					cpos.append(defs[i] + vels[i] * t)
					cvel.append(vels[i])
				per_def.append([cpos, cvel])
			else:
				per_def.append(_pursuit(r, defs[i], vels[i], react, centre == "intercept"))
		out.append(per_def)
	_centres[key] = out
	return out


# A defender starting at `p0` moving `v0` who carries on for `react`, then skates
# at row `r`'s puck as he saw it a reaction ago (`lead`: at where it is heading,
# a trip's worth on), on his thrust and top speed, easing in to it: his
# [positions, velocities] at the row's samples.
func _pursuit(r: int, p0: Vector3, v0: Vector3, react: float, lead: bool) -> Array:
	var ts: Array[float] = _times[r]
	var cpos: Array[Vector3] = []
	var cvel: Array[Vector3] = []
	var p: Vector3 = p0
	var v: Vector3 = v0
	var t: float = 0.0
	var h: float = 1.0 / 60.0
	for k: int in ts.size():
		while t < ts[k] - 1e-6:
			var step: float = minf(h, ts[k] - t)
			if t >= react:
				var target: Vector3 = _puck_at(r, t - react)
				if lead:
					var seen: Vector3 = (target - _puck_at(r, t - react - 0.1)) / 0.1
					target += seen * minf(Vector2(target.x - p.x, target.z - p.z).length()
							/ _caps.max_speed, 1.0)
				var to := Vector3(target.x - p.x, 0.0, target.z - p.z)
				var want: Vector3 = to.normalized() * minf(_caps.max_speed, to.length() * 3.0) \
						if to.length() > 0.01 else Vector3.ZERO
				v += (want - v).limit_length(_caps.max_accel * step)
			p += v * step
			t += step
		cpos.append(p)
		cvel.append(v)
	return [cpos, cvel]


# Row `r`'s puck at `t`, between its samples (its first before them).
func _puck_at(r: int, t: float) -> Vector3:
	var ts: Array[float] = _times[r]
	var pts: Array[Vector3] = _points[r]
	if t <= ts[0]:
		return pts[0]
	for k: int in range(1, ts.size()):
		if ts[k] >= t:
			return pts[k - 1].lerp(pts[k], (t - ts[k - 1]) / maxf(ts[k] - ts[k - 1], 1e-6))
	return pts[pts.size() - 1]


# The push a defender whose centre is at `centre` moving `cvel` needs to be at
# `x` `t` from now (his share of his body's push), and the log of the fan's area
# scale.
func _ease(centre: Vector3, cvel: Vector3, x: Vector3, t: float, react: float,
		shaped: bool) -> Vector2:
	var tau: float = maxf(t - react, 0.05)
	var d := Vector2(x.x - centre.x, x.z - centre.z)
	var speed: float = Vector2(cvel.x, cvel.z).length()
	var dir: Vector2 = Vector2(cvel.x, cvel.z) / speed if speed > 0.5 \
			else (d.normalized() if d.length() > 0.001 else Vector2(1, 0))
	var along: float = d.dot(dir)
	var across: float = absf(d.cross(dir))
	var half: float = 0.5 * tau * tau
	var s_f: float = half * _caps.max_accel
	var s_b: float = s_f
	var s_c: float = s_f
	if shaped:
		s_f = maxf(minf(s_f, (_caps.max_speed - speed) * tau), 0.1)
		if speed > 0.5:
			s_b = half * GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2
	var s_a: float = s_f if along >= 0.0 else s_b
	var u: float = sqrt((along / s_a) * (along / s_a) + (across / s_c) * (across / s_c))
	return Vector2(u, log(PI * s_c * (s_f + s_b)))


func _tracked_rows(families: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for r: int in _family.size():
		if not _tracks[r].is_empty() and _family[r] in families:
			out.append(r)
	return out


# How much of the segment `a`→`b` lies within `rad` of the origin (m).
func _segment_in_disc(a: Vector2, b: Vector2, rad: float) -> float:
	var d: Vector2 = b - a
	var aa: float = d.dot(d)
	if aa < 1e-9:
		return 0.0
	var bb: float = 2.0 * a.dot(d)
	var cc: float = a.dot(a) - rad * rad
	var disc: float = bb * bb - 4.0 * aa * cc
	if disc <= 0.0:
		return 0.0
	var sq: float = sqrt(disc)
	var t1: float = clampf((-bb - sq) / (2.0 * aa), 0.0, 1.0)
	var t2: float = clampf((-bb + sq) / (2.0 * aa), 0.0, 1.0)
	return maxf(0.0, t2 - t1) * sqrt(aa)


# Row `r`'s per-sample exposure, given where each defender really was, summed
# over them: the metres of the puck's path through his reach in his frame (a
# standing puck he arrives on counting a full pass through it), the seconds a
# standing puck sat in his reach, the seconds a moving one did, and the puck's
# entries into his reach (from outside it, or through it between samples).
func _overlaps(r: int, reach: float) -> Array:
	var pts: Array[Vector3] = _points[r]
	var ts: Array[float] = _times[r]
	var stand: Array[bool] = _stand[r]
	var track: Array = _tracks[r]
	var ov: Array[float] = []
	var st: Array[float] = []
	var mv: Array[float] = []
	var en: Array[float] = []
	for k: int in ts.size():
		var dt: float = ts[k] - (ts[k - 1] if k > 0 else 0.0)
		var o: float = 0.0
		var s_in: float = 0.0
		var m_in: float = 0.0
		var entries: float = 0.0
		for i: int in track.size():
			var r1 := Vector2(pts[k].x - track[i][k].x, pts[k].z - track[i][k].z)
			var r0: Vector2 = r1 if k == 0 \
					else Vector2(pts[k - 1].x - track[i][k - 1].x, pts[k - 1].z - track[i][k - 1].z)
			var inside: bool = r1.length() <= reach
			if r0.length() > reach and (inside or _segment_in_disc(r0, r1, reach) > 0.0):
				entries += 1.0
			elif k == 0 and inside:
				entries += 1.0
			if stand[k]:
				if inside:
					s_in += dt
					if r0.length() > reach:
						o += 2.0 * reach
			else:
				o += _segment_in_disc(r0, r1, reach)
				if inside:
					m_in += dt
		ov.append(o)
		st.append(s_in)
		mv.append(m_in)
		en.append(entries)
	return [ov, st, mv, en]


# The strip models the tracked runs are read by: each a list of exposure
# components (_overlaps' indices) with a rate on each, gridded.
const OVERLAP := 0
const STAND_IN := 1
const MOVE_IN := 2
const ENTRY := 3
const ENTRY_RATES: Array[float] = [0.0, 0.05, 0.1, 0.2, 0.3, 0.45, 0.6, 0.8, 1.0, 1.5, 2.0, 3.0]
# The strip rate (/s) while a moving puck is in reach, for the time-in-reach
# models.
const MOVE_IN_RATES: Array[float] = [0.0, 0.1, 0.2, 0.3, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.5, 6.0]
# The radius (m) his stick takes the puck within, off his body: the race's reach
# (stick, blade and a buffer) and further out to his full reach with the poke.
const STRIP_RADII: Array[float] = [1.8, 2.0, 2.2, 2.4, 2.6]


func _strip_models() -> Array:
	return [
		["overlap (per metre) + standing in reach (/s)", [OVERLAP, STAND_IN], [OVERLAP_RATES, STAND_IN_RATES]],
		["time in reach, moving and standing (/s)", [MOVE_IN, STAND_IN], [MOVE_IN_RATES, STAND_IN_RATES]],
		["entry (per entry) + moving and standing in reach (/s)", [ENTRY, MOVE_IN, STAND_IN],
				[ENTRY_RATES, MOVE_IN_RATES, STAND_IN_RATES]],
	]


# Over `rows`: each component's total, and each loss's components at its sample
# over the interval's length.
func _strip_basis(rows: Array[int], exposures: Array, comps: Array) -> Array:
	var totals: Array[float] = []
	for _c: int in comps.size():
		totals.append(0.0)
	var events: Array = []
	for r: int in rows:
		var e: Array = exposures[r]
		var ts: Array[float] = _times[r]
		for c: int in comps.size():
			var col: Array[float] = e[comps[c]]
			for k: int in ts.size():
				totals[c] += col[k]
		if _event_t[r] >= 0.0:
			var k: int = ts.size() - 1
			var dt: float = maxf(ts[k] - (ts[k - 1] if k > 0 else 0.0), 0.001)
			var at: Array[float] = []
			for c: int in comps.size():
				var col: Array[float] = e[comps[c]]
				at.append(col[k] / dt)
			events.append(at)
	return [totals, events]


func _basis_ll(basis: Array, rates: Array[float]) -> float:
	var totals: Array[float] = basis[0]
	var ll: float = 0.0
	for c: int in rates.size():
		ll -= rates[c] * totals[c]
	for at: Array[float] in basis[1]:
		var h: float = 0.0
		for c: int in rates.size():
			h += rates[c] * at[c]
		ll += log(maxf(h, 1e-9))
	return ll


func _grid_fit(basis: Array, grids: Array) -> Array:
	var best: Array = [-INF, []]
	var idx: Array[int] = []
	for _g: int in grids.size():
		idx.append(0)
	while true:
		var rates: Array[float] = []
		for g: int in grids.size():
			rates.append(grids[g][idx[g]])
		var ll: float = _basis_ll(basis, rates)
		if ll > best[0]:
			best = [ll, rates]
		var g2: int = 0
		while g2 < grids.size():
			idx[g2] += 1
			if idx[g2] < grids[g2].size():
				break
			idx[g2] = 0
			g2 += 1
		if g2 == grids.size():
			break
	return best


# Row `r`'s expected losses up to each sample at `rates` on `comps`.
func _strip_risk(e: Array, comps: Array, rates: Array[float]) -> Array[float]:
	var first: Array[float] = e[comps[0]]
	var out: Array[float] = []
	var total: float = 0.0
	for k: int in first.size():
		for c: int in comps.size():
			var col: Array[float] = e[comps[c]]
			total += rates[c] * col[k]
		out.append(total)
	return out


# The strip half: given where each defender really was, how surely each strip
# model reads the losses on the scripted single-defender runs, against a
# constant loss rate; then observed against expected by family.
func _report_overlap() -> void:
	var rows: Array[int] = _tracked_rows(SCRIPTED)
	if rows.is_empty():
		return
	var events: float = 0.0
	var watched: float = 0.0
	for r: int in rows:
		events += 1.0 if _event_t[r] >= 0.0 else 0.0
		watched += _end_t[r]
	var rate0: float = events / watched
	gut.p("strip: %d tracked scripted runs, %d losses; a constant %.2f losses/s: log likelihood per run %.3f" % [
			rows.size(), int(events), rate0,
			(events * log(rate0) - rate0 * watched) / rows.size()])
	for model: Array in _strip_models():
		var comps: Array = model[1]
		var best: Array = [-INF, []]
		var exposures: Array = []
		var radius: float = 0.0
		for rad: float in STRIP_RADII:
			var ex: Array = []
			for r: int in _family.size():
				ex.append(_overlaps(r, rad) if not _tracks[r].is_empty() else [])
			var fit: Array = _grid_fit(_strip_basis(rows, ex, comps), model[2])
			if fit[0] > best[0]:
				best = fit
				exposures = ex
				radius = rad
		var rates: Array[float] = best[1]
		if comps == [MOVE_IN, STAND_IN]:
			_best_strip = [radius, rates[0], rates[1]]
		var risk: Array = []
		for r: int in _family.size():
			risk.append(_strip_risk(exposures[r], comps, rates) if r in rows else [])
		gut.p("  %s within %.1f m: rates %s | log likelihood per run %.3f | ranking %.3f" % [
				model[0], radius, str(rates), best[0] / rows.size(), _risk_ranking(rows, risk)])
		for fam: String in SCRIPTED + ["pair"]:
			var fam_rows: Array[int] = _tracked_rows([fam])
			if fam_rows.is_empty():
				continue
			var obs: float = 0.0
			var expct: float = 0.0
			for r: int in fam_rows:
				var rk: Array[float] = _strip_risk(exposures[r], comps, rates)
				expct += rk[rk.size() - 1] if not rk.is_empty() else 0.0
				obs += 1.0 if _event_t[r] >= 0.0 else 0.0
			gut.p("    %-13s %4.0f / %6.1f = %.2f" % [fam, obs, expct, obs / maxf(expct, 1e-6)])


# At each loss, how often the run that lost it had read riskier up to then than
# a run still in play.
func _risk_ranking(rows: Array[int], risk: Array) -> float:
	var concordant: float = 0.0
	var pairs: float = 0.0
	for x: int in rows:
		if _event_t[x] < 0.0:
			continue
		var risk_x: Array[float] = risk[x]
		var rx: float = risk_x[risk_x.size() - 1]
		for y: int in rows:
			if y == x or _end_t[y] <= _event_t[x]:
				continue
			var ts_y: Array[float] = _times[y]
			var risk_y: Array[float] = risk[y]
			var ry: float = 0.0
			for k: int in ts_y.size():
				if ts_y[k] > _event_t[x] + 1e-6:
					break
				ry = risk_y[k]
			pairs += 1.0
			concordant += 1.0 if rx > ry else (0.5 if rx == ry else 0.0)
	return concordant / maxf(pairs, 1.0)


# The two halves together, from the start alone, for each centre: the odds each
# defender is within the strip radius of the puck at each sample (that centre's
# best fan, integrated over the radius) × the strip fit's rate, the defenders
# adding — no rate refitted. On the scripted runs: expected against observed
# losses, the ranking, and observed against expected by family.
func _report_combined() -> void:
	var rows: Array[int] = _tracked_rows(SCRIPTED)
	if rows.is_empty() or _best_strip.is_empty():
		return
	var radius: float = _best_strip[0]
	for centre: String in CENTRES:
		var move: Array = _best_move[centre]
		var centres: Array = _centres_for(centre, move[1])
		var risk: Array = []
		var total_expected: float = 0.0
		var events: float = 0.0
		for r: int in _family.size():
			if not r in rows and not (_family[r] == "pair" and not _tracks[r].is_empty()):
				risk.append([])
				continue
			var rk: Array[float] = _combined_risk(r, radius, centres[r], move)
			risk.append(rk)
			if r in rows:
				total_expected += rk[rk.size() - 1]
				events += 1.0 if _event_t[r] >= 0.0 else 0.0
		gut.p("combined, %s (react %.1f s, %s, scale %.2f; strip within %.1f m at %.2f /s moving, %.2f /s standing): %d losses against %.1f expected, ranking %.3f" % [
				centre, move[1], "shaped" if move[2] else "disc", move[3], radius,
				_best_strip[1], _best_strip[2], int(events), total_expected, _risk_ranking(rows, risk)])
		for fam: String in SCRIPTED + ["pair"]:
			var fam_rows: Array[int] = _tracked_rows([fam])
			var obs: float = 0.0
			var expct: float = 0.0
			for r: int in fam_rows:
				var rk: Array[float] = risk[r]
				expct += rk[rk.size() - 1]
				obs += 1.0 if _event_t[r] >= 0.0 else 0.0
			if not fam_rows.is_empty():
				gut.p("    %-13s %4.0f / %6.1f = %.2f" % [fam, obs, expct, obs / maxf(expct, 1e-6)])


# Row `r`'s expected losses up to each sample, read from each defender's start
# on his centre's path (`centres_r`) and the fan `move`.
func _combined_risk(r: int, radius: float, centres_r: Array, move: Array) -> Array[float]:
	var pts: Array[Vector3] = _points[r]
	var ts: Array[float] = _times[r]
	var stand: Array[bool] = _stand[r]
	var out: Array[float] = []
	var total: float = 0.0
	for k: int in ts.size():
		var dt: float = ts[k] - (ts[k - 1] if k > 0 else 0.0)
		var p_in: float = 0.0
		for c: Array in centres_r:
			var cpos: Array[Vector3] = c[0]
			var cvel: Array[Vector3] = c[1]
			p_in += _odds_within(cpos[k], cvel[k], pts[k], ts[k], radius, move)
		total += dt * (_best_strip[2] if stand[k] else _best_strip[1]) * p_in
		out.append(total)
	return out


# The fan `move`'s odds a defender centred at `centre` moving `cvel` is within
# `radius` of `point` at `t`: its density over the disc, on three rings.
func _odds_within(centre: Vector3, cvel: Vector3, point: Vector3, t: float, radius: float,
		move: Array) -> float:
	var scale: float = move[3]
	var total: float = 0.0
	var rings: Array[float] = [0.0, 0.45, 0.8]
	var shares: Array[float] = [0.09, 0.36, 0.55]
	for j: int in rings.size():
		var n: int = 1 if rings[j] == 0.0 else 8
		for a: int in n:
			var ang: float = TAU * a / n
			var x := Vector3(point.x + cos(ang) * rings[j] * radius, 0.0,
					point.z + sin(ang) * rings[j] * radius)
			var e: Vector2 = _ease(centre, cvel, x, t, move[1], move[2])
			total += shares[j] / n * exp(-e.x / scale - e.y) / (scale * scale)
	return minf(total * PI * radius * radius, 1.0)


# The strip odds' truth file (tests/unit/ai/data/strip_odds_truth.txt, read by
# test_strip_odds_vs_truth.gd): the tracked scripted runs, one of each staging's
# repeats, each defender's start and the puck's path to two decimals.
const STRIP_TRUTH_PATH: String = "res://tests/unit/ai/data/strip_odds_truth.txt"


func _write_strip_truth() -> void:
	var f := FileAccess.open(STRIP_TRUTH_PATH, FileAccess.WRITE)
	f.store_line("# Generated by tests/instruments/ai/test_defender_race_truth.gd with MITTS_WRITE_STRIP_TRUTH=1; never hand-edit.")
	f.store_line("# family	lost_at (-1: kept)	watched_to	defenders	per defender: x z vx vz	per sample: t x z (the puck)")
	var n: int = 0
	for r: int in _family.size():
		if _tracks[r].is_empty() or not (_family[r] in SCRIPTED or _family[r] == "pair") \
				or r % REPEATS != 0:
			continue
		var defs: Array[Vector3] = _defs[r]
		var vels: Array[Vector3] = _def_vels[r]
		var line := PackedStringArray([_family[r], "%.3f" % _event_t[r], "%.3f" % _end_t[r],
				str(defs.size())])
		for i: int in defs.size():
			line.append_array(["%.2f" % defs[i].x, "%.2f" % defs[i].z, "%.2f" % vels[i].x,
					"%.2f" % vels[i].z])
		var pts: Array[Vector3] = _points[r]
		var ts: Array[float] = _times[r]
		for k: int in pts.size():
			line.append_array(["%.3f" % ts[k], "%.2f" % pts[k].x, "%.2f" % pts[k].z])
		f.store_line("\t".join(line))
		n += 1
	gut.p("wrote %d runs to %s" % [n, STRIP_TRUTH_PATH])


func _save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for r: int in _family.size():
		var defs: Array[Vector3] = _defs[r]
		var vels: Array[Vector3] = _def_vels[r]
		var line := PackedStringArray([_family[r], str(_event_t[r]), str(_end_t[r]),
				_event_kind[r] if _event_kind[r] != "" else "-", str(defs.size())])
		var track: Array = _tracks[r]
		var tracked: bool = not track.is_empty()
		if tracked:
			line.append("T")
		for i: int in defs.size():
			line.append_array([str(defs[i].x), str(defs[i].z), str(vels[i].x), str(vels[i].z)])
		var pts: Array[Vector3] = _points[r]
		var ts: Array[float] = _times[r]
		var stand: Array[bool] = _stand[r]
		for k: int in pts.size():
			line.append_array([str(ts[k]), str(pts[k].x), str(pts[k].z), "1" if stand[k] else "0"])
			if tracked:
				for i: int in defs.size():
					line.append_array([str(track[i][k].x), str(track[i][k].z)])
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
		var tracked: bool = parts[5] == "T"
		var head: int = 6 if tracked else 5
		var defs: Array[Vector3] = []
		var vels: Array[Vector3] = []
		for i: int in nd:
			var b: int = head + i * 4
			defs.append(Vector3(float(parts[b]), 0, float(parts[b + 1])))
			vels.append(Vector3(float(parts[b + 2]), 0, float(parts[b + 3])))
		_defs.append(defs)
		_def_vels.append(vels)
		var pts: Array[Vector3] = []
		var ts: Array[float] = []
		var stand: Array[bool] = []
		var track: Array = []
		if tracked:
			for i: int in nd:
				var tj: Array[Vector3] = []
				track.append(tj)
		var stride: int = 4 + (2 * nd if tracked else 0)
		for k: int in range(head + nd * 4, parts.size(), stride):
			ts.append(float(parts[k]))
			pts.append(Vector3(float(parts[k + 1]), 0, float(parts[k + 2])))
			stand.append(parts[k + 3] == "1")
			if tracked:
				for i: int in nd:
					track[i].append(Vector3(float(parts[k + 4 + 2 * i]), 0,
							float(parts[k + 5 + 2 * i])))
		_points.append(pts)
		_times.append(ts)
		_stand.append(stand)
		_tracks.append(track)
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
			_end_t, _tracks]:
		arr.pop_back()


func _env_list(key: String, fallback: Array[String]) -> Array[String]:
	if not OS.has_environment(key):
		return fallback
	var out: Array[String] = []
	for part: String in OS.get_environment(key).split(",", false):
		out.append(part.strip_edges())
	return out


func test_defender_race_truth() -> void:
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
	_report_movement()
	_report_overlap()
	_report_combined()
	if OS.get_environment("MITTS_WRITE_STRIP_TRUTH") == "1":
		_write_strip_truth()
	assert_true(true)

extends GutTest

# Pass lanes against a worst-case interceptor (docs/strip-interception-plan.md's
# question, for a pass): a passer releases a flat feed, a saucer or a rim to a
# receiver, past a defender who reads the windup and knows where the puck is
# going — a real body in the duel harness whose input is replaced every tick. He
# skates flat out to the earliest point of the puck's path his stick reaches
# _set_s before the puck (else the point he has most time to spare at), a point
# where it is on the ice for a stick to play (never under a saucer), and puts
# his blade through it; once the receiver has it he runs him down instead. The
# receiver is a real bot taking the feed; the passer stands. Never our defending
# bots: what a defender can do, not what ours choose to.
#
# Windup runs put the defender on the passer, who holds the puck for the whole
# windup and can be stripped of it ("stripped"), beside the windup reads: the
# release contest and the one-chance read on the held puck.
#
# Each run records whether the pass got through (caught by the receiver, taken
# by the defender, or neither), who touched it first after the release (a
# defender's deflection or body block is the lane's, a receiver's bobble the
# reception's), what the defender's first touch did (caught it, bobbled it,
# deflected it, contested it, blocked it) at what closing speed in his frame,
# and how many torsos it ran into, whether the receiver still had the puck
# KEEP_S after the catch, and beside it each lane read the bots price with now —
# the flat accurate lane, the saucer's, the rim's — and, along the puck's
# own path, the one-chance strip read and the defender's best and first spare
# time on it where a stick can play it. Writes .preview/pass_truth/runs.csv. MITTS_PASS_SET_S overrides the
# interceptor's set margin; MITTS_PASS_LIMIT caps the stagings.
# MITTS_PASS_READS_FROM=<runs.csv> re-reads a recorded set without running it
# (the same stagings in the same order, outcomes from the file) and adds, along
# the puck's own path, the one-chance pass read at each of READ_SETS set margins:
# each defender's best AIStripOdds.chance_at on the path, his lane reach, none
# where the puck flies. Reports only.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const PASSER: int = 1
const RECEIVER: int = 2
const DEFENDER: int = 201
const WATCH_S: float = 3.0
const KEEP_S: float = 1.0
const SAMPLE_S: float = 0.1
const SET_S: float = 0.25
const PLAN_STEP_TICKS: int = 3
const PLAY_M: float = 3.0
const JAB_THROUGH_M: float = 0.6
const ARRIVE_M: float = 0.3
const OUT_DIR: String = "res://.preview/pass_truth"
# He reads the windup, not the release (AIPuckLane.LANE_WINDUP_READ_DELAY_S):
# the passer holds the puck these ticks while he already skates.
const PREROLL_TICKS: int = maxi(0, roundi(-AIPuckLane.LANE_WINDUP_READ_DELAY_S * 120.0))
# A windup run's passer holds the puck for the whole windup, strippable, against a
# defender already playing him (on his hip, or closing on it) from its start.
const WINDUP_TICKS: int = roundi(AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S * 120.0)
const READ_SETS: Array[float] = [0.0, 0.15, 0.25, 0.3, 0.45, 0.6]

var _set_s: float = SET_S
# Ticks the passer holds the puck before the release in the run at hand.
var _preroll: int = PREROLL_TICKS
# The puck's free path, every tick after the release, up to where it reaches the
# receiver's blade (the dry run's), and whether it is in the air there.
var _path: Array[Vector3] = []
var _air: Array[bool] = []
# The interceptor's line to aim at, every tick from the decision.
var _aim: Array[Vector3] = []
# Per _aim entry: the puck is in the air there, out of every stick's reach.
var _aim_air: Array[bool] = []


func test_pass_truth() -> void:
	if OS.has_environment("MITTS_PASS_SET_S"):
		_set_s = float(OS.get_environment("MITTS_PASS_SET_S"))
	var stagings: Array[Dictionary] = _stagings()
	var kinds: Dictionary = {}
	for st: Dictionary in stagings:
		kinds[st["kind"]] = int(kinds.get(st["kind"], 0)) + 1
	gut.p("stagings: %s" % str(kinds))
	var limit: int = int(OS.get_environment("MITTS_PASS_LIMIT")) \
			if OS.has_environment("MITTS_PASS_LIMIT") else stagings.size()
	var stride: int = maxi(1, stagings.size() / maxi(limit, 1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var recorded: Array[PackedStringArray] = []
	if OS.has_environment("MITTS_PASS_READS_FROM"):
		var src := FileAccess.open(OS.get_environment("MITTS_PASS_READS_FROM"), FileAccess.READ)
		src.get_line()
		while not src.eof_reached():
			var l: String = src.get_line()
			if not l.is_empty():
				recorded.append(l.split(","))
		gut.p("re-reading %d recorded runs" % recorded.size())
	var f := FileAccess.open(OUT_DIR + "/runs.csv", FileAccess.WRITE)
	var header: String = "kind,ox,oz,rx,rz,lx,ly,lz,dx,dz,dvx,dvz,outcome,t_out,kept,lane_flat," \
			+ "lane_saucer,rim_lane,path_keep,best_spare,first_spare,flight_s,first_touch,blocks," \
			+ "touch_kind,touch_closing,release_clean,windup_keep"
	for set_s: float in READ_SETS:
		header += ",pass_%02d" % roundi(set_s * 100.0)
	f.store_line(header)
	var tally: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	var n: int = 0
	for i: int in range(0, stagings.size(), stride):
		var row: Dictionary = _reread(stagings[i], recorded[n]) if not recorded.is_empty() \
				else _run(stagings[i])
		if row.is_empty():
			continue
		f.store_line(row["line"])
		var key: String = "%s %s" % [stagings[i]["kind"], row["outcome"]]
		tally[key] = int(tally.get(key, 0)) + 1
		n += 1
	gut.p("%d runs in %.0f s, set margin %.2f s" % [n, (Time.get_ticks_msec() - t0) / 1000.0, _set_s])
	var keys: Array = tally.keys()
	keys.sort()
	for k: String in keys:
		gut.p("  %-22s %d" % [k, tally[k]])
	assert_true(true)


# Flat feeds and saucers from mid-ice to receivers up-ice and either diagonal,
# and rims from deep in our end up the wall, each against a defender along the
# puck's path at a share of the way, on it or off it either side, standing or
# skating toward it.
func _stagings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var o := Vector3(0, 0, 10)
	for dir: Vector3 in [Vector3(0, 0, -1), Vector3(0.6, 0, -0.8), Vector3(-0.6, 0, -0.8)]:
		for dist: float in [8.0, 14.0, 20.0]:
			var r: Vector3 = o + dir * dist
			for pace: float in [12.0, 18.0, 24.0]:
				_add_lane_stagings(out, "flat", o, r, dir * pace)
			var saucer: float = minf(18.0, AIPuckLane.saucer_max_launch_speed(dist))
			if saucer >= AIPuckLane.SOFTEST_FEED_M_S:
				var v: Vector3 = dir * saucer
				v.y = AIPuckLane.saucer_launch_vy(saucer)
				_add_lane_stagings(out, "saucer", o, r, v)
	for dir: Vector3 in [Vector3(0, 0, -1), Vector3(0.6, 0, -0.8), Vector3(-0.6, 0, -0.8)]:
		_add_windup_stagings(out, o, o + dir * 14.0, dir * 18.0)
	for side: float in [1.0, -1.0]:
		var ro := Vector3(3.0 * side, 0, 28.0)
		for rz: float in [18.0, 14.0, 9.0]:
			var r := Vector3(11.5 * side, 0, rz)
			var launch: Vector3 = _rim_launch(ro, r)
			if launch != Vector3.ZERO:
				_add_lane_stagings(out, "rim", ro, r, launch)
	return out


func _add_lane_stagings(out: Array[Dictionary], kind: String, o: Vector3, r: Vector3,
		launch: Vector3) -> void:
	var path: Array[Vector3] = _free_path(o, r, launch)
	if path.size() < 4:
		return
	for frac: float in [0.3, 0.6, 0.9]:
		var at: Vector3 = path[int((path.size() - 1) * frac)]
		var ahead: Vector3 = path[mini(int((path.size() - 1) * frac) + 1, path.size() - 1)] - at
		var along := Vector2(ahead.x, ahead.z).normalized()
		var across := Vector2(-along.y, along.x)
		for off: float in [0.0, 1.5, 3.0, 5.0, 8.0]:
			for side: float in ([1.0] if off == 0.0 or kind == "rim" else [1.0, -1.0]):
				var p2 := Vector2(at.x, at.z) + across * off * side
				var p := Vector3(p2.x, 0, p2.y)
				if kind == "rim":
					# A rim hugs the boards: its defenders stand on the ice side of it.
					var inward := Vector2(-at.x, 0.0).normalized() if absf(at.x) > 1.0 \
							else across
					p2 = Vector2(at.x, at.z) + inward * off
					p = Vector3(p2.x, 0, p2.y)
				p = Vector3(clampf(p.x, -12.0, 12.0), 0, clampf(p.z, -27.0, 27.0))
				var toward := Vector3(at.x - p.x, 0, at.z - p.z)
				for vel: Vector3 in [Vector3.ZERO,
						toward.normalized() * 3.0 if toward.length() > 0.1 else Vector3.ZERO]:
					out.append({"kind": kind, "o": o, "r": r, "launch": launch, "d": p,
							"dv": vel})


# A flat feed from `o` to `r` against a defender on the passer: at a ring of
# distances round him, every 45° from the pass's line, standing or closing on him.
func _add_windup_stagings(out: Array[Dictionary], o: Vector3, r: Vector3,
		launch: Vector3) -> void:
	var along := Vector2(r.x - o.x, r.z - o.z).normalized()
	for dist: float in [0.8, 1.2, 1.6, 2.0, 2.5, 3.0]:
		for deg: int in range(0, 360, 45):
			var off: Vector2 = along.rotated(deg_to_rad(float(deg))) * dist
			var p := Vector3(o.x + off.x, 0, o.z + off.y)
			for vel: Vector3 in [Vector3.ZERO, (o - p).normalized() * 3.0]:
				out.append({"kind": "windup", "o": o, "r": r, "launch": launch, "d": p,
						"dv": vel})


# The rim the bots would fire from `o` to a man at `r`: of the launches that reach
# him, the softest nearly as sure as the best (AICarrierPassSearch's pick), none
# against.
func _rim_launch(o: Vector3, r: Vector3) -> Vector3:
	var none: Array[Vector3] = []
	var no_caps: Array[AISkaterCaps] = []
	AIRimPass.build(o, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, signf(o.z) * GameRules.GOAL_LINE_Z,
			none, none, no_caps)
	var best: float = INF
	var pick: int = -1
	for k: int in AIRimPass.count:
		var t: float = AIRimPass.meet_time(k, r, Vector3.ZERO, null)
		if t == INF or not AIRimPass.catchable(k, t, Vector3.ZERO):
			continue
		if pick == -1 or AIRimPass.paces[k] < AIRimPass.paces[pick] \
				or (AIRimPass.paces[k] == AIRimPass.paces[pick] and t < best):
			pick = k
			best = t
	return AIRimPass.dirs[pick] * AIRimPass.paces[pick] if pick >= 0 else Vector3.ZERO


# The puck released at `launch` from `o` with nobody on the ice to touch it, every
# tick, up to where it first comes within a blade of `r`.
func _free_path(o: Vector3, r: Vector3, launch: Vector3) -> Array[Vector3]:
	var duel: Object = Duel.new()
	_add_passer(duel, o)
	duel.start(PASSER)
	_release(duel, launch)
	var out: Array[Vector3] = []
	_air.clear()
	for _i: int in int(WATCH_S / Duel.DT):
		duel.step()
		out.append(duel.puck_pos)
		_air.append(duel.airborne_ticks > 0)
		if Vector2(duel.puck_pos.x - r.x, duel.puck_pos.z - r.z).length() <= Duel.BLADE_REACH:
			break
	return out


func _add_passer(duel: Object, o: Vector3, toward: Vector3 = Vector3.ZERO) -> void:
	duel.add_skater(PASSER, 0, o)
	var s: Object = duel._skater(PASSER)
	var stay: Array[Vector3] = [o]
	s.script_path = stay
	s.script_loop = false
	var face := Vector2(toward.x - o.x, toward.z - o.z)
	if face.length() > 0.01:
		s.facing = face.normalized()


func _release(duel: Object, launch: Vector3) -> void:
	var s: Object = duel._skater(PASSER)
	duel.carrier_id = -1
	duel.loose_released_by = PASSER
	duel.touched_by = PASSER
	duel._release_grace[PASSER] = 1 << 30
	duel.puck_pos = s.blade
	duel._launch(launch)


func _run(st: Dictionary) -> Dictionary:
	_path = _free_path(st["o"], st["r"], st["launch"])
	if _path.size() < 4:
		return {}
	var duel: Object = Duel.new()
	var windup: bool = st["kind"] == "windup"
	_preroll = WINDUP_TICKS if windup else PREROLL_TICKS
	_add_passer(duel, st["o"], st["r"])
	duel.add_skater(RECEIVER, 0, st["r"])
	duel.add_skater(DEFENDER, 1, st["d"], null, st["dv"])
	duel.start(PASSER)
	# Blades start on their bodies: one tick puts every blade, and the carried
	# puck, where its arm holds it before anyone can play anything.
	duel.step()
	var d_body: Object = duel._skater(DEFENDER)
	d_body.pos = st["d"]
	d_body.vel = st["dv"]
	duel._skater(PASSER).script_strippable = windup
	var caps: AISkaterCaps = duel.caps_by_peer.get(DEFENDER)
	duel._skater(DEFENDER).input_override = func(s: Object) -> void: _intercept(s, duel, caps)
	for i: int in _preroll:
		duel.step()
		if duel.carrier() != PASSER:
			return {"outcome": "stripped", "line": _line(st, "stripped", (i + 1 - _preroll) * Duel.DT,
					-1, caps, "defender", 0, "strip", -1.0)}
	_release(duel, st["launch"])
	var outcome: String = "incomplete"
	var t_out: float = WATCH_S
	var kept: int = -1
	var caught_at: int = -1
	var first_touch: String = "none"
	var touch_kind: String = "none"
	var touch_closing: float = -1.0
	for i: int in int((WATCH_S + KEEP_S) / Duel.DT):
		var before := Vector4(duel.bobbles, duel.deflects, duel.contests, duel.body_blocks)
		var closing: float = Vector2(duel.puck_vel.x - d_body.vel.x,
				duel.puck_vel.z - d_body.vel.z).length()
		var defender_touched: bool = duel.touched_by == DEFENDER
		duel.step()
		var t: float = (i + 1) * Duel.DT
		if touch_kind == "none" and not defender_touched and duel.touched_by == DEFENDER:
			touch_closing = closing
			touch_kind = "catch" if duel.carrier() == DEFENDER \
					else "bobble" if duel.bobbles > before.x \
					else "deflect" if duel.deflects > before.y \
					else "contest" if duel.contests > before.z \
					else "block" if duel.body_blocks > before.w else "other"
		if first_touch == "none" and duel.touched_by == DEFENDER:
			first_touch = "defender"
		elif first_touch == "none" and duel.touched_by == RECEIVER:
			first_touch = "receiver"
		var c: int = duel.carrier()
		if caught_at < 0:
			if c == DEFENDER:
				outcome = "intercepted"
				t_out = t
				break
			if c == RECEIVER:
				outcome = "complete"
				t_out = t
				caught_at = i
				kept = 1
			elif t >= WATCH_S:
				break
			continue
		if c == DEFENDER:
			kept = 0
			break
		if c == -1 and duel.loose_released_by != RECEIVER:
			kept = 0
			break
		if c != RECEIVER or (i - caught_at) * Duel.DT >= KEEP_S:
			break
	return {"outcome": outcome, "line": _line(st, outcome, t_out, kept, caps, first_touch,
			duel.body_blocks, touch_kind, touch_closing)}


# A recorded run re-read: its outcome from `cols`, every read afresh.
func _reread(st: Dictionary, cols: PackedStringArray) -> Dictionary:
	_preroll = WINDUP_TICKS if st["kind"] == "windup" else PREROLL_TICKS
	_path = _free_path(st["o"], st["r"], st["launch"])
	if _path.size() < 4:
		return {}
	var caps: AISkaterCaps = Duel.match_caps()
	return {"outcome": cols[12], "line": _line(st, cols[12], float(cols[13]), int(cols[14]), caps,
			cols[22], int(cols[23]), cols[24], float(cols[25]))}


# The run's row: its staging, outcome and the lane reads from the decision.
func _line(st: Dictionary, outcome: String, t_out: float, kept: int, caps: AISkaterCaps,
		first_touch: String, blocks: int, touch_kind: String, touch_closing: float) -> String:
	var o: Vector3 = st["o"]
	var r: Vector3 = st["r"]
	var launch: Vector3 = st["launch"]
	var d: Vector3 = st["d"]
	var dv: Vector3 = st["dv"]
	var defs: Array[Vector3] = [d]
	var vels: Array[Vector3] = [dv]
	var cap_list: Array = [caps]
	var pace: float = Vector2(launch.x, launch.z).length()
	var lane_flat: float = AIPuckLane.lane_clear(o, r, defs, pace, vels, cap_list, true)
	var lane_saucer: float = AIPuckLane.lane_clear_saucer(o, r, defs, pace, vels, cap_list) \
			if st["kind"] == "saucer" else -1.0
	var rim_lane: float = -1.0
	if st["kind"] == "rim":
		var rim_caps: Array[AISkaterCaps] = [caps]
		AIRimPass.build(o, AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
				signf(o.z) * GameRules.GOAL_LINE_Z, defs, vels, rim_caps)
		for k: int in AIRimPass.count:
			if AIRimPass.dirs[k].is_equal_approx(launch / pace) \
					and is_equal_approx(AIRimPass.paces[k], pace):
				rim_lane = AIRimPass.lane(k, AIRimPass.meet_time(k, r, Vector3.ZERO, null))
	var lead: float = _preroll * Duel.DT
	var points: Array[Vector3] = []
	var times: Array[float] = []
	var best: float = -INF
	var first: float = -1.0
	var every: int = int(SAMPLE_S / Duel.DT)
	for j: int in _path.size():
		var t: float = lead + (j + 1) * Duel.DT
		if not _air[j]:
			var spare: float = t - _stick_arrival(d, dv, _path[j], caps)
			best = maxf(best, spare)
			if first < 0.0 and spare >= 0.0:
				first = t
		if (j + 1) % every == 0 or j == _path.size() - 1:
			points.append(_path[j])
			times.append(t)
	var keep: float = AIStripOdds.path_keep(points, times, defs, vels, cap_list, 0.0, INF)
	var reads := PackedStringArray()
	var reach: float = AILaneReach.defender_reach(caps)
	for set_s: float in READ_SETS:
		var best_chance: float = 0.0
		for j: int in _path.size():
			if not _air[j]:
				best_chance = maxf(best_chance, AIStripOdds.chance_at(d, dv, caps, _path[j],
						lead + (j + 1) * Duel.DT, set_s, reach))
		reads.append("%.4f" % (1.0 - best_chance))
	# The windup: the shot read's release contest, and the one-chance read on the
	# puck held at the release point through it by a man already playing him.
	var release_pt: Vector3 = AIPuckLane.release_point_toward(o, r)
	var release_clean: float = AIPuckLane.release_contest_clean(release_pt, defs, cap_list)
	var windup_keep: float = 1.0 - AIStripOdds.SET_STRIP * AIStripOdds.chance_at(d, dv, caps,
			release_pt, AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S)
	var head: String = "%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s,%.3f,%d,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f,%s,%d,%s,%.2f,%.4f,%.4f" % [
			st["kind"], o.x, o.z, r.x, r.z, launch.x, launch.y, launch.z, d.x, d.z, dv.x, dv.z,
			outcome, t_out, kept, lane_flat, lane_saucer, rim_lane, keep, best, first,
			_path.size() * Duel.DT, first_touch, blocks, touch_kind, touch_closing, release_clean,
			windup_keep]
	return head + "," + ",".join(reads)


# One tick of the interceptor: to the earliest point of the line he aims at that
# his stick reaches _set_s first, cursor through the puck once it is in play.
func _intercept(s: Object, duel: Object, caps: AISkaterCaps) -> void:
	var input: InputState = s.input
	input.shoot_pressed = false
	input.shoot_held = false
	input.slap_pressed = false
	input.slap_held = false
	input.hit_held = false
	input.stance_held = false
	input.stick_check_held = false
	input.stick_check_pressed = false
	input.stick_lift_held = false
	input.stick_lift_pressed = false
	input.quick_pass_pressed = false
	input.block_held = false
	input.bot_shuffle = false
	var now: int = duel.ticks
	_aim.resize(now + int(WATCH_S / Duel.DT))
	_aim_air.resize(_aim.size())
	_aim_air.fill(false)
	var c: int = duel.carrier()
	var start: int = now
	if c == RECEIVER:
		# Run the receiver down: the line his momentum takes him on.
		var r: Object = duel._skater(RECEIVER)
		for j: int in range(now, _aim.size()):
			var t: float = (j + 1 - now) * Duel.DT
			var p := GameRules.clamp_to_rink_inner(Vector2(r.pos.x + r.vel.x * t,
					r.pos.z + r.vel.z * t))
			_aim[j] = Vector3(p.x, 0.0, p.y)
	else:
		# The puck's own path, from the release on.
		start = maxi(now, _preroll)
		_aim.resize(_preroll + _path.size())
		_aim_air.resize(_aim.size())
		for j: int in range(_preroll, _aim.size()):
			_aim[j] = _path[j - _preroll]
			_aim_air[j] = _air[j - _preroll]
	var target: Vector3 = _intercept_point(s, now, start, caps)
	var to := Vector3(target.x - s.pos.x, 0.0, target.z - s.pos.z)
	var dist: float = to.length()
	var speed: float = Vector2(s.vel.x, s.vel.z).length()
	var stopping: float = speed * speed / (2.0 * GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2)
	input.brake = dist < stopping + ARRIVE_M and speed > 1.0
	input.move_vector = Vector2.ZERO if input.brake or dist < ARRIVE_M \
			else Vector2(to.x, to.z) / dist
	var puck: Vector3 = duel.puck_pos
	var to_puck := Vector3(puck.x - s.pos.x, 0.0, puck.z - s.pos.z)
	if to_puck.length() < PLAY_M:
		input.mouse_world_pos = puck + to_puck.normalized() * JAB_THROUGH_M
	elif dist > 0.01:
		input.mouse_world_pos = s.pos + to / dist * PLAY_M
	else:
		input.mouse_world_pos = puck


func _intercept_point(s: Object, now: int, start: int, caps: AISkaterCaps) -> Vector3:
	var reach: float = caps.max_blade_reach if caps != null \
			else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
	var best := Vector3.INF
	var best_spare: float = -INF
	for j: int in range(start, _aim.size(), PLAN_STEP_TICKS):
		if _aim_air[j]:
			continue
		var p: Vector3 = _aim[j]
		var to := Vector3(p.x - s.pos.x, 0.0, p.z - s.pos.z)
		var d: float = to.length()
		var spot: Vector3 = s.pos if d <= reach else s.pos + to * ((d - reach) / d)
		var spare: float = (j + 1 - now) * Duel.DT \
				- AIArrival.time_to_arrive_caps(s.pos, spot, s.vel, caps)
		if spare >= _set_s:
			return spot
		if spare > best_spare:
			best_spare = spare
			best = spot
	return best if best.is_finite() else s.pos


func _stick_arrival(pos: Vector3, vel: Vector3, point: Vector3, caps: AISkaterCaps) -> float:
	var reach: float = caps.max_blade_reach if caps != null \
			else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
	var to := Vector3(point.x - pos.x, 0.0, point.z - pos.z)
	var d: float = to.length()
	if d <= reach:
		return 0.0
	return AIArrival.time_to_arrive_caps(pos, pos + to * ((d - reach) / d), vel, caps)

extends GutTest

# Five Hard bots set up in their zone against five Hard defenders in zone
# coverage, on the duel harness, against the real keeper: how a 5v5 possession
# that starts low in the zone ends (a shot, a turnover, the puck out), how long
# it lasts, how often the puck moves, and — at every shot — what the carrier
# priced the shot at against the best pass he saw, beside what the shot field's
# set read says the keeper concedes from there. test_ozone_possession.gd's 3v3
# sweep, in 5v5, with the compete's two sides logged.
# Team 0 attacks -Z. Not modelled: offside, rebounds (a possession ends at its
# first shot), board pins (the harness's).
#
# The 48 base runs are 24 starts and their mirrors, too few to tell a few shots
# from noise. MITTS_OZ_JITTER=J adds J copies of each with every spawn nudged
# up to JITTER_M, from a seed per run, so a comparison is repeatable;
# MITTS_OZ_SHARD=i MITTS_OZ_SHARDS=n runs every n-th of them from i. Every run
# prints an OZRUN line (index | end | shot kind | the shot's set read | passes |
# seconds) for merging shards, and the summary gives each rate with its
# standard error. MITTS_OZ_TRACE=1 also prints, every TRACE_EVERY_TICKS while
# one of ours carries in the zone, an OZTRC line: the carrier's compete (its
# intent, shot, best pass and its receiver's slot, carry) and every receiver's
# feed as the pass search priced it (slot:EV:lane:worth:gate, the pass
# search's trace).
#
# MITTS_OZ_REBOUND=1 plays on past the first shot (docs/bot-net-front-offense-
# plan.md, step 2d). The duel has no keeper to save it, so the save is drawn
# from the measured rebound field (AIReboundField): one of the nearest spot's
# shots, by a seed per run. A covered shot or a goal ends the run; a missed one
# plays on; a live rebound flies the shot to the save point and leaves it as
# the save did, and REBOUND_WINDOW_S is watched: who touches it first, and
# whether we get a second shot (with whether the measured keeper was still down
# then). Its OZRUN line gains those fields.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const SECS: float = 12.0
const DOTS_OUT_M: float = 6.1
const SLOT_NEAR_M: float = 1.5
const SLOT_FAR_M: float = 10.0
const SLOT_HALF_WIDTH_M: float = 4.5
const POINT_OUT_M: float = 15.0
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const KEEPER_SETTLE_S: float = 1.5
const JITTER_M: float = 1.0
const TRACE_EVERY_TICKS: int = 9
const REBOUND_WINDOW_S: float = 3.0
# A jittered spawn behind the goal line keeps this far outside the post.
const JITTER_NET_CLEAR_M: float = GameRules.NET_HALF_WIDTH + 0.6
const OURS: Array[int] = [101, 102, 103, 104, 105]
const THEIRS: Array[int] = [201, 202, 203, 204, 205]

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController
# The keeper as the bots read him: his whole replicated state (stance, facing,
# velocity), or only his position as the harness's default keeper.
var _keeper_state: GoalieNetworkState = GoalieNetworkState.new()
var _full_keeper: bool = true
# The run being swept (its OZRUN index), and whether it is traced.
var _run_index: int = 0
var _trace: bool = false
var _rebounds: bool = false


func before_all() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child(n)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_ctrl.setup(_goalie, _puck, GOAL_Z, true)


func after_all() -> void:
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		n.queue_free()


static func _out(p: Vector3) -> float:
	return p.z + GameRules.GOAL_LINE_Z


static func _in_slot(p: Vector3) -> bool:
	var out: float = _out(p)
	return out >= SLOT_NEAR_M and out <= SLOT_FAR_M and absf(p.x) <= SLOT_HALF_WIDTH_M


static func _shot_kind(p: Vector3) -> String:
	if _in_slot(p):
		return "slot"
	if _out(p) >= POINT_OUT_M:
		return "point"
	if _out(p) < DOTS_OUT_M and absf(p.x) > SLOT_HALF_WIDTH_M:
		return "angle"
	return "other"


static func _is_shot(rec: Dictionary) -> bool:
	return rec.get("decision", "") in ["SHOOT", "ONE_TIMER"]


# One possession: { end, t, low_s, passes, shots: [shot records] }. A shot
# record: its kind, release spot, the carrier's priced shot, best pass (and the
# receiver's spot), carry, and the set read at the release.
func _run(duel: Object) -> Dictionary:
	var r: Dictionary = {"end": "timeout", "t": SECS, "low_s": 0.0, "passes": 0, "shot": {},
			"pass_log": [], "battle_s": 0.0, "screen": 0.0}
	var passing: bool = false
	var last_pass: Dictionary = {}
	var last_pass_t: float = 0.0
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	for i: int in int(SECS / Duel.DT):
		var before: int = duel.releases.size()
		duel.step()
		var t: float = (i + 1) * Duel.DT
		var released: Dictionary = {}
		if duel.releases.size() > before and int(duel.releases[-1]["team"]) == 0:
			released = duel.releases[-1]
		var c: int = duel.carrier()
		var ours: bool = c != -1 and duel.team_map[c] == 0
		if ours:
			passing = false
		if ours and _out(duel.puck_pos) <= DOTS_OUT_M:
			r["low_s"] += Duel.DT
		if _trace and ours and i % TRACE_EVERY_TICKS == 0:
			_print_trace(duel, c, t)
		r["battle_s"] += Duel.DT * _battling(duel)
		_count_screen(duel, r)
		if not released.is_empty():
			if _is_shot(released):
				var at: Vector3 = released["pos"]
				var s: Dictionary = {"kind": _shot_kind(at), "pos": at,
						"decision": released["decision"],
						"set": AIShotValue.set_keeper(at, goal),
						"pass": float(released.get("pass_score", 0.0)),
						"carry": float(released.get("carry_score", 0.0)),
						"shot": 0.0, "pass_to": Vector3.INF}
				var agent: SkaterAgentStateMachine = null
				for sk: Object in duel.skaters:
					if sk.peer_id == int(released["peer"]):
						agent = sk.agent
				var puck: Vector3 = released.get("pass_puck", at)
				var keeper: Vector3 = _goalie.global_position
				keeper.y = 0.0
				s["puck"] = puck
				s["keeper"] = keeper
				s["keeper_vx"] = _keeper_state.velocity_x
				s["stance"] = AIShotOdds.stance_of(_keeper_state, goal)
				s["live"] = AIShotValue.now(puck, goal, keeper, _keeper_state.velocity_x,
						s["stance"], _keeper_state.rotation_y, AIShotOdds.History.CARRIED)
				s["set_puck"] = AIShotValue.set_keeper(puck, goal)
				var mates: String = ""
				for pid: int in OURS:
					if pid == int(released["peer"]):
						continue
					var mp: Vector3 = duel.skater_pos(pid)
					if _out(mp) > POINT_OUT_M:
						continue
					mates += " (%4.1f,%4.1f) feed %.2f set %.2f" % [mp.x, _out(mp),
							AIShotValue.feed(puck, mp, 16.0, goal, keeper, true),
							AIShotValue.set_keeper(mp, goal)]
				s["mates"] = mates
				if agent != null and agent._carrier != null:
					s["shot"] = agent._carrier.debug_shoot_score
					s["history"] = agent._carrier._shot_history()
					var pp: int = int(released.get("pass_peer", 0))
					if pp > 0:
						s["pass_to"] = duel.skater_pos(pp)
				r["end"] = "shot"
				r["t"] = t
				r["shot"] = s
				r["screen"] = _screen_on(duel, int(released["peer"]), at, goal, keeper)
				if _rebounds:
					r["rebound"] = _play_rebound(duel, released)
				return r
			r["passes"] += 1
			passing = true
			var kept: float = float(released.get("pass_kept", -1.0))
			var ev: float = float(released.get("pass_score", 0.0))
			var from_p: Vector3 = released.get("pass_puck", released["pos"])
			var to_p: Vector3 = released.get("pass_spot", Vector3.INF)
			r["pass_log"].append([ev, kept, float(released.get("carry_score", 0.0)),
					AIPossessionFloor.continuation(from_p, goal), from_p, to_p, "made"])
			last_pass = released
			last_pass_t = t
		if c != -1 and duel.team_map[c] == 1:
			r["end"] = "picked" if passing else "stripped"
			r["t"] = t
			if passing and not r["pass_log"].is_empty():
				r["pass_log"][-1][6] = "PICKED %.2f s on" % (t - last_pass_t)
			if passing and not last_pass.is_empty():
				var from: Vector3 = last_pass.get("pass_puck", last_pass["pos"])
				var to: Vector3 = last_pass.get("pass_spot", Vector3.INF)
				var who: Vector3 = duel.skater_pos(c)
				var off: float = -1.0
				if to.is_finite():
					var d: Vector3 = (to - from)
					d.y = 0.0
					d = d.normalized()
					off = absf((who.x - from.x) * d.z - (who.z - from.z) * d.x)
				r["pick"] = "priced lane %.2f kept %.2f (clean %.2f miss %.2f catch %.2f) | %s -> %s | picked %.2f s after by a man %.1f m off its line, at (%.1f, %.1f out)" % [
						float(last_pass.get("pass_lane", -1.0)), float(last_pass.get("pass_kept", -1.0)),
						float(last_pass.get("pass_release_clean", -1.0)),
						float(last_pass.get("pass_miss", -1.0)),
						float(last_pass.get("pass_reception", -1.0)),
						"(%.1f, %.1f out)" % [from.x, _out(from)],
						"(%.1f, %.1f out)" % [to.x, _out(to)] if to.is_finite() else "?",
						t - last_pass_t, off, who.x, _out(who)]
			return r
		if duel.puck_pos.z > -GameRules.BLUE_LINE_Z:
			r["end"] = "out-ours" if passing else ("out-carried" if ours else "cleared")
			r["t"] = t
			return r
	return r


# The save and what follows it (MITTS_OZ_REBOUND). `released` is our shot,
# launched this tick.
func _play_rebound(duel: Object, released: Dictionary) -> Dictionary:
	var res: Dictionary = {"outcome": "-", "first": "none", "t_first": -1.0, "second": false,
			"t_second": -1.0, "second_kind": "-", "down": false, "tipped": false,
			"second_xg": 0.0, "first_slot": "-"}
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var spot: int = AIReboundField.spot_of(released["pos"], goal)
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * _run_index + 7
	var row: int = AIReboundField.shot(spot,
			rng.randi_range(0, AIReboundField.shot_count(spot) - 1))
	var o: int = AIReboundField.outcome(row)
	res["outcome"] = "GWCSR"[o]
	if o == AIReboundField.Outcome.GOAL or o == AIReboundField.Outcome.COVERED \
			or o == AIReboundField.Outcome.REBOUND_GOAL:
		return res
	var shooter: int = int(released["peer"])
	if o == AIReboundField.Outcome.LIVE:
		var hit: Vector3 = AIReboundField.sample_pos(row, 0, goal)
		var from := Vector3(duel.puck_pos.x, 0.0, duel.puck_pos.z)
		var speed: float = maxf(Vector2(duel.puck_vel.x, duel.puck_vel.z).length(), 1.0)
		var dir: Vector3 = (hit - from).normalized()
		for k: int in ceili(from.distance_to(hit) / speed / Duel.DT):
			duel.step()
			if duel.carrier() != -1 or duel.loose_released_by != shooter:
				res["tipped"] = true
				break
			duel.puck_pos = from + dir * speed * (k + 1) * Duel.DT
			duel.puck_vel = dir * speed
		if not res["tipped"]:
			duel.puck_pos = hit
			duel.puck_vel = AIReboundField.sample_vel(row, 0, goal)
			duel.loose_released_by = -1
			duel.airborne_ticks = 0
	for k: int in int(REBOUND_WINDOW_S / Duel.DT):
		var before: int = duel.releases.size()
		duel.step()
		var tt: float = (k + 1) * Duel.DT
		var c: int = duel.carrier()
		if res["first"] == "none" and c != -1:
			res["first"] = "ours" if duel.team_map[c] == 0 else "theirs"
			res["t_first"] = tt
			var b: TeamBrain = duel.brains[duel.team_map[c]]
			res["first_slot"] = AIRoleSlots.label(b.slot_assignments.get(c, 0))
		if duel.releases.size() > before and int(duel.releases[-1]["team"]) == 0 \
				and _is_shot(duel.releases[-1]):
			res["second"] = true
			res["t_second"] = tt
			res["second_kind"] = _shot_kind(duel.releases[-1]["pos"])
			var ks: int = roundi(tt / AIReboundField.SAMPLE_S)
			res["down"] = o == AIReboundField.Outcome.LIVE and not res["tipped"] \
					and ks < AIReboundField.sample_count(row) \
					and AIReboundField.keeper_down(row, ks)
			# What the field measured a second shot to score at that moment: at
			# its contest, or once past halfway to it, its late sample (0: no
			# measured chance, a tipped or missed shot).
			var k0: int = AIReboundField.contest_sample(row)
			var kl: int = AIReboundField.late_sample(row)
			if res["down"] or (o == AIReboundField.Outcome.LIVE and not res["tipped"] and k0 >= 0):
				res["second_xg"] = AIReboundField.late_scored(row) \
						if kl >= 0 and 2 * ks > k0 + kl else AIReboundField.contest_scored(row)
			break
		if res["first"] == "theirs" or duel.puck_pos.z > -GameRules.BLUE_LINE_Z:
			break
	return res


# How many of ours fight for a screen spot this tick: Ctrl held with the spot
# their role holds, in contact with a man of theirs.
func _battling(duel: Object) -> int:
	var n: int = 0
	for sk: Object in duel.skaters:
		if sk.team_id != 0 or sk.agent == null or not sk.input.hit_held:
			continue
		var dec: RoleDecision = sk.agent._cached_role_decision
		if dec != null and dec.screen_spot.is_finite():
			n += 1
	return n


# Where the battle chain stops: ticks one of ours holds a published screen
# spot, a man of theirs within STEP_IN_M is nearer it, and our Ctrl is down.
func _count_screen(duel: Object, r: Dictionary) -> void:
	for sk: Object in duel.skaters:
		if sk.team_id != 0 or sk.agent == null:
			continue
		var dec: RoleDecision = sk.agent._cached_role_decision
		if dec == null or not dec.screen_spot.is_finite():
			continue
		r["pub_s"] = r.get("pub_s", 0.0) + Duel.DT
		var mine: float = Vector2(dec.screen_spot.x - sk.pos.x, dec.screen_spot.z - sk.pos.z).length()
		r["mine_m"] = r.get("mine_m", 0.0) + Duel.DT * mine
		for o: Object in duel.skaters:
			if o.team_id == 0:
				continue
			var theirs: float = Vector2(dec.screen_spot.x - o.pos.x, dec.screen_spot.z - o.pos.z).length()
			if theirs < mine and AIPressRead.gap_m(sk.pos, o.pos) <= AIPressRead.STEP_IN_M:
				r["contest_s"] = r.get("contest_s", 0.0) + Duel.DT
				break


# The screen every other body gives a release at `at` (AIScreenField.best_uplift,
# the keeper's own sightline test).
func _screen_on(duel: Object, shooter: int, at: Vector3, goal: Vector3, keeper: Vector3) -> float:
	var bodies: Array[Vector3] = []
	for sk: Object in duel.skaters:
		if sk.peer_id != shooter:
			bodies.append(sk.pos)
	return AIScreenField.best_uplift(at, goal, keeper, bodies, GoalieScreenRules.ScreenConfig.new())


func _print_trace(duel: Object, c: int, t: float) -> void:
	var agent: SkaterAgentStateMachine = null
	for sk: Object in duel.skaters:
		if sk.peer_id == c:
			agent = sk.agent
	if agent == null or agent._carrier == null:
		return
	var car: AIRoleCarrier = agent._carrier
	var brain: TeamBrain = duel.brains[0]
	var trace: AICarrierPassTrace = car._pass.trace
	var recv: PackedStringArray = []
	for k: int in trace.peer.size():
		recv.append("%s:%.4f:%.3f:%.4f:%d" % [
				AIRoleSlots.label(brain.slot_assignments.get(trace.peer[k], 0)),
				trace.ev[k], trace.lane[k], trace.worth[k], trace.gate[k]])
	var cp: Vector3 = duel.skater_pos(c)
	gut.p("OZTRC|%d|%.2f|%d|%.4f|%.4f|%s|%.4f|%.1f|%.1f|%s" % [_run_index, t,
			car.intended_action, car.debug_shoot_score, car.debug_pass_score,
			AIRoleSlots.label(brain.slot_assignments.get(car.debug_pass_peer_id, 0))
					if car.debug_pass_peer_id > 0 else "-",
			car.debug_carry_score, cp.x, _out(cp), ";".join(recv)])


# Our carrier low (`carrier`, skating at `vel`), two forwards at `fa` and `fb`,
# both D on the points; their five in zone coverage, tight (the strong D already
# on the carrier) or home.
func _setup(carrier: Vector3, vel: Vector3, fa: Vector3, fb: Vector3, tight: bool,
		rng: RandomNumberGenerator = null) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 5
	for k: int in 5:
		duel.positions[OURS[k]] = k
		duel.positions[THEIRS[k]] = k
	var side: float = signf(carrier.x) if absf(carrier.x) > 0.5 else 1.0
	var point_z: float = -(GameRules.BLUE_LINE_Z + 2.0)
	var hard: BotSkillProfile = BotSkillProfile.hard()
	carrier = _jit(carrier, rng)
	duel.add_skater(OURS[0], 0, carrier, hard, vel)
	duel.add_skater(OURS[1], 0, _jit(fa, rng), hard)
	duel.add_skater(OURS[2], 0, _jit(fb, rng), hard)
	duel.add_skater(OURS[3], 0, _jit(Vector3(side * 6.5, 0, point_z), rng), hard)
	duel.add_skater(OURS[4], 0, _jit(Vector3(-side * 6.0, 0, point_z), rng), hard)
	# Their F1-F3 then their D pair.
	var strong_d := Vector3(side * 5.5, 0, -21.5)
	if tight:
		strong_d = carrier + (Vector3(0, 0, -21.0) - carrier).normalized() * 2.0
	duel.add_skater(THEIRS[0], 1, _jit(Vector3(side * 1.5, 0, -19.5), rng), hard)
	duel.add_skater(THEIRS[1], 1, _jit(Vector3(side * 7.0, 0, -12.5), rng), hard)
	duel.add_skater(THEIRS[2], 1, _jit(Vector3(-side * 5.0, 0, -13.5), rng), hard)
	duel.add_skater(THEIRS[3], 1, _jit(strong_d, rng), hard)
	duel.add_skater(THEIRS[4], 1, _jit(Vector3(-side * 1.0, 0, -24.0), rng), hard)
	duel.start(OURS[0])
	if _trace:
		for sk: Object in duel.skaters:
			if sk.team_id == 0:
				sk.agent._carrier._pass.trace = AICarrierPassTrace.new()
	_ctrl.reset_to_crease()
	_shooter.global_position = carrier
	_puck.set_carrier(_shooter)
	_puck.global_position = carrier
	for _i: int in int(KEEPER_SETTLE_S / Duel.DT):
		_ctrl._physics_process(Duel.DT)
	duel.goalie_provider = func(team_id: int, puck_pos: Vector3) -> Variant:
		if team_id != 1:
			return null
		_shooter.global_position = puck_pos
		_puck.global_position = puck_pos
		_ctrl._physics_process(Duel.DT)
		_keeper_state = GoalieNetworkState.new()
		_ctrl.fill_state(_keeper_state)
		return _keeper_state if _full_keeper else _goalie.global_position
	return duel


# `p` nudged up to JITTER_M in a random direction (as given with no `rng`),
# kept outside the post behind the goal line.
static func _jit(p: Vector3, rng: RandomNumberGenerator) -> Vector3:
	if rng == null:
		return p
	var a: float = rng.randf() * TAU
	var r: float = JITTER_M * sqrt(rng.randf())
	var q := Vector3(p.x + r * cos(a), 0.0, p.z + r * sin(a))
	if absf(q.z) > GameRules.GOAL_LINE_Z and absf(q.x) < JITTER_NET_CLEAR_M:
		q.x = signf(q.x if q.x != 0.0 else 1.0) * JITTER_NET_CLEAR_M
	return q


static func _env_int(key: String, fallback: int) -> int:
	var v: String = OS.get_environment(key)
	return int(v) if v.is_valid_int() else fallback


# Starts (carrier, forward a, forward b, carrier velocities), each run as given
# and mirrored, standing and skating each way, the defence tight and home: the
# half-wall low, the corner, behind the net, below the circle off the wall.
func _starts() -> Array:
	return [
		[Vector3(-11.0, 0, -20.0), Vector3(0.5, 0, -23.0), Vector3(5.5, 0, -19.0),
				[Vector3(0, 0, -4.0), Vector3(0, 0, 4.0)]],
		[Vector3(-10.0, 0, -24.5), Vector3(-1.0, 0, -22.5), Vector3(1.0, 0, -15.0),
				[Vector3(0, 0, 4.0), Vector3(4.0, 0, -2.0)]],
		[Vector3(-1.5, 0, -28.3), Vector3(3.5, 0, -24.0), Vector3(-2.0, 0, -18.0),
				[Vector3(-4.0, 0, 0), Vector3(-2.0, 0, 3.5)]],
		[Vector3(-8.0, 0, -22.0), Vector3(4.0, 0, -24.5), Vector3(1.0, 0, -14.5),
				[Vector3(4.0, 0, 1.0), Vector3(-4.0, 0, 1.0)]],
	]


func _sweep(label: String) -> void:
	var ends: Dictionary = {}
	var kinds: Dictionary = {}
	var low_s: float = 0.0
	var t_all: float = 0.0
	var t_shot: float = 0.0
	var passes: int = 0
	var runs: int = 0
	var shots: Array[Dictionary] = []
	var picks: Array[String] = []
	var pass_log: Array = []
	var row: String = "   "
	var jitter: int = _env_int("MITTS_OZ_JITTER", 0)
	var shards: int = maxi(_env_int("MITTS_OZ_SHARDS", 1), 1)
	var shard: int = _env_int("MITTS_OZ_SHARD", 0)
	_trace = _env_int("MITTS_OZ_TRACE", 0) == 1
	_rebounds = _env_int("MITTS_OZ_REBOUND", 0) == 1
	var set_sum: float = 0.0
	var set_sq: float = 0.0
	var g: int = -1
	for start: Array in _starts():
		var vels: Array = [Vector3.ZERO] + start[3]
		for combo: int in 2 * vels.size() * 2 * (jitter + 1):
			g += 1
			if g % shards != shard:
				continue
			var copy: int = combo / (2 * vels.size() * 2)
			var base: int = combo % (2 * vels.size() * 2)
			var m := Vector3(1.0 if base % 2 == 0 else -1.0, 1.0, 1.0)
			var vel: Vector3 = vels[(base >> 1) % vels.size()] * m
			var tight: bool = base >= 2 * vels.size()
			var rng: RandomNumberGenerator = null
			if copy > 0:
				rng = RandomNumberGenerator.new()
				rng.seed = 7919 * g + 17
			_run_index = g
			var r: Dictionary = _run(_setup(start[0] * m, vel, start[1] * m, start[2] * m,
					tight, rng))
			runs += 1
			var shot_set: float = float(r["shot"]["set"]) if r["end"] == "shot" else 0.0
			set_sum += shot_set
			set_sq += shot_set * shot_set
			var reb: String = ""
			if r.has("rebound"):
				var rb: Dictionary = r["rebound"]
				reb = "|%s|%s|%.2f|%d|%.2f|%s|%d|%d|%.4f|%s" % [rb["outcome"], rb["first"],
						rb["t_first"], int(rb["second"]), rb["t_second"], rb["second_kind"],
						int(rb["down"]), int(rb["tipped"]), rb["second_xg"], rb["first_slot"]]
			gut.p("OZSCREEN|%d|%.2f|%.2f|%.2f" % [g, r.get("pub_s", 0.0), r.get("contest_s", 0.0),
					r.get("mine_m", 0.0) / maxf(r.get("pub_s", 0.0), 0.001)])
			gut.p("OZRUN|%d|%s|%s|%.4f|%d|%.2f%s|%.2f|%.3f" % [g, r["end"],
					r["shot"]["kind"] if r["end"] == "shot" else "-", shot_set,
					r["passes"], r["t"], reb, r["battle_s"], r["screen"]])
			row += " %s@%.1f/p%d" % [str(r["end"]).left(4), r["t"], r["passes"]]
			ends[r["end"]] = int(ends.get(r["end"], 0)) + 1
			passes += r["passes"]
			low_s += r["low_s"]
			t_all += r["t"]
			if r.has("pick"):
				picks.append(r["pick"])
			pass_log.append_array(r["pass_log"])
			if r["end"] == "shot":
				var s: Dictionary = r["shot"]
				shots.append(s)
				kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
				t_shot += r["t"]
	gut.p(row)
	gut.p("%s | ends %s | shots %s, mean %.1f s in | possession %.1f s | passes %d over %d runs | below the dots %.1f s" % [
			label, str(ends), str(kinds), t_shot / maxf(shots.size(), 1), t_all / runs,
			passes, runs, low_s / runs])
	var n: float = maxf(runs, 1)
	var set_mean: float = set_sum / n
	gut.p("    per possession: shot %s | slot shot %s | set read of its shot %.4f ± %.4f" % [
			_rate(shots.size(), n), _rate(int(kinds.get("slot", 0)), n), set_mean,
			sqrt(maxf(set_sq / n - set_mean * set_mean, 0.0) / n)])
	gut.p("    shot (x, out)      kind   priced   set    pass  carry  pass-to (x, out)")
	var over: float = 0.0
	var pass_near: int = 0
	for s: Dictionary in shots:
		var p: Vector3 = s["pos"]
		var to: Vector3 = s["pass_to"]
		over += float(s["shot"]) - float(s["set"])
		if float(s["pass"]) >= 0.5 * float(s["shot"]) and float(s["pass"]) > 0.0:
			pass_near += 1
		gut.p("    (%5.1f, %4.1f)   %-6s %6.3f  %6.3f  %6.3f %6.3f  %s" % [p.x, _out(p), s["kind"],
				s["shot"], s["set"], s["pass"], s["carry"],
				"(%5.1f, %4.1f)" % [to.x, _out(to)] if to.is_finite() else "-"])
		var pk: Vector3 = s["puck"]
		var kp: Vector3 = s["keeper"]
		gut.p("        puck (%5.1f, %4.1f) live %.3f set %.3f hist %d | keeper (%5.2f, %4.2f) vx %5.2f st %d |%s" % [
				pk.x, _out(pk), s["live"], s["set_puck"], int(s.get("history", -1)),
				kp.x, _out(kp), s["keeper_vx"], s["stance"], s["mates"]])
	gut.p("    mean priced - set: %+.3f over %d shots; a pass within half the shot's price on %d" % [
			over / maxf(shots.size(), 1), shots.size(), pass_near])
	gut.p("    every pass: EV | completion | its receiver's worth (EV / completion) | the carry | the continuation where he stood | from -> to | then")
	for e: Array in pass_log:
		var f: Vector3 = e[4]
		var to: Vector3 = e[5]
		gut.p("        %.3f | %.2f | %.3f | %.3f | %.3f | (%5.1f, %4.1f out) -> %s | %s" % [e[0], e[1],
				e[0] / e[1] if e[1] > 0.01 else -1.0, e[2], e[3], f.x, _out(f),
				"(%5.1f, %4.1f out)" % [to.x, _out(to)] if to.is_finite() else "?", e[6]])
	gut.p("    passes picked off:")
	for line: String in picks:
		gut.p("        " + line)


# `k` of `n` as a share with its binomial standard error.
static func _rate(k: int, n: float) -> String:
	var p: float = k / n
	return "%.3f ± %.3f" % [p, sqrt(p * (1.0 - p) / n)]


func test_ozone_possession_5v5() -> void:
	_sweep("5v5 hard  ")
	assert_true(true)

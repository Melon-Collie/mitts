extends "res://tests/instruments/ai/test_defender_race_truth.gd"

# The race truth instrument's scripted carrier paths against a worst-case
# interceptor instead of a defending bot (docs/strip-interception-plan.md): a
# real body — the harness's movement, arm and poke rules — whose input is
# replaced every tick. He knows the carrier's path (a dry run of it alone), skates
# flat out to the earliest point of it his stick reaches SET_S before the puck
# does (else the point he has most time to spare at), faces it, and jabs his
# blade through the puck once it is in reach. What a defender can do, not what
# ours choose to. MITTS_RACE_SAVE writes the runs in the race truth format, and
# beside it (<path>.planned) each run's planned puck path — the dry run's, every
# sample, whether or not the puck was lost on it; MITTS_RACE_LIMIT caps the
# stagings and MITTS_INTERCEPT_ONLY (comma-separated) keeps only those families.
# Reports only.

# The spare time he aims to arrive with: a reaction's worth to set his blade
# (MITTS_INTERCEPT_SET_S overrides it).
const SET_S: float = 0.25
# How far ahead his plan reads the path, and how finely.
const PLAN_STEP_TICKS: int = 6
# Inside this of the puck he plays it: the cursor goes through it.
const PLAY_M: float = 3.0
const JAB_THROUGH_M: float = 0.6
const ARRIVE_M: float = 0.3
const INTERCEPT_FAMILIES: Array[String] = ["straight_lane", "straight_side", "chased", "cut",
		"stand", "pair", "far_side", "behind", "run_down"]

# The carrier's body every tick of a dry run of his path alone, index i after
# step i + 1.
var _schedule: Array[Vector3] = []
var _set_s: float = SET_S
# The dry run's puck every sample (the planned path), and one per recorded run.
var _planned_now: Array[Vector3] = []
var _planned: Array = []


func test_defender_race_truth() -> void:
	pass


func test_interceptor_truth() -> void:
	_rng.seed = 20261028
	if OS.has_environment("MITTS_INTERCEPT_SET_S"):
		_set_s = float(OS.get_environment("MITTS_INTERCEPT_SET_S"))
	var only: PackedStringArray = OS.get_environment("MITTS_INTERCEPT_ONLY").split(",", false)
	var stagings: Array[Dictionary] = []
	for st: Dictionary in _stagings():
		if st["family"] in INTERCEPT_FAMILIES and (only.is_empty() or st["family"] in only):
			stagings.append(st)
	var limit: int = int(OS.get_environment("MITTS_RACE_LIMIT")) \
			if OS.has_environment("MITTS_RACE_LIMIT") else stagings.size()
	var stride: int = maxi(1, stagings.size() / maxi(limit, 1))
	var t0: int = Time.get_ticks_msec()
	for i: int in range(0, stagings.size(), stride):
		for _r: int in REPEATS:
			_run(stagings[i])
	gut.p("%d runs in %.0f s" % [_family.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	if OS.has_environment("MITTS_RACE_SAVE"):
		_save(OS.get_environment("MITTS_RACE_SAVE"))
		_save_planned(OS.get_environment("MITTS_RACE_SAVE") + ".planned")
	for fam: String in INTERCEPT_FAMILIES:
		var rows: Array[int] = _rows(fam)
		if rows.is_empty():
			continue
		var lost: int = 0
		var kinds: Dictionary = {}
		var t_sum: float = 0.0
		for r: int in rows:
			if _event_t[r] >= 0.0:
				lost += 1
				t_sum += _event_t[r]
				kinds[_event_kind[r]] = int(kinds.get(_event_kind[r], 0)) + 1
		gut.p("  %-13s lost %3d of %3d, mean at %.2f s %s" % [fam, lost, rows.size(),
				t_sum / maxf(lost, 1.0), str(kinds)])
	assert_true(true)


# The race truth's stagings, and two more that start the interceptor where he can
# barely reach the path or cannot: far off its side, and behind the carrier.
func _stagings() -> Array[Dictionary]:
	var out: Array[Dictionary] = super()
	for z0: float in START_ZS:
		var c := Vector3(START_X, 0, z0)
		var straight: Array[Vector3] = [c, Vector3(START_X, 0, PATH_END_Z)]
		for v0: float in [4.0, 7.5]:
			var cv := Vector3(0, 0, -v0)
			for lat: float in [8.0, 11.0]:
				for d: float in [-6.0, -2.0, 2.0, 6.0, 10.0, 15.0]:
					for dv: Vector3 in [Vector3.ZERO, Vector3(0, 0, -3.0), Vector3(0, 0, 3.0)]:
						out.append(_staging("far_side", c, cv, straight, [c + Vector3(lat, 0, -d)],
								[dv]))
			for d: float in [4.0, 6.0, 9.0]:
				for lat: float in [0.0, 3.0]:
					for dv: Vector3 in [Vector3.ZERO, Vector3(0, 0, -3.0)]:
						out.append(_staging("behind", c, cv, straight, [c + Vector3(lat, 0, d)],
								[dv]))
	return out


func _add_carrier(duel: Object, pos: Vector3, vel: Vector3, path: Array[Vector3]) -> void:
	super(duel, pos, vel, path)
	var dry: Object = Duel.new()
	super(dry, pos, vel, path)
	dry.start(CARRIER)
	_schedule.clear()
	_planned_now.clear()
	for i: int in int((HORIZON_S + 0.5) / Duel.DT):
		dry.step()
		_schedule.append(dry._skater(CARRIER).pos)
		if (i + 1) % SAMPLE_TICKS == 0 and (i + 1) * Duel.DT <= HORIZON_S + 1e-6:
			_planned_now.append(dry.puck_pos)


func _run(st: Dictionary) -> void:
	var before: int = _family.size()
	super(st)
	if _family.size() > before:
		_planned.append(_planned_now.duplicate())


# One line per recorded run: the planned puck's x z every sample.
func _save_planned(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for pts: Array in _planned:
		var line := PackedStringArray()
		for p: Vector3 in pts:
			line.append_array([str(p.x), str(p.z)])
		f.store_line(" ".join(line))


func _add_defender(duel: Object, peer_id: int, pos: Vector3, vel: Vector3) -> void:
	duel.add_skater(peer_id, 1, pos, null, vel)
	var caps: AISkaterCaps = duel.caps_by_peer.get(peer_id)
	duel._skater(peer_id).input_override = func(s: Object) -> void: _intercept(s, duel, caps)


# One tick of the interceptor's input.
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
	var target: Vector3 = _intercept_point(s, duel.ticks, caps)
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


# Where his stick meets the carrier's path: the earliest point he reaches _set_s
# before the carrier, else the one he has the most time to spare at — the body
# spot a blade's reach short of the carrier's, on his side.
func _intercept_point(s: Object, now_tick: int, caps: AISkaterCaps) -> Vector3:
	var reach: float = caps.max_blade_reach if caps != null else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
	var best := Vector3.INF
	var best_spare: float = -INF
	for j: int in range(now_tick, _schedule.size(), PLAN_STEP_TICKS):
		var p: Vector3 = _schedule[j]
		var to := Vector3(p.x - s.pos.x, 0.0, p.z - s.pos.z)
		var d: float = to.length()
		var spot: Vector3 = s.pos if d <= reach else s.pos + to * ((d - reach) / d)
		var spare: float = (j + 1 - now_tick) * Duel.DT \
				- AIArrival.time_to_arrive_caps(s.pos, spot, s.vel, caps)
		if spare >= _set_s:
			return spot
		if spare > best_spare:
			best_spare = spare
			best = spot
	return best if best.is_finite() else s.pos

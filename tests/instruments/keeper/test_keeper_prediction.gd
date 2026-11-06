extends GutTest

# Measures the option in docs/goalie-rebuild-plan.md, "Open: the client
# predicts the goalie on the render clock" (#903): re-seed a copy of the
# host's keeper at each snapshot's capture instant and step the same keeper
# code on to the render instant. Results and how to read them:
# docs/goalie-prediction-measurements.md.
#
# Host: the real keeper (KeeperController on Goalie.tscn) and the real puck's
# server tick (Puck._physics_process, his save boxes its contacts), scripted
# skaters, played tick by tick through each scenario; its world and its keeper
# are recorded every tick (pass 1). Pass 2 plays the same scenario again (it is
# deterministic, and checked to be) and at every snapshot tick copies the
# keeper's whole sim state onto a second keeper in a world of its own
# (keeper_state_cloner.gd), then steps that copy forward from the recorded
# world to the render instant and holds it against what pass 1 recorded the
# host doing at that tick.
#
# The span stepped: a snapshot captured at host time S arrives a one-way trip
# later, when the client draws S + one_way + input_lead
# (ClockSync.input_lead_for_rtt(2 * one_way) = one_way + the ~28 ms margin), so
# span = 2 * one_way + margin, rounded UP to the tick (the tick a frame between
# two ticks interpolates toward); the render clock then moves on two ticks
# before the next snapshot (45 Hz), so each snapshot's copy is compared at
# span and span + 1 tick and stepped to span + 2, and every host tick is
# compared exactly once.
#
# What the copy is fed after S, three ways:
#   TRUTH   everything as the host had it, every release and contact on the
#           tick it happened: a lower bound on disagreement (and, since nothing
#           differs, the check that the copy is complete).
#   HIDDEN  as TRUTH, but a release after S is not seen: the puck stays on its
#           carrier's blade (a pass in flight flies on), the shooter's shot
#           state stays as it was, and nothing that release causes (its
#           contacts) reaches the copy, until the next snapshot re-seeds it.
#   DR      as HIDDEN, and the skaters dead-reckoned from S at their S velocity
#           with their S shot states, a carried puck riding its carrier.
# In all three a loose puck already in flight at S (and his contacts with it
# before any later release) is the host's: the client's own puck prediction is
# not modelled, so what its contact with a mispredicted keeper would do is read
# from the boxes instead (the shot table below).
#
# Run: bash .claude/hooks/run-gut.sh -gselect=test_keeper_prediction
#      -gdir=res://tests/instruments. Asserts nothing. KEEPER_PREDICTION_TIERS
# (e.g. "HARD,EASY") picks the tiers; HARD alone by default.
# KEEPER_PREDICTION_QUICK=1 runs only TRUTH and WIRE at one one-way: the check
# of NOT_ON_WIRE; KEEPER_PREDICTION_SKIP (Class.field, comma separated) leaves
# more off it, to try one.

const Cloner := preload("res://tests/instruments/keeper/keeper_state_cloner.gd")
const ClockSync := preload("res://Scripts/networking/clock_sync.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const AIM_X: float = GameRules.NET_HALF_WIDTH - 0.12
const ONE_WAYS_MS: Array[float] = [15.0, 30.0, 50.0, 75.0, 100.0]
const SETTLE_TICKS: int = 150
const TAIL_TICKS: int = 90
# Snapshots from this far before the action, through the tail.
const LEAD_IN_TICKS: int = 20
const CARRY_AHEAD_M: float = 0.5
const BOX_OFF_M: float = 0.01

enum Variant { TRUTH, HIDDEN, DR, WIRE }
const VARIANT_NAMES: Array[String] = ["TRUTH", "HIDDEN", "DR", "WIRE"]
enum Ev { RELEASE, TOUCHED, CAUGHT, BOARDS, POST, GOAL_BODY, LOOSE, CHEST }
# The named plays, then the sweep's shots (SWEEP, one per `_sweep` row), whose
# rows are grouped standing and skating in in the scenario table.
enum Sc { SLOT_LOW_GLOVE, SLOT_TOP_BLOCKER, DOT_COLD_PAD, POINT_SLAPPER, CARRY_ACROSS, ONE_TIMER, REBOUND,
		SHARP_ANGLE, SWEEP }
const SC_NAMES: Array[String] = ["slot wrister, low glove", "slot wrister, top blocker", "dot, cold, far pad",
		"point slapper, five-hole", "carried across the slot, shot", "cross-crease pass, one-timer",
		"rebound and put-back", "sharp angle drive, short side high", "sweep, standing", "sweep, skating in"]
# The sweep: from the net front, the slot, the dot and the high slot, at
# 25 m/s to the low corners, the five-hole and the top corners; by a carrier
# standing on the spot who lets it go 6 ticks after the settle, and by one who
# skates in onto it from SWEEP_SKATE_M further out at SWEEP_SKATE_M_S and lets
# it go there. Every carrier settles first with the puck in the keeper's eyes,
# long enough to prime his read (KeeperPlayRead.PRIME_S).
const SWEEP_SPOTS: Array[Vector3] = [Vector3(0.6, 0.0, GOAL_Z + 3.5), Vector3(-1.0, 0.0, GOAL_Z + 7.0),
		Vector3(6.7, 0.0, GOAL_Z + 6.1), Vector3(0.0, 0.0, GOAL_Z + 12.0)]
const SWEEP_SPOT_NAMES: Array[String] = ["net front", "slot", "dot", "high slot"]
const SWEEP_STANDING_TICKS: int = 6
const SWEEP_SKATE_M: float = 4.0
const SWEEP_SKATE_M_S: float = 6.0
const SWEEP_SPEED: float = 25.0
const SWEEP_TAIL_TICKS: int = 70
# A sweep window opens this long before the release: past the longest span, so
# every span sees the release hidden.
const SWEEP_LEAD_IN_TICKS: int = 26
# The one-way the wire set is checked at.
const WIRE_AT: int = 2
# Fields the wire need not carry, by Class.field: the tier's tuning (the
# client has it), each collaborator's scratch (written before it is read on
# every tick), and what the pose already on the wire derives (the skeleton).
# The WIRE variant copies everything else and is held against TRUTH.
const NOT_ON_WIRE: Array[String] = [
	"Keeper.skeleton",
	"KeeperController._attackers", "KeeperController._opponents", "KeeperController._defenders",
	"KeeperController._screen_cfg", "KeeperController._last_save_time", "KeeperController._sm",
	"KeeperController._current_x", "KeeperController._current_depth",
	"KeeperShotRead.leg_delay_s", "KeeperShotRead.primed_delay_s",
	"KeeperPlayRead.delay_s", "KeeperPlayRead.primed_delay_s", "KeeperPlayRead._reception",
	"KeeperPlayRead._sticks",
	"KeeperSave.glove_speed_m_s", "KeeperSave.blocker_speed_m_s", "KeeperSave.drop_s", "KeeperSave._skel",
	"KeeperSave._rest_skel", "KeeperSave._try", "KeeperSave._base", "KeeperSave._out", "KeeperSave._scratch",
	"KeeperSave._contact", "KeeperSave._rebound", "KeeperSave._trial_turn",
	"KeeperCover.glove_speed_m_s", "KeeperCover._skel", "KeeperCover._pose", "KeeperCover._upright",
	"KeeperPoke.skel", "KeeperPoke._pose", "KeeperClear._aim", "KeeperClear._hit",
	"KeeperPositioning.screen",
	"KeeperSaveMove.drop_s", "KeeperSaveMove.pad_friction", "KeeperSaveMove.edge_decel", "KeeperSaveMove._skel",
	"KeeperFootwork.t_push_speed", "KeeperFootwork.shuffle_speed", "KeeperFootwork.c_cut_speed",
	"KeeperFootwork.accel",
	"KeeperGlide.t_push_speed", "KeeperGlide.c_cut_speed", "KeeperGlide.shuffle_speed", "KeeperGlide.accel",
	"KeeperLowReady._low", "KeeperLowReady._ready", "KeeperLowReady._skel",
	"KeeperDrop.drop_s", "KeeperDrop.rise_s", "KeeperDrop._up", "KeeperDrop._low", "KeeperDrop._skel",
	"KeeperSlide.push_speed", "KeeperSlide.drop_s", "KeeperSlide.friction", "KeeperSlide.edge_brake",
	"KeeperPost.drop_s", "KeeperPost.rise_s", "KeeperPost.swing_rad_s", "KeeperPost._ready", "KeeperPost._low",
	"KeeperPost._rvh", "KeeperPost._standing_edge", "KeeperPost._sealed_edge",
	"KeeperRoute._pivot_rate", "KeeperRoute._pivot_accel", "KeeperRoute._lead_max",
	"KeeperDrop._loaded", "KeeperDrop._loaded_knee",
	"KeeperSlide._low", "KeeperSlide._ready", "KeeperSlide._loaded", "KeeperSlide._loaded_knee", "KeeperSlide._set",
	"KeeperSlide._rvh", "KeeperSlide._off_post", "KeeperSlide._off_post_knee", "KeeperSlide._pad_end",
	"KeeperSlide._skel",
	"KeeperMotor._cut", "KeeperSaveMove._now",
	"KeeperSave._path", "KeeperSave._path_t", "KeeperSave._line_at", "KeeperSave._into_net", "KeeperSave._across",
	"KeeperSave._hit_part", "KeeperSave._hit_v", "KeeperSave._wait", "KeeperSave._fall", "KeeperSave._best",
	"KeeperRoute._best", "KeeperRoute._step_do", "KeeperRoute._step_spot", "KeeperRoute._step_legs",
	"KeeperRoute._step_hand_off", "KeeperRoute._glides_last", "KeeperRoute._way_do", "KeeperRoute._way_spot",
	"KeeperRoute._way_side", "KeeperRoute._down_do", "KeeperRoute._down_spot", "KeeperRoute._down_side",
	"KeeperPlayRead.receivers", "KeeperPlayRead.meets", "KeeperPlayRead.meet", "KeeperPlayRead.meet_s",
	"KeeperCover.target", "KeeperCover.glove_at", "KeeperCover.land_s", "KeeperCover.lean", "KeeperCover.toward",
	"KeeperCover.fingers", "KeeperPoke.target", "KeeperPoke.reach_s", "KeeperFetch.spot", "KeeperFetch.facing",
	"KeeperClear.target", "KeeperClear.blade_yaw", "KeeperClear.reach_s",
	"KeeperPositioning.bodies",
	"KeeperController._net", "KeeperController._last_velocity", "KeeperController._velocity_x",
	"KeeperController._velocity_z", "KeeperController._pending_reaction_back_date",
]


# What the keeper reads of the world on one tick, as the host had it after the
# skaters moved and before his tick, and what reached him around it.
class Frame:
	var puck_pos := Vector3.ZERO
	var puck_vel := Vector3.ZERO
	var puck_pending := Vector3.ZERO
	var carrier: int = -1
	var locked: bool = false
	var pinned: bool = false
	var sk_pos := PackedVector3Array()
	var sk_vel := PackedVector3Array()
	var sk_state := PackedInt32Array()
	# Before his tick (a release), and after it from the puck's tick.
	var pre: Array = []
	var post: Array = []
	var shot: bool = false


# The keeper after one tick, as the comparison reads him.
class Seen:
	var boxes: Array[Transform3D] = []
	var root := Vector3.ZERO
	var yaw: float = 0.0
	var save := Vector4i.ZERO


# The nodes of one world: a goalie, his keeper, the puck, two skaters.
class World:
	var goalie: Goalie = null
	var puck: Puck = null
	var ctrl: KeeperController = null
	var skaters: Array[Skater] = []

	func free_all() -> void:
		for n: Node in [ctrl, goalie, puck, skaters[0], skaters[1]]:
			if is_instance_valid(n):
				n.free()


class Stats:
	var box: PackedFloat64Array = PackedFloat64Array()
	var root: PackedFloat64Array = PackedFloat64Array()
	var ticks: int = 0
	var box_off: int = 0
	var save_ticks: int = 0
	var save_off: int = 0
	var shots: int = 0
	var verdict_off: int = 0
	var part_off: int = 0
	var choice_off: int = 0
	var shot_box: PackedFloat64Array = PackedFloat64Array()
	var clone_us: PackedFloat64Array = PackedFloat64Array()
	var step_us: PackedFloat64Array = PackedFloat64Array()
	var choose_us: PackedFloat64Array = PackedFloat64Array()
	var catch_us: PackedFloat64Array = PackedFloat64Array()
	var snap_us: PackedFloat64Array = PackedFloat64Array()
	var steps_us: PackedFloat64Array = PackedFloat64Array()
	var seat_us: PackedFloat64Array = PackedFloat64Array()
	var solve_us: PackedFloat64Array = PackedFloat64Array()
	# The part furthest off, by part, on the ticks whose gap passes BOX_OFF_M.
	var worst: Dictionary = {}


var _cloner: RefCounted = Cloner.new()
var _corners: Array[PackedVector3Array] = []
var _not_on_wire: Dictionary = {}
var _span: Array[int] = []
var _host: World = null
var _client: World = null
# A keeper reset and never played: on every other snapshot the WIRE copy lands
# on his state rather than on the last copy's, so a field left off the wire is
# held both stale and at its default.
var _decoy: World = null
var _quick: bool = false
var _frames: Array[Frame] = []
var _seen: Array[Seen] = []
var _rec: bool = true
var _cur: Frame = null
var _sc: int = 0
var _sweep_row: Array = []
var _sweep: Array = []
var _first_snap: int = 0
var _act: int = 0
var _len: int = 0
var _state: Dictionary = {}
var _t: int = 0
var _puck_max_speed: float = 0.0
var _puck_max_height: float = 0.0
var _frame := PuckGeometryCollision.Result.new()
var _tick := PuckAuthorityRules.TickResult.new()
var _sw := SweptDiscOBB.Result.new()
# Per [one-way][variant]: the clone's keeper per tick (t → Seen), and stats;
# per scenario too for the scenario table.
var _client_seen: Array = []
var _stats: Array = []
var _sc_stats: Array = []
var _host_us := PackedFloat64Array()
var _host_choose_us := PackedFloat64Array()
var _drift: int = 0
var _uncopied: Dictionary = {}


func before_all() -> void:
	for part: int in KeeperGear.PART_COUNT:
		var h: Vector3 = KeeperGear.half_extents(part)
		var c := PackedVector3Array()
		for i: int in 8:
			c.append(Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
		_corners.append(c)
	for f: String in NOT_ON_WIRE:
		_not_on_wire[f] = true
	for ow: float in ONE_WAYS_MS:
		_span.append(ceili((ow * 0.001 + ClockSync.input_lead_for_rtt(2.0 * ow)) / DT - 1e-6))
	var targets: Array = [["low glove", Vector3(AIM_X, 0.0, GOAL_Z)], ["low blocker", Vector3(-AIM_X, 0.0, GOAL_Z)],
			["five-hole", Vector3(0.0, 0.0, GOAL_Z)], ["top glove", Vector3(AIM_X, 1.05, GOAL_Z)],
			["top blocker", Vector3(-AIM_X, 1.05, GOAL_Z)]]
	for skating: bool in [false, true]:
		for i: int in SWEEP_SPOTS.size():
			for tg: Array in targets:
				_sweep.append([SWEEP_SPOTS[i], skating, tg[1], "%s, %s, %s" % [SWEEP_SPOT_NAMES[i],
						"skating in" if skating else "standing", tg[0]]])


func test_report_keeper_prediction() -> void:
	var tiers: Array[int] = []
	for t: String in OS.get_environment("KEEPER_PREDICTION_TIERS").split(",", false):
		tiers.append(GoalieSkillProfile.Difficulty[t.strip_edges().to_upper()])
	if tiers.is_empty():
		tiers.append(GoalieSkillProfile.Difficulty.HARD)
	_quick = OS.get_environment("KEEPER_PREDICTION_QUICK") == "1"
	for f: String in OS.get_environment("KEEPER_PREDICTION_SKIP").split(",", false):
		_not_on_wire[f.strip_edges()] = true
	var out: PackedStringArray = []
	out.append(_span_table())
	for tier: int in tiers:
		out.append(_run_tier(tier))
	out.append(_size_report())
	gut.p("\n" + "\n".join(out))
	assert_true(true)


func _span_table() -> String:
	var lines: PackedStringArray = ["### Spans", "",
			"| one-way ms | input lead ms | span ms (one-way + lead) | ticks stepped to the render tick | compared at ticks |",
			"|---|---|---|---|---|"]
	for i: int in ONE_WAYS_MS.size():
		var ow: float = ONE_WAYS_MS[i]
		var lead: float = ClockSync.input_lead_for_rtt(2.0 * ow) * 1000.0
		lines.append("| %.0f | %.1f | %.1f | %d (%.1f ms) | %d, %d |" % [ow, lead, ow + lead, _span[i],
				_span[i] * DT * 1000.0, _span[i], _span[i] + 1])
	return "\n".join(lines)


func _run_tier(tier: int) -> String:
	_client_seen.clear()
	_stats.clear()
	_sc_stats.clear()
	for oi: int in ONE_WAYS_MS.size():
		var per_v: Array = []
		var st: Array = []
		for v: int in Variant.size():
			per_v.append({})
			st.append(Stats.new())
		_client_seen.append(per_v)
		_stats.append(st)
	_host_us.clear()
	_host_choose_us.clear()
	_drift = 0
	var profile: GoalieSkillProfile = GoalieSkillProfile.for_difficulty(tier)
	var sc_lines: PackedStringArray = []
	for g: int in SC_NAMES.size():
		var sc_st: Array = []
		for oi: int in ONE_WAYS_MS.size():
			var row: Array = []
			for v: int in Variant.size():
				row.append(Stats.new())
			sc_st.append(row)
		_sc_stats.append(sc_st)
	var plays: Array = []
	for sc: int in Sc.SWEEP:
		plays.append([sc, []])
	for row: Array in _sweep:
		plays.append([Sc.SWEEP, row])
	for play: Array in plays:
		for per_v: Array in _client_seen:
			for d: Dictionary in per_v:
				d.clear()
		_sweep_row = play[1]
		_play_scenario(int(play[0]), profile)
		sc_lines.append_array(_score_scenario(_group()))
	return _tier_tables(tier, sc_lines)


# ── The two passes ────────────────────────────────────────────────────────────

func _play_scenario(sc: int, profile: GoalieSkillProfile) -> void:
	_sc = sc
	_frames.clear()
	_seen.clear()
	_client = _make_world(profile)
	_decoy = _make_world(profile)
	for pass_no: int in 2:
		_rec = pass_no == 0
		_host = _make_world(profile)
		_host.goalie.chest_contact = _on_chest
		_host.puck.puck_touched_goalie.connect(func(_g: Goalie) -> void: _post(Ev.TOUCHED))
		_host.puck.puck_caught_by_goalie.connect(func(_g: Goalie) -> void: _post(Ev.CAUGHT))
		_host.puck.puck_hit_boards.connect(func() -> void: _post(Ev.BOARDS))
		_host.puck.puck_touched_post.connect(func() -> void: _post(Ev.POST))
		_host.puck.puck_hit_goal_body.connect(func() -> void: _post(Ev.GOAL_BODY))
		_host.puck.puck_touched_loose.connect(func(_s: Skater) -> void: _post(Ev.LOOSE))
		_state.clear()
		_act = SETTLE_TICKS
		if sc == Sc.SWEEP:
			var go: int = _sweep_release_tick()
			_len = _act + go + SWEEP_TAIL_TICKS
			_first_snap = _act + go - SWEEP_LEAD_IN_TICKS
		else:
			_len = _act + _action_ticks(sc) + TAIL_TICKS
			_first_snap = _act - LEAD_IN_TICKS
		var first_snap: int = _first_snap
		var last_snap: int = _len - _span[_span.size() - 1] - 3
		for t: int in _len:
			_host_tick(t)
			if not _rec and t >= first_snap and t <= last_snap and t % 2 == 0:
				_snapshot(t)
		_host.free_all()
	_client.free_all()
	_decoy.free_all()


func _make_world(profile: GoalieSkillProfile) -> World:
	var w := World.new()
	w.goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate() as Goalie
	w.puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	for i: int in 2:
		w.skaters.append((load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater)
	w.ctrl = KeeperController.new()
	for n: Node in [w.goalie, w.puck, w.skaters[0], w.skaters[1], w.ctrl]:
		add_child(n)
		n.set_physics_process(false)
		n.set_process(false)
	w.puck.set_server_mode(true)
	_puck_max_speed = w.puck.max_speed
	_puck_max_height = w.puck.max_height
	w.puck.set_goalie_provider(func() -> Array: return [w.goalie])
	var sk: Array = [w.skaters[0], w.skaters[1]]
	w.ctrl.set_skater_getter(func() -> Array: return sk)
	w.ctrl.setup(w.goalie, w.puck, GOAL_Z, true)
	w.ctrl.apply_skill_profile(profile)
	w.ctrl.reset_to_crease()
	return w


# One host tick: the skaters and the puck as the scenario has them (a release
# read at once, as the puck's signal is), his tick, then the puck's own tick
# against his boxes while it is loose.
func _host_tick(t: int) -> void:
	var c: KeeperController = _host.ctrl
	c._view.invalidate()
	_t = t
	_cur = Frame.new()
	_drive(t)
	_capture_world(_cur)
	var chosen_at: float = c._chosen_at
	var t0: int = Time.get_ticks_usec()
	c._physics_process(DT)
	var us: float = float(Time.get_ticks_usec() - t0)
	if t >= _first_snap:
		_host_us.append(us)
		if c._chosen_at != chosen_at and c._chosen:
			_host_choose_us.append(us)
	var seen: Seen = _see(c)
	if _rec:
		_seen.append(seen)
	elif _box_gap(seen, _seen[t]) > 0.0 or seen.save != _seen[t].save:
		_drift += 1
	if _host.puck.get_carrier() == null:
		_host.goalie._part_velocity_frame = Engine.get_physics_frames() - 1
		_host.goalie.get_collision_part_velocities()
		_host.puck._physics_process(DT)
		_host.puck.drain_contact_events()
	if _rec:
		_frames.append(_cur)


func _post(ev: int) -> void:
	_cur.post.append([ev])
	if (ev == Ev.TOUCHED or ev == Ev.CAUGHT) and not _state.has("touch"):
		_state["touch"] = _t


func _on_chest(incoming: Vector3, point: Vector3, normal: Vector3, surface: Vector3,
		result: GoalieSaveRules.ContactResult) -> void:
	_cur.post.append([Ev.CHEST, incoming, point, normal, surface, result.trapped])
	_host.ctrl._chest_contact(incoming, point, normal, surface, result)


func _capture_world(f: Frame) -> void:
	var p: Puck = _host.puck
	f.puck_pos = p.global_position
	f.puck_vel = p.linear_velocity
	f.puck_pending = p._pending_elevation_vel
	f.carrier = _host.skaters.find(p.get_carrier())
	f.locked = p.pickup_locked
	f.pinned = p.motion_pinned
	for s: Skater in _host.skaters:
		f.sk_pos.append(s.global_position)
		f.sk_vel.append(s.velocity)
		f.sk_state.append(s.current_shot_state)


func _see(c: KeeperController) -> Seen:
	var s := Seen.new()
	var g: Transform3D = c.goalie.global_transform
	for part: int in KeeperGear.PART_COUNT:
		s.boxes.append(g * KeeperGear.box(c._keeper.skeleton, part))
	s.root = g.origin
	s.yaw = c.motor.yaw
	s.save = Vector4i(1 if c._chosen else 0, c.save.low, c.save.hand, int(signf(c.save.low_side)))
	return s


# The part whose box sits furthest from its place in `b`.
func _worst_part(a: Seen, b: Seen) -> int:
	var worst: float = -1.0
	var at: int = 0
	for part: int in KeeperGear.PART_COUNT:
		for corner: Vector3 in _corners[part]:
			var d: float = (a.boxes[part] * corner).distance_to(b.boxes[part] * corner)
			if d > worst:
				worst = d
				at = part
	return at


# The farthest any corner of any save box sits from its place in `b`.
func _box_gap(a: Seen, b: Seen) -> float:
	var worst: float = 0.0
	for part: int in KeeperGear.PART_COUNT:
		var xa: Transform3D = a.boxes[part]
		var xb: Transform3D = b.boxes[part]
		for corner: Vector3 in _corners[part]:
			worst = maxf(worst, (xa * corner).distance_to(xb * corner))
	return worst


# At snapshot `s` (the host's tick s done, the puck's included): for each
# one-way and each feed, his state copied onto the client's keeper and stepped
# to the render instant and two ticks past it.
func _snapshot(s: int) -> void:
	var src: KeeperController = _host.ctrl
	var dst: KeeperController = _client.ctrl
	_capture_size(src)
	for oi: int in ONE_WAYS_MS.size():
		var n0: int = _span[oi]
		for v: int in Variant.size():
			if v == Variant.WIRE and oi != WIRE_AT:
				continue
			if _quick and (oi != WIRE_AT or (v != Variant.TRUTH and v != Variant.WIRE)):
				continue
			if v == Variant.WIRE and s % 4 == 0:
				_cloner.copy(_decoy.ctrl, dst)
			var st: Stats = _stats[oi][v]
			var t0: int = Time.get_ticks_usec()
			_cloner.copy(src, dst, _not_on_wire if v == Variant.WIRE else {})
			var clone_us: float = float(Time.get_ticks_usec() - t0)
			st.clone_us.append(clone_us)
			var catch_us: float = clone_us
			var snap_us: float = clone_us
			var hidden_from: int = 1 << 30
			if v == Variant.HIDDEN or v == Variant.DR:
				for k: int in range(1, n0 + 3):
					if _has_release(_frames[s + k]):
						hidden_from = s + k
						break
			var dead := [Vector3.INF, Vector3.ZERO]
			for k: int in range(1, n0 + 3):
				var t: int = s + k
				dst._view.invalidate()
				var see_events: bool = t < hidden_from
				_apply_world(t, s, v, hidden_from, dead)
				if see_events:
					_replay(_frames[t].pre)
				var chosen_at: float = dst._chosen_at
				var t1: int = Time.get_ticks_usec()
				dst._physics_process(DT)
				var us: float = float(Time.get_ticks_usec() - t1)
				st.step_us.append(us)
				if dst._chosen_at != chosen_at and dst._chosen:
					st.choose_us.append(us)
				snap_us += us
				if k <= n0:
					catch_us += us
				if see_events:
					_replay(_frames[t].post)
				if k == n0 or k == n0 + 1:
					(_client_seen[oi][v] as Dictionary)[t] = _see(dst)
			st.catch_us.append(catch_us)
			st.snap_us.append(snap_us)
			st.steps_us.append(snap_us - clone_us)
			if v == Variant.TRUTH:
				_time_body(st, dst)
	for k: String in _cloner.uncopyable:
		_uncopied[k] = _cloner.uncopyable[k]


# What two pieces of his tick cost alone, on the pose he has: the skeleton
# solved from it, and his 22 save boxes seated on their nodes.
func _time_body(st: Stats, c: KeeperController) -> void:
	var t0: int = Time.get_ticks_usec()
	c._keeper.skeleton.pose(c._keeper_pose)
	var t1: int = Time.get_ticks_usec()
	for part: int in KeeperGear.PART_COUNT:
		c.goalie.seat_save_box(part, KeeperGear.box(c._keeper.skeleton, part))
	st.solve_us.append(float(t1 - t0))
	st.seat_us.append(float(Time.get_ticks_usec() - t1))


static func _has_release(f: Frame) -> bool:
	for e: Array in f.pre:
		if e[0] == Ev.RELEASE:
			return true
	return false


# The client's world on tick `t` for a copy seeded at `s`, fed as `v` has it.
func _apply_world(t: int, s: int, v: int, hidden_from: int, dead: Array) -> void:
	var f: Frame = _frames[t]
	var dr: bool = v == Variant.DR
	for i: int in 2:
		var sk: Skater = _client.skaters[i]
		if dr:
			var fs: Frame = _frames[s]
			sk.global_position = fs.sk_pos[i] + fs.sk_vel[i] * float(t - s) * DT
			sk.velocity = fs.sk_vel[i]
			sk.current_shot_state = fs.sk_state[i]
		else:
			sk.global_position = f.sk_pos[i]
			sk.velocity = f.sk_vel[i]
			sk.current_shot_state = f.sk_state[i]
	var p: Puck = _client.puck
	p.pickup_locked = f.locked
	p.motion_pinned = f.pinned
	# Carried at S and dead-reckoned: on its carrier's blade as S had it.
	var fs0: Frame = _frames[s]
	if dr and fs0.carrier >= 0 and (t < hidden_from or _frames[hidden_from - 1].carrier == fs0.carrier):
		_carry(p, fs0, fs0.carrier)
		return
	if t < hidden_from:
		_set_puck(p, f.puck_pos, f.puck_vel, f.puck_pending, f.carrier)
		return
	# Hidden: the release has not been seen.
	var before: Frame = _frames[hidden_from - 1]
	if before.carrier >= 0:
		if not dr:
			var sk2: Skater = _client.skaters[before.carrier]
			sk2.current_shot_state = before.sk_state[before.carrier]
		_carry(p, before, before.carrier)
		return
	if dead[0] == Vector3.INF:
		dead[0] = before.puck_pos
		dead[1] = before.puck_vel if before.puck_pending == Vector3.ZERO else before.puck_pending
		for _i: int in t - (hidden_from - 1):
			_free_step(dead)
	else:
		_free_step(dead)
	_set_puck(p, dead[0], dead[1], Vector3.ZERO, -1)


# The puck on `carrier`'s blade where it was at `f`, moved on with him as the
# client has him now.
func _carry(p: Puck, f: Frame, carrier: int) -> void:
	var sk: Skater = _client.skaters[carrier]
	_set_puck(p, f.puck_pos + (sk.global_position - f.sk_pos[carrier]), sk.velocity, Vector3.ZERO, carrier)


func _set_puck(p: Puck, pos: Vector3, vel: Vector3, queued: Vector3, carrier: int) -> void:
	if carrier >= 0:
		p.set_carrier(_client.skaters[carrier])
	else:
		p.clear_carrier()
	p.global_position = pos
	p.linear_velocity = vel
	p._pending_elevation_vel = queued


func _free_step(state: Array) -> void:
	_tick.touched_post = false
	_tick.touched_net = false
	PuckAuthorityRules.step_frame_substep(state[0], state[1], DT, GameRules.PUCK_COLLISION_RADIUS,
			_puck_max_speed, GameRules.PUCK_COLLISION_HALF_HEIGHT, _puck_max_height, _frame, _tick)
	state[0] = _tick.position
	state[1] = _tick.velocity


# The host's events on the client's puck, his goalie standing in for the host's.
func _replay(events: Array) -> void:
	var p: Puck = _client.puck
	var g: Goalie = _client.goalie
	for e: Array in events:
		match e[0]:
			Ev.RELEASE:
				p.puck_released.emit()
			Ev.TOUCHED:
				p.puck_touched_goalie.emit(g)
			Ev.CAUGHT:
				p.puck_caught_by_goalie.emit(g)
			Ev.BOARDS:
				p.puck_hit_boards.emit()
			Ev.POST:
				p.puck_touched_post.emit()
			Ev.GOAL_BODY:
				p.puck_hit_goal_body.emit()
			Ev.LOOSE:
				p.puck_touched_loose.emit(null)
			Ev.CHEST:
				var r := GoalieSaveRules.ContactResult.new()
				r.trapped = e[5]
				_client.ctrl._chest_contact(e[1], e[2], e[3], e[4], r)


# ── The scenarios ─────────────────────────────────────────────────────────────

func _action_ticks(sc: int) -> int:
	match sc:
		Sc.CARRY_ACROSS:
			return 150
		Sc.POINT_SLAPPER:
			return 54
		Sc.SHARP_ANGLE:
			return 105
		Sc.ONE_TIMER, Sc.REBOUND:
			return 90
	return 36


# The skaters and the puck on tick `t`; before the action, the carrier stands
# on his spot with the puck and the keeper settles on him.
func _drive(t: int) -> void:
	var a: int = t - _act
	match _sc:
		Sc.SLOT_LOW_GLOVE:
			_off_ice(1)
			_wrister(a, Vector3(0.0, 0.0, GOAL_Z + 9.0), 36, Vector3(AIM_X, 0.0, GOAL_Z), 26.0)
		Sc.SLOT_TOP_BLOCKER:
			_off_ice(1)
			_wrister(a, Vector3(0.0, 0.0, GOAL_Z + 9.0), 36, Vector3(-AIM_X, 1.05, GOAL_Z), 28.0)
		Sc.DOT_COLD_PAD:
			_off_ice(1)
			_wrister(a, Vector3(-6.7, 0.0, GOAL_Z + 6.1), -36, Vector3(AIM_X, 0.3, GOAL_Z), 30.0)
		Sc.POINT_SLAPPER:
			_off_ice(1)
			_wrister(a, Vector3(5.0, 0.0, GOAL_Z + 18.0), 54, Vector3(0.0, 0.05, GOAL_Z), 34.0,
					SkaterStateMachine.State.SLAPPER_CHARGE_WITH_PUCK)
		Sc.CARRY_ACROSS:
			_carry_across(a)
		Sc.ONE_TIMER:
			_one_timer(a)
		Sc.REBOUND:
			_rebound(t, a)
		Sc.SHARP_ANGLE:
			_sharp_angle(a)
		Sc.SWEEP:
			_off_ice(1)
			_sweep_shot(a)


func _stand(i: int, at: Vector3, vel: Vector3, state: int) -> void:
	var s: Skater = _host.skaters[i]
	s.global_position = at
	s.velocity = vel
	s.current_shot_state = state


func _hold(i: int) -> void:
	var s: Skater = _host.skaters[i]
	var p: Puck = _host.puck
	if p.get_carrier() != s:
		p.set_carrier(s)
	p.global_position = Vector3(s.global_position.x, p.ice_height, s.global_position.z - CARRY_AHEAD_M)
	p.linear_velocity = s.velocity


func _release(from: Vector3, vel: Vector3, shot: bool) -> void:
	var p: Puck = _host.puck
	p.clear_carrier()
	p.global_position = Vector3(from.x, p.ice_height, from.z)
	p.apply_release_velocity(vel)
	_cur.pre.append([Ev.RELEASE])
	_cur.shot = shot
	p.puck_released.emit()


# The flight from `from` that crosses the goal line at `target` at `speed`
# across the ice.
static func _flight(from: Vector3, target: Vector3, speed: float) -> Vector3:
	var flat := Vector2(target.x - from.x, target.z - from.z)
	var flight_s: float = flat.length() / speed
	var vy: float = 0.0
	if target.y > 0.0:
		vy = (target.y + 0.5 * GameRules.GRAVITY_M_S2 * flight_s * flight_s) / flight_s
	var along: Vector2 = flat.normalized() * speed
	return Vector3(along.x, vy, along.y)


func _off_ice(i: int) -> void:
	_stand(i, Vector3(20.0, 0.0, 20.0), Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)


# A carrier on `at` who winds up `windup` ticks (a cold release, none: the
# negative is when he lets it go) and shoots at `target`.
func _wrister(a: int, at: Vector3, windup: int, target: Vector3, speed: float,
		charge: int = SkaterStateMachine.State.WRISTER_AIM) -> void:
	var go: int = absi(windup)
	if a < go:
		_stand(0, at, Vector3.ZERO, charge if a >= 0 and windup > 0 else SkaterStateMachine.State.SKATING_WITH_PUCK)
		_hold(0)
	elif a == go:
		_stand(0, at, Vector3.ZERO, SkaterStateMachine.State.FOLLOW_THROUGH)
		var from: Vector3 = _host.puck.global_position
		_release(from, _flight(from, target, speed), true)
	else:
		_stand(0, at, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)


func _sweep_release_tick() -> int:
	return roundi(SWEEP_SKATE_M / SWEEP_SKATE_M_S / DT) if bool(_sweep_row[1]) else SWEEP_STANDING_TICKS


func _sweep_shot(a: int) -> void:
	var spot: Vector3 = _sweep_row[0]
	var go: int = _sweep_release_tick()
	if not bool(_sweep_row[1]):
		_wrister(a, spot, -go, _sweep_row[2], SWEEP_SPEED)
		return
	# Skating in down the line from the spot to the net's centre.
	var way: Vector3 = (Vector3(0.0, 0.0, GOAL_Z) - spot).normalized()
	var from: Vector3 = spot - way * SWEEP_SKATE_M
	var vel: Vector3 = way * SWEEP_SKATE_M_S
	if a < 0:
		_stand(0, from, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITH_PUCK)
		_hold(0)
	elif a < go:
		_stand(0, from + vel * float(a) * DT, vel, SkaterStateMachine.State.SKATING_WITH_PUCK)
		_hold(0)
	elif a == go:
		_stand(0, spot, vel, SkaterStateMachine.State.FOLLOW_THROUGH)
		var p: Vector3 = _host.puck.global_position
		_release(p, _flight(p, _sweep_row[2], SWEEP_SPEED), true)
	else:
		_stand(0, spot, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)


func _carry_across(a: int) -> void:
	_off_ice(1)
	var from := Vector3(-5.0, 0.0, GOAL_Z + 8.0)
	var speed: float = 6.0
	if a < 0:
		_stand(0, from, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITH_PUCK)
		_hold(0)
	elif a < 150:
		_stand(0, from + Vector3(speed * float(a) * DT, 0.0, 0.0), Vector3(speed, 0.0, 0.0),
				SkaterStateMachine.State.SKATING_WITH_PUCK)
		_hold(0)
	elif a == 150:
		var at: Vector3 = from + Vector3(speed * 150.0 * DT, 0.0, 0.0)
		_stand(0, at, Vector3(speed, 0.0, 0.0), SkaterStateMachine.State.FOLLOW_THROUGH)
		var p: Vector3 = at + Vector3(0.0, 0.0, -CARRY_AHEAD_M)
		_release(p, _flight(p, Vector3(-AIM_X, 0.1, GOAL_Z), 26.0), true)
	else:
		var at2: Vector3 = from + Vector3(speed * 150.0 * DT, 0.0, 0.0)
		_stand(0, at2, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)


# A pass from low on one side across the crease to a stick loaded on the far
# side, shot as it gets there.
func _one_timer(a: int) -> void:
	var passer := Vector3(-5.0, 0.0, GOAL_Z + 3.0)
	var receiver := Vector3(2.5, 0.0, GOAL_Z + 5.5)
	var stick: Vector3 = receiver + Vector3(-0.3, 0.0, -CARRY_AHEAD_M)
	if a < 10:
		_stand(0, passer, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITH_PUCK)
		_stand(1, receiver, Vector3.ZERO, SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK)
		_hold(0)
		return
	_stand(0, passer, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)
	if a == 10:
		_stand(1, receiver, Vector3.ZERO, SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK)
		var from: Vector3 = _host.puck.global_position
		var to := Vector3(stick.x, 0.0, stick.z)
		_release(from, (to - Vector3(from.x, 0.0, from.z)).normalized() * 14.0, false)
		return
	if _state.has("shot"):
		_stand(1, receiver, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)
		return
	_stand(1, receiver, Vector3.ZERO, SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK)
	var at: Vector3 = _host.puck.global_position
	var left: Vector3 = Vector3(stick.x - at.x, 0.0, stick.z - at.z)
	if left.length() < 0.35 or left.dot(_host.puck.linear_velocity) < 0.0:
		_state["shot"] = true
		_stand(1, receiver, Vector3.ZERO, SkaterStateMachine.State.FOLLOW_THROUGH)
		_release(at, _flight(at, Vector3(-AIM_X, 0.1, GOAL_Z), 30.0), true)


# A shot at the pads from the slot, and a second attacker skating onto what
# comes off him and putting it back to the far side.
func _rebound(t: int, a: int) -> void:
	var at := Vector3(0.0, 0.0, GOAL_Z + 8.0)
	if a <= 27:
		_stand(1, Vector3(-2.5, 0.0, GOAL_Z + 4.0), Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)
		_wrister(a, at, 27, Vector3(0.35, 0.1, GOAL_Z), 22.0)
		return
	_stand(0, at, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)
	var p: Puck = _host.puck
	var s: Skater = _host.skaters[1]
	var to_puck := Vector3(p.global_position.x - s.global_position.x, 0.0, p.global_position.z - s.global_position.z)
	var step: Vector3 = to_puck.normalized() * minf(5.0 * DT, maxf(to_puck.length() - 0.6, 0.0))
	if _state.has("putback"):
		_stand(1, s.global_position, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)
		return
	_stand(1, s.global_position + step, step / DT, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)
	if _state.has("touch") and t - int(_state["touch"]) == 30 and p.get_carrier() == null and not p.pickup_locked \
			and p.global_position.z > GOAL_Z + 0.3:
		_state["putback"] = true
		var from: Vector3 = p.global_position
		var side: float = -signf(from.x) if absf(from.x) > 0.05 else -1.0
		_release(from, _flight(from, Vector3(side * AIM_X, 0.1, GOAL_Z), 24.0), true)


func _sharp_angle(a: int) -> void:
	_off_ice(1)
	var from := Vector3(-9.0, 0.0, GOAL_Z + 3.0)
	var to := Vector3(-3.5, 0.0, GOAL_Z + 1.0)
	var vel: Vector3 = (to - from) / (105.0 * DT)
	if a < 0:
		_stand(0, from, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITH_PUCK)
		_hold(0)
	elif a < 105:
		_stand(0, from + vel * float(a) * DT, vel, SkaterStateMachine.State.SKATING_WITH_PUCK)
		_hold(0)
	elif a == 105:
		_stand(0, to, vel, SkaterStateMachine.State.FOLLOW_THROUGH)
		var p: Vector3 = _host.puck.global_position
		_release(p, _flight(p, Vector3(-AIM_X, 0.9, GOAL_Z), 24.0), true)
	else:
		_stand(0, to, Vector3.ZERO, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)


# ── Scoring ───────────────────────────────────────────────────────────────────

# The scenario table's row for the play under way.
func _group() -> int:
	if _sc != Sc.SWEEP:
		return _sc
	return Sc.SWEEP + (1 if bool(_sweep_row[1]) else 0)


func _play_name() -> String:
	return SC_NAMES[_sc] if _sc != Sc.SWEEP else "sweep: " + String(_sweep_row[3])


# This scenario's compared ticks into the tier's and the scenario's stats, and
# a line per shot: the host's verdict and the client's at each one-way, by feed.
func _score_scenario(sc: int) -> PackedStringArray:
	for oi: int in ONE_WAYS_MS.size():
		for v: int in Variant.size():
			var seen: Dictionary = _client_seen[oi][v]
			for t: int in seen:
				for st: Stats in [_stats[oi][v], _sc_stats[sc][oi][v]]:
					_score_tick(st, seen[t], _seen[t])
	var lines: PackedStringArray = []
	var shot_no: int = 0
	for r: int in _frames.size():
		if not (_has_release(_frames[r]) and _frames[r].shot):
			continue
		shot_no += 1
		var host: Array = _verdict(r, _seen_by_tick())
		var flight: String = "%.0f ms" % (float(int(host[1]) - r + 1) * DT * 1000.0) if int(host[0]) >= 0 else "-"
		var row: String = "| %s #%d | %s | %s | %s |" % [_play_name(), shot_no, flight, _verdict_name(host),
				_real_outcome(r)]
		for oi: int in ONE_WAYS_MS.size():
			var cell: String = ""
			for v: int in [Variant.TRUTH, Variant.HIDDEN, Variant.DR]:
				var client: Array = _verdict(r, _client_seen[oi][v])
				cell += _score_shot([_stats[oi][v], _sc_stats[sc][oi][v]], host, client, _client_seen[oi][v]) + " "
			row += " %s |" % cell.strip_edges()
		lines.append(row)
	return lines


func _seen_by_tick() -> Dictionary:
	var d: Dictionary = {}
	for t: int in _seen.size():
		d[t] = _seen[t]
	return d


func _score_tick(st: Stats, c: Seen, h: Seen) -> void:
	st.ticks += 1
	var gap: float = _box_gap(c, h)
	st.box.append(gap)
	st.root.append(Vector2(c.root.x - h.root.x, c.root.z - h.root.z).length())
	if gap > BOX_OFF_M:
		st.box_off += 1
		var part: String = KeeperGear.Part.keys()[_worst_part(c, h)]
		st.worst[part] = int(st.worst.get(part, 0)) + 1
	if c.save.x == 1 or h.save.x == 1:
		st.save_ticks += 1
		if c.save != h.save:
			st.save_off += 1


# The free flight of the shot released on tick `r` (the puck's own frame step,
# no keeper) against the keeper `seen` has on each tick: [kind (0 save, 1 goal,
# 2 wide, -1 undecided: a tick it has no keeper for), tick, part].
func _verdict(r: int, seen: Dictionary) -> Array:
	var f: Frame = _frames[r]
	var state: Array = [f.puck_pos, f.puck_pending if f.puck_pending != Vector3.ZERO else f.puck_vel]
	for t: int in range(r, _frames.size()):
		if not seen.has(t):
			return [-1, t, -1]
		var was: Vector3 = state[0]
		_free_step(state)
		var at: Vector3 = state[0]
		var s: Seen = seen[t]
		var best: float = INF
		var part_hit: int = -1
		for part: int in KeeperGear.PART_COUNT:
			if SweptDiscOBB.contact(was, at, GameRules.PUCK_COLLISION_RADIUS, s.boxes[part],
					KeeperGear.half_extents(part), _sw) and _sw.toi < best:
				best = _sw.toi
				part_hit = part
		if part_hit >= 0:
			return [0, t, part_hit]
		if at.z <= GOAL_Z:
			var r_m: float = GameRules.PUCK_COLLISION_RADIUS
			var inside: bool = absf(at.x) < GameRules.NET_HALF_WIDTH - r_m and at.y < GameRules.NET_HEIGHT - r_m
			return [1 if inside else 2, t, -1]
		if (state[1] as Vector3).z > -0.5:
			return [2, t, -1]
	return [-1, _frames.size(), -1]


static func _verdict_name(v: Array) -> String:
	match int(v[0]):
		0:
			return "save %s @%d" % [KeeperGear.Part.keys()[v[2]], v[1]]
		1:
			return "GOAL @%d" % v[1]
		2:
			return "wide @%d" % v[1]
	return "?"


# What the real puck did after the release on `r`: the first contact with him,
# or none.
func _real_outcome(r: int) -> String:
	for t: int in range(r, mini(r + 120, _frames.size())):
		if t > r and _has_release(_frames[t]):
			break
		for e: Array in _frames[t].post:
			if e[0] == Ev.CAUGHT:
				return "caught @%d" % t
			if e[0] == Ev.TOUCHED:
				return "touched @%d" % t
	return "not touched"


# One shot's client verdict against the host's into each of `into`: = the same
# save on the same tick (or the same goal or miss), ~ a save on another part or
# tick, X a save against a goal or a miss, ? undecided (a tick past the
# window). With it, the save each had chosen and the boxes' gap on the tick
# the host's verdict fell.
func _score_shot(into: Array, host: Array, client: Array, cseen: Dictionary) -> String:
	if int(host[0]) < 0 or int(client[0]) < 0:
		return "?"
	var t: int = int(host[1])
	var mark: String = "="
	if (int(host[0]) == 0) != (int(client[0]) == 0) or (int(host[0]) != 0 and int(host[0]) != int(client[0])):
		mark = "X"
	elif int(host[0]) == 0 and (int(host[2]) != int(client[2]) or int(host[1]) != int(client[1])):
		mark = "~"
	for st: Stats in into:
		st.shots += 1
		if mark == "X":
			st.verdict_off += 1
		elif mark == "~":
			st.part_off += 1
		if cseen.has(t):
			var c: Seen = cseen[t]
			st.shot_box.append(_box_gap(c, _seen[t]))
			if c.save != _seen[t].save:
				st.choice_off += 1
	return mark


# ── Tables ────────────────────────────────────────────────────────────────────

func _tier_tables(tier: int, shot_lines: PackedStringArray) -> String:
	var name_tier: String = GoalieSkillProfile.Difficulty.keys()[tier]
	var profile: GoalieSkillProfile = GoalieSkillProfile.for_difficulty(tier)
	var lines: PackedStringArray = ["", "## %s (read %.0f ms, primed %.0f ms)" % [name_tier,
			profile.reaction_delay_s * 1000.0, profile.prearmed_reaction_delay_s * 1000.0], "",
			"Host replay drift (pass 2 against pass 1, ticks off): %d" % _drift, "",
			"### Disagreement by one-way and feed", "",
			"| one-way | feed | ticks | box gap p50 / p95 / max cm | root p95 cm | ticks box > 1 cm | save state differs | shots | X | ~ | save chosen differs at the verdict | box gap at the verdict p95 / max cm | parts furthest off (ticks > 1 cm) |",
			"|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
	for oi: int in ONE_WAYS_MS.size():
		for v: int in Variant.size():
			var st: Stats = _stats[oi][v]
			if st.ticks == 0:
				continue
			lines.append("| %.0f | %s | %d | %s | %.1f | %.1f%% | %d / %d | %d | %d | %d | %d | %s | %s |" % [
					ONE_WAYS_MS[oi], VARIANT_NAMES[v], st.ticks, _cm3(st.box), 100.0 * _pct(st.root, 0.95),
					100.0 * float(st.box_off) / float(st.ticks), st.save_off, st.save_ticks, st.shots,
					st.verdict_off, st.part_off, st.choice_off, _cm2(st.shot_box), _top(st.worst)])
	lines.append_array(["", "### Box gap by scenario, HIDDEN / DR (p95 / max cm)", ""])
	var head: String = "| scenario |"
	var rule: String = "|---|"
	for ow: float in ONE_WAYS_MS:
		head += " %.0f ms |" % ow
		rule += "---|"
	lines.append_array([head, rule])
	for sc: int in SC_NAMES.size():
		var row: String = "| %s |" % SC_NAMES[sc]
		for oi: int in ONE_WAYS_MS.size():
			var h: Stats = _sc_stats[sc][oi][Variant.HIDDEN]
			var d: Stats = _sc_stats[sc][oi][Variant.DR]
			row += " %s / %s |" % [_cm2(h.box), _cm2(d.box)]
		lines.append(row)
	var shot_head: String = "| shot | release to verdict | host (free flight against his boxes) | real puck |"
	var shot_rule: String = "|---|---|---|---|"
	for ow: float in ONE_WAYS_MS:
		shot_head += " %.0f ms T H D |" % ow
		shot_rule += "---|"
	lines.append_array(["", "### Shots: the client's verdict (= same, ~ other part or tick, X save against goal, ? past the window)",
			"", shot_head, shot_rule])
	lines.append_array(shot_lines)
	lines.append_array(_cost_table())
	return "\n".join(lines)


func _cost_table() -> PackedStringArray:
	var lines: PackedStringArray = ["", "### Cost (µs on this machine, GDScript, no native extension)", "",
			"Host keeper tick: p50 %.0f, p95 %.0f, max %.0f; ticks that chose a save: n %d, max %.0f. Two keepers, host, per 60 fps frame: %.2f ms."
			% [_pct(_host_us, 0.5), _pct(_host_us, 0.95), _pct(_host_us, 1.0), _host_choose_us.size(),
			_pct(_host_choose_us, 1.0), 2.0 * 1.5 * _mean(_host_us) / 1000.0], "",
			"| one-way | copy p50 / p95 | step p50 / p95 / max | steps that chose a save: n, p50 / max | catch-up (copy + span) p50 / p95 / max | a snapshot's steps (span + 2) mean / max | two keepers per 60 fps frame, mean ms: steps / with this copy | two keepers, the snapshot's frame (copy + span), p95 / max ms |",
			"|---|---|---|---|---|---|---|---|"]
	for oi: int in ONE_WAYS_MS.size():
		var st := Stats.new()
		for v: int in [Variant.TRUTH, Variant.HIDDEN, Variant.DR]:
			var s: Stats = _stats[oi][v]
			st.clone_us.append_array(s.clone_us)
			st.step_us.append_array(s.step_us)
			st.choose_us.append_array(s.choose_us)
			st.catch_us.append_array(s.catch_us)
			st.snap_us.append_array(s.snap_us)
			st.steps_us.append_array(s.steps_us)
		lines.append("| %.0f | %.0f / %.0f | %.0f / %.0f / %.0f | %d, %.0f / %.0f | %.0f / %.0f / %.0f | %.0f / %.0f | %.2f / %.2f | %.2f / %.2f |" % [
				ONE_WAYS_MS[oi], _pct(st.clone_us, 0.5), _pct(st.clone_us, 0.95), _pct(st.step_us, 0.5),
				_pct(st.step_us, 0.95), _pct(st.step_us, 1.0), st.choose_us.size(), _pct(st.choose_us, 0.5),
				_pct(st.choose_us, 1.0), _pct(st.catch_us, 0.5), _pct(st.catch_us, 0.95), _pct(st.catch_us, 1.0),
				_mean(st.steps_us), _pct(st.steps_us, 1.0), 2.0 * 45.0 * _mean(st.steps_us) / 60.0 / 1000.0,
				2.0 * 45.0 * _mean(st.snap_us) / 60.0 / 1000.0,
				2.0 * _pct(st.catch_us, 0.95) / 1000.0, 2.0 * _pct(st.catch_us, 1.0) / 1000.0])
	var w: Stats = _stats[WIRE_AT][Variant.WIRE]
	lines.append("")
	var t: Stats = _stats[WIRE_AT][Variant.TRUTH]
	lines.append("Copying only the wire set (WIRE, at %.0f ms): copy p50 %.0f µs. Of a step, on the pose he has: the skeleton solved p50 %.0f µs, his 22 save boxes seated on their nodes p50 %.0f µs." % [
			ONE_WAYS_MS[WIRE_AT], _pct(w.clone_us, 0.5), _pct(t.solve_us, 0.5), _pct(t.seat_us, 0.5)])
	return lines


static func _top(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	var out: PackedStringArray = []
	for k: String in keys.slice(0, 4):
		out.append("%s %d" % [k, counts[k]])
	return ", ".join(out)


static func _pct(a: PackedFloat64Array, q: float) -> float:
	if a.is_empty():
		return NAN
	var s: PackedFloat64Array = a.duplicate()
	s.sort()
	return s[clampi(int(ceil(q * float(s.size()))) - 1, 0, s.size() - 1)]


static func _mean(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return NAN
	var sum: float = 0.0
	for x: float in a:
		sum += x
	return sum / float(a.size())


static func _cm3(a: PackedFloat64Array) -> String:
	return "%.1f / %.1f / %.1f" % [100.0 * _pct(a, 0.5), 100.0 * _pct(a, 0.95), 100.0 * _pct(a, 1.0)]


static func _cm2(a: PackedFloat64Array) -> String:
	return "%.1f / %.1f" % [100.0 * _pct(a, 0.95), 100.0 * _pct(a, 1.0)]


# ── What the copy carries ─────────────────────────────────────────────────────

const FIRST: Array[String] = ["motor", "read", "play", "save", "cover", "look", "fetch", "poke", "clear", "brain"]
const PLAY_HISTORY: Array[String] = ["_at", "_moving", "_bodies", "_winding", "_loose", "_theirs", "_hidden",
		"_head", "_count"]
var _size_lines: PackedStringArray = []


# The state's weight, taken once, with a save in flight.
func _capture_size(src: KeeperController) -> void:
	if not _size_lines.is_empty() or not src._chosen:
		return
	var listing_full: Dictionary = {}
	var listing_wire: Dictionary = {}
	var full: Dictionary = _cloner.account(src, {}, FIRST, listing_full)
	var wire: Dictionary = _cloner.account(src, _not_on_wire, FIRST, listing_wire)
	_size_lines.append_array(["", "## The copied state (taken mid-save, %s)" % _play_name(), "",
			"| field | full: raw B / quantized B / leaves / poses | wire set: quantized B / leaves / poses |",
			"|---|---|---|"])
	var tf := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var tw := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for f: String in full:
		var a: PackedFloat64Array = full[f]
		var b: PackedFloat64Array = wire.get(f, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
		for i: int in 4:
			tf[i] += a[i]
			tw[i] += b[i]
		if a[2] == 0.0:
			continue
		_size_lines.append("| %s | %.0f / %.0f / %.0f / %.0f | %.0f / %.0f / %.0f |" % [f, a[0], a[1], a[2], a[3],
				b[1], b[2], b[3]])
	_size_lines.append("| **total** | %.0f / %.0f / %.0f / %.0f | %.0f / %.0f / %.0f |" % [tf[0], tf[1], tf[2], tf[3],
			tw[1], tw[2], tw[3]])
	var hist := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for f: String in PLAY_HISTORY:
		_cloner._acc(src.play.get(f), hist, {})
	var pose: float = float(KeeperPoseCodec.SIZE)
	_size_lines.append_array(["",
			"Of the wire set: the pose already on the wire %.0f B; the play read's history (%s) %.0f B quantized, which the client can rebuild from its own snapshot buffer; the rest %.0f B."
			% [pose, ", ".join(PLAY_HISTORY), hist[1], tw[1] - pose - hist[1]], "",
			"Wire set, fields by class:", ""])
	var classes: Array = listing_wire.keys()
	classes.sort()
	for cls: String in classes:
		_size_lines.append("- `%s`: %s" % [cls, ", ".join(listing_wire[cls])])


func _size_report() -> String:
	var lines: PackedStringArray = _size_lines.duplicate()
	lines.append("")
	lines.append("Reached and not copyable (shared as they are): %s" % (str(_uncopied) if not _uncopied.is_empty() else "none"))
	return "\n".join(lines)

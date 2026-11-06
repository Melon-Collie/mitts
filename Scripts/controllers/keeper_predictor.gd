class_name KeeperPredictor
extends Node3D

# A client's own keeper for one goalie, drawn on the render clock
# (Scripts/networking/CLAUDE.md → the goalie on the render clock, #903): the
# host's keeper rebuilt from the newest snapshot's blob at that snapshot's tick
# and stepped by the same keeper code, tick by tick, to the instant the rest of
# the scene is drawn at, against a shadow world of its own (KeeperWorldSource:
# a shadow puck and shadow skaters as this client has them at each instant).
# Nothing it does reaches the real puck, the skaters or the game: its goalie,
# puck and skaters are its own nodes, hidden, never processed, in no group.
#
# Rollback: it keeps its own blob at each recent broadcast tick (writing it is
# the snap the host makes there, so it steps as the host does). A snapshot
# whose blob equals the one it kept for that tick confirms it and it steps on,
# one tick a tick; one that differs, or one for a tick it holds no blob for,
# re-seeds it there and it re-steps to the render instant. It never steps past
# the render instant, nor further than MAX_SPAN_S from the newest snapshot.

const _Constants: GDScript = preload("res://Scripts/game/constants.gd")
const DT: float = _Constants.TICK_DURATION
# Ticks between broadcasts: the host snaps on every one.
const BROADCAST_EVERY: int = _Constants.PHYSICS_TICK / _Constants.STATE_RATE
# Past this from the newest snapshot there is no prediction to draw: the loose
# puck's own limit, past which this client has no puck to step him against.
const MAX_SPAN_S: float = _Constants.PUCK_PREDICT_MAX_S
# A sequence jump past this is a new timeline (a new match's codec, a long
# gap), not a run of lost snapshots.
const MAX_SEQ_JUMP: int = 4 * _Constants.STATE_RATE
# Broadcast ticks of his own state kept for comparison: past the longest span.
const HISTORY: int = 32
# A render instant this near a tick is that tick's: host times are wall labels
# in 0.1 ms, and a tick's instant summed from them carries float error.
const TICK_EPSILON: float = 1e-3
const _GOALIE_SCENE: PackedScene = preload("res://Scenes/Goalie.tscn")

var keeper: KeeperController = null
# The drawn instant: his two stepped ticks bracketing it, blended.
var drawn := GoalieNetworkState.new()

# Outcomes since the counters were last taken: snapshots that confirmed his
# own state, snapshots that re-seeded him and re-stepped the span (their box
# gap, m, at the snapshot's tick where he held a state for it: the farthest box
# corner off the host's, how many, their sum and the largest), ticks stepped,
# and the time the last `advance` took.
var confirmed: int = 0
var resteps: int = 0
var gaps: int = 0
var gap_sum_m: float = 0.0
var gap_max_m: float = 0.0
var steps: int = 0
var last_frame_us: int = 0

var _goalie: Goalie = null
var _puck: KeeperShadowPuck = null
var _skaters: Array[KeeperShadowSkater] = []
var _source: KeeperWorldSource = null

var _seeded: bool = false
# The tick he stands at, and the newest snapshot's tick and host time, on one
# count of ticks (a snapshot's tick is its sequence's broadcasts times
# BROADCAST_EVERY).
var _tick: int = 0
var _snap_tick: int = 0
var _snap_time: float = 0.0
var _last_seq: int = -1
var _seq_count: int = 0
var _has_pending: bool = false
var _pending_blob := PackedByteArray()
var _pending_tick: int = 0
var _pending_time: float = 0.0
var _hist_tick := PackedInt64Array()
var _hist_blob: Array[PackedByteArray] = []
var _hist_state: Array[GoalieNetworkState] = []
var _prev := GoalieNetworkState.new()
var _cur := GoalieNetworkState.new()
var _mismatch := GoalieNetworkState.new()
var _gap_a := KeeperSkeleton.new()
var _gap_b := KeeperSkeleton.new()


# His shadow world under this node and his keeper in it, playing as the host's
# does: `goal_line_z`, `team_id` and `profile` as the drawn goalie's.
func setup(goal_line_z: float, team_id: int, profile: GoalieSkillProfile, source: KeeperWorldSource) -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_source = source
	_goalie = _GOALIE_SCENE.instantiate() as Goalie
	add_child(_goalie)
	_puck = KeeperShadowPuck.new()
	add_child(_puck)
	keeper = KeeperController.new()
	keeper.team_id = team_id
	keeper.seat_places_only = true
	add_child(keeper)
	keeper.set_skater_getter(_shadow_skaters)
	keeper.setup(_goalie, _puck, goal_line_z, true, profile)
	keeper.apply_skill_profile(profile)
	_hist_tick.resize(HISTORY)
	_hist_tick.fill(-1)
	for i: int in HISTORY:
		_hist_blob.append(PackedByteArray())
		_hist_state.append(GoalieNetworkState.new())


func _shadow_skaters() -> Array:
	return _skaters


func apply_skill_profile(profile: GoalieSkillProfile) -> void:
	keeper.apply_skill_profile(profile)


# The newest snapshot's blob, captured at `host_ts`, sequence `seq` (the world
# state's u16): resolved on the next `advance`, once the rest of that snapshot
# is in.
func offer(blob: PackedByteArray, host_ts: float, seq: int) -> void:
	if _last_seq < 0:
		_seq_count = 0
	else:
		var jump: int = ((seq - _last_seq + 32768) & 0xFFFF) - 32768
		if jump <= 0:
			return
		if jump > MAX_SEQ_JUMP:
			_seeded = false
			_seq_count = 0
		else:
			_seq_count += jump
	_last_seq = seq
	_has_pending = true
	_pending_blob = blob
	_pending_tick = _seq_count * BROADCAST_EVERY
	_pending_time = host_ts


# Forget every snapshot: the next one seeds him afresh.
func reset() -> void:
	_seeded = false
	_has_pending = false
	_last_seq = -1


# Him stepped to `render_t` (host time) and `drawn` filled; false when there is
# nothing to draw (no snapshot yet, a blob that does not read, the newest
# snapshot too stale), and the caller draws him as before.
func advance(render_t: float) -> bool:
	var t0: int = Time.get_ticks_usec()
	if _has_pending:
		_resolve_pending()
	if not _seeded:
		return false
	var span: float = render_t - _snap_time
	if span > MAX_SPAN_S:
		return false
	var target: int = _snap_tick + maxi(ceili(span / DT - TICK_EPSILON), 0)
	while _tick < target:
		_step()
	var t: float = (render_t - _tick_time(_tick - 1)) / DT
	if _tick > target or t >= 1.0 - TICK_EPSILON:
		drawn.copy_from(_cur)
	else:
		_blend(_prev, _cur, clampf(t, 0.0, 1.0))
	last_frame_us = Time.get_ticks_usec() - t0
	return true


func _tick_time(k: int) -> float:
	return _snap_time + float(k - _snap_tick) * DT


func _resolve_pending() -> void:
	_has_pending = false
	var k: int = _pending_tick
	_snap_tick = k
	_snap_time = _pending_time
	if not _seeded:
		_reseed(k)
		return
	var slot: int = _slot(k)
	var held: bool = k <= _tick and _hist_tick[slot] == k
	if held and _hist_blob[slot] == _pending_blob:
		confirmed += 1
		NetworkTelemetry.record_keeper_snapshot(true, 0.0)
		return
	resteps += 1
	if held:
		_mismatch.copy_from(_hist_state[slot])
	_reseed(k)
	var gap: float = -1.0
	if held and _seeded:
		gap = _box_gap(_mismatch, _cur)
		gaps += 1
		gap_sum_m += gap
		gap_max_m = maxf(gap_max_m, gap)
	NetworkTelemetry.record_keeper_snapshot(false, gap)


# Him rebuilt from the pending blob at tick `k`, and that blob kept as his own
# there.
func _reseed(k: int) -> void:
	if not keeper.apply_wire_state(_pending_blob):
		_seeded = false
		return
	_seeded = true
	_tick = k
	for i: int in HISTORY:
		if _hist_tick[i] >= k:
			_hist_tick[i] = -1
	var slot: int = _slot(k)
	_hist_tick[slot] = k
	_hist_blob[slot].clear()
	_hist_blob[slot].append_array(_pending_blob)
	keeper.fill_state(_cur)
	_hist_state[slot].copy_from(_cur)
	_prev.copy_from(_cur)
	_source.anchor(_snap_time)


# One tick: the world as he reads it, his tick, the puck's after it, and on a
# broadcast tick the snap the host makes there, kept.
func _step() -> void:
	_tick += 1
	var t: float = _tick_time(_tick)
	_fit_skaters()
	keeper.invalidate_world_view()
	_source.stage(t, _puck, _skaters)
	keeper.step_sim(DT)
	_source.settle(t, _puck, _goalie)
	_prev.copy_from(_cur)
	if _tick % BROADCAST_EVERY == 0:
		var slot: int = _slot(_tick)
		_hist_tick[slot] = _tick
		_hist_blob[slot].clear()
		keeper.append_wire_state(_hist_blob[slot])
		keeper.fill_state(_cur)
		_hist_state[slot].copy_from(_cur)
	else:
		keeper.fill_state(_cur)
	steps += 1


func _slot(k: int) -> int:
	return (k / BROADCAST_EVERY) % HISTORY


func _fit_skaters() -> void:
	var n: int = _source.skater_count()
	while _skaters.size() < n:
		var s := KeeperShadowSkater.new()
		add_child(s)
		_skaters.append(s)
	if _skaters.size() > n:
		for i: int in range(n, _skaters.size()):
			_skaters[i].queue_free()
		_skaters.resize(n)


func _blend(a: GoalieNetworkState, b: GoalieNetworkState, t: float) -> void:
	drawn.position_x = lerpf(a.position_x, b.position_x, t)
	drawn.position_z = lerpf(a.position_z, b.position_z, t)
	drawn.rotation_y = lerp_angle(a.rotation_y, b.rotation_y, t)
	drawn.state_enum = b.state_enum
	drawn.five_hole_openness = lerpf(a.five_hole_openness, b.five_hole_openness, t)
	drawn.velocity_x = lerpf(a.velocity_x, b.velocity_x, t)
	drawn.velocity_z = lerpf(a.velocity_z, b.velocity_z, t)
	drawn.pose.blend(a.pose, b.pose, t)


# The farthest any corner of any of his save boxes sits in `a` from its place
# in `b`, m.
func _box_gap(a: GoalieNetworkState, b: GoalieNetworkState) -> float:
	_gap_a.pose(a.pose)
	_gap_b.pose(b.pose)
	var root_a := Transform3D(Basis(Vector3.UP, a.rotation_y), Vector3(a.position_x, 0.0, a.position_z))
	var root_b := Transform3D(Basis(Vector3.UP, b.rotation_y), Vector3(b.position_x, 0.0, b.position_z))
	var worst: float = 0.0
	for part: int in KeeperGear.PART_COUNT:
		var h: Vector3 = KeeperGear.half_extents(part)
		var xa: Transform3D = root_a * KeeperGear.box(_gap_a, part)
		var xb: Transform3D = root_b * KeeperGear.box(_gap_b, part)
		for i: int in 8:
			var c := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
			worst = maxf(worst, (xa * c).distance_to(xb * c))
	return worst

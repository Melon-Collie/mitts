class_name NetworkTelemetry
extends RefCounted

# Owned by GameManager. Created at world spawn, freed on scene exit.
# Call sites use static methods so they're null-safe outside a game session.
static var instance: NetworkTelemetry = null

# ── Window counters (reset each second) ──────────────────────────────────────
var _world_state_count: int = 0
var _input_count: int = 0
var _reconcile_count: int = 0
var _extrapolation_count: int = 0
var _reconcile_mag_sum: float = 0.0
var _reconcile_mag_n: int = 0
var _blade_jump_count: int = 0
var _blade_jump_mag_sum: float = 0.0
var _blade_jump_n: int = 0
var _blade_reconcile_mag_sum: float = 0.0
var _blade_reconcile_n: int = 0
var _prediction_divergence_sum: float = 0.0
var _prediction_divergence_n: int = 0
var _ooo_drop_count: int = 0
var _window_timer: float = 0.0

# ── Published metrics (read by overlay) ──────────────────────────────────────
var world_state_hz: float = 0.0
var input_hz: float = 0.0
var reconcile_per_sec: float = 0.0
var reconcile_magnitude_avg: float = 0.0
var extrapolation_per_sec: float = 0.0
var buffer_depth_skater: int = 0
var buffer_depth_puck: int = 0
var buffer_depth_goalie: int = 0
var blade_jump_per_sec: float = 0.0
var blade_jump_mag_avg: float = 0.0
var blade_reconcile_mag_avg: float = 0.0
var prediction_divergence_avg: float = 0.0
var ooo_drops_per_sec: float = 0.0
var input_queue_depth_median: int = 0
var _queue_depth_window: Array[int] = []
var packet_loss_pct: float = 0.0
var jitter_p95_ms: float = 0.0
var puck_mode: String = "—"

# ── Static call sites (no-op when not in a game session) ─────────────────────
static func record_world_state() -> void:
	if instance: instance._world_state_count += 1

static func record_input_sent() -> void:
	if instance: instance._input_count += 1

const QUEUE_DEPTH_WINDOW: int = 80  # 2 s at 40 Hz

static func record_queue_depth(depth: int) -> void:
	if instance == null:
		return
	instance._queue_depth_window.append(depth)
	if instance._queue_depth_window.size() > QUEUE_DEPTH_WINDOW:
		instance._queue_depth_window.pop_front()

static func record_packet_loss(pct: float) -> void:
	if instance: instance.packet_loss_pct = pct

static func record_jitter_p95(ms: float) -> void:
	if instance: instance.jitter_p95_ms = ms

static func record_reconcile(delta_m: float) -> void:
	if instance == null:
		return
	instance._reconcile_count += 1
	instance._reconcile_mag_sum += delta_m
	instance._reconcile_mag_n += 1

# blade_jump: any physics frame where blade world pos moved > 5 cm (teleport-class).
static func record_blade_jump(magnitude: float) -> void:
	if instance == null:
		return
	instance._blade_jump_count += 1
	instance._blade_jump_mag_sum += magnitude
	instance._blade_jump_n += 1

# blade_reconcile: how much the blade world pos moved as a direct result of reconcile.
static func record_blade_reconcile(magnitude: float) -> void:
	if instance == null:
		return
	instance._blade_reconcile_mag_sum += magnitude
	instance._blade_reconcile_n += 1

# prediction_divergence: position error between client prediction and server state
# measured before the input replay, each time a reconcile fires. Average over the
# window surfaces non-determinism — a healthy connection should see near-zero drift.
static func record_prediction_divergence(meters: float) -> void:
	if instance == null:
		return
	instance._prediction_divergence_sum += meters
	instance._prediction_divergence_n += 1

# ooo_drop: a world-state packet arrived out of order and was silently discarded.
static func record_ooo_drop() -> void:
	if instance: instance._ooo_drop_count += 1

func observe_actors(skater_buf: int, puck_buf: int, goalie_buf: int, extrapolating: bool) -> void:
	buffer_depth_skater = skater_buf
	buffer_depth_puck = puck_buf
	buffer_depth_goalie = goalie_buf
	if extrapolating:
		_extrapolation_count += 1

# ── Tick — called by GameManager._process each frame ─────────────────────────
func tick(delta: float) -> void:
	_window_timer += delta
	if _window_timer < 1.0:
		return
	world_state_hz = _world_state_count / _window_timer
	input_hz = _input_count / _window_timer
	reconcile_per_sec = _reconcile_count / _window_timer
	extrapolation_per_sec = _extrapolation_count / _window_timer
	reconcile_magnitude_avg = _reconcile_mag_sum / _reconcile_mag_n if _reconcile_mag_n > 0 else 0.0
	blade_jump_per_sec = _blade_jump_count / _window_timer
	blade_jump_mag_avg = _blade_jump_mag_sum / _blade_jump_n if _blade_jump_n > 0 else 0.0
	blade_reconcile_mag_avg = _blade_reconcile_mag_sum / _blade_reconcile_n if _blade_reconcile_n > 0 else 0.0
	prediction_divergence_avg = _prediction_divergence_sum / _prediction_divergence_n if _prediction_divergence_n > 0 else 0.0
	ooo_drops_per_sec = _ooo_drop_count / _window_timer
	if not _queue_depth_window.is_empty():
		var sorted := _queue_depth_window.duplicate()
		sorted.sort()
		input_queue_depth_median = sorted[sorted.size() >> 1]
	_world_state_count = 0
	_input_count = 0
	_reconcile_count = 0
	_extrapolation_count = 0
	_reconcile_mag_sum = 0.0
	_reconcile_mag_n = 0
	_blade_jump_count = 0
	_blade_jump_mag_sum = 0.0
	_blade_jump_n = 0
	_blade_reconcile_mag_sum = 0.0
	_blade_reconcile_n = 0
	_prediction_divergence_sum = 0.0
	_prediction_divergence_n = 0
	_ooo_drop_count = 0
	_window_timer = 0.0

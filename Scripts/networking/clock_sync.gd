extends RefCounted

const INITIAL_PING_COUNT: int = 3
const INITIAL_PING_INTERVAL: float = 0.5
const ONGOING_PING_INTERVAL: float = 2.0
const SAMPLE_WINDOW: int = 8
const OUTLIER_DROP: int = 2
const OFFSET_EMA_ALPHA: float = 0.3  # after is_ready; ~3 pings to reach 66% of a new target

# Input stamps lead host-present by the one-way trip plus a fixed margin, so an
# input lands at the host before its stamp comes due. estimated_host_time() is
# the host's clock NOW, not when the input arrives — the trip is not already in
# it, and rtt/2 is the exact amount even on an asymmetric link, because the NTP
# offset's asymmetry error cancels against it.
# BATCH_INTERVAL: worst-case send delay (input stamped right after a batch went
#   out). Derived from Constants.INPUT_RATE, never hardcoded — a send-rate change
#   must not silently strand the lead at the old rate's value.
# BUFFER_TICKS: jitter cushion — the host queue depth left once the trip is paid.
#   1.5 ticks is 16.7 ms at the 90 Hz tick, sized from NetTimingHarness's
#   lateness under 10–30 ms jitter. Jitter is a time and this is counted in
#   ticks, so a tick-rate change must re-derive it to keep the cushion.
const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")
const BATCH_INTERVAL: float = 1.0 / _PhysicsConstants.INPUT_RATE
const BUFFER_TICKS: float = 1.5
const TICK_DURATION: float = 1.0 / _PhysicsConstants.PHYSICS_TICK
const INPUT_LEAD_SEC: float = BATCH_INTERVAL + BUFFER_TICKS * TICK_DURATION  # the margin: ~28 ms
# One-way trips past this are not covered: inputs from such a link land overdue
# and the host's backlog drain absorbs them. Also the bound a claim-carried lead
# is clamped to, so a modified client cannot buy a deeper rewind.
const MAX_ONE_WAY_S: float = 0.1
const MAX_INPUT_LEAD_SEC: float = INPUT_LEAD_SEC + MAX_ONE_WAY_S
# Per-tick cap on how far the lead moves when the RTT estimate changes. Stamps
# then stay within a hair of one tick apart, so a falling lead never reorders
# them and a rising one never opens a gap the host's queue starves through.
const _LEAD_SLEW_S: float = 0.0001
var _lead: float = INPUT_LEAD_SEC
var _lead_started: bool = false


# The lead for a link of this RTT. The client feeds its own estimate; the host
# feeds the ping it measures to that client, to recover the lead a remote
# stamped with where nothing on the wire carries it.
static func input_lead_for_rtt(link_rtt_ms: float) -> float:
	if not is_finite(link_rtt_ms):
		return INPUT_LEAD_SEC
	return INPUT_LEAD_SEC + clampf(link_rtt_ms / 2000.0, 0.0, MAX_ONE_WAY_S)


# One physics step: slew the lead toward this link's target. Snaps on the first
# step after sync, before any stamp has been issued against it.
func advance_input_lead() -> void:
	if not is_ready:
		return
	var target: float = input_lead_for_rtt(rtt_ms)
	_lead = move_toward(_lead, target, _LEAD_SLEW_S) if _lead_started else target
	_lead_started = true


func current_input_lead_s() -> float:
	return _lead

var is_ready: bool = false
var rtt_ms: float = 0.0
var latest_rtt_ms: float = 0.0
# Magnitude of the last post-ready EMA correction to the offset (ms) — the
# clock-quality telemetry signal.
var last_correction_ms: float = 0.0

# The NTP estimate (_offset) moves in steps, one per pong; the clock reads the
# applied offset, which follows it at OFFSET_SLEW_S of host time per second, so
# a correction runs the clock 0.5% fast or slow for a while instead of jumping
# every render instant at once — or, downward, freezing them behind the
# monotone floor. Past OFFSET_SNAP_S the error is warm-up or a changed path
# rather than drift, and crawling would leave the clock wrong for tens of
# seconds, so it snaps (the sim clock's _SIM_RESYNC_S, for the same reason).
const OFFSET_SLEW_S: float = 0.005
const OFFSET_SNAP_S: float = 0.1

var _offset: float = 0.0
var _applied_offset: float = 0.0
var _applied_started: bool = false
var _applied_at_wall: float = 0.0
var _last_estimated_time: float = 0.0
var _samples: Array = []  # Array of {rtt: float, offset: float}
var _timer: float = 0.0
var _session_start_us: int = 0

func init_session(us: int) -> void:
	_session_start_us = us

# Warm-up keeps the quick cadence until enough pongs have LANDED, not until
# enough pings were sent: the probes are unreliable, and one lost in warm-up
# would otherwise hold the clock unready for a whole ongoing interval.
func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	_timer = ONGOING_PING_INTERVAL if is_ready else INITIAL_PING_INTERVAL
	return true

func record_pong(client_send_time: float, host_time: float, recv_time: float) -> void:
	var rtt := recv_time - client_send_time
	latest_rtt_ms = rtt * 1000.0
	var offset := (host_time + rtt / 2.0) - recv_time
	_samples.append({rtt = rtt, offset = offset})
	if _samples.size() > SAMPLE_WINDOW:
		_samples.pop_front()
	_recompute()
	if not is_ready and _samples.size() >= INITIAL_PING_COUNT:
		is_ready = true

func estimated_host_time() -> float:
	return host_time_at((Time.get_ticks_usec() - _session_start_us) / 1000000.0)


# The host's clock at session-relative wall time `wall` (s), which only moves
# forward. Advances the applied offset to `wall`.
func host_time_at(wall: float) -> float:
	if not _applied_started:
		_applied_started = true
		_applied_offset = _offset
	else:
		var err: float = _offset - _applied_offset
		if absf(err) > OFFSET_SNAP_S:
			_applied_offset = _offset
		else:
			var step: float = OFFSET_SLEW_S * maxf(wall - _applied_at_wall, 0.0)
			_applied_offset += clampf(err, -step, step)
	_applied_at_wall = wall
	# Only a snap can step the clock back; the floor holds it there until real
	# time catches up rather than let a render instant repeat.
	_last_estimated_time = maxf(wall + _applied_offset, _last_estimated_time)
	return _last_estimated_time

func estimated_input_stamp_time() -> float:
	return estimated_host_time() + _lead

func _recompute() -> void:
	var sorted := _samples.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rtt < b.rtt)
	var keep_end: int = maxi(sorted.size() - OUTLIER_DROP, 1)
	var keep := sorted.slice(0, keep_end)
	var rtt_sum := 0.0
	var offset_sum := 0.0
	for s: Dictionary in keep:
		rtt_sum += s.rtt
		offset_sum += s.offset
	rtt_ms = (rtt_sum / keep.size()) * 1000.0
	var raw_offset := offset_sum / keep.size()
	if is_ready:
		var corrected := lerpf(_offset, raw_offset, OFFSET_EMA_ALPHA)
		last_correction_ms = absf(corrected - _offset) * 1000.0
		_offset = corrected
	else:
		_offset = raw_offset

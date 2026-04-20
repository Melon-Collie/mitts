extends RefCounted

const INITIAL_PING_COUNT: int = 3
const INITIAL_PING_INTERVAL: float = 0.5
const ONGOING_PING_INTERVAL: float = 5.0
const SAMPLE_WINDOW: int = 8
const OUTLIER_DROP: int = 2

var is_ready: bool = false
var rtt_ms: float = 0.0
var latest_rtt_ms: float = 0.0

var _offset: float = 0.0
var _samples: Array = []  # Array of {rtt: float, offset: float}
var _pings_sent: int = 0
var _timer: float = 0.0

func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	_timer = INITIAL_PING_INTERVAL if _pings_sent < INITIAL_PING_COUNT else ONGOING_PING_INTERVAL
	_pings_sent += 1
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
	return Time.get_ticks_msec() / 1000.0 + _offset

func _recompute() -> void:
	var sorted := _samples.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rtt < b.rtt)
	var keep := sorted.slice(0, max(sorted.size() - OUTLIER_DROP, 1))
	var rtt_sum := 0.0
	var offset_sum := 0.0
	for s: Dictionary in keep:
		rtt_sum += s.rtt
		offset_sum += s.offset
	rtt_ms = (rtt_sum / keep.size()) * 1000.0
	_offset = offset_sum / keep.size()

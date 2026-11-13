extends GutTest

# ClockSync — NTP-style RTT sampling and offset computation.
# Uses load() because ClockSync has no class_name (it's only instantiated
# inside NetworkManager).

var ClockSyncScript = load("res://Scripts/networking/clock_sync.gd")


func _make() -> RefCounted:
	return ClockSyncScript.new()


# ── Readiness ────────────────────────────────────────────────────────────────

func test_not_ready_before_initial_ping_count() -> void:
	var cs := _make()
	for _i in range(cs.INITIAL_PING_COUNT - 1):
		cs.record_pong(0.0, 0.05, 0.1)
	assert_false(cs.is_ready)


func test_ready_after_initial_ping_count() -> void:
	var cs := _make()
	for _i in range(cs.INITIAL_PING_COUNT):
		cs.record_pong(0.0, 0.05, 0.1)
	assert_true(cs.is_ready)


func test_ready_stays_true_after_more_samples() -> void:
	var cs := _make()
	for i: int in cs.INITIAL_PING_COUNT + 3:
		cs.record_pong(0.0, 0.05, 0.1)
	assert_true(cs.is_ready)


# ── RTT calculation ──────────────────────────────────────────────────────────

func test_rtt_is_recv_minus_send_time() -> void:
	var cs := _make()
	# send=1.0, recv=1.1 → 100 ms RTT
	cs.record_pong(1.0, 1.05, 1.1)
	assert_almost_eq(cs.rtt_ms, 100.0, 1.0)


func test_rtt_reflects_symmetric_delay() -> void:
	var cs := _make()
	# 50 ms one-way → 100 ms RTT
	cs.record_pong(0.0, 0.05, 0.1)
	assert_almost_eq(cs.rtt_ms, 100.0, 1.0)


# ── Outlier dropping ─────────────────────────────────────────────────────────

func test_outlier_samples_excluded_from_rtt_average() -> void:
	var cs := _make()
	# Fill the window: 6 normal samples at 50 ms, 2 outliers at 500 ms.
	# OUTLIER_DROP=2 removes the two highest, leaving only 50 ms samples.
	for i: int in 6:
		cs.record_pong(0.0, 0.025, 0.05)
	cs.record_pong(0.0, 0.25, 0.5)
	cs.record_pong(0.0, 0.25, 0.5)
	assert_almost_eq(cs.rtt_ms, 50.0, 5.0)


func test_single_sample_not_dropped() -> void:
	# With fewer samples than OUTLIER_DROP, at least one is always kept.
	var cs := _make()
	cs.record_pong(0.0, 0.1, 0.2)
	assert_almost_eq(cs.rtt_ms, 200.0, 1.0)


# ── Offset / sync ────────────────────────────────────────────────────────────

func test_zero_offset_when_clocks_are_in_sync() -> void:
	# If host_time == midpoint of the round trip, offset should be ~0.
	# send=0, recv=0.1, host_time=0.05 → rtt=0.1, offset=(0.05+0.05)-0.1=0
	var cs := _make()
	for i: int in cs.INITIAL_PING_COUNT:
		cs.record_pong(0.0, 0.05, 0.1)
	# estimated_host_time ≈ local_time + 0 ≈ local_time
	var now: float = Time.get_ticks_msec() / 1000.0
	assert_almost_eq(cs.estimated_host_time(), now, 0.05)


func test_positive_offset_when_host_is_ahead() -> void:
	# host is 10 s ahead of client; mid-trip host_time should be ~(local+10+rtt/2)
	# send=0, recv=0.1, host_time=10.05 → offset=(10.05+0.05)-0.1=10.0
	var cs := _make()
	for i: int in cs.INITIAL_PING_COUNT:
		cs.record_pong(0.0, 10.05, 0.1)
	var now: float = Time.get_ticks_msec() / 1000.0
	assert_almost_eq(cs.estimated_host_time(), now + 10.0, 0.05)


# ── Input lead: one-way trip + fixed margin ──────────────────────────────────

func _ready_clock() -> RefCounted:
	var cs := _make()
	for _i in range(cs.INITIAL_PING_COUNT):
		cs.record_pong(0.0, 0.05, 0.1)
	return cs


func test_lead_covers_the_one_way_trip() -> void:
	# estimated_host_time() is the host's clock NOW; an input lands one way
	# later. A lead short of the trip runs every input overdue at the host.
	assert_almost_eq(ClockSyncScript.input_lead_for_rtt(60.0),
			ClockSyncScript.INPUT_LEAD_SEC + 0.030, 1e-9)
	assert_almost_eq(ClockSyncScript.input_lead_for_rtt(0.0), ClockSyncScript.INPUT_LEAD_SEC, 1e-9)


func test_lead_is_bounded() -> void:
	assert_almost_eq(ClockSyncScript.input_lead_for_rtt(10000.0), ClockSyncScript.MAX_INPUT_LEAD_SEC, 1e-9)
	assert_almost_eq(ClockSyncScript.input_lead_for_rtt(NAN), ClockSyncScript.INPUT_LEAD_SEC, 1e-9,
			"a garbage RTT falls back to the margin")


func test_lead_snaps_to_the_link_on_the_first_step() -> void:
	var cs := _ready_clock()  # rtt 100 ms
	cs.advance_input_lead()
	assert_almost_eq(cs.current_input_lead_s(), ClockSyncScript.input_lead_for_rtt(cs.rtt_ms), 1e-9)


func test_lead_waits_for_the_clock() -> void:
	var cs := _make()
	cs.advance_input_lead()
	assert_almost_eq(cs.current_input_lead_s(), ClockSyncScript.INPUT_LEAD_SEC, 1e-9,
			"no RTT yet, so no trip to cover")


func test_a_changing_rtt_slews_the_lead() -> void:
	# A lead that jumped would open a gap the host queue starves through (up) or
	# fold stamps back over each other (down).
	var cs := _ready_clock()
	cs.advance_input_lead()
	var before: float = cs.current_input_lead_s()
	cs.rtt_ms = 20.0
	cs.advance_input_lead()
	assert_almost_eq(before - cs.current_input_lead_s(), cs._LEAD_SLEW_S, 1e-9)
	for _i in range(2000):
		cs.advance_input_lead()
	assert_almost_eq(cs.current_input_lead_s(), ClockSyncScript.input_lead_for_rtt(20.0), 1e-9,
			"and it arrives")


func test_stamps_stay_ordered_while_the_lead_falls() -> void:
	var cs := _ready_clock()
	cs.advance_input_lead()
	cs.rtt_ms = 0.0
	var tick: float = 1.0 / 120.0
	var prev: float = -INF
	for i in range(1000):
		cs.advance_input_lead()
		var stamp: float = float(i) * tick + cs.current_input_lead_s()
		assert_true(stamp - prev > tick * 0.9, "tick %d: stamps must keep a tick apart" % i)
		prev = stamp


func test_lead_never_touches_the_ntp_offset() -> void:
	var cs := _ready_clock()
	var offset_before: float = cs._offset
	for _i in range(100):
		cs.advance_input_lead()
	assert_eq(cs._offset, offset_before, "the lead moved the NTP offset")
	# Both terms read the wall clock, so the tolerance must clear the 1 ms
	# granularity of Time.get_ticks_msec().
	var lead_gap: float = cs.estimated_input_stamp_time() - cs.estimated_host_time()
	assert_almost_eq(lead_gap, cs.current_input_lead_s(), 2e-3,
			"stamp lead is the lead, with no offset drift folded in")


# ── Probe cadence ────────────────────────────────────────────────────────────

func _ticks_until_ping(cs: RefCounted, step: float) -> float:
	var waited: float = 0.0
	while not cs.tick(step):
		waited += step
	return waited + step


func test_lost_warmup_probes_cost_only_warmup_intervals() -> void:
	var cs := _make()
	var step: float = 0.01
	assert_true(cs.tick(step), "the first probe goes at once")
	# Four probes go out and two are lost: two pongs land.
	for i in range(3):
		_ticks_until_ping(cs, step)
		if i > 0:
			cs.record_pong(0.0, 0.05, 0.1)
	assert_false(cs.is_ready, "the control: two samples are not a clock")
	var wait: float = _ticks_until_ping(cs, step)
	assert_almost_eq(wait, cs.INITIAL_PING_INTERVAL, step * 1.5,
			"the next probe follows at the warm-up interval, not the ongoing one")


func test_a_ready_clock_probes_at_the_ongoing_interval() -> void:
	var cs := _make()
	var step: float = 0.01
	cs.tick(step)
	for _i in range(cs.INITIAL_PING_COUNT):
		cs.record_pong(0.0, 0.05, 0.1)
	assert_true(cs.is_ready)
	_ticks_until_ping(cs, step)  # the one already scheduled at the warm-up interval
	var wait: float = _ticks_until_ping(cs, step)
	assert_almost_eq(wait, cs.ONGOING_PING_INTERVAL, step * 1.5)


# A probe that waits on a retransmit, or behind other reliable traffic, carries
# that wait in its round trip and skews the offset by half of it.
func test_every_timing_probe_is_unreliable() -> void:
	var src: String = FileAccess.get_file_as_string("res://Scripts/networking/network_manager.gd")
	for probe: String in ["send_ping", "receive_pong", "host_ping", "host_pong"]:
		var at: int = src.find("\nfunc %s(" % probe)
		assert_gt(at, -1, "%s exists" % probe)
		var rpc_at: int = src.rfind("@rpc(", at)
		var annotation: String = src.substr(rpc_at, src.find("\n", rpc_at) - rpc_at)
		assert_true(annotation.contains("\"unreliable\""),
				"%s is %s" % [probe, annotation])


# ── Applied offset ───────────────────────────────────────────────────────────

const FRAME: float = 1.0 / 144.0


# Steps the clock frame by frame over `seconds` of wall time from `wall`,
# returning the smallest and largest host-time advance a frame saw, as a
# fraction of the frame.
func _frame_rates(cs: RefCounted, wall: float, seconds: float) -> Vector2:
	var prev: float = cs.host_time_at(wall)
	var lo: float = INF
	var hi: float = -INF
	var frames: int = int(seconds / FRAME)
	for i in range(1, frames + 1):
		var now: float = cs.host_time_at(wall + float(i) * FRAME)
		lo = minf(lo, (now - prev) / FRAME)
		hi = maxf(hi, (now - prev) / FRAME)
		prev = now
	return Vector2(lo, hi)


func test_a_correction_runs_the_clock_slightly_fast_instead_of_jumping() -> void:
	var cs := _ready_clock()
	cs.host_time_at(10.0)
	cs._offset += 0.02
	var rates: Vector2 = _frame_rates(cs, 10.0, 2.0)
	assert_almost_eq(rates.y, 1.0 + cs.OFFSET_SLEW_S, 1e-6, "no frame jumps past the slew")
	assert_gt(rates.x, 1.0, "and every frame is gaining on the correction")


func test_a_backward_correction_never_freezes_the_clock() -> void:
	var cs := _ready_clock()
	cs.host_time_at(10.0)
	cs._offset -= 0.02
	var rates: Vector2 = _frame_rates(cs, 10.0, 2.0)
	assert_almost_eq(rates.x, 1.0 - cs.OFFSET_SLEW_S, 1e-6,
			"each frame still advances, a little slower")


func test_a_correction_is_taken_up_whole() -> void:
	var cs := _ready_clock()
	cs.host_time_at(10.0)
	var target: float = cs._offset + 0.02
	cs._offset = target
	_frame_rates(cs, 10.0, 0.02 / cs.OFFSET_SLEW_S + 0.5)
	assert_almost_eq(cs._applied_offset, target, 1e-9)
	var settled: Vector2 = _frame_rates(cs, 20.0, 1.0)
	assert_almost_eq(settled.x, 1.0, 1e-6, "and then it runs at real time")
	assert_almost_eq(settled.y, 1.0, 1e-6)


func test_a_large_error_snaps() -> void:
	var cs := _ready_clock()
	cs.host_time_at(10.0)
	cs._offset += cs.OFFSET_SNAP_S * 2.0
	assert_almost_eq(cs.host_time_at(10.0 + FRAME), 10.0 + FRAME + cs._offset, 1e-9)


func test_a_snap_back_holds_the_clock_until_real_time_catches_up() -> void:
	var cs := _ready_clock()
	var before: float = cs.host_time_at(10.0)
	cs._offset -= cs.OFFSET_SNAP_S * 2.0
	assert_eq(cs.host_time_at(10.0 + FRAME), before, "never backward")


# A 1 ms clock rounded every reading to the millisecond: 12% of a tick of noise
# on every stamp and every packet delay. The session clock reads microseconds.
func test_the_clock_resolves_under_a_millisecond() -> void:
	var cs := _ready_clock()
	var a: float = cs.estimated_host_time()
	var b: float = a
	var start: int = Time.get_ticks_usec()
	while b == a and Time.get_ticks_usec() - start < 5000:
		b = cs.estimated_host_time()
	assert_lt(b - a, 0.0009, "consecutive distinct readings are under a millisecond apart")


# Each round trip's offset carries its own error. The clock starts on the mean
# of the best round trips of the warm-up, so errors that cancel, cancel; started
# on the single best, it kept that sample's whole error for the first seconds.
func test_the_clock_starts_on_several_round_trips() -> void:
	var cs := _make()
	var errors: Array[float] = [0.004, -0.004, 0.002, -0.002, 0.009, -0.009]
	assert_eq(errors.size(), cs.INITIAL_PING_COUNT)
	for i in range(errors.size()):
		var rtt: float = 0.05 + 0.01 * float(i)  # the last two are the outliers dropped
		cs.record_pong(0.0, rtt / 2.0 + errors[i], rtt)
	assert_true(cs.is_ready)
	assert_almost_eq(cs._offset, 0.0, 1e-9)

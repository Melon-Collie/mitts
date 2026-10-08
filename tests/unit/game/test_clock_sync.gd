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
	cs.record_pong(0.0, 0.05, 0.1)
	cs.record_pong(0.0, 0.05, 0.1)
	assert_false(cs.is_ready)


func test_ready_after_initial_ping_count() -> void:
	var cs := _make()
	cs.record_pong(0.0, 0.05, 0.1)
	cs.record_pong(0.0, 0.05, 0.1)
	cs.record_pong(0.0, 0.05, 0.1)
	assert_true(cs.is_ready)


func test_ready_stays_true_after_more_samples() -> void:
	var cs := _make()
	for i: int in 6:
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
	for i: int in 3:
		cs.record_pong(0.0, 0.05, 0.1)
	# estimated_host_time ≈ local_time + 0 ≈ local_time
	var now: float = Time.get_ticks_msec() / 1000.0
	assert_almost_eq(cs.estimated_host_time(), now, 0.05)


func test_positive_offset_when_host_is_ahead() -> void:
	# host is 10 s ahead of client; mid-trip host_time should be ~(local+10+rtt/2)
	# send=0, recv=0.1, host_time=10.05 → offset=(10.05+0.05)-0.1=10.0
	var cs := _make()
	for i: int in 3:
		cs.record_pong(0.0, 10.05, 0.1)
	var now: float = Time.get_ticks_msec() / 1000.0
	assert_almost_eq(cs.estimated_host_time(), now + 10.0, 0.05)


# ── Input lead: one-way trip + fixed margin ──────────────────────────────────

func _ready_clock() -> RefCounted:
	var cs := _make()
	cs.record_pong(0.0, 0.05, 0.1)
	cs.record_pong(0.0, 0.05, 0.1)
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

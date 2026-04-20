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

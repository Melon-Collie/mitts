extends GutTest

# #725: F3's host "Queue depth" row read input_queue_depth_median, which only a
# client's decode feeds, so every host with a peer read 0 — starving — and the
# always-on dot sat on PROBLEM. The host row reads its own peak
# (host_input_queue_depth_max), only when samples arrived, banded against the
# depth the input lead's margin holds the queue at.

const Health = NetworkDebugOverlay.Health


func test_the_margins_depth_is_healthy() -> void:
	var margin: int = roundi(NetworkManager.INPUT_LEAD_SEC * float(Constants.PHYSICS_TICK))
	assert_eq(NetworkDebugOverlay.queue_health(margin), Health.OK)
	assert_eq(NetworkDebugOverlay.queue_health(margin + 2), Health.OK, "a burst of a frame or two")


func test_starving_and_backed_up_flag() -> void:
	assert_eq(NetworkDebugOverlay.queue_health(0), Health.BAD, "empty at every sample")
	assert_eq(NetworkDebugOverlay.queue_health(8), Health.WARN, "~60 ms of extra input latency")
	assert_eq(NetworkDebugOverlay.queue_health(15), Health.BAD, "~140 ms")


func test_the_host_row_reads_the_hosts_own_counter() -> void:
	var src: String = FileAccess.get_file_as_string("res://Scripts/ui/network_debug_overlay.gd")
	var start: int = src.find("func _render_host(")
	var body: String = src.substr(start, src.find("\nfunc ", start + 1) - start)
	assert_false(body.contains("input_queue_depth_median"),
			"the median is the client's echo; it folds 0 on a host")
	assert_true(body.contains("host_input_queue_depth_samples"),
			"the row shows only when this window has samples")


func test_samples_are_counted_with_the_peak() -> void:
	var t := NetworkTelemetry.new()
	var was: NetworkTelemetry = NetworkTelemetry.instance
	NetworkTelemetry.instance = t
	NetworkTelemetry.record_host_queue_depth(2)
	NetworkTelemetry.record_host_queue_depth(4)
	assert_eq(t._host_queue_depth_window_samples, 2)
	assert_eq(t._host_queue_depth_window_max, 4)
	NetworkTelemetry.instance = was

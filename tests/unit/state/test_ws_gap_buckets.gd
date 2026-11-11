extends GutTest

# The F3 packet-spacing histogram is read by its shape: mass in the on-time
# bucket is a healthy link, mass at both ends is clumping. Its edges are laid
# round the broadcast interval, so a broadcast-rate change that moves the
# healthy gap out of the on-time bucket must fail here rather than quietly read
# as late packets.

const INTERVAL_MS: float = 1000.0 / Constants.STATE_RATE


func test_the_healthy_gap_lands_on_time() -> void:
	assert_eq(NetworkTelemetry.ws_gap_bucket(INTERVAL_MS), NetworkTelemetry.WS_GAP_ON_TIME_BUCKET)


func test_a_little_jitter_stays_on_time() -> void:
	assert_eq(NetworkTelemetry.ws_gap_bucket(INTERVAL_MS - 4.0), NetworkTelemetry.WS_GAP_ON_TIME_BUCKET)
	assert_eq(NetworkTelemetry.ws_gap_bucket(INTERVAL_MS + 4.0), NetworkTelemetry.WS_GAP_ON_TIME_BUCKET)


func test_a_clump_lands_in_the_first_bucket() -> void:
	assert_eq(NetworkTelemetry.ws_gap_bucket(1.0), 0)


func test_one_missed_broadcast_is_past_late() -> void:
	assert_gt(NetworkTelemetry.ws_gap_bucket(2.0 * INTERVAL_MS), NetworkTelemetry.WS_GAP_ON_TIME_BUCKET + 1)


func test_every_bucket_has_a_label() -> void:
	assert_eq(NetworkTelemetry.WS_GAP_LABELS.size(), NetworkTelemetry.WS_GAP_EDGES_MS.size() + 1)


# The interp-depth readout beside the histogram: the session folds it as a
# minimum, so the per-frame value must be the shallowest remote, not whichever
# was iterated last.
func test_interp_depth_reports_the_shallowest() -> void:
	var d: int = -1
	for depth: int in [4, 1, 3]:
		d = NetworkTelemetry.shallowest_depth(d, depth)
	assert_eq(d, 1, "the remote closest to running dry")
	assert_eq(NetworkTelemetry.shallowest_depth(-1, 5), 5)

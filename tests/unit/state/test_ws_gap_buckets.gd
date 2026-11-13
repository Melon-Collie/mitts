extends GutTest

# The F3 packet-spacing histogram is read by its shape: mass in the on-time
# bucket is a healthy link, mass at both ends is clumping. Its edges are laid
# round the broadcast interval, so a broadcast-rate change that moves the
# healthy gap out of the on-time bucket must fail here rather than quietly read
# as late packets.

const INTERVAL_MS: float = 1000.0 / Constants.STATE_RATE
const NetworkManagerScript: GDScript = preload("res://Scripts/networking/network_manager.gd")


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


# A goal replay or an intermission stops the broadcast for seconds. That gap is
# a designed pause, not the link's cadence: on the host it saturated the
# interval p95, on a client it put seconds of "jitter" in the window and the
# histogram's overflow bucket after every pause.
func test_a_designed_pause_is_not_a_cadence_sample() -> void:
	assert_true(NetworkManagerScript.is_cadence_gap(INTERVAL_MS / 1000.0))
	assert_true(NetworkManagerScript.is_cadence_gap(0.5), "a half-second stall is the link's")
	assert_false(NetworkManagerScript.is_cadence_gap(4.0))


func test_both_ends_skip_a_designed_pause() -> void:
	var src: String = FileAccess.get_file_as_string("res://Scripts/networking/network_manager.gd")
	for fn: String in ["try_broadcast", "_apply_world_state"]:
		var at: int = src.find("\nfunc %s(" % fn)
		var body: String = src.substr(at, src.find("\nfunc ", at + 1) - at)
		assert_true(body.contains("is_cadence_gap("), "%s records a pause as cadence" % fn)

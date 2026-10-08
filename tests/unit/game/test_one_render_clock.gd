extends GutTest

# One render clock: everything a client draws, and every host rewind that judges
# what it drew, sits on the instant its own predicted body occupies —
# host-present + its input lead. Each consumer derives that instant by its own
# path, so a change to one path (a new lead source, a different delay clamp, a
# different stamp) leaves the others behind with nothing failing. That is how
# the release seed ended up a lead off the puck it seeded.
#
# Every row below is computed by the code path that consumer actually runs and
# compared against the local body's instant, across links from LAN to past the
# one-way cap.

const ClockSyncScript: GDScript = preload("res://Scripts/networking/clock_sync.gd")

const H: float = 100.0  # the claim/render stamp: estimated_host_time() that frame
const RTTS_MS: Array[float] = [10.0, 60.0, 150.0, 400.0]
const INTERP_DELAYS_S: Array[float] = [0.03, 0.08, 0.15]
const TICK: float = 1.0 / float(Constants.PHYSICS_TICK)


func _lead_ms(rtt_ms: float) -> float:
	return ClockSyncScript.input_lead_for_rtt(rtt_ms) * 1000.0


# The local body: inputs are applied immediately and stamped a lead ahead, so the
# body on screen is at H + lead.
func _body_instant(rtt_ms: float) -> float:
	return H + LagCompRewind.clamped_lead_s(_lead_ms(rtt_ms))


func test_the_local_stamp_lead_is_the_lead_every_consumer_reads() -> void:
	for rtt: float in RTTS_MS:
		var cs: RefCounted = ClockSyncScript.new()
		cs.record_pong(0.0, 0.05, 0.1)
		cs.record_pong(0.0, 0.05, 0.1)
		cs.record_pong(0.0, 0.05, 0.1)
		cs.rtt_ms = rtt
		cs.advance_input_lead()
		assert_almost_eq(cs.current_input_lead_s(),
				LagCompRewind.clamped_lead_s(_lead_ms(rtt)), 1e-9,
				"rtt %d: the lead a claim carries must survive the host's clamp unchanged" % int(rtt))


func test_remote_skaters_render_on_the_body_instant() -> void:
	# RemoteController._interpolate: interpolated past (H - d), intent-integrated
	# forward_predict_ticks toward present.
	for rtt: float in RTTS_MS:
		for d: float in INTERP_DELAYS_S:
			var lead: float = LagCompRewind.clamped_lead_s(_lead_ms(rtt))
			var ticks: int = LagCompRewind.forward_predict_ticks(
					Constants.REMOTE_FORWARD_PREDICT_FRACTION, d, lead)
			assert_almost_eq((H - d) + float(ticks) * TICK, _body_instant(rtt), TICK * 0.5,
					"rtt %d, delay %d ms" % [int(rtt), int(d * 1000.0)])


func test_the_host_rewinds_a_remote_to_where_the_claimant_drew_it() -> void:
	# Hit / poke / stick-lift: remote_view_time, then forward_predict_skater's depth
	# from the claim-carried delay and lead.
	for rtt: float in RTTS_MS:
		for d: float in INTERP_DELAYS_S:
			var ticks: int = LagCompRewind.forward_predict_ticks(
					Constants.REMOTE_FORWARD_PREDICT_FRACTION, d,
					LagCompRewind.clamped_lead_s(_lead_ms(rtt)))
			var rewound: float = LagCompRewind.remote_view_time(H, d * 1000.0) + float(ticks) * TICK
			assert_almost_eq(rewound, _body_instant(rtt), TICK * 0.5,
					"rtt %d, delay %d ms" % [int(rtt), int(d * 1000.0)])


func test_the_host_judges_the_claimant_s_own_body_at_the_body_instant() -> void:
	for rtt: float in RTTS_MS:
		assert_almost_eq(LagCompRewind.self_view_time(H, _lead_ms(rtt)), _body_instant(rtt), 1e-9,
				"rtt %d" % int(rtt))


func test_the_host_judges_the_loose_puck_at_the_body_instant() -> void:
	for rtt: float in RTTS_MS:
		assert_almost_eq(LagCompRewind.puck_view_time(H, _lead_ms(rtt)), _body_instant(rtt), 1e-9,
				"rtt %d" % int(rtt))


func test_the_client_draws_the_loose_puck_at_the_body_instant() -> void:
	# PuckController reads the live clock, so this row is pinned at whatever link
	# the suite's NetworkManager reports — it is the same expression the remote
	# render and every claim build their lead from.
	var pc := PuckController.new()
	autofree(pc)
	assert_almost_eq(pc._render_instant(),
			NetworkManager.estimated_host_time()
					+ LagCompRewind.clamped_lead_s(NetworkManager.get_input_lead_ms()), 1e-9)

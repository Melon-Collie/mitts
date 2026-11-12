extends GutTest

# HitClaimResolver — throttle bookkeeping and rematch reset.
# `notify_local_hit` and `receive_claim` happy paths need a real Skater node
# (for victim → peer_id resolution) and a populated StateBufferManager
# (for rewind), neither of which is reasonable to stand up here. We cover the
# state the resolver owns directly: the throttle dict and reset_throttle().

var resolver: HitClaimResolver
var registry: PlayerRegistry
var hit_tracker: HitTracker


func before_each() -> void:
	registry = PlayerRegistry.new()
	hit_tracker = HitTracker.new()
	hit_tracker.setup(registry)
	resolver = HitClaimResolver.new()
	# The puck_controller getter isn't needed for the state-only branches.
	resolver.setup(registry, null, hit_tracker, Callable())


# ── Throttle state ────────────────────────────────────────────────────────────

func test_throttle_dict_starts_empty() -> void:
	assert_eq(resolver._last_claim_sent.size(), 0)


func test_reset_throttle_clears_dict() -> void:
	resolver._last_claim_sent["1:2"] = 100.0
	resolver._last_claim_sent["1:3"] = 100.0
	resolver.reset_throttle()
	assert_eq(resolver._last_claim_sent.size(), 0)


# ── receive_claim() early-return branches ─────────────────────────────────────

func test_receive_claim_with_null_state_buffer_is_noop() -> void:
	# state_buffer is null → early return without crash. The credit path also
	# wouldn't fire, but the lighter assertion is that nothing throws.
	resolver.receive_claim(1, 2, 0.0, 75.0, 25.0)
	assert_eq(hit_tracker._last_hit_time.size(), 0)


# ── contact range ─────────────────────────────────────────────────────────────
# The rewound bodies must be about touching: a modified client committed and
# closing must not be credited from across a gap it never closed.

const RADII_SUM: float = 0.7


func test_touching_bodies_are_in_range() -> void:
	assert_true(HitClaimResolver.in_contact_range(
			Vector3.ZERO, Vector3(RADII_SUM, 0.0, 0.0), RADII_SUM))


func test_the_reconstruction_slack_is_tolerated() -> void:
	var at: Vector3 = Vector3(0.0, 0.0, RADII_SUM + HitClaimResolver.CONTACT_SLACK_M - 0.01)
	assert_true(HitClaimResolver.in_contact_range(Vector3.ZERO, at, RADII_SUM))


func test_a_body_two_metres_off_was_never_touched() -> void:
	assert_false(HitClaimResolver.in_contact_range(
			Vector3.ZERO, Vector3(2.0, 0.0, 0.0), RADII_SUM),
			"two metres between centres is over a metre of open ice")


func test_the_slack_stays_well_inside_a_body_width() -> void:
	assert_lt(HitClaimResolver.CONTACT_SLACK_M, RADII_SUM,
			"the slack is reconstruction error, not reach")


func test_height_does_not_count() -> void:
	assert_true(HitClaimResolver.in_contact_range(
			Vector3.ZERO, Vector3(RADII_SUM, 3.0, 0.0), RADII_SUM))

extends GutTest

# SkaterCollisionRules — analytic disc-vs-disc resolution (the body-check contact
# core). Pure math: positional separation + a single no-bounce inelastic impulse.

const R := 0.5   # test disc radius; two at 0.5 overlap when centers are < 1.0 apart


func _res() -> SkaterCollisionRules.Result:
	return SkaterCollisionRules.Result.new()


# ── no contact ────────────────────────────────────────────────────────────────

func test_no_overlap_does_nothing() -> void:
	var out := _res()
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3.ZERO, 80.0, R,
		Vector3(2.0, 0.0, 0.0), Vector3.ZERO, 80.0, R,
		1.0)
	assert_false(out.overlapping, "discs 2 m apart are not overlapping")
	assert_false(out.impulse_applied)
	assert_eq(out.sep_a, Vector3.ZERO)
	assert_eq(out.dvel_b, Vector3.ZERO)


# ── separation ────────────────────────────────────────────────────────────────

func test_overlap_separates_along_axis() -> void:
	var out := _res()
	# Centers 0.6 apart on X, radii sum 1.0 → overlap 0.4. Stationary → sep only.
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3.ZERO, 80.0, R,
		Vector3(0.6, 0.0, 0.0), Vector3.ZERO, 80.0, R,
		1.0)
	assert_true(out.overlapping)
	assert_false(out.impulse_applied, "no closing velocity → no hit impulse")
	# A pushed -X, B pushed +X, equal masses → half the overlap each.
	assert_almost_eq(out.sep_a.x, -0.2, 0.0001)
	assert_almost_eq(out.sep_b.x, 0.2, 0.0001)
	# Full overlap resolved.
	assert_almost_eq((out.sep_b - out.sep_a).x, 0.4, 0.0001)


func test_lighter_body_pushed_more_on_separation() -> void:
	var out := _res()
	# A heavy (120), B light (60). Overlap 0.4. B should move ~2x A.
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3.ZERO, 120.0, R,
		Vector3(0.6, 0.0, 0.0), Vector3.ZERO, 60.0, R,
		1.0)
	# inv_a=1/120, inv_b=1/60 → B's share is 2x A's.
	assert_almost_eq(absf(out.sep_b.x) / absf(out.sep_a.x), 2.0, 0.001)
	assert_almost_eq((out.sep_b - out.sep_a).x, 0.4, 0.0001)


# ── inelastic impulse ─────────────────────────────────────────────────────────

func test_closing_launches_victim_and_slows_attacker() -> void:
	var out := _res()
	# A closing on B at 6 m/s along +X, overlapping, equal masses, full transfer.
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 80.0, R,
		Vector3(0.8, 0.0, 0.0), Vector3.ZERO, 80.0, R,
		1.0)
	assert_true(out.impulse_applied)
	assert_almost_eq(out.closing_speed, 6.0, 0.0001)
	# Equal mass, transfer 1 → converge to shared 3 m/s: A loses 3, B gains 3.
	assert_almost_eq(out.dvel_a.x, -3.0, 0.001, "attacker decelerates by half the closing")
	assert_almost_eq(out.dvel_b.x, 3.0, 0.001, "victim launched by half the closing")


func test_no_bounce_attacker_never_reverses() -> void:
	var out := _res()
	# Whatever the transfer, the attacker's post-impulse velocity along the axis
	# must not go negative (a reversal would be a pinball bounce).
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3(5.0, 0.0, 0.0), 80.0, R,
		Vector3(0.8, 0.0, 0.0), Vector3.ZERO, 80.0, R,
		1.0)
	var post_a: float = 5.0 + out.dvel_a.x
	assert_true(post_a >= 0.0, "attacker must not be pushed backward past a stop")
	# At equal mass / full transfer it converges to the shared speed (5+0)/2, not below.
	assert_almost_eq(post_a, 2.5, 0.001)


func test_heavy_attacker_drives_through_light_victim() -> void:
	var out := _res()
	# Heavy A (150) closing on light B (55) at 6 m/s, full transfer.
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 150.0, R,
		Vector3(0.8, 0.0, 0.0), Vector3.ZERO, 55.0, R,
		1.0)
	# Attacker barely slows (drive-through), victim is launched hard.
	assert_true(absf(out.dvel_a.x) < absf(out.dvel_b.x),
		"heavy attacker changes velocity less than the light victim")
	# Victim Δv ≈ closing × m_a/(m_a+m_b) = 6 × 150/205 ≈ 4.39
	assert_almost_eq(out.dvel_b.x, 6.0 * 150.0 / 205.0, 0.01)
	# Attacker Δv ≈ -closing × m_b/(m_a+m_b) = -6 × 55/205 ≈ -1.61
	assert_almost_eq(out.dvel_a.x, -6.0 * 55.0 / 205.0, 0.01)


func test_victim_kick_matches_what_resolve_delivers() -> void:
	# victim_kick is the resolver's OWN delivery function, exposed so
	# predictors (AIBodyCheck's commit gate) share the exact formula. Pin the
	# consistency contract: for a live contact, resolve's applied |dvel_b|
	# equals victim_kick at the same closing speed, masses, and transfer —
	# if the delivery model ever changes, this and the AI's prediction move
	# in the same edit or fail here.
	var out := _res()
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3(7.0, 0.0, 0.0), 1.18, R,
		Vector3(0.8, 0.0, 0.0), Vector3(-2.0, 0.0, 0.0), 0.9, R, 0.61)
	assert_true(out.impulse_applied)
	assert_almost_eq(out.dvel_b.length(),
			SkaterCollisionRules.victim_kick(
					out.closing_speed, 1.18, 0.9, 0.61),
			0.0001)


func test_transfer_scales_impulse_linearly() -> void:
	var full := _res()
	var half := _res()
	SkaterCollisionRules.resolve(full,
		Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 80.0, R,
		Vector3(0.8, 0.0, 0.0), Vector3.ZERO, 80.0, R, 1.0)
	SkaterCollisionRules.resolve(half,
		Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 80.0, R,
		Vector3(0.8, 0.0, 0.0), Vector3.ZERO, 80.0, R, 0.5)
	# The uncommitted (half-transfer) hit delivers exactly half the knockback...
	assert_almost_eq(half.dvel_b.x, full.dvel_b.x * 0.5, 0.001)
	# ...and separation is unaffected by transfer (positional, always full).
	assert_almost_eq(half.sep_a.x, full.sep_a.x, 0.0001)


func test_low_transfer_barely_slows_attacker() -> void:
	var out := _res()
	# The "skate into someone uncommitted" case: small transfer → the attacker
	# keeps most of its speed instead of dead-stopping.
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 80.0, R,
		Vector3(0.8, 0.0, 0.0), Vector3.ZERO, 80.0, R, 0.2)
	var post_a: float = 6.0 + out.dvel_a.x
	assert_true(post_a > 5.0, "uncommitted contact glances off, keeping most speed")


# ── direction / non-contact velocity ──────────────────────────────────────────

func test_separating_pair_gets_no_impulse() -> void:
	var out := _res()
	# Overlapping but B moving away faster than A → not closing.
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 80.0, R,
		Vector3(0.8, 0.0, 0.0), Vector3(4.0, 0.0, 0.0), 80.0, R, 1.0)
	assert_true(out.overlapping, "still separated positionally")
	assert_false(out.impulse_applied, "moving apart → no hit impulse")
	assert_true(out.closing_speed < 0.0)


func test_impulse_is_along_center_axis_not_velocity() -> void:
	var out := _res()
	# A moving purely +X but offset on Z so the contact axis is diagonal. The
	# knockback must point along the center-to-center axis, not the velocity —
	# this is what kills the frame-to-frame normal jitter of the old resolver.
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 80.0, R,
		Vector3(0.6, 0.0, 0.6), Vector3.ZERO, 80.0, R, 1.0)
	# Axis is (0.6, 0, 0.6) normalized → equal X and Z components on the victim.
	assert_almost_eq(out.dvel_b.x, out.dvel_b.z, 0.001,
		"knockback follows the center axis (equal X/Z here), not the pure-X velocity")


# ── determinism guard ─────────────────────────────────────────────────────────

func test_coincident_centers_no_nan() -> void:
	var out := _res()
	SkaterCollisionRules.resolve(out,
		Vector3.ZERO, Vector3.ZERO, 80.0, R,
		Vector3.ZERO, Vector3.ZERO, 80.0, R, 1.0)
	assert_true(out.overlapping)
	assert_true(out.sep_a.is_finite() and out.sep_b.is_finite(),
		"coincident centers must resolve to a finite deterministic push, not NaN")
	assert_false(is_nan(out.sep_a.x))


# ── contact_transfer ──────────────────────────────────────────────────────────
# The one delivery rule the resolver, the reconcile replay and the strip read.

const T: float = 0.65
const BRACE: float = 0.4
const PASSIVE: float = 0.3


# A committed checker is inside his drive unless `driving` says otherwise.
func _ct(a_committed: bool, a_puck: bool, b_committed: bool, b_puck: bool,
		driving: bool = true) -> float:
	return SkaterCollisionRules.contact_transfer(T, a_committed, driving, a_puck, BRACE,
			T, b_committed, driving, b_puck, BRACE, PASSIVE)


func test_contact_transfer_is_the_same_from_either_side() -> void:
	for a_c: bool in [false, true]:
		for a_p: bool in [false, true]:
			for b_c: bool in [false, true]:
				for b_p: bool in [false, true]:
					if a_p and b_p:
						continue
					assert_almost_eq(_ct(a_c, a_p, b_c, b_p), _ct(b_c, b_p, a_c, a_p), 1e-6,
							"A %s/%s, B %s/%s" % [a_c, a_p, b_c, b_p])


func test_a_committed_checker_delivers_whoever_is_faster() -> void:
	assert_almost_eq(_ct(true, false, false, false), T, 1e-6)
	assert_almost_eq(_ct(false, true, true, false), T, 1e-6, "a carrier skating into a set defender")


func test_a_checker_past_his_drive_delivers_the_held_share() -> void:
	assert_almost_eq(_ct(true, false, false, false, false), T * CheckDriveRules.HELD_SHARE, 1e-6)
	assert_almost_eq(_ct(false, true, true, false, false), T * CheckDriveRules.HELD_SHARE, 1e-6)
	assert_gt(_ct(true, false, false, false, false), _ct(false, false, false, false, false),
			"still more than the bump")


func test_a_drive_kicks_the_other_body_and_never_its_thrower() -> void:
	var out := SkaterCollisionRules.Result.new()
	var plain := SkaterCollisionRules.Result.new()
	var a_pos := Vector3.ZERO
	var b_pos := Vector3(0.6, 0.0, 0.0)
	var a_vel := Vector3(3.0, 0.0, 0.0)
	SkaterCollisionRules.resolve(plain, a_pos, a_vel, 1.0, 0.35, b_pos, Vector3.ZERO, 1.0,
			0.35, T)
	SkaterCollisionRules.resolve(out, a_pos, a_vel, 1.0, 0.35, b_pos, Vector3.ZERO, 1.0,
			0.35, T, 0.8, 0.0)
	assert_almost_eq(out.dvel_b.x, plain.dvel_b.x + 0.8, 1e-5, "on top of the closing share")
	assert_almost_eq(out.dvel_a.x, plain.dvel_a.x, 1e-6, "his skates take the reaction")
	assert_almost_eq(out.kick_on_b, 0.8, 1e-6)


# Thrown into a man he is leaning on, where the closing speed is a stride's
# worth a tick, the kick is all of the hit: a shove.
func test_a_drive_into_a_man_he_leans_on_is_a_shove() -> void:
	var out := SkaterCollisionRules.Result.new()
	SkaterCollisionRules.resolve(out, Vector3.ZERO, Vector3(0.1, 0.0, 0.0), 1.0, 0.35,
			Vector3(0.6, 0.0, 0.0), Vector3.ZERO, 1.0, 0.35, T, 0.8, 0.0)
	assert_almost_eq(out.kick_on_b, 0.8, 1e-6)
	assert_gt(out.dvel_b.x, 0.8)


func test_no_drive_kick_without_a_closing_contact() -> void:
	var out := SkaterCollisionRules.Result.new()
	SkaterCollisionRules.resolve(out, Vector3.ZERO, Vector3(-1.0, 0.0, 0.0), 1.0, 0.35,
			Vector3(0.6, 0.0, 0.0), Vector3.ZERO, 1.0, 0.35, T, 0.8, 0.8)
	assert_eq(out.dvel_b, Vector3.ZERO)
	assert_eq(out.dvel_a, Vector3.ZERO)


func test_only_a_driving_checker_kicks_and_a_braced_carrier_takes_less() -> void:
	var kick: float = SkaterCollisionRules.drive_kick(true, true, false, 10.0, 1.0, 1.0,
			false, BRACE)
	assert_almost_eq(kick, CheckDriveRules.kick_dv(10.0, 1.0, 1.0), 1e-6)
	assert_eq(SkaterCollisionRules.drive_kick(false, true, false, 10.0, 1.0, 1.0, false, BRACE),
			0.0, "past his drive")
	assert_eq(SkaterCollisionRules.drive_kick(true, true, true, 10.0, 1.0, 1.0, false, BRACE),
			0.0, "a carrier's Ctrl is the brace")
	assert_almost_eq(SkaterCollisionRules.drive_kick(true, true, false, 10.0, 1.0, 1.0, true,
			BRACE), kick * BRACE, 1e-6)


func test_with_nobody_committed_it_is_the_passive_bump() -> void:
	assert_almost_eq(_ct(false, false, false, true), T * PASSIVE, 1e-6)


func test_a_carrier_holding_ctrl_braces_and_never_delivers() -> void:
	assert_almost_eq(_ct(true, false, true, true), T * BRACE, 1e-6, "checked, braced")
	assert_almost_eq(_ct(true, true, false, false), T * PASSIVE * BRACE, 1e-6,
			"bulldozing while braced lands less than the bump")

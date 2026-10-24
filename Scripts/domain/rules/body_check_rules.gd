class_name BodyCheckRules

# Pure math for the "stagger" debuff a body check inflicts on its victim: a
# temporary thrust and edge-grip penalty, scaled by how hard the hit landed. Kept
# pure (static, no engine state) so it unit-tests without a live skater and —
# like SkaterMovementRules — survives client-side prediction + reconcile: the
# victim's stagger_timer is replicated, snapped to the host baseline at replay
# start, and decays deterministically.
#
# "How hard" is the victim's transfer-impulse magnitude — the m/s velocity delta
# the hit imparts (= approach x weight_ratio x effective_transfer, so both
# bodies' mass and the closing speed feed it) — normalized to 0..1 between
# min_impulse (below which a bump inflicts nothing) and ref_impulse (a
# full-strength check).
#
# One float, stagger_timer (seconds remaining), encodes BOTH the penalty depth
# and the recovery window: a harder hit sets a longer timer, and the per-tick
# penalties are proportional to the timer that remains, so depth and duration
# scale together off a single replicated value and ease back as it decays.
#
# The timer has two bands. Up to max_stagger_seconds it is the stagger. A full
# check (ref_impulse and up) ROCKS its man instead: the timer starts above that
# floor, and while it stays there he is rocked — his stick jarred off the ice,
# his stance and commit gone, his edges deeper gone — before the full stagger's
# tail eases out beneath it.

class Config:
	# Defaults mirror SkaterController's @export tunables (the authoritative
	# source). The stagger band is tuned to the inelastic magnitudes: ref_impulse
	# equals the puck-strip threshold (1.35), so a full-strength check is exactly
	# a puck-dislodging check — landing at ~4 m/s closing for a medium build (0.65
	# transfer), ~3.4 for a heavy one ("skate into them with some pace", not a
	# full-speed-only collision). See the ladder derivation on
	# SkaterController.stagger_min_impulse.
	var min_impulse: float = 0.6          # m/s victim velocity delta below which no debuff lands
	var ref_impulse: float = 1.35         # m/s delta treated as a full-strength check (== puck-strip threshold)
	var max_stagger_seconds: float = 1.0  # recovery window of a full-strength check
	var max_thrust_penalty: float = 0.5   # peak thrust reduction (fraction) at full stagger
	# Peak edge-grip reduction (fraction) at full stagger. Thrust alone barely
	# registers on a skater already at speed — the stride is power-limited there
	# and the glide is long — so a rattled skater is also off his edges.
	var max_grip_penalty: float = 0.4
	# The rocked band, above max_stagger_seconds: rocked_min_seconds long at
	# ref_impulse, rocked_max_seconds at rocked_ref_impulse (a full-speed
	# committed check at equal builds) and beyond.
	var rocked_ref_impulse: float = 2.6
	var rocked_min_seconds: float = 0.5
	var rocked_max_seconds: float = 0.8
	# Peak edge-grip reduction at the top of the rocked band: off his edges, he
	# glides along the hit rather than cutting out of it.
	var rocked_grip_penalty: float = 0.75
	# Knockdown: a hit that beats his balance (BodyBalanceRules.overshoot over 1)
	# knocks him off his skates — movement locked, slides and bleeds speed, can't
	# touch the puck. He falls to the ice (KnockdownFallRules.first_impact_time),
	# lies there from min_lie_seconds just past his balance to max_lie_seconds at
	# knockdown_ref_overshoot and beyond, then gets up; the caller adds the fall
	# and the get-up, so the get-up never starts before he is down.
	var knockdown_ref_overshoot: float = 1.7
	var min_lie_seconds: float = 0.15
	var max_lie_seconds: float = 0.7


# 0..1 hit hardness from the victim impulse magnitude.
static func intensity(impulse_mag: float, cfg: Config) -> float:
	if cfg.ref_impulse <= cfg.min_impulse:
		return 0.0
	return clampf((impulse_mag - cfg.min_impulse) / (cfg.ref_impulse - cfg.min_impulse), 0.0, 1.0)


# Seconds of stagger a fresh hit adds (0 below min_impulse): up to the stagger's
# max, and a full check that leaves him on his feet past it into the rocked
# band. A hit that `knocked_down` takes no rocked band: he is going down, and
# the timer runs out under the knockdown's own. Callers take the max with any
# in-flight timer so a weaker follow-up can't shorten an existing stagger.
static func stagger_seconds_from_impulse(impulse_mag: float, cfg: Config,
		knocked_down: bool = false) -> float:
	var stagger: float = intensity(impulse_mag, cfg) * cfg.max_stagger_seconds
	if impulse_mag < cfg.ref_impulse or knocked_down:
		return stagger
	var span: float = maxf(cfg.rocked_ref_impulse - cfg.ref_impulse, 0.001)
	var t: float = clampf((impulse_mag - cfg.ref_impulse) / span, 0.0, 1.0)
	return stagger + lerpf(cfg.rocked_min_seconds, cfg.rocked_max_seconds, t)


static func is_rocked(stagger_timer: float, cfg: Config) -> bool:
	return stagger_timer > cfg.max_stagger_seconds


# How far into the rocked band the timer sits, 0..1 of rocked_max_seconds: the
# depth of the rocked grip and pose, easing to 0 as he comes out of it.
static func rocked_share(stagger_timer: float, cfg: Config) -> float:
	if cfg.rocked_max_seconds <= 0.0:
		return 0.0
	return clampf((stagger_timer - cfg.max_stagger_seconds) / cfg.rocked_max_seconds, 0.0, 1.0)


# Seconds he lies on the ice from how far past his balance the hit landed
# (BodyBalanceRules.overshoot, over 1 for a knockdown at all): min_lie_seconds
# just past it, up to max_lie_seconds at knockdown_ref_overshoot (clamped).
static func lie_seconds_from_overshoot(overshoot: float, cfg: Config) -> float:
	var span: float = maxf(cfg.knockdown_ref_overshoot - 1.0, 0.001)
	var t: float = clampf((overshoot - 1.0) / span, 0.0, 1.0)
	return lerpf(cfg.min_lie_seconds, cfg.max_lie_seconds, t)


# Thrust multiplier (<= 1.0) for the stagger remaining this tick. The penalty is
# proportional to the fraction of a full-strength window still on the clock, so a
# harder hit (longer timer) both starts deeper and takes longer to ease back to
# full thrust as stagger_timer decays to 0.
static func thrust_mult(stagger_timer: float, cfg: Config) -> float:
	return 1.0 - _stagger_frac(stagger_timer, cfg) * cfg.max_thrust_penalty


# Edge-grip multiplier (<= 1.0) for the stagger remaining this tick — the same
# shape as thrust_mult, deepening on through the rocked band, so it is
# continuous as he comes out of it. NativeSkaterMovement.integrate_forward
# carries the same formula.
static func grip_mult(stagger_timer: float, cfg: Config) -> float:
	return 1.0 - _stagger_frac(stagger_timer, cfg) * cfg.max_grip_penalty \
			- rocked_share(stagger_timer, cfg) * (cfg.rocked_grip_penalty - cfg.max_grip_penalty)


static func _stagger_frac(stagger_timer: float, cfg: Config) -> float:
	if stagger_timer <= 0.0 or cfg.max_stagger_seconds <= 0.0:
		return 0.0
	return clampf(stagger_timer / cfg.max_stagger_seconds, 0.0, 1.0)


# The victim transfer-impulse the puck-strip / pickup-denial decision keys off —
# the SAME "how hard did it land on the victim" magnitude the stagger uses (the
# actually-applied |Δv|), so the contact's transfer, both skaters' mass, and the
# closing speed all decide whether the puck comes loose. A glancing shove barely
# jars it; an enforcer strips it clean.
#
# Reconstructed from impact_force = checker_weight × approach (what the
# body_checked_player signal carries): closing = impact_force / checker_weight,
# then the delivery is the collision resolver's OWN function
# (SkaterCollisionRules.victim_kick — the exact inelastic reduced-mass kick
# resolve() applies), at the contact's transfer (contact_transfer, the brace in
# it). Delegating rather than mirroring is the point: a reconstruction of the
# kick here goes silently stale the moment the resolver changes, while
# delegation propagates a delivery-model change in the same edit.
# test_body_check_rules locks the identity against a live resolve() contact.
static func puck_strip_impulse(
		impact_force: float,
		checker_weight: float,
		transfer: float,
		victim_weight: float) -> float:
	return SkaterCollisionRules.victim_kick(
			impact_force / maxf(checker_weight, 0.001),
			checker_weight, victim_weight, transfer)

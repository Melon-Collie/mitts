class_name SkaterCollisionRules

# Analytic disc-vs-disc resolution for skater bodies on the XZ plane. This is the
# body-check contact core, and it is the ONLY thing separating two skaters —
# nothing collides through the physics server. Two clean pieces —
#
#   1. Positional separation: overlapping discs are pushed apart along the
#      center-to-center axis, split by inverse mass (the lighter body moves more).
#      Always applied when overlapping, independent of velocity, so bodies never
#      interpenetrate and never dead-stop.
#
#   2. A single INELASTIC impulse along that same axis, applied only when the
#      bodies are closing. There is deliberately NO restitution/(1+e) term: the
#      impulse can remove or transfer closing momentum but can never reverse it,
#      so an attacker is never pushed backward past a stop. The pinball bounce is
#      structurally impossible here, not merely tuned to zero.
#
#   3. Each body's leg drive (CheckDriveRules), on a closing contact: a kick on
#      the OTHER body along the axis, with no reaction on the driver, whose
#      skates take it.
#
# All the gameplay attributes AND the hit button enter through ONE caller-supplied
# scalar, `transfer` (0..1), from contact_transfer. It scales the shared impulse, so:
#   * transfer → 1  : full inelastic transfer. Equal masses converge to a shared
#                     velocity (the grind); a heavy attacker on a light victim
#                     barely slows (drive-through) while the victim is launched.
#   * transfer small: a glancing, uncommitted bump — the victim barely moves and
#                     the attacker keeps most of its speed (glances off), which is
#                     what keeps an uncommitted bump from reading as "skate into
#                     someone and your momentum just stops".
# Drive-through vs. grind is thus emergent from the mass ratio (Δv = J/m), NOT a
# hand-shaped restitution curve — the grounded-model discipline (see Scripts/domain/ai/CLAUDE.md).
#
# Each body's own Δv is the "how hard did it land" number its stagger, rocked
# band, knockdown and puck strip key off downstream — both bodies', whichever
# one's resolver ran.
#
# Pure/static + value-type math (Vector3, no heap allocation beyond the caller-owned
# Result), so it is hot-path safe at the tick rate × pairs AND — unlike an engine contact
# solver — replays bit-identically in reconcile: live prediction, host authority,
# and replay all call this same function on the same replicated inputs.

const _EPS: float = 0.0001


# Caller-owned scratch result, filled by resolve(). Held once and reused per tick
# (the "build once, fill scratch" hot-path pattern) rather than freshly allocated
# per pair. A/B match the argument order passed to resolve — A is the skater the
# caller treats as the attacker (its resolver is running), B is the other.
class Result:
	var sep_a: Vector3 = Vector3.ZERO      # positional push to apply to A's position
	var sep_b: Vector3 = Vector3.ZERO      # positional push to apply to B's position
	var dvel_a: Vector3 = Vector3.ZERO     # velocity delta for A (attacker; its decel / drive-through)
	var dvel_b: Vector3 = Vector3.ZERO     # velocity delta for B (victim; the knockback the stagger keys off)
	var closing_speed: float = 0.0         # >0 when A was closing on B along the axis (0 if separating/apart)
	var kick_on_a: float = 0.0             # m/s of dvel_a that is B's leg drive (inside dvel_a)
	var kick_on_b: float = 0.0             # m/s of dvel_b that is A's leg drive (inside dvel_b)
	var overlapping: bool = false          # discs overlap this tick (separation was applied)
	var impulse_applied: bool = false      # a closing impulse was applied (a real contact hit)

	func clear() -> void:
		sep_a = Vector3.ZERO
		sep_b = Vector3.ZERO
		dvel_a = Vector3.ZERO
		dvel_b = Vector3.ZERO
		closing_speed = 0.0
		kick_on_a = 0.0
		kick_on_b = 0.0
		overlapping = false
		impulse_applied = false


# Resolve one skater pair on the XZ plane, filling `out`. Y is ignored (skaters are
# axis-locked in Y). `transfer` (clamped 0..1) scales the inelastic impulse — the
# caller builds it from the attacker's delivery × hit-commit and the victim's brace.
# `kick_on_b` and `kick_on_a` (m/s) are what A's and B's leg drives add to the
# other body (drive_kick), on a closing contact.
static func resolve(
		out: Result,
		pos_a: Vector3, vel_a: Vector3, mass_a: float, radius_a: float,
		pos_b: Vector3, vel_b: Vector3, mass_b: float, radius_b: float,
		transfer: float, kick_on_b: float = 0.0, kick_on_a: float = 0.0) -> void:
	out.clear()

	# Center-to-center axis on XZ, n pointing A -> B.
	var d: Vector3 = pos_b - pos_a
	d.y = 0.0
	var dist: float = d.length()
	var n: Vector3
	if dist < _EPS:
		# Coincident centers (spawn overlap, teleport): pick a deterministic axis
		# so the pair still separates instead of producing a NaN normal. +X is
		# arbitrary but identical on every machine, preserving replay determinism.
		n = Vector3(1.0, 0.0, 0.0)
		dist = 0.0
	else:
		n = d / dist

	var overlap: float = (radius_a + radius_b) - dist
	if overlap <= 0.0:
		return  # not touching — nothing to do

	out.overlapping = true

	var inv_a: float = 1.0 / maxf(mass_a, _EPS)
	var inv_b: float = 1.0 / maxf(mass_b, _EPS)
	var inv_sum: float = inv_a + inv_b

	# Positional separation, split by inverse mass: the lighter body is pushed
	# more. A moves along -n (away from B), B along +n. Sum equals the full overlap.
	var push_a: float = overlap * (inv_a / inv_sum)
	var push_b: float = overlap * (inv_b / inv_sum)
	out.sep_a = -n * push_a
	out.sep_b = n * push_b

	# Closing speed along n (positive when A is moving toward B).
	var rel: Vector3 = vel_a - vel_b
	rel.y = 0.0
	var s: float = rel.dot(n)
	out.closing_speed = s
	if s <= 0.0:
		return  # separating or sliding tangentially — separation only, no hit impulse

	# Single inelastic impulse via the shared victim_kick (J·inv_b): no (1+e)
	# term — J removes/transfers at most the closing momentum (scaled by
	# transfer), so the attacker can slow toward — but never past — a stop. No
	# bounce. Routing the delivery through victim_kick keeps this resolver and
	# every PREDICTOR of it (the AI's check-commit gate) on one formula.
	var kick_b: float = victim_kick(s, mass_a, mass_b, transfer)
	# Equal-and-opposite momentum: Δv_a = J/m_a = kick_b · m_b/m_a.
	out.kick_on_a = kick_on_a
	out.kick_on_b = kick_on_b
	out.dvel_a = -n * (kick_b * mass_b * inv_a + out.kick_on_a)   # attacker decelerates (drive-through emerges)
	out.dvel_b = n * (kick_b + out.kick_on_b)                     # victim launched along the hit line
	out.impulse_applied = true


# The victim's velocity-delta magnitude (m/s) for a hit closing at
# `closing_speed` — THE single inelastic delivery this resolver applies:
# Δv_b = J·inv_b with J = closing × reduced_mass × transfer, which reduces to
# closing × transfer × m_a/(m_a + m_b). This is the "how hard did it land"
# number the stagger ladder, knockdown, and puck-strip key off. Factored out
# and consumed by resolve() itself so PREDICTORS of a future hit — the AI's
# check-commit gate (AIBodyCheck) — share the exact delivery math: when this
# model changes, every prediction of it changes in the same edit, instead of
# a mirrored formula silently going stale (which is how the AI stopped
# hitting for a while after the inelastic rewrite).
static func victim_kick(closing_speed: float, mass_a: float, mass_b: float,
		transfer: float) -> float:
	return closing_speed * clampf(transfer, 0.0, 1.0) \
			* mass_a / maxf(mass_a + mass_b, _EPS)


# The transfer a contact between bodies A and B lands at: the one rule the live
# resolver, the reconcile replay and the puck strip read, symmetric in A and B.
# A committed checker (Ctrl held without the puck) delivers his whole transfer
# inside his drive (CheckDriveRules) and its held share past it, whichever of
# the two is moving faster; with neither committed it is the passive bump; a
# carrier holding Ctrl braces, cutting it by his resistance.
static func contact_transfer(
		a_transfer: float, a_committed: bool, a_driving: bool, a_has_puck: bool,
		a_brace: float,
		b_transfer: float, b_committed: bool, b_driving: bool, b_has_puck: bool,
		b_brace: float, passive_mult: float) -> float:
	var a_delivers: bool = a_committed and not a_has_puck
	var b_delivers: bool = b_committed and not b_has_puck
	var t: float
	if a_delivers or b_delivers:
		t = maxf(_delivered(a_transfer, a_delivers, a_driving),
				_delivered(b_transfer, b_delivers, b_driving))
	else:
		t = maxf(a_transfer, b_transfer) * passive_mult
	if a_committed and a_has_puck:
		t *= a_brace
	if b_committed and b_has_puck:
		t *= b_brace
	return t


static func _delivered(transfer: float, delivers: bool, driving: bool) -> float:
	if not delivers:
		return 0.0
	return transfer if driving else transfer * CheckDriveRules.HELD_SHARE


# The Δv (m/s) a body's leg drive adds to the body it hits (resolve's
# kick_on_*): CheckDriveRules.kick_dv while he is a checker inside his drive,
# cut by the brace of a carrier holding Ctrl as the transfer is, else nothing.
static func drive_kick(driving: bool, committed: bool, has_puck: bool, thrust: float,
		mass: float, other_mass: float, other_braced: bool, other_brace: float) -> float:
	if not driving or not committed or has_puck:
		return 0.0
	var kick: float = CheckDriveRules.kick_dv(thrust, mass, other_mass)
	return kick * other_brace if other_braced else kick

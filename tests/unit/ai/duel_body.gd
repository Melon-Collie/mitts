extends RefCounted

# A skater's body in contact, for the duel harness: what a contact between two
# bodies lands at (SkaterCollisionRules.contact_transfer), what a landed hit does
# to the one it lands on (SkaterController._absorb_hit — the stagger, the rocked
# band, the knockdown off his balance), how a stagger and a knockdown move him
# (SkaterController._apply_movement), and whether a hit strips the carrier
# (Puck.on_body_check). Every number is read once off a set-up body, its
# controller and the puck (capture); the rules are the game's own.

var weight: float
var radius: float
var transfer: float
var brace: float
var passive_mult: float
var check_cfg: BodyCheckRules.Config
var balance_cfg: BodyBalanceRules.Config
var fall_cfg: KnockdownFallRules.Config
var height_mult: float
var getup_s: float
var getup_stagger_s: float
var knockdown_friction: float
var strip_threshold: float
var strip_ref: float
var strip_trickle_m_s: float
var strip_loose_m_s: float
var hit_cooldown_s: float
var hit_cooldown_threshold: float


static func capture(skater: Skater, ctrl: SkaterController, puck: Puck) -> RefCounted:
	var body: RefCounted = (load("res://tests/unit/ai/duel_body.gd") as GDScript).new()
	body.weight = skater.weight
	body.radius = skater.collision_radius()
	body.transfer = skater.body_check_transfer
	body.brace = skater.body_check_brace_resistance
	body.passive_mult = skater.hit_passive_transfer_mult
	body.check_cfg = ctrl._body_check_config()
	body.balance_cfg = ctrl._balance_config()
	body.fall_cfg = ctrl._fall_config()
	body.height_mult = ctrl._build_height_mult
	body.getup_s = ctrl.knockdown_getup_seconds
	body.getup_stagger_s = ctrl.knockdown_getup_stagger_seconds
	body.knockdown_friction = ctrl.knockdown_friction
	body.strip_threshold = puck.body_check_strip_threshold
	body.strip_ref = puck.body_check_strip_ref_impulse
	body.strip_trickle_m_s = puck.body_check_puck_speed
	body.strip_loose_m_s = puck.body_check_loose_speed
	body.hit_cooldown_s = puck.hit_pickup_cooldown
	body.hit_cooldown_threshold = puck.hit_pickup_cooldown_threshold
	return body


# The transfer a contact between two bodies lands at, from each one's commit and
# possession.
func contact_transfer(a_committed: bool, a_has_puck: bool, b_committed: bool,
		b_has_puck: bool) -> float:
	return SkaterCollisionRules.contact_transfer(transfer, a_committed, a_has_puck, brace,
			transfer, b_committed, b_has_puck, brace, passive_mult)


# The Δv `impulse` landing on a body facing `facing`, `strength` its board-backed
# hardness: returns his (stagger, knockdown) timers, each extended, never
# shortened. `delivers` (committed without the puck) leans him into it.
func absorb(stagger: float, knockdown: float, impulse: Vector3, strength: float,
		facing: Vector2, stance: bool, off_balance: bool, delivers: bool) -> Vector2:
	var felt: Vector3 = impulse
	if delivers:
		var leaned: Vector2 = BodyBalanceRules.leaned_into(Vector2(impulse.x, impulse.z),
				facing, balance_cfg)
		felt = Vector3(leaned.x, 0.0, leaned.y)
	var magnitude: float = felt.length()
	var felt_share: float = magnitude / maxf(impulse.length(), 1e-6)
	var stagger_from: float = maxf(magnitude, strength * felt_share)
	var knockdown_add: float = 0.0
	var over: float = BodyBalanceRules.overshoot(Vector2(felt.x, felt.z), facing,
			BodyBalanceRules.posture_of(stance, off_balance), height_mult, balance_cfg)
	if over > 1.0:
		knockdown_add = KnockdownFallRules.first_impact_time(
				Vector2(impulse.x, impulse.z).length(), fall_cfg) \
				+ BodyCheckRules.lie_seconds_from_overshoot(over, check_cfg) + getup_s
	var stagger_add: float = BodyCheckRules.stagger_seconds_from_impulse(stagger_from,
			check_cfg, knockdown_add > 0.0)
	return Vector2(maxf(stagger, stagger_add), maxf(knockdown, knockdown_add))


# The impulse a hit of `closing` m/s delivers to the carrier it lands on, the
# boards behind him counted (Puck.on_body_check): ≥ hit_cooldown_threshold locks
# him off the puck, ≥ strip_threshold knocks it off his stick.
func strip_impulse(closing: float, contact: float, hit_dir: Vector2,
		wall_out: Vector2) -> float:
	var delivered: float = BodyCheckRules.puck_strip_impulse(weight * closing, weight,
			contact, weight)
	return BoardPinRules.backstop_hit_strength(delivered, closing, contact, hit_dir,
			wall_out, weight, weight)


# The puck off a carrier struck at `delivered` along `hit_dir`.
func strip_velocity(hit_dir: Vector3, delivered: float) -> Vector3:
	var intensity: float = clampf((delivered - strip_threshold)
			/ maxf(strip_ref - strip_threshold, 0.001), 0.0, 1.0)
	return PuckCollisionRules.body_check_strip_velocity(hit_dir, strip_trickle_m_s,
			strip_loose_m_s, intensity)

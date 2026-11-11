class_name FightPunchRules
extends RefCounted

# Whether a punch lands, where, and what it does (docs/fighting-plan.md §4).
# The punching fist (FightFistRules) is swept from where it was last tick to
# where it is now through the other man's head, his chest and his arms; the
# first it meets is what it hits, and an arm in the way is a block. A fist
# moving onto him slower than MIN_LAND_M_S is a hand on him, not a punch.
#
# What it does is mostly the rattle: a fist moves a man only ~0.4 m/s (an arm's
# mass on his body's), far under the 2.4 m/s his balance rides
# (BodyBalanceRules), so punches knock nobody over by their momentum. A head
# that is hit leaves its legs less sure under it, and that is what the rattle
# models: a timer, in seconds, that each punch adds to by where and how hard it
# landed, that wears off, and that takes his balance away with it. A man
# rattled to the full has almost no balance left, and a clean shot to the head
# then puts him down through the same balance rule a check does.

enum Hit { NONE, HEAD, BODY, BLOCKED }

# The head: a ball this big, its centre this far over the chin point
# (SkaterFightHands.chin_world).
const HEAD_RADIUS_M: float = 0.13
const HEAD_ABOVE_CHIN_M: float = 0.1
# The chest: a ball this big, this far under the shoulders' line.
const BODY_RADIUS_M: float = 0.2
const BODY_BELOW_SHOULDERS_M: float = 0.22
# A forearm, as a capsule from shoulder to fist, and the fist's own size.
const ARM_RADIUS_M: float = 0.06
const FIST_RADIUS_M: float = 0.05
# A fist closing on him slower than this lands nothing.
const MIN_LAND_M_S: float = 2.5
# After a punch lands, that fist lands nothing more for this long: one punch,
# not one a tick while it stays on him.
const HIT_COOLDOWN_S: float = 0.3
# The striking mass of a fist, its forearm and some of the arm behind it, kg.
const ARM_MASS_KG: float = 4.0
# A body of Skater.weight 1.0, the neutral build's 201 lb, kg.
const NEUTRAL_MASS_KG: float = 91.2

# The rattle, seconds: its most, what a clean full-speed punch adds (to the
# head, the body, or through a block, as shares of that), and how fast it wears
# off.
const RATTLE_MAX_S: float = 3.0
const RATTLE_HEAD_S: float = 1.2
const RATTLE_BODY_SHARE: float = 0.3
const RATTLE_BLOCKED_SHARE: float = 0.08
const RATTLE_DECAY_PER_S: float = 0.4
# Fully rattled, his balance is this share short of a sound man's...
const RATTLE_BALANCE_LOSS: float = 0.95
# ...and his fists this share short of their speed.
const RATTLE_FIST_LOSS: float = 0.5
# The reel a full-speed punch throws him into, as a check's stagger strength
# (m/s, BodyCheckRules), to the head; the body takes a share of it.
const REEL_HEAD_M_S: float = 1.1
const REEL_BODY_SHARE: float = 0.5


# Where along the sweep from `a` to `b` a ball of `radius` at `center` is first
# touched, 0..1, or −1 if it is not.
static func sweep_sphere(a: Vector3, b: Vector3, center: Vector3, radius: float) -> float:
	var d: Vector3 = b - a
	var f: Vector3 = a - center
	var aa: float = d.dot(d)
	var c: float = f.dot(f) - radius * radius
	if c <= 0.0:
		return 0.0
	if aa < 1e-10:
		return -1.0
	var half_b: float = f.dot(d)
	var disc: float = half_b * half_b - aa * c
	if disc < 0.0:
		return -1.0
	var t: float = (-half_b - sqrt(disc)) / aa
	return t if t >= 0.0 and t <= 1.0 else -1.0


# The same against a capsule from `p` to `q`: the sweep sampled along its
# length, each sample's nearest point on the capsule's line taken as a ball.
# Exact enough for a fist a few centimetres a tick against a forearm.
static func sweep_capsule(a: Vector3, b: Vector3, p: Vector3, q: Vector3, radius: float) -> float:
	var steps: int = 6
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		var at: Vector3 = a.lerp(b, t)
		if at.distance_to(_nearest_on_segment(at, p, q)) <= radius:
			return t
	return -1.0


static func _nearest_on_segment(x: Vector3, p: Vector3, q: Vector3) -> Vector3:
	var d: Vector3 = q - p
	var len2: float = d.length_squared()
	if len2 < 1e-10:
		return p
	return p + d * clampf((x - p).dot(d) / len2, 0.0, 1.0)


# How fast a fist moving at `fist_vel` closes on a target moving at
# `target_vel`, along `toward` (unit, fist to target).
static func closing_speed(fist_vel: Vector3, target_vel: Vector3, toward: Vector3) -> float:
	return (fist_vel - target_vel).dot(toward)


static func lands(speed: float) -> bool:
	return speed >= MIN_LAND_M_S


# The rattle a punch adds, at `speed` (closing, m/s).
static func rattle_added(hit: Hit, speed: float) -> float:
	var full: float = RATTLE_HEAD_S * clampf(speed / FightFistRules.MAX_SPEED_M_S, 0.0, 1.0)
	match hit:
		Hit.HEAD:
			return full
		Hit.BODY:
			return full * RATTLE_BODY_SHARE
		Hit.BLOCKED:
			return full * RATTLE_BLOCKED_SHARE
	return 0.0


static func rattle_share(rattle: float) -> float:
	return clampf(rattle / RATTLE_MAX_S, 0.0, 1.0)


# What a Δv on a rattled man does to his balance, as a multiple of what it does
# to a sound one: his budget is shrunk, which is the same as the Δv grown.
static func balance_scale(rattle: float) -> float:
	return 1.0 / maxf(1.0 - RATTLE_BALANCE_LOSS * rattle_share(rattle), 0.05)


static func fist_scale(rattle: float) -> float:
	return 1.0 - RATTLE_FIST_LOSS * rattle_share(rattle)


# The Δv a punch at `speed` lands on a body of `mass_kg`, m/s. A blocked one
# is taken on the arm and moves him all the same.
static func impulse_dv(speed: float, mass_kg: float) -> float:
	return ARM_MASS_KG * speed / maxf(mass_kg, 1.0)


# How hard it reels him, as a check's stagger strength (m/s).
static func reel(hit: Hit, speed: float) -> float:
	var full: float = REEL_HEAD_M_S * clampf(speed / FightFistRules.MAX_SPEED_M_S, 0.0, 1.0)
	match hit:
		Hit.HEAD:
			return full
		Hit.BODY:
			return full * REEL_BODY_SHARE
	return 0.0


# 0..1, how hard it landed, for the sound, the burst and the crowd.
static func intensity(hit: Hit, speed: float) -> float:
	var t: float = clampf((speed - MIN_LAND_M_S) / (FightFistRules.MAX_SPEED_M_S - MIN_LAND_M_S),
			0.0, 1.0)
	return t * (1.0 if hit == Hit.HEAD else 0.7 if hit == Hit.BODY else 0.3)

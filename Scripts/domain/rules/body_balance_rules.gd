class_name BodyBalanceRules

# Whether a hit knocks a skater off his skates: the part of his Δv that tips
# him against what his base can take (docs/hit-outcomes-plan.md, Phase 2).
#
# A body knocked down is one tipped over the edge of its base. As an inverted
# pendulum, ½Δv² = g(√(h² + b²) − h) ≈ g·b²/2h, so the Δv it can take on its
# feet goes as b·√(g/h): up with the half-base b in the hit's direction, down
# with the height h of the centre of mass. A skater steps and rides a hit far
# beyond what a static pendulum survives, so the level is a feel tunable
# (balance_ref_dv); the pendulum fixes how each term moves it.
#
# Every input is replicated state (velocity change, facing, stance, shot state,
# the build), so the host and the local victim's prediction reach one verdict.
# All vectors are XZ.

class Config:
	# Δv (m/s) a square, upright skater of the reference height rides on his
	# feet: one-sided checks at equal builds below top speed never reach it.
	var balance_ref_dv: float = 2.4
	# Share of the Δv along his blades that tips him: the skates roll with the
	# body, so most of it is carried off as travel. Across them the edges bite.
	var along_share: float = 0.5
	# His budget with his back to the hitter, against 1 facing him down; linear
	# in (1 + cos) / 2 between. A man who sees it coming rides it.
	var sight_behind: float = 0.6
	# Budget × this while his body is committed to something else: a slapper's
	# wind-up, a wrister's load, a follow-through, a one-timer's hold.
	var vulnerable_mult: float = 0.6
	# The loaded stance's base over the skating base, half-width over
	# half-width: each skate set SkaterController.stance_width_m out from under a
	# hip GaitPose.HIP_HALF_WIDTH off centre. The controller derives it from those
	# two; test_rocked_hit.gd holds this default to its value.
	var stance_base_ratio: float = (0.13 + 0.125) / 0.13
	# A committed checker leans into the contact: the part of his Δv that drives
	# him back the way he faces counts at this share for his every outcome, so
	# landing a check slows him without rocking him.
	var checker_front_share: float = 0.4


enum Posture { UPRIGHT, STANCE, VULNERABLE }


static func posture_of(stance_active: bool, vulnerable: bool) -> Posture:
	if vulnerable:
		return Posture.VULNERABLE
	return Posture.STANCE if stance_active else Posture.UPRIGHT


# The part of `dv` his feet can't carry off as travel: along his blades
# (`heading`, unit) at along_share, across them whole.
static func tip_dv(dv: Vector2, heading: Vector2, cfg: Config) -> float:
	var along: float = dv.dot(heading)
	var across_sq: float = maxf(dv.length_squared() - along * along, 0.0)
	return sqrt(cfg.along_share * cfg.along_share * along * along + across_sq)


# 0..1 how square he is to the hitter, who is where `dv` drove him from.
static func sight(dv: Vector2, facing: Vector2, cfg: Config) -> float:
	var dv_len: float = dv.length()
	if dv_len < 1e-6:
		return 1.0
	var cos_to_hitter: float = facing.dot(-dv / dv_len)
	return lerpf(cfg.sight_behind, 1.0, 0.5 * (1.0 + cos_to_hitter))


# The Δv tip_dv must exceed to knock him down. `height_mult` is his build's
# height over the reference build's, which his centre of mass scales with.
static func budget(dv: Vector2, facing: Vector2, posture: Posture,
		height_mult: float, cfg: Config) -> float:
	var stand: float = 1.0
	if posture == Posture.STANCE:
		stand = cfg.stance_base_ratio
	elif posture == Posture.VULNERABLE:
		stand = cfg.vulnerable_mult
	return cfg.balance_ref_dv * stand * sight(dv, facing, cfg) / sqrt(maxf(height_mult, 0.01))


# How far past his balance the hit landed: tip_dv over the budget, his blades
# pointing along his facing (forward or skating backward). Over 1
# knocks him down; BodyCheckRules turns it into the time he is down.
static func overshoot(dv: Vector2, facing: Vector2, posture: Posture,
		height_mult: float, cfg: Config) -> float:
	var b: float = budget(dv, facing, posture, height_mult, cfg)
	return tip_dv(dv, facing, cfg) / maxf(b, 1e-6)


# `dv` as a committed checker facing `facing` takes it: the part driving him
# back the way he faces at checker_front_share, the rest whole.
static func leaned_into(dv: Vector2, facing: Vector2, cfg: Config) -> Vector2:
	var along: float = dv.dot(facing)
	if along >= 0.0:
		return dv
	return dv - facing * along * (1.0 - cfg.checker_front_share)

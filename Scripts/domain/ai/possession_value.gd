class_name AIPossessionValue
extends RefCounted

# What a shot has to be worth to be worth the possession it spends
# (docs/possession-value-plan.md §3). A shot that does not score ends the
# possession unless the puck comes back, so it must out-value keeping the puck:
#
#   fire = xG + (1 − xG) · [(1 − P_lose) · V − P_lose · C]      hold = V
#
# and fire ≥ hold solves to `shot_bar`. V is the possession's continuation value,
# C the opponent's value where they collect a shot we lose. The carrier applies
# the bar as a giveaway floor only — it never enters the carry search, so it
# decides WHETHER to fire, never where to carry (plan §4).
#
# Reads AIActionScoring (the read-validity τ); never read by it.

# xG a controlled offensive-zone possession produces per second of holding the
# puck — the `r` in V = r / (h + 1/τ). Measured on
# benchmarks/test_oz_possession_harness.gd (2026-10-12; Hard and Normal pooled,
# one episode per trial to the first shot): 3v3 11.4 xG over 234 s, 5v5 8.1 xG
# over 227 s. One significant figure: 16–34 shots per row, and the harness's
# static keeper and missing body contact bias it both ways (plan §6).
const XG_RATE_3V3: float = 0.05
const XG_RATE_5V5: float = 0.04

# Probability that a shot which does not score ends our possession. A PRIOR, not
# a measurement: no harness models a save followed by the next possession, so
# the number comes from logged play (shot_events.next_control) once it exists.
const P_LOSE_PRIOR: float = 0.7

# A keep probability of exactly 0 would be an infinite hazard; this caps it at a
# possession that cannot outlive one read.
const KEEP_PROB_FLOOR: float = 0.0001


static func xg_rate(team_size: int) -> float:
	return XG_RATE_5V5 if team_size >= 5 else XG_RATE_3V3


# Constant-hazard loss rate (1/s) from the probability of keeping the puck over
# `horizon_s` — the same survival form as AIActionScoring.delay_discount.
static func hazard(keep_prob: float, horizon_s: float) -> float:
	return -log(clampf(keep_prob, KEEP_PROB_FLOOR, 1.0)) / maxf(horizon_s, 0.001)


# V: looks at `rate` xG/s for as long as the possession survives `hazard` AND the
# read stays valid — r ∫ exp(−(h + 1/τ)t) dt. Bounded by r·τ as h → 0.
static func continuation_value(rate: float, loss_hazard: float) -> float:
	return rate / (maxf(loss_hazard, 0.0) + 1.0 / AIActionScoring.READ_VALIDITY_TAU_S)


# The xG a shot must reach to beat holding the puck. `opp_value` is C, the
# opponent's value at the point they collect a shot we lose (≥ 0).
static func shot_bar(possession_value: float, p_lose: float, opp_value: float) -> float:
	var keep_term: float = (1.0 - p_lose) * possession_value - p_lose * opp_value
	return p_lose * (possession_value + opp_value) / (1.0 - keep_term)

class_name AIFeedStationPick
extends RefCounted

# The argmax of a receiver station a teammate feeds: the spot whose feed is worth
# most as the passer prices it (AIRoleReads.feed_ev). While no candidate has a
# lane at all (a forechecker on the release kills every feed alike) the feed
# says nothing about the spot, so the spot our possession values most for when
# the carrier gets free wins instead.

var _best_ev: float = -INF
var _best_ev_pos: Vector3 = Vector3.INF
var _best_held: float = -INF
var _best_held_pos: Vector3 = Vector3.INF
var _any_lane: bool = false


func reset() -> void:
	_best_ev = -INF
	_best_ev_pos = Vector3.INF
	_best_held = -INF
	_best_held_pos = Vector3.INF
	_any_lane = false


# Candidate `spot`, fed from `origin` at `speed`: our possession there `held`,
# the hysteresis `bonus` both reads carry, theirs `theirs` where a feed is picked
# off. Every feed's worth is at most `held` (its lane ≤ 1, the interception cost
# ≥ 0), so a spot that cannot beat the best feed so far has no lane read, nor a
# lane that cannot its loss point (exact).
func offer(ctx: RoleContext, origin: Vector3, spot: Vector3, speed: float, held: float,
		bonus: float, theirs: AIPossessionValue) -> void:
	if held + bonus > _best_held:
		_best_held = held + bonus
		_best_held_pos = spot
	if _any_lane and held + bonus <= _best_ev:
		return
	var lane: float = AIRoleReads.feed_lane(ctx, origin, spot, speed)
	if lane > 0.0:
		_any_lane = true
	var ev: float = lane * held
	if ev + bonus <= _best_ev:
		return
	if lane < 1.0:
		ev = AIRoleReads.feed_ev(ctx, origin, spot, speed, lane, held, theirs)
	if ev + bonus > _best_ev:
		_best_ev = ev + bonus
		_best_ev_pos = spot


# The pick, or `fallback` when no candidate was offered.
func best(fallback: Vector3) -> Vector3:
	var pos: Vector3 = _best_ev_pos if _any_lane else _best_held_pos
	return pos if pos.is_finite() else fallback

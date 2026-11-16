class_name AIShotLoss

# What a shot loses when it does not score, priced as a pass's loss modes are
# (AICarrierPassSearch._pass_ev), so the shoot, pass and carry legs of the
# carrier's compete price a shot alike: the shot now and the rip
# (AIRoleCarrier), the shot a carry arrives at and a receiver's off the feed
# (AICarrierField.value_at / feed_value_at).


# The cost of a shot released at `release` at `speed`: the puck lost before it
# leaves (1 − `keep`) at the release; blocked short of `lane_end` (`reach` the
# odds it gets there) where its lane is lost; and, reaching it and not scoring
# (`scores` its odds, first contact or the tip, before any rebound credit), the
# rebounds their side touches first, raced over the rebound field
# (AIReboundValue.their_share), where they touch them. Each at their possession
# there, the shooter one of our men at his release, and the counter-rush it
# hands over, his own recovery from the release.
static func cost(field: AICarrierField, ctx: RoleContext, release: Vector3,
		lane_end: Vector3, speed: float, keep: float, reach: float, scores: float) -> float:
	var our_goalie: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var self_caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	var lost: float = 1.0 - keep
	var total: float = field.turnover_cost(release, lost, 0.0, release, self_caps) \
			+ field.counter_exposure_cost(ctx, release, lost, release, our_goalie)
	var blocked: float = keep * (1.0 - reach)
	if blocked > 0.0:
		var at: Vector3 = Vector3.INF
		if lane_end.is_finite():
			at = AIPuckLane.lane_loss_point(release, lane_end, field.opponents_release, speed,
					field.opponent_vels, field.opponent_caps, field.opponent_blades_release)
		if not at.is_finite():
			at = release
		total += field.turnover_cost(at, blocked, 0.0, release, self_caps) \
				+ field.counter_exposure_cost(ctx, at, blocked, release, our_goalie)
	var saved: float = keep * reach * (1.0 - scores)
	if saved > 0.0:
		field.rebound.fill(release, ctx.attacking_goal_pos, field.our_bodies,
				field.our_body_vels, field.opponents, field.opponent_vels)
		var theirs: float = saved * field.rebound.their_share()
		if theirs > 0.0:
			var at: Vector3 = field.rebound.their_at
			total += field.turnover_cost(at, theirs, 0.0, release, self_caps) \
					+ field.counter_exposure_cost(ctx, at, theirs, release, our_goalie)
	return total

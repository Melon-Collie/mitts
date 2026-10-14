class_name AIRoleChase

# CHASE (NEUTRAL, both team sizes) — the elected peer for a loose puck. The
# whole decision is AIRoleHelpers.chase_puck: race it, or hold the pre-contain
# stand when an opponent has already won it.

static func decide(ctx: RoleContext) -> RoleDecision:
	var d := RoleDecision.new()
	AIRoleHelpers.chase_puck(ctx, d)
	return d

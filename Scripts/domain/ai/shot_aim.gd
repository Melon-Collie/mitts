class_name AIShotAim

# Picks a shot aim point past the opposing goalie's projected shadow on the net
# plane. Returns a world XZ point at y=0; callers write it to
# InputState.mouse_world_pos so the blade IK and the quick-shot release
# direction both follow it.
#
# The shooter→goalie sightline traced to the net plane (z = net_z) is the
# goalie's shadow, `shadow_half` wide either side. Aim along the larger of the
# two open arcs, biased from its midpoint toward its post by `corner_bias`. A
# shadow covering the whole net degenerates both arcs; the less-covered side
# still wins, and the post clamp keeps the aim makeable.
#
# `goalie_velocity_x` shoots back across the grain: a sliding goalie keeps
# drifting until the shot arrives, so the arc he must reverse to cover grows.
# The default 0.0 is the static-shadow read, for callers without goalie velocity
# in scope (the lane-clear checks in action_scoring.gd, where the small aim
# divergence doesn't matter).


# Where in the open arc the bot aims: 0 = the arc MIDPOINT (max clearance from
# both the post and the goalie's cover edge), +1 = the open POST, -1 = the
# goalie's cover edge.
#
# Keep this at 0.0. The shot score prices its partial make probability with the
# aim at the window centre, so an off-centre aim desyncs score from release. A
# centred aim also splits the execution wobble symmetrically into goals, saves
# and posts; a post bias throws the whole tail onto the iron and the goalie
# never makes a save.
const DEFAULT_CORNER_BIAS: float = 0.0

# Seconds of goalie slide projected onto the shadow — deliberately short of a
# shot's flight: a goalie who brakes mid-slide turns any over-projection into a
# shot wide of the post, so this leans toward the recovery arc without
# inverting the aim.
const SHADOW_VELOCITY_LOOKAHEAD_S: float = 0.12


static func compute_open_net_aim(
		shooter: Vector3,
		goalie: Vector3,
		net_z: float,
		net_half_width: float,
		shadow_half: float,
		corner_bias: float = DEFAULT_CORNER_BIAS,
		goalie_velocity_x: float = 0.0) -> Vector3:
	var dz: float = goalie.z - shooter.z
	var to_net_z: float = net_z - shooter.z
	# Shooter level with the goalie, or the goalie beyond the net: no sightline
	# crosses the net plane, so aim at centre.
	if absf(dz) < 0.001 or signf(dz) != signf(to_net_z):
		return Vector3(0.0, 0.0, net_z)
	var t: float = to_net_z / dz
	var shadow_x: float = shooter.x + t * (goalie.x - shooter.x)
	shadow_x += goalie_velocity_x * SHADOW_VELOCITY_LOOKAHEAD_S
	# Clamp the shadow's two edges to the net so an off-net shadow doesn't
	# count as blocking.
	var shadow_left: float = clampf(shadow_x - shadow_half, -net_half_width, net_half_width)
	var shadow_right: float = clampf(shadow_x + shadow_half, -net_half_width, net_half_width)
	var left_arc_size: float = shadow_left - (-net_half_width)
	var right_arc_size: float = net_half_width - shadow_right
	var aim_x: float
	if left_arc_size >= right_arc_size:
		var midpoint: float = (-net_half_width + shadow_left) * 0.5
		aim_x = lerpf(midpoint, -net_half_width, corner_bias)
	else:
		var midpoint: float = (shadow_right + net_half_width) * 0.5
		aim_x = lerpf(midpoint, net_half_width, corner_bias)
	# Post clearance: never aim outside the line the puck's CENTER can cross
	# without clipping the pipe (post radius + puck radius inside the post
	# centerline — GameRules.NET_ENTRY_HALF_WIDTH's derivation). A degenerate
	# arc lerps the aim onto the post itself, and with zero aim error the bot
	# rides that exact line into the iron every time.
	var entry_max: float = net_half_width \
			- GameRules.NET_POST_RADIUS - GameRules.PUCK_COLLISION_RADIUS
	return Vector3(clampf(aim_x, -entry_max, entry_max), 0.0, net_z)

class_name CarveRules

# The travel direction's turn rate from two velocity samples — the crossover
# cadence's clock (steps per radian of heading change) and the glide's read of
# a turn it is coming out of. Velocity is replicated, so every machine reads
# the identical rate with nothing new on the wire.
#
# Frame: XZ plane vectors as Vector2(x, z). Sign convention (pinned by
# tests): turning toward +X (the skater's right when travelling toward −Z)
# yields a POSITIVE turn rate.


# Signed turn rate of the travel direction in rad/s. Zero when either sample
# is too slow to carry a meaningful direction — at a near-standstill the
# velocity direction is noise, and a carve read from noise flails the legs.
static func turn_rate(prev_vel_xz: Vector2, vel_xz: Vector2,
		delta: float, min_speed: float) -> float:
	if delta <= 0.0:
		return 0.0
	if prev_vel_xz.length() < min_speed or vel_xz.length() < min_speed:
		return 0.0
	return prev_vel_xz.angle_to(vel_xz) / delta

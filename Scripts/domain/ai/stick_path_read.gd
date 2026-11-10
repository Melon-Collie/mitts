class_name AIStickPathRead
extends RefCounted

# Where the defender who owns the carrier holds his blade. Any blade of ours
# within GameRules.POKE_RADIUS_M of the carried puck strips it
# (PuckInteractionRules.check_poke: no swing and no button), so the stick goes
# where the puck is going, not where it is. Everything is what a defender sees:
# the puck, the carrier's skating, his own skating and his own blade. World XZ.

# How finely the puck's path is walked for the first point the blade beats it to.
const PATH_STEP_S: float = 0.05
# The walk ends within this long of the puck coming into reach: a carrier
# re-plans his line many times over, so a point further down a dead-reckoned
# path is no read of where the puck will be.
const PATH_HORIZON_S: float = 1.0


# Where to hold the blade now so the puck's path comes through it: the first
# point on the carried puck's path (dead-reckoned at the carrier's velocity)
# that is inside `reach` of our body (dead-reckoned at ours) when the puck gets
# there, and that our blade, from `blade_now` at `blade_speed` across the body,
# gets to no later than the puck. It is returned in our moving frame — that
# point less the ground our skating covers before the puck is there — because
# the cursor rides the body: aimed at the world point itself, a defender backing
# in leaves his blade behind him. INF when the path never comes into reach in
# time.
static func path_point(self_pos: Vector3, self_vel: Vector3, blade_now: Vector3,
		puck_pos: Vector3, carrier_vel: Vector3, reach: float,
		blade_speed: float) -> Vector3:
	var rpx: float = puck_pos.x - self_pos.x
	var rpz: float = puck_pos.z - self_pos.z
	var rvx: float = carrier_vel.x - self_vel.x
	var rvz: float = carrier_vel.z - self_vel.z
	var a: float = rvx * rvx + rvz * rvz
	var b: float = 2.0 * (rpx * rvx + rpz * rvz)
	var c: float = rpx * rpx + rpz * rpz - reach * reach
	var t_in: float = 0.0
	var t_out: float = INF
	if c > 0.0:
		var disc: float = b * b - 4.0 * a * c
		if a < 1e-6 or disc < 0.0:
			return Vector3.INF
		var root: float = sqrt(disc)
		t_in = (-b - root) / (2.0 * a)
		t_out = (-b + root) / (2.0 * a)
		if t_out < 0.0:
			return Vector3.INF
		t_in = maxf(t_in, 0.0)
	elif a > 1e-6:
		t_out = (-b + sqrt(b * b - 4.0 * a * c)) / (2.0 * a)
	var t_end: float = minf(t_out, t_in + PATH_HORIZON_S)
	var t: float = t_in
	while t <= t_end:
		var px: float = puck_pos.x + carrier_vel.x * t
		var pz: float = puck_pos.z + carrier_vel.z * t
		# The blade slews relative to the body, which carries it along.
		var bx: float = px - (blade_now.x + self_vel.x * t)
		var bz: float = pz - (blade_now.z + self_vel.z * t)
		var travel: float = blade_speed * t + GameRules.POKE_RADIUS_M
		if bx * bx + bz * bz <= travel * travel:
			return Vector3(px - self_vel.x * t, 0.0, pz - self_vel.z * t)
		t += PATH_STEP_S
	return Vector3.INF


# The carrier's line from the puck to our net where it first comes into `reach`
# of our body: the ice he has to skate the puck through, at the edge of it
# nearest him. The puck itself when it is already in reach; INF when the line
# never passes within reach.
static func lane_point(self_pos: Vector3, puck_pos: Vector3, our_net: Vector3,
		reach: float) -> Vector3:
	var fx: float = puck_pos.x - self_pos.x
	var fz: float = puck_pos.z - self_pos.z
	var c: float = fx * fx + fz * fz - reach * reach
	if c <= 0.0:
		return Vector3(puck_pos.x, 0.0, puck_pos.z)
	var dx: float = our_net.x - puck_pos.x
	var dz: float = our_net.z - puck_pos.z
	var a: float = dx * dx + dz * dz
	if a < 1e-6:
		return Vector3.INF
	var b: float = 2.0 * (fx * dx + fz * dz)
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0:
		return Vector3.INF
	var s: float = (-b - sqrt(disc)) / (2.0 * a)
	if s < 0.0 or s > 1.0:
		return Vector3.INF
	return Vector3(puck_pos.x + dx * s, 0.0, puck_pos.z + dz * s)


# `target` turned about `self_pos` no further off `facing` than the blade reaches
# on its side (FacingRules.reach_edge), at the same distance: past the edge the
# hips pivot onto the other line, so a stick aimed there would turn him.
static func within_reach_edges(self_pos: Vector3, target: Vector3, facing: Vector2,
		cfg: FacingRules.Config, is_left_handed: bool) -> Vector3:
	var to := Vector2(target.x - self_pos.x, target.z - self_pos.z)
	var dist: float = to.length()
	if dist < 1e-4 or facing.length_squared() < 1e-6:
		return target
	var f: Vector2 = facing.normalized()
	var angle: float = f.angle_to(to)
	var edge: float = FacingRules.reach_edge(cfg, f, to, is_left_handed)
	if absf(angle) <= edge:
		return target
	var held: Vector2 = f.rotated(signf(angle) * edge) * dist
	return Vector3(self_pos.x + held.x, 0.0, self_pos.z + held.y)

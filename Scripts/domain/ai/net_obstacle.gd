class_name AINetObstacle

# Segment tests on the ice plane against the two cages and our own slot: what
# a pass, a carry or a blade target may not pass through. A leaf (GameRules
# only).

# ── The net as a CARRY / BLADE obstacle ──────────────────────────────────────
# The carry model sees the cage the way the body steering does
# (AISteering._net_detour rounds the post). Two consumers:
#   - carry_path_blocked_by_net — a carried traverse (body + puck) cannot pass
#     through the cage, so a carry candidate whose straight route crosses it
#     is unreachable as priced.
#   - net_safe_blade_target — the carry cursor must never ask the blade IK to
#     reach THROUGH the frame (stick-on-net contact dislodges the carried
#     puck), so a crossing chord is swung around the nearer post.
# Margins are physical half-widths of the thing traversing: a carried body +
# puck for the path, a blade length of standoff for the cursor (same standard
# as the boards clamp).
const CARRY_NET_CLEAR_MARGIN_M: float = 0.5
const BLADE_NET_CLEAR_MARGIN_M: float = GameRules.DEFAULT_BLADE_LENGTH_M


# True iff a carried traverse from → to would pass through either cage
# (frame AABB inflated by the carry margin). From-inside counts as blocked —
# the slab test's t_min = 0 is inside the box — which is correct: a body
# standing against the mesh can't carry through it.
static func carry_path_blocked_by_net(from: Vector3, to: Vector3) -> bool:
	var hw: float = GameRules.NET_BACK_HALF_WIDTH + CARRY_NET_CLEAR_MARGIN_M
	var z_front: float = GameRules.GOAL_LINE_Z - CARRY_NET_CLEAR_MARGIN_M
	var z_back: float = GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH + CARRY_NET_CLEAR_MARGIN_M
	if _segment_crosses_aabb_xz(from.x, from.z, to.x, to.z, -hw, hw, z_front, z_back):
		return true
	return _segment_crosses_aabb_xz(from.x, from.z, to.x, to.z, -hw, hw, -z_back, -z_front)


# Redirect a blade-aim target whose chord from `from` crosses a net frame:
# rotate the aim to the frame's tangent bearing around the nearer post (the
# occluded bearing interval is bounded by the inflated frame's corner
# bearings; the chord crosses, so the original bearing lies inside it — clamp
# to the nearer edge plus a small step of daylight). Distance from `from` is
# preserved, y is flattened (blade targets live on the ice plane). A
# non-crossing target returns unchanged. Degenerate case — `from` itself
# inside the inflated frame region (pinned against the mesh): no tangent
# exists, so slide the aim laterally toward the nearer post-side exit.
static func net_safe_blade_target(from: Vector3, target: Vector3) -> Vector3:
	var hw: float = GameRules.NET_BACK_HALF_WIDTH + BLADE_NET_CLEAR_MARGIN_M
	var z_front: float = GameRules.GOAL_LINE_Z - BLADE_NET_CLEAR_MARGIN_M
	var z_back: float = GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH + BLADE_NET_CLEAR_MARGIN_M
	var box_z0: float
	var box_z1: float
	if _segment_crosses_aabb_xz(from.x, from.z, target.x, target.z, -hw, hw, z_front, z_back):
		box_z0 = z_front
		box_z1 = z_back
	elif _segment_crosses_aabb_xz(from.x, from.z, target.x, target.z, -hw, hw, -z_back, -z_front):
		box_z0 = -z_back
		box_z1 = -z_front
	else:
		return target
	var to_target := Vector2(target.x - from.x, target.z - from.z)
	var dist: float = to_target.length()
	if dist < 0.001:
		return target
	if from.x > -hw and from.x < hw and from.z > box_z0 and from.z < box_z1:
		var side: float = signf(from.x) if from.x != 0.0 else 1.0
		return Vector3(from.x + side * dist, 0.0, from.z)
	var target_ang: float = atan2(to_target.x, to_target.y)
	var min_rel: float = INF
	var max_rel: float = -INF
	for corner_x: float in [-hw, hw]:
		for corner_z: float in [box_z0, box_z1]:
			var rel: float = wrapf(
					atan2(corner_x - from.x, corner_z - from.z) - target_ang, -PI, PI)
			min_rel = minf(min_rel, rel)
			max_rel = maxf(max_rel, rel)
	# The chord crosses, so 0 ∈ [min_rel, max_rel]. Swing to the nearer edge,
	# plus a small step of daylight past the corner.
	var swing: float = min_rel if -min_rel <= max_rel else max_rel
	var out_ang: float = target_ang + swing + signf(swing) * 0.05
	return Vector3(from.x + sin(out_ang) * dist, 0.0, from.z + cos(out_ang) * dist)


# Own-DZ slot danger zone. True iff the pass segment crosses the
# rectangle in front of OUR net — the high-danger area where a
# deflected/intercepted pass becomes a goal against. Asymmetric to
# `pass_lane_blocked_by_net` because passes through OPP slot are
# legitimate (backdoor / cross-crease feeds); only OWN slot is risky.
#
# Slot rect: x ∈ ±OWN_DZ_SLOT_HALF_WIDTH_M, z ∈ [own_goal_line - depth,
# own_goal_line] for own_goal_z > 0; mirrored for own_goal_z < 0. Sized to the
# "home plate" high-danger area, not just the net mouth: a feed that clips the
# flanks is the same giveaway as a dead-centre one. Half-width covers the posts
# plus a stick either side; depth reaches toward the hash marks.
const OWN_DZ_SLOT_HALF_WIDTH_M: float = 2.75
const OWN_DZ_SLOT_DEPTH_M: float = 6.0
static func pass_crosses_own_slot(from: Vector3, to: Vector3, own_goal_z: float) -> bool:
	var depth: float = OWN_DZ_SLOT_DEPTH_M
	var half_w: float = OWN_DZ_SLOT_HALF_WIDTH_M
	if own_goal_z > 0.0:
		# Team 0: own net at +z. Slot is in front of goal line,
		# z ∈ [own_goal_z - depth, own_goal_z].
		return _segment_crosses_aabb_xz(
				from.x, from.z, to.x, to.z,
				-half_w, half_w,
				own_goal_z - depth, own_goal_z)
	else:
		# Team 1: own net at -z. Slot z ∈ [own_goal_z, own_goal_z + depth].
		return _segment_crosses_aabb_xz(
				from.x, from.z, to.x, to.z,
				-half_w, half_w,
				own_goal_z, own_goal_z + depth)


# Liang-Barsky parametric clipping: returns true iff the segment from
# (fx, fz) to (tx, tz) intersects the axis-aligned rectangle bounded
# by [x_min, x_max] × [z_min, z_max]. Endpoint inside the rect counts
# as intersection.
static func _segment_crosses_aabb_xz(
		fx: float, fz: float, tx: float, tz: float,
		x_min: float, x_max: float, z_min: float, z_max: float) -> bool:
	var dx: float = tx - fx
	var dz: float = tz - fz
	var t_min: float = 0.0
	var t_max: float = 1.0
	# X slab.
	if absf(dx) < 0.0001:
		if fx < x_min or fx > x_max:
			return false
	else:
		var t1: float = (x_min - fx) / dx
		var t2: float = (x_max - fx) / dx
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return false
	# Z slab.
	if absf(dz) < 0.0001:
		if fz < z_min or fz > z_max:
			return false
	else:
		var t1: float = (z_min - fz) / dz
		var t2: float = (z_max - fz) / dz
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return false
	return true


# True when `p` sits inside either inflated cage frame box (the same
# inflation carry_path_blocked_by_net tests against).
static func point_in_cage_box(p: Vector3) -> bool:
	if absf(p.x) > GameRules.NET_BACK_HALF_WIDTH + CARRY_NET_CLEAR_MARGIN_M:
		return false
	var az: float = absf(p.z)
	return az >= GameRules.GOAL_LINE_Z - CARRY_NET_CLEAR_MARGIN_M \
			and az <= GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH \
					+ CARRY_NET_CLEAR_MARGIN_M


# True iff the segment from `from` to `to` (in world XZ) intersects either
# net's PHYSICAL footprint: the back-frame half-width (NET_BACK_HALF_WIDTH,
# wider than the post span — GameRules.is_over_net_footprint's reading)
# inflated by the puck's radius, since the puck's EDGE clanks the frame. Do not
# narrow it to the post line: a feed from below the goal line would read clear
# and ring off the outside of the cage.
static func pass_lane_blocked_by_net(from: Vector3, to: Vector3) -> bool:
	var goal_line_z: float = GameRules.GOAL_LINE_Z - GameRules.PUCK_COLLISION_RADIUS
	var net_half_w: float = GameRules.NET_BACK_HALF_WIDTH + GameRules.PUCK_COLLISION_RADIUS
	var net_back_z: float = GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH \
			+ GameRules.PUCK_COLLISION_RADIUS
	# Team 0's net (positive z).
	if _segment_crosses_aabb_xz(
			from.x, from.z, to.x, to.z,
			-net_half_w, net_half_w,
			goal_line_z, net_back_z):
		return true
	# Team 1's net (negative z), mirrored.
	if _segment_crosses_aabb_xz(
			from.x, from.z, to.x, to.z,
			-net_half_w, net_half_w,
			-net_back_z, -goal_line_z):
		return true
	return false

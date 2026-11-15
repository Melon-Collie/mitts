class_name AINetObstacle

# Segment tests on the ice plane against the two cages and our own slot: what
# a pass, a carry or a blade target may not pass through. A leaf (GameRules,
# CreaseRules, CarryPostureRules and AIBotMechanics only).

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


# ── Our own goal mouth as a CARRIED puck's no-go ─────────────────────────────
# The twine holds a carried puck at its surface rather than stripping it, so
# nothing in the physics stops a carrier dragging the puck over his own goal
# line between the posts: that is a goal. A carried puck goes where the blade
# cursor is, so the cursor is the one place to forbid it.
#
# The mouth: the span a puck riding anywhere on the blade crosses the line
# inside — the post centrelines, the pipe and the puck's radius, and half a
# blade either side of mid-blade, which the cursor names — from the top of the
# crease back to the cage's back frame.
const OWN_MOUTH_HALF_WIDTH_M: float = GameRules.NET_HALF_WIDTH + GameRules.NET_POST_RADIUS \
		+ GameRules.PUCK_COLLISION_RADIUS + 0.5 * GameRules.DEFAULT_BLADE_LENGTH_M
const OWN_MOUTH_DEPTH_M: float = CreaseRules.ARC_RADIUS
# Where a target forced out of the mouth goes: wide of the cage frame by the
# blade standoff net_safe_blade_target keeps, so the blade is not pressed onto
# a post, whose pipe strips the puck.
const OWN_MOUTH_EXIT_HALF_WIDTH_M: float = GameRules.NET_BACK_HALF_WIDTH \
		+ BLADE_NET_CLEAR_MARGIN_M
# How far in front of the line it goes out, when the puck is in front: the
# puck's radius and half a blade, so no part of it is over the line.
const OWN_MOUTH_EXIT_FRONT_M: float = GameRules.PUCK_COLLISION_RADIUS \
		+ 0.5 * GameRules.DEFAULT_BLADE_LENGTH_M


# How far a carrier's BODY keeps off that mouth: the puck rides out to the carry
# ring ahead of him (AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M) and his stick
# swings it anywhere round him, so nearer than that the puck can be in it. The
# routes he plans skate round this (AICarryRollout.reach_short_of_net, the
# waypoints round our cage, the walkouts), which is what keeps him wide of our
# posts and off our net front; own_mouth_safe_blade_target is the backstop.
const OWN_MOUTH_KEEP_OUT_M: float = AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M


# How far a carrier's body at `p` stands inside the keep-out of our own mouth
# (m; ≤ 0 outside it): the keep-out less his distance to the mouth's front —
# the span between the posts from the goal line to the top of the crease, the
# one way in. Only in front of the line: behind it the cage stands between him
# and the mouth, so he may hug the back of it, and the keep-out is where he
# comes out past the post.
static func own_mouth_keep_out_depth(p: Vector3, own_goal_dir: float) -> float:
	var in_front: float = GameRules.GOAL_LINE_Z - p.z * own_goal_dir
	if in_front < 0.0:
		return in_front
	var out_x: float = maxf(absf(p.x) - OWN_MOUTH_HALF_WIDTH_M, 0.0)
	return OWN_MOUTH_KEEP_OUT_M \
			- Vector2(out_x, maxf(in_front - OWN_MOUTH_DEPTH_M, 0.0)).length()


# Beside our cage on the side of `x`, at the edge of our mouth's keep-out and
# half the cage's depth behind the goal line: the way past our post a puck
# behind our line is come to, or taken round, wide of the mouth.
static func own_post_side_waypoint(x: float, own_goal_dir: float) -> Vector3:
	var side: float = signf(x) if x != 0.0 else 1.0
	return Vector3(side * (OWN_MOUTH_HALF_WIDTH_M + OWN_MOUTH_KEEP_OUT_M), 0.0,
			own_goal_dir * (GameRules.GOAL_LINE_Z + 0.5 * GameRules.NET_DEPTH))


# Whether a carrier skating straight from `from` to `to` takes his body deeper
# into our own mouth's keep-out than `from` stands, sampled every
# KEEP_OUT_STEP_M along the line: a route that must go round it.
const KEEP_OUT_STEP_M: float = 0.25
static func carry_path_enters_own_keep_out(from: Vector3, to: Vector3,
		own_goal_dir: float) -> bool:
	var start: float = maxf(own_mouth_keep_out_depth(from, own_goal_dir), 0.0)
	var length: float = Vector2(to.x - from.x, to.z - from.z).length()
	var steps: int = ceili(length / KEEP_OUT_STEP_M)
	for i: int in range(1, steps + 1):
		var p: Vector3 = from.lerp(to, float(i) / float(steps))
		if own_mouth_keep_out_depth(p, own_goal_dir) > start:
			return true
	return false


# Whether the carried puck, aimed at `target` while the body travels at
# `self_velocity`, is in or crossing our own goal mouth over the next
# `horizon_s` (the blade's time to take the puck clear of it).
static func carried_puck_in_own_mouth(target: Vector3, self_velocity: Vector3,
		own_goal_dir: float, horizon_s: float) -> bool:
	return _crosses_own_mouth(target, target + self_velocity * horizon_s, own_goal_dir)


# A carrier's blade target kept out of our own goal mouth. The puck is not at
# the cursor but where the carry holds it, no nearer than the floor
# (`floor_band`: the carry's floor standing and under its skating fold) along
# the cursor's bearing, or along `facing` with the cursor on his centre; and on
# its way there it is wherever the blade has it now (`puck_at`). Three ways in:
#
#   - held in the mouth, or dragged through it by the body's travel within
#     `horizon_s`: the target goes out wide of the post on the body's own side,
#     at the held depth unless the floor would pull it back in from there, when
#     it goes up the ice from the body until the floor is met;
#   - the puck in the mouth already, or dragged into it: the same;
#   - the puck's way from where it is to the target crossing the mouth (round
#     the cage from in front of the line to behind it, say): the target is the
#     way round the post on the puck's side, wide of the cage at the target's
#     depth, until the straight way on is clear.
#
# Any other target returns unchanged.
static func own_mouth_safe_blade_target(self_pos: Vector3, self_velocity: Vector3,
		facing: Vector2, target: Vector3, floor_band: Vector2, own_goal_dir: float,
		horizon_s: float, puck_at: Vector3) -> Vector3:
	var offset := Vector2(target.x - self_pos.x, target.z - self_pos.z)
	var near: Vector2 = CarryPostureRules.held_out_along(offset, facing, floor_band.x)
	var far: Vector2 = CarryPostureRules.held_out_along(offset, facing, floor_band.y)
	var held_in: bool = carried_puck_in_own_mouth(
			Vector3(self_pos.x + near.x, 0.0, self_pos.z + near.y),
			self_velocity, own_goal_dir, horizon_s) \
			or carried_puck_in_own_mouth(Vector3(self_pos.x + far.x, 0.0, self_pos.z + far.y),
					self_velocity, own_goal_dir, horizon_s)
	if held_in or carried_puck_in_own_mouth(puck_at, self_velocity, own_goal_dir, horizon_s):
		var side: float = signf(self_pos.x)
		if side == 0.0:
			side = signf(self_velocity.x) if self_velocity.x != 0.0 else 1.0
		var dx: float = side * OWN_MOUTH_EXIT_HALF_WIDTH_M - self_pos.x
		var dz: float = near.y
		if dx * dx + dz * dz < floor_band.y * floor_band.y:
			dz = -own_goal_dir * sqrt(maxf(floor_band.y * floor_band.y - dx * dx, 0.0))
		var exit := Vector3(self_pos.x + dx, 0.0, self_pos.z + dz)
		# The puck goes out on its own side of the line: from in front to behind,
		# the straight way crosses the line inside the post; from behind to in
		# front, it wraps the post into the mouth. Round the cage after.
		var line_z: float = own_goal_dir * GameRules.GOAL_LINE_Z
		var puck_front: float = (line_z - puck_at.z) * own_goal_dir
		var exit_front: float = (line_z - exit.z) * own_goal_dir
		if puck_front > 0.0 and exit_front < OWN_MOUTH_EXIT_FRONT_M:
			exit.z = line_z - own_goal_dir * OWN_MOUTH_EXIT_FRONT_M
		elif puck_front <= 0.0 and exit_front > -OWN_MOUTH_EXIT_FRONT_M:
			exit.z = line_z + own_goal_dir * OWN_MOUTH_EXIT_FRONT_M
		return exit
	if _crosses_own_mouth(puck_at, target, own_goal_dir):
		var puck_side: float = signf(puck_at.x) if puck_at.x != 0.0 else signf(self_pos.x)
		return Vector3((puck_side if puck_side != 0.0 else 1.0) * OWN_MOUTH_EXIT_HALF_WIDTH_M,
				0.0, target.z)
	return target


# Whether a puck released from `from` in front of our goal line, along `dir`,
# crosses the line inside our mouth (the posts, the puck and half a blade):
# fired straight into our own cage. One released from behind the line meets the
# back of the cage, and one going away from the line never reaches it.
static func release_into_own_net(from: Vector3, dir: Vector3, own_goal_dir: float) -> bool:
	var line_z: float = own_goal_dir * GameRules.GOAL_LINE_Z
	var in_front: float = (line_z - from.z) * own_goal_dir
	var closing: float = dir.z * own_goal_dir
	if in_front < 0.0 or closing <= 0.0001:
		return false
	var at_x: float = from.x + dir.x * (in_front / closing)
	return absf(at_x) < OWN_MOUTH_HALF_WIDTH_M


# A stick WITHOUT the puck, from where it is (`from`), kept from reaching over our
# own goal line inside our mouth: its target goes no deeper than a puck's
# clearance in front of the line along its way there. Whatever it sweeps
# through on the way (a loose puck it picks up, a pass it deflects) leaves the
# blade at the line, not behind it, and a pickup pins the puck on the blade
# that far on. A stick behind the line is behind the cage, and one crossing the
# line wide of the posts is beside it: both are left alone.
static func own_line_safe_stick_target(from: Vector3, target: Vector3,
		own_goal_dir: float) -> Vector3:
	var line_z: float = own_goal_dir * GameRules.GOAL_LINE_Z
	var from_front: float = (line_z - from.z) * own_goal_dir
	var to_front: float = (line_z - target.z) * own_goal_dir
	if from_front < 0.0 or to_front >= OWN_MOUTH_EXIT_FRONT_M:
		return target
	var t: float = 0.0
	if from_front > OWN_MOUTH_EXIT_FRONT_M:
		t = (from_front - OWN_MOUTH_EXIT_FRONT_M) / (from_front - to_front)
	var at: Vector3 = from.lerp(target, t)
	var at_line: Vector3 = from.lerp(target, from_front / maxf(from_front - to_front, 0.0001))
	if absf(at_line.x) >= OWN_MOUTH_HALF_WIDTH_M:
		return target
	return Vector3(at.x, 0.0, line_z - own_goal_dir * OWN_MOUTH_EXIT_FRONT_M)


# Whether the body's travel (`velocity`) carries the puck at `puck` over our goal
# line inside our mouth within `horizon_s`: where the blade, held at its reach,
# cannot take it out faster than the body takes it in.
static func dragged_over_own_line(puck: Vector3, velocity: Vector3, own_goal_dir: float,
		horizon_s: float) -> bool:
	var in_front: float = (own_goal_dir * GameRules.GOAL_LINE_Z - puck.z) * own_goal_dir
	var closing: float = velocity.z * own_goal_dir
	if in_front < 0.0 or closing <= 0.0001 or in_front > closing * horizon_s:
		return false
	return absf(puck.x + velocity.x * (in_front / closing)) < OWN_MOUTH_HALF_WIDTH_M


# Whether the body's travel takes the puck at `puck`, already in our mouth,
# deeper into it: toward the middle of our goal line. A carrier skating it out of
# the mouth is taking it the other way.
static func drags_deeper_into_own_mouth(puck: Vector3, velocity: Vector3,
		own_goal_dir: float) -> bool:
	if not carried_puck_in_own_mouth(puck, Vector3.ZERO, own_goal_dir, 0.0):
		return false
	var to_middle := Vector2(-puck.x, own_goal_dir * GameRules.GOAL_LINE_Z - puck.z)
	return to_middle.dot(Vector2(velocity.x, velocity.z)) > 0.0


static func _crosses_own_mouth(from: Vector3, to: Vector3, own_goal_dir: float) -> bool:
	var near_z: float = own_goal_dir * (GameRules.GOAL_LINE_Z - OWN_MOUTH_DEPTH_M)
	var far_z: float = own_goal_dir * (GameRules.GOAL_LINE_Z + GameRules.NET_DEPTH)
	return _segment_crosses_aabb_xz(from.x, from.z, to.x, to.z,
			-OWN_MOUTH_HALF_WIDTH_M, OWN_MOUTH_HALF_WIDTH_M,
			minf(near_z, far_z), maxf(near_z, far_z))


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

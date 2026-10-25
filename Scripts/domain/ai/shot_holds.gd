class_name AIShotHolds
extends RefCounted

# Where a bot holds the puck for a charged release, and what each hold carries.
# A wrist shot fires from where the puck sits at the press, at the share of the
# bot's pace its load allows there (WristerLoad), so the carrier prices the holds
# the blade can put the puck in first and the state machine carries it to the
# winner. One instance per bot, configured from its own build: the carrier and
# the state machine read the same answers.
#
# Holds (solve_shot), index 0 the puck where it is: the best-loaded pocket
# (WristerPocket), and a reach out to either side of the shot line, which moves
# the whole tangent-cone geometry around a goalie in tight (the pull-across, the
# backhand tuck) at whatever pace the load leaves there. A skating carrier lists
# no hold past his backhand stop (FacingRules pivoting). A pull costs its real
# time (pull_time, _fill_pulled). A pulled hold sits at the handling reach; the
# load reads its bearing, not its distance. All vectors are world XZ, offsets
# off the body.

# A puck this near the body's centre has no bearing to load from.
const MIN_OFFSET_M: float = 0.05
# Segments the route to a hold is read in (an even count, so one point is its
# midpoint) for its closest pass by a man.
const ROUTE_SEGMENTS: int = 4

var is_left_handed: bool = false
var load_cfg: WristerLoad.Config = WristerLoad.Config.new()
var facing_cfg: FacingRules.Config = FacingRules.Config.new()
var unloaded_share: float = 0.6
var backhand_coefficient: float = 0.75
var handle_reach: float = 0.9
var blade_speed: float = 10.0
var facing_turn_rate: float = 6.0
# The cursor's swing round the body to a hold behind it (rad/s).
var arc_rate: float = 7.5

# solve_shot's holds: offset, share of pace, pull time. A quarter-turn that is
# the pocket itself is not listed twice.
var offset: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var share: Array[float] = [1.0, 1.0, 1.0, 1.0]
var pull_s: Array[float] = [0.0, 0.0, 0.0, 0.0]
# price_keep's odds the puck is still on the blade when each hold fires.
var keep: Array[float] = [1.0, 1.0, 1.0, 1.0]
var count: int = 0
# solve_arrival's hold for a shot from a spot a carry reaches, its share of pace
# and its odds of keeping the puck through the charge.
var arrival_offset: Vector2 = Vector2.ZERO
var arrival_share: float = 1.0
var arrival_keep: float = 1.0
# solve_pass's hold and the share the press waits for.
var pass_offset: Vector2 = Vector2.ZERO
var pass_share: float = 0.0
# The hand of the last share_at.
var is_backhand: bool = false
# The last pocket solved (solve_shot, pocket).
var pocket_result := WristerPocket.Result.new()

var _facing := FacingRules.Result.new()
var _load := WristerLoad.Result.new()
var _route := PackedVector2Array()


func configure_from(ctx: RoleContext) -> void:
	is_left_handed = ctx.self_forehand_perp_sign > 0.0
	load_cfg = ctx.self_wrister_load
	facing_cfg = ctx.self_carry_facing_rules
	unloaded_share = ctx.self_wrister_unloaded_share
	backhand_coefficient = ctx.self_backhand_power_coefficient
	handle_reach = ctx.self_handle_reach
	blade_speed = ctx.self_blade_speed
	facing_turn_rate = ctx.self_facing_turn_rate
	arc_rate = ctx.self_arc_rate


# Share of pace a release along `aim` carries with the puck at `puck_offset` and
# the body facing `facing`, which a wrist shot freezes at the press.
func share_at(puck_offset: Vector2, aim: Vector2, facing: Vector2) -> float:
	if puck_offset.length() < MIN_OFFSET_M:
		is_backhand = false
		return WristerLoad.power_share(0.0, 1.0, false, unloaded_share, backhand_coefficient)
	var s: float = WristerPocket.share_at(puck_offset, aim, facing, is_left_handed,
			load_cfg, unloaded_share, backhand_coefficient, _load)
	is_backhand = _load.is_backhand
	return s


# The best-loaded pocket for a release along `aim`, into pocket_result.
func pocket(aim: Vector2, velocity: Vector2, facing: Vector2) -> WristerPocket.Result:
	WristerPocket.solve(pocket_result, aim, velocity, facing, is_left_handed, load_cfg,
			facing_cfg, unloaded_share, backhand_coefficient, _facing, _load)
	return pocket_result


# The pocket's offset at the handling reach.
func pocket_offset() -> Vector2:
	return pocket_result.dir * handle_reach


# Where a charged pass needing `needed` of the pace holds the puck: where it is
# when that already carries the feed, else the pocket for it.
func solve_pass(aim: Vector2, puck_offset: Vector2, velocity: Vector2, facing: Vector2,
		needed: float) -> void:
	if share_at(puck_offset, aim, facing) >= needed:
		pass_offset = puck_offset
		pass_share = needed
		return
	pocket(aim, velocity, facing)
	pass_offset = pocket_offset()
	pass_share = minf(needed, pocket_result.power_share)


func solve_shot(aim: Vector2, puck_offset: Vector2, velocity: Vector2,
		facing: Vector2) -> void:
	offset[0] = puck_offset
	share[0] = share_at(puck_offset, aim, facing)
	pull_s[0] = 0.0
	pocket(aim, velocity, facing)
	_fill_pulled(1, pocket_result.dir, aim, pocket_result.facing, facing, velocity)
	count = 2
	for side: int in 2:
		var dir: Vector2 = aim.normalized().rotated(PI * 0.5 if side == 0 else -PI * 0.5)
		if dir.dot(pocket_result.dir) > 0.999:
			continue
		FacingRules.solve(_facing, facing, dir, velocity, false, false, is_left_handed,
				facing_cfg)
		if _facing.pivoting:
			continue
		_fill_pulled(count, dir, aim, _facing.target, facing, velocity)
		count += 1


# The hold a shot on arrival at a carry's spot is taken from: the best-loaded
# pocket for `aim` at `velocity`, or the reach to the shot line's other side when
# a man's stick makes the pocket the worse bet (share × keep). Each is kept
# through `t` from now, the body then at `at` (world), against every opponent's
# reachable stick (AICarrySpace).
func solve_arrival(aim: Vector2, velocity: Vector2, facing: Vector2, at: Vector3,
		t: float, opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array) -> void:
	pocket(aim, velocity, facing)
	arrival_offset = pocket_offset()
	arrival_share = pocket_result.power_share
	arrival_keep = _dwell_keep(at, arrival_offset, t, opponents, opponent_vels, opponent_caps)
	if arrival_keep >= 1.0:
		return
	var side: float = -1.0 if aim.cross(pocket_result.dir) > 0.0 else 1.0
	var dir: Vector2 = aim.normalized().rotated(side * PI * 0.5)
	FacingRules.solve(_facing, facing, dir, velocity, false, false, is_left_handed,
				facing_cfg)
	if _facing.pivoting:
		return
	var other: Vector2 = dir * handle_reach
	var other_share: float = share_at(other, aim, _facing.target)
	var other_keep: float = _dwell_keep(at, other, t, opponents, opponent_vels, opponent_caps)
	if other_share * other_keep > arrival_share * arrival_keep:
		arrival_offset = other
		arrival_share = other_share
		arrival_keep = other_keep


static func _dwell_keep(at: Vector3, off: Vector2, t: float, opponents: Array[Vector3],
		opponent_vels: Array[Vector3], opponent_caps: Array) -> float:
	return AICarrySpace.clearance_to_safety(AICarrySpace.reach_clearance(
			Vector3(at.x + off.x, 0.0, at.z + off.y), t, opponents, opponent_vels,
			opponent_caps, minf(t, AICarrySpace.CARRY_LUNGE_WINDOW_S)))


# Odds each solve_shot hold keeps the puck from `self_pos` (world) skating at
# `velocity`: the blade carries it along the route the cursor walks (BladeRoute
# to a hold in front, around the body to one behind `facing`), then it sits at
# the hold through `charge_s`, against every opponent's reachable stick
# (AICarrySpace). A stick sweeps its own reach faster than a pull crosses it, so
# a route that drags the puck nearer a man than it started is read where it
# passes closest to him as a puck sitting there.
# Fills keep[k] for every listed hold.
func price_keep(self_pos: Vector3, velocity: Vector2, facing: Vector2, charge_s: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array) -> void:
	var has_caps: bool = opponent_caps.size() == opponents.size()
	for k: int in count:
		var t_end: float = pull_s[k] + charge_s
		var k_keep: float = _dwell_keep(_world(self_pos, Vector2.ZERO, velocity, t_end),
				offset[k], t_end, opponents, opponent_vels, opponent_caps)
		if pull_s[k] > 0.0 and k_keep > 0.0:
			var t_mid: float = pull_s[k] * 0.5
			_fill_route(k, facing, velocity)
			k_keep = minf(k_keep, AICarrySpace.transit_clearance_to_safety(
					AICarrySpace.reach_clearance(
							_world(self_pos, _route[ROUTE_SEGMENTS / 2], velocity, t_mid),
							t_mid, opponents, opponent_vels, opponent_caps)))
			for i: int in opponents.size():
				if k_keep <= 0.0:
					break
				var man := Vector2(opponents[i].x - self_pos.x, opponents[i].z - self_pos.z) \
						+ (Vector2(opponent_vels[i].x, opponent_vels[i].z) - velocity) * t_mid
				var route_gap: float = _route_gap(man)
				if route_gap >= man.distance_to(offset[0]):
					continue
				var caps: AISkaterCaps = opponent_caps[i] if has_caps else null
				var stick: float = caps.blade_span if caps != null \
						else AICarrySpace.EVADE_STICK_REACH_M
				k_keep = minf(k_keep, AICarrySpace.clearance_to_safety(route_gap - stick))
		keep[k] = k_keep


func _fill_route(k: int, facing: Vector2, velocity: Vector2) -> void:
	_route.resize(ROUTE_SEGMENTS + 1)
	for j: int in ROUTE_SEGMENTS + 1:
		_route[j] = _route_point(k, facing, velocity, float(j) / ROUTE_SEGMENTS)


func _route_gap(p: Vector2) -> float:
	var gap: float = INF
	for j: int in ROUTE_SEGMENTS:
		gap = minf(gap, _segment_gap(p, _route[j], _route[j + 1]))
	return gap


static func _behind(from: Vector2, to: Vector2, facing: Vector2) -> bool:
	return to.dot(facing) < 0.0 and from.length() >= MIN_OFFSET_M


# The blade's time pulling the puck from `from` to `to` (offsets off the body
# facing `facing`, skating at `velocity`): BladeRoute's length at the blade speed
# to a spot in front; to one behind, the swing round (BladeRoute.swing_angle) at
# arc_rate, or the blade's travel if longer.
func pull_time(from: Vector2, to: Vector2, facing: Vector2, velocity: Vector2) -> float:
	var speed: float = maxf(blade_speed, 0.1)
	if not _behind(from, to, facing):
		return BladeRoute.length(from, to, facing) / speed
	return maxf(absf(_swing(from, to, facing, velocity)) / maxf(arc_rate, 0.1),
			from.distance_to(to) / speed)


func _swing(from: Vector2, to: Vector2, facing: Vector2, velocity: Vector2) -> float:
	return BladeRoute.swing_angle(from, to, facing, velocity, facing_cfg, is_left_handed)


# The point a fraction `frac` along the pull to hold `k`: BladeRoute to a hold in
# front, the swing round the body to one behind.
func _route_point(k: int, facing: Vector2, velocity: Vector2, frac: float) -> Vector2:
	var from: Vector2 = offset[0]
	var to: Vector2 = offset[k]
	if _behind(from, to, facing):
		return from.normalized().rotated(_swing(from, to, facing, velocity) * frac) \
				* lerpf(from.length(), to.length(), frac)
	return BladeRoute.point_along(from, to, facing,
			BladeRoute.length(from, to, facing) * frac)


static func _segment_gap(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / len_sq, 0.0, 1.0))


static func _world(self_pos: Vector3, off: Vector2, velocity: Vector2, t: float) -> Vector3:
	return Vector3(self_pos.x + off.x + velocity.x * t, 0.0,
			self_pos.z + off.y + velocity.y * t)


# A pulled hold along `dir`. The cursor on it turns the body toward `body`, but
# the press waits for that turn only when the turn is what loads the puck.
func _fill_pulled(k: int, dir: Vector2, aim: Vector2, body: Vector2,
		facing: Vector2, velocity: Vector2) -> void:
	offset[k] = dir * handle_reach
	var blade_s: float = pull_time(offset[0], offset[k], facing, velocity)
	var share_now: float = share_at(offset[k], aim, facing)
	var share_turned: float = share_at(offset[k], aim, body)
	if share_now >= share_turned - 0.001 or facing.length_squared() < 0.0001:
		share[k] = share_now
		pull_s[k] = blade_s
		return
	share[k] = share_turned
	pull_s[k] = maxf(blade_s, absf(facing.angle_to(body)) / maxf(facing_turn_rate, 0.1))

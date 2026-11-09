class_name AIShotHolds
extends RefCounted

# Where a bot holds the puck for a charged release, and what each hold carries.
# A wrist shot fires from where the puck sits at the press, at the share of the
# bot's pace its load allows there (WristerLoad), so the carrier prices the holds
# the blade can put the puck in first and the state machine carries it to the
# winner. One instance per bot, configured from its own build: the carrier and
# the state machine read the same answers.
#
# Every charged release comes from a listed spot, never from wherever the carry
# left the puck; that spot is only where each pull starts (origin), so a puck
# already sitting in one pulls to it in no time. Shots (solve_shot): the
# best-loaded pocket (WristerPocket); a reach out to either side of the shot
# line, which moves the whole tangent-cone geometry around a goalie in tight
# (the pull-across, the backhand tuck) at whatever pace the load leaves there;
# and the snapshot, out in front on the forehand where the carry presents the
# puck, so a shot in stride or off a catch leaves without a pull, at the share
# its load gives. A skating carrier lists no hold past his backhand stop
# (FacingRules pivoting). Passes go from one of the pocket's candidates
# (solve_pass, solve_pass_kept). A pull costs its real time (pull_time,
# _fill_pulled). All vectors are world XZ, offsets off the body.

# A puck this near the body's centre has no bearing to load from.
const MIN_OFFSET_M: float = 0.05
# Segments the route to a hold is read in (an even count, so one point is its
# midpoint) for its closest pass by a man.
const ROUTE_SEGMENTS: int = 4
# The snapshot's bearing off the shot line, toward the forehand: the puck ahead
# of the body, a third of the way round to the stick side. Off the line, never
# off the facing: the body turns to the cursor resting on it, and a spot that
# turned with the body would walk him round in a circle.
const SNAP_FOREHAND_RAD: float = PI / 6.0

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

# Where the puck sits off the body as the last solve read it: every pull's start.
var origin: Vector2 = Vector2.ZERO
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
# solve_pass's hold, the share the press waits for, and the wait before it
# (pass_wait).
var pass_offset: Vector2 = Vector2.ZERO
var pass_share: float = 0.0
var pass_pull_s: float = 0.0
# The hand of the last share_at.
var is_backhand: bool = false
# The last pocket solved (solve_shot, pocket).
var pocket_result := WristerPocket.Result.new()

# The last solve_pass's pocket: the blade's time there, the turn onto the
# pocket's facing, and the share it carries with the body as it faces now.
var _pass_blade_s: float = 0.0
var _pass_turn_s: float = 0.0
var _pass_share_now: float = 1.0

# Odds the last solve_pass_kept's pick is kept through the blade's pull and
# the charge.
var pass_keep: float = 1.0

var _cand := WristerPocket.Result.new()
# solve_pass_kept's candidates read up front, and their order best-loaded first.
var _cands: Array[WristerPocket.Result] = []
var _cand_ok := PackedByteArray()
var _cand_order := PackedInt32Array()
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
			facing_cfg, unloaded_share, backhand_coefficient, _facing, _load, _cand)
	return pocket_result


# The pocket's offset at the handling reach.
func pocket_offset() -> Vector2:
	return pocket_result.dir * handle_reach


# Where a charged pass needing `needed` of the pace holds the puck: the pocket
# for it, and the share it waits for there (no more than the pocket carries).
func solve_pass(aim: Vector2, puck_offset: Vector2, velocity: Vector2, facing: Vector2,
		needed: float) -> void:
	origin = puck_offset
	pocket(aim, velocity, facing)
	_fill_pass(aim, velocity, facing, needed)


# solve_pass with men about: of the pocket's candidates round the aim
# (WristerPocket.read_candidate), the one whose share of the feed — no more
# than it needs — times the odds the puck is kept there through the blade's
# pull and `charge_s` (keep_for, from `self_pos`), times `lane` (called with
# the offset and the blade's pull: the share of the feed from there that gets
# by the defence, 0 where it may not leave from at all) is best; the
# better-loaded on a tie. A passer with a man on one side releases from the
# other when it still carries the pace. Its keep is left in pass_keep.
func solve_pass_kept(aim: Vector2, puck_offset: Vector2, velocity: Vector2, facing: Vector2,
		needed: float, self_pos: Vector3, charge_s: float, opponents: Array[Vector3],
		opponent_vels: Array[Vector3], opponent_caps: Array,
		lane: Callable = Callable()) -> void:
	origin = puck_offset
	var best: float = -1.0
	pass_keep = 1.0
	if aim.length_squared() >= 0.000001:
		_read_candidates(aim, velocity, facing)
		for k: int in _cand_order:
			if _cand_ok[k] == 0:
				continue
			WristerPocket.copy(_cand, _cands[k])
			# Exact prunes: keep and lane are at most 1, so the load bounds the
			# value, and the keep bounds it again before the costlier lane read.
			# Read best-loaded first, a feed needing less than the pocket carries
			# ties every candidate that carries it, and the tie prunes them.
			var bound: float = minf(needed, _cand.power_share)
			if not _may_beat(bound, best):
				continue
			var off: Vector2 = _cand.dir * handle_reach
			var blade: float = pull_time(origin, off, facing, velocity)
			var kept: float = keep_for(off, blade, self_pos, velocity, facing, charge_s,
					opponents, opponent_vels, opponent_caps)
			if not _may_beat(bound * kept, best):
				continue
			var through: float = lane.call(off, blade) if lane.is_valid() else 1.0
			var v: float = bound * kept * through
			if through > 0.0 and _may_beat(v, best):
				best = v
				pass_keep = kept
				WristerPocket.copy(pocket_result, _cand)
	if best < 0.0:
		pocket(aim, velocity, facing)
	_fill_pass(aim, velocity, facing, needed)


# Reads every pocket candidate round `aim` into _cands (_cand_ok: the blade can
# hold the puck there), and orders them best-loaded first into _cand_order.
func _read_candidates(aim: Vector2, velocity: Vector2, facing: Vector2) -> void:
	var n: int = WristerPocket.CANDIDATE_COUNT
	if _cands.size() != n:
		_cands.clear()
		for i: int in n:
			_cands.append(WristerPocket.Result.new())
		_cand_ok.resize(n)
		_cand_order.resize(n)
	for k: int in n:
		_cand_ok[k] = 1 if WristerPocket.read_candidate(_cands[k], k, aim, velocity, facing,
				is_left_handed, load_cfg, facing_cfg, unloaded_share, backhand_coefficient,
				_facing, _load) else 0
		_cand_order[k] = k
	# Insertion sort on six: stable, so equal loads keep the pocket's own order.
	for i: int in range(1, n):
		var k: int = _cand_order[i]
		var j: int = i - 1
		while j >= 0 and _cands[_cand_order[j]].power_share < _cands[k].power_share:
			_cand_order[j + 1] = _cand_order[j]
			j -= 1
		_cand_order[j + 1] = k


# Whether solve_pass_kept's candidate in _cand, worth `v`, beats the best so far
# (`best`, held in pocket_result): a tie goes to the better-loaded.
func _may_beat(v: float, best: float) -> bool:
	return v > best or (v == best and _cand.power_share > pocket_result.power_share)


# pass_offset at pocket_result, and the wait (pass_wait) for `needed`.
func _fill_pass(aim: Vector2, velocity: Vector2, facing: Vector2, needed: float) -> void:
	pass_offset = pocket_offset()
	_pass_blade_s = pull_time(origin, pass_offset, facing, velocity)
	_pass_share_now = share_at(pass_offset, aim, facing) \
			if facing.length_squared() >= 0.0001 else pocket_result.power_share
	_pass_turn_s = absf(facing.angle_to(pocket_result.facing)) / maxf(facing_turn_rate, 0.1) \
			if facing.length_squared() >= 0.0001 else 0.0
	pass_pull_s = pass_wait(needed)


# The blade's pull alone to the last solve_pass's pocket.
func pass_blade_s() -> float:
	return _pass_blade_s


# The wait before the press of a feed from the last solve_pass's pocket needing
# `needed` of the pace, into pass_share: the blade's pull there, and the turn
# onto the pocket's facing too when the body as it faces now does not carry it.
func pass_wait(needed: float) -> float:
	pass_share = minf(needed, pocket_result.power_share)
	if _pass_share_now >= pass_share:
		return _pass_blade_s
	return maxf(_pass_blade_s, _pass_turn_s)


func solve_shot(aim: Vector2, puck_offset: Vector2, velocity: Vector2,
		facing: Vector2) -> void:
	origin = puck_offset
	pocket(aim, velocity, facing)
	_fill_pulled(0, pocket_result.dir, aim, pocket_result.facing, facing, velocity)
	count = 1
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
	var snap: Vector2 = snap_dir(aim)
	FacingRules.solve(_facing, facing, snap, velocity, false, false, is_left_handed, facing_cfg)
	if not _facing.pivoting:
		_fill_pulled(count, snap, aim, _facing.target, facing, velocity,
				AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M)
		count += 1


# The snapshot's direction for a shot along `aim` (SNAP_FOREHAND_RAD toward the
# stick side, the forehand's home side in WristerLoad's frame).
func snap_dir(aim: Vector2) -> Vector2:
	var stick_sign: float = 1.0 if is_left_handed else -1.0
	var yaw: float = atan2(-aim.x, -aim.y) + stick_sign * SNAP_FOREHAND_RAD
	return Vector2(-sin(yaw), -cos(yaw))


# The listed hold with the best share × keep (price_keep's), the first on a tie;
# -1 when none is listed.
func best_hold() -> int:
	var best: int = -1
	for k: int in count:
		if best < 0 or share[k] * keep[k] > share[best] * keep[best]:
			best = k
	return best


# The hold a shot on arrival at a carry's spot is taken from: the best-loaded
# pocket for `aim` at `velocity`, or the reach to the shot line's other side when
# a man's stick makes the pocket the worse bet (share × keep). Each is kept
# through `t` from now, the body then at `at` (world) after a carry from `from`,
# against every opponent's reachable stick (AICarrySpace).
func solve_arrival(aim: Vector2, velocity: Vector2, facing: Vector2, at: Vector3,
		t: float, opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array, from: Vector3 = Vector3.INF) -> void:
	pocket(aim, velocity, facing)
	arrival_offset = pocket_offset()
	arrival_share = pocket_result.power_share
	arrival_keep = _dwell_keep(at, arrival_offset, t, opponents, opponent_vels, opponent_caps,
			from)
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
	var other_keep: float = _dwell_keep(at, other, t, opponents, opponent_vels, opponent_caps,
			from)
	if other_share * other_keep > arrival_share * arrival_keep:
		arrival_offset = other
		arrival_share = other_share
		arrival_keep = other_keep


# The odds the puck sits at `at` + `off` through `t` unreached, carried there
# from `from`. A man chasing that carry from behind is on it there for the whole
# carry (AICarrySpace.reach_clearance): a puck in the shooting pocket is not
# shielded as a carried one is.
static func _dwell_keep(at: Vector3, off: Vector2, t: float, opponents: Array[Vector3],
		opponent_vels: Array[Vector3], opponent_caps: Array,
		from: Vector3 = Vector3.INF) -> float:
	var spot := Vector3(at.x + off.x, 0.0, at.z + off.y)
	return AICarrySpace.clearance_to_safety(AICarrySpace.reach_clearance(
			spot, t, opponents, opponent_vels, opponent_caps,
			minf(t, AICarrySpace.CARRY_LUNGE_WINDOW_S), Vector2.ZERO, 0.0, -INF, from))


# Odds each solve_shot hold keeps the puck from `self_pos` (world) skating at
# `velocity`: the blade carries it from origin along the route the cursor walks
# (BladeRoute to a hold in front, around the body to one behind `facing`), then
# it sits at the hold through `charge_s`, against every opponent's reachable
# stick (AICarrySpace). A stick sweeps its own reach faster than a pull crosses
# it, so a route that drags the puck nearer a man than it started is read where
# it passes closest to him as a puck sitting there.
# Fills keep[k] for every listed hold.
func price_keep(self_pos: Vector3, velocity: Vector2, facing: Vector2, charge_s: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array) -> void:
	for k: int in count:
		keep[k] = keep_for(offset[k], pull_s[k], self_pos, velocity, facing, charge_s,
				opponents, opponent_vels, opponent_caps)


# Odds a hold at `to` reached after `pull` keeps the puck through `charge_s`,
# as price_keep reads each listed hold, from the last solve's origin.
func keep_for(to: Vector2, pull: float, self_pos: Vector3, velocity: Vector2,
		facing: Vector2, charge_s: float, opponents: Array[Vector3],
		opponent_vels: Array[Vector3], opponent_caps: Array) -> float:
	var has_caps: bool = opponent_caps.size() == opponents.size()
	var t_end: float = pull + charge_s
	var k_keep: float = _dwell_keep(_world(self_pos, Vector2.ZERO, velocity, t_end),
			to, t_end, opponents, opponent_vels, opponent_caps)
	if pull <= 0.0 or k_keep <= 0.0:
		return k_keep
	var t_mid: float = pull * 0.5
	_fill_route(to, facing, velocity)
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
		if route_gap >= man.distance_to(origin):
			continue
		var caps: AISkaterCaps = opponent_caps[i] if has_caps else null
		var stick: float = caps.blade_span if caps != null \
				else AICarrySpace.EVADE_STICK_REACH_M
		k_keep = minf(k_keep, AICarrySpace.clearance_to_safety(route_gap - stick))
	return k_keep


func _fill_route(to: Vector2, facing: Vector2, velocity: Vector2) -> void:
	_route.resize(ROUTE_SEGMENTS + 1)
	for j: int in ROUTE_SEGMENTS + 1:
		_route[j] = _route_point(to, facing, velocity, float(j) / ROUTE_SEGMENTS)


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


# The point a fraction `frac` along the pull from origin to `to`: BladeRoute to
# a hold in front, the swing round the body to one behind.
func _route_point(to: Vector2, facing: Vector2, velocity: Vector2, frac: float) -> Vector2:
	if _behind(origin, to, facing):
		return origin.normalized().rotated(_swing(origin, to, facing, velocity) * frac) \
				* lerpf(origin.length(), to.length(), frac)
	return BladeRoute.point_along(origin, to, facing,
			BladeRoute.length(origin, to, facing) * frac)


static func _segment_gap(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / len_sq, 0.0, 1.0))


static func _world(self_pos: Vector3, off: Vector2, velocity: Vector2, t: float) -> Vector3:
	return Vector3(self_pos.x + off.x + velocity.x * t, 0.0,
			self_pos.z + off.y + velocity.y * t)


# A pulled hold along `dir` at `reach` (the handling reach by default). The
# cursor on it turns the body toward `body`, but the press waits for that turn
# only when the turn is what loads the puck.
func _fill_pulled(k: int, dir: Vector2, aim: Vector2, body: Vector2,
		facing: Vector2, velocity: Vector2, reach: float = -1.0) -> void:
	offset[k] = dir * (handle_reach if reach < 0.0 else reach)
	var blade_s: float = pull_time(origin, offset[k], facing, velocity)
	var share_now: float = share_at(offset[k], aim, facing)
	var share_turned: float = share_at(offset[k], aim, body)
	if share_now >= share_turned - 0.001 or facing.length_squared() < 0.0001:
		share[k] = share_now
		pull_s[k] = blade_s
		return
	share[k] = share_turned
	pull_s[k] = maxf(blade_s, absf(facing.angle_to(body)) / maxf(facing_turn_rate, 0.1))

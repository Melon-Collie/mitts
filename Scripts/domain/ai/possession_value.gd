class_name AIPossessionValue
extends RefCounted

# What the puck at a spot is worth to the side attacking `goal`, in the shot
# field's unit — the odds of the first shot that side gets to from it:
#
#   in the zone   the best of the shot from here, one straight drive in, and
#                 the best entry still ahead of him, skated to without crossing
#                 the line (a man near it is no worse off for being over it)
#   outside it    the best zone entry
#
# A drive is worth the shot where it ends × the odds of keeping the puck that
# far × the delay discount of the skate. An entry is a crossing of the line,
# anywhere along it (CROSSINGS samples): the better of the shot from a stride
# inside and the drive in from there, × the skate's delay discount, × the odds
# the puck is kept along the whole of it — the skate to the line, the contest at
# the line and the drive in — which is the worst of the three, so each defender
# is charged once. At the line (_line_keep) a defender inside the line shadows
# where the carrier is heading — he takes the carrier→net line at his own depth,
# if his skate gets him there before the carrier commits — and then has the
# lunge the carry search gives a defender at a carry's arrival (AICarrySpace
# .CARRY_LUNGE_WINDOW_S) to cover the crossing the carrier picks: a man set at
# his line covers the lane he shadows and what his lunge reaches of the rest,
# never the whole line; a man gapped back covers none of it and is the drive's
# to charge. One outside the line is where project_defender has him.
#
# An entry's shot and drive are read against the defence as it will be when he
# crosses (project_defender: a man behind the play backchecks), priced at
# FOLLOW_UP_TIMES and read between them. Each depends only on fill()'s defence,
# so it is priced once per fill, and only when a read could use it: its worth on
# empty ice, which a defence only lowers, bounds it until then.
#
# Every shot is against a keeper who tracked the play: set and square
# (AIShotValue.set_keeper). Not modelled: passes — one man carries — and the
# pace he crosses with: the drive in from an entry starts from rest.

# Where a side crosses: a stride past the line, at CROSSINGS points spread evenly
# between the two wall lanes.
const ENTRY_LEAD_M: float = 3.0
const ENTRY_WALL_INSET_M: float = 2.0
const CROSSINGS: int = 5
# When, from now, an entry's shot and drive are priced against the defence; read
# between them, and held past the last (s).
const FOLLOW_UP_TIMES: Array[float] = [0.0, 1.0, 2.0, 4.0]
# A drive in: straight at the net, at most this far, stopping this far out. Also
# how far a skate to an entry is priced as a carry: the read does not follow the
# defence's pursuit further.
const DRIVE_MAX_M: float = 12.0
const DRIVE_MIN_NET_DIST_M: float = 3.0
# Goalie halves memoized per fill (_goalie_half): a defence read prices the same
# few spots against every candidate body. Round-robin past this many.
const GOALIE_MEMO_CAP: int = 32
# Entry worths shared across reads (_SharedEntries): every bot on a side prices
# the same entries against the same defence in one AI batch. Round-robin past
# this many defences.
const SHARED_ENTRY_SLOTS: int = 4


# One defence's entry worths, keyed on the exact ice they were priced against.
# `generation` moves when the slot is handed to another defence, so a read that
# holds it can tell. Reads run on the AI worker alone (as AIShotOdds' do).
class _SharedEntries:
	var goal: Vector3 = Vector3.INF
	var defenders: Array[Vector3] = []
	var vels: Array[Vector3] = []
	var caps: Array = []
	# Per entry and follow-up time, ENTRY_FIELDS values (_price_entry): < 0 until
	# priced.
	var worth: Array[float] = []
	var generation: int = 0

	func matches(g: Vector3, d: Array[Vector3], v: Array[Vector3], c: Array) -> bool:
		return goal == g and defenders == d and vels == v and caps == c

	func claim(g: Vector3, d: Array[Vector3], v: Array[Vector3], c: Array,
			entries: int) -> void:
		goal = g
		defenders.assign(d)
		vels.assign(v)
		caps.assign(c)
		worth.resize(entries * FOLLOW_UP_TIMES.size() * ENTRY_FIELDS)
		worth.fill(-1.0)
		generation += 1


static var _shared: Array[_SharedEntries] = []
static var _shared_next: int = 0

var _goal: Vector3 = Vector3.ZERO
var _defenders: Array[Vector3] = []
var _defender_vels: Array[Vector3] = []
var _defender_caps: Array = []
var _entry_spots: Array[Vector3] = []
# Per entry and follow-up time, ENTRY_FIELDS values (_price_entry); < 0 until
# priced (_priced).
var _entry_worth: Array[float] = []
# _follow_up's result: the entry's shot, its drive's end shot × the drive's
# discount, and the drive's keep.
var _f_shot: float = 0.0
var _f_drive: float = 0.0
var _f_keep: float = 0.0
var _follow_defence: Array[Vector3] = []
var _follow_vels: Array[Vector3] = []
var _reached_defence: Array[Vector3] = []
var _reached_vels: Array[Vector3] = []
var _projected: Array[Vector3] = []
var _projected_vels: Array[Vector3] = []
var _skate_defence: Array[Vector3] = []
var _skate_vels: Array[Vector3] = []
var _line_defence: Array[Vector3] = []
var _line_vels: Array[Vector3] = []
# The depth of the line a side crosses.
var _line_z: float = 0.0
# The entries' worth on empty ice at _open_goal: _worth's bound.
var _open_goal: Vector3 = Vector3.INF
var _open_worth: Array[float] = []
var _open_fields: Array[float] = []
# _drive_keep's other result.
var _drive_reached_value: float = 0.0
var _no_one: Array[Vector3] = []
var _no_caps: Array = []
# Bodies push_defender added since fill(), and _worth's scratch for setting them
# aside.
var _pushed: int = 0
var _stash_pos: Array[Vector3] = []
var _stash_vel: Array[Vector3] = []
var _stash_caps: Array = []
# _goalie_half's memo: a shot's quality from `_memo_from` (`_memo_to` INF), or a
# feed's odds from `_memo_from` to `_memo_to`, against the keeper at
# `_memo_keeper`.
var _memo_from: Array[Vector3] = []
var _memo_to: Array[Vector3] = []
var _memo_keeper: Array[Vector3] = []
var _memo_value: Array[float] = []
var _memo_next: int = 0
# The shared slot this fill's entries live in, and its generation when taken.
var _slot: _SharedEntries = null
var _slot_generation: int = -1


# Reads the ice for the side attacking `goal` against `defenders` (velocities and
# caps index-matched) and prices its entries, unless `in_zone_only`: then only
# spots in the zone may be read. The arrays are read, not copied: refill them in
# place and call fill() again when the ice changes. push_defender appends to
# them, so a read that is pushed onto needs its three arrays distinct.
func fill(goal: Vector3, defenders: Array[Vector3], defender_vels: Array[Vector3],
		defender_caps: Array, in_zone_only: bool = false) -> void:
	_goal = goal
	_defenders = defenders
	_defender_vels = defender_vels
	_defender_caps = defender_caps
	_pushed = 0
	_memo_from.clear()
	_memo_to.clear()
	_memo_keeper.clear()
	_memo_value.clear()
	_memo_next = 0
	_entry_spots.clear()
	_entry_worth.clear()
	_slot = null
	if in_zone_only:
		return
	_line_z = signf(goal.z) * GameRules.BLUE_LINE_Z
	var z: float = signf(goal.z) * (GameRules.BLUE_LINE_Z + ENTRY_LEAD_M)
	var wide_x: float = GameRules.RINK_HALF_WIDTH - ENTRY_WALL_INSET_M
	for k: int in CROSSINGS:
		_entry_spots.append(Vector3(wide_x * (2.0 * k / (CROSSINGS - 1) - 1.0), 0.0, z))
		for _f: int in FOLLOW_UP_TIMES.size() * ENTRY_FIELDS:
			_entry_worth.append(-1.0)
	if goal != _open_goal:
		_price_open()


# The puck at `pos` for the side fill() priced, its man there `start_s` from now
# and moving at `vel` (his skate to an entry or down the drive starts from it), on
# his build `man_caps` (null: the league build).
func at(pos: Vector3, start_s: float = 0.0, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	var shot: float = 0.0
	if AIActionScoring.in_offensive_zone(pos, _goal):
		shot = _shot(pos) * AIActionScoring.delay_discount(start_s)
	return maxf(shot, play_on(pos, start_s, vel, man_caps))


# at() without the shot from `pos` itself: what the man there makes of the puck
# by skating on with it — the drive in from the zone, and the entries.
func play_on(pos: Vector3, start_s: float = 0.0, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	var best: float = 0.0
	if AIActionScoring.in_offensive_zone(pos, _goal):
		best = _drive(pos, start_s, vel, man_caps)
	return entry_at(pos, start_s, vel, best, man_caps)


# The best zone entry for the man at `pos` (as at() reads him), or `known` when
# none is worth more: a value already known prunes the entries it beats.
func entry_at(pos: Vector3, start_s: float, vel: Vector3, known: float,
		man_caps: AISkaterCaps = null) -> float:
	var best: float = known
	var skate_defence: Array[Vector3] = _defenders
	var skate_vels: Array[Vector3] = _defender_vels
	var projected: bool = false
	# A man already in the zone skates on to an entry without crossing the line,
	# and never back up to one behind him.
	var in_zone: bool = AIActionScoring.in_offensive_zone(pos, _goal)
	for i: int in _entry_spots.size():
		if in_zone and absf(pos.z) >= absf(_entry_spots[i].z):
			continue
		var t: float = start_s + AIArrival.time_to_arrive_caps(pos, _entry_spots[i], vel,
				man_caps)
		var discount: float = AIActionScoring.delay_discount(t)
		if _open_worth[i] * discount <= best:
			continue
		_follow_up(i, t)
		var shot: float = _f_shot
		var drive: float = _f_drive
		var drive_keep: float = _f_keep
		if maxf(shot, drive * drive_keep) * discount <= best:
			continue
		var keep: float = 1.0
		if not in_zone:
			var crossing := Vector3(_entry_spots[i].x, 0.0, _line_z)
			keep = _line_keep(crossing, start_s + AIArrival.time_to_arrive_caps(
					pos, crossing, vel, man_caps), pos, vel)
			if maxf(shot, drive) * keep * discount <= best:
				continue
		if start_s > 0.0 and not projected:
			projected = true
			_project(_skate_defence, _skate_vels, start_s, pos.z)
			skate_defence = _skate_defence
			skate_vels = _skate_vels
		keep = minf(keep, _skate_keep(pos, _entry_spots[i], vel, skate_defence, skate_vels,
				man_caps))
		best = maxf(best, maxf(shot * keep, drive * minf(keep, drive_keep)) * discount)
	return best


# The odds a crossing of the line at `crossing`, reached `t` from now by a
# carrier now at `carrier_pos` skating at `carrier_vel`, survives the defence
# there — a moving puck's band. Each defender is placed where he is as the
# carrier commits to it, the lunge window before. Inside the line, he shadows
# the carrier's natural crossing (_natural_crossing: where his skate is taking
# him) — on the carrier→net line at his own depth into the zone, if his skate
# gets him there (part way along if not) — since he can stand in one place, and
# a crossing the carrier picks late is the lunge's to cover. Outside the line,
# where project_defender has him.
func _line_keep(crossing: Vector3, t: float, carrier_pos: Vector3,
		carrier_vel: Vector3) -> float:
	if _defenders.is_empty():
		return 1.0
	var w: float = minf(t, AICarrySpace.CARRY_LUNGE_WINDOW_S)
	var commit: float = t - w
	var natural: Vector3 = _natural_crossing(carrier_pos, carrier_vel)
	var to_net := Vector3(_goal.x - natural.x, 0.0, _goal.z - natural.z).normalized()
	_line_defence.clear()
	_line_vels.clear()
	for k: int in _defenders.size():
		var p: Vector3 = _defenders[k]
		var v: Vector3 = _defender_vels[k]
		var depth: float = (p.z - natural.z) * signf(_goal.z)
		if depth <= 0.0 or absf(to_net.z) < 0.001:
			_line_defence.append(project_defender(p, v, commit, carrier_pos.z, _goal.z,
					_caps_of(k)))
			_line_vels.append(projected_vel)
			continue
		var shadow: Vector3 = natural + to_net * (depth / absf(to_net.z))
		var t_shadow: float = AIArrival.time_to_arrive_caps(p, shadow, v, _caps_of(k))
		if t_shadow <= commit:
			_line_defence.append(shadow)
			_line_vels.append(Vector3.ZERO)
		else:
			_line_defence.append(p.lerp(shadow, commit / t_shadow))
			_line_vels.append((shadow - p) / t_shadow)
	return AICarrySpace.transit_clearance_to_safety(AICarrySpace.reach_clearance(
			crossing, w, _line_defence, _line_vels, _defender_caps, w))


# Where on the line a carrier at `pos` skating at `vel` crosses if he holds his
# course: along it when it takes him at the line, else straight ahead; within
# the wall lanes.
func _natural_crossing(pos: Vector3, vel: Vector3) -> Vector3:
	var x: float = pos.x
	var toward: float = vel.z * signf(_goal.z)
	if toward > 0.1:
		x += vel.x * (absf(_line_z - pos.z) / toward)
	var wide_x: float = GameRules.RINK_HALF_WIDTH - ENTRY_WALL_INSET_M
	return Vector3(clampf(x, -wide_x, wide_x), 0.0, _line_z)


# Where a defender at `pos` skating at `vel`, built as `caps` (null: the league
# build), is `t` from now, against a carrier at depth `carrier_z` attacking the
# net at depth `goal_z`:
#
#   in front of the carrier, skating toward that net — backing off the carry:
#     backing off keeps his gap, and stopping is the one choice that leaves him
#     in the way, so he slides to a stop and stays;
#   in front of him otherwise — he carries on as he is until he is level with
#     the carrier, and is behind him from then;
#   behind him — he backchecks (_backcheck).
#
# His velocity then is left in projected_vel.
static func project_defender(pos: Vector3, vel: Vector3, t: float, carrier_z: float,
		goal_z: float, caps: AISkaterCaps = null) -> Vector3:
	projected_vel = vel
	if t <= 0.0:
		return pos
	var attack_z: float = signf(goal_z)
	var ahead: float = (pos.z - carrier_z) * attack_z
	if ahead > 0.0:
		if vel.z * attack_z > 0.0:
			var speed: float = Vector2(vel.x, vel.z).length()
			var t_stop: float = speed / AIArrival.REVERSAL_BRAKE_DECEL_M_S2
			var tb: float = minf(t, t_stop)
			var slide: float = speed * tb - 0.5 * AIArrival.REVERSAL_BRAKE_DECEL_M_S2 * tb * tb
			projected_vel = Vector3(vel.x, 0.0, vel.z) * (1.0 - tb / t_stop)
			return pos + Vector3(vel.x, 0.0, vel.z) * (slide / speed)
		var closing: float = -vel.z * attack_z
		var t_level: float = ahead / closing if closing > 0.0 else INF
		if t <= t_level:
			return AITrajectory.predict_at(pos, vel, t)
		pos = pos + vel * t_level
		t -= t_level
	return _backcheck(pos, vel, t, goal_z, caps)


# project_defender's other result: the projected man's velocity.
static var projected_vel: Vector3 = Vector3.ZERO


# A man behind the play `t` from now: he brakes out what speed he has away from
# home, the rest carrying on, then skates for the top of his house on the
# arrival clock, the share of the trip he has made by then along the way.
static func _backcheck(pos: Vector3, vel: Vector3, t: float, goal_z: float,
		caps: AISkaterCaps) -> Vector3:
	var home := Vector3(0.0, 0.0, goal_z - signf(goal_z) * AIZoneCoverage.HOUSE_TOP_DEPTH_M)
	var to_home := Vector3(home.x - pos.x, 0.0, home.z - pos.z)
	var dist: float = to_home.length()
	if dist < 0.01:
		projected_vel = Vector3.ZERO
		return home
	var h: Vector3 = to_home / dist
	var away: float = maxf(0.0, -(vel.x * h.x + vel.z * h.z))
	var brake: float = AIArrival.REVERSAL_BRAKE_DECEL_M_S2
	var t_shed: float = minf(t, away / brake)
	var v_rest: Vector3 = Vector3(vel.x, 0.0, vel.z) + h * away
	var m: Vector3 = pos + v_rest * t_shed - h * (away * t_shed - 0.5 * brake * t_shed * t_shed)
	var rest: float = t - t_shed
	if rest <= 0.0:
		projected_vel = v_rest - h * (away - brake * t_shed)
		return m
	var t_home: float = AIArrival.time_to_arrive_caps(m, home, v_rest, caps)
	if t_home <= rest:
		projected_vel = Vector3.ZERO
		return home
	projected_vel = (home - m) / t_home
	return m.lerp(home, rest / t_home)


# Defender `k`'s caps, when the read's caps are index-matched.
func _caps_of(k: int) -> AISkaterCaps:
	return _defender_caps[k] if _defender_caps.size() == _defenders.size() else null


# The odds the man at `from`, moving at `vel`, keeps the puck on his skate toward
# `entry` against `defence`: priced over the drive's own horizon (DRIVE_MAX_M),
# the rest of the way left to the contest at the line.
func _skate_keep(from: Vector3, entry: Vector3, vel: Vector3,
		defence: Array[Vector3], defence_vels: Array[Vector3], man_caps: AISkaterCaps) -> float:
	var leg: Vector3 = entry - from
	var d: float = leg.length()
	if d > DRIVE_MAX_M:
		leg *= DRIVE_MAX_M / d
	var t: float = AIArrival.time_to_arrive_caps(from, from + leg, vel, man_caps)
	return AICarrySpace.carry_safety(from, from + leg, t, defence, defence_vels,
			_defender_caps, true)


# Entry `i`'s shot and drive against the defence `t` from now, into _f_shot,
# _f_drive and _f_keep: read between the two FOLLOW_UP_TIMES either side.
func _follow_up(i: int, t: float) -> void:
	var times: Array[float] = FOLLOW_UP_TIMES
	var b: int = 0
	while b + 1 < times.size() and times[b + 1] <= t:
		b += 1
	var lo: int = _priced(i, b)
	if b + 1 >= times.size():
		_f_shot = _entry_worth[lo]
		_f_drive = _entry_worth[lo + 1]
		_f_keep = _entry_worth[lo + 2]
		return
	var hi: int = _priced(i, b + 1)
	var u: float = (t - times[b]) / (times[b + 1] - times[b])
	_f_shot = lerpf(_entry_worth[lo], _entry_worth[hi], u)
	_f_drive = lerpf(_entry_worth[lo + 1], _entry_worth[hi + 1], u)
	_f_keep = lerpf(_entry_worth[lo + 2], _entry_worth[hi + 2], u)


# Entry `i` at follow-up time `b` priced against fill()'s defence, with any body
# pushed since set aside: the index of its ENTRY_FIELDS values in _entry_worth.
func _priced(i: int, b: int) -> int:
	var base: int = (i * FOLLOW_UP_TIMES.size() + b) * ENTRY_FIELDS
	if _entry_worth[base] >= 0.0:
		return base
	var n: int = _pushed
	for _k: int in n:
		_stash_pos.push_back(_defenders.back())
		_stash_vel.push_back(_defender_vels.back())
		_stash_caps.push_back(_defender_caps.back() \
				if _defender_caps.size() == _defenders.size() else null)
		pop_defender()
	_shared_price(i, b, base)
	for _k: int in n:
		push_defender(_stash_pos.pop_back(), _stash_vel.pop_back(), _stash_caps.pop_back())
	return base


# Entry `i`'s worth on fill()'s defence as it stands, with the line and the skate
# free: what reaching it now can be worth at most.
func _worth(i: int) -> float:
	var base: int = _priced(i, 0)
	return maxf(_entry_worth[base], _entry_worth[base + 1] * _entry_worth[base + 2])


# Entry `i` at follow-up time `b` against fill()'s defence (no pushed bodies),
# into _entry_worth from `base`, from the shared slot when another read already
# priced it.
func _shared_price(i: int, b: int, base: int) -> void:
	if _slot == null or _slot.generation != _slot_generation:
		_slot = _find_slot()
		_slot_generation = _slot.generation
	if _slot.worth[base] < 0.0:
		_price_entry(_entry_spots[i], _slot.worth, base, FOLLOW_UP_TIMES[b])
	for f: int in ENTRY_FIELDS:
		_entry_worth[base + f] = _slot.worth[base + f]


func _find_slot() -> _SharedEntries:
	for slot: _SharedEntries in _shared:
		if slot.matches(_goal, _defenders, _defender_vels, _defender_caps):
			return slot
	var slot: _SharedEntries
	if _shared.size() < SHARED_ENTRY_SLOTS:
		slot = _SharedEntries.new()
		_shared.append(slot)
	else:
		slot = _shared[_shared_next]
		_shared_next = (_shared_next + 1) % SHARED_ENTRY_SLOTS
	slot.claim(_goal, _defenders, _defender_vels, _defender_caps, _entry_spots.size())
	return slot


func _price_open() -> void:
	_open_goal = _goal
	var defenders: Array[Vector3] = _defenders
	var vels: Array[Vector3] = _defender_vels
	var caps: Array = _defender_caps
	_defenders = _no_one
	_defender_vels = _no_one
	_defender_caps = _no_caps
	_open_worth.clear()
	_open_fields.resize(ENTRY_FIELDS)
	for spot: Vector3 in _entry_spots:
		_price_entry(spot, _open_fields, 0, 0.0)
		_open_worth.append(maxf(_open_fields[0], _open_fields[1]))
	_defenders = defenders
	_defender_vels = vels
	_defender_caps = caps


# Values an entry is priced to, from `base` in `out`, against the defence `t`
# from now: the shot from it; the drive in from it, from rest, at its end's shot
# × the skate's discount; and the odds that drive keeps the puck.
const ENTRY_FIELDS: int = 3


func _price_entry(spot: Vector3, out: Array[float], base: int, t: float) -> void:
	_project(_follow_defence, _follow_vels, t, spot.z)
	out[base] = _shot_vs(spot, _follow_defence)
	out[base + 2] = _drive_keep(spot, t)
	out[base + 1] = _drive_reached_value
	if out[base + 2] <= 0.0:
		out[base + 1] = 0.0


# Every defender `t` from now against a carrier at depth `carrier_z`
# (project_defender), into `out` and his velocity then into `out_vels`,
# index-matched to the read's defenders.
func _project(out: Array[Vector3], out_vels: Array[Vector3], t: float,
		carrier_z: float) -> void:
	out.clear()
	out_vels.clear()
	for k: int in _defenders.size():
		out.append(project_defender(_defenders[k], _defender_vels[k], t, carrier_z, _goal.z,
				_caps_of(k)))
		out_vels.append(projected_vel)


func _shot(pos: Vector3) -> float:
	return _shot_vs(pos, _defenders)


# _shot against `defence`, index-matched to the read's defenders.
func _shot_vs(pos: Vector3, defence: Array[Vector3]) -> float:
	return AIActionScoring.score_shoot_value(pos, _goal, Vector3.INF, defence, 0.0,
			AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, _defender_caps,
			_goalie_half(pos, Vector3.INF, Vector3.INF, 0.0))


# The defence-free half of a shot from `from` (`to` INF: AIActionScoring
# .shot_quality) or of a one-timer off a feed from `from` to `to` at `speed`
# (AIShotValue.feed), against the keeper at `keeper`.
func _goalie_half(from: Vector3, to: Vector3, keeper: Vector3, speed: float) -> float:
	for i: int in _memo_value.size():
		if _memo_from[i] == from and _memo_to[i] == to and _memo_keeper[i] == keeper:
			return _memo_value[i]
	var v: float = AIActionScoring.shot_quality(from, _goal, keeper) if not to.is_finite() \
			else AIShotValue.feed(from, to, speed, _goal, keeper, true)
	if _memo_value.size() < GOALIE_MEMO_CAP:
		_memo_from.append(from)
		_memo_to.append(to)
		_memo_keeper.append(keeper)
		_memo_value.append(v)
	else:
		_memo_from[_memo_next] = from
		_memo_to[_memo_next] = to
		_memo_keeper[_memo_next] = keeper
		_memo_value[_memo_next] = v
		_memo_next = (_memo_next + 1) % GOALIE_MEMO_CAP
	return v


# One straight drive at the net from `from`, the man there `start_s` from now at
# `vel`:
# credited as far as the path stays clear and at the odds it is kept that far
# (AICarrySpace's reachable sets, a man he out-skates beaten — as the carrier's
# own drive-in is), against the defence carried on to when he sets off.
func _drive(from: Vector3, start_s: float, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	var keep: float = _drive_keep(from, start_s, vel, man_caps)
	if keep <= 0.0:
		return 0.0
	return _drive_reached_value * keep * AIActionScoring.delay_discount(start_s)


# _drive's keep, leaving the shot where it ends × the skate's own discount in
# _drive_reached_value (0 for no drive).
func _drive_keep(from: Vector3, start_s: float, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	_drive_reached_value = 0.0
	var to_net := Vector3(_goal.x - from.x, 0.0, _goal.z - from.z)
	var d: float = to_net.length()
	if d <= DRIVE_MIN_NET_DIST_M + 0.1:
		return 0.0
	var target: Vector3 = from + to_net * (minf(DRIVE_MAX_M, d - DRIVE_MIN_NET_DIST_M) / d)
	if AINetObstacle.carry_path_blocked_by_net(from, target):
		return 0.0
	var defence: Array[Vector3] = _defenders
	var defence_vels: Array[Vector3] = _defender_vels
	if start_s > 0.0:
		_project(_projected, _projected_vels, start_s, from.z)
		defence = _projected
		defence_vels = _projected_vels
	var t: float = AIArrival.time_to_arrive_caps(from, target, vel, man_caps)
	var keep: float = AICarrySpace.carry_safety(from, target, t, defence, defence_vels,
			_defender_caps, true)
	if keep <= 0.0:
		return 0.0
	var reached: Vector3 = target
	if keep < 1.0:
		reached = AICarrySpace.carry_strip_point(from, target, t, defence,
				defence_vels, _defender_caps, true, true)
		if reached != target:
			t = AIArrival.time_to_arrive_caps(from, reached, vel, man_caps)
	_project(_reached_defence, _reached_vels, start_s + t, from.z)
	_drive_reached_value = _shot_vs(reached, _reached_defence) \
			* AIActionScoring.delay_discount(t)
	return keep


# ── The defence's read of a man ──────────────────────────────────────────────
# Read off a fill() whose `defenders` are the defence and whose `goal` is the
# net it defends. The keeper is where he stands.

# What a man at `pos`, moving at `vel`, threatens with the puck on his stick:
# his shot where he stands, or what possession of his spot is worth.
func threat_of_carrier(pos: Vector3, vel: Vector3, keeper: Vector3) -> float:
	var shot: float = 0.0
	# Outside the zone with the keeper home a shot is dead by the hole geometry.
	if AIActionScoring.in_offensive_zone(pos, _goal) \
			or keeper.distance_to(_goal) >= AIActionScoring.THREAT_GOALIE_HOME_M:
		shot = AIActionScoring.score_shoot_value(pos, _goal, keeper, _defenders, 0.0,
				AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
				_defender_caps, _goalie_half(pos, Vector3.INF, keeper, 0.0))
	return maxf(shot, at(pos, 0.0, vel))


# What a feed from `from` to a man at `to`, moving at `to_vel`, threatens: his
# one-timer off it, or the lane × his possession of the spot once it gets there.
func threat_of_feed(from: Vector3, to: Vector3, to_vel: Vector3,
		keeper: Vector3) -> float:
	if AINetObstacle.pass_lane_blocked_by_net(from, to):
		return 0.0
	var speed: float = AIPuckLane.expected_pass_speed(from, to)
	var lane: float = AIPuckLane.lane_clear(from, to, _defenders, speed,
			AIActionScoring.EMPTY_VEC3, _defender_caps)
	var odds: float = _goalie_half(from, to, keeper, speed) if lane > 0.0 else 0.0
	var one_timer: float = AIActionScoring.score_pass_value(from, to, _goal, keeper,
			_defenders, speed, _defender_caps, true, lane, odds)
	return maxf(one_timer, lane * at(to, from.distance_to(to) / maxf(speed, 0.1), to_vel))


# A hypothetical defender added to the read's (the caller's) arrays for a read,
# and taken off again: a candidate spot priced with our body on it. The entries
# keep their worth against fill()'s defence; the races and the zone read see him.
# Caps ride along only when the read's caps were index-matched.
func push_defender(pos: Vector3, vel: Vector3, caps: AISkaterCaps) -> void:
	if _defender_caps.size() == _defenders.size():
		_defender_caps.push_back(caps)
	_defenders.push_back(pos)
	_defender_vels.push_back(vel)
	_pushed += 1


func pop_defender() -> void:
	_pushed -= 1
	_defenders.pop_back()
	_defender_vels.pop_back()
	if _defender_caps.size() > _defenders.size():
		_defender_caps.pop_back()

class_name AIPossessionValue
extends RefCounted

# What the puck at a spot is worth to the side attacking `goal`, in the shot
# field's unit — the odds of the first shot that side gets to from it, against
# the defence as it stands:
#
#   in the zone   the best of the shot from here, one straight drive in, and
#                 the best zone entry, as outside it
#   outside it    the best zone entry × the skate there × the race to it
#
# A drive is worth the shot where it ends × the odds of keeping the puck that
# far × the delay discount of the skate. An entry is worth the better of its
# shot and the drive in from it, × the skate there — its delay discount, and the
# odds he keeps the puck on it (_skate_keep) — × the race to it: the side's man
# from the spot against the defence's first arrival (AIActionScoring
# .arrival_race, its band widened by the arrival clock's error). Entry worths
# depend only on fill()'s defence, so each is priced once per fill, and only
# when a read could use it: its worth on empty ice, which a defence only lowers,
# bounds it until then.
#
# Every shot is against a keeper who tracked the play: set and square
# (AIShotValue.set_keeper). Not modelled: passes — one man carries — and where
# the defence will be by the time he gets anywhere.

# Where a side enters: a stride past the line, in the middle and in each wall lane.
const ENTRY_LEAD_M: float = 3.0
const ENTRY_WALL_INSET_M: float = 2.0
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
		worth.resize(entries)
		worth.fill(-1.0)
		generation += 1


static var _shared: Array[_SharedEntries] = []
static var _shared_next: int = 0

var _goal: Vector3 = Vector3.ZERO
var _defenders: Array[Vector3] = []
var _defender_vels: Array[Vector3] = []
var _defender_caps: Array = []
var _entry_spots: Array[Vector3] = []
var _entry_worth: Array[float] = []   # < 0 until priced (_worth)
var _projected: Array[Vector3] = []
var _shot_defence: Array[Vector3] = []
var _skate_defence: Array[Vector3] = []
# The entries' worth on empty ice at _open_goal: _worth's bound.
var _open_goal: Vector3 = Vector3.INF
var _open_worth: Array[float] = []
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
	var z: float = signf(goal.z) * (GameRules.BLUE_LINE_Z + ENTRY_LEAD_M)
	var wide_x: float = GameRules.RINK_HALF_WIDTH - ENTRY_WALL_INSET_M
	for x: float in [-wide_x, 0.0, wide_x]:
		_entry_spots.append(Vector3(x, 0.0, z))
		_entry_worth.append(-1.0)
	if goal != _open_goal:
		_price_open()


# The puck at `pos` for the side fill() priced, its man there `start_s` from now
# and moving at `vel` (his skate to an entry or down the drive starts from it).
func at(pos: Vector3, start_s: float = 0.0, vel: Vector3 = Vector3.ZERO) -> float:
	var best: float = 0.0
	if AIActionScoring.in_offensive_zone(pos, _goal):
		best = maxf(_shot(pos) * AIActionScoring.delay_discount(start_s),
				_drive(pos, start_s, vel))
	return entry_at(pos, start_s, vel, best)


# The best zone entry for the man at `pos` (as at() reads him), or `known` when
# none is worth more: a value already known prunes the entries it beats.
func entry_at(pos: Vector3, start_s: float, vel: Vector3, known: float) -> float:
	var best: float = known
	for i: int in _entry_spots.size():
		var t: float = start_s + AIArrival.time_to_arrive(pos, _entry_spots[i], vel)
		var discount: float = AIActionScoring.delay_discount(t)
		if _open_worth[i] * discount <= best:
			continue
		var timed: float = _worth(i) * discount
		if timed <= best:
			continue
		timed *= AIActionScoring.arrival_race(_entry_spots[i], t, _defenders,
				_defender_vels, true)
		if timed <= best:
			continue
		var defence: Array[Vector3] = _defenders
		if start_s > 0.0:
			_skate_defence.clear()
			for k: int in _defenders.size():
				_skate_defence.append(AITrajectory.predict_at(_defenders[k],
						_defender_vels[k], start_s))
			defence = _skate_defence
		best = maxf(best, timed * _skate_keep(pos, _entry_spots[i], vel, defence))
	return best


# The odds the man at `from`, moving at `vel`, keeps the puck on his skate toward
# `entry` against `defence`: priced over the drive's own horizon (DRIVE_MAX_M),
# the rest of the way left to the race for the entry.
func _skate_keep(from: Vector3, entry: Vector3, vel: Vector3,
		defence: Array[Vector3]) -> float:
	var leg: Vector3 = entry - from
	var d: float = leg.length()
	if d > DRIVE_MAX_M:
		leg *= DRIVE_MAX_M / d
	var t: float = AIArrival.time_to_arrive(from, from + leg, vel)
	return AICarrySpace.carry_safety(from, from + leg, t, defence, _defender_vels,
			_defender_caps, true)


# Entry `i`'s worth against fill()'s defence, priced on first use with any body
# pushed since set aside.
func _worth(i: int) -> float:
	if _entry_worth[i] >= 0.0:
		return _entry_worth[i]
	var n: int = _pushed
	for _k: int in n:
		_stash_pos.push_back(_defenders.back())
		_stash_vel.push_back(_defender_vels.back())
		_stash_caps.push_back(_defender_caps.back() \
				if _defender_caps.size() == _defenders.size() else null)
		pop_defender()
	_entry_worth[i] = _shared_worth(i)
	for _k: int in n:
		push_defender(_stash_pos.pop_back(), _stash_vel.pop_back(), _stash_caps.pop_back())
	return _entry_worth[i]


# Entry `i` against fill()'s defence (no pushed bodies), from the shared slot
# when another read already priced it.
func _shared_worth(i: int) -> float:
	if _slot == null or _slot.generation != _slot_generation:
		_slot = _find_slot()
		_slot_generation = _slot.generation
	if _slot.worth[i] < 0.0:
		_slot.worth[i] = _price_entry(_entry_spots[i])
	return _slot.worth[i]


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
	for spot: Vector3 in _entry_spots:
		_open_worth.append(_price_entry(spot))
	_defenders = defenders
	_defender_vels = vels
	_defender_caps = caps


func _price_entry(spot: Vector3) -> float:
	return maxf(_shot(spot), _drive(spot, 0.0))


func _shot(pos: Vector3) -> float:
	return AIActionScoring.score_shoot_value(pos, _goal, Vector3.INF, _defenders, 0.0,
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
func _drive(from: Vector3, start_s: float, vel: Vector3 = Vector3.ZERO) -> float:
	var to_net := Vector3(_goal.x - from.x, 0.0, _goal.z - from.z)
	var d: float = to_net.length()
	if d <= DRIVE_MIN_NET_DIST_M + 0.1:
		return 0.0
	var target: Vector3 = from + to_net * (minf(DRIVE_MAX_M, d - DRIVE_MIN_NET_DIST_M) / d)
	if AINetObstacle.carry_path_blocked_by_net(from, target):
		return 0.0
	var defence: Array[Vector3] = _defenders
	if start_s > 0.0:
		_projected.clear()
		for i: int in _defenders.size():
			_projected.append(AITrajectory.predict_at(_defenders[i], _defender_vels[i], start_s))
		defence = _projected
	var t: float = AIArrival.time_to_arrive(from, target, vel)
	var keep: float = AICarrySpace.carry_safety(from, target, t, defence, _defender_vels,
			_defender_caps, true)
	if keep <= 0.0:
		return 0.0
	var reached: Vector3 = target
	if keep < 1.0:
		reached = AICarrySpace.carry_strip_point(from, target, t, defence,
				_defender_vels, _defender_caps, true, true)
		if reached != target:
			t = AIArrival.time_to_arrive(from, reached, vel)
	return _shot(reached) * keep * AIActionScoring.delay_discount(start_s + t)


# ── The defence's read of a man ──────────────────────────────────────────────
# Read off a fill() whose `defenders` are the defence and whose `goal` is the
# net it defends. The keeper is where he stands.

# What a man at `pos`, moving at `vel`, threatens with the puck on his stick:
# his shot where he stands, or what possession of his spot is worth; the man
# there `start_s` from now, against the defence carried on to then.
func threat_of_carrier(pos: Vector3, vel: Vector3, keeper: Vector3, start_s: float = 0.0) -> float:
	var shot: float = 0.0
	# Outside the zone with the keeper home a shot is dead by the hole geometry.
	if AIActionScoring.in_offensive_zone(pos, _goal) \
			or keeper.distance_to(_goal) >= AIActionScoring.THREAT_GOALIE_HOME_M:
		var defence: Array[Vector3] = _defenders
		if start_s > 0.0:
			_shot_defence.clear()
			for i: int in _defenders.size():
				_shot_defence.append(AITrajectory.predict_at(_defenders[i], _defender_vels[i], start_s))
			defence = _shot_defence
		shot = AIActionScoring.score_shoot_value(pos, _goal, keeper, defence, 0.0,
				AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
				_defender_caps, _goalie_half(pos, Vector3.INF, keeper, 0.0)) \
				* AIActionScoring.delay_discount(start_s)
	return maxf(shot, at(pos, start_s, vel))


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

class_name AIPossessionValue
extends RefCounted

# What the puck at a spot is worth to the side attacking `goal`: in the shot
# field's unit (at, play_on) or in the zone currency (p_next, p_exit, p_enter,
# worth, turnover_cost). The model is Scripts/domain/ai/CLAUDE.md → "Positional
# value"; each piece's own comment covers it.

# Where a side crosses: a stride past the line, at CROSSINGS points spread evenly
# between the two wall lanes.
const ENTRY_LEAD_M: float = 3.0
# Division guard on the side's odds from an ordinary entry, far below any entry
# the read can price.
const ENTRY_ODDS_GUARD: float = 0.001
const ENTRY_WALL_INSET_M: float = 2.0
const CROSSINGS: int = 5
# When, from now, an entry's shot and drive are priced against the defence; read
# between them, and held past the last (s).
const FOLLOW_UP_TIMES: Array[float] = [0.0, 1.0, 2.0, 4.0]
# The beat after an entry in which a teammate onside behind it follows in to
# take a pass (_mate_pass): a stride or two (s).
const PASS_BEAT_S: float = 1.0
# A drive in: straight at the net, at most this far, stopping this far out.
const DRIVE_MAX_M: float = 12.0
const DRIVE_MIN_NET_DIST_M: float = 3.0
# Goalie halves memoized per fill (_goalie_half): a defence read prices the same
# few spots against every candidate body. Round-robin past this many.
const GOALIE_MEMO_CAP: int = 32
# Entry worths shared across reads (AISharedEntries): every bot on a side prices
# the same entries against the same defence in one AI batch. Round-robin past
# this many defences.
const SHARED_ENTRY_SLOTS: int = 4
const _NO_SKATERS: Array[Vector3] = []


static var _shared: Array[AISharedEntries] = []
static var _shared_next: int = 0

var _goal: Vector3 = Vector3.ZERO
var _defenders: Array[Vector3] = []
var _defender_vels: Array[Vector3] = []
var _defender_caps: Array = []
# Who of fill()'s defence rides which attacker.
var _pairing := AIDefencePairing.new()
var _entry_spots: Array[Vector3] = []
# Per entry and follow-up time, ENTRY_FIELDS values (_price_entry); < 0 until
# priced (_priced).
var _entry_worth: Array[float] = []
# _follow_up's result: the entry's shot, its drive's end shot × the drive's
# discount, and the drive's keep.
var _f_shot: float = 0.0
var _f_drive: float = 0.0
var _f_keep: float = 0.0
var _f_pass: float = 0.0
var _follow_defence: Array[Vector3] = []
var _follow_vels: Array[Vector3] = []
var _reached_defence: Array[Vector3] = []
var _reached_vels: Array[Vector3] = []
# The defence as it will be when a skate read sets off later (_skate_keep), for
# the man at _leg_from setting off _leg_s from now, on the defence of
# _defence_gen (bumped whenever the read's defence changes).
var _leg_defence: Array[Vector3] = []
var _leg_vels: Array[Vector3] = []
var _leg_from: Vector3 = Vector3.INF
var _leg_s: float = -1.0
var _leg_gen: int = -1
var _defence_gen: int = 0
# The depth of the line a side crosses into the attacked zone (its own blue line
# is at -_line_z).
var _line_z: float = 0.0
# _p_cross's other results: where and when its best crossing is made.
var _cross_at: Vector3 = Vector3.ZERO
var _cross_s: float = 0.0
# The entries' worth on empty ice at _open_goal, at their best follow-up time:
# _worth's bound.
var _open_goal: Vector3 = Vector3.INF
var _open_worth: Array[float] = []
var _open_fields: Array[float] = []
# The mean of _open_worth: the unit p_enter counts entries in.
var _open_mean: float = 1.0
# The best shot on empty ice, from the doorstep: what bounds a pass's worth.
var _open_shot_cap: float = 1.0
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
var _slot: AISharedEntries = null
var _slot_generation: int = -1


# Reads the ice for the side attacking `goal` against `defenders` (velocities and
# caps index-matched) and prices its entries, unless `in_zone_only`: then only
# spots in the zone may be read. `attackers` (velocities index-matched) are that
# side's skaters other than the puck's holder, at `holder` (INF: nobody holds
# it), which the defence is paired to (_pair). The arrays are read, not copied:
# refill them in place and call fill() again when the ice changes. push_defender
# appends to the defence's, so a read that is pushed onto needs its three arrays
# distinct.
func fill(goal: Vector3, defenders: Array[Vector3], defender_vels: Array[Vector3],
		defender_caps: Array, in_zone_only: bool = false,
		attackers: Array[Vector3] = _NO_SKATERS, attacker_vels: Array[Vector3] = _NO_SKATERS,
		holder: Vector3 = Vector3.INF) -> void:
	_goal = goal
	_defenders = defenders
	_defender_vels = defender_vels
	_defender_caps = defender_caps
	_pairing.pair(goal, defenders, defender_vels, defender_caps, attackers, attacker_vels,
			holder)
	_pushed = 0
	_defence_gen += 1
	_memo_from.clear()
	_memo_to.clear()
	_memo_keeper.clear()
	_memo_value.clear()
	_memo_next = 0
	_entry_spots.clear()
	_entry_worth.clear()
	_slot = null
	_line_z = signf(goal.z) * GameRules.BLUE_LINE_Z
	if in_zone_only:
		return
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


# The odds the man at `pos` (as at() reads him) gets the puck into the next zone
# with it — out of his own zone, or into the attacked one — discounted to now as
# at() is: 1 once he is in it (at `start_s`). The zone currency
# (docs/zone-currency-plan.md).
func p_next(pos: Vector3, start_s: float = 0.0, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	if AIActionScoring.in_offensive_zone(pos, _goal):
		return AIActionScoring.delay_discount(start_s)
	if _in_own_zone(pos):
		return _p_cross(pos, start_s, vel, man_caps, -_line_z)
	return _p_cross(pos, start_s, vel, man_caps, _line_z)


# The odds the man at `pos` gets the puck out of his own zone with it: 1 (at
# `start_s`) once he is out.
func p_exit(pos: Vector3, start_s: float = 0.0, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	if not _in_own_zone(pos):
		return AIActionScoring.delay_discount(start_s)
	return _p_cross(pos, start_s, vel, man_caps, -_line_z)


# The entries the man at `pos` (as at() reads him) makes of the puck: the odds he
# gets it into the attacked zone, each counted by what the entry makes of the
# puck against the defence as it will be (its shot, its drive in, or the pass to
# a teammate following in: _price_entry) in units of the mean crossing on empty
# ice (_open_mean) — in the zone, where he stands (at()); from his own zone, the
# chain: out by the crossing he gets out through surest, then in from there.
func p_enter(pos: Vector3, start_s: float = 0.0, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	if AIActionScoring.in_offensive_zone(pos, _goal):
		return at(pos, start_s, vel, man_caps) / _open_mean
	if not _in_own_zone(pos):
		return _p_cross(pos, start_s, vel, man_caps, _line_z, true)
	var out: float = _p_cross(pos, start_s, vel, man_caps, -_line_z)
	if out <= 0.0:
		return 0.0
	return out / AIActionScoring.delay_discount(_cross_s) \
			* _p_cross(_cross_at, _cross_s, _exit_vel(pos, start_s, vel, man_caps), man_caps,
					_line_z, true)


# The man's velocity as he crosses at _cross_at / _cross_s, from `pos` at `vel`
# `start_s` from now: along his skate there, at the pace its stride ramp reaches.
func _exit_vel(pos: Vector3, start_s: float, vel: Vector3, man_caps: AISkaterCaps) -> Vector3:
	var dir := Vector3(_cross_at.x - pos.x, 0.0, _cross_at.z - pos.z).normalized()
	var vmax: float = man_caps.max_speed if man_caps != null else AIArrival.SKATER_REF_SPEED_M_S
	var accel: float = man_caps.max_accel if man_caps != null \
			else AIArrival.SHED_ACCEL_DEFAULT_M_S2
	return dir * maxf(0.0, AIStrideRamp.signed_speed_at(vel.dot(dir), _cross_s - start_s, vmax,
			accel, AIArrival.REVERSAL_BRAKE_DECEL_M_S2))


# What the side fill() priced is after with the puck, by where the man deciding
# for it plays (docs/zone-currency-plan.md): score in the attacked zone, get into
# it from the neutral zone, get out of its own.
enum Objective { SCORE, ENTER, EXIT }


func objective_at(decider: Vector3) -> int:
	if AIActionScoring.in_offensive_zone(decider, _goal):
		return Objective.SCORE
	if _in_own_zone(decider):
		return Objective.EXIT
	return Objective.ENTER


# The puck at `pos` (as at() reads it) in `objective`'s currency.
func worth(objective: int, pos: Vector3, start_s: float = 0.0,
		vel: Vector3 = Vector3.ZERO, man_caps: AISkaterCaps = null) -> float:
	if objective == Objective.ENTER:
		return p_enter(pos, start_s, vel, man_caps)
	if objective == Objective.EXIT:
		return p_exit(pos, start_s, vel, man_caps)
	return at(pos, start_s, vel, man_caps)


# What the side `ours` prices loses by losing the puck at `loss`, `loss_s` from
# now, in `objective`'s currency, `theirs` being the other side's read
# (Scripts/domain/ai/CLAUDE.md → "One currency across the carrier's compete").
static func turnover_cost(objective: int, loss: Vector3, loss_s: float,
		ours: AIPossessionValue, theirs: AIPossessionValue) -> float:
	if objective == Objective.SCORE:
		if AIActionScoring.in_offensive_zone(loss, ours._goal):
			return 0.0
		return theirs.at(loss, loss_s)
	if AIActionScoring.in_offensive_zone(loss, theirs._goal):
		return theirs.entries_handed(loss, loss_s)
	return theirs.p_enter(loss, loss_s)


# The side's scoring odds from `pos` counted in zone entries: against its odds
# from an ordinary entry, the middle a stride over the line, on the same read.
func entries_handed(pos: Vector3, start_s: float = 0.0) -> float:
	var entry := Vector3(0.0, 0.0, signf(_goal.z) * (GameRules.BLUE_LINE_Z + ENTRY_LEAD_M))
	return at(pos, start_s) / maxf(at(entry, start_s), ENTRY_ODDS_GUARD)


func _in_own_zone(pos: Vector3) -> bool:
	return AIActionScoring.in_offensive_zone(pos, Vector3(0.0, 0.0, -_goal.z))


# The best crossing of the blue line at depth `line_z` for the man at `pos` (as
# at() reads him): the strip odds of the skate there (_skate_keep), discounted to
# the crossing — and, with `quality`, × what the entry a stride past it makes of
# the puck then, in _open_mean's unit. Leaves where and when the best one crosses
# in _cross_at / _cross_s.
func _p_cross(pos: Vector3, start_s: float, vel: Vector3, man_caps: AISkaterCaps,
		line_z: float, quality: bool = false) -> float:
	var best: float = 0.0
	var wide_x: float = GameRules.RINK_HALF_WIDTH - ENTRY_WALL_INSET_M
	quality = quality and _open_worth.size() == CROSSINGS
	for k: int in CROSSINGS:
		var crossing := Vector3(wide_x * (2.0 * k / (CROSSINGS - 1) - 1.0), 0.0, line_z)
		var t: float = start_s + AIArrival.time_to_arrive_caps(pos, crossing, vel, man_caps)
		var discount: float = AIActionScoring.delay_discount(t)
		if quality:
			# Empty ice bounds the entry's own shot and drive, and the doorstep its
			# pass.
			if maxf(_open_worth[k], _open_shot_cap) / _open_mean * discount <= best:
				continue
			_follow_up(k, t)
			discount *= maxf(maxf(_f_shot, _f_drive * _f_keep), _f_pass) / _open_mean
		if discount <= best:
			continue
		var keep: float = _skate_keep(pos, crossing, start_s, t - start_s, man_caps)
		if keep * discount > best:
			best = keep * discount
			_cross_at = crossing
			_cross_s = t
	return best


# The best zone entry for the man at `pos` (as at() reads him), or `known` when
# none is worth more: a value already known prunes the entries it beats.
func entry_at(pos: Vector3, start_s: float, vel: Vector3, known: float,
		man_caps: AISkaterCaps = null) -> float:
	var best: float = known
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
		var skate_to: Vector3 = _entry_spots[i] if in_zone \
				else Vector3(_entry_spots[i].x, 0.0, _line_z)
		var keep: float = _skate_keep(pos, skate_to, start_s,
				AIArrival.time_to_arrive_caps(pos, skate_to, vel, man_caps), man_caps)
		best = maxf(best, maxf(shot * keep, drive * minf(keep, drive_keep)) * discount)
	return best


# Defender `k`'s caps, when the read's caps are index-matched.
func _caps_of(k: int) -> AISkaterCaps:
	return _defender_caps[k] if _defender_caps.size() == _defenders.size() else null


# The odds the man built as `man_caps` skating from `from` to `to` in `trip` s,
# setting off `start_s` from now, keeps the puck the whole way: the strip odds
# (AIStripOdds) against the defence as it will be when he sets off (_project,
# left in _leg_defence), read from then — the skate is his decision then, not a
# plan the defence can read now.
func _skate_keep(from: Vector3, to: Vector3, start_s: float, trip: float,
		man_caps: AISkaterCaps = null, find_cover: bool = false) -> float:
	if start_s <= 0.0:
		return AICarrySpace.carry_safety(from, to, trip, _defenders, _defender_vels,
				_defender_caps, 0.0, 0.0, man_caps, find_cover)
	if _leg_gen != _defence_gen or _leg_s != start_s or _leg_from != from:
		_project(_leg_defence, _leg_vels, start_s, from)
		_leg_gen = _defence_gen
		_leg_s = start_s
		_leg_from = from
	return AICarrySpace.carry_safety(from, to, trip, _leg_defence, _leg_vels,
			_defender_caps, 0.0, 0.0, man_caps, find_cover)


# Entry `i`'s shot, drive and pass against the defence `t` from now, into
# _f_shot, _f_drive, _f_keep and _f_pass: read between the two FOLLOW_UP_TIMES
# either side.
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
		_f_pass = _entry_worth[lo + 3]
		return
	var hi: int = _priced(i, b + 1)
	var u: float = (t - times[b]) / (times[b + 1] - times[b])
	_f_shot = lerpf(_entry_worth[lo], _entry_worth[hi], u)
	_f_drive = lerpf(_entry_worth[lo + 1], _entry_worth[hi + 1], u)
	_f_keep = lerpf(_entry_worth[lo + 2], _entry_worth[hi + 2], u)
	_f_pass = lerpf(_entry_worth[lo + 3], _entry_worth[hi + 3], u)


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


func _find_slot() -> AISharedEntries:
	for slot: AISharedEntries in _shared:
		if slot.matches(_goal, _defenders, _defender_vels, _defender_caps, _pairing.ride,
				_pairing.attackers, _pairing.attacker_vels):
			return slot
	var slot: AISharedEntries
	if _shared.size() < SHARED_ENTRY_SLOTS:
		slot = AISharedEntries.new()
		_shared.append(slot)
	else:
		slot = _shared[_shared_next]
		_shared_next = (_shared_next + 1) % SHARED_ENTRY_SLOTS
	slot.claim(_goal, _defenders, _defender_vels, _defender_caps, _pairing.ride,
			_pairing.attackers, _pairing.attacker_vels,
			_entry_spots.size() * FOLLOW_UP_TIMES.size() * ENTRY_FIELDS)
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
	var sum: float = 0.0
	for spot: Vector3 in _entry_spots:
		var open: float = 0.0
		for t: float in FOLLOW_UP_TIMES:
			_price_entry(spot, _open_fields, 0, t)
			open = maxf(open, maxf(_open_fields[0], _open_fields[1]))
		_open_worth.append(open)
		sum += open
	_open_mean = maxf(sum / CROSSINGS, ENTRY_ODDS_GUARD)
	_open_shot_cap = _shot_vs(Vector3(_goal.x, 0.0,
			_goal.z - signf(_goal.z) * DRIVE_MIN_NET_DIST_M), _no_one)
	_defenders = defenders
	_defender_vels = vels
	_defender_caps = caps


# Values an entry is priced to, from `base` in `out`, against the defence `t`
# from now: the shot from it; the drive in from it, carried up ice at the pace a
# skate of `t` from rest reaches (whoever enters, he has had that long to build
# it), at its end's shot × the skate's discount; the odds that drive keeps the
# puck; and the pass to a teammate following in (_mate_pass).
const ENTRY_FIELDS: int = 4


func _price_entry(spot: Vector3, out: Array[float], base: int, t: float) -> void:
	_project(_follow_defence, _follow_vels, t, spot)
	out[base] = _shot_vs(spot, _follow_defence)
	var pace: float = AIStrideRamp.speed_at(0.0, t, AIArrival.SKATER_REF_SPEED_M_S,
			AIArrival.SHED_ACCEL_DEFAULT_M_S2)
	out[base + 2] = _best_drive_keep(spot, t, Vector3(0.0, 0.0, signf(_goal.z) * pace))
	out[base + 1] = _drive_reached_value
	if out[base + 2] <= 0.0:
		out[base + 1] = 0.0
	out[base + 3] = _mate_pass(spot, t, _follow_defence, _follow_vels)


# The pass from an entry at `spot`, made `t` from now, to the teammate best placed
# to take it in the beat after (PASS_BEAT_S): one still onside behind the puck as
# it crosses who has followed in by then, priced at the lane to him × his shot
# there against `defence` (index-matched to the read's) × the discount of the
# beat and the flight. A teammate already in the zone is offside, and one still
# outside it has nothing to shoot.
func _mate_pass(spot: Vector3, t: float, defence: Array[Vector3],
		defence_vels: Array[Vector3]) -> float:
	var best: float = 0.0
	var mates: Array[Vector3] = _pairing.attackers
	var vels: Array[Vector3] = _pairing.attacker_vels
	for j: int in mates.size():
		if AIActionScoring.in_offensive_zone(AITrajectory.predict_at(mates[j], vels[j], t), _goal):
			continue
		var then: Vector3 = AITrajectory.predict_at(mates[j], vels[j], t + PASS_BEAT_S)
		if not AIActionScoring.in_offensive_zone(then, _goal) \
				or absf(then.x) > GameRules.RINK_HALF_WIDTH \
				or absf(then.z) > GameRules.GOAL_LINE_Z:
			continue
		var speed: float = AIPuckLane.expected_pass_speed(spot, then)
		var fed: float = _shot_vs(then, defence) \
				* AIActionScoring.delay_discount(PASS_BEAT_S + spot.distance_to(then) / speed)
		if fed <= best:
			continue
		if not defence.is_empty():
			fed *= AIPuckLane.lane_clear(spot, then, defence, speed, defence_vels,
					_defender_caps)
		best = maxf(best, fed)
	return best


# Every defender `t` from now against a carrier who is at `carrier` then
# (AIDefenderProjection, read against the puck's holder now; or riding his man,
# AIDefencePairing), into `out` and his velocity then into `out_vels`,
# index-matched to the read's defenders.
func _project(out: Array[Vector3], out_vels: Array[Vector3], t: float,
		carrier: Vector3) -> void:
	var now: Vector3 = _pairing.holder if _pairing.holder.is_finite() else carrier
	out.clear()
	out_vels.clear()
	for k: int in _defenders.size():
		if _pairing.rides(k):
			out.append(_pairing.ride_at(k, t))
			out_vels.append(AIDefencePairing.ride_vel)
		else:
			out.append(AIDefenderProjection.at(_defenders[k], _defender_vels[k], t, now, carrier,
					_goal, _caps_of(k)))
			out_vels.append(AIDefenderProjection.vel_then)


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
	var keep: float = _best_drive_keep(from, start_s, vel, man_caps)
	if keep <= 0.0:
		return 0.0
	return _drive_reached_value * keep * AIActionScoring.delay_discount(start_s)


# The better of the drive straight at the net and the one cutting in to the top
# of the slot, by its end's shot × its keep: _drive_keep's results for it. From
# the boards the drive at the net ends at a sharp angle the cut does not.
func _best_drive_keep(from: Vector3, start_s: float, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null) -> float:
	var keep: float = _drive_keep(from, start_s, vel, man_caps)
	var reached: float = _drive_reached_value
	var slot_top := Vector3(_goal.x, 0.0,
			_goal.z - signf(_goal.z) * (GameRules.SLOT_DIST_M + DRIVE_MIN_NET_DIST_M))
	var cut_keep: float = _drive_keep(from, start_s, vel, man_caps, slot_top)
	if _drive_reached_value * cut_keep > reached * keep:
		return cut_keep
	_drive_reached_value = reached
	return keep


# _drive's keep, leaving the shot where it ends × the skate's own discount in
# _drive_reached_value (0 for no drive): straight at the net to DRIVE_MIN_NET_DIST_M
# off it, or to `toward` when given; at most DRIVE_MAX_M either way.
func _drive_keep(from: Vector3, start_s: float, vel: Vector3 = Vector3.ZERO,
		man_caps: AISkaterCaps = null, toward: Vector3 = Vector3.INF) -> float:
	_drive_reached_value = 0.0
	var aim: Vector3 = toward if toward.is_finite() else _goal
	var stop: float = 0.0 if toward.is_finite() else DRIVE_MIN_NET_DIST_M
	var to_aim := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	var d: float = to_aim.length()
	if d <= stop + 0.1:
		return 0.0
	var target: Vector3 = from + to_aim * (minf(DRIVE_MAX_M, d - stop) / d)
	if AINetObstacle.carry_path_blocked_by_net(from, target):
		return 0.0
	var t: float = AIArrival.time_to_arrive_caps(from, target, vel, man_caps)
	var keep: float = _skate_keep(from, target, start_s, t, man_caps, true)
	if keep <= 0.0:
		return 0.0
	var reached: Vector3 = AIStripOdds.last_covered_at
	if reached != target:
		t = AIArrival.time_to_arrive_caps(from, reached, vel, man_caps)
	_project(_reached_defence, _reached_vels, start_s + t, from)
	_drive_reached_value = _shot_vs(reached, _reached_defence) \
			* AIActionScoring.delay_discount(t)
	return keep


# ── The defence's read of a man ──────────────────────────────────────────────
# Read off a fill() whose `defenders` are the defence and whose `goal` is the
# net it defends. The keeper is where he stands.

# What a man at `pos`, moving at `vel`, threatens with the puck on his stick, in
# `objective`'s currency (objective_at, read off the attack's play, so every man
# is weighed in one): scoring, his shot where he stands or his possession of the
# spot; otherwise his odds of the next line from there.
func threat_of_carrier(pos: Vector3, vel: Vector3, keeper: Vector3, objective: int) -> float:
	if objective != Objective.SCORE:
		return worth(objective, pos, 0.0, vel)
	var shot: float = AIActionScoring.score_shoot_value(pos, _goal, keeper, _defenders, 0.0,
			AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S,
			_defender_caps, _goalie_half(pos, Vector3.INF, keeper, 0.0)) \
			if AIActionScoring.in_offensive_zone(pos, _goal) \
					or keeper.distance_to(_goal) >= AIActionScoring.THREAT_GOALIE_HOME_M \
			else 0.0
	return maxf(shot, at(pos, 0.0, vel))


# What a feed from `from` to a man at `to`, moving at `to_vel`, threatens in
# `objective`'s currency: scoring, his one-timer off it or the lane × his
# possession of the spot once it gets there; otherwise the lane × his odds of the
# next line from there.
func threat_of_feed(from: Vector3, to: Vector3, to_vel: Vector3,
		keeper: Vector3, objective: int) -> float:
	if AINetObstacle.pass_lane_blocked_by_net(from, to):
		return 0.0
	var speed: float = AIPuckLane.expected_pass_speed(from, to)
	var lane: float = AIPuckLane.lane_clear(from, to, _defenders, speed,
			AIActionScoring.EMPTY_VEC3, _defender_caps)
	var flight: float = from.distance_to(to) / maxf(speed, 0.1)
	if objective != Objective.SCORE:
		return lane * worth(objective, to, flight, to_vel)
	var odds: float = _goalie_half(from, to, keeper, speed) if lane > 0.0 else 0.0
	var one_timer: float = AIActionScoring.score_pass_value(from, to, _goal, keeper,
			_defenders, speed, _defender_caps, true, lane, odds)
	return maxf(one_timer, lane * at(to, flight, to_vel))


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
	_defence_gen += 1


func pop_defender() -> void:
	_pushed -= 1
	_defence_gen += 1
	_defenders.pop_back()
	_defender_vels.pop_back()
	if _defender_caps.size() > _defenders.size():
		_defender_caps.pop_back()

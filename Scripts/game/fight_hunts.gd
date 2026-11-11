class_name FightHunts
extends RefCounted

# Host-only: who on each team has gone after a man to fight him, held by
# FightTracker. A team's hunt starts once one of its bots' grudge against a man
# (FightGrudges) reaches FightGrudgeRules.CHALLENGE_LEVEL, and one bot goes: the
# team's biggest, unless he is more than ENFORCER_DETOUR_M further from the man
# than its maddest, who goes instead. It lasts while the grudge that started it
# (the cause) is at ACCEPT_LEVEL or more — each refused challenge spends
# REFUSAL_COST of it — and ends when the man fights anyone on the hunting team,
# or either is gone. One hunt per team at a time.

signal hunt_started(hunter: Skater, target: Skater)
signal hunt_ended(hunter: Skater)

const TEAMS: Array[int] = [0, 1]

class Hunt:
	var hunter: Skater
	var target: Skater
	var cause_pid: int = -1     # the bot whose grudge sent him

var _registry: PlayerRegistry = null
var _grudges: FightGrudges = null
var _now_getter: Callable = Callable()       # () -> float, host seconds
var _carrier_getter: Callable = Callable()   # () -> Skater
var _takes_part: Callable = Callable()       # (Skater) -> bool: free to fight now
var _hunts: Dictionary = {}                  # team id -> Hunt


func setup(registry: PlayerRegistry, grudges: FightGrudges, now_getter: Callable,
		carrier_getter: Callable, takes_part: Callable) -> void:
	_registry = registry
	_grudges = grudges
	_now_getter = now_getter
	_carrier_getter = carrier_getter
	_takes_part = takes_part


# Ends the hunts that are over and starts the ones that are due.
func step() -> void:
	if _grudges == null or _registry == null:
		return
	var now: float = _now_getter.call()
	for team: int in TEAMS:
		var h: Hunt = _hunts.get(team, null)
		if h != null and not _still_on(h, team, now):
			_end(team)
		if not _hunts.has(team):
			_start_due(team, now)


func target_of(hunter: Skater) -> Skater:
	for team: int in TEAMS:
		var h: Hunt = _hunts.get(team, null)
		if h != null and h.hunter == hunter:
			return h.target
	return null


func is_hunting(hunter: Skater, target: Skater) -> bool:
	return hunter != null and target_of(hunter) == target


# The hunter's challenge went unanswered: it costs the grudge that sent him.
func note_refused(challenger: Skater, target: Skater) -> void:
	if not is_hunting(challenger, target):
		return
	var h: Hunt = _hunts[_team_of(challenger)]
	var target_pid: int = _registry.resolve_peer_id(target)
	var now: float = _now_getter.call()
	_grudges.raise(h.cause_pid, target_pid, -FightGrudgeRules.REFUSAL_COST, now)
	var hunter_pid: int = _registry.resolve_peer_id(challenger)
	if hunter_pid != h.cause_pid:
		_grudges.raise(hunter_pid, target_pid, -FightGrudgeRules.REFUSAL_COST, now)


# A fight started: a man hunted by the other's team has answered for it.
func note_fight(a: Skater, b: Skater) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var team: int = _team_of(pair[1])
		var h: Hunt = _hunts.get(team, null)
		if h != null and h.target == pair[0]:
			_grudges.settle(h.cause_pid, _registry.resolve_peer_id(pair[0]))
			_end(team)


func clear() -> void:
	for team: int in TEAMS:
		if _hunts.has(team):
			_end(team)


func _still_on(h: Hunt, team: int, now: float) -> bool:
	if not is_instance_valid(h.hunter) or not is_instance_valid(h.target) \
			or h.hunter.is_ghost or h.target.is_ghost \
			or _team_of(h.hunter) != team or _team_of(h.target) == team:
		return false
	return _grudges.level(h.cause_pid, _registry.resolve_peer_id(h.target), now) \
			>= FightGrudgeRules.ACCEPT_LEVEL


# The team's angriest grudge at the challenge level, if any, sends a man.
func _start_due(team: int, now: float) -> void:
	var cause_pid: int = -1
	var target_pid: int = -1
	var best: float = FightGrudgeRules.CHALLENGE_LEVEL
	for pid: int in _registry.bot_peers:
		if _registry.team_id_by_peer.get(pid, -1) != team:
			continue
		var who: int = _grudges.angriest_at(pid, now)
		if who == -1:
			continue
		var lv: float = _grudges.level(pid, who, now)
		if lv > best or (lv == best and (cause_pid == -1 or pid < cause_pid)):
			best = lv
			cause_pid = pid
			target_pid = who
	if cause_pid == -1:
		return
	var target: Skater = _skater_of(target_pid)
	if target == null or target.is_ghost or _team_of(target) == team:
		return
	var hunter: Skater = _elect(team, target, target_pid, now)
	if hunter == null:
		return
	var h := Hunt.new()
	h.hunter = hunter
	h.target = target
	h.cause_pid = cause_pid
	_hunts[team] = h
	hunt_started.emit(hunter, target)


# The biggest free bot on the team, unless the maddest is closer by more than
# the detour. Ties to the lower peer id.
func _elect(team: int, target: Skater, target_pid: int, now: float) -> Skater:
	var biggest: Skater = null
	var maddest: Skater = null
	var big_w: float = -INF
	var mad_lv: float = -INF
	var big_pid: int = 0
	var mad_pid: int = 0
	var carrier: Variant = _carrier_getter.call() if _carrier_getter.is_valid() else null
	for s: Skater in _registry.skaters():
		var pid: int = _registry.resolve_peer_id(s)
		if not _registry.bot_peers.has(pid) or _team_of(s) != team or s == carrier \
				or not _takes_part.call(s):
			continue
		if s.weight > big_w or (s.weight == big_w and pid < big_pid):
			big_w = s.weight
			big_pid = pid
			biggest = s
		var lv: float = _grudges.level(pid, target_pid, now)
		if lv > mad_lv or (lv == mad_lv and pid < mad_pid):
			mad_lv = lv
			mad_pid = pid
			maddest = s
	if biggest == null:
		return null
	var to: Vector3 = target.global_position
	if FightGrudgeRules.enforcer_goes(_flat_distance(biggest.global_position, to),
			_flat_distance(maddest.global_position, to)):
		return biggest
	return maddest


func _end(team: int) -> void:
	var h: Hunt = _hunts.get(team, null)
	_hunts.erase(team)
	if h != null and is_instance_valid(h.hunter):
		hunt_ended.emit(h.hunter)


func _team_of(s: Skater) -> int:
	return _registry.team_id_by_skater.get(s, -1)


func _skater_of(pid: int) -> Skater:
	for s: Skater in _registry.skaters():
		if _registry.resolve_peer_id(s) == pid:
			return s
	return null


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

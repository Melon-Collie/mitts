class_name FightTracker
extends RefCounted

# Host-only owner of every challenge and every fight (FightRules). It reads each
# skater's fight press (`Skater.fight_press_pending`, which it clears) and says
# when a fight starts and when the last one is over; GameManager blows the
# whistle and runs the faceoff after.
#
# A press by a man an open challenge is aimed at answers it, if he is still
# within FightRules.ACCEPT_RANGE_M of the challenger. Any other press challenges
# the opponent nearest in front of the presser (FightRules.can_challenge), unless
# he already has a challenge open, is cooling down from one that lapsed, or is
# carrying the puck. A bot never challenges, and answers every challenge at once.
# Nobody already fighting, down or ghosted takes part.
#
# A fight ends when the pair have been apart long enough or at the linesmen's cap
# (FightRules.end_of), or when either man is gone.

signal challenge_made(challenger: Skater, target: Skater)
signal challenge_lapsed(challenger: Skater)
signal fight_started(a: Skater, b: Skater)
signal fights_over

class Challenge:
	var target: Skater
	var expires_at: float

var _registry: PlayerRegistry = null
var _now_getter: Callable = Callable()        # () -> float, host seconds
var _carrier_getter: Callable = Callable()    # () -> Skater, the host's carrier or null
var _challenges: Dictionary = {}              # challenger Skater -> Challenge
var _cooling_until: Dictionary = {}           # Skater -> host seconds
var _partner: Dictionary = {}                 # Skater -> Skater, both ways round
var _started_at: Dictionary = {}              # Skater -> host seconds, both of a pair
var _apart_s: Dictionary = {}                 # Skater -> seconds, both of a pair


func setup(registry: PlayerRegistry, now_getter: Callable, carrier_getter: Callable) -> void:
	_registry = registry
	_now_getter = now_getter
	_carrier_getter = carrier_getter


# `allowed` is FightRules.allowed for this match; `phase` the game phase. A
# fight can start in any phase FightRules.phase_allows, and inside the stoppage
# another one already called.
func tick(delta: float, allowed: bool, phase: int) -> void:
	if _registry == null:
		return
	if not allowed:
		clear()
		return
	var open: bool = FightRules.phase_allows(phase) or phase == GamePhase.Phase.FIGHT
	if phase != GamePhase.Phase.FIGHT and not _partner.is_empty():
		_end_all()  # play went on without them (a manual reset): no faceoff to call
	_lapse_challenges()
	for skater: Skater in _registry.skaters():
		if not skater.fight_press_pending:
			continue
		skater.fight_press_pending = false
		if open:
			_on_press(skater)
	_step_fights(delta)


func is_fighting(skater: Skater) -> bool:
	return _partner.has(skater)


func partner_of(skater: Skater) -> Skater:
	return _partner.get(skater, null)


func challenge_target_of(challenger: Skater) -> Skater:
	var c: Challenge = _challenges.get(challenger, null)
	return c.target if c != null else null


# A stoppage, a rematch or a teardown: every challenge and fight goes, and so
# does every press nobody has read yet.
func clear() -> void:
	_challenges.clear()
	_cooling_until.clear()
	_end_all()
	if _registry == null:
		return
	for skater: Skater in _registry.skaters():
		skater.fight_press_pending = false


func _on_press(skater: Skater) -> void:
	if not _can_take_part(skater):
		return
	var challenger: Skater = _challenger_aimed_at(skater)
	if challenger != null:
		if FightRules.can_accept(_xz(skater), _xz(challenger)):
			_start(challenger, skater)
		return
	if _challenges.has(skater) or _now() < float(_cooling_until.get(skater, -INF)) \
			or _is_bot(skater) or _carries_puck(skater):
		return
	var target: Skater = _nearest_in_front(skater)
	if target == null:
		return
	var c := Challenge.new()
	c.target = target
	c.expires_at = _now() + FightRules.CHALLENGE_WINDOW_S
	_challenges[skater] = c
	challenge_made.emit(skater, target)
	if _is_bot(target):
		_start(skater, target)


func _can_take_part(skater: Skater) -> bool:
	return is_instance_valid(skater) and not _partner.has(skater) \
			and not skater.is_knocked_down and not skater.is_ghost


func _challenger_aimed_at(target: Skater) -> Skater:
	for key: Variant in _challenges.keys():
		var c: Challenge = _challenges[key]
		if c.target == target and is_instance_valid(key) and _can_take_part(key as Skater):
			return key as Skater
	return null


func _nearest_in_front(skater: Skater) -> Skater:
	var team: int = _registry.team_id_by_skater.get(skater, -1)
	var from: Vector2 = _xz(skater)
	var facing: Vector2 = skater.get_facing()
	var best: Skater = null
	var best_d2: float = INF
	for other: Skater in _registry.skaters():
		if other == skater or not _can_take_part(other):
			continue
		var other_team: int = _registry.team_id_by_skater.get(other, -1)
		if team == -1 or other_team == -1 or other_team == team:
			continue
		var to: Vector2 = _xz(other)
		if not FightRules.can_challenge(from, facing, to):
			continue
		var d2: float = from.distance_squared_to(to)
		if d2 < best_d2:
			best_d2 = d2
			best = other
	return best


func _start(a: Skater, b: Skater) -> void:
	_challenges.erase(a)
	_challenges.erase(b)
	var now: float = _now()
	_partner[a] = b
	_partner[b] = a
	_started_at[a] = now
	_started_at[b] = now
	_apart_s[a] = 0.0
	_apart_s[b] = 0.0
	fight_started.emit(a, b)


func _lapse_challenges() -> void:
	if _challenges.is_empty():
		return
	var now: float = _now()
	for key: Variant in _challenges.keys():
		var c: Challenge = _challenges[key]
		var gone: bool = not is_instance_valid(key) or not is_instance_valid(c.target)
		if not gone and now < c.expires_at:
			continue
		_challenges.erase(key)
		if gone:
			continue
		_cooling_until[key] = now + FightRules.CHALLENGE_COOLDOWN_S
		challenge_lapsed.emit(key as Skater)


func _step_fights(delta: float) -> void:
	if _partner.is_empty():
		return
	var now: float = _now()
	for key: Variant in _partner.keys():
		if not _partner.has(key):
			continue  # its pair ended earlier in this pass
		var other: Variant = _partner[key]
		if not is_instance_valid(key) or not is_instance_valid(other):
			_end(key, other)
			continue
		var a: Skater = key as Skater
		var b: Skater = other as Skater
		var apart: float = FightRules.step_apart(float(_apart_s.get(a, 0.0)),
				_xz(a).distance_to(_xz(b)), delta)
		_apart_s[a] = apart
		_apart_s[b] = apart
		var elapsed: float = now - float(_started_at.get(a, now))
		if FightRules.end_of(elapsed, apart) != FightRules.End.NONE:
			_end(a, b)
	if _partner.is_empty():
		fights_over.emit()


func _end_all() -> void:
	_partner.clear()
	_started_at.clear()
	_apart_s.clear()


# Takes Variants: either man may already be freed.
func _end(a: Variant, b: Variant) -> void:
	_partner.erase(a)
	_partner.erase(b)
	_started_at.erase(a)
	_started_at.erase(b)
	_apart_s.erase(a)
	_apart_s.erase(b)


func _is_bot(skater: Skater) -> bool:
	return _registry.bot_peers.has(_registry.resolve_peer_id(skater))


func _carries_puck(skater: Skater) -> bool:
	return _carrier_getter.is_valid() and _carrier_getter.call() == skater


func _now() -> float:
	return _now_getter.call() if _now_getter.is_valid() else 0.0


static func _xz(skater: Skater) -> Vector2:
	return Vector2(skater.global_position.x, skater.global_position.z)

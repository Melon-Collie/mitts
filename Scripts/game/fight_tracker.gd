class_name FightTracker
extends RefCounted

# Host-only owner of every challenge and every fight (FightRules). It reads each
# skater's fight press (`Skater.fight_press_pending`, which it clears), is the
# only writer of the replicated `Skater.fight_role`, and says when a fight starts
# and when the last one is over; GameManager blows the whistle and runs the
# faceoff after.
#
# A press by a man an open challenge is aimed at answers it, if he is still
# within FightRules.ACCEPT_RANGE_M of the challenger. Any other press challenges
# the opponent nearest in front of the presser (FightRules.can_challenge), unless
# he already has a challenge open, is cooling down from one that lapsed, or is
# carrying the puck. A bot has no press: it answers a challenge at once if its
# grudge against the challenger has reached FightGrudgeRules.ACCEPT_LEVEL, or if
# the challenger is hunting it (FightHunts: it has to answer for its hits), and
# otherwise lets it lapse; a hunter calls out the man it hunts once he is in
# front of it. A fight spends the pair's grudges. Nobody already fighting, down
# or ghosted takes part.
#
# A fight ends when either man goes down, when the pair have been apart long
# enough or at the linesmen's cap (FightRules.end_of), or when either man is gone.

signal challenge_made(challenger: Skater, target: Skater)
signal challenge_lapsed(challenger: Skater)
signal fight_started(a: Skater, b: Skater)
signal fights_over
signal hunt_started(hunter: Skater, target: Skater)
signal hunt_ended(hunter: Skater)

class Challenge:
	var target: Skater
	var expires_at: float

var _registry: PlayerRegistry = null
var _now_getter: Callable = Callable()        # () -> float, host seconds
var _carrier_getter: Callable = Callable()    # () -> Skater, the host's carrier or null
var _grudges: FightGrudges = null             # null: no bot ever wants to fight
var _challenges: Dictionary = {}              # challenger Skater -> Challenge
var _cooling_until: Dictionary = {}           # Skater -> host seconds
var _partner: Dictionary = {}                 # Skater -> Skater, both ways round
var _started_at: Dictionary = {}              # Skater -> host seconds, both of a pair
var _apart_s: Dictionary = {}                 # Skater -> seconds, both of a pair
var _hunts: FightHunts = null                 # with grudges only


func setup(registry: PlayerRegistry, now_getter: Callable, carrier_getter: Callable,
		grudges: FightGrudges = null) -> void:
	_registry = registry
	_now_getter = now_getter
	_carrier_getter = carrier_getter
	_grudges = grudges
	if grudges != null:
		_hunts = FightHunts.new()
		_hunts.setup(registry, grudges, _now, carrier_getter, _can_take_part)
		_hunts.hunt_started.connect(hunt_started.emit)
		_hunts.hunt_ended.connect(hunt_ended.emit)


# A credited body check (HitTracker.impact_landed): every bot on the hit man's
# team holds it against the hitter, the hit man most.
func note_check(hitter_pid: int, victim_pid: int, force: float) -> void:
	if _grudges == null or _registry == null:
		return
	var team: int = _registry.team_id_by_peer.get(victim_pid, -1)
	if team == -1 or _registry.team_id_by_peer.get(hitter_pid, -1) == team:
		return
	var now: float = _now()
	for pid: int in _registry.bot_peers:
		if pid == hitter_pid or _registry.team_id_by_peer.get(pid, -1) != team:
			continue
		var gain: float = FightGrudgeRules.victim_gain(force) if pid == victim_pid \
				else FightGrudgeRules.teammate_gain(force)
		_grudges.raise(pid, hitter_pid, gain, now)


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
	if open and _hunts != null:
		_hunts.step()
		_hunters_call_out()
	_step_fights(delta)


func is_fighting(skater: Skater) -> bool:
	return _partner.has(skater)


func partner_of(skater: Skater) -> Skater:
	return _partner.get(skater, null)


# The man this bot is skating after to fight, or null.
func hunt_target_of(hunter: Skater) -> Skater:
	return _hunts.target_of(hunter) if _hunts != null else null


func challenge_target_of(challenger: Skater) -> Skater:
	var c: Challenge = _challenges.get(challenger, null)
	return c.target if c != null else null


# A stoppage, a rematch or a teardown: every challenge and fight goes, and so
# does every press nobody has read yet. Sweeps every skater, not only the ones
# held here: the goal replay stamps its recorded fight_role onto the live actors.
func clear() -> void:
	if _hunts != null:
		_hunts.clear()
	_challenges.clear()
	_cooling_until.clear()
	_end_all()
	if _registry == null:
		return
	for skater: Skater in _registry.skaters():
		skater.fight_press_pending = false
		skater.fight_role = FightRules.Role.NONE


func _on_press(skater: Skater) -> void:
	if not _can_take_part(skater):
		return
	var challenger: Skater = _challenger_aimed_at(skater)
	if challenger != null:
		if FightRules.can_accept(_xz(skater), _xz(challenger)):
			_start(challenger, skater)
		return
	if not _may_call_out(skater):
		return
	var target: Skater = _nearest_in_front(skater)
	if target != null:
		_challenge(skater, target)


func _hunters_call_out() -> void:
	for skater: Skater in _registry.skaters():
		var target: Skater = _hunts.target_of(skater)
		if target == null or not _can_take_part(skater) or not _can_take_part(target) \
				or not _may_call_out(skater) \
				or not FightRules.can_challenge(_xz(skater), skater.get_facing(), _xz(target)):
			continue
		_challenge(skater, target)


func _may_call_out(skater: Skater) -> bool:
	return not _challenges.has(skater) and not _carries_puck(skater) \
			and _now() >= float(_cooling_until.get(skater, -INF))


func _challenge(skater: Skater, target: Skater) -> void:
	var c := Challenge.new()
	c.target = target
	c.expires_at = _now() + FightRules.CHALLENGE_WINDOW_S
	_challenges[skater] = c
	skater.fight_role = FightRules.Role.CHALLENGING
	challenge_made.emit(skater, target)
	if _is_bot(target) and (_grudge(target, skater) >= FightGrudgeRules.ACCEPT_LEVEL
			or _hunts != null and _hunts.is_hunting(skater, target)):
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
	a.fight_role = FightRules.Role.FIGHTING
	b.fight_role = FightRules.Role.FIGHTING
	if _hunts != null:
		_hunts.note_fight(a, b)
	if _grudges != null:
		var pa: int = _registry.resolve_peer_id(a)
		var pb: int = _registry.resolve_peer_id(b)
		_grudges.settle(pa, pb)
		_grudges.settle(pb, pa)
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
			if is_instance_valid(key) and (key as Skater).fight_role == FightRules.Role.CHALLENGING:
				(key as Skater).fight_role = FightRules.Role.NONE
			continue
		_cooling_until[key] = now + FightRules.CHALLENGE_COOLDOWN_S
		var challenger: Skater = key as Skater
		if challenger.fight_role == FightRules.Role.CHALLENGING:
			challenger.fight_role = FightRules.Role.NONE
		if _hunts != null:
			_hunts.note_refused(challenger, c.target)
		challenge_lapsed.emit(challenger)


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
		if a.is_knocked_down or b.is_knocked_down:
			_end(a, b)  # put down: that is the fight
			continue
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
	for key: Variant in _partner.keys():
		if is_instance_valid(key):
			(key as Skater).fight_role = FightRules.Role.NONE
	_partner.clear()
	_started_at.clear()
	_apart_s.clear()


# Takes Variants: either man may already be freed.
func _end(a: Variant, b: Variant) -> void:
	for s: Variant in [a, b]:
		if is_instance_valid(s):
			(s as Skater).fight_role = FightRules.Role.NONE
	_partner.erase(a)
	_partner.erase(b)
	_started_at.erase(a)
	_started_at.erase(b)
	_apart_s.erase(a)
	_apart_s.erase(b)


func _grudge(holder: Skater, target: Skater) -> float:
	if _grudges == null:
		return 0.0
	return _grudges.level(_registry.resolve_peer_id(holder), _registry.resolve_peer_id(target), _now())


func _is_bot(skater: Skater) -> bool:
	return _registry.bot_peers.has(_registry.resolve_peer_id(skater))


func _carries_puck(skater: Skater) -> bool:
	return _carrier_getter.is_valid() and _carrier_getter.call() == skater


func _now() -> float:
	return _now_getter.call() if _now_getter.is_valid() else 0.0


static func _xz(skater: Skater) -> Vector2:
	return Vector2(skater.global_position.x, skater.global_position.z)

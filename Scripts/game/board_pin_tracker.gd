class_name BoardPinTracker
extends RefCounted

# Host-only owner of every board pin: which committed checker has driven which
# unbraced opponent into the boards (BoardPinRules), and the only writer of
# Skater.pin_role / pin_strength, which replicate. The caps those fields drive
# are each controller's own, so this decides only when a lock starts and ends.
#
# Onset: a committed, puckless checker in body contact with an opponent, driving
# him square into the boards he is against, who is not braced (holding his own
# commit), not already locked, not down or ghosted, and not inside his immunity.
# A pinned carrier loses the puck at once (it squirts loose at his feet).
#
# The lock ends when the victim's body is no longer lined up with the pinner's
# (BoardPinRules.escaped), when the pinner lets go of the commit, when the bodies
# part, when the victim is off the wall, on a knockdown or a ghost, at the cap, at
# a stoppage, or when the frozen-puck rule squirts the puck (release). Every end
# starts the victim's immunity.

var _registry: PlayerRegistry = null
var _now_getter: Callable = Callable()        # () -> float, host seconds
var _strip_carrier: Callable = Callable()     # (victim: Skater, pinner: Skater) -> void
var _victim_by_pinner: Dictionary = {}        # Skater -> Skater
var _started_at: Dictionary = {}              # pinner Skater -> host seconds
var _immune_until: Dictionary = {}            # victim Skater -> host seconds


func setup(registry: PlayerRegistry, now_getter: Callable, strip_carrier: Callable) -> void:
	_registry = registry
	_now_getter = now_getter
	_strip_carrier = strip_carrier


func tick(live: bool) -> void:
	if _registry == null:
		return
	if not live:
		clear()
		return
	if not _victim_by_pinner.is_empty():
		_hold_or_end()
	for pinner: Skater in _registry.skaters():
		if not _can_pin(pinner):
			continue
		for victim: Skater in _registry.skaters():
			if _onset(pinner, victim):
				_lock(pinner, victim)
				break


# The frozen-puck rule's squirt (and anything else that ends a pin from outside):
# lets go of the lock `skater` is in, either side of it.
func release(skater: Skater) -> void:
	for pinner: Skater in _victim_by_pinner.keys():
		if pinner == skater or _victim_by_pinner[pinner] == skater:
			_end(pinner)
			return


# A stoppage: every lock lets go, with no immunity (play restarts anyway).
func clear() -> void:
	for pinner: Skater in _victim_by_pinner:
		_unlock(pinner, _victim_by_pinner[pinner])
	_victim_by_pinner.clear()
	_started_at.clear()


func victim_of(pinner: Skater) -> Skater:
	return _victim_by_pinner.get(pinner, null)


func _can_pin(pinner: Skater) -> bool:
	return pinner.hit_committed and pinner.pin_role == BoardPinRules.Role.NONE \
			and not SkaterStateMachine.state_has_puck(pinner.current_shot_state) \
			and not pinner.is_knocked_down and not pinner.is_ghost


func _onset(pinner: Skater, victim: Skater) -> bool:
	if victim == pinner or victim.pin_role != BoardPinRules.Role.NONE \
			or victim.is_knocked_down or victim.is_ghost:
		return false
	var p_team: int = _registry.team_id_by_skater.get(pinner, -1)
	var v_team: int = _registry.team_id_by_skater.get(victim, -1)
	if p_team == -1 or v_team == -1 or p_team == v_team:
		return false
	if _now() < _immune_until.get(victim, -INF):
		return false
	var d := Vector2(victim.global_position.x - pinner.global_position.x,
			victim.global_position.z - pinner.global_position.z)
	var touching: float = pinner.collision_radius() + victim.collision_radius() \
			+ BoardPinRules.PIN_CONTACT_SLACK_M
	if d.length_squared() > touching * touching or d.length_squared() < 1e-8:
		return false
	var wall_out: Vector2 = BoardPinRules.wall_normal(victim.global_position,
			victim.collision_radius(), BoardPinRules.PIN_WALL_MARGIN_M)
	return BoardPinRules.pin_holds(true, victim.hit_committed, d.normalized(),
			pinner.velocity, pinner.move_intent, wall_out)


func _lock(pinner: Skater, victim: Skater) -> void:
	var strength: float = BoardPinRules.pin_strength(pinner.weight, victim.weight)
	pinner.pin_role = BoardPinRules.Role.PINNER
	victim.pin_role = BoardPinRules.Role.PINNED
	pinner.pin_strength = strength
	victim.pin_strength = strength
	_victim_by_pinner[pinner] = victim
	_started_at[pinner] = _now()
	if _strip_carrier.is_valid():
		_strip_carrier.call(victim, pinner)


func _hold_or_end() -> void:
	var now: float = _now()
	for pinner: Skater in _victim_by_pinner.keys():
		var victim: Skater = _victim_by_pinner[pinner]
		if not is_instance_valid(pinner) or not is_instance_valid(victim):
			_victim_by_pinner.erase(pinner)
			_started_at.erase(pinner)
			if is_instance_valid(victim):
				victim.pin_role = BoardPinRules.Role.NONE
			if is_instance_valid(pinner):
				pinner.pin_role = BoardPinRules.Role.NONE
			continue
		if not _holds(pinner, victim, now):
			_end(pinner)


func _holds(pinner: Skater, victim: Skater, now: float) -> bool:
	if not pinner.hit_committed or pinner.is_knocked_down or victim.is_knocked_down \
			or pinner.is_ghost or victim.is_ghost:
		return false
	if now - float(_started_at.get(pinner, now)) >= BoardPinRules.PIN_MAX_S:
		return false
	var wall_out: Vector2 = BoardPinRules.wall_normal(victim.global_position,
			victim.collision_radius(), BoardPinRules.PIN_WALL_RELEASE_M)
	if wall_out == Vector2.ZERO:
		return false
	var gap: float = Vector2(victim.global_position.x - pinner.global_position.x,
			victim.global_position.z - pinner.global_position.z).length() \
			- pinner.collision_radius() - victim.collision_radius()
	if gap > BoardPinRules.PIN_SEPARATION_M:
		return false
	return not BoardPinRules.escaped(BoardPinRules.along_wall_offset(
			victim.global_position, pinner.global_position, wall_out))


func _end(pinner: Skater) -> void:
	var victim: Skater = _victim_by_pinner.get(pinner, null)
	_victim_by_pinner.erase(pinner)
	_started_at.erase(pinner)
	_unlock(pinner, victim)
	if victim != null and is_instance_valid(victim):
		_immune_until[victim] = _now() + BoardPinRules.PIN_IMMUNITY_S


static func _unlock(pinner: Skater, victim: Skater) -> void:
	if is_instance_valid(pinner):
		pinner.pin_role = BoardPinRules.Role.NONE
		pinner.pin_strength = 0.0
	if victim != null and is_instance_valid(victim):
		victim.pin_role = BoardPinRules.Role.NONE
		victim.pin_strength = 0.0


func _now() -> float:
	return _now_getter.call() if _now_getter.is_valid() else 0.0

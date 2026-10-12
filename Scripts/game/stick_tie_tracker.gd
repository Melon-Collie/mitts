class_name StickTieTracker
extends RefCounted

# Host-only owner of every stick tie: which defender's TIE-phase stick holds
# which opponent's shaft. The defender's phase is input-driven and knows nothing
# of a target (StickCheckRules); this is where a target is found, held and let
# go, and the only writer of Skater.stick_tied, which replicates.
#
# A tie latches by present-time geometry here, or through a client's lag-comp
# claim (StickTieClaimResolver → try_engage). It holds while the defender stays in
# TIE with the blade inside the hold radius of the victim's shaft, and breaks on
# separation, release, a knockdown, the victim gaining the puck, or a stoppage —
# after which the pair waits out TIE_COOLDOWN_S.

var _registry: PlayerRegistry = null
var _carrier_getter: Callable = Callable()   # () -> Skater (null when loose)
var _now_getter: Callable = Callable()       # () -> float, host seconds
var _hold_radius: float = StickCheckRules.tie_hold_radius(Constants.NETWORK_INTERPOLATION_DELAY)
var _victim_by_defender: Dictionary = {}     # Skater -> Skater
# "defender_id:victim_id" -> host time the pair may tie again. Written only when
# a tie breaks, so the string key costs nothing per tick.
var _cooldown_until: Dictionary = {}


func setup(registry: PlayerRegistry, carrier_getter: Callable, now_getter: Callable) -> void:
	_registry = registry
	_carrier_getter = carrier_getter
	_now_getter = now_getter


func tick(live: bool) -> void:
	if _registry == null:
		return
	if not live:
		clear()
		return
	if not _victim_by_defender.is_empty():
		_hold_or_break()
	for defender: Skater in _registry.skaters():
		if defender.stick_check_phase == StickCheckRules.Phase.TIE \
				and not _victim_by_defender.has(defender):
			var victim: Skater = _nearest_tieable(defender)
			if victim != null:
				_link(defender, victim)


# The claim path's entry. Re-checks the present: the defender still tying and
# free, the victim tieable — the rewound geometry is the resolver's to judge.
func try_engage(defender: Skater, victim: Skater) -> bool:
	if defender.stick_check_phase != StickCheckRules.Phase.TIE \
			or _victim_by_defender.has(defender) or not _tieable(defender, victim):
		return false
	_link(defender, victim)
	return true


func victim_of(defender: Skater) -> Skater:
	return _victim_by_defender.get(defender, null)


func clear() -> void:
	for defender: Skater in _victim_by_defender:
		var victim: Skater = _victim_by_defender[defender]
		if is_instance_valid(victim):
			victim.stick_tied = false
	_victim_by_defender.clear()


func _hold_or_break() -> void:
	var carrier: Skater = _carrier_getter.call() if _carrier_getter.is_valid() else null
	for defender: Skater in _victim_by_defender.keys():
		var victim: Skater = _victim_by_defender[defender]
		if not is_instance_valid(defender) or not is_instance_valid(victim):
			_victim_by_defender.erase(defender)
			if is_instance_valid(victim):
				victim.stick_tied = false
			continue
		var holds: bool = defender.stick_check_phase == StickCheckRules.Phase.TIE \
				and not defender.is_knocked_down and not victim.is_knocked_down \
				and not defender.is_ghost and not victim.is_ghost \
				and victim != carrier \
				and _shaft_distance(defender, victim) <= _hold_radius
		if not holds:
			_break(defender, victim)


func _nearest_tieable(defender: Skater) -> Skater:
	var best: Skater = null
	var best_d: float = StickCheckRules.TIE_ENGAGE_RADIUS_M
	for victim: Skater in _registry.skaters():
		if not _tieable(defender, victim):
			continue
		var d: float = _shaft_distance(defender, victim)
		if d <= best_d:
			best_d = d
			best = victim
	return best


# Geometry is the caller's: an opponent who is not carrying (a carrier's stick is
# lifted, not tied), not already tied, not down or ghosted, and off cooldown.
func _tieable(defender: Skater, victim: Skater) -> bool:
	if victim == defender or victim.stick_tied or victim.is_knocked_down or victim.is_ghost:
		return false
	if defender.is_knocked_down or defender.is_ghost:
		return false
	var d_team: int = _registry.team_id_by_skater.get(defender, -1)
	var v_team: int = _registry.team_id_by_skater.get(victim, -1)
	if d_team == -1 or v_team == -1 or d_team == v_team:
		return false
	var carrier: Skater = _carrier_getter.call() if _carrier_getter.is_valid() else null
	if victim == carrier:
		return false
	var until: float = _cooldown_until.get(_pair_key(defender, victim), -1.0)
	return _now() >= until


func _link(defender: Skater, victim: Skater) -> void:
	_victim_by_defender[defender] = victim
	victim.stick_tied = true


func _break(defender: Skater, victim: Skater) -> void:
	_victim_by_defender.erase(defender)
	victim.stick_tied = false
	_cooldown_until[_pair_key(defender, victim)] = _now() + StickCheckRules.TIE_COOLDOWN_S


func _shaft_distance(defender: Skater, victim: Skater) -> float:
	return PuckInteractionRules.distance_to_shaft(defender.get_blade_contact_global(),
			victim.upper_body_to_global(victim.get_top_hand_position()),
			victim.get_blade_contact_global())


func _pair_key(defender: Skater, victim: Skater) -> String:
	return "%d:%d" % [defender.get_instance_id(), victim.get_instance_id()]


func _now() -> float:
	return _now_getter.call() if _now_getter.is_valid() else 0.0

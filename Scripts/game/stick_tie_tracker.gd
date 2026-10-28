class_name StickTieTracker
extends RefCounted

# Host-only owner of every stick tie: two opponents' sticks tied together, off
# the ice and slowed. A skater's TIE phase is input-driven and knows nothing of a
# target (StickCheckRules); this is where a tie is found, held and let go, and
# the only writer of Skater.stick_tied, which replicates and is set on BOTH
# players.
#
# A tie latches when a skater in TIE, off the shared cooldown, has their stick
# touching a non-carrying opponent's (present-time here, or through a client's
# lag-comp claim, StickTieClaimResolver → try_engage). It holds while either of
# the two holds the stick-check button and the sticks stay within
# TIE_SEPARATION_M, and breaks otherwise, on a knockdown or a ghost, when either
# gains the puck or is in a board pin, or at a stoppage. A break puts both on the shared
# cooldown. Nobody in a pin ties or is tied: the pin is ticked first.

var _registry: PlayerRegistry = null
var _carrier_getter: Callable = Callable()   # () -> Skater (null when loose)
var _partner: Dictionary = {}                # Skater -> Skater, both directions


func setup(registry: PlayerRegistry, carrier_getter: Callable) -> void:
	_registry = registry
	_carrier_getter = carrier_getter


func tick(live: bool) -> void:
	if _registry == null:
		return
	if not live:
		clear()
		return
	if not _partner.is_empty():
		_hold_or_break()
	for skater: Skater in _registry.skaters():
		if _can_initiate(skater):
			var victim: Skater = _nearest_tieable(skater)
			if victim != null:
				_link(skater, victim)


# The claim path's entry. Re-checks the present: the initiator still reaching in
# TIE and free, the victim tieable — the rewound geometry is the resolver's.
func try_engage(initiator: Skater, victim: Skater) -> bool:
	if not _can_initiate(initiator) or not _tieable(initiator, victim):
		return false
	_link(initiator, victim)
	return true


func partner_of(skater: Skater) -> Skater:
	return _partner.get(skater, null)


# A stoppage: every tie lets go, with no cooldown (play restarts anyway). Sweeps
# every skater, not only the pairs held here: the goal replay stamps its recorded
# stick_tied onto the live actors, and a tie it revives is one _partner never saw.
func clear() -> void:
	_partner.clear()
	if _registry == null:
		return
	for skater: Skater in _registry.skaters():
		if is_instance_valid(skater):
			skater.stick_tied = false


func _can_initiate(skater: Skater) -> bool:
	return skater.stick_check_phase == StickCheckRules.Phase.TIE and not skater.stick_tied \
			and not skater.is_stick_check_cooling() and not skater.is_knocked_down \
			and not skater.is_ghost and skater.pin_role == BoardPinRules.Role.NONE


func _hold_or_break() -> void:
	var carrier: Skater = _carrier_getter.call() if _carrier_getter.is_valid() else null
	for a: Skater in _partner.keys():
		if not _partner.has(a):
			continue  # its pair already broke this pass
		var b: Skater = _partner[a]
		if not is_instance_valid(a) or not is_instance_valid(b):
			_drop(a)
			_drop(b)
			continue
		var holds: bool = (a.stick_check_held or b.stick_check_held) \
				and not a.is_knocked_down and not b.is_knocked_down \
				and not a.is_ghost and not b.is_ghost \
				and a.pin_role == BoardPinRules.Role.NONE and b.pin_role == BoardPinRules.Role.NONE \
				and a != carrier and b != carrier \
				and _stick_gap(a, b) <= StickCheckRules.TIE_SEPARATION_M
		if not holds:
			_break(a, b)


func _nearest_tieable(initiator: Skater) -> Skater:
	var best: Skater = null
	var best_d: float = StickCheckRules.TIE_CONTACT_M
	for victim: Skater in _registry.skaters():
		if not _tieable(initiator, victim):
			continue
		var d: float = _stick_gap(initiator, victim)
		if d <= best_d:
			best_d = d
			best = victim
	return best


# Geometry is the caller's: an opponent who is not carrying (a carrier's stick is
# lifted, not tied), not already tied, not in a pin, and not down or ghosted.
func _tieable(initiator: Skater, victim: Skater) -> bool:
	if victim == initiator or victim.stick_tied or victim.is_knocked_down or victim.is_ghost \
			or victim.pin_role != BoardPinRules.Role.NONE:
		return false
	var i_team: int = _registry.team_id_by_skater.get(initiator, -1)
	var v_team: int = _registry.team_id_by_skater.get(victim, -1)
	if i_team == -1 or v_team == -1 or i_team == v_team:
		return false
	var carrier: Skater = _carrier_getter.call() if _carrier_getter.is_valid() else null
	return victim != carrier


func _link(a: Skater, b: Skater) -> void:
	_partner[a] = b
	_partner[b] = a
	a.stick_tied = true
	b.stick_tied = true


func _break(a: Skater, b: Skater) -> void:
	_drop(a)
	_drop(b)
	a.start_stick_check_cooldown()
	b.start_stick_check_cooldown()


func _drop(skater: Skater) -> void:
	_partner.erase(skater)
	if is_instance_valid(skater):
		skater.stick_tied = false


static func _stick_gap(a: Skater, b: Skater) -> float:
	return StickCheckRules.stick_gap(
			a.upper_body_to_global(a.get_top_hand_position()), a.get_blade_contact_global(),
			b.upper_body_to_global(b.get_top_hand_position()), b.get_blade_contact_global())

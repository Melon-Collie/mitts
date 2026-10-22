class_name CrossCheckTracker
extends RefCounted

# Host-only owner of every cross-check landing: a shover in the push
# (CrossCheckRules.can_land, the punch past the load) with an opponent's body on
# his shaft shoves the nearest one along the aim the throw was pressed with, once
# per throw — at
# present time here, or through a client's lag-comp claim
# (CrossCheckClaimResolver → try_land), the first valid one winning. The victim
# answers the push himself (SkaterController.take_cross_check); `landed` carries
# what got through to the feedback broadcast.
#
# Nobody in a board pin, ghosted or down shoves or is shoved. Goalies are not in
# the registry's skaters, so they are never a target.

signal landed(shover: Skater, victim: Skater, dv: float, push_dir: Vector3)

var _registry: PlayerRegistry = null
var _controller_of: Callable = Callable()   # (Skater) -> SkaterController
var _landed: Dictionary = {}                # shover Skater -> his current throw landed
var _was_pushing: Dictionary = {}           # shover Skater -> in the push last tick


func setup(registry: PlayerRegistry, controller_of: Callable) -> void:
	_registry = registry
	_controller_of = controller_of


func tick(live: bool) -> void:
	if _registry == null:
		return
	if not live:
		clear()
		return
	for shover: Skater in _registry.skaters():
		var pushing: bool = CrossCheckRules.can_land(shover.cross_check_phase,
				shover.cross_check_elapsed)
		if pushing and not _was_pushing.get(shover, false):
			_landed[shover] = false
		_was_pushing[shover] = pushing
		if not pushing or _landed.get(shover, true) or not _free(shover):
			continue
		var victim: Skater = _nearest_in_reach(shover)
		if victim != null:
			_land(shover, victim)


# The claim path's entry, after the resolver has checked the rewound geometry:
# re-checks the present — this throw has not landed yet, and both are free
# opponents — and lands it (idempotent with the present-time path).
func try_land(shover: Skater, victim: Skater) -> bool:
	if _landed.get(shover, true) or not _free(shover) or not _shovable(shover, victim):
		return false
	_land(shover, victim)
	return true


# A stoppage: no throw carries over.
func clear() -> void:
	_landed.clear()
	_was_pushing.clear()


static func _free(skater: Skater) -> bool:
	return not skater.is_ghost and not skater.is_knocked_down \
			and skater.pin_role == BoardPinRules.Role.NONE


func _shovable(shover: Skater, victim: Skater) -> bool:
	if victim == shover or not _free(victim):
		return false
	var s_team: int = _registry.team_id_by_skater.get(shover, -1)
	var v_team: int = _registry.team_id_by_skater.get(victim, -1)
	return s_team != -1 and v_team != -1 and s_team != v_team


func _nearest_in_reach(shover: Skater) -> Skater:
	var best: Skater = null
	var best_d: float = INF
	for victim: Skater in _registry.skaters():
		if not _shovable(shover, victim) or not CrossCheckRules.in_reach(shover.global_position,
				shover.cross_check_aim, shover.collision_radius(), victim.global_position,
				victim.collision_radius()):
			continue
		var d: float = shover.global_position.distance_squared_to(victim.global_position)
		if d < best_d:
			best_d = d
			best = victim
	return best


func _land(shover: Skater, victim: Skater) -> void:
	if not _controller_of.is_valid():
		return
	var shover_ctrl: SkaterController = _controller_of.call(shover) as SkaterController
	var victim_ctrl: SkaterController = _controller_of.call(victim) as SkaterController
	if shover_ctrl == null or victim_ctrl == null:
		return
	_landed[shover] = true
	var dir: Vector2 = shover.cross_check_aim
	var dv: float = victim_ctrl.take_cross_check(shover.weight, shover_ctrl.thrust, dir)
	landed.emit(shover, victim, dv, Vector3(dir.x, 0.0, dir.y))

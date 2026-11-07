class_name GameKeeperWorld
extends KeeperWorldSource

# This client's world as a predicted keeper reads it at each host instant he is
# stepped to (KeeperPredictor), from what the client already predicts: a remote
# skater from his buffer's forward prediction (RemoteController.sample_state_at),
# the local one from his prediction history (LocalController.predicted_at); the
# puck on its drawn carrier, as far off his body as it is drawn now, or loose,
# stepped on the shared solver from where this client last knew it loose
# (PuckController.loose_origin, step_loose_tick). It reads the game and writes
# only the shadow puck and skaters it is handed.
#
# Not modelled: a release this client has not heard of, and what the puck's own
# tick does to him (a contact, a catch, a rebound). The next snapshot carries
# those, and re-seeds him.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION

var _pc: PuckController = null
var _registry: PlayerRegistry = null
var _origin := PuckNetworkState.new()
var _origin_t: float = -INF
# The loose puck stepped from `_origin`, and how many ticks.
var _loose_pos := Vector3.ZERO
var _loose_vel := Vector3.ZERO
var _loose_ticks: int = -1
var _tick := PuckAuthorityRules.TickResult.new()
# Whether the last staged tick had the puck carried; a fresh anchor stages its
# first tick without hearing a release (the snapshot's keeper already has).
var _was_carried: bool = false
var _fresh: bool = true


func _init(puck_controller: PuckController, registry: PlayerRegistry) -> void:
	_pc = puck_controller
	_registry = registry


func skater_count() -> int:
	return _registry.skaters().size()


func anchor(_host_t: float) -> void:
	_fresh = true
	_loose_ticks = -1


func stage(host_t: float, puck: KeeperShadowPuck, skaters: Array[KeeperShadowSkater]) -> void:
	var real: Array[Skater] = _registry.skaters()
	var origin_t: float = _pc.loose_origin(host_t, _origin)
	var carried_by: Skater = _pc.drawn_carrier()
	if origin_t == INF:
		var local: PlayerRecord = _registry.get_local()
		carried_by = local.skater if local != null else null
	var carrier: KeeperShadowSkater = null
	for i: int in mini(real.size(), skaters.size()):
		_place_skater(real[i], skaters[i], host_t)
		if real[i] == carried_by:
			carrier = skaters[i]
	puck.carrier = carrier
	if carrier != null:
		puck.global_position = carrier.global_position + (_pc.puck.global_position - carried_by.global_position)
		puck.linear_velocity = carrier.velocity
	else:
		_place_loose(host_t, origin_t, puck)
	puck.pickup_locked = _pc.puck.pickup_locked
	puck.motion_pinned = false
	if _was_carried and carrier == null and not _fresh:
		puck.puck_released.emit()
	_was_carried = carrier != null
	_fresh = false


func _place_skater(real: Skater, s: KeeperShadowSkater, host_t: float) -> void:
	var at: Vector3 = real.global_position
	var vel: Vector3 = real.velocity
	var state: int = real.current_shot_state
	var ghost: bool = real.is_ghost
	var record: PlayerRecord = _registry.get_record(_registry.peer_id_by_skater.get(real, -1) as int)
	var ctrl: SkaterController = record.controller if record != null else null
	if ctrl is RemoteController:
		var sampled: SkaterNetworkState = (ctrl as RemoteController).sample_state_at(host_t)
		if sampled != null:
			at = sampled.position
			vel = sampled.velocity
			state = sampled.shot_state
			ghost = sampled.is_ghost
	elif ctrl is LocalController:
		var predicted: PredictedState = (ctrl as LocalController).predicted_at(host_t)
		if predicted != null:
			at = predicted.position
			vel = predicted.velocity
			state = predicted.shot_state
	s.global_position = at
	s.velocity = vel
	s.current_shot_state = state
	s.is_ghost = ghost
	s.shadow_team = real.get_team_id()
	s.body_collision_radius = real.collision_radius()
	s.shadow_blade = at + (real.get_blade_contact_global() - real.global_position)
	s.blade_world_velocity = real.blade_world_velocity


# The loose puck his tick at `host_t` reads: the one after the tick before,
# stepped from the origin the client has.
func _place_loose(host_t: float, origin_t: float, puck: KeeperShadowPuck) -> void:
	if origin_t == -INF or origin_t == INF:
		puck.global_position = _pc.puck.global_position
		puck.linear_velocity = Vector3.ZERO
		return
	var n: int = 0 if _pc.is_held_for_faceoff(_origin) else maxi(roundi((host_t - DT - origin_t) / DT), 0)
	if origin_t != _origin_t or _loose_ticks < 0 or n < _loose_ticks:
		_origin_t = origin_t
		_loose_ticks = 0
		_loose_pos = _origin.position
		_loose_vel = _origin.velocity
	while _loose_ticks < n:
		_pc.step_loose_tick(_loose_pos, _loose_vel, _tick)
		_loose_pos = _tick.position
		_loose_vel = _tick.velocity
		_loose_ticks += 1
	puck.global_position = _loose_pos
	puck.linear_velocity = _loose_vel

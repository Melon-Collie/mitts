class_name SmartPingCoordinator
extends RefCounted

# The smart ping on one machine: the local key (a preview while it is held,
# the send when it comes up), what a ping off the wire draws and plays for the
# pinger's team, and on the host the election of the bot that obeys.
#
# What a ping says and who obeys is PingRules; what an order does to a bot is
# AIPingDirectives. An elected order leaves here as `bot_ordered`, for the
# owner to hand to the bots.

signal bot_ordered(team_id: int, ping_type: int, pinger_peer_id: int,
		target_peer_id: int, obeyer_peer_id: int, world_pos: Vector3)

# A marker on a skater or the puck stands as long as the words over the pinger.
const _MARKER_HOLD_S: float = 2.4
const _TAP_GAP_S: float = 0.11
# The obeying bot answers a beat after the call, as a man would.
const _ACK_DELAY_S: float = 0.35

var _tree: SceneTree = null
var _registry: PlayerRegistry = null
var _get_puck: Callable = Callable()
# Where the local player's cursor lies on the ice; Vector3.INF when he has
# none to ping with.
var _local_cursor: Callable = Callable()
# Who has the puck (-1 loose) as THIS machine draws it, which is what the
# local player's ping is about; and as the host has it, which is whom an
# order may not conscript.
var _viewed_carrier_peer: Callable = Callable()
var _host_carrier_peer: Callable = Callable()
var _preview: PingPreview = null


func setup(tree: SceneTree, registry: PlayerRegistry, get_puck: Callable,
		local_cursor: Callable, viewed_carrier_peer: Callable,
		host_carrier_peer: Callable) -> void:
	_tree = tree
	_registry = registry
	_get_puck = get_puck
	_local_cursor = local_cursor
	_viewed_carrier_peer = viewed_carrier_peer
	_host_carrier_peer = host_carrier_peer


# The ping key down: the call it would make is previewed until it comes up.
func begin() -> void:
	var scene_root: Node = _tree.current_scene
	if scene_root == null:
		return
	if not is_instance_valid(_preview):
		_preview = PingPreview.new()
		_preview.setup(_resolve_local, _subject_of)
		scene_root.add_child(_preview)
	_preview.open()


# The ping key up. `send` false calls it off (a menu took the screen), and a
# release that no press here began is not a ping.
func end(send: bool) -> void:
	if not is_instance_valid(_preview) or not _preview.is_open():
		return
	_preview.close()
	if not send:
		return
	var res: PingRules.Resolution = _resolve_local()
	if res != null:
		NetworkManager.send_smart_ping(res.type, res.target_peer, res.world_pos)


# A ping off the relay, on every peer. Display is team-only: a ping is a team
# message, and hiding it from the opponents keeps "Pass to me!" from
# telegraphing the play.
func on_received(sender_peer_id: int, ping_type: int, target_peer_id: int,
		world_pos: Vector3) -> void:
	# The payload is the pinger's own: the relay checked its type and nothing else.
	var positions: Dictionary = _skater_positions()
	if not PingRules.is_well_formed(ping_type, target_peer_id, world_pos, positions):
		return
	if ping_type == PingRules.Type.GO_THERE:
		var inside: Vector2 = GameRules.clamp_to_rink_inner(
				Vector2(world_pos.x, world_pos.z))
		world_pos = Vector3(inside.x, 0.0, inside.y)
	var sender_team: int = _registry.team_id_by_peer.get(sender_peer_id, -1)
	if sender_team == -1:
		return  # unknown / spectator sender — nothing to show or obey
	if sender_team == _local_team() and not NetworkManager.is_replay_mode() \
			and _shows_pings_from(sender_peer_id):
		_draw(sender_peer_id, ping_type, target_peer_id, world_pos)
		_play_taps()
	# Bots are the host's, and offline play runs the host's path.
	if NetworkManager.is_host:
		_order_a_bot(sender_team, sender_peer_id, ping_type, target_peer_id,
				world_pos, positions)


# The host's word on which bot took a ping, on every peer.
func on_acknowledged(obeyer_peer_id: int, pinger_peer_id: int) -> void:
	if NetworkManager.is_replay_mode() or not _shows_pings_from(pinger_peer_id):
		return
	var local_team: int = _local_team()
	if local_team == -1 or _registry.team_id_by_peer.get(obeyer_peer_id, -1) != local_team:
		return
	_tree.create_timer(_ACK_DELAY_S).timeout.connect(_answer.bind(obeyer_peer_id))


func _order_a_bot(team_id: int, pinger_peer_id: int, ping_type: int,
		target_peer_id: int, world_pos: Vector3, positions: Dictionary) -> void:
	var bot_peers: Array = []
	var players: Dictionary[int, PlayerRecord] = _registry.all()
	for pid: int in players:
		if players[pid].is_bot and positions.has(pid) \
				and _registry.team_id_by_peer.get(pid, -1) == team_id:
			bot_peers.append(pid)
	var obeyer: int = PingRules.choose_obeyer(
			ping_type, target_peer_id, world_pos, pinger_peer_id,
			_host_carrier_peer.call(), _puck_position(), bot_peers, positions)
	bot_ordered.emit(team_id, ping_type, pinger_peer_id, target_peer_id, obeyer, world_pos)
	if PingRules.acknowledges(ping_type, obeyer):
		NetworkManager.send_smart_ping_ack(obeyer, pinger_peer_id)


# What the local player's ping would say right now, on this machine's view of
# the play; null when he cannot ping or it would say nothing.
func _resolve_local() -> PingRules.Resolution:
	var cursor: Vector3 = _local_cursor.call()
	var rec: PlayerRecord = _registry.get_local()
	if rec == null or not cursor.is_finite():
		return null
	var my_team: int = _registry.team_id_by_peer.get(rec.peer_id, -1)
	if my_team == -1:
		return null
	return PingRules.resolve(cursor, rec.peer_id, my_team, _skater_positions(),
			_registry.team_id_by_peer, _viewed_carrier_peer.call(), _puck_position())


func _subject_of(res: PingRules.Resolution) -> Node3D:
	return _subject(res.type, res.target_peer)


# The skater or puck a ping marks, null when it marks a spot or nothing.
func _subject(ping_type: int, target_peer_id: int) -> Node3D:
	var target_rec: PlayerRecord = _registry.get_record(target_peer_id) \
			if target_peer_id != -1 else null
	if target_rec != null and target_rec.skater != null:
		return target_rec.skater
	if ping_type == PingRules.Type.GET_PUCK:
		return _get_puck.call() as Node3D
	return null


# Every skater a ping can name or order, by peer. One in the penalty box is
# neither: he is out of sight and can obey nothing.
func _skater_positions() -> Dictionary:
	var positions: Dictionary = {}
	var players: Dictionary[int, PlayerRecord] = _registry.all()
	for pid: int in players:
		var r: PlayerRecord = players[pid]
		if r.skater != null and not r.skater.in_box:
			positions[pid] = r.skater.global_position
	return positions


func _puck_position() -> Vector3:
	var puck: Node3D = _get_puck.call() as Node3D
	return puck.global_position if puck != null else Vector3.ZERO


func _local_team() -> int:
	return _registry.team_id_by_peer.get(NetworkManager.local_peer_id(), -1)


func _shows_pings_from(pinger_peer_id: int) -> bool:
	return PlayerPrefs.teammate_pings_enabled \
			or pinger_peer_id == NetworkManager.local_peer_id()


# The words over the pinger, and a marker on what he means: the spot, the
# loose puck, or the skater he named (himself, when he is calling for it).
func _draw(sender_peer_id: int, ping_type: int, target_peer_id: int,
		world_pos: Vector3) -> void:
	var scene_root: Node = _tree.current_scene
	var sender_rec: PlayerRecord = _registry.get_record(sender_peer_id)
	if scene_root == null or sender_rec == null or sender_rec.skater == null:
		return
	var pinger: Skater = sender_rec.skater
	pinger.show_ping_bubble(_translated(PingRules.message_key_for(ping_type)))
	var subject: Node3D = _subject(ping_type, target_peer_id)
	if ping_type == PingRules.Type.GO_THERE:
		scene_root.add_child(PingMarker.at_spot(world_pos, pinger,
				PingRules.directive_duration_s(ping_type)))
	elif subject != null:
		scene_root.add_child(PingMarker.on_node(subject, pinger, _MARKER_HOLD_S))


# A call is heard as a player makes one: two raps of the stick on the ice. On
# the UI pool, so a teammate the length of the rink away is heard as well.
func _play_taps() -> void:
	_tap()
	_tree.create_timer(_TAP_GAP_S).timeout.connect(_tap)


func _tap() -> void:
	SoundManager.play_ui(SoundManager.Sound.STICK_TAP)


# One rap to the call's two.
func _answer(obeyer_peer_id: int) -> void:
	var obeyer: PlayerRecord = _registry.get_record(obeyer_peer_id)
	if obeyer == null or obeyer.skater == null or NetworkManager.is_replay_mode():
		return
	obeyer.skater.show_ping_bubble(_translated(PingRules.ACK_MESSAGE_KEY))
	_tap()


static func _translated(key: String) -> String:
	return String(TranslationServer.translate(key))

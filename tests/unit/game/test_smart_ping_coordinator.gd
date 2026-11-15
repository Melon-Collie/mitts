extends GutTest

# SmartPingCoordinator on real Skater scenes, never ticked: what the local
# player's ping resolves to, which bot the host orders and tells the team
# about, and whose pings a machine shows. Peer 1 is the local player (the
# offline NetworkManager's own id), on team 0 with two bots; peer 2 is the
# opponent.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const ME: int = 1
const OPP: int = 2
const BOT_NEAR: int = 10000
const BOT_FAR: int = 10001
const SPOT := Vector3(6.0, 0.0, -6.0)

var _registry: PlayerRegistry = null
var _pings: SmartPingCoordinator = null
var _cursor: Vector3 = Vector3.INF
var _viewed_carrier: int = -1
var _host_carrier: int = -1
var _orders: Array = []
var _acks: Array = []
var _was_host: bool = false
var _showed_teammate_pings: bool = true


func before_each() -> void:
	_was_host = NetworkManager.is_host
	_showed_teammate_pings = PlayerPrefs.teammate_pings_enabled
	NetworkManager.is_host = true
	_registry = PlayerRegistry.new()
	_add(ME, 0, Vector3(0.0, 0.0, 10.0), false).is_local = true
	_add(OPP, 1, Vector3(-5.0, 0.0, 0.0), false)
	_add(BOT_NEAR, 0, Vector3(5.0, 0.0, -5.0), true)
	_add(BOT_FAR, 0, Vector3(-12.0, 0.0, 12.0), true)
	_cursor = Vector3.INF
	_viewed_carrier = -1
	_host_carrier = -1
	_orders.clear()
	_acks.clear()
	_pings = SmartPingCoordinator.new()
	_pings.setup(get_tree(), _registry, func() -> Node3D: return null,
			func() -> Vector3: return _cursor,
			func() -> int: return _viewed_carrier,
			func() -> int: return _host_carrier)
	_pings.bot_ordered.connect(
			func(team: int, type: int, _pinger: int, _target: int, obeyer: int,
					_pos: Vector3) -> void: _orders.append([team, type, obeyer]))
	NetworkManager.smart_ping_acknowledged.connect(_on_ack)


func after_each() -> void:
	NetworkManager.smart_ping_acknowledged.disconnect(_on_ack)
	NetworkManager.is_host = _was_host
	PlayerPrefs.teammate_pings_enabled = _showed_teammate_pings


func _on_ack(obeyer: int, pinger: int) -> void:
	_acks.append([obeyer, pinger])


func _add(peer_id: int, team_id: int, at: Vector3, is_bot: bool) -> PlayerRecord:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	skater.global_position = at
	var rec := PlayerRecord.new(peer_id, 0, false, null)
	rec.skater = skater
	rec.is_bot = is_bot
	_registry._players[peer_id] = rec
	_registry.team_id_by_peer[peer_id] = team_id
	return rec


# ── The local player's ping ──────────────────────────────────────────────────

func test_the_ping_is_about_the_carrier_this_machine_sees() -> void:
	# A client: the host's carrier reads loose here for the whole match.
	_cursor = _registry.get_record(ME).skater.global_position
	_viewed_carrier = BOT_NEAR
	_host_carrier = -1
	assert_eq(_pings._resolve_local().type, PingRules.Type.PASS_TO_ME)
	_cursor = _registry.get_record(BOT_NEAR).skater.global_position
	assert_eq(_pings._resolve_local().type, PingRules.Type.SHOOT)
	_viewed_carrier = OPP
	_cursor = _registry.get_record(OPP).skater.global_position
	assert_eq(_pings._resolve_local().type, PingRules.Type.PRESSURE_CARRIER)


func test_no_cursor_is_no_ping() -> void:
	_cursor = Vector3.INF
	assert_null(_pings._resolve_local())


func test_a_release_no_press_began_sends_nothing() -> void:
	_cursor = SPOT
	watch_signals(NetworkManager)
	_pings.end(true)
	assert_signal_not_emitted(NetworkManager, "smart_ping_received")


# ── The host's order ─────────────────────────────────────────────────────────

func test_the_nearest_bot_is_ordered_and_says_so() -> void:
	_pings.on_received(ME, PingRules.Type.GO_THERE, -1, SPOT)
	assert_eq(_orders, [[0, PingRules.Type.GO_THERE, BOT_NEAR]])
	assert_eq(_acks, [[BOT_NEAR, ME]])


func test_a_bot_in_the_box_is_not_conscripted() -> void:
	_registry.get_record(BOT_NEAR).skater.in_box = true
	_pings.on_received(ME, PingRules.Type.GO_THERE, -1, SPOT)
	assert_eq(_orders, [[0, PingRules.Type.GO_THERE, BOT_FAR]])


func test_the_bot_with_the_puck_is_not_conscripted() -> void:
	_host_carrier = BOT_NEAR
	_pings.on_received(ME, PingRules.Type.GO_THERE, -1, SPOT)
	assert_eq(_orders, [[0, PingRules.Type.GO_THERE, BOT_FAR]])


func test_a_shot_call_is_ordered_but_not_answered() -> void:
	_host_carrier = BOT_NEAR
	_pings.on_received(ME, PingRules.Type.SHOOT, BOT_NEAR, Vector3.ZERO)
	assert_eq(_orders, [[0, PingRules.Type.SHOOT, BOT_NEAR]])
	assert_eq(_acks, [], "his own read can still refuse it")


func test_a_payload_naming_nobody_real_is_dropped() -> void:
	_pings.on_received(ME, PingRules.Type.COVER_HIM, 999, Vector3.ZERO)
	_pings.on_received(ME, PingRules.Type.GO_THERE, -1, Vector3(NAN, 0.0, 0.0))
	_pings.on_received(77, PingRules.Type.GO_THERE, -1, SPOT)
	assert_eq(_orders, [], "a missing target, no position, a sender on no team")


func test_a_spot_outside_the_boards_is_ordered_inside_them() -> void:
	var seen: Array[Vector3] = []
	_pings.bot_ordered.connect(
			func(_t: int, _ty: int, _p: int, _tg: int, _o: int, pos: Vector3) -> void:
				seen.append(pos))
	_pings.on_received(ME, PingRules.Type.GO_THERE, -1, Vector3(500.0, 0.0, 0.0))
	assert_eq(seen.size(), 1)
	assert_lt(seen[0].x, GameRules.INNER_HALF_WIDTH + 0.01)


func test_a_client_orders_no_bots() -> void:
	NetworkManager.is_host = false
	_pings.on_received(ME, PingRules.Type.GO_THERE, -1, SPOT)
	assert_eq(_orders, [])
	assert_eq(_acks, [])


# ── Whose pings this machine shows ───────────────────────────────────────────

func test_the_toggle_hides_other_players_pings_and_never_ones_own() -> void:
	assert_true(_pings._shows_pings_from(OPP))
	PlayerPrefs.teammate_pings_enabled = false
	assert_false(_pings._shows_pings_from(BOT_NEAR))
	assert_true(_pings._shows_pings_from(ME))

extends GutTest

# LobbyBench: a client seats each peer in the look the host relayed, and the
# benches list every fielded slot — humans and bots — in slot order.

var _bench: LobbyBench = null
var _was_host: bool = false
var _bot_slots: Dictionary = {}
var _bot_identities: Dictionary[int, Dictionary] = {}


func before_each() -> void:
	_bench = LobbyBench.new()
	_was_host = NetworkManager.is_host
	_bot_slots = NetworkManager.pending_bot_slots.duplicate()
	_bot_identities = NetworkManager.pending_bot_identities.duplicate()
	NetworkManager.is_host = false
	NetworkManager.pending_bot_slots.clear()
	NetworkManager.pending_bot_identities.clear()


func after_each() -> void:
	NetworkManager.is_host = _was_host
	NetworkManager.pending_bot_slots = _bot_slots
	NetworkManager.pending_bot_identities = _bot_identities


func _slot(peer_id: int, p_name: String, number: int) -> Dictionary:
	return {"peer_id": peer_id, "player_name": p_name, "is_left_handed": true,
		"jersey_number": number}


func test_a_client_seats_each_peer_in_the_relayed_look() -> void:
	var sent := PlayerLook.new()
	sent.skin_tone = 4
	sent.gear_style_code = GearStyleConfig.from_code(31337).to_code()
	_bench.remember([42, 0, 2, "Ada", true, 9, false] + sent.cosmetics_to_wire())
	var look: PlayerLook = _bench.look_for(_slot(42, "Ada", 9))
	assert_eq(look.player_name, "Ada")
	assert_eq(look.jersey_number, 9)
	assert_eq(look.skin_tone, 4)
	assert_eq(look.gear_style_code, sent.gear_style_code)


func test_benches_seat_humans_and_bots_in_slot_order() -> void:
	var slots: Dictionary = {
		LobbySlotKey.encode(0, 2): _slot(11, "Third", 3),
		LobbySlotKey.encode(0, 0): _slot(10, "First", 1),
		LobbySlotKey.encode(1, 0): _slot(12, "Away", 5),
		LobbySlotKey.encode(GameRules.SPECTATOR_TEAM_ID, 0): _slot(13, "Watcher", 7),
	}
	var bot_key: int = LobbySlotKey.encode(0, 1)
	NetworkManager.pending_bot_slots[bot_key] = true
	NetworkManager.pending_bot_identities[bot_key] = {"name": "Botty", "number": 88}
	var benches: Array = _bench.benches(slots, 3)
	var home: Array[String] = []
	for look: PlayerLook in benches[0]:
		home.append(look.player_name)
	assert_eq(home, ["First", "Botty", "Third"] as Array[String])
	assert_eq((benches[1] as Array).size(), 1, "spectators don't sit on a bench")


# 3v3 never fields the D slots, so they don't sit either.
func test_slots_past_the_team_size_stay_off_the_bench() -> void:
	var slots: Dictionary = {
		LobbySlotKey.encode(0, 0): _slot(10, "Forward", 1),
		LobbySlotKey.encode(0, 4): _slot(11, "Defense", 2),
	}
	assert_eq((_bench.benches(slots, 3)[0] as Array).size(), 1)
